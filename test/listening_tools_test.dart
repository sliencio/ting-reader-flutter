import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ting_reader_flutter/src/core/api/api_client.dart';
import 'package:ting_reader_flutter/src/core/models/models.dart';
import 'package:ting_reader_flutter/src/core/services/listening_preferences.dart';
import 'package:ting_reader_flutter/src/core/services/listening_progress_sync.dart';
import 'package:ting_reader_flutter/src/core/services/playback_checkpoints.dart';
import 'package:ting_reader_flutter/src/core/services/playback_resume_store.dart';
import 'package:ting_reader_flutter/src/core/state/download/smart_cache_policy.dart';

class _SyncApi extends ApiClient {
  final uploaded = <Map<String, dynamic>>[];
  final remote = <String, Map<String, dynamic>>{};
  bool fail = false;
  Future<void>? postGate;
  Future<void>? getGate;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? params, CancelToken? cancelToken}) async {
    await getGate;
    if (fail) throw StateError('连接失败');
    return Response(
        requestOptions: RequestOptions(path: path),
        data: remote[Uri.decodeComponent(path.split('/').last)] ?? {});
  }

  @override
  Future<Response<dynamic>> post(String path,
      {Object? data,
      Map<String, dynamic>? params,
      CancelToken? cancelToken,
      Duration? receiveTimeout}) async {
    if (fail) throw StateError('连接失败');
    final value = Map<String, dynamic>.from(data! as Map);
    uploaded.add(value);
    await postGate;
    remote[value['book_id'] as String] = {
      ...value,
      'updated_at': DateTime.now().toUtc().toIso8601String()
    };
    return Response(
        requestOptions: RequestOptions(path: path),
        data: remote[value['book_id']]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  PendingListeningProgress progress(String book, double position,
          {DateTime? at}) =>
      PendingListeningProgress(
          bookId: book,
          chapterId: 'chapter-$book',
          position: position,
          duration: 600,
          updatedAt: at ?? DateTime.now());

  test('智能回退只在长暂停后执行，并保留片头边界与用户关闭设置', () {
    final now = DateTime(2026, 10, 29, 12);
    double resume(int pausedSeconds, int rewind,
            {double position = 100, double intro = 30}) =>
        ListeningPreferences.resumePosition(
            position: position,
            intro: intro,
            pausedAt: now.subtract(Duration(seconds: pausedSeconds)),
            now: now,
            seconds: rewind);
    expect(resume(59, 10), 100);
    expect(resume(60, 10), 90);
    expect(resume(3600, 0), 100);
    expect(resume(90, 10, position: 35), 30);
  });

  test('每本书倍速隔离账号和服务端，允许恢复默认值', () async {
    final prefs = ListeningPreferences();
    await prefs.saveSpeed('server:user1', 'book', 1.6);
    await prefs.saveSpeed('server:user1', 'other', 1.2);
    expect(await prefs.speed('server:user1', 'book'), 1.6);
    expect(await prefs.speed('server:user2', 'book'), isNull);
    expect(await prefs.speed('other:user1', 'book'), isNull);
    await prefs.saveSpeed('server:user1', 'book', null);
    expect(await prefs.speed('server:user1', 'book'), isNull);
    expect(await prefs.speed('server:user1', 'other'), 1.2);
  });

  test('进度保护并发写入保留最新二十条，按账号隔离', () async {
    final store = PlaybackCheckpoints();
    const book = Book(id: 'book', libraryId: 'lib', title: '测试书');
    const chapter = Chapter(
        id: 'chapter',
        bookId: 'book',
        title: '第一章',
        path: '/audio.mp3',
        chapterIndex: 1);
    await Future.wait(List.generate(
        25,
        (i) => store.add(
            'owner',
            PlaybackCheckpoint(
                PlaybackResumeRecord(
                    book, [chapter], chapter.id, i * 10, DateTime.now()),
                'seek'))));
    final entries = await store.read('owner');
    expect(entries, hasLength(20));
    expect(entries.first.record.position, 240);
    expect(entries.last.record.position, 50);
    expect(await store.read('other'), isEmpty);
  });

  test('智能缓存窗口从当前章开始且不超出书籍末尾', () {
    final chapters = List.generate(
        6,
        (i) => Chapter(
            id: '$i',
            bookId: 'book',
            title: '$i',
            path: '/$i.mp3',
            chapterIndex: i));
    const policy = SmartCachePolicy(ahead: 2);
    expect(
        policy.window(chapters, '1').map((item) => item.id), ['1', '2', '3']);
    expect(policy.window(chapters, '5').map((item) => item.id), ['5']);
    expect(policy.window(chapters, 'missing'), isEmpty);
  });

  test('离线记录跨进程恢复，按书保留最新位置并补传所有书籍', () async {
    final api = _SyncApi();
    var online = false;
    var sync = ListeningProgressSync(
        api: api, identity: () => 'owner', canSync: () => online);
    await sync.record(progress('a', 10));
    await sync.record(progress('a', 30));
    await sync.record(progress('b', 50));
    await sync.flush();
    expect(api.uploaded, isEmpty);
    sync.dispose();
    sync = ListeningProgressSync(
        api: api, identity: () => 'owner', canSync: () => online);
    await sync.initialize();
    expect(sync.pendingCount, 2);
    online = true;
    await sync.flush();
    expect(api.uploaded.map((item) => item['position']), [30, 50]);
    expect(sync.pendingCount, 0);
    sync.dispose();
  });

  test('请求失败保留本机待同步记录，后续可重试', () async {
    final api = _SyncApi()..fail = true;
    final sync = ListeningProgressSync(
        api: api, identity: () => 'owner', canSync: () => true);
    await sync.record(progress('a', 23));
    await sync.flush();
    expect(sync.pendingCount, 1);
    expect(sync.error, isNotNull);
    api.fail = false;
    await sync.flush();
    expect(sync.pendingCount, 0);
    expect(sync.error, isNull);
    sync.dispose();
  });

  test('恢复收听的新位置不能抹掉离线期间形成的同步冲突', () async {
    final api = _SyncApi();
    final sync = ListeningProgressSync(
        api: api, identity: () => 'owner', canSync: () => true);
    await sync.record(progress('a', 30,
        at: DateTime.now().subtract(const Duration(hours: 2))));
    api.remote['a'] = progress('a', 300,
            at: DateTime.now().subtract(const Duration(hours: 1)))
        .toJson();
    await sync.record(progress('a', 35));
    expect(await sync.prepareRealtime('a'), isFalse);
    await sync.flush();
    expect(api.uploaded, isEmpty);
    expect(sync.conflicts.keys, ['a']);
    sync.dispose();
  });

  test('新远端进度阻止离线旧进度覆盖，用户可选择保留本机', () async {
    final api = _SyncApi();
    api.remote['a'] = {...progress('a', 300).toJson(), 'chapter_title': '第一章'};
    final sync = ListeningProgressSync(
        api: api, identity: () => 'owner', canSync: () => true);
    await sync.record(progress('a', 30,
        at: DateTime.now().subtract(const Duration(hours: 1))));
    expect(await sync.prepareRealtime('a'), isFalse);
    await sync.flush();
    expect(api.uploaded, isEmpty);
    expect(sync.conflicts.keys, ['a']);
    await sync.resolve('a', useRemote: false);
    expect(api.uploaded.single['position'], 30);
    expect(sync.pendingCount, 0);
    sync.dispose();
  });

  test('采用其他设备进度会重新读取服务端并保留其他书籍的离线记录', () async {
    final api = _SyncApi();
    final sync = ListeningProgressSync(
        api: api, identity: () => 'owner', canSync: () => true);
    await sync.record(progress('a', 30));
    await sync.record(progress('b', 50));
    api.remote['a'] = progress('a', 400).toJson();
    final remote = await sync.resolve('a', useRemote: true);
    expect(remote!.position, 400);
    expect(sync.hasPending('a'), isFalse);
    expect(sync.hasPending('b'), isTrue);
    expect(api.uploaded, isEmpty);
    sync.dispose();
  });

  test('上传期间产生新位置时，旧请求完成不能删除新记录', () async {
    final api = _SyncApi();
    final gate = Completer<void>();
    api.postGate = gate.future;
    final sync = ListeningProgressSync(
        api: api, identity: () => 'owner', canSync: () => true);
    await sync.record(progress('a', 10));
    final pending = sync.flush();
    while (api.uploaded.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await sync.record(progress('a', 90));
    gate.complete();
    await pending;
    expect(sync.pendingCount, 1);
    await sync.flush();
    expect(api.uploaded.last['position'], 90);
    expect(sync.pendingCount, 0);
    sync.dispose();
  });

  test('切换账号后不发送旧账号的离线进度', () async {
    final api = _SyncApi();
    var owner = 'first';
    final gate = Completer<void>();
    api.getGate = gate.future;
    final sync = ListeningProgressSync(
        api: api, identity: () => owner, canSync: () => true);
    await sync.record(progress('a', 10));
    final pending = sync.flush();
    await Future<void>.delayed(Duration.zero);
    owner = 'second';
    gate.complete();
    await pending;
    expect(api.uploaded, isEmpty);
    await sync.initialize();
    expect(sync.pendingCount, 0);
    owner = 'first';
    expect(sync.pendingCount, 1);
    sync.dispose();
  });
}
