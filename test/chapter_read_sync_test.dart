import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ting_reader_flutter/src/core/api/api_client.dart';
import 'package:ting_reader_flutter/src/core/models/chapter.dart';
import 'package:ting_reader_flutter/src/core/services/chapter_read_marks.dart';
import 'package:ting_reader_flutter/src/core/services/chapter_read_sync.dart';

class _Api extends ApiClient {
  final batches = <List<String>>[];
  int? failAt;
  int? status;
  Completer<void>? gate;
  @override
  Future<Response<dynamic>> post(String path,
      {Object? data,
      Map<String, dynamic>? params,
      CancelToken? cancelToken,
      Duration? receiveTimeout}) async {
    expect(path, '/api/books/book/chapters/read-status');
    final body = data as Map;
    expect(body['read'], isTrue);
    expect(body.containsKey('position'), isFalse);
    batches.add((body['chapter_ids'] as List).cast<String>());
    await gate?.future;
    if (failAt == batches.length || status != null) {
      throw DioException(
          requestOptions: RequestOptions(path: path),
          response: Response(
              requestOptions: RequestOptions(path: path),
              statusCode: status ?? 503));
    }
    return Response(
        requestOptions: RequestOptions(path: path), statusCode: 204);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('离线批量标记在重启后补传，账号和服务器保持隔离', () async {
    var owner = 'server:user';
    var online = false;
    final api = _Api();
    ChapterReadSync create() =>
        ChapterReadSync(api: api, identity: () => owner, canSync: () => online);
    final first = create();
    await first.mark('book', ['one', 'two']);
    await first.flush();
    expect(api.batches, isEmpty);
    first.dispose();
    final sync = create();
    addTearDown(sync.dispose);
    owner = 'other:user';
    online = true;
    await sync.flush();
    expect(api.batches, isEmpty);
    owner = 'server:other';
    await sync.flush();
    expect(api.batches, isEmpty);
    owner = 'server:user';
    await sync.flush();
    expect(api.batches.single, ['one', 'two']);
    expect(sync.pendingFor('book'), isEmpty);
    expect(sync.confirmedFor('book'), {'one', 'two'});
    sync.acceptSnapshot('book', ['one']);
    expect(sync.confirmedFor('book'), {'two'});
    await sync.flush();
    expect(api.batches.length, 1);
  });

  test('旧本机已读迁移、分批部分失败以及失败后的补传', () async {
    await ChapterReadMarksStore().write('owner:book', {'legacy'});
    final api = _Api()..failAt = 2;
    final sync =
        ChapterReadSync(api: api, identity: () => 'owner', canSync: () => true);
    addTearDown(sync.dispose);
    await sync.migrate('book');
    expect(sync.pendingFor('book'), {'legacy'});
    expect(await ChapterReadMarksStore().read('owner:book'), isEmpty);
    await sync.mark('book', List.generate(400, (i) => 'c$i'));
    await sync.flush();
    expect(api.batches.first.length, 200);
    expect(sync.pendingFor('book').length, 201);
    expect(sync.error, isNotNull);
    api.failAt = null;
    await sync.flush();
    expect(sync.pendingFor('book'), isEmpty);
    expect(sync.confirmedFor('book').length, 401);
    expect(sync.error, isNull);
  });

  test('旧服务端不回退写入播放进度，保留待同步并提示升级', () async {
    final api = _Api()..status = 404;
    final sync =
        ChapterReadSync(api: api, identity: () => 'owner', canSync: () => true);
    addTearDown(sync.dispose);
    await sync.mark('book', ['unknown-duration']);
    await sync.flush();
    expect(sync.pendingFor('book'), {'unknown-duration'});
    expect(sync.confirmedFor('book'), isEmpty);
    expect(sync.error, contains('升级服务端'));
  });

  test('上传期间切换账号，不删除旧账号待同步内容', () async {
    var owner = 'old';
    final api = _Api()..gate = Completer<void>();
    final sync =
        ChapterReadSync(api: api, identity: () => owner, canSync: () => true);
    addTearDown(sync.dispose);
    await sync.mark('book', ['one']);
    final upload = sync.flush();
    while (api.batches.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    owner = 'new';
    api.gate!.complete();
    await upload;
    await sync.flush();
    expect(sync.confirmedFor('book'), isEmpty);
    owner = 'old';
    await sync.flush();
    expect(api.batches.length, 2);
  });

  test('服务端已读不需要章节时长，旧服务端响应仍可解析', () {
    final chapter = Chapter.fromJson({'id': 'one', 'is_read': true});
    expect(chapter.isRead, isTrue);
    expect(chapter.copyWith(title: 'new').isRead, isTrue);
    expect(Chapter.fromJson({'id': 'old'}).isRead, isFalse);
  });
}
