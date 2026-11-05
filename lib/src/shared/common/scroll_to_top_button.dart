import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/locale.dart';

/// 右下角浮动的「回到顶部」按钮。
///
/// 直接包在页面内容外层，监听所有竖直方向的滚动通知：只有页面确实可以滚动、
/// 且已经向下滚过一段距离时才浮现。放到这一层做，书架、详情、设置等页面都
/// 自动具备这个能力，不必每个页面各写一遍滚动控制器。
class ScrollToTopButton extends StatefulWidget {
  const ScrollToTopButton({
    super.key,
    required this.child,
    this.bottom = 16,
    this.right = 16,
  });

  final Widget child;

  /// 距内容区底部的距离；播放条浮起来时由调用方把距离抬高。
  final double bottom;
  final double right;

  @override
  State<ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<ScrollToTopButton> {
  /// 滚过这么多才显示，避免刚滑一点点就冒出按钮。
  static const double _showAfter = 240;

  static const Duration _fadeDuration = Duration(milliseconds: 180);
  static const Duration _scrollDuration = Duration(milliseconds: 320);

  /// 最近一次滚动来自哪个滚动视图，点击时据此找回它的位置。
  BuildContext? _scrollContext;
  bool _visible = false;

  bool _handleScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    // 只认最外层的竖直滚动：横向列表、章节横滑等嵌套滚动都会带上更深的
    // depth，忽略它们，否则按钮会被无关的滑动晃出来。
    if (notification.depth != 0 || metrics.axis != Axis.vertical) return false;
    if (!metrics.hasPixels || !metrics.hasContentDimensions) return false;

    _scrollContext = notification.context ?? _scrollContext;
    final visible = metrics.maxScrollExtent > 0 && metrics.pixels > _showAfter;
    if (visible != _visible) {
      setState(() => _visible = visible);
    }
    return false;
  }

  void _scrollToTop() {
    final position =
        _scrollContext?.findAncestorStateOfType<ScrollableState>()?.position;
    if (position == null || !position.hasPixels) return;
    position.animateTo(
      0,
      duration: _scrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: widget.child,
          ),
        ),
        Positioned(
          right: widget.right,
          bottom: widget.bottom,
          child: IgnorePointer(
            ignoring: !_visible,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: _fadeDuration,
              curve: Curves.easeOut,
              child: AnimatedScale(
                scale: _visible ? 1 : 0.86,
                duration: _fadeDuration,
                curve: Curves.easeOutCubic,
                child: _buildButton(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildButton(BuildContext context) {
    return Tooltip(
      message: context.localeText('回到顶部', 'Back to top'),
      child: Material(
        color: context.cardColor,
        elevation: context.isDark ? 0 : 2,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        shape: CircleBorder(side: BorderSide(color: context.faintBorder)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _scrollToTop,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 24,
              color: context.isDark ? AppColors.slate200 : AppColors.slate600,
            ),
          ),
        ),
      ),
    );
  }
}
