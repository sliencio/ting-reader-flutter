import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChapterReadMarksStore {
  String _key(String identity) =>
      'chapter_read_marks:${base64Url.encode(utf8.encode(identity))}';

  Future<Set<String>> read(String identity) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(identity)) ?? const <String>[]).toSet();
  }

  Future<void> write(String identity, Set<String> chapterIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(identity), chapterIds.toList()..sort());
  }
}
