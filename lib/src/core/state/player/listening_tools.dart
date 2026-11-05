part of '../player_state.dart';

extension ListeningTools on PlayerState {
  PlaybackResumeRecord? _listeningSnapshot() {
    final book = currentBook;
    final chapter = currentChapter;
    if (book == null || chapter == null || !currentTime.isFinite) return null;
    return PlaybackResumeRecord(
        book, List.of(chapters), chapter.id, currentTime, DateTime.now());
  }

  void _checkpointInBackground(String reason,
      {PlaybackResumeRecord? snapshot, bool replace = false}) {
    final owner = _currentResumeIdentity;
    final record = snapshot ?? _listeningSnapshot();
    if (record == null || _disposed) return;
    unawaited(_checkpoints
        .add(owner, PlaybackCheckpoint(record, reason), replace: replace)
        .catchError((Object failure) {
      debugPrint('保存进度保护点失败：$failure');
    }));
  }

  /// 关键点：本地留一条进度找回记录，同时把位置推给服务端。
  ///
  /// 进度找回必须能从记录直接恢复，所以这里总存完整章节列表；只存单章的
  /// 快照恢复后队列里只有一章，切下一章会失败。
  ///
  /// [replace] 用于定时同步：只保留该书最新一条，避免挤占 20 条名额。
  void _syncKeyPoint(String reason, {bool replace = false}) {
    _checkpointInBackground(reason, replace: replace);
    unawaited(sendProgress());
  }

  void _applyCheckpointSettings() {
    final next = PlaybackCheckpointSettings.fromSettings(appState.settings);
    if (next == _checkpointSettings) return;
    _checkpointSettings = next;
    if (_audio.playing) _startIntervalSyncTimer();
  }

  PlaybackCheckpointSettings get checkpointSettings => _checkpointSettings;

  /// 睡眠定时结束：把最后真正播过的那一章节记进进度找回，并同步服务端。
  ///
  /// 按集数睡眠在切章时触发，此刻 [currentChapter] 已经是没播过的新章节，
  /// 所以调用方必须把切换前的快照传进来；分钟定时则传 null，用当前状态。
  void _syncSleepEnd([PlaybackResumeRecord? snapshot]) {
    final record = snapshot ?? _listeningSnapshot();
    if (record == null || _disposed) return;
    _checkpointInBackground('sleep_end', snapshot: record);
    final chapter = record.chapter;
    if (chapter == null) return;
    // 显式发送睡眠前的位置：此刻 currentChapter 可能已经是没播过的新章。
    unawaited(_progress.send((
      book: record.book,
      chapter: chapter,
      position: record.position,
      duration: chapter.duration.toDouble(),
    )));
  }

  Future<List<PlaybackCheckpoint>> playbackCheckpoints() =>
      _checkpoints.read(_currentResumeIdentity);

  void _recordChapterStartIfPlaying() {
    final book = currentBook;
    final chapter = currentChapter;
    if (book == null ||
        chapter == null ||
        _disposed ||
        _connectingPlayback ||
        _selectionPending ||
        _suppressPositionUpdates ||
        _applyingQueueStartSeek ||
        _stoppingForEpisodeSleep ||
        _gatewayReauthenticationPending ||
        !_audio.playing ||
        _audio.processingState != audio.ProcessingState.ready ||
        error != null) {
      return;
    }
    final owner = _currentResumeIdentity;
    if (_resumeIdentity != owner) return;
    if (_sleepUnplayedChapterId == chapter.id) _sleepUnplayedChapterId = null;
    final key = (owner: owner, book: book.id, chapter: chapter.id);
    if (_lastRecordedChapterStart == key) return;
    // 同一章再次起播算「开始播放」，换到别的章才算「下一章开始」。
    final resumedSameChapter = _lastPlayedChapterKey == key;
    _lastPlayedChapterKey = key;
    final settings = _checkpointSettings;
    _lastRecordedChapterStart = key;
    if (resumedSameChapter) {
      if (settings.onPlayStart) _syncKeyPoint('play_start');
      return;
    }
    if (settings.onChapterStart) _syncKeyPoint('chapter_start');
  }

  /// 曲目播到中间时记一次；每章只触发一次。
  void _recordChapterMiddleIfNeeded() {
    if (!_checkpointSettings.onChapterMiddle ||
        _disposed ||
        _connectingPlayback ||
        _selectionPending ||
        _suppressPositionUpdates ||
        _applyingQueueStartSeek ||
        !_audio.playing ||
        duration <= 0) {
      return;
    }
    final book = currentBook;
    final chapter = currentChapter;
    if (book == null || chapter == null || currentTime < duration / 2) return;
    final owner = _currentResumeIdentity;
    if (_resumeIdentity != owner) return;
    final key = (owner: owner, chapter: chapter.id);
    if (_middleRecordedKey == key) return;
    _middleRecordedKey = key;
    _syncKeyPoint('chapter_middle');
  }

  Future<void> restoreCheckpoint(PlaybackCheckpoint checkpoint) async {
    final record = checkpoint.record;
    final chapter = record.chapter;
    if (chapter == null) return;
    _checkpointInBackground('restore');
    _pausedAt = null;
    await _playChapter(record.book, record.chapters, chapter,
        startAt: record.position);
  }

  Future<void> setSmartRewind(int seconds) => appState.updateLocalSettings({
        'smart_rewind_seconds': seconds.clamp(0, 30),
      });

  Future<void> useDefaultBookSpeed() async {
    final book = currentBook;
    if (book == null) return;
    await _listeningPreferences.saveSpeed(
        _currentResumeIdentity, book.id, null);
    await setSpeed(
        _resolvePlaybackSpeedSetting(appState.settings,
            nested: asMap(appState.settings['settings_json'])),
        rememberBook: false);
  }

  Future<void> applyDefaultPlaybackSpeed() async {
    final book = currentBook;
    if (book != null) {
      await _applyBookSpeed(book);
    } else {
      await setSpeed(
          _resolvePlaybackSpeedSetting(appState.settings,
              nested: asMap(appState.settings['settings_json'])),
          rememberBook: false);
    }
  }

  Future<void> _applyBookSpeed(Book book) async {
    final identity = _currentResumeIdentity;
    final generation = _playGeneration;
    final saved = await _listeningPreferences.speed(identity, book.id);
    if (_disposed ||
        identity != _currentResumeIdentity ||
        generation != _playGeneration) {
      return;
    }
    await setSpeed(
        saved ??
            _resolvePlaybackSpeedSetting(appState.settings,
                nested: asMap(appState.settings['settings_json'])),
        rememberBook: false);
  }

  Future<void> _prepareSmartResume() async {
    if (_applyingSmartRewind || _pausedChapterId != currentChapter?.id) return;
    final pausedAt = _pausedAt;
    _pausedAt = null;
    final book = currentBook;
    final chapter = currentChapter;
    if (book == null || chapter == null) return;
    final target = ListeningPreferences.resumePosition(
        position: currentTime,
        intro: _introPositionFor(book, chapter).clamp(0, currentTime),
        pausedAt: pausedAt,
        now: DateTime.now(),
        seconds: smartRewindSeconds);
    if (target >= currentTime) return;
    _applyingSmartRewind = true;
    try {
      await _seekPlayback(target, resumeAfterSeek: false, syncProgress: false);
    } finally {
      _applyingSmartRewind = false;
    }
  }

  void _updateListeningCache() {
    final book = currentBook;
    final chapter = currentChapter;
    if (book != null && chapter != null) {
      downloadState.updatePlaybackContext(book, chapters, chapter.id);
    }
  }

  void _recordChapterFinished() {
    final chapter = currentChapter;
    if (chapter == null || _suppressPositionUpdates) return;
    final outro = currentBook?.skipOutro ?? 0;
    if (duration > 0 && _furthestChapterPosition < duration - outro - 2) return;
    final key = '$_currentResumeIdentity:${chapter.id}';
    if (!_finishedChapters.add(key)) return;
    if (_checkpointSettings.onChapterEnd) _syncKeyPoint('chapter_end');
    final book = currentBook;
    if (book != null) {
      unawaited(appState.chapterReadSync
          .mark(book.id, [chapter.id])
          .then((_) => appState.chapterReadSync.flush())
          .catchError((Object failure) {
            debugPrint('同步章节已读失败：$failure');
          }));
    }
    unawaited(downloadState
        .markChapterPlayed(chapter.id)
        .catchError((Object failure) {
      debugPrint('更新已听缓存失败：$failure');
    }));
  }

  void _onListeningConnectionChanged() {
    if (_disposed) return;
    _applyCheckpointSettings();
    unawaited(_progress.journal.flush());
    unawaited(appState.chapterReadSync.flush());
    _notifyIfActive();
  }

  void _onListeningNetworkChanged() {
    if (_disposed) return;
    _progress.connectionChanged();
    if (!downloadState.network.offline) unawaited(appState.checkSession());
    _onListeningConnectionChanged();
  }

  Future<void> resolveProgressConflict(String bookId,
      {required bool useRemote}) async {
    _checkpointInBackground('sync');
    if (useRemote && currentBook?.id == bookId) await pause();
    final remote =
        await _progress.journal.resolve(bookId, useRemote: useRemote);
    if (_disposed ||
        remote == null ||
        !useRemote ||
        currentBook?.id != bookId) {
      return;
    }
    final chapter =
        chapters.where((item) => item.id == remote.chapterId).firstOrNull;
    if (chapter == null) throw StateError('本机章节列表中未找到其他设备正在听的章节，请刷新书籍');
    _pausedAt = null;
    await _playChapter(currentBook!, chapters, chapter,
        startAt: remote.position, autoPlay: false);
  }
}
