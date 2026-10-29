import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/external_links.dart';

class ClientReleaseInfo {
  const ClientReleaseInfo({
    required this.version,
    required this.downloadUrl,
    required this.size,
    required this.date,
    this.notes = '',
    this.pageUrl = clientReleasesUrl,
  });

  factory ClientReleaseInfo.fromGitHub(
      Map<String, dynamic> json, TargetPlatform? platform) {
    final tag = json['tag_name']?.toString().trim() ?? '';
    final assetName = switch (platform) {
      TargetPlatform.android => 'ting-reader-flutter-android.apk',
      TargetPlatform.windows => 'TingReader-windows-x64-setup.exe',
      TargetPlatform.macOS => 'TingReader-macos.zip',
      TargetPlatform.linux => 'TingReader-linux-x64.tar.gz',
      TargetPlatform.iOS => 'TingReader-ios-self-sign.ipa',
      _ => null,
    };
    final assets = json['assets'];
    Map? asset;
    if (assetName != null && assets is List) {
      for (final item in assets) {
        if (item is Map &&
            item['name'] == assetName &&
            item['state'] == 'uploaded' &&
            item['size'] is num &&
            (item['size'] as num) > 0) {
          final url = item['browser_download_url']?.toString() ?? '';
          if (url == '$clientReleasesUrl/download/$tag/$assetName') {
            asset = item;
            break;
          }
        }
      }
    }
    return ClientReleaseInfo(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      downloadUrl: asset?['browser_download_url']?.toString() ?? '',
      size: asset?['size']?.toString() ?? '',
      date: json['published_at']?.toString() ?? '',
      notes: json['body']?.toString().trim() ?? '',
      pageUrl: tag.isEmpty
          ? clientReleasesUrl
          : '$clientReleasesUrl/tag/${Uri.encodeComponent(tag)}',
    );
  }

  final String version;
  final String downloadUrl;
  final String size;
  final String date;
  final String notes;
  final String pageUrl;

  bool get hasDownload => downloadUrl.isNotEmpty;
}

class ClientUpdateService {
  ClientUpdateService({Dio? dio, TargetPlatform? platform})
      : _platform = platform ?? (kIsWeb ? null : defaultTargetPlatform),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
            ));

  final Dio _dio;
  final TargetPlatform? _platform;

  void dispose() => _dio.close(force: true);

  Future<PackageInfo> packageInfo() => PackageInfo.fromPlatform();

  Future<String> currentVersion() async => (await packageInfo()).version;

  Future<String> currentVersionLabel() async => 'v${await currentVersion()}';

  Future<ClientReleaseInfo?> fetchLatest() async {
    try {
      final response = await _dio.get<Object?>(
        clientLatestReleaseApi,
        options: Options(headers: const {
          'Accept': 'application/vnd.github+json',
          'Cache-Control': 'no-cache',
        }),
      );
      final data = response.data;
      if (data is! Map ||
          data['draft'] != false ||
          data['prerelease'] != false ||
          _ReleaseVersion.parse(data['tag_name']?.toString() ?? '') == null) {
        throw const FormatException('无法识别仓库的正式版本信息');
      }
      return ClientReleaseInfo.fromGitHub(
          Map<String, dynamic>.from(data), _platform);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      if ([403, 429].contains(error.response?.statusCode)) {
        return _fetchFromReleasePage();
      }
      rethrow;
    }
  }

  Future<ClientReleaseInfo?> _fetchFromReleasePage() async {
    // 公共 API 被共享出口限流时，使用 GitHub 官方的最新版本跳转。
    final response = await _dio.get<String>(
      '$clientReleasesUrl/latest',
      options: Options(
        followRedirects: false,
        responseType: ResponseType.plain,
        validateStatus: (status) =>
            status != null && status < 400 || status == 404,
      ),
    );
    if (response.statusCode == 404) return null;
    final location = response.headers.value('location') ?? '';
    final page = Uri.parse(clientReleasesUrl).resolve(location);
    const prefix = '$clientReleasesUrl/tag/';
    final tag = page.toString().startsWith(prefix)
        ? Uri.decodeComponent(page.toString().substring(prefix.length))
        : '';
    if (!RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) {
      throw const FormatException('无法确认仓库的最新正式版本，请前往 Releases 查看');
    }
    final version = tag.substring(1);
    var notes = '';
    try {
      final changelog = await _dio.get<String>(
        'https://raw.githubusercontent.com/$clientRepository/$tag/CHANGELOG.md',
        options: Options(responseType: ResponseType.plain),
      );
      var currentSection = false;
      final lines = <String>[];
      for (final line in (changelog.data ?? '').split('\n')) {
        if (line.startsWith('## ')) {
          if (currentSection) break;
          currentSection = RegExp(
            '^## ${RegExp.escape(version)}(?:\\s+-.*)?\\s*\$',
          ).hasMatch(line);
        } else if (currentSection) {
          lines.add(line);
        }
      }
      notes = lines.join('\n').trim();
    } on DioException {
      // 日志暂不可达时仍可展示已确认的版本，并打开其发布页。
    }
    return ClientReleaseInfo(
        version: version,
        downloadUrl: '',
        size: '',
        date: '',
        notes: notes,
        pageUrl: page.toString());
  }

  bool isNewer(String remoteVersion, String currentVersion) {
    final remote = _ReleaseVersion.parse(remoteVersion);
    final current = _ReleaseVersion.parse(currentVersion);
    return remote != null && current != null && remote.compareTo(current) > 0;
  }

  bool get canInstallDirectly =>
      _platform == TargetPlatform.android ||
      _platform == TargetPlatform.windows;

  Future<void> openOrInstall(
    ClientReleaseInfo release, {
    ValueChanged<double>? onProgress,
    String languageCode = 'zh',
  }) async {
    if (!release.hasDownload || !canInstallDirectly) {
      // iOS 需要自行签名；先打开版本页查看安装说明和附件。
      await openExternalUrl(release.pageUrl);
      return;
    }
    final tempDir = await getTemporaryDirectory();
    final safeVersion =
        release.version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final android = _platform == TargetPlatform.android;
    final targetPath =
        '${tempDir.path}/ting-reader-$safeVersion.${android ? 'apk' : 'exe'}';
    await _dio.download(
      release.downloadUrl,
      targetPath,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );
    onProgress?.call(1);
    final result = await OpenFilex.open(targetPath,
        type: android ? 'application/vnd.android.package-archive' : null);
    if (result.type != ResultType.done) throw StateError(result.message);
  }

  Future<void> openDownloadPage(String languageCode) =>
      openExternalUrl(clientReleasesUrl);
}

class _ReleaseVersion implements Comparable<_ReleaseVersion> {
  const _ReleaseVersion(this.numbers, this.prerelease);

  final List<int> numbers;
  final List<String> prerelease;

  static _ReleaseVersion? parse(String value) {
    final match = RegExp(
      r'^[vV]?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    return _ReleaseVersion(
      [for (var i = 1; i <= 3; i++) int.parse(match[i]!)],
      match[4]?.split('.') ?? const [],
    );
  }

  @override
  int compareTo(_ReleaseVersion other) {
    for (var i = 0; i < numbers.length; i++) {
      final result = numbers[i].compareTo(other.numbers[i]);
      if (result != 0) return result;
    }
    if (prerelease.isEmpty || other.prerelease.isEmpty) {
      return prerelease.isEmpty == other.prerelease.isEmpty
          ? 0
          : (prerelease.isEmpty ? 1 : -1);
    }
    for (var i = 0; i < prerelease.length; i++) {
      if (i == other.prerelease.length) return 1;
      final left = prerelease[i];
      final right = other.prerelease[i];
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      final result = leftNumber != null && rightNumber != null
          ? leftNumber.compareTo(rightNumber)
          : leftNumber != null
              ? -1
              : rightNumber != null
                  ? 1
                  : left.compareTo(right);
      if (result != 0) return result;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }
}
