import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ting_reader_flutter/src/features/mine/listening_settings_page.dart';
import 'package:ting_reader_flutter/src/features/mine/personalization/personalization_page.dart';
import 'package:ting_reader_flutter/src/features/mine/favorites_page.dart';
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

Future<(_App, _Player)> _pump(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final app = _App()
    ..token = 'token'
    ..user = const User(id: 'user', username: 'reader', role: 'user');
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
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
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
      expect(tester.getTopLeft(find.byTooltip('Settings')).dx, lessThan(24));
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
