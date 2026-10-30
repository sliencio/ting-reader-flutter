import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ting_reader_flutter/src/core/api/api_client.dart';
import 'package:ting_reader_flutter/src/core/services/listening_progress_sync.dart';
import 'package:ting_reader_flutter/src/core/state/books_state.dart';

class _Api extends ApiClient {
  final calls = <String>[];
  final writes = <Map<String, dynamic>>[];
  int contentVersion = 1;
  int readingVersion = 1;
  int progressVersion = 1;
  String title = 'Initial';
  bool conflict = false;
  Map<String, dynamic> remote = {
    'book_id': 'book',
    'chapter_id': 'chapter',
    'position': 10,
    'revision': 1,
    'updated_at': '2000-01-01T00:00:00Z'
  };
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? params, CancelToken? cancelToken}) async {
    calls.add(path);
    final dynamic data = path.endsWith('/revision')
        ? {
            'instance': 'server',
            'content_revision': contentVersion,
            'reading_revision': readingVersion,
            'progress_revision': progressVersion
          }
        : path.startsWith('/api/progress/')
            ? Map<String, dynamic>.of(remote)
            : path.endsWith('/chapters')
                ? {
                    'chapters': [
                      {
                        'id': 'chapter',
                        'book_id': 'book',
                        'title': 'Chapter',
                        'is_read': readingVersion > 1
                      }
                    ],
                    'total': 1,
                    'main_total': 1,
                    'extra_total': 0,
                    'offset': 0,
                    'limit': 100
                  }
                : path == '/api/settings'
                    ? {'settings_json': <String, dynamic>{}}
                    : {'id': 'book', 'library_id': 'library', 'title': title};
    return Response(requestOptions: RequestOptions(path: path), data: data);
  }

  @override
  Future<Response<dynamic>> post(String path,
      {Object? data,
      Map<String, dynamic>? params,
      CancelToken? cancelToken,
      Duration? receiveTimeout}) async {
    final value = Map<String, dynamic>.of(data as Map<String, dynamic>);
    writes.add(value);
    if (conflict) {
      conflict = false;
      remote = {...remote, 'position': 90, 'revision': 2};
      throw DioException(
          requestOptions: RequestOptions(path: path),
          response: Response(
              requestOptions: RequestOptions(path: path),
              statusCode: 409,
              data: {'code': 'PROGRESS_CONFLICT', 'current': remote}));
    }
    expect(value['base_revision'], remote['revision']);
    remote = {
      ...value,
      'revision': (remote['revision'] as int) + 1,
      'updated_at': '2000-01-01T00:00:00Z'
    };
    return Response(requestOptions: RequestOptions(path: path), data: remote);
  }
}

PendingListeningProgress _pending(double position) => PendingListeningProgress(
    bookId: 'book',
    chapterId: 'chapter',
    position: position,
    duration: 100,
    updatedAt: DateTime.utc(2026, 10, 30));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('版本未变化时只校验轻量接口，变化后刷新目录且保留缓存首屏', () async {
    final api = _Api();
    final cache = BookDetailsCache();
    final first = BookDetailState(api, 'book', cache: cache);
    await first.load();
    first.dispose();
    final second = BookDetailState(api, 'book', cache: cache);
    addTearDown(second.dispose);
    expect(second.loading, isFalse);
    expect(second.book?.title, 'Initial');
    api.calls.clear();
    await second.load();
    expect(api.calls, ['/api/books/book/revision']);
    expect(second.chapters.single.id, 'chapter');
    api.title = 'Forced';
    await second.load(force: true);
    expect(second.book?.title, 'Forced');
    api.contentVersion++;
    api.readingVersion++;
    api.title = 'Changed';
    await second.load();
    expect(second.book?.title, 'Changed');
    expect(second.chapters.single.isRead, isTrue);
    final third = BookDetailState(api, 'book', cache: cache);
    addTearDown(third.dispose);
    expect(third.loading, isFalse);
    expect(third.book?.title, 'Changed');
  });
  test('GET 与 POST 之间发生并发更新时保留待同步，明确选本机后再写入', () async {
    final api = _Api()..conflict = true;
    final sync = ListeningProgressSync(
        api: api, identity: () => 'owner', canSync: () => true);
    addTearDown(sync.dispose);
    await sync.record(_pending(20));
    await sync.flush();
    expect(sync.pendingCount, 1);
    expect(sync.conflicts['book']?.revision, 2);
    expect(api.writes.single['base_revision'], 1);
    expect(api.writes.single['device_id'], isNotEmpty);
    await sync.resolve('book', useRemote: false);
    expect(sync.pendingCount, 0);
    expect(sync.conflicts, isEmpty);
    expect(api.writes.last['base_revision'], 2);
    expect(api.remote['position'], 20);
  });
  test('重启后保留确认过的版本，服务器时间较旧也不能覆盖其他设备进度', () async {
    final api = _Api();
    ListeningProgressSync create() => ListeningProgressSync(
        api: api, identity: () => 'owner', canSync: () => true);
    final first = create();
    await first.record(_pending(20));
    await first.flush();
    first.dispose();
    api.remote = {...api.remote, 'position': 80, 'revision': 8};
    final second = create();
    addTearDown(second.dispose);
    await second.record(_pending(30));
    await second.flush();
    expect(api.writes.length, 1);
    expect(second.pendingCount, 1);
    expect(second.conflicts['book']?.position, 80);
    final remote = await second.resolve('book', useRemote: true);
    expect(remote?.revision, 8);
    expect(second.pendingCount, 0);
  });
  test('延迟到达的本机通知不能回退已确认版本', () async {
    final api = _Api();
    final sync = ListeningProgressSync(
        api: api, identity: () => 'owner', canSync: () => true);
    addTearDown(sync.dispose);
    await sync.record(_pending(20));
    await sync.flush();
    await sync.observeRemote({
      ...api.remote,
      'position': 10,
      'revision': 1,
      'device_id': api.writes.single['device_id']
    });
    await sync.record(_pending(30));
    await sync.flush();
    expect(sync.conflicts, isEmpty);
    expect(sync.pendingCount, 0);
    expect(api.writes.last['base_revision'], 2);
  });
  for (final adopted in [false, true]) {
    test('远端通知只有实际采用位置后才推进本机基线（$adopted）', () async {
      final api = _Api();
      final sync = ListeningProgressSync(
          api: api, identity: () => 'owner', canSync: () => true);
      addTearDown(sync.dispose);
      await sync.record(_pending(20));
      await sync.flush();
      api.remote = {
        ...api.remote,
        'position': 80,
        'revision': 3,
        'device_id': 'other-device'
      };
      await sync.observeRemote(api.remote, applyRemote: () => adopted);
      await sync.record(_pending(adopted ? 85 : 30));
      await sync.flush();
      expect(sync.conflicts.isEmpty, adopted);
      expect(sync.pendingCount, adopted ? 0 : 1);
    });
  }
}
