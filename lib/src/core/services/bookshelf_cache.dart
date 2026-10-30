import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BookshelfCache {
  String _key(String identity) =>
      'bookshelf_cache_v1:${base64Url.encode(utf8.encode(identity))}';

  Future<Map<String, dynamic>?> read(String identity) async {
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
      return value;
    } catch (_) {
      // 缓存损坏或磁盘不可用时仍可从服务端加载。
      return null;
    }
  }

  Future<void> write(String identity, Map<String, dynamic> snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(identity), jsonEncode(snapshot));
    } catch (_) {
      // 本地缓存失败不影响已经加载的书架。
    }
  }
}
