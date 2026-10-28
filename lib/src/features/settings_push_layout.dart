import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsPushLayout extends StatefulWidget {
  const SettingsPushLayout({
    super.key,
    required this.open,
    required this.onClose,
    required this.panel,
    required this.child,
  });

  final bool open;
  final VoidCallback onClose;
  final Widget panel;
  final Widget child;

  @override
  State<SettingsPushLayout> createState() => _SettingsPushLayoutState();
}

class _SettingsPushLayoutState extends State<SettingsPushLayout> {
  final _panelFocus = FocusNode(debugLabel: '设置导航');

  void _focusPanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.open) _panelFocus.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.open) _focusPanel();
  }

  @override
  void didUpdateWidget(covariant SettingsPushLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && !oldWidget.open) _focusPanel();
  }

  @override
  void dispose() {
    _panelFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.open;
    final onClose = widget.onClose;
    final panel = widget.panel;
    final child = widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final panelWidth =
            (width >= 840 ? 280.0 : 72.0) + MediaQuery.paddingOf(context).left;
        final duration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 260);
        return CallbackShortcuts(
          bindings: {
            if (open) const SingleActivator(LogicalKeyboardKey.escape): onClose,
          },
          child: ClipRect(
            child: Stack(fit: StackFit.expand, children: [
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                left: open ? 0 : -panelWidth,
                top: 0,
                bottom: 0,
                width: panelWidth,
                child: IgnorePointer(
                  ignoring: !open,
                  child: ExcludeFocus(
                    excluding: !open,
                    child: ExcludeSemantics(
                      excluding: !open,
                      child: TickerMode(
                          enabled: open,
                          child: Focus(focusNode: _panelFocus, child: panel)),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                left: open ? panelWidth : 0,
                top: 0,
                bottom: 0,
                width: open ? (width - panelWidth).clamp(0, width) : width,
                // 左右两侧同时可用，内容根据右侧的实际宽度适配。
                child: LayoutBuilder(builder: (context, content) {
                  final media = MediaQuery.of(context);
                  return MediaQuery(
                    data: media.copyWith(
                      size: Size(content.maxWidth, content.maxHeight),
                      padding: open
                          ? media.padding.copyWith(left: 0)
                          : media.padding,
                      viewPadding: open
                          ? media.viewPadding.copyWith(left: 0)
                          : media.viewPadding,
                    ),
                    child: child,
                  );
                }),
              ),
            ]),
          ),
        );
      },
    );
  }
}
