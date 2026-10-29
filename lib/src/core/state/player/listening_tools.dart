part of '../player_state.dart';

extension ListeningTools on PlayerState {
  PlaybackResumeRecord? _listeningSnapshot() {
    final book = currentBook;
    final chapter = currentChapter;
    if (book == null || chapter == null || !currentTime.isFinite) return null;
    return PlaybackResumeRecord(
        book, List.of(chapters), chapter.id, currentTime, DateTime.now());
  }

  void _checkpointInBackground(String reason) {
    final record = _listeningSnapshot();
    if (record == null || _disposed) return;
    unawaited(_checkpoints
        .add(_currentResumeIdentity, PlaybackCheckpoint(record, reason))
        .catchError((Object failure) {
      debugPrint('保存进度保护点失败：$failure');
    }));
  }

  Future<List<PlaybackCheckpoint>> playbackCheckpoints() =>
      _checkpoints.read(_currentResumeIdentity);

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
    unawaited(downloadState
        .markChapterPlayed(chapter.id)
        .catchError((Object failure) {
      debugPrint('更新已听缓存失败：$failure');
    }));
  }

  void _onListeningConnectionChanged() {
    if (_disposed) return;
    unawaited(_progress.journal.flush());
    _notifyIfActive();
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
