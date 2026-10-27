import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets(
        'tab switches preserve pages without repeating requests at $size',
        (tester) async {
      final (app, player) = await _pump(tester, size);
      final shelf = tester.state(find.byType(BookshelfPage));
      final requests = List<String>.of(app.client.requests);
      expect(find.byType(DownloadsPage, skipOffstage: false), findsNothing);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Playback & appearance'), findsOneWidget);
      expect(find.byType(DownloadsPage, skipOffstage: false), findsNothing);
      player.notifyListeners();
      await tester.pump();
      await tester.tap(find.text('Bookshelf'));
      await tester.pumpAndSettle();
      expect(
          identical(tester.state(find.byType(BookshelfPage)), shelf), isTrue);
      expect(app.client.requests, requests);

      await tester.tap(find.text('Downloads'));
      await tester.pumpAndSettle();
      final downloads = tester.state(find.byType(DownloadsPage));
      await tester.tap(find.text('Bookshelf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Downloads'));
      await tester.pumpAndSettle();
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
