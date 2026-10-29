part of '../download_state.dart';

extension SmartDownloads on DownloadState {
  int get automaticCacheBytes =>
      _downloads.values
          .where((item) => item.automatic)
          .fold(0, (sum, item) => sum + item.fileSize) +
      _tasks.values
          .where((task) =>
              task.automatic &&
              task.status != DownloadStatus.completed &&
              !_downloads.containsKey(task.storageKey))
          .fold(0, (sum, task) => sum + task.receivedBytes);

  bool get _automaticAllowed =>
      smartCache.enabled &&
      !appState.offlineMode &&
      !network.offline &&
      (!smartCache.wifiOnly || network.unmetered);

  String? get smartCacheWaitingReason {
    if (!smartCache.enabled) return null;
    if (appState.offlineMode || network.offline) {
      return appState.textForLocale(
          '离线中，等待联网', 'Offline; waiting for a connection');
    }
    if (smartCache.wifiOnly && !network.unmetered) {
      return appState.textForLocale(
          '等待 Wi-Fi 或有线网络', 'Waiting for Wi-Fi or Ethernet');
    }
    if (_capacityBlocked.isNotEmpty ||
        automaticCacheBytes >= smartCache.maxBytes) {
      return appState.textForLocale(
          '自动缓存已达容量上限', 'Automatic cache limit reached');
    }
    return null;
  }

  Future<void> setSmartCachePolicy(SmartCachePolicy policy) async {
    await initialize();
    if (_disposed) return;
    smartCache = policy;
    _capacityBlocked.clear();
    _stopDisallowedTransfers();
    await _saveIndex();
    await refreshSmartCache();
    _notifyIfActive();
  }

  void updatePlaybackContext(
      Book book, List<Chapter> chapters, String chapterId) {
    _cacheBook = book;
    _cacheChapters = List.of(chapters);
    _cacheChapterId = chapterId;
    _cacheServerKey = _currentServerKey;
    _capacityBlocked.clear();
    unawaited(refreshSmartCache());
  }

  Future<void> markChapterPlayed(String chapterId) async {
    final key = _currentRecordKey(chapterId);
    _playedKeys.add(key);
    await _saveIndex();
    await refreshSmartCache();
  }

  Future<void> keepChapter(String chapterId) async {
    final key = _downloadKeyFor(chapterId);
    final item = _downloads[key];
    if (item?.automatic == true) {
      _downloads[key!] =
          LocalDownload.fromJson({...item!.toJson(), 'automatic': false});
    }
    final task = taskForChapter(chapterId);
    if (task != null) task.automatic = false;
    if (item != null || task != null) {
      _capacityBlocked.remove(task?.storageKey);
      await _saveIndex();
      _notifyIfActive();
      _pumpQueue();
    }
  }

  Future<void> refreshSmartCache() {
    final work =
        _cacheWork.catchError((_) {}).then((_) => _maintainSmartCache());
    _cacheWork = work.catchError((Object error) {
      debugPrint('智能缓存维护失败：$error');
    });
    return _cacheWork;
  }

  Future<void> _maintainSmartCache() async {
    if (_disposed || kIsWeb || _storage.directory == null) return;
    final protectedKey = _cacheServerKey == null || _cacheChapterId == null
        ? null
        : downloadRecordKey(_cacheServerKey!, _cacheChapterId!);
    if (smartCache.enabled && smartCache.deletePlayed) {
      final removable = _downloads.values
          .where((item) =>
              item.automatic &&
              item.storageKey != protectedKey &&
              _playedKeys.contains(item.storageKey))
          .map((item) => item.storageKey)
          .toList();
      for (final key in removable) {
        if (_disposed) return;
        await deleteChapter(key);
      }
    }
    final book = _cacheBook;
    final currentId = _cacheChapterId;
    if (book == null ||
        currentId == null ||
        _cacheServerKey != _currentServerKey) {
      return;
    }
    final window = smartCache.window(_cacheChapters, currentId);
    final wanted =
        window.map((chapter) => _currentRecordKey(chapter.id)).toSet();
    // 切书或缩小缓存范围时取消多余的自动任务，手动任务不受影响。
    final stale = _tasks.values
        .where((task) =>
            task.automatic &&
            task.status != DownloadStatus.completed &&
            (!smartCache.enabled || !wanted.contains(task.storageKey)))
        .map((task) => task.storageKey)
        .toList();
    for (final key in stale) {
      if (_disposed) return;
      await deleteTask(key);
    }
    if (!_automaticAllowed) return;
    // 容量不足时只淘汰自动缓存，保留当前章节和手动下载。
    final old = _downloads.values
        .where((item) =>
            item.automatic &&
            item.storageKey != protectedKey &&
            !wanted.contains(item.storageKey))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final waiting = _tasks.values
        .where((task) =>
            task.automatic &&
            _capacityBlocked.contains(task.storageKey) &&
            wanted.contains(task.storageKey) &&
            task.totalBytes > 0 &&
            task.totalBytes <= smartCache.maxBytes)
        .firstOrNull;
    final neededBytes = waiting?.totalBytes ?? 0;
    for (final item in old) {
      if (_disposed ||
          (automaticCacheBytes < smartCache.maxBytes &&
              smartCache.maxBytes - automaticCacheBytes >= neededBytes)) {
        break;
      }
      await deleteChapter(item.storageKey);
    }
    for (final task in _tasks.values) {
      if (task.totalBytes > 0 &&
          task.totalBytes <= smartCache.maxBytes - automaticCacheBytes) {
        _capacityBlocked.remove(task.storageKey);
      }
    }
    final excess = _downloads.values
        .where((item) => item.automatic && item.storageKey != protectedKey)
        .toList()
      ..sort((a, b) => b.chapterIndex.compareTo(a.chapterIndex));
    for (final item in excess) {
      if (_disposed || automaticCacheBytes <= smartCache.maxBytes) break;
      await deleteChapter(item.storageKey);
    }
    for (final chapter in window) {
      if (_disposed ||
          !_automaticAllowed ||
          _cacheBook?.id != book.id ||
          _cacheChapterId != currentId ||
          _cacheServerKey != _currentServerKey) {
        return;
      }
      if (_playedKeys.contains(_currentRecordKey(chapter.id)) &&
          chapter.id != currentId) {
        continue;
      }
      if (canQueueChapter(chapter.id)) {
        queueChapter(book, chapter, automatic: true);
      }
    }
    _pumpQueue();
    _notifyIfActive();
  }

  void _stopDisallowedTransfers() {
    for (final task in _tasks.values) {
      if (appState.offlineMode || (task.automatic && !_automaticAllowed)) {
        final token = _tokens[task.storageKey];
        if (token != null && !token.isCancelled) {
          _policyBlocked.add(task.storageKey);
          token.cancel('等待允许的网络');
        }
      }
    }
  }

  void _networkChanged() {
    if (_disposed) return;
    _stopDisallowedTransfers();
    unawaited(refreshSmartCache());
    _pumpQueue();
    _notifyIfActive();
  }

  void _downloadAppChanged() => _networkChanged();
}
