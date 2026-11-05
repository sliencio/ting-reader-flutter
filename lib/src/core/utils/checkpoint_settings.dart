import '../models/models.dart';

/// 进度保护点的触发时机。
///
/// 进度找回最多保留 20 条，所以高频触发必须能自定义：按分钟同步默认关闭，
/// 需要时由用户选择间隔；其余触发点各自独立开关。
class PlaybackCheckpointSettings {
  const PlaybackCheckpointSettings({
    this.onPlayStart = true,
    this.onChapterStart = true,
    this.onChapterMiddle = false,
    this.onChapterEnd = true,
    this.intervalMinutes = 0,
  });

  static const settingKey = 'progress_checkpoint_settings';

  /// 可选同步间隔（分钟），0 表示关闭。
  static const intervalOptions = <int>[0, 1, 2, 5, 10, 15, 30];

  /// 开始播放（含暂停后继续）。
  final bool onPlayStart;

  /// 新的一章开始。
  final bool onChapterStart;

  /// 曲目播放到中间。
  final bool onChapterMiddle;

  /// 章节播放到结尾。
  final bool onChapterEnd;

  /// 定时同步间隔（分钟），0 表示不按时间同步。
  final int intervalMinutes;

  factory PlaybackCheckpointSettings.fromSettings(
      Map<String, dynamic> settings) {
    final nested = asMap(settings['settings_json']);
    final source = asMap(settings[settingKey] ?? nested[settingKey]);
    return PlaybackCheckpointSettings(
      onPlayStart: _bool(source, 'on_play_start', fallback: true),
      onChapterStart: _bool(source, 'on_chapter_start', fallback: true),
      onChapterMiddle: _bool(source, 'on_chapter_middle', fallback: false),
      onChapterEnd: _bool(source, 'on_chapter_end', fallback: true),
      intervalMinutes: _interval(source),
    );
  }

  PlaybackCheckpointSettings copyWith({
    bool? onPlayStart,
    bool? onChapterStart,
    bool? onChapterMiddle,
    bool? onChapterEnd,
    int? intervalMinutes,
  }) =>
      PlaybackCheckpointSettings(
        onPlayStart: onPlayStart ?? this.onPlayStart,
        onChapterStart: onChapterStart ?? this.onChapterStart,
        onChapterMiddle: onChapterMiddle ?? this.onChapterMiddle,
        onChapterEnd: onChapterEnd ?? this.onChapterEnd,
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      );

  Map<String, dynamic> toJson() => {
        'on_play_start': onPlayStart,
        'on_chapter_start': onChapterStart,
        'on_chapter_middle': onChapterMiddle,
        'on_chapter_end': onChapterEnd,
        'interval_minutes': intervalMinutes,
      };

  static bool _bool(Map<String, dynamic> source, String key,
      {required bool fallback}) {
    final value = source[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return fallback;
  }

  static int _interval(Map<String, dynamic> source) {
    final raw = source['interval_minutes'];
    final value =
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    if (value == null || value <= 0) return 0;
    return intervalOptions.contains(value) ? value : 0;
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackCheckpointSettings &&
      other.onPlayStart == onPlayStart &&
      other.onChapterStart == onChapterStart &&
      other.onChapterMiddle == onChapterMiddle &&
      other.onChapterEnd == onChapterEnd &&
      other.intervalMinutes == intervalMinutes;

  @override
  int get hashCode => Object.hash(onPlayStart, onChapterStart, onChapterMiddle,
      onChapterEnd, intervalMinutes);
}
