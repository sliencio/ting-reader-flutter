import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsPushLayout extends StatelessWidget {
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
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final panelWidth = (width * 0.88).clamp(0.0, 420.0);
          final duration = MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 260);
          return CallbackShortcuts(
            bindings: {
              if (open)
                const SingleActivator(LogicalKeyboardKey.escape): onClose,
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
                            child: Focus(autofocus: open, child: panel)),
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
                  width: width,
                  // 平移整个页面，避免打开设置时重排书架和播放条。
                  child: Stack(fit: StackFit.expand, children: [
                    ExcludeFocus(
                      excluding: open,
                      child: ExcludeSemantics(
                        excluding: open,
                        child: IgnorePointer(ignoring: open, child: child),
                      ),
                    ),
                    if (open)
                      ModalBarrier(
                        color: Colors.black.withValues(alpha: 0.12),
                        onDismiss: onClose,
                        semanticsLabel: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                      ),
                  ]),
                ),
              ]),
            ),
          );
        },
      );
}
