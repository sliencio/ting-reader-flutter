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
import 'package:ting_reader_flutter/src/core/services/listening_progress_sync.dart';
import 'package:ting_reader_flutter/src/core/models/models.dart';
import 'package:ting_reader_flutter/src/core/state/app_state.dart';
import 'package:ting_reader_flutter/src/core/state/download_state.dart';
import 'package:ting_reader_flutter/src/core/state/player_state.dart';
import 'package:ting_reader_flutter/src/features/app_shell.dart';
import 'package:ting_reader_flutter/src/features/bookshelf/bookshelf_page.dart';
import 'package:ting_reader_flutter/src/features/mine/downloads_page.dart';
import 'package:ting_reader_flutter/src/features/mine/about_update_dialog.dart';
import 'package:ting_reader_flutter/src/features/player/mini_player.dart';
import 'package:ting_reader_flutter/src/shared/app_scope.dart';
import 'package:ting_reader_flutter/src/shared/common/media_widgets.dart';

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
  Book? book;
  Chapter? chapter;
  bool expanded = false;
  bool playing = false;
  double position = 20;
  int toggles = 0;
  @override
  final progressSync = ListeningProgressSync(
      api: _Api(), identity: () => 'reader', canSync: () => false);
  @override
  Chapter? get currentChapter => chapter;
  @override
  double get currentTime => position;
  @override
  double get duration => 600;
  @override
  double get playbackSpeed => 1;
  @override
  double get volume => 1;
  @override
  bool get isPlaying => playing;
  @override
  bool get isLoading => false;
  @override
  String? get playbackStatus => null;
  @override
  int? get sleepRemainingSeconds => null;
  @override
  int? get sleepEpisodesRemaining => null;
  @override
  int get smartRewindSeconds => 10;
  @override
  Book? get currentBook => book;
  @override
  bool get isMiniCollapsed => false;
  @override
  bool get hasChapter => book != null && chapter != null;
  @override
  bool get isExpanded => expanded;
  @override
  void setExpanded(bool value) {
    expanded = value;
    notifyListeners();
  }

  @override
  Future<void> seek(double value) async {
    position = value;
    notifyListeners();
  }

  @override
  Future<void> togglePlay() async {
    playing = !playing;
    toggles++;
    notifyListeners();
  }

  @override
  void dispose() {
    progressSync.dispose();
    super.dispose();
  }

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

  for (final (size, scale, sidebar) in [
    (const Size(1280, 686), 1.0, false),
    (const Size(1024, 566), 1.0, false),
    (const Size(853, 446), 1.0, false),
    (const Size(1024, 566), 1.5, false),
    (const Size(1280, 686), 1.0, true),
  ]) {
    for (final shape in ['square', 'rect']) {
      testWidgets('桌面播放详情首屏显示完整控件 $size 缩放 $scale 侧栏 $sidebar 封面 $shape',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final (app, player) = await _pump(tester, size);
        app.settings = {'bookshelf_cover_shape': shape};
        if (sidebar) {
          await tester.tap(find.byTooltip('Settings'));
          await tester.pumpAndSettle();
        }
        player.book = Book.fromJson({'id': 'book', 'title': '书籍标题'});
        player.chapter = Chapter.fromJson({
          'id': 'chapter',
          'book_id': 'book',
          'title': '正在播放的章节',
          'duration': 600,
        });
        player.expanded = true;
        player.notifyListeners();
        await tester.pumpAndSettle();
        final overlay = find.byType(ExpandedPlayerOverlay);
        final bounds = tester.getRect(overlay);
        for (final icon in [
          Icons.keyboard_arrow_down_rounded,
          Icons.skip_previous_rounded,
          Icons.play_arrow_rounded,
          Icons.skip_next_rounded,
          Icons.list_alt_rounded,
        ]) {
          final target =
              find.descendant(of: overlay, matching: find.byIcon(icon));
          final rect = tester.getRect(target);
          expect(bounds.contains(rect.topLeft), isTrue, reason: '$icon 顶部应可见');
          expect(bounds.contains(rect.bottomRight), isTrue,
              reason: '$icon 底部应可见');
          expect(target.hitTestable(), findsOneWidget);
        }
        final slider =
            find.descendant(of: overlay, matching: find.byType(Slider));
        await tester.drag(slider, const Offset(60, 0));
        await tester.pumpAndSettle();
        expect(player.position, greaterThan(20));
        await tester.tap(find.descendant(
            of: overlay, matching: find.byIcon(Icons.play_arrow_rounded)));
        await tester.pumpAndSettle();
        expect(player.toggles, 1);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  testWidgets('桌面播放详情窄窗可滚动操作，放大窗口后恢复首屏布局', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final (_, player) = await _pump(tester, const Size(560, 400));
    player.book = Book.fromJson({'id': 'book', 'title': '书籍'});
    player.chapter = Chapter.fromJson({
      'id': 'chapter',
      'book_id': 'book',
      'title': '章节',
      'duration': 600,
    });
    player.expanded = true;
    player.notifyListeners();
    await tester.pumpAndSettle();
    final overlay = find.byType(ExpandedPlayerOverlay);
    final play = find.descendant(
        of: overlay, matching: find.byIcon(Icons.play_arrow_rounded));
    await tester.ensureVisible(play);
    await tester.pumpAndSettle();
    await tester.tap(play);
    await tester.pumpAndSettle();
    expect(player.toggles, 1);
    tester.view.physicalSize = const Size(1280, 686);
    await tester.pumpAndSettle();
    final pause = find.descendant(
        of: overlay, matching: find.byIcon(Icons.pause_rounded));
    expect(pause.hitTestable(), findsOneWidget);
    expect(
        find
            .descendant(
                of: overlay,
                matching: find.byIcon(Icons.keyboard_arrow_down_rounded))
            .hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

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
    expect(find.byTooltip('Force refresh'), findsNothing);
    await _select(tester, 'About Ting Reader');
    final refresh = find.widgetWithText(OutlinedButton, 'Force refresh');
    await tester.ensureVisible(refresh);
    await tester.pumpAndSettle();
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(app.bookDetailsCache.revision, revision + 1);
    expect(find.byType(SnackBar), findsNothing);
    await _select(tester, 'Bookshelf');
    expect(identical(tester.state(find.byType(BookshelfPage)), shelf), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform 展开播放详情后可左滑收起菜单，进度条仍可拖动', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final (_, player) = await _pump(tester, const Size(390, 844));
      player.book = Book.fromJson({'id': 'book', 'title': '收听中的书籍'});
      player.chapter = Chapter.fromJson({
        'id': 'chapter',
        'book_id': 'book',
        'title': '当前章节',
        'duration': 600,
      });
      player.notifyListeners();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find
          .descendant(
              of: find.byType(MiniPlayer), matching: find.byType(CoverImage))
          .first);
      await tester.pumpAndSettle();
      expect(player.isExpanded, isTrue);
      final overlay = tester.element(find.byType(ExpandedPlayerOverlay));
      final slider = find.descendant(
          of: find.byType(ExpandedPlayerOverlay),
          matching: find.byType(Slider));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      await tester.drag(slider, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(player.position, greaterThan(20));
      expect(find.byTooltip('Close settings').hitTestable(), findsOneWidget);
      await tester.dragFrom(const Offset(260, 130), const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close settings').hitTestable(), findsNothing);
      expect(player.isExpanded, isTrue);
      expect(
          identical(
              tester.element(find.byType(ExpandedPlayerOverlay)), overlay),
          isTrue);
      await tester.dragFrom(const Offset(100, 130), const Offset(160, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close settings').hitTestable(), findsNothing);
      final play = find.byIcon(Icons.play_arrow_rounded);
      await tester.ensureVisible(play);
      await tester.pumpAndSettle();
      await tester.tap(play);
      await tester.pumpAndSettle();
      expect(player.toggles, 1);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final size in [const Size(320, 568), const Size(1440, 1000)]) {
    testWidgets('打开关于不刷新或清除缓存，版本加载失败不影响页面 $size', (tester) async {
      final (app, _) = await _pump(tester, size);
      final shelf = tester.state(find.byType(BookshelfPage));
      final revision = app.bookDetailsCache.revision;
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final settingsRequests =
          app.client.requests.where((path) => path == '/api/settings').length;
      for (var i = 0; i < 2; i++) {
        await _select(tester, 'About Ting Reader');
        expect(find.byType(AboutPage), findsOneWidget);
        expect(app.bookDetailsCache.revision, revision);
        expect(
            app.client.requests.where((path) => path == '/api/settings').length,
            settingsRequests);
        expect(find.byType(SnackBar), findsNothing);
        await _select(tester, 'Bookshelf');
        expect(
            identical(tester.state(find.byType(BookshelfPage)), shelf), isTrue);
        expect(tester.takeException(), isNull);
      }
    });
  }

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
