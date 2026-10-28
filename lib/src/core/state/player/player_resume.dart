part of '../player_state.dart';

extension _PlayerResume on PlayerState {
  String get _currentResumeIdentity =>
      '${appState.serverUrl}:${appState.fnId}:${appState.user?.id}';

  Future<void> _restoreLastPlayback() async {
    final identity = _currentResumeIdentity;
    if (_resumeIdentity == identity || _disposed) return;
    final previousIdentity = _resumeIdentity;
    _resumeIdentity = identity;
    if (previousIdentity != null && previousIdentity != identity) {
      ++_playGeneration;
      _selectionPending = true;
      _suppressPositionUpdates = true;
      currentBook = null;
      currentChapter = null;
      chapters = [];
      currentTime = 0;
      duration = 0;
      _closeProgressSocket();
      await _audio.stop();
      if (_resumeIdentity != identity || _disposed) return;
      _notifyIfActive();
    }
    if (hasChapter) return;
    final generation = _playGeneration;
    bool active() =>
        !_disposed &&
        _resumeIdentity == identity &&
        _currentResumeIdentity == identity &&
        generation == _playGeneration;
    final cached = await _resumeStore.read(identity);
    if (!active()) return;
    if (cached != null) _selectResumeRecord(cached);
    if (appState.offlineMode) return;
    ChapterCatalogue? catalogue;
    try {
      final response = await appState.api.get('/api/progress/recent');
      if (!active()) return;
      final recent = asMapList(response.data)
          .map(ProgressItem.fromJson)
          .where((item) => item.bookId.isNotEmpty)
          .toList()
        ..sort((a, b) => (DateTime.tryParse(b.updatedAt ?? '') ??
                DateTime(1970))
            .compareTo(DateTime.tryParse(a.updatedAt ?? '') ?? DateTime(1970)));
      if (recent.isEmpty) return;
      final latest = recent.first;
      final updated = DateTime.tryParse(latest.updatedAt ?? '');
      if (cached != null &&
          (updated == null || !updated.isAfter(cached.updatedAt))) {
        return;
      }
      catalogue = ChapterCatalogue(appState.api, latest.bookId);
      final bookResponse = await appState.api
          .get('/api/books/${Uri.encodeComponent(latest.bookId)}');
      final items = await catalogue.all();
      if (!active() || items == null || items.isEmpty) return;
      // 已删除的章节不替换本地续播记录，避免错误跳回第一章。
      if (!items.any((item) => item.id == latest.chapterId)) return;
      final record = PlaybackResumeRecord(
          Book.fromJson(asMap(bookResponse.data)),
          items,
          latest.chapterId!,
          latest.position,
          updated ?? DateTime.now());
      _selectResumeRecord(record);
      await _resumeStore.write(identity, record);
    } catch (_) {
      // 服务端不可达时仍可用本地记录继续收听。
    } finally {
      catalogue?.dispose();
    }
  }

  void _selectResumeRecord(PlaybackResumeRecord record) {
    final chapter = record.chapter;
    if (chapter == null) return;
    currentBook = record.book;
    chapters = sortChaptersForPlayback(record.chapters);
    currentChapter = chapter;
    duration = chapter.duration.toDouble();
    currentTime = _clampPlaybackTime(record.position);
    _furthestChapterPosition = currentTime;
    _selectionPending = true;
    _suppressPositionUpdates = true;
    isPlaying = false;
    isMiniCollapsed = false;
    _usingAudioQueue = false;
    _usingTranscodeStream = false;
    error = null;
    _notifyIfActive();
  }

  Future<void> _saveResumeRecord({bool includePending = false}) async {
    final book = currentBook;
    final chapter = currentChapter;
    if (_disposed ||
        book == null ||
        chapter == null ||
        (_selectionPending && !includePending)) {
      return;
    }
    final identity = _resumeIdentity ?? _currentResumeIdentity;
    if (identity != _currentResumeIdentity) return;
    await _resumeStore.write(
        identity,
        PlaybackResumeRecord(
            book, List.of(chapters), chapter.id, currentTime, DateTime.now()));
  }
}
