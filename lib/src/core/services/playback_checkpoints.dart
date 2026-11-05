import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'playback_resume_store.dart';

class PlaybackCheckpoint {
  const PlaybackCheckpoint(this.record, this.reason);
  final PlaybackResumeRecord record;
  final String reason;
  static bool isTimelineReason(String reason) =>
      reason == 'chapter_start' || reason == 'sleep_end';
  Map<String, dynamic> toJson() =>
      {'record': record.toJson(), 'reason': reason};
  factory PlaybackCheckpoint.fromJson(Map<String, dynamic> json) =>
      PlaybackCheckpoint(PlaybackResumeRecord.fromJson(asMap(json['record'])),
          json['reason']?.toString() ?? 'seek');
}

class PlaybackCheckpoints {
  Future<void> _writes = Future<void>.value();
  String _key(String identity, {bool timeline = false}) =>
      '${timeline ? 'playback_timeline' : 'playback_checkpoints'}:'
      '${base64Url.encode(utf8.encode(identity))}';

  Future<List<PlaybackCheckpoint>> read(String identity) async {
    await _writes;
    return _read(_key(identity));
  }

  Future<List<PlaybackCheckpoint>> readTimeline(String identity) async {
    await _writes;
    final entries = [
      ...await _read(_key(identity, timeline: true)),
      ...(await _read(_key(identity))).where((item) => item.reason == 'sleep'),
    ]..sort((a, b) => b.record.updatedAt.compareTo(a.record.updatedAt));
    return entries.take(20).toList();
  }

  Future<List<PlaybackCheckpoint>> _read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      return asMapList(jsonDecode(prefs.getString(key) ?? '[]'))
          .map(PlaybackCheckpoint.fromJson)
          .where((item) =>
              item.record.chapter != null && item.record.position.isFinite)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(String identity, PlaybackCheckpoint value) {
    final timeline = PlaybackCheckpoint.isTimelineReason(value.reason);
    final key = _key(identity, timeline: timeline);
    final write = _writes.catchError((_) {}).then((_) async {
      final entries = await _read(key);
      if (!timeline && value.reason != 'sleep' && entries.isNotEmpty) {
        final last = entries.first;
        if (last.reason == value.reason &&
            last.record.book.id == value.record.book.id &&
            last.record.chapterId == value.record.chapterId &&
            (last.record.position - value.record.position).abs() < 2) {
          return;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          key,
          jsonEncode([value, ...entries]
              .take(20)
              .map((item) => item.toJson())
              .toList()));
    });
    _writes = write.catchError((_) {});
    return write;
  }
}
