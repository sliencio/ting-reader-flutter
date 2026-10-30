import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/api/api_error.dart';
import '../../core/models/models.dart';
import '../../core/utils/locale.dart';
import '../../shared/app_scope.dart';
import '../../shared/common/common_widgets.dart';

class ServerMaintenancePage extends StatefulWidget {
  const ServerMaintenancePage({super.key});
  @override
  State<ServerMaintenancePage> createState() => _ServerMaintenancePageState();
}

class _ServerMaintenancePageState extends State<ServerMaintenancePage> {
  Map<String, dynamic>? _settings;
  Map<String, dynamic> _backups = {};
  Map<String, dynamic>? _report;
  List<Map<String, dynamic>> _libraries = [];
  final Map<String, String> _libraryReports = {};
  final Map<String, TextEditingController> _fields = {};
  bool _busy = false;
  String? _message;
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run(_load);
    });
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final app = AppScope.appOf(context);
    if (!app.isAdmin || app.offlineMode) return;
    final api = app.api;
    final values = await Future.wait([
      api.get('/api/system/maintenance'),
      api.get('/api/system/backups'),
      api.get('/api/libraries')
    ]);
    if (!mounted) return;
    setState(() {
      _settings = asMap(values[0].data);
      _backups = asMap(values[1].data);
      _libraries = asMapList(values[2].data);
      for (final entry in _settings!.entries) {
        if (entry.value is! num && entry.value != null) continue;
        _fields.putIfAbsent(entry.key, () => TextEditingController()).text =
            entry.value?.toString() ?? '';
      }
    });
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted && success != null) setState(() => _message = success);
    } catch (error) {
      if (mounted) setState(() => _message = ApiError.messageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final values = Map<String, dynamic>.of(_settings!);
    for (final entry in _fields.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty && entry.key == 'disk_cache_mib') {
        values[entry.key] = null;
        continue;
      }
      final number = int.tryParse(text);
      if (number == null) {
        throw StateError(
            context.localeText('请输入有效整数', 'Please enter a valid integer'));
      }
      values[entry.key] = number;
    }
    await AppScope.appOf(context)
        .api
        .put('/api/system/maintenance', data: values);
    await _load();
  }

  Widget _number(String key, String cn, String en, String range) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: _fields.putIfAbsent(key, () => TextEditingController()),
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          decoration: InputDecoration(
              labelText: context.localeText(cn, en),
              helperText: range,
              border: const OutlineInputBorder()),
        ),
      );
  Widget _button(String cn, String en, VoidCallback? action,
          {IconData? icon}) =>
      OutlinedButton.icon(
        onPressed: _busy ? null : action,
        icon: Icon(icon ?? Icons.chevron_right_rounded, size: 18),
        label: Text(context.localeText(cn, en)),
      );
  String _size(Object? bytes) =>
      '${(((bytes as num?)?.toDouble() ?? 0) / 1024 / 1024).toStringAsFixed(1)} MiB';

  Future<void> _import() async {
    final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'sqlite', 'sqlite3'],
        withReadStream: true);
    if (!mounted || picked == null) return;
    final file = picked.files.single;
    if (file.size > 512 * 1024 * 1024) {
      throw StateError(context.localeText(
          '备份不能超过 512 MiB', 'Backup must not exceed 512 MiB'));
    }
    final stream = file.readStream;
    if (stream == null) {
      throw StateError(
          context.localeText('无法读取备份文件', 'Cannot read the backup file'));
    }
    bool consumed = false;
    final data = FormData.fromMap({
      'backup': MultipartFile.fromStream(() {
        if (!kIsWeb && file.path != null) return file.xFile.openRead();
        if (consumed) throw StateError('上传会话已更新，请重新选择备份文件');
        consumed = true;
        return stream;
      }, file.size, filename: 'backup.db')
    });
    await AppScope.appOf(context).api.post('/api/system/backups/import',
        data: data, receiveTimeout: const Duration(minutes: 2));
    await _load();
  }

  Future<void> _download(Map<String, dynamic> file) async {
    if ((file['bytes'] as num? ?? 0) > 64 * 1024 * 1024) {
      throw StateError(context.localeText(
          '备份超过 64 MiB，请在服务端 Web 页面下载，避免占用过多客户端内存',
          'For backups over 64 MiB, use the server web page to avoid high memory usage'));
    }
    final name = file['name'].toString();
    final response = await AppScope.appOf(context)
        .api
        .getBytes('/api/system/backups/${Uri.encodeComponent(name)}');
    if (!mounted) return;
    final bytes = Uint8List.fromList((response.data as List).cast<int>());
    await FilePicker.platform.saveFile(
        dialogTitle: context.localeText('保存数据库备份', 'Save database backup'),
        fileName: name,
        bytes: bytes);
  }

  Future<void> _restore(Map<String, dynamic> file) async {
    final accepted = await showDialog<bool>(
        context: context,
        builder: (_) =>
            _RestoreConfirmationDialog(name: file['name'].toString()));
    if (!mounted || accepted != true) return;
    await _run(() async {
      await AppScope.appOf(context).api.post(
          '/api/system/backups/${Uri.encodeComponent(file['name'].toString())}/restore',
          data: {'confirmation': '恢复备份'});
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.appOf(context);
    if (app.offlineMode) {
      return Center(
          child: Text(context.localeText('离线模式下无法管理服务端',
              'Server maintenance is unavailable in offline mode')));
    }
    if (!app.isAdmin) {
      return Center(
          child: Text(context.localeText('仅管理员可管理服务端',
              'Server administration requires an administrator')));
    }
    return PageListView(children: [
      HeaderText(
          title: context.localeText('服务端维护', 'Server maintenance'),
          subtitle: context.localeText(
              '备份恢复、预加载缓存与故障诊断', 'Backups, preloading and diagnostics')),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final entry in [
          (0, '备份恢复', 'Backups'),
          (1, '预加载与缓存', 'Cache'),
          (2, '故障诊断', 'Diagnostics')
        ])
          ChoiceChip(
              label: Text(context.localeText(entry.$2, entry.$3)),
              selected: _tab == entry.$1,
              onSelected: (_) => setState(() => _tab = entry.$1)),
        _button('刷新', 'Refresh', () => _run(_load), icon: Icons.refresh),
      ]),
      if (_busy)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: LinearProgressIndicator()),
      if (_message != null)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SelectableText(_message!)),
      if (_settings == null)
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(context.localeText('加载失败时请先升级服务端，再点击刷新。',
                'If loading fails, upgrade the server and refresh.'))),
      if (_settings != null) ...[
        const SizedBox(height: 20),
        if (_tab == 0) ...[
          Text(context.localeText(
              '备份包含账号、阅读状态和数据库内设置，不包含音频及外部配置。跨机器或变更数据库路径恢复后，可能需重新填写 WebDAV、插件凭据。自动清理仅处理自动备份。',
              'Backups include accounts, reading state and database settings, excluding audio and external configuration. Restoring to a different machine or database path may require entering WebDAV and plugin credentials again. Retention applies only to automatic backups.')),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.localeText('定时备份', 'Automatic backups')),
              value: _settings!['automatic_backup'] == true,
              onChanged: _busy
                  ? null
                  : (value) =>
                      setState(() => _settings!['automatic_backup'] = value)),
          _number('backup_interval_hours', '备份间隔（小时）',
              'Backup interval (hours)', '1–168'),
          _number('backup_retention', '自动备份保留份数', 'Automatic backups to keep',
              '1–60'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _button(
                '保存设置',
                'Save settings',
                () => _run(_save,
                    success: context.localeText('设置已保存', 'Settings saved')),
                icon: Icons.save_outlined),
            _button(
                '立即备份',
                'Back up now',
                () => _run(() async {
                      await app.api.post('/api/system/backups',
                          receiveTimeout: const Duration(minutes: 2));
                      await _load();
                    }),
                icon: Icons.backup_outlined),
            _button('导入备份', 'Import backup', () => _run(_import),
                icon: Icons.file_upload_outlined),
          ]),
          if (_backups['pending_restore'] == true)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.localeText('已暂存恢复请求，请重启服务端应用。恢复后可能需要重新登录。',
                          'A restore is staged. Restart the server to apply it. You may need to sign in again.')),
                      _button(
                          '取消待恢复请求',
                          'Cancel staged restore',
                          () => _run(() async {
                                await app.api.delete(
                                    '/api/system/backups/pending-restore');
                                await _load();
                              })),
                    ])),
          if (_backups['last_error'] != null)
            Text(
                '${context.localeText('最近自动备份失败：', 'Last automatic backup failed: ')}${_backups['last_error']}'),
          const SizedBox(height: 16),
          for (final file in asMapList(_backups['files']))
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(file['name'].toString()),
                          const SizedBox(height: 6),
                          Text(
                              '${_size(file['bytes'])} · ${file['created_at']}'),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            _button('下载', 'Download',
                                () => _run(() => _download(file)),
                                icon: Icons.download_outlined),
                            _button(
                                '恢复',
                                'Restore',
                                _backups['pending_restore'] == true
                                    ? null
                                    : () => _restore(file),
                                icon: Icons.restore),
                            _button(
                                '删除',
                                'Delete',
                                () => _run(() async {
                                      final confirmed = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                                  title: Text(context.localeText(
                                                      '删除这个备份？',
                                                      'Delete this backup?')),
                                                  content: Text(
                                                      file['name'].toString()),
                                                  actions: [
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                ctx, false),
                                                        child: Text(context.l10n
                                                            .commonCancel)),
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                ctx, true),
                                                        child: Text(
                                                            context.localeText(
                                                                '删除',
                                                                'Delete')))
                                                  ]));
                                      if (confirmed == true) {
                                        await app.api.delete(
                                            '/api/system/backups/${Uri.encodeComponent(file['name'].toString())}');
                                        await _load();
                                      }
                                    }),
                                icon: Icons.delete_outline),
                          ]),
                        ]))),
        ],
        if (_tab == 1) ...[
          Text(context.localeText('这些设置影响服务端缓存，与本机下载独立；自动预加载开关继续使用账号的播放设置。',
              'These settings control server caches separately from device downloads. Automatic preloading follows the account playback settings.')),
          const SizedBox(height: 18),
          _number('preload_window_mib', '每章预加载大小（MiB）',
              'Preload per chapter (MiB)', '1–16'),
          _number('preload_memory_mib', '预加载内存上限（MiB）',
              'Preload memory limit (MiB)', '4–256'),
          _number('preload_idle_seconds', '预加载空闲有效期（秒）',
              'Preload idle timeout (seconds)', '5–3600'),
          _number('disk_cache_chapters', '磁盘缓存章节上限', 'Disk cache chapter limit',
              '1–500'),
          _number(
              'disk_cache_mib',
              '磁盘缓存上限（MiB，留空沿用原配置）',
              'Disk cache limit (MiB; blank keeps original setting)',
              '64–65536'),
          _button(
              '保存设置',
              'Save settings',
              () => _run(_save,
                  success: context.localeText('设置已保存', 'Settings saved')),
              icon: Icons.save_outlined),
        ],
        if (_tab == 2) ...[
          _button(
              '运行服务端检查',
              'Check server',
              () => _run(() async {
                    final response =
                        await app.api.get('/api/system/diagnostics');
                    if (mounted) setState(() => _report = asMap(response.data));
                  }),
              icon: Icons.fact_check_outlined),
          if (_report != null)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${context.localeText('数据库响应', 'Database response')}: ${_report!['database_ms']} ms'),
                          for (final item in asMapList(_report!['directories']))
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                    '${item['name']}: ${item['writable'] == true ? context.localeText('可写', 'Writable') : context.localeText('不可写', 'Not writable')}${item['free_bytes'] == null ? '' : ' · ${_size(item['free_bytes'])}'}${item['error'] == null ? '' : ' · ${item['error']}'}')),
                          for (final item in asMapList(_report!['tools']))
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: SelectableText(
                                    '${item['name']}: ${item['version'] ?? item['error']}')),
                          const SizedBox(height: 8),
                          Text(
                              '${context.localeText('磁盘缓存', 'Disk cache')}: ${_size(asMap(_report!['cache'])['disk_bytes'])}'),
                          Text(
                              '${context.localeText('预加载内存', 'Preload memory')}: ${_size(asMap(asMap(_report!['cache'])['memory'])['bytes'])}'),
                          Text(
                              '${context.localeText('命中 / 未命中', 'Hits / misses')}: ${asMap(asMap(_report!['cache'])['memory'])['hits']} / ${asMap(asMap(_report!['cache'])['memory'])['misses']}'),
                        ]))),
          for (final library in _libraries)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(library['name'].toString()),
                          _button(
                              '检查连接及抽样章节',
                              'Check connection and sample chapter',
                              () => _run(() async {
                                    final response = await app.api.post(
                                        '/api/system/diagnostics/libraries/${Uri.encodeComponent(library['id'].toString())}');
                                    final data = asMap(response.data);
                                    if (mounted) {
                                      setState(() => _libraryReports[
                                              library['id'].toString()] =
                                          '${data['error'] ?? asMap(data['result'])['message']} (${data['elapsed_ms']} ms)');
                                    }
                                  })),
                          if (_libraryReports.containsKey(library['id']))
                            SelectableText(_libraryReports[library['id']]!),
                        ]))),
        ],
      ],
    ]);
  }
}

class _RestoreConfirmationDialog extends StatefulWidget {
  const _RestoreConfirmationDialog({required this.name});
  final String name;
  @override
  State<_RestoreConfirmationDialog> createState() =>
      _RestoreConfirmationDialogState();
}

class _RestoreConfirmationDialogState
    extends State<_RestoreConfirmationDialog> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _input,
        builder: (context, value, _) => AlertDialog(
          title: Text(context.localeText('暂存恢复请求', 'Stage database restore')),
          content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(context.localeText(
                    '重启服务端后恢复账号、进度与配置，不替换音频文件。恢复前会先备份当前数据库，重启前可取消。',
                    'After restarting the server, accounts, progress and settings will be restored. Audio files are kept. The current database is backed up first. You can cancel before restarting.')),
                const SizedBox(height: 12),
                SelectableText(widget.name),
                const SizedBox(height: 16),
                TextField(
                    controller: _input,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: InputDecoration(
                        labelText:
                            context.localeText('请输入“恢复备份”', 'Enter 恢复备份'),
                        border: const OutlineInputBorder())),
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.commonCancel)),
            TextButton(
                onPressed: value.text == '恢复备份'
                    ? () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.pop(context, true);
                      }
                    : null,
                child: Text(context.localeText('确认暂存', 'Confirm'))),
          ],
        ),
      );
}
