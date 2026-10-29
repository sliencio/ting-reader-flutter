import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ting_reader_flutter/src/features/mine/listening_settings_page.dart';
import 'package:ting_reader_flutter/src/features/mine/personalization/personalization_page.dart';
import 'package:ting_reader_flutter/src/features/mine/favorites_page.dart';
import 'package:ting_reader_flutter/src/features/admin/admin_pages.dart';
import 'package:ting_reader_flutter/src/features/admin/users/admin_users_page.dart';
import 'package:ting_reader_flutter/src/features/player/desktop_window_host.dart';
import 'package:ting_reader_flutter/l10n/app_localizations.dart';
import 'package:ting_reader_flutter/src/core/api/api_client.dart';
import 'package:ting_reader_flutter/src/core/models/models.dart';
import 'package:ting_reader_flutter/src/core/state/app_state.dart';
import 'package:ting_reader_flutter/src/core/state/download_state.dart';
import 'package:ting_reader_flutter/src/core/state/player_state.dart';
import 'package:ting_reader_flutter/src/features/app_shell.dart';
import 'package:ting_reader_flutter/src/features/bookshelf/bookshelf_page.dart';
import 'package:ting_reader_flutter/src/features/mine/downloads_page.dart';
import 'package:ting_reader_flutter/src/shared/app_scope.dart';

class _Api extends ApiClient {
  final requests = <String>[];

  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? params, CancelToken? cancelToken}) async {
    requests.add(path);
    return Response(
      requestOptions: RequestOptions(path: path),
      data: path == '/api/settings' ||
              path == '/api/history/summary' ||
              path == '/api/health'
          ? <String, dynamic>{}
          : [],
    );
  }
}

class _App extends AppState {
  final client = _Api();
  @override
  ApiClient get api => client;
}

class _Player extends ChangeNotifier implements PlayerState {
  @override
  Book? get currentBook => null;
  @override
  bool get isMiniCollapsed => false;
  @override
  bool get hasChapter => false;
  @override
  bool get isExpanded => false;
  @override
  void setExpanded(bool value) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(_App, _Player)> _pump(WidgetTester tester, Size size,
    {bool admin = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final app = _App()
    ..token = 'token'
    ..user =
        User(id: 'user', username: 'reader', role: admin ? 'admin' : 'user');
  final player = _Player();
  final downloads = DownloadState(app);
  addTearDown(app.dispose);
  addTearDown(player.dispose);
  addTearDown(downloads.dispose);
  await tester.pumpWidget(AppScope(
    appState: app,
    downloadState: downloads,
    playerState: player,
    child: const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AppShell(),
    ),
  ));
  await tester.pumpAndSettle();
  return (app, player);
}

Future<void> _select(WidgetTester tester, String label) async {
  final target = find.descendant(
      of: find.byType(ListeningSettingsPage), matching: find.byTooltip(label));
  if (target.evaluate().isEmpty) {
    final scrollable = find.descendant(
        of: find.byType(ListeningSettingsPage),
        matching: find.byType(Scrollable));
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(target, 200, scrollable: scrollable);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux
  ]) {
    testWidgets('window settings entry visibility on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester, const Size(390, 1000));
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        final desktop = [
          TargetPlatform.windows,
          TargetPlatform.macOS,
          TargetPlatform.linux
        ].contains(platform);
        final entry = find.descendant(
            of: find.byType(ListeningSettingsPage),
            matching: find.byTooltip('Window behavior'));
        expect(entry, desktop ? findsOneWidget : findsNothing);
        if (desktop) {
          final icon = find.descendant(
              of: entry, matching: find.byType(WindowCaptionIcon));
          expect(tester.widget<WindowCaptionIcon>(icon).action,
              WindowCaptionAction.mini);
        }
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
  for (final width in [390.0, 1440.0]) {
    testWidgets('admin entries open directly from settings at $width',
        (tester) async {
      await _pump(tester, Size(width, 1000), admin: true);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byType(ListeningSettingsPage));
      expect(find.byTooltip('Server & extensions'), findsNothing);
      for (final target in [
        ('Libraries', AdminLibrariesPage),
        ('Users', AdminUsersV2Page),
        ('Plugins', PluginsPage),
        ('System Logs', LogsPage),
      ]) {
        await _select(tester, target.$1);
        expect(tester.takeException(), isNull, reason: target.$1);
        expect(find.byType(target.$2), findsOneWidget);
        expect(find.byType(Drawer), findsNothing);
        expect(tester.getRect(find.byType(ListeningSettingsPage)), bounds);
        expect(find.byTooltip('Close settings'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1024, 1366),
  ]) {
    testWidgets('iOS 设置在 $size 保持导航并隐藏桌面功能', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final landscape = size.width > size.height;
      final padding = landscape
          ? const FakeViewPadding(left: 47, right: 47, bottom: 21)
          : const FakeViewPadding(top: 59, bottom: 34);
      tester.view.padding = padding;
      tester.view.viewPadding = padding;
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await _pump(tester, size);
      expect(find.byTooltip('Mini window'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final menu = tester.element(find.byType(ListeningSettingsPage));
      final bounds = tester.getRect(find.byType(ListeningSettingsPage));
      expect(find.byTooltip('Window behavior'), findsNothing);
      expect(find.byTooltip('Exit application'), findsNothing);
      for (final target in [
        ('Playback & appearance', PersonalizationPage),
        ('Favorites', FavoritesPage),
        ('Downloads', DownloadsPage),
        ('Bookshelf', BookshelfPage),
      ]) {
        await _select(tester, target.$1);
        expect(find.byType(target.$2), findsOneWidget);
        expect(tester.getRect(find.byType(ListeningSettingsPage)), bounds);
        expect(
            identical(tester.element(find.byType(ListeningSettingsPage)), menu),
            isTrue);
        expect(tester.takeException(), isNull, reason: target.$1);
      }
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }
  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets(
        'settings selection updates the right pane and preserves navigation at $width',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final (app, _) = await _pump(tester, Size(width, 1000));
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        final menu = tester.element(find.byType(ListeningSettingsPage));
        final menuBounds = tester.getRect(find.byType(ListeningSettingsPage));
        expect(
            find.descendant(
                of: find.byType(ListeningSettingsPage),
                matching: find.byTooltip('Mini window')),
            findsNothing);
        await _select(tester, 'Window behavior');
        expect(find.byType(WindowSettingsPage), findsOneWidget);
        expect(
            find.descendant(
                of: find.byType(WindowSettingsPage),
                matching: find.byType(WindowCaptionIcon)),
            findsOneWidget);
        expect(tester.getRect(find.byType(WindowSettingsPage)).left,
            greaterThan(menuBounds.right - 1));
        expect(tester.getRect(find.byType(ListeningSettingsPage)), menuBounds);
        expect(
            identical(tester.element(find.byType(ListeningSettingsPage)), menu),
            isTrue);
        expect(
            find.descendant(
                of: find.byType(WindowSettingsPage),
                matching: find.byType(DropdownButtonFormField<String>)),
            findsNothing);
        await tester.tap(find.text('Minimize to taskbar'));
        await tester.pumpAndSettle();
        expect(app.settings['desktop_close_behavior'], 'minimize');
        expect(
            tester
                .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
                .groupValue,
            'minimize');
        await _select(tester, 'Playback & appearance');
        expect(find.byType(PersonalizationPage), findsOneWidget);
        expect(tester.getRect(find.byType(ListeningSettingsPage)), menuBounds);
        await _select(tester, 'Favorites');
        expect(find.byType(FavoritesPage), findsOneWidget);
        expect(tester.getRect(find.byType(ListeningSettingsPage)), menuBounds);
        await _select(tester, 'Window behavior');
        expect(
            tester
                .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
                .groupValue,
            'minimize');
        await _select(tester, 'Downloads');
        expect(find.byType(DownloadsPage), findsOneWidget);
        expect(tester.getRect(find.byType(ListeningSettingsPage)), menuBounds);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.byType(BookshelfPage), findsOneWidget);
        expect(tester.getRect(find.byType(ListeningSettingsPage)), menuBounds);
        expect(find.byTooltip('Close settings'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets('left gear opens settings while retaining the page at $width',
        (tester) async {
      await _pump(tester, Size(width, 1000));
      final page = tester.element(find.byType(BookshelfPage));
      final before = tester.getRect(find.byType(BookshelfPage));
      expect(tester.getTopLeft(find.byTooltip('Home')).dx, lessThan(24));
      expect(tester.getTopLeft(find.byTooltip('Settings')).dx,
          greaterThan(tester.getTopLeft(find.byTooltip('Home')).dx));
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      final halfway = tester.getRect(find.byType(BookshelfPage));
      expect(halfway.left, greaterThan(before.left));
      expect(halfway.left, lessThan(before.left + (width >= 840 ? 280 : 72)));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Playback & appearance'), findsOneWidget);
      await tester.tap(find.byTooltip('Close settings'));
      await tester.pumpAndSettle();
      expect(
          identical(tester.element(find.byType(BookshelfPage)), page), isTrue);
      expect(tester.getRect(find.byType(BookshelfPage)).left,
          closeTo(before.left, 0.001));
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform 设置支持右滑打开左滑隐藏，主页键清除子页并保留书架', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final (app, _) = await _pump(tester, const Size(390, 844));
        final shelf = tester.state(find.byType(BookshelfPage));
        await tester.dragFrom(const Offset(150, 24), const Offset(140, 0));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Close settings').hitTestable(), findsOneWidget);
        await _select(tester, 'Playback & appearance');
        final settings = tester.state(find.byType(PersonalizationPage));
        await tester.dragFrom(const Offset(220, 24), const Offset(-140, 0));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Settings').hitTestable(), findsOneWidget);
        expect(
            identical(tester.state(find.byType(PersonalizationPage)), settings),
            isTrue);
        await tester.dragFrom(const Offset(150, 24), const Offset(140, 0));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Close settings').hitTestable(), findsOneWidget);
        await _select(tester, 'Favorites');
        final requests = List<String>.of(app.client.requests);
        await tester.tap(find.byTooltip('Home').hitTestable());
        await tester.pumpAndSettle();
        expect(find.byType(FavoritesPage), findsNothing);
        expect(
            identical(tester.state(find.byType(BookshelfPage)), shelf), isTrue);
        expect(find.byTooltip('Settings').hitTestable(), findsOneWidget);
        expect(app.client.requests, requests);
        expect(tester.getTopLeft(find.byTooltip('Home').hitTestable()).dx,
            lessThan(24));
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('桌面主页键也能返回主页，横向拖动不打开设置', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pump(tester, const Size(1440, 1000));
      await tester.dragFrom(const Offset(200, 24), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Settings'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await _select(tester, 'Favorites');
      await tester.tap(find.byTooltip('Home').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(BookshelfPage), findsOneWidget);
      expect(find.byType(FavoritesPage), findsNothing);
      expect(find.byTooltip('Settings').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('force refresh discards retained shelf and details',
      (tester) async {
    final (app, _) = await _pump(tester, const Size(390, 844));
    final shelf = tester.state(find.byType(BookshelfPage));
    final revision = app.bookDetailsCache.revision;
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await _select(tester, 'Force refresh');
    expect(app.bookDetailsCache.revision, revision + 1);
    await _select(tester, 'Bookshelf');
    expect(identical(tester.state(find.byType(BookshelfPage)), shelf), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets(
        'tab switches preserve pages without repeating requests at $size',
        (tester) async {
      final (app, player) = await _pump(tester, size);
      final shelf = tester.state(find.byType(BookshelfPage));
      final requests = List<String>.of(app.client.requests);
      expect(find.text('Settings'), findsNothing);
      expect(find.text('Downloads'), findsNothing);
      expect(find.byType(DownloadsPage, skipOffstage: false), findsNothing);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Playback & appearance'), findsOneWidget);
      expect(find.byType(DownloadsPage, skipOffstage: false), findsNothing);
      player.notifyListeners();
      await tester.pump();
      await _select(tester, 'Bookshelf');
      expect(
          identical(tester.state(find.byType(BookshelfPage)), shelf), isTrue);
      expect(app.client.requests, requests);

      await _select(tester, 'Downloads');
      final downloads = tester.state(find.byType(DownloadsPage));
      await _select(tester, 'Bookshelf');
      await _select(tester, 'Downloads');
      expect(identical(tester.state(find.byType(DownloadsPage)), downloads),
          isTrue);
      expect(app.client.requests, requests);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('changing servers discards retained server data', (tester) async {
    final (app, _) = await _pump(tester, const Size(390, 844));
    final shelf = tester.state(find.byType(BookshelfPage));
    app.serverUrl = 'https://another-server.example';
    app.notifyListeners();
    await tester.pumpAndSettle();
    expect(identical(tester.state(find.byType(BookshelfPage)), shelf), isFalse);
    expect(app.client.requests.where((path) => path == '/api/books').length, 2);
    expect(tester.takeException(), isNull);
  });
}
