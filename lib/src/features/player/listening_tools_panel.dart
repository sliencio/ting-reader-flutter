import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/state/player_state.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/locale.dart';

Future<void> showListeningCheckpoints(
    BuildContext context, PlayerState player) async {
  final entries = await player.playbackCheckpoints();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
              child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: Column(children: [
              ListTile(
                  title: Text(context.localeText(
                      '进度找回', 'Restore a listening position')),
                  subtitle: Text(context.localeText('跳转前和开始睡眠定时的位置，最近保留 20 条',
                      'Before navigation and sleep timers; keeps the latest 20 positions')),
                  trailing: IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded))),
              Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Text(context.localeText(
                              '还没有进度保护记录', 'No saved positions yet')))
                      : ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (_, index) {
                            final entry = entries[index];
                            final record = entry.record;
                            final reason = switch (entry.reason) {
                              'sleep' => context.localeText(
                                  '睡眠定时起点', 'Sleep timer started'),
                              'chapter' => context.localeText(
                                  '切换章节前', 'Before switching chapters'),
                              'restore' => context.localeText(
                                  '恢复进度前', 'Before restoring a position'),
                              'sync' => context.localeText(
                                  '处理同步前', 'Before resolving sync'),
                              _ =>
                                context.localeText('跳转进度前', 'Before seeking'),
                            };
                            final time = record.updatedAt.toLocal();
                            return ListTile(
                              leading: Icon(entry.reason == 'sleep'
                                  ? Icons.bedtime_outlined
                                  : Icons.history_rounded),
                              title: Text(
                                  '${record.book.title} · ${record.chapter?.title ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '$reason · ${formatDurationShort(record.position)}\n${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'),
                              isThreeLine: true,
                              onTap: () async {
                                Navigator.pop(sheetContext);
                                try {
                                  await player.restoreCheckpoint(entry);
                                } catch (failure) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                ApiError.messageFor(failure))));
                                  }
                                }
                              },
                            );
                          },
                        )),
            ]),
          )));
}

Future<void> showListeningSync(BuildContext context, PlayerState player) async {
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ProgressSyncDialog(player: player));
}

class _ProgressSyncDialog extends StatefulWidget {
  const _ProgressSyncDialog({required this.player});
  final PlayerState player;
  @override
  State<_ProgressSyncDialog> createState() => _ProgressSyncDialogState();
}

class _ProgressSyncDialogState extends State<_ProgressSyncDialog> {
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted) setState(() => _error = ApiError.messageFor(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final sync = player.progressSync;
    return AnimatedBuilder(
        animation: sync,
        builder: (context, _) => AlertDialog(
              title: Text(context.localeText('进度同步', 'Progress sync')),
              content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.localeText(
                          '本机待同步：${sync.pendingCount} 本书。离线收听进度会先保存在本机，联网后自动补传。',
                          '${sync.pendingCount} books pending. Offline progress is saved locally and uploaded when connected.')),
                      for (final entry in sync.conflicts.entries) ...[
                        const Divider(height: 28),
                        Text(entry.key == player.currentBook?.id
                            ? player.currentBook!.title
                            : context.localeText('其他书籍的进度', 'Another book')),
                        Text(context.localeText(
                            '其他设备有较新的进度：${entry.value.chapterTitle ?? '另一章节'} ${formatDurationShort(entry.value.position)}。请选择要保留的位置。',
                            'Another device has a newer position: ${entry.value.chapterTitle ?? 'chapter'} ${formatDurationShort(entry.value.position)}. Choose which position to keep.')),
                        Wrap(spacing: 8, children: [
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() =>
                                      player.resolveProgressConflict(entry.key,
                                          useRemote: true)),
                              child: Text(context.localeText(
                                  '采用其他设备进度', 'Use other device'))),
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() =>
                                      player.resolveProgressConflict(entry.key,
                                          useRemote: false)),
                              child: Text(context.localeText(
                                  '保留本机进度', 'Keep this device'))),
                        ]),
                      ],
                      if (_error != null)
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      if (_busy) const LinearProgressIndicator(),
                    ],
                  ))),
              actions: [
                TextButton(
                    onPressed: _busy ? null : () => _run(sync.flush),
                    child: Text(context.localeText('立即同步', 'Sync now'))),
                TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: Text(context.localeText('关闭', 'Close'))),
              ],
            ));
  }
}

class PlaybackStatusNotice extends StatelessWidget {
  const PlaybackStatusNotice({super.key, required this.player});
  final PlayerState player;

  @override
  Widget build(BuildContext context) {
    final status = player.playbackStatus;
    final sync = player.progressSync;
    final syncNotice = sync.conflicts.isNotEmpty ||
        (sync.pendingCount > 0 &&
            (player.appState.offlineMode ||
                player.downloadState.network.offline ||
                sync.error != null));
    if (status == null && !syncNotice) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(children: [
          if (status != null)
            Row(children: [
              if (player.isLoading)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(
                    player.error != null
                        ? Icons.error_outline_rounded
                        : Icons.info_outline_rounded,
                    size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(status, style: const TextStyle(fontSize: 12))),
              if (player.error != null)
                TextButton(
                    onPressed: player.togglePlay,
                    child: Text(context.localeText('重试', 'Retry'))),
            ]),
          if (syncNotice)
            TextButton.icon(
                onPressed: () => showListeningSync(context, player),
                icon: Icon(
                    sync.conflicts.isNotEmpty
                        ? Icons.sync_problem_rounded
                        : Icons.cloud_off_outlined,
                    size: 18),
                label: Text(
                    sync.conflicts.isNotEmpty
                        ? context.localeText(
                            '进度冲突，点击选择', 'Resolve progress conflict')
                        : context.localeText('进度已保存在本机，等待同步',
                            'Progress saved locally; sync pending'),
                    style: const TextStyle(fontSize: 12))),
        ]));
  }
}
