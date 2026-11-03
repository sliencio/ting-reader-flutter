import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/services/desktop_window.dart';
import '../../core/state/player_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/locale.dart';
import '../../shared/app_scope.dart';

/// 小小窗：左侧圆形集数徽标 + 播放三键 + 右上角放大与关闭。
///
/// 不显示封面、书名与窗口标题；空白处可拖动窗口。
class MicroPlayerWindow extends StatefulWidget {
  const MicroPlayerWindow({
    super.key,
    required this.openChapters,
    required this.onExpand,
  });

  final Future<void> Function() openChapters;
  final VoidCallback onExpand;

  @override
  State<MicroPlayerWindow> createState() => _MicroPlayerWindowState();
}

class _MicroPlayerWindowState extends State<MicroPlayerWindow> {
  String? _hoverLabel;

  /// 圆内默认只显示当前集；点一下切换为「当前 / 总集数」。
  bool _showTotal = false;

  void _setHover(String? label) {
    if (_hoverLabel == label) return;
    setState(() => _hoverLabel = label);
  }

  @override
  Widget build(BuildContext context) {
    final player = AppScope.playerOf(context);
    final window = DesktopWindow.instance;
    final hasChapter = player.hasChapter;
    final colors = Theme.of(context).colorScheme;
    final compactBtn = IconButton.styleFrom(
      minimumSize: const Size(28, 28),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );

    Widget hoverable(String label, Widget child) => MouseRegion(
          onEnter: (_) => _setHover(label),
          onExit: (_) => _setHover(null),
          child: child,
        );

    return Material(
      color: colors.surface,
      child: Stack(
        children: [
          // 拖动层铺在最底下，并允许上层的按钮接收点击。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => window.startDragging(),
              onSecondaryTapUp: (details) {
                _setHover(null);
                _showContextMenu(context, details.globalPosition);
              },
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  hoverable(
                    context.localeText('切换集数显示', 'Toggle chapter count'),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _showTotal = !_showTotal),
                      child: _ChapterBadge(
                        player: player,
                        showTotal: _showTotal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  hoverable(
                    context.localeText('上一曲', 'Previous'),
                    IconButton(
                      style: compactBtn,
                      iconSize: 20,
                      icon: const Icon(Icons.skip_previous_rounded),
                      onPressed: hasChapter ? player.previousChapter : null,
                    ),
                  ),
                  hoverable(
                    context.localeText('播放或暂停', 'Play or pause'),
                    IconButton(
                      style: compactBtn.copyWith(
                        backgroundColor: WidgetStatePropertyAll(
                          colors.primary.withValues(alpha: 0.13),
                        ),
                        foregroundColor: WidgetStatePropertyAll(colors.primary),
                        minimumSize: const WidgetStatePropertyAll(Size(32, 28)),
                      ),
                      iconSize: 22,
                      icon: player.isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(player.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                      onPressed: hasChapter ? player.togglePlay : null,
                    ),
                  ),
                  hoverable(
                    context.localeText('下一曲', 'Next'),
                    IconButton(
                      style: compactBtn,
                      iconSize: 20,
                      icon: const Icon(Icons.skip_next_rounded),
                      onPressed: hasChapter ? player.nextChapter : null,
                    ),
                  ),
                  const Spacer(),
                  hoverable(
                    context.localeText('放大小窗', 'Enlarge window'),
                    IconButton(
                      style: compactBtn,
                      iconSize: 15,
                      icon: const Icon(Icons.open_in_full_rounded),
                      onPressed: widget.onExpand,
                    ),
                  ),
                  hoverable(
                    context.localeText('关闭', 'Close'),
                    IconButton(
                      style: compactBtn.copyWith(
                        foregroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.hovered)
                                ? Colors.white
                                : null),
                        backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.hovered)
                                ? Colors.red
                                : Colors.transparent),
                      ),
                      iconSize: 14,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: window.close,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 悬浮提示贴在窗口顶部内侧，避免被窗口边缘截断。
          if (_hoverLabel != null)
            Positioned(
              top: 1,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: context.isDark
                          ? AppColors.slate700.withValues(alpha: 0.95)
                          : AppColors.slate800.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      _hoverLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final window = DesktopWindow.instance;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'mini',
          child: Text(context.localeText('小窗模式', 'Mini window')),
        ),
        PopupMenuItem(
          value: 'normal',
          child: Text(context.localeText('返回主窗口', 'Restore window')),
        ),
      ],
    );
    if (selected == 'mini') {
      await window.setMode(DesktopWindowMode.mini);
    } else if (selected == 'normal') {
      await window.setMode(DesktopWindowMode.normal);
    }
  }
}

/// 圆形徽标：外圈为播放进度弧，圆内默认显示当前集，点开后显示当前/总集数。
class _ChapterBadge extends StatefulWidget {
  const _ChapterBadge({required this.player, required this.showTotal});

  final PlayerState player;
  final bool showTotal;

  @override
  State<_ChapterBadge> createState() => _ChapterBadgeState();
}

class _ChapterBadgeState extends State<_ChapterBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bubbles = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _bubbles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final colors = Theme.of(context).colorScheme;
    final isDark = context.isDark;
    final chapter = player.currentChapter;
    final chapters = player.chapters;

    final duration =
        player.duration.isFinite && player.duration > 0 ? player.duration : 1.0;
    final position = player.currentTime.isFinite
        ? player.currentTime.clamp(0.0, duration)
        : 0.0;
    final progress = duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;

    var number = 0;
    var total = 0;
    if (chapter != null) {
      final index = chapters.indexWhere((item) => item.id == chapter.id);
      number = chapter.chapterIndex > 0 ? chapter.chapterIndex : index + 1;
      total = chapter.isExtra
          ? chapters.where((item) => item.isExtra).length
          : chapters.where((item) => !item.isExtra).length;
    }

    return SizedBox(
      width: 44,
      height: 44,
      child: AnimatedBuilder(
        animation: _bubbles,
        builder: (context, child) => CustomPaint(
          painter: _BadgePainter(
            progress: progress,
            accentColor: colors.primary,
            trackColor: isDark ? AppColors.slate800 : AppColors.slate200,
            bubblePhase: player.isPlaying ? _bubbles.value : 0,
          ),
          child: child,
        ),
        child: Center(
          child: chapter == null
              ? Text(
                  '--',
                  style: TextStyle(fontSize: 11, color: context.mutedText),
                )
              : widget.showTotal
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$number',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                            color: colors.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (total > 0)
                          Text(
                            '/ $total',
                            style: TextStyle(
                              fontSize: 9,
                              height: 1.05,
                              color: context.mutedText,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                      ],
                    )
                  : Text(
                      '$number',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                        color: colors.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
        ),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  const _BadgePainter({
    required this.progress,
    required this.accentColor,
    required this.trackColor,
    required this.bubblePhase,
  });

  final double progress;
  final Color accentColor;
  final Color trackColor;
  final double bubblePhase;

  static const _bubbleSpecs = [
    (0.32, 1.6, 0.00),
    (0.55, 1.2, 0.35),
    (0.44, 2.0, 0.15),
    (0.66, 1.4, 0.70),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 3.5;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      final arcPaint = Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        arcPaint,
      );
    }

    if (bubblePhase <= 0) return;

    // 气泡只画在圆内，文字压在气泡之上。
    final innerRadius = radius - strokeWidth - 0.5;
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: innerRadius)),
    );
    for (final (xFactor, bubbleRadius, phaseOffset) in _bubbleSpecs) {
      final t = (bubblePhase + phaseOffset) % 1.0;
      final x = center.dx + (xFactor - 0.5) * innerRadius * 1.6;
      final y = center.dy + innerRadius * (0.95 - 1.9 * t);
      final alpha = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(x, y),
        bubbleRadius,
        Paint()
          ..color = accentColor.withValues(alpha: alpha * 0.28)
          ..style = PaintingStyle.fill,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BadgePainter old) =>
      old.progress != progress ||
      old.bubblePhase != bubblePhase ||
      old.accentColor != accentColor;
}
