import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ting_reader_flutter/l10n/app_localizations.dart';
import 'package:ting_reader_flutter/src/core/api/api_client.dart';
import 'package:ting_reader_flutter/src/core/models/models.dart';
import 'package:ting_reader_flutter/src/core/services/chapter_read_marks.dart';
import 'package:ting_reader_flutter/src/core/state/app_state.dart';
import 'package:ting_reader_flutter/src/core/state/download_state.dart';
import 'package:ting_reader_flutter/src/core/state/player_state.dart';
import 'package:ting_reader_flutter/src/features/bookshelf/book_detail/book_detail_page.dart';
import 'package:ting_reader_flutter/src/shared/app_scope.dart';

class _Api extends ApiClient {
  final readIds = <String>{};
  final mutations = <String>[];
  @override
  Future<Response<dynamic>> post(String path,
      {Object? data,
      Map<String, dynamic>? params,
      CancelToken? cancelToken,
      Duration? receiveTimeout}) async {
    mutations.add(path);
    readIds.addAll(((data as Map)['chapter_ids'] as List).cast<String>());
    return Response(
        requestOptions: RequestOptions(path: path), statusCode: 204);
  }

  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? params, CancelToken? cancelToken}) async {
    final dynamic data = path.endsWith('/chapters')
        ? {
            'chapters': [
              for (final id in ['one', 'two'])
                {
                  'id': id,
                  'book_id': 'book',
                  'title': 'Chapter $id',
                  'duration': 0,
                  'is_read': readIds.contains(id),
                  'chapter_index': id == 'one' ? 1 : 2
                }
            ],
            'total': 2,
            'main_total': 2,
            'extra_total': 0,
            'offset': 0,
            'limit': 100,
            'chapter_type': 'main'
          }
        : path == '/api/settings'
            ? <String, dynamic>{}
            : path.startsWith('/api/progress/')
                ? {'book_id': 'book'}
                : {'id': 'book', 'title': 'Book', 'library_id': 'library'};
    return Response(requestOptions: RequestOptions(path: path), data: data);
  }
}

class _App extends AppState {
  final client = _Api();
  @override
  ApiClient get api => client;
}

class _Downloads extends DownloadState {
  _Downloads(super.appState);
  @override
  bool hasChapter(String id) => id == 'one';
}

class _Player extends ChangeNotifier implements PlayerState {
  @override
  Book? get currentBook => null;
  @override
  Chapter? get currentChapter => null;
  @override
  bool get isPlaying => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('chapter marks survive store replacement and isolate identities',
      () async {
    await ChapterReadMarksStore().write('server:user:book', {'one', 'two'});
    final next = ChapterReadMarksStore();
    expect(await next.read('server:user:book'), {'one', 'two'});
    for (final identity in [
      'other:user:book',
      'server:other:book',
      'server:user:other'
    ]) {
      expect(await next.read(identity), isEmpty);
    }
  });
  testWidgets(
      'downloaded and unknown-duration chapters can be marked and reopened',
      (tester) async {
    final app = _App();
    app.user = User.fromJson({'id': 'user', 'username': 'reader'});
    app.token = 'token';
    final player = _Player();
    final downloads = _Downloads(app);
    addTearDown(app.dispose);
    addTearDown(player.dispose);
    addTearDown(downloads.dispose);
    Widget page(String key) => AppScope(
          appState: app,
          downloadState: downloads,
          playerState: player,
          child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                  body: BookDetailPage(
                      key: ValueKey(key), bookId: 'book', onBack: () {}))),
        );
    await tester.pumpWidget(page('first'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Select chapters'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Select chapters'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Select Page'));
    await tester.tap(find.text('Select Page'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.ensureVisible(find.text('Mark as read'));
    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();
    expect(find.text('Read'), findsNWidgets(2));
    expect(app.client.mutations, ['/api/books/book/chapters/read-status']);
    expect(app.client.readIds, {'one', 'two'});
    await ChapterReadMarksStore()
        .write('${app.serverUrl}:${app.fnId}:user:book', {});
    await tester.pumpWidget(page('second'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Select chapters'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Read'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
