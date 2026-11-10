import 'dart:convert';

import '../models/models.dart';
import 'account_document_store.dart';
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
  PlaybackCheckpoints({AccountDocumentStore? store})
      : _store = store ?? AccountDocumentStore();

  /// 保留的记录条数上限。每条记录都带完整章节列表，条数不宜随意放大。
  static const maxEntries = 50;

  /// 存档格式版本。v1 是每条记录各自内嵌整本书和整份章节列表，
  /// 同一本书的 40 条记录会把它重复 40 遍。
  static const _version = 2;

  Future<void> _writes = Future<void>.value();
  final AccountDocumentStore _store;

  String _key(String identity) =>
      'playback_checkpoints:${base64Url.encode(utf8.encode(identity))}';

  Future<List<PlaybackCheckpoint>> read(String identity) async {
    await _writes;
    return _read(identity);
  }

  Future<List<PlaybackCheckpoint>> _read(String identity) async {
    try {
      final raw = await _store.read(_key(identity));
      if (raw == null) return [];
      final document = jsonDecode(raw);
      if (document is Map && document['version'] == _version) {
        return _decodeV2(document);
      }
      // v1：旧存档直接按原格式读，下次写入时自然升级。
      return asMapList(document)
          .map(PlaybackCheckpoint.fromJson)
          .where(_usable)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static bool _usable(PlaybackCheckpoint item) =>
      item.record.chapter != null && item.record.position.isFinite;

  /// v2 把书与章节列表提到顶层，按书 id 只存一份；记录本身只留位置。
  List<PlaybackCheckpoint> _decodeV2(Map<dynamic, dynamic> document) {
    final books = <String, ({Book book, List<Chapter> chapters})>{};
    for (final entry in asMapList(document['books'])) {
      final book = Book.fromJson(asMap(entry['book']));
      if (book.id.isEmpty) continue;
      books[book.id] = (
        book: book,
        chapters: asMapList(entry['chapters']).map(Chapter.fromJson).toList(),
      );
    }
    final result = <PlaybackCheckpoint>[];
    for (final entry in asMapList(document['entries'])) {
      final payload = asMap(entry);
      final cached = books[payload['book_id']?.toString()];
      if (cached == null) continue;
      final record = PlaybackResumeRecord(
        cached.book,
        cached.chapters,
        payload['chapter_id']?.toString() ?? '',
        (payload['position'] as num?)?.toDouble() ?? 0,
        DateTime.tryParse(payload['updated_at']?.toString() ?? '') ??
            DateTime.now(),
      );
      final checkpoint =
          PlaybackCheckpoint(record, payload['reason']?.toString() ?? 'seek');
      if (_usable(checkpoint)) result.add(checkpoint);
    }
    return result;
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
      final kept = [value, ...entries].take(maxEntries).toList();
      await _store.write(_key(identity), _encode(kept));
    });
    _writes = write.catchError((_) {});
    return write;
  }

  /// 每条记录都带完整章节列表，同一本书的多条记录共享一份。
  String _encode(List<PlaybackCheckpoint> entries) {
    final books = <String, Map<String, dynamic>>{};
    for (final item in entries) {
      final book = item.record.book;
      books.putIfAbsent(
          book.id,
          () => {
                'book': book.toJson(),
                'chapters': [
                  for (final chapter in item.record.chapters) chapter.toJson(),
                ],
              });
    }
    return jsonEncode({
      'version': _version,
      'books': books.values.toList(),
      'entries': [
        for (final item in entries)
          {
            'book_id': item.record.book.id,
            'chapter_id': item.record.chapterId,
            'position': item.record.position,
            'reason': item.reason,
            'updated_at': item.record.updatedAt.toUtc().toIso8601String(),
          },
      ],
    });
  }
}
