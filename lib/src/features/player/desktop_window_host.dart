import 'package:flutter/material.dart';

import '../../core/services/desktop_window.dart';
import '../../core/utils/locale.dart';
import '../../shared/app_scope.dart';
import 'micro_player_window.dart';
import 'small_player_window.dart';

class DesktopWindowHost extends StatefulWidget {
  const DesktopWindowHost(
      {super.key, required this.child, required this.openChapters});
  final Widget child;
  final Future<void> Function() openChapters;

  @override
  State<DesktopWindowHost> createState() => _DesktopWindowHostState();
}

class _DesktopWindowHostState extends State<DesktopWindowHost> {
  final window = DesktopWindow.instance;
  bool _usesOverlay = false;
  late final OverlayEntry _scene = OverlayEntry(builder: _buildScene);

  @override
  void initState() {
    super.initState();
    window.addListener(_changed);
  }

  void _changed() => _scene.markNeedsBuild();

  @override
  void didUpdateWidget(covariant DesktopWindowHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _changed();
  }

  @override
  void dispose() {
    window.removeListener(_changed);
    if (_usesOverlay) _scene.remove();
    _scene.dispose();
    super.dispose();
  }

  Widget _buildScene(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = window.mode != DesktopWindowMode.normal;
    // 小小窗不显示标题栏，进度线直接贴顶，高度留给播放控制。
    final showTitleBar =
        (window.usesCustomTitleBar || compact) && !window.isMicro;
    if (!compact) {
      window.normalSize = Size(size.width,
          (size.height - (showTitleBar ? 34 : 0)).clamp(0, double.infinity));
    }
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(children: [
        if (showTitleBar)
          _WindowTitleBar(
            openChapters: widget.openChapters,
            compact: window.isMicro,
          ),
        Expanded(
            child: Stack(fit: StackFit.expand, children: [
          Offstage(
            offstage: compact,
            child: TickerMode(
              enabled: !compact,
              child: ExcludeFocus(
                excluding: compact,
                child: OverflowBox(
                  minWidth: window.normalSize.width,
                  maxWidth: window.normalSize.width,
                  minHeight: window.normalSize.height,
                  maxHeight: window.normalSize.height,
                  child: MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(size: window.normalSize),
                      child: widget.child),
                ),
              ),
            ),
          ),
          if (window.isMicro)
            MicroPlayerWindow(
              openChapters: widget.openChapters,
              onExpand: () => window.setMode(DesktopWindowMode.mini),
            )
          else if (window.isMini)
            SmallPlayerWindow(openChapters: widget.openChapters),
        ])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!window.supported) return widget.child;
    _usesOverlay = true;
    return Overlay(initialEntries: [_scene]);
  }
}

class _WindowTitleBar extends StatelessWidget {
  const _WindowTitleBar({required this.openChapters, this.compact = false});
  final Future<void> Function() openChapters;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final window = DesktopWindow.instance;
    final height = compact ? 28.0 : 34.0;
    final buttonWidth = compact ? 38.0 : 44.0;
    Widget button(String label, WindowCaptionAction icon,
            Future<void> Function() action,
            {bool close = false}) =>
        SizedBox(
            width: buttonWidth,
            height: height,
            child: IconButton(
              tooltip: label,
              padding: EdgeInsets.zero,
              iconSize: compact ? 14 : 17,
              style: ButtonStyle(
                shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
                backgroundColor: WidgetStateProperty.resolveWith((states) =>
                    close && states.contains(WidgetState.hovered)
                        ? Colors.red
                        : Colors.transparent),
                foregroundColor: WidgetStateProperty.resolveWith((states) =>
                    close && states.contains(WidgetState.hovered)
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface),
              ),
              icon: WindowCaptionIcon(icon),
              onPressed: action,
            ));
    return SizedBox(
        height: height,
        child: Row(children: [
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                  onPressed: AppScope.playerOf(context).hasChapter
                      ? openChapters
                      : null,
                  child: Text(context.localeText('章节列表', 'Chapters'))),
              const Divider(height: 1),
              MenuItemButton(
                  leadingIcon: Icon(
                    Icons.radio_button_checked_rounded,
                    size: 16,
                    color: window.mode == DesktopWindowMode.normal
                        ? null
                        : Colors.transparent,
                  ),
                  onPressed: () => window.setMode(DesktopWindowMode.normal),
                  child: Text(context.localeText('普通窗口', 'Normal window'))),
              MenuItemButton(
                  leadingIcon: Icon(
                    Icons.radio_button_checked_rounded,
                    size: 16,
                    color: window.isMini ? null : Colors.transparent,
                  ),
                  onPressed: () => window.setMode(DesktopWindowMode.mini),
                  child: Text(context.localeText('小窗模式', 'Mini window'))),
              MenuItemButton(
                  leadingIcon: Icon(
                    Icons.radio_button_checked_rounded,
                    size: 16,
                    color: window.isMicro ? null : Colors.transparent,
                  ),
                  onPressed: () => window.setMode(DesktopWindowMode.micro),
                  child: Text(context.localeText('小小窗模式', 'Micro window'))),
              const Divider(height: 1),
              MenuItemButton(
                  onPressed: window.requestExit,
                  child: Text(context.localeText('退出软件', 'Exit application'))),
            ],
            builder: (context, controller, _) => SizedBox(
                width: compact ? 34 : 48,
                height: height,
                child: IconButton(
                    tooltip: context.localeText('窗口菜单', 'Window menu'),
                    padding: EdgeInsets.zero,
                    iconSize: compact ? 15 : 18,
                    icon: const Icon(Icons.headphones_rounded),
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open())),
          ),
          Expanded(
              child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => window.startDragging(),
            onDoubleTap: compact ? null : window.toggleMaximize,
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    context.localeText(
                        window.isMicro
                            ? '听悦 · 小小窗'
                            : window.isMini
                                ? '听悦 · 小窗'
                                : '听悦',
                        window.isMicro
                            ? 'Ting Reader · Micro'
                            : window.isMini
                                ? 'Ting Reader · Mini'
                                : 'Ting Reader'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge)),
          )),
          button(
              context.localeText(window.isMicro ? '放大小窗' : '小小窗模式',
                  window.isMicro ? 'Enlarge window' : 'Micro window'),
              window.isMicro
                  ? WindowCaptionAction.restore
                  : WindowCaptionAction.micro,
              () => window.setMode(window.isMicro
                  ? DesktopWindowMode.mini
                  : DesktopWindowMode.micro)),
          if (!window.isMicro)
            button(
                context.localeText(window.isMini ? '返回主窗口' : '小窗模式',
                    window.isMini ? 'Restore window' : 'Mini window'),
                window.isMini
                    ? WindowCaptionAction.restore
                    : WindowCaptionAction.mini,
                () => window.setMode(window.isMini
                    ? DesktopWindowMode.normal
                    : DesktopWindowMode.mini)),
          if (!window.isMicro)
            button(context.localeText('最小化', 'Minimize'),
                WindowCaptionAction.minimize, window.minimize),
          if (window.mode == DesktopWindowMode.normal)
            button(
                context.localeText(window.isMaximized ? '还原' : '最大化',
                    window.isMaximized ? 'Restore size' : 'Maximize'),
                window.isMaximized
                    ? WindowCaptionAction.restore
                    : WindowCaptionAction.maximize,
                window.toggleMaximize),
          button(context.localeText('关闭', 'Close'), WindowCaptionAction.close,
              window.close,
              close: true),
        ]));
  }
}

enum WindowCaptionAction { micro, mini, restore, minimize, maximize, close }

class WindowCaptionIcon extends StatelessWidget {
  const WindowCaptionIcon(this.action, {super.key});
  final WindowCaptionAction action;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size.square(18),
        painter: _WindowCaptionPainter(
            action,
            IconTheme.of(context).color ??
                Theme.of(context).colorScheme.onSurface),
      );
}

class _WindowCaptionPainter extends CustomPainter {
  const _WindowCaptionPainter(this.action, this.color);
  final WindowCaptionAction action;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 窗口控制直接绘制线条，不依赖发布版图标字体。
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.scale(size.width / 18, size.height / 18);
    switch (action) {
      case WindowCaptionAction.minimize:
        canvas.drawLine(const Offset(3, 9), const Offset(15, 9), paint);
      case WindowCaptionAction.maximize:
        canvas.drawRect(const Rect.fromLTWH(3, 3, 12, 12), paint);
      case WindowCaptionAction.close:
        canvas.drawLine(const Offset(4, 4), const Offset(14, 14), paint);
        canvas.drawLine(const Offset(14, 4), const Offset(4, 14), paint);
      case WindowCaptionAction.restore:
        canvas.drawRect(const Rect.fromLTWH(3, 6, 9, 9), paint);
        canvas.drawPath(
            Path()
              ..moveTo(6, 6)
              ..lineTo(6, 3)
              ..lineTo(15, 3)
              ..lineTo(15, 12)
              ..lineTo(12, 12),
            paint);
      case WindowCaptionAction.mini:
        canvas.drawRect(const Rect.fromLTWH(2, 3, 14, 12), paint);
        canvas.drawRect(const Rect.fromLTWH(9, 9, 5, 4), paint);
      case WindowCaptionAction.micro:
        canvas.drawRect(const Rect.fromLTWH(2, 3, 14, 12), paint);
        canvas.drawRect(const Rect.fromLTWH(9, 10, 6, 4), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WindowCaptionPainter oldDelegate) =>
      oldDelegate.action != action || oldDelegate.color != color;
}
