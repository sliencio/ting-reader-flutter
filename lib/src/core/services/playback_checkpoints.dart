import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'playback_resume_store.dart';

class PlaybackCheckpoint {
  const PlaybackCheckpoint(this.record, this.reason);
  final PlaybackResumeRecord record;
  final String reason;
  Map<String, dynamic> toJson() =>
      {'record': record.toJson(), 'reason': reason};
  factory PlaybackCheckpoint.fromJson(Map<String, dynamic> json) =>
      PlaybackCheckpoint(PlaybackResumeRecord.fromJson(asMap(json['record'])),
          json['reason']?.toString() ?? 'seek');
}

class PlaybackCheckpoints {
  /// 保留的记录条数上限。每条记录都带完整章节列表，条数不宜随意放大。
  static const maxEntries = 50;

  Future<void> _writes = Future<void>.value();
  String _key(String identity) =>
      'playback_checkpoints:${base64Url.encode(utf8.encode(identity))}';

  Future<List<PlaybackCheckpoint>> read(String identity) async {
    await _writes;
    return _read(identity);
  }

  Future<List<PlaybackCheckpoint>> _read(String identity) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      return asMapList(jsonDecode(prefs.getString(_key(identity)) ?? '[]'))
          .map(PlaybackCheckpoint.fromJson)
          .where((item) =>
              item.record.chapter != null && item.record.position.isFinite)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 写入一条记录；[replace] 为 true 时先丢掉同一本书、同一原因的旧记录。
  ///
  /// 定时同步这类高频触发必须用 [replace]，否则会在 [maxEntries] 上限里
  /// 不断挤掉真正有用的时间点（例如睡眠起点）。
  Future<void> add(String identity, PlaybackCheckpoint value,
      {bool replace = false}) {
    final write = _writes.catchError((_) {}).then((_) async {
      final stored = await _read(identity);
      final entries = replace
          ? stored
              .where((item) =>
                  item.reason != value.reason ||
                  item.record.book.id != value.record.book.id)
              .toList()
          : stored;
      if (entries.isNotEmpty) {
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
          _key(identity),
          jsonEncode([value, ...entries]
              .take(maxEntries)
              .map((item) => item.toJson())
              .toList()));
    });
    _writes = write.catchError((_) {});
    return write;
  }
}
