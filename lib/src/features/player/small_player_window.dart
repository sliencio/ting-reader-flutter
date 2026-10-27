import 'package:flutter/material.dart';

import '../../core/services/desktop_window.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/locale.dart';
import '../../shared/app_scope.dart';

class SmallPlayerWindow extends StatelessWidget {
  const SmallPlayerWindow({super.key, required this.openChapters});
  final Future<void> Function() openChapters;

  @override
  Widget build(BuildContext context) {
    final player = AppScope.playerOf(context);
    final duration = player.duration > 0 ? player.duration : 1.0;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SingleChildScrollView(
            child: Column(
          children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        player.currentBook?.title ??
                            context.localeText('听悦', 'Ting Reader'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(
                        player.currentChapter?.title ??
                            context.localeText('暂无播放内容', 'Nothing playing'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ])),
              IconButton(
                tooltip: context.localeText('返回主窗口', 'Restore window'),
                icon: const Icon(Icons.open_in_full_rounded),
                onPressed: () => DesktopWindow.instance.setMini(false),
              ),
            ]),
            Slider(
                value: player.currentTime.clamp(0, duration),
                max: duration,
                onChanged: player.hasChapter ? player.seek : null),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(formatDurationShort(player.currentTime)),
              Text(formatDurationShort(player.duration)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                  tooltip: context.localeText('上一章', 'Previous'),
                  icon: const Icon(Icons.skip_previous_rounded),
                  onPressed: player.previousChapter),
              IconButton.filled(
                  tooltip: context.localeText('播放或暂停', 'Play or pause'),
                  icon: Icon(player.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                  onPressed: player.hasChapter ? player.togglePlay : null),
              IconButton(
                  tooltip: context.localeText('下一章', 'Next'),
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: player.nextChapter),
              IconButton(
                  tooltip: context.localeText('章节列表', 'Chapters'),
                  icon: const Icon(Icons.queue_music_rounded),
                  onPressed: player.hasChapter ? openChapters : null),
            ]),
          ],
        )),
      ),
    );
  }
}
