import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BookshelfCache {
  final _snapshots = <String, Map<String, dynamic>>{};

  Map<String, dynamic>? peek(String identity) => _snapshots[identity];

  Map<String, dynamic>? book(String identity, String id) {
    final snapshot = peek(identity);
    if (snapshot == null) return null;
    final candidates = <dynamic>[
      ...(snapshot['books'] as List),
      for (final series in snapshot['series'] as List)
        ...((series as Map)['books'] as List? ?? const []),
    ];
    for (final candidate in candidates) {
      if (candidate is Map<String, dynamic> && candidate['id'] == id) {
        return candidate;
      }
    }
    return null;
  }

  void _remember(String identity, Map<String, dynamic> snapshot) {
    _snapshots.remove(identity);
    _snapshots[identity] = snapshot;
    if (_snapshots.length > 8) _snapshots.remove(_snapshots.keys.first);
  }

  String _key(String identity) =>
      'bookshelf_cache_v1:${base64Url.encode(utf8.encode(identity))}';

  Future<Map<String, dynamic>?> read(String identity) async {
    final memory = peek(identity);
    if (memory != null) return memory;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(identity));
      if (raw == null) return null;
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['books'] is! List ||
          value['series'] is! List ||
          value['libraries'] is! List ||
          value['settings'] is! Map) {
        return null;
      }
      _remember(identity, value);
      return value;
    } catch (_) {
      // 缓存损坏或磁盘不可用时仍可从服务端加载。
      return null;
    }
  }

  Future<void> write(String identity, Map<String, dynamic> snapshot) async {
    _remember(identity, snapshot);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(identity), jsonEncode(snapshot));
    } catch (_) {
      // 本地缓存失败不影响已经加载的书架。
    }
  }
}
