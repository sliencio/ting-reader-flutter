part of '../player_state.dart';

/// Audio source construction, local downloads and notification metadata.
extension _PlayerSources on PlayerState {
  /// [previousBook] 是本次切换前的书。预选会提前把 `currentBook` 指向新书，
  /// 因此不能用 `currentBook` 判断是否换书，否则会错误复用上一本的音频队列。
  bool _canReuseAudioQueue(
      Book? previousBook, Book book, List<Chapter> nextChapters) {
    if (!_usingAudioQueue ||
        _usingTranscodeStream ||
        error != null ||
        _audio.processingState == audio.ProcessingState.completed ||
        _audio.processingState == audio.ProcessingState.idle ||
        !identical(previousBook, book) ||
        _mediaAuthRevision != appState.api.authRevision ||
        chapters.length != nextChapters.length) {
      return false;
    }
    for (var index = 0; index < chapters.length; index++) {
      if (chapters[index].id != nextChapters[index].id ||
          chapters[index].path != nextChapters[index].path) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _seekExistingAudioQueue(
    Chapter chapter,
    int index, {
    required String? localPath,
    required double position,
  }) async {
    if (_failedQueueChapters.contains(chapter.id)) return false;
    final queue = _audio.audioSource;
    if (queue is! audio.ConcatenatingAudioSource ||
        index < 0 ||
        index >= chapters.length ||
        !_inQueue(index)) {
      return false;
    }
    final nativeIndex = _nativeIndexOf(index);
    if (nativeIndex < 0 || nativeIndex >= queue.children.length) return false;
    final source = queue.children[nativeIndex];
    final expected = localPath == null
        ? Uri.parse(streamUrl(chapter.id))
        : Uri.file(localPath);
    if (source is! audio.UriAudioSource || source.uri != expected) return false;
    try {
      // 音源和鉴权未变时直接切换队列索引，不重新加载整本书。
      await _audio.seek(Duration(milliseconds: (position * 1000).round()),
          index: nativeIndex);
      return true;
    } catch (_) {
      // 原生后端不支持队列跳转时，回退到原有的音源加载流程。
      return false;
    }
  }

  String _buildStreamUrl(
    String chapterId, {
    String? transcodeFormat,
    double? seek,
  }) {
    final token = appState.token;
    final params = <String>[
      if (token != null && token.isNotEmpty)
        'token=${Uri.encodeComponent(token)}',
      if (transcodeFormat != null && transcodeFormat.isNotEmpty)
        'transcode=${Uri.encodeComponent(transcodeFormat)}',
      if (seek != null && seek > 0) 'seek=${seek.floor()}',
    ];
    return '${appState.activeUrl}/api/stream/$chapterId'
        '${params.isEmpty ? '' : '?${params.join('&')}'}';
  }

  Future<void> _setAudioUrlWithRedirectRecovery(
    String Function() buildUrl, {
    required MediaItem mediaItem,
    Duration? initialPosition,
  }) async {
    final firstUrl = buildUrl();
    try {
      await _setAudioUrl(
        firstUrl,
        mediaItem,
        initialPosition: initialPosition,
      );
    } catch (_) {
      if (!appState.usesActiveOrigin(firstUrl)) rethrow;
      final previousActiveUrl = appState.activeUrl;
      final recoveredUrl = await appState.recoverActiveUrl();
      if (recoveredUrl == null ||
          recoveredUrl.isEmpty ||
          recoveredUrl == previousActiveUrl) {
        rethrow;
      }
      await _setAudioUrl(
        buildUrl(),
        mediaItem,
        initialPosition: initialPosition,
      );
    }
  }

  Future<void> _setAudioUrl(
    String url,
    MediaItem mediaItem, {
    Duration? initialPosition,
  }) async {
    final authRevision = appState.api.authRevision;
    if (kIsWeb) {
      await _audio.setAudioSource(
        audio.AudioSource.uri(Uri.parse(url), tag: mediaItem),
        initialPosition: initialPosition,
      );
      _mediaAuthRevision = authRevision;
      return;
    }
    final headers = _streamHeaders;
    await _audio.setAudioSource(
      audio.AudioSource.uri(
        Uri.parse(url),
        headers: headers.isEmpty ? null : headers,
        tag: mediaItem,
      ),
      initialPosition: initialPosition,
    );
    _mediaAuthRevision = authRevision;
  }

  Future<void> _setGatewaySingleChapterSource(
    Book book,
    Chapter chapter, {
    required String? localPath,
    required double position,
  }) async {
    final mediaItem = _mediaItemFor(book, chapter);
    if (localPath != null) {
      await _audio.setAudioSource(
        audio.AudioSource.uri(Uri.file(localPath), tag: mediaItem),
        initialPosition: Duration(
          milliseconds: (position * 1000).round(),
        ),
      );
      _mediaAuthRevision = appState.api.authRevision;
      return;
    }

    await _setAudioUrlWithRedirectRecovery(
      () => streamUrl(chapter.id),
      mediaItem: mediaItem,
      initialPosition: Duration(
        milliseconds: (position * 1000).round(),
      ),
    );
  }

  Future<void> _setFallbackTranscodeSource(
    Chapter chapter,
    MediaItem mediaItem,
    double seek,
  ) async {
    await _setMp3TranscodeSource(chapter, mediaItem, seek);
  }

  Future<void> _setMp3TranscodeSource(
    Chapter chapter,
    MediaItem mediaItem,
    double seek,
  ) async {
    await _setAudioUrlWithRedirectRecovery(
      () => streamUrl(
        chapter.id,
        transcodeFormat: 'mp3',
        seek: seek,
      ),
      mediaItem: mediaItem.copyWith(
        duration:
            chapter.duration > 0 ? Duration(seconds: chapter.duration) : null,
        extras: {
          ...?mediaItem.extras,
          'isTranscodedStream': true,
          'streamOffsetSeconds': seek,
        },
      ),
    );
  }

  Future<void> _setAudioQueueWithRedirectRecovery(
    Book book,
    List<Chapter> chapterList, {
    required int initialIndex,
    required Duration initialPosition,
  }) async {
    try {
      await _setAudioQueue(
        book,
        chapterList,
        initialIndex: initialIndex,
        initialPosition: initialPosition,
      );
    } catch (_) {
      final firstUrl = streamUrl(chapterList[initialIndex].id);
      if (!appState.usesActiveOrigin(firstUrl)) rethrow;
      final previousActiveUrl = appState.activeUrl;
      final recoveredUrl = await appState.recoverActiveUrl();
      if (recoveredUrl == null ||
          recoveredUrl.isEmpty ||
          recoveredUrl == previousActiveUrl) {
        rethrow;
      }
      await _setAudioQueue(
        book,
        chapterList,
        initialIndex: initialIndex,
        initialPosition: initialPosition,
      );
    }
  }

  Future<void> _setAudioQueue(
    Book book,
    List<Chapter> chapterList, {
    required int initialIndex,
    required Duration initialPosition,
  }) async {
    final authRevision = appState.api.authRevision;
    final headers = _streamHeaders;
    // 只把当前章节附近的一段装进原生队列。整本书一次性入队时，iOS 会为
    // 每一章同步创建 AVPlayerItem，1700 章的书首次起播要等上千次对象创建，
    // 这才是「点播放很久才出声」的来源；后续章节靠 _extendAudioQueue 在
    // 播放过程中追加。
    final windowStart =
        max(0, initialIndex - PlayerState._chaptersBeforeCurrentIndex);
    final windowEnd = min(
      chapterList.length,
      initialIndex + 1 + PlayerState._chaptersAfterCurrentIndex,
    );
    final window = chapterList.sublist(windowStart, windowEnd);
    final localPaths = await Future.wait([
      for (final chapter in window)
        _localFilePathFromChapter(chapter) == null
            ? downloadState.localPathForChapter(chapter.id)
            : Future.value(_localFilePathFromChapter(chapter)),
    ]);
    final sources = <audio.AudioSource>[
      for (var index = 0; index < window.length; index++)
        audio.AudioSource.uri(
          localPaths[index] == null
              ? Uri.parse(streamUrl(window[index].id))
              : Uri.file(localPaths[index]!),
          headers:
              localPaths[index] == null && headers.isNotEmpty ? headers : null,
          tag: _mediaItemFor(
            book,
            window[index],
            index: windowStart + index,
          ),
        ),
    ];
    ++_queueRevision;
    _queueOffset = windowStart;
    _queueCount = window.length;
    await _audio.setAudioSource(
      audio.ConcatenatingAudioSource(children: sources),
      initialIndex: initialIndex - windowStart,
      initialPosition: initialPosition,
    );
    _mediaAuthRevision = authRevision;
  }

  /// 当前章节快走完窗口时，把后面一段章节补进原生队列。
  ///
  /// 补章要串行：并发的 insertAll 会让原生队列下标错位。整体重建队列时会
  /// 递增 [_queueRevision]，这里据此丢弃过期的补章结果。
  Future<void> _extendAudioQueue() {
    final revision = _queueRevision;
    final next = _queueAppend.then((_) async {
      if (_disposed || revision != _queueRevision || !_usingAudioQueue) return;
      final book = currentBook;
      if (book == null) return;
      final queue = _audio.audioSource;
      if (queue is! audio.ConcatenatingAudioSource) return;
      final remaining = chapters.length - (_queueOffset + _queueCount);
      if (remaining <= 0) return;
      final take = min(remaining, PlayerState._chaptersAfterCurrentIndex);
      final start = _queueOffset + _queueCount;
      final batch = chapters.sublist(start, start + take);
      final headers = _streamHeaders;
      final localPaths = await Future.wait([
        for (final chapter in batch)
          _localFilePathFromChapter(chapter) == null
              ? downloadState.localPathForChapter(chapter.id)
              : Future.value(_localFilePathFromChapter(chapter)),
      ]);
      if (_disposed || revision != _queueRevision) return;
      final sources = <audio.AudioSource>[
        for (var index = 0; index < batch.length; index++)
          audio.AudioSource.uri(
            localPaths[index] == null
                ? Uri.parse(streamUrl(batch[index].id))
                : Uri.file(localPaths[index]!),
            headers: localPaths[index] == null && headers.isNotEmpty
                ? headers
                : null,
            tag: _mediaItemFor(book, batch[index], index: start + index),
          ),
      ];
      await queue.addAll(sources);
      if (revision != _queueRevision) return;
      _queueCount += take;
    });
    _queueAppend = next.catchError((Object failure) {
      debugPrint('追加播放队列失败：$failure');
    });
    return _queueAppend;
  }

  Map<String, String> get _streamHeaders {
    if (kIsWeb) return const {};
    // streamUrl already authenticates with its token query parameter.
    // just_audio caches the final redirect URI in its header proxy and
    // reapplies supplied headers on later Range requests. Forwarding our
    // Bearer token to a STRM origin can make that origin reject seeking.
    // Keep gateway headers/cookies needed to reach the server, but never
    // supply the redundant application Authorization header to media.
    return Map.of(appState.api.authHeaders)
      ..removeWhere((name, _) => name.toLowerCase() == 'authorization');
  }

  String? _localFilePathFromChapter(Chapter chapter) {
    final raw = chapter.path.trim();
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    // API chapter paths belong to the server, even when they are absolute.
    // Offline chapters explicitly use file URIs; indexed downloads are
    // resolved separately through DownloadState.
    if (uri != null && uri.scheme == 'file') return uri.toFilePath();
    return null;
  }

  MediaItem _mediaItemFor(
    Book book,
    Chapter chapter, {
    double streamOffset = 0,
    int? index,
  }) {
    final authorValue = book.author;
    final narratorValue = book.narrator;
    final artistParts = [
      if (narratorValue != null && narratorValue.trim().isNotEmpty)
        narratorValue.trim(),
      if (authorValue != null && authorValue.trim().isNotEmpty)
        authorValue.trim(),
    ];
    final artUri = _mediaArtUri(book);
    final artHeaders = artUri != null &&
            (artUri.scheme == 'http' || artUri.scheme == 'https') &&
            appState.usesActiveOrigin(artUri.toString())
        ? _streamHeaders
        : null;
    // iOS 依据 Now Playing 的队列信息决定耳机切歌手势是否可用，
    // 不上报时系统会把它当成单曲播放，右耳「下一曲」双击被直接丢弃。
    // 建队列时调用方已知下标，传进来即可：整本书逐章 indexWhere 是 O(n²)。
    final chapterIndex =
        index ?? chapters.indexWhere((item) => item.id == chapter.id);
    return MediaItem(
      id: chapter.id,
      album: book.title,
      title: chapter.title,
      artist: artistParts.isEmpty ? null : artistParts.join(' / '),
      duration:
          chapter.duration > 0 ? Duration(seconds: chapter.duration) : null,
      artUri: artUri,
      artHeaders: artHeaders == null || artHeaders.isEmpty ? null : artHeaders,
      extras: {
        'bookId': book.id,
        'chapterId': chapter.id,
        if (chapterIndex >= 0) 'queueIndex': chapterIndex,
        if (chapters.isNotEmpty) 'queueCount': chapters.length,
        if (streamOffset > 0) 'streamOffsetSeconds': streamOffset,
      },
    );
  }

  Uri? _mediaArtUri(Book book) {
    final cover = bookCoverUrl(appState, book).trim();
    if (cover.isEmpty) return null;
    if (cover.startsWith('file://')) return Uri.tryParse(cover);
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(cover) ||
        cover.startsWith('/data/') ||
        cover.startsWith('/storage/') ||
        cover.startsWith('/var/') ||
        cover.startsWith('/Users/')) {
      return Uri.file(cover);
    }
    return Uri.tryParse(cover);
  }
}
