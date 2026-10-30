import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class PlaybackResumeRecord {
  const PlaybackResumeRecord(
      this.book, this.chapters, this.chapterId, this.position, this.updatedAt);

  final Book book;
  final List<Chapter> chapters;
  final String chapterId;
  final double position;
  final DateTime updatedAt;

  Chapter? get chapter =>
      chapters.where((item) => item.id == chapterId).firstOrNull;

  Map<String, dynamic> toJson() => {
        'book': {
          'id': book.id,
          'library_id': book.libraryId,
          'title': book.title,
          'author': book.author,
          'narrator': book.narrator,
          'cover_url': book.coverUrl,
          'theme_color': book.themeColor,
          'description': book.description,
          'duration': book.duration,
          'size': book.size,
          'path': book.path,
          'hash': book.hash,
          'created_at': book.createdAt,
          'updated_at': book.updatedAt,
          'is_favorite': book.isFavorite,
          'library_type': book.libraryType,
          'can_write_metadata_files': book.canWriteMetadataFiles,
          'manual_corrected': book.manualCorrected,
          'skip_intro': book.skipIntro,
          'skip_outro': book.skipOutro,
          'tags': book.tags,
          'genre': book.genre,
          'year': book.year,
          'chapter_regex': book.chapterRegex,
          'progress_percent': book.progressPercent,
        },
        'chapters': [
          for (final item in chapters)
            {
              'id': item.id,
              'book_id': item.bookId,
              'title': item.title,
              'path': item.path,
              'chapter_index': item.chapterIndex,
              'duration': item.duration,
              'is_extra': item.isExtra,
              'progress_position': item.progressPosition,
              'progress_updated_at': item.progressUpdatedAt,
              'is_read': item.isRead,
            },
        ],
        'chapter_id': chapterId,
        'position': position,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory PlaybackResumeRecord.fromJson(Map<String, dynamic> json) =>
      PlaybackResumeRecord(
        Book.fromJson(asMap(json['book'])),
        asMapList(json['chapters']).map(Chapter.fromJson).toList(),
        json['chapter_id']?.toString() ?? '',
        (json['position'] as num).toDouble(),
        DateTime.parse(json['updated_at'] as String),
      );
}

class PlaybackResumeStore {
  String _key(String identity) =>
      'playback_resume:${base64Url.encode(utf8.encode(identity))}';

  Future<PlaybackResumeRecord?> read(String identity) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(identity));
      if (raw == null) return null;
      final record = PlaybackResumeRecord.fromJson(asMap(jsonDecode(raw)));
      if (record.book.id.isEmpty ||
          record.chapter == null ||
          !record.position.isFinite) {
        return null;
      }
      return record;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String identity, PlaybackResumeRecord record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(identity), jsonEncode(record.toJson()));
    } catch (_) {
      // 本地存储失败不影响播放和服务端进度同步。
    }
  }
}
