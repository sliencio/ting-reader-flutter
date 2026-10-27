import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ting_reader_flutter/l10n/app_localizations.dart';
import 'package:ting_reader_flutter/src/core/api/api_client.dart';
import 'package:ting_reader_flutter/src/core/models/models.dart';
import 'package:ting_reader_flutter/src/core/state/app_state.dart';
import 'package:ting_reader_flutter/src/core/state/download_state.dart';
import 'package:ting_reader_flutter/src/core/state/player_state.dart';
import 'package:ting_reader_flutter/src/features/bookshelf/continue_listening.dart';
import 'package:ting_reader_flutter/src/shared/app_scope.dart';

class _Api extends ApiClient {
  bool fail = false;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
    CancelToken? cancelToken,
  }) async {
    if (fail) throw StateError('连接失败');
    final dynamic data = switch (path) {
      '/api/progress/recent' => [
          {'book_id': 'old', 'book_title': '旧书', 'updated_at': '2026-10-20'},
          {
            'book_id': 'new',
            'book_title': '新书',
            'chapter_id': 'chapter',
            'position': 125.5,
            'updated_at': '2026-10-27',
          },
        ],
      '/api/books/new' => {'id': 'new', 'title': '新书'},
      '/api/books/new/chapters' => [
          {
            'id': 'chapter',
            'book_id': 'new',
            'title': '第一章',
            'chapter_index': 1,
            'duration': 600,
          },
        ],
      _ => {},
    };
    return Response(
      requestOptions: RequestOptions(path: path),
      data: data,
    );
  }
}

class _App extends AppState {
  final client = _Api();
  @override
  ApiClient get api => client;
}

class _Player extends ChangeNotifier implements PlayerState {
  String? playedBook;
  String? playedChapter;
  double? position;

  @override
  Book? get currentBook => null;

  @override
  Future<void> playChapter(
    Book book,
    List<Chapter> chapters,
    Chapter chapter, {
    double? startAt,
  }) async {
    playedBook = book.id;
    playedChapter = chapter.id;
    position = startAt;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(_App, _Player)> _pump(WidgetTester tester, {bool fail = false}) async {
  final app = _App();
  app.client.fail = fail;
  final downloads = DownloadState(app);
  final player = _Player();
  addTearDown(app.dispose);
  addTearDown(downloads.dispose);
  addTearDown(player.dispose);
  await tester.pumpWidget(
    AppScope(
      appState: app,
      downloadState: downloads,
      playerState: player,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ContinueListening(openBook: (_) {})),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (app, player);
}

void main() {
  testWidgets('resume uses the latest book and its saved chapter position', (
    tester,
  ) async {
    final (_, player) = await _pump(tester);
    expect(find.text('新书'), findsOneWidget);
    expect(find.text('旧书'), findsNothing);
    await tester.tap(find.byTooltip('继续播放'));
    await tester.pumpAndSettle();
    expect(player.playedBook, 'new');
    expect(player.playedChapter, 'chapter');
    expect(player.position, 125.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable history leaves the shelf usable', (tester) async {
    await _pump(tester, fail: true);
    expect(find.byType(Card), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
