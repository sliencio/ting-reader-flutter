import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ting_reader_flutter/src/core/services/cover_cache.dart';

void main() {
  late Directory directory;
  late CoverCache cache;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ting-cover-cache-');
    cache = CoverCache(directory: () async => directory);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('封面按服务器账号隔离，NAS路由和token切换复用同一缓存', () {
    final first = cache.key('NAS:reader',
        'https://relay.example/api/proxy/cover?path=book.jpg&token=old',
        serverResource: true);
    final second = cache.key('NAS:reader',
        'http://192.168.1.10/api/proxy/cover?path=book.jpg&token=new',
        serverResource: true);
    expect(first, second);
    expect(
        cache.key('other:reader',
            'https://relay.example/api/proxy/cover?path=book.jpg&token=old',
            serverResource: true),
        isNot(first));
  });

  test('并发读取合并请求，重启后从磁盘读取封面且不访问STRM来源', () async {
    final gate = Completer<List<int>>();
    var requests = 0;
    Future<List<int>> fetch() {
      requests++;
      return gate.future;
    }

    final first = cache.load('cover', fetch, version: '1');
    final second = cache.load('cover', fetch, version: '1');
    gate.complete([1, 2, 3]);
    final files = await Future.wait([first, second]);
    expect(requests, 1);
    expect(files[0]?.path, files[1]?.path);
    cache = CoverCache(directory: () async => directory);
    final restored = await cache.load('cover', () async {
      fail('封面已有磁盘缓存，不应再请求远端');
    }, version: '1');
    expect(await restored!.readAsBytes(), [1, 2, 3]);
  });

  test('封面URL不变但版本变化时更新图片，离线保留已有副本', () async {
    final old = await cache.load('cover', () async => [1], version: '1');
    final updated = await cache.load('cover', () async => [2], version: '2');
    expect(updated?.path, isNot(old?.path));
    expect(await updated!.readAsBytes(), [2]);
    final offline = await cache
        .load('cover', () async => throw StateError('离线'), version: '3');
    expect(await offline!.readAsBytes(), [2]);
  });

  test('冷启动发现封面版本变化，先显示磁盘副本再等待网络', () async {
    await cache.load('cover', () async => [1], version: '1');
    cache = CoverCache(directory: () async => directory);
    final cached = Completer<File>();
    final gate = Completer<List<int>>();
    final refresh =
        cache.load('cover', () => gate.future, version: '2', onCached: (file) {
      if (!cached.isCompleted) cached.complete(file);
    });
    expect(await (await cached.future).readAsBytes(), [1]);
    gate.complete([2]);
    expect(await (await refresh)!.readAsBytes(), [2]);
  });

  test('显式刷新会清除封面副本，旧的下载不能恢复已清空缓存', () async {
    final gate = Completer<List<int>>();
    final started = Completer<void>();
    final pending = cache.load('cover', () {
      started.complete();
      return gate.future;
    });
    await started.future;
    await cache.invalidate();
    gate.complete([1]);
    expect(await pending, isNull);
    final fresh = await cache.load('cover', () async => [2]);
    expect(await fresh!.readAsBytes(), [2]);
  });
}
