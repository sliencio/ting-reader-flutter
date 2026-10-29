import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';

class PlaybackSkipSettings {
  const PlaybackSkipSettings(this.intro, this.outro);

  final int intro;
  final int outro;

  Book apply(Book book) => book.copyWith(skipIntro: intro, skipOutro: outro);
}

class PlaybackSkipStore {
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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
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
    final prefs = await SharedPreferences.getInstance();
    final key = _key(identity, bookId);
    final saved = await prefs.setString(
        key, jsonEncode({'intro': settings.intro, 'outro': settings.outro}));
    if (!saved) throw StateError('Could not save local playback settings');
    _cache[key] = settings;
  }
}
