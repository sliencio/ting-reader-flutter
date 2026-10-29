import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ting_reader_flutter/l10n/app_localizations.dart';
import 'package:ting_reader_flutter/src/core/services/client_update_service.dart';
import 'package:ting_reader_flutter/src/core/utils/external_links.dart';
import 'package:ting_reader_flutter/src/features/mine/about_update_dialog.dart';

class _Updates extends ClientUpdateService {
  _Updates({super.platform});

  ClientReleaseInfo? latest;
  Object? error;
  int requests = 0;
  int installs = 0;

  @override
  Future<String> currentVersion() async => '1.4.6';

  @override
  Future<ClientReleaseInfo?> fetchLatest() async {
    requests++;
    if (error != null) throw error!;
    return latest;
  }

  @override
  Future<void> openOrInstall(ClientReleaseInfo release,
      {ValueChanged<double>? onProgress, String languageCode = 'zh'}) async {
    installs++;
    onProgress?.call(1);
  }
}

Future<void> _pump(WidgetTester tester, _Updates updates,
    {Size size = const Size(320, 568),
    double scale = 1,
    Locale locale = const Locale('en'),
    ValueChanged<String>? open}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: AboutPage(
        backendVersion: '2.12.8',
        onBack: () {},
        updateService: updates,
        openLink: (url) async {
          open?.call(url);
          return true;
        },
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _check(WidgetTester tester) async {
  final button = find.widgetWithText(TextButton, 'Check for updates').first;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    testWidgets('$platform 确认更新后选择安装程序或本仓库版本页', (tester) async {
      final urls = <String>[];
      final updates = _Updates(platform: platform)
        ..latest = const ClientReleaseInfo(
            version: '1.4.7',
            downloadUrl: '$clientReleasesUrl/download/v1.4.7/package',
            size: '100',
            date: '',
            notes: '本版说明',
            pageUrl: '$clientReleasesUrl/tag/v1.4.7');
      await _pump(tester, updates, open: urls.add);
      await _check(tester);
      expect(find.text('本版说明'), findsOneWidget);
      final direct =
          [TargetPlatform.android, TargetPlatform.windows].contains(platform);
      await tester.tap(find.text(direct ? 'Download' : 'View release'));
      await tester.pumpAndSettle();
      expect(updates.installs, direct ? 1 : 0);
      expect(urls, direct ? isEmpty : ['$clientReleasesUrl/tag/v1.4.7']);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [
    const Size(248, 568),
    const Size(318, 844),
    const Size(700, 320),
    const Size(1160, 1000),
  ]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('关于页在 $size、字体 $scale 下完整显示版本及链接', (tester) async {
        final urls = <String>[];
        final updates = _Updates();
        await _pump(tester, updates, size: size, scale: scale, open: urls.add);
        expect(find.text('v1.4.6'), findsOneWidget);
        expect(find.text('v2.12.8'), findsOneWidget);
        expect(updates.requests, 0);
        for (final target in [
          ('Project repository', clientRepositoryUrl),
          ('Changelog', clientReleasesUrl),
          ('Report an issue', '$clientRepositoryUrl/issues'),
          ('Original client repository', upstreamClientRepositoryUrl),
        ]) {
          await tester.ensureVisible(find.text(target.$1));
          await tester.pumpAndSettle();
          await tester.tap(find.text(target.$1));
          await tester.pumpAndSettle();
          expect(urls.last, target.$2);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('更新弹窗长日志可滚动，横屏大字仍可点击取消', (tester) async {
    final updates = _Updates()
      ..latest = ClientReleaseInfo(
        version: '1.4.7',
        downloadUrl: '',
        date: '2026-10-29T12:00:00Z',
        size: '',
        notes: List.filled(80, '本版更新说明 Release notes').join('\n'),
      );
    await _pump(tester, updates, size: const Size(568, 320), scale: 1.8);
    await _check(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Later').hitTestable(), findsOneWidget);
    expect(find.text('View release').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('同版本没有附件时仍提示最新，不自动打开浏览器', (tester) async {
    final urls = <String>[];
    final updates = _Updates()
      ..latest = const ClientReleaseInfo(
          version: '1.4.6', downloadUrl: '', size: '', date: '');
    await _pump(tester, updates, open: urls.add);
    await _check(tester);
    expect(find.text('Client is up to date'), findsOneWidget);
    expect(urls, isEmpty);
  });

  testWidgets('更新失败提供重试和本仓库下载入口，不显示已经最新', (tester) async {
    final urls = <String>[];
    final updates = _Updates()..error = StateError('network unavailable');
    await _pump(tester, updates, open: urls.add);
    await _check(tester);
    expect(find.text('Client is up to date'), findsNothing);
    await tester.ensureVisible(find.text('Open Releases'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Releases'));
    await tester.pumpAndSettle();
    expect(urls, [clientReleasesUrl]);
    updates.error = null;
    updates.latest = const ClientReleaseInfo(
        version: '1.4.6', downloadUrl: '', size: '', date: '');
    await _check(tester);
    expect(updates.requests, 2);
    expect(find.text('Open Releases'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
