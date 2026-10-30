import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/models/models.dart';
import '../../core/services/client_update_service.dart';
import '../../core/utils/external_links.dart';
import '../../core/utils/locale.dart';
import '../../shared/app_scope.dart';
import '../../shared/common/common_widgets.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({
    super.key,
    required this.backendVersion,
    required this.onBack,
    this.onForceRefresh,
    this.updateService,
    this.openLink = openExternalUrl,
  });

  final String? backendVersion;
  final VoidCallback onBack;
  final Future<void> Function()? onForceRefresh;
  final ClientUpdateService? updateService;
  final Future<bool> Function(String) openLink;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final _clientUpdateService =
      widget.updateService ?? ClientUpdateService();
  String? _backendVersion;
  String? _backendError;
  String? _clientError;
  String _clientVersion = '';
  bool _loadingBackend = false;
  bool _refreshingData = false;
  bool _checkingBackend = false;
  bool _checkingClient = false;
  bool _downloadingClient = false;
  double _clientDownloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _backendVersion = widget.backendVersion;
    _loadClientVersion();
    if ((_backendVersion ?? '').trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadBackendVersion();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AboutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.backendVersion ?? '').trim().isNotEmpty) {
      _backendVersion = widget.backendVersion;
    }
  }

  @override
  void dispose() {
    _clientUpdateService.dispose();
    super.dispose();
  }

  Future<void> _loadBackendVersion() async {
    if (_loadingBackend) return;
    setState(() {
      _loadingBackend = true;
      _backendError = null;
    });
    try {
      final res = await AppScope.appOf(context).api.get('/api/health');
      final version = asMap(res.data)['version']?.toString().trim() ?? '';
      if (version.isEmpty) throw const FormatException('服务端没有返回版本号');
      if (mounted) setState(() => _backendVersion = version);
    } catch (error) {
      if (mounted) setState(() => _backendError = ApiError.messageFor(error));
    } finally {
      if (mounted) setState(() => _loadingBackend = false);
    }
  }

  Future<void> _loadClientVersion() async {
    try {
      final version = await _clientUpdateService.currentVersionLabel();
      if (mounted) setState(() => _clientVersion = version);
    } catch (_) {
      // 版本读取失败时仍保留项目链接和手动下载入口。
    }
  }

  Future<void> _refreshData() async {
    final refresh = widget.onForceRefresh;
    if (refresh == null || _refreshingData) return;
    setState(() => _refreshingData = true);
    try {
      await refresh();
    } catch (error) {
      if (mounted) _showSnack(ApiError.messageFor(error));
    } finally {
      if (mounted) setState(() => _refreshingData = false);
    }
  }

  Future<void> _checkBackendUpdate() async {
    if (_checkingBackend || _loadingBackend) return;
    final language = Localizations.localeOf(context).languageCode;
    setState(() => _checkingBackend = true);
    try {
      if ((_backendVersion ?? '').isEmpty) await _loadBackendVersion();
      if (!mounted) return;
      if ((_backendVersion ?? '').isEmpty) {
        throw StateError(_backendError ?? '无法获取当前服务端版本');
      }
      final res =
          await AppScope.appOf(context).api.get('/api/system/check-update');
      final data = asMap(res.data);
      final remote = data['version']?.toString().trim() ?? '';
      if (remote.isEmpty) throw const FormatException('服务端没有返回更新信息');
      if (!mounted) return;
      if (_clientUpdateService.isNewer(remote, _backendVersion!)) {
        final open = await _showUpdateDialog(
          title: context.localeText(
              '发现服务端新版本 ${_versionLabel(context, remote)}',
              'Server update ${_versionLabel(context, remote)} available'),
          date: (data['date'] ?? data['published_at'])?.toString() ?? '',
          actionLabel: context.localeText('查看更新指南', 'Update guide'),
        );
        if (mounted && open == true) {
          await _openLink(localizedServerUpdateGuideUrl(language));
        }
      } else {
        _showSnack(context.localeText('服务端已是最新版本', 'Server is up to date'));
      }
    } catch (error) {
      if (mounted) {
        _showSnack(
            context.localeText('检查服务端更新失败：', 'Server update check failed: ') +
                ApiError.messageFor(error));
      }
    } finally {
      if (mounted) setState(() => _checkingBackend = false);
    }
  }

  Future<void> _checkClientUpdate() async {
    if (_checkingClient) return;
    setState(() {
      _checkingClient = true;
      _clientError = null;
    });
    try {
      final latest = await _clientUpdateService.fetchLatest();
      if (!mounted) return;
      if (latest == null) {
        setState(() => _clientError = context.localeText(
            '仓库暂未发布正式版本，可以前往 Releases 查看。',
            'No stable release is available. You can visit Releases.'));
        return;
      }
      final current = await _clientUpdateService.currentVersion();
      if (!mounted) return;
      if (!_clientUpdateService.isNewer(latest.version, current)) {
        _showSnack(context.localeText('客户端已是最新版本', 'Client is up to date'));
        return;
      }
      final direct =
          latest.hasDownload && _clientUpdateService.canInstallDirectly;
      final confirm = await _showUpdateDialog(
        title: context.localeText('发现客户端新版本 v${latest.version}',
            'Client update v${latest.version} available'),
        date: latest.date,
        notes: latest.notes,
        message: latest.hasDownload
            ? context.localeText(
                '更新来源：$clientRepository', 'Release source: $clientRepository')
            : context.localeText('请前往版本页查看安装包与说明。',
                'Visit the release page for packages and installation notes.'),
        actionLabel: direct
            ? context.localeText('下载安装', 'Download')
            : context.localeText('查看版本页', 'View release'),
      );
      if (!mounted || confirm != true) return;
      if (!direct) {
        await _openLink(latest.pageUrl);
        return;
      }
      setState(() {
        _downloadingClient = true;
        _clientDownloadProgress = 0;
      });
      await _clientUpdateService.openOrInstall(latest, onProgress: (progress) {
        if (mounted) {
          setState(
              () => _clientDownloadProgress = progress.clamp(0, 1).toDouble());
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _clientError = context.localeText(
                '检查或下载失败，可重试或前往 Releases 手动下载。\n',
                'Check or download failed. Retry or download from Releases.\n') +
            ApiError.messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _checkingClient = false;
          _downloadingClient = false;
        });
      }
    }
  }

  Future<void> _openLink(String url) async {
    try {
      if (!await widget.openLink(url) && mounted) {
        _showSnack(context.localeText('无法打开链接：$url', 'Unable to open: $url'));
      }
    } catch (error) {
      if (mounted) _showSnack(ApiError.messageFor(error));
    }
  }

  Future<bool?> _showUpdateDialog({
    required String title,
    required String date,
    required String actionLabel,
    String notes = '',
    String message = '',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        constraints: const BoxConstraints(maxWidth: 520),
        title: Text(title),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (date.isNotEmpty) Text(_dateOnly(date)),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(message),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              SelectableText(notes),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.localeText('暂不更新', 'Later')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(actionLabel, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return PageListView(
      onRefresh: _loadBackendVersion,
      children: [
        AppBackButton(onPressed: widget.onBack),
        const SizedBox(height: 16),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TingCard(
                  child: Column(children: [
                    Image.asset('assets/images/logo.png',
                        width: 64, height: 64),
                    const SizedBox(height: 12),
                    Text(
                        context.localeText(
                            '关于 Ting Reader', 'About Ting Reader'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      context.localeText('基于开源项目改进的听悦客户端',
                          'An improved client based on the open source Ting Reader project'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    _AboutVersionRow(
                      label: context.localeText('客户端版本', 'Client version'),
                      version: _clientVersion.isEmpty
                          ? context.localeText('未知', 'Unknown')
                          : _clientVersion,
                      checking: _checkingClient,
                      onCheckUpdate: _checkClientUpdate,
                    ),
                    if (_downloadingClient) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                          value: _clientDownloadProgress <= 0
                              ? null
                              : _clientDownloadProgress),
                      const SizedBox(height: 8),
                      Text(_clientDownloadProgress <= 0
                          ? context.localeText('准备下载…', 'Preparing download…')
                          : '${(_clientDownloadProgress * 100).round()}%'),
                    ],
                    if (_clientError != null) ...[
                      const SizedBox(height: 12),
                      Text(_clientError!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                      TextButton(
                        onPressed: () => _openLink(clientReleasesUrl),
                        child: Text(
                            context.localeText('前往 Releases', 'Open Releases')),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _AboutVersionRow(
                      label: context.localeText('服务端版本', 'Server version'),
                      version: _loadingBackend
                          ? context.localeText('加载中…', 'Loading…')
                          : _versionLabel(context, _backendVersion ?? ''),
                      checking: _checkingBackend || _loadingBackend,
                      onCheckUpdate: _checkBackendUpdate,
                    ),
                    if (_backendError != null) ...[
                      const SizedBox(height: 8),
                      Text(context.localeText('服务端版本暂不可用，下拉重试。',
                          'Server version unavailable. Pull down to retry.')),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
                TingCard(
                  child: Column(children: [
                    _link(
                        Icons.code_rounded,
                        context.localeText('项目主页', 'Project repository'),
                        clientRepository,
                        clientRepositoryUrl),
                    _link(
                        Icons.history_rounded,
                        context.localeText('更新日志', 'Changelog'),
                        context.localeText(
                            '本仓库的版本说明与下载', 'Release notes and downloads'),
                        localizedChangelogUrl(language)),
                    _link(
                        Icons.bug_report_outlined,
                        context.localeText('问题反馈', 'Report an issue'),
                        context.localeText(
                            '在本仓库提交问题', 'Issues in this repository'),
                        '$clientRepositoryUrl/issues'),
                    _link(
                        Icons.description_outlined,
                        context.localeText('开源许可', 'Open source license'),
                        'AGPL-3.0',
                        '$clientRepositoryUrl/blob/main/LICENSE'),
                  ]),
                ),
                const SizedBox(height: 16),
                TingCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.localeText('致谢', 'Acknowledgements'),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(context.localeText(
                          '本项目基于 dqsq2e2/ting-reader-flutter 改进。感谢原作者和社区贡献者的开源工作。',
                          'Based on dqsq2e2/ting-reader-flutter. Thanks to the original author and community contributors.')),
                      _link(
                          Icons.favorite_outline_rounded,
                          context.localeText(
                              '原客户端仓库', 'Original client repository'),
                          'dqsq2e2/ting-reader-flutter',
                          upstreamClientRepositoryUrl),
                    ],
                  ),
                ),
                if (widget.onForceRefresh != null) ...[
                  const SizedBox(height: 16),
                  TingCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(context.localeText('数据刷新', 'Refresh data'),
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(context.localeText('重新加载书籍信息和封面，已下载的音频会保留。',
                            'Reload book details and covers. Downloaded audio is kept.')),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _refreshingData ? null : _refreshData,
                          icon: const Icon(Icons.sync_rounded),
                          label: Text(_refreshingData
                              ? context.localeText('刷新中…', 'Refreshing…')
                              : context.localeText('强制刷新', 'Force refresh')),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _link(IconData icon, String title, String subtitle, String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openLink(url),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(icon, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _AboutVersionRow extends StatelessWidget {
  const _AboutVersionRow({
    required this.label,
    required this.version,
    required this.checking,
    required this.onCheckUpdate,
  });

  final String label;
  final String version;
  final bool checking;
  final VoidCallback onCheckUpdate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 400 ||
          MediaQuery.textScalerOf(context).scale(14) > 18;
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(version, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );
      final button = TextButton(
        onPressed: checking ? null : onCheckUpdate,
        child: Text(checking
            ? context.localeText('检查中…', 'Checking…')
            : context.localeText('检查更新', 'Check for updates')),
      );
      return narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              details,
              Align(alignment: Alignment.centerRight, child: button),
            ])
          : Row(children: [Expanded(child: details), button]);
    });
  }
}

String _versionLabel(BuildContext context, String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.toLowerCase() == 'unknown') {
    return context.localeText('未知', 'Unknown');
  }
  return value.toLowerCase().startsWith('v') ? value : 'v$value';
}

String _dateOnly(String raw) => raw.trim().split('T').first;
