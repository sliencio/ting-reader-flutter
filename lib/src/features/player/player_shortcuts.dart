import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/desktop_window.dart';
import '../../shared/app_scope.dart';

/// 全局播放快捷键：媒体键、空格与左右方向键。
///
/// 媒体键在 Windows 上既可能以按键事件到达，也可能经 WM_APPCOMMAND 转成
/// [DesktopWindow.mediaCommand] 到达，因此按下后短时间内重复的同名指令会被
/// 丢弃，避免一次按键触发两次播放/暂停。
class PlayerShortcuts extends StatefulWidget {
  const PlayerShortcuts({super.key, required this.child});

  final Widget child;

  @override
  State<PlayerShortcuts> createState() => _PlayerShortcutsState();
}

class _PlayerShortcutsState extends State<PlayerShortcuts> {
  static const _seekStep = 15.0;
  static const _duplicateWindow = Duration(milliseconds: 300);

  final Map<String, DateTime> _lastHandled = {};

  @override
  void initState() {
    super.initState();
    DesktopWindow.instance.mediaCommand = _handleCommand;
  }

  @override
  void dispose() {
    if (DesktopWindow.instance.mediaCommand == _handleCommand) {
      DesktopWindow.instance.mediaCommand = null;
    }
    super.dispose();
  }

  /// 文本输入时让空格和方向键照常输入，不触发播放控制。
  bool get _editingText {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (focusContext.widget is EditableText) return true;
    var editing = false;
    focusContext.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        editing = true;
        return false;
      }
      return true;
    });
    return editing;
  }

  void _handleCommand(String command) {
    final now = DateTime.now();
    final last = _lastHandled[command];
    if (last != null && now.difference(last) < _duplicateWindow) return;
    _lastHandled[command] = now;

    final player = AppScope.playerOf(context);
    if (!player.hasChapter) return;
    switch (command) {
      case 'playPause':
        player.togglePlay();
      case 'next':
        player.nextChapter();
      case 'previous':
        player.previousChapter();
      case 'forward':
        player.seek((player.currentTime + _seekStep)
            .clamp(0, player.duration > 0 ? player.duration : double.infinity)
            .toDouble());
      case 'rewind':
        player.seek((player.currentTime - _seekStep)
            .clamp(0, double.infinity)
            .toDouble());
    }
  }

  void _guarded(VoidCallback action) {
    if (_editingText) return;
    action();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _guarded(() => _handleCommand('playPause')),
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
            _handleCommand('playPause'),
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () =>
            _handleCommand('next'),
        const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () =>
            _handleCommand('previous'),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _guarded(() => _handleCommand('forward')),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _guarded(() => _handleCommand('rewind')),
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: widget.child,
      ),
    );
  }
}
