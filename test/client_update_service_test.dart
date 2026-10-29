import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ting_reader_flutter/src/core/services/client_update_service.dart';
import 'package:ting_reader_flutter/src/core/utils/external_links.dart';

const _names = {
  TargetPlatform.android: 'ting-reader-flutter-android.apk',
  TargetPlatform.windows: 'TingReader-windows-x64-setup.exe',
  TargetPlatform.macOS: 'TingReader-macos.zip',
  TargetPlatform.linux: 'TingReader-linux-x64.tar.gz',
  TargetPlatform.iOS: 'TingReader-ios-self-sign.ipa',
};

Map<String, dynamic> _release() => {
      'tag_name': 'v1.4.7',
      'draft': false,
      'prerelease': false,
      'published_at': '2026-10-29T12:00:00Z',
      'body': '本版本的修复说明',
      'assets': [
        for (final name in ['pubspec.lock', 'example.aab', ..._names.values])
          {
            'name': name,
            'state': 'uploaded',
            'size': 1024,
            'browser_download_url': '$clientReleasesUrl/download/v1.4.7/$name',
          },
      ],
    };

void main() {
  for (final entry in _names.entries) {
    test('${entry.key} 从自己的仓库获取正式版本及对应安装包', () async {
      final dio = Dio();
      RequestOptions? request;
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        request = options;
        handler.resolve(Response(requestOptions: options, data: _release()));
      }));
      final service = ClientUpdateService(dio: dio, platform: entry.key);
      addTearDown(service.dispose);
      final release = (await service.fetchLatest())!;
      expect(request!.uri.toString(), clientLatestReleaseApi);
      expect(request!.headers.containsKey('Authorization'), isFalse);
      expect(release.version, '1.4.7');
      expect(release.notes, '本版本的修复说明');
      expect(release.downloadUrl,
          '$clientReleasesUrl/download/v1.4.7/${entry.value}');
      expect(release.pageUrl, '$clientReleasesUrl/tag/v1.4.7');
      expect(service.canInstallDirectly,
          [TargetPlatform.android, TargetPlatform.windows].contains(entry.key));
    });
  }

  test('缺少附件或附件未上传时仍能获得版本和更新说明', () {
    final data = _release();
    data['assets'] = [
      {
        'name': _names[TargetPlatform.windows],
        'state': 'new',
        'size': 0,
        'browser_download_url': 'https://example.com/installer.exe',
      }
    ];
    final release = ClientReleaseInfo.fromGitHub(data, TargetPlatform.windows);
    expect(release.hasDownload, isFalse);
    expect(release.version, '1.4.7');
    expect(release.notes, isNotEmpty);
  });

  test('不使用其他仓库或官网的可执行文件作为更新附件', () {
    final data = _release();
    final assets = data['assets'] as List;
    for (final asset in assets) {
      (asset as Map)['browser_download_url'] = 'https://example.com/update.exe';
    }
    expect(
        ClientReleaseInfo.fromGitHub(data, TargetPlatform.windows).hasDownload,
        isFalse);
    expect(
        ClientReleaseInfo.fromGitHub(_release(), TargetPlatform.fuchsia)
            .hasDownload,
        isFalse);
  });

  test('404 表示暂无版本，网络失败和 API 限流不能当成已经最新', () async {
    var status = 404;
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: options, statusCode: status)));
    }));
    final service = ClientUpdateService(dio: dio);
    addTearDown(service.dispose);
    expect(await service.fetchLatest(), isNull);
    status = 403;
    await expectLater(service.fetchLatest(), throwsA(isA<DioException>()));
  });

  test('不把错误数据、草稿和预发布当成正式更新', () async {
    Object data = '<html>proxy error</html>';
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, data: data));
    }));
    final service = ClientUpdateService(dio: dio);
    addTearDown(service.dispose);
    for (final invalid in [
      data,
      {..._release(), 'draft': true},
      {..._release(), 'prerelease': true},
      {..._release(), 'tag_name': 'beta'},
    ]) {
      data = invalid;
      await expectLater(service.fetchLatest(), throwsFormatException);
    }
  });

  test('比较语义版本，忽略构建号并正确比较预发布版本', () {
    final service = ClientUpdateService();
    addTearDown(service.dispose);
    for (final pair in [
      ('1.4.7', '1.4.6'),
      ('v1.10.0', 'v1.9.9'),
      ('1.5.0', '1.5.0-rc.1'),
      ('1.5.0-rc.10', '1.5.0-rc.2'),
    ]) {
      expect(service.isNewer(pair.$1, pair.$2), isTrue, reason: '$pair');
      expect(service.isNewer(pair.$2, pair.$1), isFalse, reason: '$pair');
    }
    expect(service.isNewer('1.4.6+999', '1.4.6+47'), isFalse);
    expect(service.isNewer('unknown', '1.4.6'), isFalse);
  });

  for (final status in [403, 429]) {
    test('API 返回 $status 时使用官方版本跳转，只展示该版本日志', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.path == clientLatestReleaseApi) {
          handler.reject(DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: status)));
        } else if (options.path == '$clientReleasesUrl/latest') {
          expect(options.followRedirects, isFalse);
          handler.resolve(Response<String>(
              requestOptions: options,
              statusCode: 302,
              headers: Headers.fromMap({
                'location': ['$clientReleasesUrl/tag/v1.4.7'],
              })));
        } else {
          expect(options.path,
              'https://raw.githubusercontent.com/$clientRepository/v1.4.7/CHANGELOG.md');
          handler.resolve(Response<String>(requestOptions: options, data: '''
# 更新日志
## 未发布
不要展示的未来内容
## 1.4.7 - 2026-10-29
### 修复
- 只有本版内容
## 1.4.6 - 2026-10-28
不要展示的历史内容
'''));
        }
      }));
      final service = ClientUpdateService(dio: dio);
      addTearDown(service.dispose);
      final release = (await service.fetchLatest())!;
      expect(release.version, '1.4.7');
      expect(release.notes, '### 修复\n- 只有本版内容');
      expect(release.pageUrl, '$clientReleasesUrl/tag/v1.4.7');
      expect(release.hasDownload, isFalse);
    });
  }

  test('备用版本跳转不得指向其他仓库', () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path == clientLatestReleaseApi) {
        handler.reject(DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: 403)));
      } else {
        handler.resolve(Response<String>(
            requestOptions: options,
            statusCode: 302,
            headers: Headers.fromMap({
              'location': ['$upstreamClientRepositoryUrl/releases/tag/v9.0.0'],
            })));
      }
    }));
    final service = ClientUpdateService(dio: dio);
    addTearDown(service.dispose);
    await expectLater(service.fetchLatest(), throwsFormatException);
  });
}
