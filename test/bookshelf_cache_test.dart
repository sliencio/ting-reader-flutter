import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ting_reader_flutter/src/core/api/api_client.dart';
import 'package:ting_reader_flutter/src/core/services/bookshelf_cache.dart';
import 'package:ting_reader_flutter/src/core/state/books_state.dart';

class _ShelfApi extends ApiClient {
  Future<void>? gate;
  bool fail = false;
  String title = '原书籍';

  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? params, CancelToken? cancelToken}) async {
    await gate;
    if (fail) throw StateError('离线');
    return Response(
        requestOptions: RequestOptions(path: path),
        data: switch (path) {
          '/api/settings' => {
              'settings_json': {'bookshelf_sort_by': 'title'},
              'bookshelf_library_id': 'library',
              'private_setting': '不应缓存',
            },
          '/api/libraries' => [
              {'id': 'library', 'name': '书库', 'password': '不应缓存'},
            ],
          '/api/books' => [
              {'id': 'book', 'library_id': 'library', 'title': title},
            ],
          '/api/v1/series' => [
              {
                'id': 'series',
                'library_id': 'library',
                'title': '系列',
                'books': []
              },
            ],
          _ => [],
        });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> waitFor(bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ready(), isTrue);
  }

  test('书架重建后先显示本地缓存，后台结果到达后更新', () async {
    final api = _ShelfApi()..sessionIdentity = () => '服务器甲:账号甲';
    addTearDown(api.close);
    final first = BookshelfState(api);
    await first.load();
    await waitFor(() => !first.loading);
    await Future<void>.delayed(Duration.zero);
    first.dispose();

    final gate = Completer<void>();
    api.gate = gate.future;
    api.title = '更新后的书籍';
    final restored = BookshelfState(api);
    addTearDown(restored.dispose);
    final pending = restored.load();
    await waitFor(() => restored.hasSnapshot);
    expect(restored.loading, isFalse);
    expect(restored.books.single.title, '原书籍');
    expect(restored.series.single.title, '系列');
    expect(restored.selectedLibrary, 'library');
    expect(restored.sortBy, 'title');
    expect(restored.settings.containsKey('private_setting'), isFalse);
    final cache = await BookshelfCache().read('服务器甲:账号甲');
    expect(
        (cache!['libraries'] as List).single.containsKey('password'), isFalse);
    gate.complete();
    await pending;
    expect(restored.books.single.title, '更新后的书籍');
  });

  test('刷新保留书架，离线失败保留缓存，空书架也可恢复', () async {
    final api = _ShelfApi();
    addTearDown(api.close);
    final shelf = BookshelfState(api);
    addTearDown(shelf.dispose);
    await shelf.load();
    final gate = Completer<void>();
    api.gate = gate.future;
    api.fail = true;
    shelf.selectedLibrary = '切换中的书库';
    final refresh = shelf.load();
    expect(shelf.loading, isFalse);
    expect(shelf.books.single.title, '原书籍');
    gate.complete();
    await refresh;
    expect(shelf.selectedLibrary, 'library');
    expect(shelf.books.single.title, '原书籍');
    expect(shelf.error, isNotNull);
    await BookshelfCache().write('空书架', {
      'books': [],
      'series': [],
      'libraries': [],
      'settings': {},
    });
    api.sessionIdentity = () => '空书架';
    await shelf.load();
    expect(shelf.hasSnapshot, isTrue);
    expect(shelf.books, isEmpty);
    expect(shelf.loading, isFalse);
  });

  test('切换账号不串缓存，旧请求返回不能覆盖新账号', () async {
    var identity = '账号甲';
    final api = _ShelfApi()..sessionIdentity = () => identity;
    addTearDown(api.close);
    final shelf = BookshelfState(api);
    addTearDown(shelf.dispose);
    await shelf.load();
    final gate = Completer<void>();
    api.gate = gate.future;
    final old = shelf.load();
    identity = '账号乙';
    api.gate = null;
    api.fail = true;
    await shelf.load();
    expect(shelf.hasSnapshot, isFalse);
    expect(shelf.books, isEmpty);
    gate.complete();
    await old;
    expect(shelf.books, isEmpty);
    expect(await BookshelfCache().read('账号乙'), isNull);
  });

  test('损坏缓存忽略并从服务端重新加载', () async {
    final prefs = await SharedPreferences.getInstance();
    await BookshelfCache().write('损坏', {
      'books': [],
      'series': [],
      'libraries': [],
      'settings': {},
    });
    await prefs.setString(prefs.getKeys().single, '{');
    final api = _ShelfApi()..sessionIdentity = () => '损坏';
    addTearDown(api.close);
    final shelf = BookshelfState(api);
    addTearDown(shelf.dispose);
    await shelf.load();
    expect(shelf.books.single.title, '原书籍');
    expect(shelf.error, isNull);
  });
}
