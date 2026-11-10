import 'dart:convert';

import '../models/book.dart';
import 'account_document_store.dart';

class PlaybackSkipSettings {
  const PlaybackSkipSettings(this.intro, this.outro);

  final int intro;
  final int outro;

  Book apply(Book book) => book.copyWith(skipIntro: intro, skipOutro: outro);
}

class PlaybackSkipStore {
  PlaybackSkipStore({AccountDocumentStore? documents})
      : _documents = documents ?? AccountDocumentStore();

  final AccountDocumentStore _documents;
  final _cache = <String, PlaybackSkipSettings?>{};

  String _key(String identity, String bookId) =>
      'playback_skip:${base64Url.encode(utf8.encode(jsonEncode([
            identity,
            bookId
          ])))}';

  PlaybackSkipSettings? cached(String identity, String bookId) =>
      _cache[_key(identity, bookId)];

  Future<PlaybackSkipSettings?> read(String identity, String bookId) async {
    final key = _key(identity, bookId);
    if (_cache.containsKey(key)) return _cache[key];
    final raw = await _documents.read(key);
    PlaybackSkipSettings? settings;
    if (raw != null) {
      try {
        final value = jsonDecode(raw);
        if (value is Map &&
            value['intro'] is int &&
            value['outro'] is int &&
            value['intro'] >= 0 &&
            value['outro'] >= 0) {
          settings = PlaybackSkipSettings(value['intro'], value['outro']);
        }
      } on FormatException {
        // 旧数据损坏时使用书籍原有设置，允许重新保存。
      }
    }
    // 保存可能在读取期间完成，以新保存的本机设置为准。
    return _cache.putIfAbsent(key, () => settings);
  }

  Future<void> write(
      String identity, String bookId, PlaybackSkipSettings settings) async {
    if (settings.intro < 0 || settings.outro < 0) {
      throw ArgumentError('Skip durations must not be negative');
    }
    final key = _key(identity, bookId);
    await _documents.write(
        key, jsonEncode({'intro': settings.intro, 'outro': settings.outro}));
    _cache[key] = settings;
  }
}
