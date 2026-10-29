import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ting_reader_flutter/src/core/models/models.dart';
import 'package:ting_reader_flutter/src/core/state/app_state.dart';
import 'package:ting_reader_flutter/src/core/state/download_state.dart';
import 'package:ting_reader_flutter/src/core/state/download/download_storage.dart';
import 'package:ting_reader_flutter/src/core/services/network_monitor.dart';

class DownloadAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final started = StreamController<RequestOptions>.broadcast();
  final pending = <Completer<ResponseBody>>[];
  bool closed = false;
  bool blocked = false;
  String? blockedHost;
  int status = 200;
  List<int>? payload;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    started.add(options);
    if (blocked || options.uri.host == blockedHost) {
      final response = Completer<ResponseBody>();
      pending.add(response);
      cancelFuture?.then((_) {
        if (!response.isCompleted) {
          response.completeError(DioException.requestCancelled(
            requestOptions: options,
            reason: 'cancelled',
          ));
        }
      });
      return response.future;
    }
    return ResponseBody.fromBytes(payload ?? utf8.encode('audio'), status,
        headers: {
          'content-type': ['audio/mpeg'],
          'content-length': ['${payload?.length ?? 5}'],
        });
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

const book = Book(id: 'book', libraryId: 'library', title: 'Book');
Chapter chapter(String id) => Chapter(
      id: id,
      bookId: 'book',
      title: 'Chapter $id',
      path: '$id.mp3',
      chapterIndex: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppState app;
  late DownloadState downloads;
  late DownloadAdapter adapter;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('ting-download-test-');
    app = AppState();
    app.serverUrl = 'http://server.test';
    app.activeUrl = app.serverUrl;
    adapter = DownloadAdapter();
    final network = NetworkMonitor(usePlatform: false);
    addTearDown(network.dispose);
    downloads = DownloadState(app,
        httpClient: Dio()..httpClientAdapter = adapter,
        networkMonitor: network);
    await downloads.setCacheDirectory(directory.path);
  });
  tearDown(() async {
    await downloads.close();
    await adapter.started.close();
    app.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> waitForDownloads(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('下载状态等待超时');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  List<Chapter> cacheChapters() =>
      List.generate(8, (i) => chapter('smart-$i').copyWith(chapterIndex: i));

  test('智能缓存仅在允许网络运行，缓存当前章和指定后续集数', () async {
    downloads.network.update(NetworkAccess.mobile);
    await downloads
        .setSmartCachePolicy(const SmartCachePolicy(enabled: true, ahead: 2));
    final chapters = cacheChapters();
    downloads.updatePlaybackContext(book, chapters, chapters.first.id);
    await downloads.refreshSmartCache();
    expect(adapter.requests, isEmpty);
    expect(downloads.smartCacheWaitingReason, contains('Wi-Fi'));
    downloads.network.update(NetworkAccess.wifi);
    await waitForDownloads(() => downloads.downloads.length == 3);
    expect(downloads.downloads.map((item) => item.chapterId),
        ['smart-0', 'smart-1', 'smart-2']);
    expect(downloads.downloads.every((item) => item.automatic), isTrue);
  });

  test('自动缓存超过容量时停止并清理临时文件，手动下载不受限制', () async {
    adapter.payload = Uint8List(2 * 1024 * 1024);
    downloads.network.update(NetworkAccess.wifi);
    await downloads.setSmartCachePolicy(
        const SmartCachePolicy(enabled: true, ahead: 1, maxMegabytes: 1));
    final chapters = cacheChapters();
    downloads.updatePlaybackContext(book, chapters, chapters.first.id);
    await waitForDownloads(() =>
        adapter.requests.length >= 2 &&
        downloads.runningCount == 0 &&
        downloads.automaticCacheBytes == 0);
    expect(downloads.downloads, isEmpty);
    expect(downloads.automaticCacheBytes, 0);
    expect(downloads.failedCount, 0);
    expect(downloads.smartCacheWaitingReason, contains('容量'));
    final partials = await directory
        .list(recursive: true)
        .where((item) => item.path.endsWith('.part'))
        .toList();
    expect(partials, isEmpty);
    final saved = await downloads.downloadChapter(book, chapters.first);
    expect(saved.fileSize, 2 * 1024 * 1024);
    expect(saved.automatic, isFalse);
  });

  test('听完后删除自动缓存，保留当前文件并随章节推进补齐', () async {
    downloads.network.update(NetworkAccess.wifi);
    await downloads
        .setSmartCachePolicy(const SmartCachePolicy(enabled: true, ahead: 1));
    final chapters = cacheChapters();
    downloads.updatePlaybackContext(book, chapters, chapters.first.id);
    await waitForDownloads(() => downloads.downloads.length == 2);
    final path = downloads.findByChapter('smart-0')!.filePath;
    await downloads.markChapterPlayed('smart-0');
    expect(await File(path).exists(), isTrue);
    downloads.updatePlaybackContext(book, chapters, chapters[1].id);
    await downloads.refreshSmartCache();
    await waitForDownloads(() => downloads.hasChapter('smart-2'));
    expect(downloads.hasChapter('smart-0'), isFalse);
    expect(await File(path).exists(), isFalse);
    expect(downloads.downloads, hasLength(2));
  });

  test('保留已听缓存时容量不足可淘汰旧窗口，为新章节留出空间', () async {
    adapter.payload = Uint8List(450 * 1024);
    downloads.network.update(NetworkAccess.wifi);
    await downloads.setSmartCachePolicy(const SmartCachePolicy(
        enabled: true, ahead: 1, deletePlayed: false, maxMegabytes: 1));
    final chapters = cacheChapters();
    downloads.updatePlaybackContext(book, chapters, chapters.first.id);
    await waitForDownloads(() => downloads.downloads.length == 2);
    adapter.payload = Uint8List(700 * 1024);
    downloads.updatePlaybackContext(book, chapters, chapters[2].id);
    await waitForDownloads(() => downloads.hasChapter('smart-2'));
    expect(downloads.hasChapter('smart-0'), isFalse);
    expect(downloads.hasChapter('smart-1'), isFalse);
    expect(downloads.automaticCacheBytes, lessThanOrEqualTo(1024 * 1024));
  });

  test('手动保留自动缓存后不再自动删除，旧下载默认也为手动保留', () async {
    downloads.network.update(NetworkAccess.wifi);
    await downloads
        .setSmartCachePolicy(const SmartCachePolicy(enabled: true, ahead: 1));
    final chapters = cacheChapters();
    downloads.updatePlaybackContext(book, chapters, chapters.first.id);
    await waitForDownloads(() => downloads.downloads.length == 2);
    await downloads.requestChapter(book, chapters.first);
    expect(downloads.findByChapter('smart-0')!.automatic, isFalse);
    await downloads.markChapterPlayed('smart-0');
    downloads.updatePlaybackContext(book, chapters, chapters[1].id);
    await downloads.refreshSmartCache();
    expect(downloads.hasChapter('smart-0'), isTrue);
    final legacy = LocalDownload.fromJson(
        {...downloads.findByChapter('smart-0')!.toJson()}..remove('automatic'));
    expect(legacy.automatic, isFalse);
  });

  test('Wi-Fi 切换蜂窝会取消自动传输，恢复 Wi-Fi 后继续', () async {
    adapter.blocked = true;
    downloads.network.update(NetworkAccess.wifi);
    await downloads
        .setSmartCachePolicy(const SmartCachePolicy(enabled: true, ahead: 1));
    final chapters = cacheChapters();
    downloads.updatePlaybackContext(book, chapters, chapters.first.id);
    await waitForDownloads(() => adapter.requests.isNotEmpty);
    downloads.network.update(NetworkAccess.mobile);
    await waitForDownloads(() => downloads.runningCount == 0);
    expect(downloads.failedCount, 0);
    final previous = adapter.requests.length;
    await downloads.refreshSmartCache();
    expect(adapter.requests.length, previous);
    adapter.blocked = false;
    downloads.network.update(NetworkAccess.wifi);
    await waitForDownloads(() => downloads.downloads.length == 2);
    expect(downloads.failedCount, 0);
  });

  test('关闭智能缓存后手动下载仍正常，设置与分类跨重启保留', () async {
    downloads.network.update(NetworkAccess.wifi);
    await downloads.setSmartCachePolicy(const SmartCachePolicy(
        enabled: true, ahead: 3, deletePlayed: false, maxMegabytes: 500));
    final saved = await downloads.downloadChapter(book, chapter('manual'));
    expect(saved.automatic, isFalse);
    final storage = DownloadStorage();
    await storage.configureDirectory(directory.path, () {});
    final index = (await storage.readIndex(() {}))!;
    expect(index.smartCache.enabled, isTrue);
    expect(index.smartCache.ahead, 3);
    expect(index.smartCache.deletePlayed, isFalse);
    expect(index.smartCache.maxMegabytes, 500);
    expect(index.downloads.single.automatic, isFalse);
  });

  test(
      'one chapter entry deduplicates, resumes and recognizes completed downloads',
      () async {
    adapter.blocked = true;
    final started = adapter.started.stream.first;
    expect((await downloads.requestChapter(book, chapter('entry'))).outcome,
        DownloadRequestOutcome.queued);
    await started;
    expect((await downloads.requestChapter(book, chapter('entry'))).outcome,
        DownloadRequestOutcome.existing);
    expect(adapter.requests, hasLength(1));
    await downloads.pauseTask('entry');
    expect(
        (await downloads.requestChapter(book, chapter('entry'),
                resumeExisting: false))
            .outcome,
        DownloadRequestOutcome.existing);
    expect(downloads.taskForChapter('entry')!.status, DownloadStatus.paused);
    adapter.blocked = false;
    expect((await downloads.requestChapter(book, chapter('entry'))).outcome,
        DownloadRequestOutcome.resumed);
    final saved = await downloads.downloadChapter(book, chapter('entry'));
    expect(await File(saved.filePath).readAsString(), 'audio');
    expect((await downloads.requestChapter(book, chapter('entry'))).outcome,
        DownloadRequestOutcome.downloaded);
    expect(adapter.requests, hasLength(2));
  });

  test('invalid cache directory preserves the active cache and its preference',
      () async {
    final invalid = File('${directory.path}/not-a-directory');
    await invalid.writeAsString('owned fixture');
    await expectLater(
        downloads.setCacheDirectory(invalid.path), throwsStateError);
    expect(downloads.cacheDirectoryPath, directory.path);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('download_cache_directory'), directory.path);
    final saved = await downloads.downloadChapter(book, chapter('still-valid'));
    expect(await File(saved.filePath).readAsString(), 'audio');
  });

  test(
      'storage restores legacy records and interrupted tasks from their disk sizes',
      () async {
    final storage = DownloadStorage();
    await storage.configureDirectory(directory.path, () {});
    final audio = File('${directory.path}/legacy.mp3');
    await audio.writeAsString('saved');
    final indexFile = File('${directory.path}/downloads.json');
    final legacy = {
      'chapter_id': 'legacy',
      'book_id': 'book',
      'file_path': audio.path
    };
    await storage.writeJson(indexFile, [legacy]);
    final old = (await storage.readIndex(() {}))!;
    expect(old.downloads.single.serverKey, legacyDownloadServerKey);
    final partial = File('${directory.path}/partial.part');
    await partial.writeAsString('partial');
    await storage.writeJson(indexFile, {
      'downloads': [
        legacy,
        {
          ...legacy,
          'chapter_id': 'missing',
          'file_path': '${directory.path}/gone.mp3'
        }
      ],
      'tasks': [
        {
          'chapter_id': 'pending',
          'book_id': 'book',
          'chapter_path': 'pending.mp3',
          'status': 'downloading',
          'temp_path': partial.path,
          'total_bytes': 14,
        }
      ],
      'settings': {'max_concurrent_downloads': 20},
    });
    final restored = (await storage.readIndex(() {}))!;
    expect(restored.downloads, hasLength(1));
    expect(restored.tasks.single.status, DownloadStatus.queued);
    expect(restored.tasks.single.receivedBytes, 7);
    expect(restored.tasks.single.progress, 0.5);
    expect(restored.maxConcurrent, 6);
    await storage.flush();
  });

  test(
      'switching servers during setup preserves the queued source and credentials',
      () async {
    app.token = 'old-token';
    app.api.configure(baseUrl: app.activeUrl, token: app.token);
    final pending = downloads.downloadChapter(book, chapter('identity'));
    app.serverUrl = app.activeUrl = 'http://other.test';
    app.token = 'new-token';
    app.api.configure(baseUrl: app.activeUrl, token: app.token);
    final saved = await pending;
    expect(adapter.requests.single.uri.host, 'server.test');
    expect(adapter.requests.single.uri.queryParameters['token'], 'old-token');
    expect(
        adapter.requests.single.headers['Authorization'], 'Bearer old-token');
    expect(saved.serverKey, 'http://server.test');
  });

  test('offline playback restores the same metadata and uses local media paths',
      () async {
    const source = Book(
        id: 'book',
        libraryId: 'library',
        title: 'Book',
        author: 'Known author',
        narrator: 'Known narrator',
        libraryType: 'local',
        skipIntro: 12,
        skipOutro: 18,
        year: 2026);
    final saved = await downloads.downloadChapter(source, chapter('offline'));
    final restored = saved.toBook();
    expect(restored.author, source.author);
    expect(restored.narrator, source.narrator);
    expect(restored.skipIntro, 12);
    expect(restored.skipOutro, 18);
    expect(restored.year, 2026);
    expect(restored.canWriteMetadataFiles, isFalse);
    expect(saved.chapter.path.startsWith('file://'), isTrue);
    expect(saved.chapter.duration, chapter('offline').duration);
    final task = DownloadTask.fromBookChapter(source, chapter('offline'),
        serverKey: 'server');
    expect(task.book.author, restored.author);
    expect(task.book.skipOutro, restored.skipOutro);
    final withLocalCover = LocalDownload.fromJson({
      ...saved.toJson(),
      'local_cover_path': '${directory.path}/cover with spaces.jpg',
    });
    expect(withLocalCover.toBook().coverUrl,
        contains('cover%20with%20spaces.jpg'));
    expect(withLocalCover.toBook().coverUrl, startsWith('file://'));
  });

  test('cancelled queued disk writes cannot replace a valid snapshot',
      () async {
    final storage = DownloadStorage();
    final target = File('${directory.path}/cancelled-write.json');
    final first = storage.writeJson(target, {'valid': true});
    var active = true;
    final second = storage.writeJson(target, {'late': true}, checkActive: () {
      if (!active) throw StateError('closed owner');
    });
    final rejected = expectLater(second, throwsStateError);
    active = false;
    await first;
    await rejected;
    await storage.flush();
    expect(jsonDecode(await target.readAsString()), {'valid': true});
    expect(directory.listSync().where((file) => file.path.endsWith('.tmp')),
        isEmpty);
  });

  test('failure notifies all server-scoped waiters and does not hang',
      () async {
    adapter.status = 403;
    final first = downloads.downloadChapter(book, chapter('failed'));
    final second = downloads.downloadChapter(book, chapter('failed'));
    await Future.wait([
      expectLater(first, throwsStateError),
      expectLater(second, throwsStateError),
    ]).timeout(const Duration(seconds: 5));
    expect(downloads.failedCount, 1);
    expect(adapter.requests.length, 1);
  });

  test('dispose cancels blocked requests and never notifies after disposal',
      () async {
    adapter.blocked = true;
    final started = adapter.started.stream.first;
    final result = downloads.downloadChapter(book, chapter('blocked'));
    final assertion = expectLater(result, throwsStateError);
    await started;
    var changes = 0;
    downloads.addListener(() => changes++);
    downloads.dispose();
    await downloads.close().timeout(const Duration(seconds: 5));
    await assertion;
    expect(adapter.closed, isTrue);
    expect(changes, 0);
    expect(downloads.downloads, isEmpty);
    expect(
        () => downloads.queueChapter(book, chapter('late')), throwsStateError);
  });

  test('delete waits for the old transfer before recreating the same task',
      () async {
    adapter.blocked = true;
    final started = adapter.started.stream.first;
    final result = downloads.downloadChapter(book, chapter('repeat'));
    final assertion = expectLater(result, throwsStateError);
    await started;
    await downloads.deleteTask('repeat').timeout(const Duration(seconds: 5));
    await assertion;
    adapter.blocked = false;
    final saved = await downloads
        .downloadChapter(book, chapter('repeat'))
        .timeout(const Duration(seconds: 5));
    expect(await File(saved.filePath).readAsString(), 'audio');
    expect(downloads.downloads, hasLength(1));
  });

  for (final removeChapter in [false, true]) {
    test(
        'requeue during ${removeChapter ? "chapter" : "task"} deletion waits for cleanup',
        () async {
      adapter.blocked = true;
      final started = adapter.started.stream.first;
      final old = downloads.downloadChapter(book, chapter('concurrent-delete'));
      final oldAssertion = expectLater(old, throwsStateError);
      await started;
      final deleting = removeChapter
          ? downloads.deleteChapter('concurrent-delete')
          : downloads.deleteTask('concurrent-delete');
      adapter.blocked = false;
      final replacement =
          downloads.downloadChapter(book, chapter('concurrent-delete'));
      await deleting;
      await oldAssertion;
      final saved = await replacement.timeout(const Duration(seconds: 5));
      expect(await File(saved.filePath).readAsString(), 'audio');
      expect(downloads.downloads, hasLength(1));
    });
  }

  test('pause settles waiters and immediate resume starts a fresh transfer',
      () async {
    adapter.blocked = true;
    final started = adapter.started.stream.first;
    final result = downloads.downloadChapter(book, chapter('paused'));
    final assertion = expectLater(result, throwsStateError);
    await started;
    final pausing = downloads.pauseTask('paused');
    adapter.blocked = false;
    final resuming = downloads.resumeTask('paused');
    await Future.wait([pausing, resuming]);
    await assertion;
    final saved = await downloads
        .downloadChapter(book, chapter('paused'))
        .timeout(const Duration(seconds: 5));
    expect(await File(saved.filePath).readAsString(), 'audio');
    expect(downloads.downloads, hasLength(1));
  });

  test('concurrent chapters preserve every index and book chapter entry',
      () async {
    final saved = await Future.wait(List.generate(
        6, (index) => downloads.downloadChapter(book, chapter('$index'))));
    final index = jsonDecode(
        await File('${directory.path}/downloads.json').readAsString()) as Map;
    expect(index['downloads'], hasLength(6));
    final chapters = jsonDecode(
        await File('${File(saved.first.filePath).parent.path}/chapters.json')
            .readAsString()) as List;
    expect(chapters.map((item) => (item as Map)['id']).toSet(),
        {'0', '1', '2', '3', '4', '5'});
    await downloads.close();
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(downloads.downloads, hasLength(6));
  });

  test(
      'pause during cover caching keeps audio partial and omits external credentials',
      () async {
    app.api.configure(baseUrl: app.activeUrl, token: 'private-token');
    adapter.blockedHost = 'cover.test';
    final covering = adapter.started.stream
        .firstWhere((request) => request.uri.host == 'cover.test');
    const coveredBook = Book(
        id: 'book',
        libraryId: 'library',
        title: 'Book',
        coverUrl: 'https://cover.test/image.jpg');
    final result = downloads.downloadChapter(coveredBook, chapter('cover'));
    final assertion = expectLater(result, throwsStateError);
    final request = await covering;
    expect(request.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')));
    await downloads.pauseTask('cover');
    await assertion;
    final task = downloads.taskForChapter('cover')!;
    expect(await File(task.filePath!).exists(), isFalse);
    expect(await File(task.tempPath!).readAsString(), 'audio');
    expect(downloads.downloads, isEmpty);
  });

  test('an unsatisfiable empty request fails rather than endlessly requeueing',
      () async {
    adapter.status = 416;
    await expectLater(
        downloads.downloadChapter(book, chapter('range')), throwsStateError);
    expect(adapter.requests, hasLength(1));
    expect(downloads.failedCount, 1);
  });

  test('deleting a cached book preserves unrelated files in its directory',
      () async {
    final saved = await downloads.downloadChapter(book, chapter('owned'));
    final note = File('${File(saved.filePath).parent.path}/user-note.txt');
    await note.writeAsString('Keep this');
    await downloads.deleteBook('book');
    expect(await File(saved.filePath).exists(), isFalse);
    expect(await note.readAsString(), 'Keep this');
    expect(downloads.downloads, isEmpty);
  });

  test(
      'disk serialization recovers after a failure without losing later writes',
      () async {
    final storage = DownloadStorage();
    final target = File('${directory.path}/serialized.json');
    await target.writeAsString('{bad json');
    await expectLater(
        storage.updateJson(target, (_) => []), throwsFormatException);
    await storage.writeJson(target, <int>[]);
    await Future.wait(List.generate(
        20,
        (index) => storage.updateJson(
              target,
              (current) => [...current as List, index],
            )));
    await storage.flush();
    expect(jsonDecode(await target.readAsString()),
        List.generate(20, (index) => index));
    expect(directory.listSync().where((item) => item.path.endsWith('.tmp')),
        isEmpty);
  });
}
