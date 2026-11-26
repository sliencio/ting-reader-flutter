import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ting_reader_flutter/src/core/api/api_client.dart';
import 'package:ting_reader_flutter/src/core/models/models.dart';
import 'package:ting_reader_flutter/src/core/services/listening_progress_sync.dart';

class _LatestApi extends ApiClient {
  final writes = <Map<String, dynamic>>[];
  Map<String, dynamic> head = {
    'book_id': 'book',
    'chapter_id': 'third',
    'position': 15,
    'updated_at': '2026-11-26T10:03:00Z',
    'revision': 3,
    'latest_wins': true,
  };
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? params, CancelToken? cancelToken}) async =>
      Response(requestOptions: RequestOptions(path: path), data: Map.of(head));

  @override
  Future<Response<dynamic>> post(String path,
      {Object? data,
      Map<String, dynamic>? params,
      CancelToken? cancelToken,
      Duration? receiveTimeout}) async {
    final value = Map<String, dynamic>.from(data! as Map);
    writes.add(value);
    if (DateTime.parse(value['listened_at'] as String)
        .isAfter(DateTime.parse(head['updated_at'] as String))) {
      head = {
        ...value,
        'updated_at': value['listened_at'],
        'revision': (head['revision'] as int) + 1,
        'latest_wins': true
      };
    }
    return Response(
        requestOptions: RequestOptions(path: path), data: Map.of(head));
  }
}

PendingListeningProgress _progress(
        String chapter, double position, int minute) =>
    PendingListeningProgress(
        bookId: 'book',
        chapterId: chapter,
        position: position,
        duration: 100,
        updatedAt: DateTime.utc(2026, 11, 26, 10, minute));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('新服务端按实际时间选择位置，同时保留离线期间每章的补传', () async {
    final api = _LatestApi();
    final adopted = <ProgressItem>[];
    final sync = ListeningProgressSync(
        api: api,
        identity: () => 'owner',
        canSync: () => true,
        onRemoteProgress: adopted.add);
    addTearDown(sync.dispose);
    await sync.record(_progress('first', 90, 1));
    await sync.record(_progress('second', 95, 2));
    final report = await sync.syncNow();
    expect(report.succeeded, isTrue);
    expect(sync.conflicts, isEmpty);
    expect(api.writes.map((item) => item['chapter_id']), ['first', 'second']);
    expect(api.writes.map((item) => item['listened_at']),
        ['2026-11-26T10:01:00.000Z', '2026-11-26T10:02:00.000Z']);
    expect(api.head['chapter_id'], 'third');
    expect(api.head['position'], 15);
    expect(adopted.last.chapterId, 'third');
  });

  test('最近的回听位置可以更靠前，不按章节或进度最大值选择', () async {
    final api = _LatestApi();
    final sync = ListeningProgressSync(
        api: api, identity: () => 'owner', canSync: () => true);
    addTearDown(sync.dispose);
    await sync.record(_progress('first', 5, 4));
    await sync.flush();
    expect(api.head['chapter_id'], 'first');
    expect(api.head['position'], 5);
    expect(sync.pendingCount, 0);
  });

  test('实时收到更新位置后，旧章节仍补传且不会覆盖最新续播位置', () async {
    final api = _LatestApi();
    ProgressItem? adopted;
    final sync = ListeningProgressSync(
        api: api,
        identity: () => 'owner',
        canSync: () => true,
        onRemoteProgress: (item) => adopted = item);
    addTearDown(sync.dispose);
    await sync.record(_progress('first', 90, 1));
    await sync.observeRemote({...api.head, 'device_id': 'phone'});
    expect(adopted?.chapterId, 'third');
    expect(sync.pendingCount, 1);
    await sync.flush();
    expect(api.writes.single['chapter_id'], 'first');
    expect(api.head['chapter_id'], 'third');
    expect(sync.pendingCount, 0);
  });

  test('其他设备恰好停在相同位置时，也不能漏传本机的设备和时间', () async {
    final api = _LatestApi();
    final sync = ListeningProgressSync(
        api: api, identity: () => 'owner', canSync: () => true);
    addTearDown(sync.dispose);
    await sync.record(_progress('third', 15, 4));
    await sync.observeRemote({...api.head, 'device_id': 'other-phone'});
    expect(sync.pendingCount, 1);
    await sync.flush();
    expect(api.writes.single['listened_at'], '2026-11-26T10:04:00.000Z');
    expect(api.head['updated_at'], '2026-11-26T10:04:00.000Z');
    expect(sync.pendingCount, 0);
  });

  for (final entry in {
    TargetPlatform.iOS: 'ios',
    TargetPlatform.android: 'android',
    TargetPlatform.windows: 'windows',
    TargetPlatform.macOS: 'macos',
  }.entries) {
    test('上报设备类型与实际平台一致：${entry.value}', () async {
      debugDefaultTargetPlatformOverride = entry.key;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final api = _LatestApi();
      final sync = ListeningProgressSync(
          api: api, identity: () => 'owner', canSync: () => true);
      addTearDown(sync.dispose);
      await sync.record(_progress('first', 5, 4));
      await sync.flush();
      expect(api.writes.single['device_type'], entry.value);
      expect(api.writes.single['device_id'], isNotEmpty);
    });
  }
}
