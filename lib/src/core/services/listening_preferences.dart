import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ListeningPreferences {
  String _speedKey(String identity, String bookId) =>
      'book_speed:${base64Url.encode(utf8.encode('$identity:$bookId'))}';

  Future<double?> speed(String identity, String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(_speedKey(identity, bookId));
    return value != null && value.isFinite && value >= 0.5 && value <= 3
        ? value
        : null;
  }

  Future<void> saveSpeed(String identity, String bookId, double? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_speedKey(identity, bookId));
    } else if (value.isFinite) {
      await prefs.setDouble(_speedKey(identity, bookId), value.clamp(0.5, 3));
    }
  }

  static double resumePosition(
      {required double position,
      required double intro,
      required DateTime? pausedAt,
      required DateTime now,
      required int seconds}) {
    if (seconds <= 0 ||
        pausedAt == null ||
        now.difference(pausedAt).inSeconds < 60) {
      return position;
    }
    return (position - seconds).clamp(intro, position).toDouble();
  }
}
