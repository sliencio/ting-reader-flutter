import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ting_reader_flutter/src/core/api/api_client.dart';
import 'package:ting_reader_flutter/src/core/state/books_state.dart';

class _Api extends ApiClient {
  String title = '旧标题';
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? params, CancelToken? cancelToken}) async {
    if (path == '/api/books/book') {
      await gate?.future;
      if (fail) throw StateError('服务端不可用');
    }
    final dynamic data = path.endsWith('/chapters')
        ? {
            'chapters': [
              {
                'id': 'chapter',
                'book_id': 'book',
                'title': '第一章',
                'chapter_index': 1
              }
            ],
            'total': 1,
            'main_total': 1,
            'extra_total': 0,
            'chapter_type': 'main',
            'offset': 0,
            'limit': 100
          }
        : path == '/api/settings'
            ? {'settings_json': <String, dynamic>{}}
            : path.startsWith('/api/progress/')
                ? {'book_id': 'book', 'chapter_id': 'chapter', 'position': 42}
                : {'id': 'book', 'title': title, 'library_id': 'library'};
    return Response(requestOptions: RequestOptions(path: path), data: data);
  }
}

void main() {
  test('同步章节已读保留详情缓存和续播位置，不影响其他账号', () async {
    final api = _Api();
    final cache = BookDetailsCache();
    for (final key in ['server:user:book', 'server:other:book']) {
      final state = BookDetailState(api, 'book', cache: cache, cacheKey: key);
      await state.load();
      state.dispose();
    }
    final revision = cache.revision;
    cache.markChaptersRead('server:user:book', {'chapter'});
    final current = BookDetailState(api, 'book',
        cache: cache, cacheKey: 'server:user:book');
    final other = BookDetailState(api, 'book',
        cache: cache, cacheKey: 'server:other:book');
    addTearDown(current.dispose);
    addTearDown(other.dispose);
    expect(current.loading, isFalse);
    expect(current.chapters.single.isRead, isTrue);
    expect(current.progress?.position, 42);
    expect(other.loading, isFalse);
    expect(other.chapters.single.isRead, isFalse);
    expect(cache.revision, revision);
  });

  test('cached details display immediately while changed metadata refreshes',
      () async {
    final api = _Api();
    final cache = BookDetailsCache();
    final first = BookDetailState(api, 'book', cache: cache);
    await first.load();
    first.dispose();
    final second = BookDetailState(api, 'book', cache: cache);
    addTearDown(second.dispose);
    expect(second.loading, isFalse);
    expect(second.book?.title, '旧标题');
    expect(second.chapters.single.id, 'chapter');
    api.title = '服务端新标题';
    api.gate = Completer<void>();
    final refresh = second.load();
    expect(second.loading, isFalse);
    expect(second.book?.title, '旧标题');
    api.gate!.complete();
    await refresh;
    expect(second.book?.title, '服务端新标题');
  });

  test('failed background refresh preserves cached content', () async {
    final api = _Api();
    final cache = BookDetailsCache();
    final first = BookDetailState(api, 'book', cache: cache);
    await first.load();
    first.dispose();
    api.fail = true;
    final second = BookDetailState(api, 'book', cache: cache);
    addTearDown(second.dispose);
    await second.load();
    expect(second.loading, isFalse);
    expect(second.book?.title, '旧标题');
    expect(second.chapters.single.id, 'chapter');
    expect(second.error, isNotNull);
  });

  test('cache keys isolate servers and accounts', () async {
    final api = _Api();
    final cache = BookDetailsCache();
    final first = BookDetailState(api, 'book',
        cache: cache, cacheKey: 'server:user:book');
    await first.load();
    first.dispose();
    final other = BookDetailState(api, 'book',
        cache: cache, cacheKey: 'server:other:book');
    addTearDown(other.dispose);
    expect(other.loading, isTrue);
    expect(other.book, isNull);
  });

  test('force refresh cannot be undone by a previous state', () async {
    final api = _Api();
    final cache = BookDetailsCache();
    final first = BookDetailState(api, 'book', cache: cache);
    await first.load();
    cache.clear();
    await first.load();
    first.dispose();
    final second = BookDetailState(api, 'book', cache: cache);
    addTearDown(second.dispose);
    expect(second.loading, isTrue);
    expect(second.book, isNull);
  });
}
