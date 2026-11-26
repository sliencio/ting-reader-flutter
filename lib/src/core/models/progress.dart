import '_helpers.dart';

class ProgressDevice {
  const ProgressDevice({this.type, required this.updatedAt});
  final String? type;
  final String? updatedAt;
  factory ProgressDevice.fromJson(Map<String, dynamic> json) => ProgressDevice(
      type: readString(json, 'device_type'),
      updatedAt: readString(json, 'updated_at'));
}

class ProgressItem {
  const ProgressItem({
    required this.id,
    required this.bookId,
    this.chapterId,
    this.position = 0,
    this.duration = 0,
    this.updatedAt,
    this.bookTitle,
    this.chapterTitle,
    this.coverUrl,
    this.libraryId,
    this.chapterDuration,
    this.revision,
    this.devices = const [],
    this.latestWins = false,
  });

  final String id;
  final String bookId;
  final String? chapterId;
  final double position;
  final double duration;
  final String? updatedAt;
  final String? bookTitle;
  final String? chapterTitle;
  final String? coverUrl;
  final String? libraryId;
  final int? chapterDuration;
  final int? revision;
  final List<ProgressDevice> devices;
  final bool latestWins;

  factory ProgressItem.fromJson(Map<String, dynamic> json) {
    return ProgressItem(
      id: readString(json, 'id') ?? '',
      bookId: readString(json, 'book_id') ?? '',
      chapterId: readString(json, 'chapter_id'),
      position: readDouble(json, 'position') ?? 0,
      duration: readDouble(json, 'duration') ?? 0,
      updatedAt: readString(json, 'updated_at'),
      bookTitle: readString(json, 'book_title'),
      chapterTitle: readString(json, 'chapter_title'),
      coverUrl: readString(json, 'cover_url'),
      libraryId: readString(json, 'library_id'),
      chapterDuration: readInt(json, 'chapter_duration'),
      revision: readInt(json, 'revision'),
      devices: (json['devices'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ProgressDevice.fromJson)
          .toList(),
      latestWins: json['latest_wins'] == true,
    );
  }
}
