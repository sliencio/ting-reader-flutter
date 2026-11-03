import 'package:flutter/material.dart';

import '../../core/state/player_state.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/locale.dart';
import '../../core/utils/urls.dart';
import '../../shared/app_scope.dart';
import '../../shared/common/media_widgets.dart';

class SmallPlayerWindow extends StatelessWidget {
  const SmallPlayerWindow({super.key, required this.openChapters});
  final Future<void> Function() openChapters;

  @override
  Widget build(BuildContext context) {
    final player = AppScope.playerOf(context);
    final book = player.currentBook;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Tooltip(
              message: context.localeText('章节列表', 'Chapters'),
              child: InkWell(
                  onTap: player.hasChapter ? openChapters : null,
                  child: SizedBox(
                      width: 56,
                      height: 56,
                      child: CoverImage(
                          url: book == null
                              ? ''
                              : bookCoverUrl(AppScope.appOf(context), book),
                          radius: 8)))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(book?.title ?? context.localeText('听悦', 'Ting Reader'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                Text(
                    player.playbackStatus ??
                        player.currentChapter?.title ??
                        context.localeText('暂无播放内容', 'Nothing playing'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
                SizedBox(
                    height: 26,
                    child: Row(children: [
                      _SmallWindowTime(value: player.currentTime),
                      Expanded(child: _SmallWindowProgress(player: player)),
                    ])),
              ])),
          const SizedBox(width: 4),
          IconButton(
              tooltip: context.localeText('上一首', 'Previous'),
              icon: const Icon(Icons.skip_previous_rounded),
              onPressed: player.hasChapter ? player.previousChapter : null),
          IconButton.filled(
              tooltip: context.localeText('播放或暂停', 'Play or pause'),
              icon: player.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(player.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
              onPressed: player.hasChapter ? player.togglePlay : null),
          IconButton(
              tooltip: context.localeText('下一首', 'Next'),
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: player.hasChapter ? player.nextChapter : null),
        ]),
      ),
    );
  }
}

class _SmallWindowTime extends StatelessWidget {
  const _SmallWindowTime({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Text(formatDurationShort(value),
        style: Theme.of(context).textTheme.labelSmall);
  }
}

/// 小窗进度条：拖动期间只更新本地值，松手后才真正跳转。
///
/// 直接在 onChanged 里调用 player.seek 会让每一帧都触发音频跳转与
/// 进度上报，拖动因此明显卡顿。
class _SmallWindowProgress extends StatefulWidget {
  const _SmallWindowProgress({required this.player});

  final PlayerState player;

  @override
  State<_SmallWindowProgress> createState() => _SmallWindowProgressState();
}

class _SmallWindowProgressState extends State<_SmallWindowProgress> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final duration =
        player.duration.isFinite && player.duration > 0 ? player.duration : 1.0;
    final position = player.currentTime.isFinite
        ? player.currentTime.clamp(0.0, duration)
        : 0.0;
    final value = (_dragValue ?? position).clamp(0.0, duration);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10)),
      child: Slider(
        min: 0,
        max: duration,
        value: value,
        onChanged: player.hasChapter
            ? (next) => setState(() => _dragValue = next)
            : null,
        onChangeStart: player.hasChapter
            ? (_) => setState(() => _dragValue = position)
            : null,
        onChangeEnd: player.hasChapter
            ? (next) {
                setState(() => _dragValue = null);
                player.seek(next);
              }
            : null,
      ),
    );
  }
}
