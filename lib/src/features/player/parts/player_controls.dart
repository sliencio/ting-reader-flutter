part of '../mini_player.dart';

/// 播放器主滑块的手柄：白色圆点 + 强调色描边与柔光，拖动时略微放大。
class _GlowSliderThumb extends SliderComponentShape {
  const _GlowSliderThumb({required this.color});

  final Color color;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(18, 18);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final scale = 1 + 0.12 * activationAnimation.value;
    final radius = 8.0 * scale;
    final glow = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, radius + 2, glow);
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }
}

class _MiniProgressSlider extends StatefulWidget {
  const _MiniProgressSlider({
    required this.player,
    required this.currentTime,
    required this.duration,
    required this.percent,
    required this.accentColor,
  });

  final PlayerState player;
  final double currentTime;
  final double duration;
  final double percent;
  final Color accentColor;

  @override
  State<_MiniProgressSlider> createState() => _MiniProgressSliderState();
}

class _MiniProgressSliderState extends State<_MiniProgressSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final max = widget.duration > 0 ? widget.duration : 1.0;
    final value = (_dragValue ?? widget.currentTime).clamp(0, max).toDouble();
    final canSeek = max > 1 || widget.percent > 0;
    return SizedBox(
      height: 24,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          activeTrackColor: widget.accentColor,
          inactiveTrackColor:
              context.isDark ? AppColors.slate800 : AppColors.slate200,
          thumbColor: widget.accentColor,
          overlayColor: widget.accentColor.withValues(alpha: 0.12),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          trackShape: const RoundedRectSliderTrackShape(),
        ),
        child: Slider(
          min: 0,
          max: max,
          value: value,
          onChanged:
              canSeek ? (next) => setState(() => _dragValue = next) : null,
          onChangeStart:
              canSeek ? (_) => setState(() => _dragValue = value) : null,
          onChangeEnd: canSeek
              ? (next) {
                  setState(() => _dragValue = null);
                  widget.player.seek(next);
                }
              : null,
        ),
      ),
    );
  }
}

class _MiniTimeLabel extends StatelessWidget {
  const _MiniTimeLabel({
    required this.value,
    this.textAlign = TextAlign.left,
  });

  final String value;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.visible,
        softWrap: false,
        textAlign: textAlign,
        style: TextStyle(
          color: context.tertiaryText,
          decoration: TextDecoration.none,
          fontSize: 11,
          fontWeight: FontWeight.w400,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.color,
    this.onPressed,
    this.onPressedWithContext,
  }) : assert(onPressed != null || onPressedWithContext != null);

  final IconData icon;
  final Color color;
  final Future<void> Function()? onPressed;
  final Future<void> Function(BuildContext context)? onPressedWithContext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final contextHandler = onPressedWithContext;
          if (contextHandler != null) {
            contextHandler(context);
            return;
          }
          onPressed?.call();
        },
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

class _MiniCollapseButton extends StatelessWidget {
  const _MiniCollapseButton({
    this.icon = Icons.keyboard_arrow_down_rounded,
    required this.color,
    required this.onPressed,
    this.plain = false,
    this.size,
    this.circleSize,
    this.iconSize,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final bool plain;
  final double? size;
  final double? circleSize;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final targetSize = size ?? (plain ? 32.0 : 48.0);
    final visualSize = circleSize ?? 38.0;
    final resolvedIconSize = iconSize ?? 22.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox(
        width: targetSize,
        height: targetSize,
        child: Center(
          child: plain
              ? Icon(icon, color: color, size: resolvedIconSize)
              : Container(
                  width: visualSize,
                  height: visualSize,
                  decoration: BoxDecoration(
                    color: context.isDark
                        ? AppColors.slate800.withValues(alpha: 0.52)
                        : AppColors.slate100.withValues(alpha: 0.86),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: resolvedIconSize,
                  ),
                ),
        ),
      ),
    );
  }
}

class _MiniTextButton extends StatelessWidget {
  const _MiniTextButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final light = _isPlayerThemeLight(color);
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onPressed(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: light ? AppColors.slate600 : color,
              decoration: TextDecoration.none,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({
    required this.icon,
    required this.onPressed,
    this.filled = false,
    this.ghost = false,
    this.diameter,
    this.iconSize,
    this.fillColor,
    this.filledIconColor,
    this.loading = false,
  });

  final IconData icon;
  final Future<void> Function() onPressed;
  final bool filled;
  final bool ghost;
  final double? diameter;
  final double? iconSize;
  final Color? fillColor;
  final Color? filledIconColor;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final size = diameter ?? (filled ? 46 : 38);
    final resolvedIconSize = iconSize ?? (filled ? 28 : 22);
    final baseColor = fillColor ?? AppColors.primary600;
    final background = filled
        ? null
        : ghost
            ? Colors.transparent
            : (context.isDark
                ? AppColors.slate800.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.72));
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: filled
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(baseColor, Colors.white, 0.16)!,
                    baseColor,
                    Color.lerp(baseColor, Colors.black, 0.12)!,
                  ],
                )
              : null,
          color: background,
          border: filled || ghost
              ? null
              : Border.all(
                  color: context.isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                ),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: baseColor.withValues(alpha: 0.42),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: context.isDark ? 0.3 : 0.08,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onPressed(),
            child: loading
                ? Center(
                    child: SizedBox(
                        width: resolvedIconSize,
                        height: resolvedIconSize,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: filled
                                ? (filledIconColor ?? Colors.white)
                                : context.mutedText)))
                : Icon(
                    icon,
                    color: filled
                        ? (filledIconColor ?? Colors.white)
                        : context.mutedText,
                    size: resolvedIconSize,
                  ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.onTapWithContext,
    this.active = false,
  }) : assert(onTap != null || onTapWithContext != null);

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Future<void> Function(BuildContext context)? onTapWithContext;
  final bool active;

  @override
  Widget build(BuildContext context) {
    const activeColor = AppColors.primary600;
    final iconColor = active ? activeColor : context.mutedText;
    return InkWell(
      onTap: () {
        final handler = onTapWithContext;
        if (handler != null) {
          handler(context);
        } else {
          onTap?.call();
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 44,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: active
                    ? activeColor.withValues(alpha: context.isDark ? 0.2 : 0.12)
                    : (context.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.03)),
                border: Border.all(
                  color: active
                      ? activeColor.withValues(alpha: 0.32)
                      : Colors.transparent,
                ),
              ),
              child: Center(
                child: Icon(icon, size: 19, color: iconColor),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.1,
                color: active ? activeColor : context.tertiaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandedDownloadAction {
  const _ExpandedDownloadAction({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;
}

class _SeekButton extends StatelessWidget {
  const _SeekButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.035),
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onPressed(),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 30, color: context.tertiaryText),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.secondaryText,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
