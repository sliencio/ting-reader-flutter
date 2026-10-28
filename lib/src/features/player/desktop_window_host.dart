import 'package:flutter/material.dart';

import '../../core/services/desktop_window.dart';
import '../../core/utils/locale.dart';
import '../../shared/app_scope.dart';
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
    if (!window.isMini) {
      window.normalSize =
          Size(size.width, (size.height - 34).clamp(0, double.infinity));
    }
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(children: [
        _WindowTitleBar(openChapters: widget.openChapters),
        Expanded(
            child: Stack(fit: StackFit.expand, children: [
          Offstage(
            offstage: window.isMini,
            child: TickerMode(
              enabled: !window.isMini,
              child: ExcludeFocus(
                excluding: window.isMini,
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
          if (window.isMini)
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
  const _WindowTitleBar({required this.openChapters});
  final Future<void> Function() openChapters;

  @override
  Widget build(BuildContext context) {
    final window = DesktopWindow.instance;
    Widget button(String label, IconData icon, Future<void> Function() action,
            {bool close = false}) =>
        SizedBox(
            width: 44,
            height: 34,
            child: IconButton(
              tooltip: label,
              padding: EdgeInsets.zero,
              iconSize: 17,
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
              icon: Icon(icon),
              onPressed: action,
            ));
    return SizedBox(
        height: 34,
        child: Row(children: [
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                  onPressed: AppScope.playerOf(context).hasChapter
                      ? openChapters
                      : null,
                  child: Text(context.localeText('章节列表', 'Chapters'))),
              MenuItemButton(
                  onPressed: window.requestExit,
                  child: Text(context.localeText('退出软件', 'Exit application'))),
            ],
            builder: (context, controller, _) => IconButton(
                tooltip: context.localeText('窗口菜单', 'Window menu'),
                icon: const Icon(Icons.headphones_rounded, size: 18),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open()),
          ),
          Expanded(
              child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => window.startDragging(),
            onDoubleTap: window.isMini ? null : window.toggleMaximize,
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    context.localeText(window.isMini ? '听悦 · 小窗' : '听悦',
                        window.isMini ? 'Ting Reader · Mini' : 'Ting Reader'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge)),
          )),
          button(
              context.localeText(window.isMini ? '返回主窗口' : '小窗模式',
                  window.isMini ? 'Restore window' : 'Mini window'),
              window.isMini
                  ? Icons.open_in_full_rounded
                  : Icons.picture_in_picture_alt_rounded,
              () => window.setMini(!window.isMini)),
          button(context.localeText('最小化', 'Minimize'), Icons.remove_rounded,
              window.minimize),
          if (!window.isMini)
            button(
                context.localeText(window.isMaximized ? '还原' : '最大化',
                    window.isMaximized ? 'Restore size' : 'Maximize'),
                window.isMaximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                window.toggleMaximize),
          button(context.localeText('关闭', 'Close'), Icons.close_rounded,
              window.close,
              close: true),
        ]));
  }
}
