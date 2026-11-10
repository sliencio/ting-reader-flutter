import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/desktop_window.dart';
import '../../shared/app_scope.dart';

/// 全局播放快捷键：媒体键、空格与左右方向键。
///
/// 媒体键在 Windows 上既可能以按键事件到达，也可能经 WM_APPCOMMAND 转成
/// [DesktopWindow.mediaCommand] 到达，因此按下后短时间内重复的同名指令会被
/// 丢弃，避免一次按键触发两次播放/暂停。
///
/// 按键走 [HardwareKeyboard] 的全局处理器，而不是 `CallbackShortcuts`：
/// 后者挂在焦点链上，只有当前有焦点节点时才收得到事件。窗口在后台失焦后，
/// Flutter 会把焦点收回到根 scope；重新激活时如果没有节点主动要焦点，
/// 焦点就是空的，于是快捷键要先把窗口点一下才生效。全局处理器不依赖焦点，
/// 窗口处于前台就能响应。
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
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
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

  /// 把按键映射成播放指令；返回 null 表示这个键与播放无关。
  String? _commandFor(LogicalKeyboardKey key) => switch (key) {
        LogicalKeyboardKey.space => 'playPause',
        LogicalKeyboardKey.mediaPlayPause => 'playPause',
        LogicalKeyboardKey.mediaTrackNext => 'next',
        LogicalKeyboardKey.mediaTrackPrevious => 'previous',
        LogicalKeyboardKey.arrowRight => 'forward',
        LogicalKeyboardKey.arrowLeft => 'rewind',
        _ => null,
      };

  /// 只在按下时触发一次；KeyUp 与长按重复不重复执行。
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final command = _commandFor(event.logicalKey);
    if (command == null) return false;
    // 空格和方向键在输入框里要照常输入；媒体键不受此限制。
    final isMediaKey = event.logicalKey == LogicalKeyboardKey.mediaPlayPause ||
        event.logicalKey == LogicalKeyboardKey.mediaTrackNext ||
        event.logicalKey == LogicalKeyboardKey.mediaTrackPrevious;
    if (!isMediaKey && _editingText) return false;
    if (!AppScope.playerOf(context).hasChapter) return false;
    // 去重只针对媒体键：它在 Windows 上会同时以按键事件和 WM_APPCOMMAND
    // 两份到达，必须合并。空格与方向键只有一个来源，去重反而会把用户
    // 连着按的第二下吞掉。
    _handleCommand(command, dedupe: isMediaKey);
    return true;
  }

  void _handleCommand(String command, {bool dedupe = true}) {
    if (dedupe) {
      final now = DateTime.now();
      final last = _lastHandled[command];
      if (last != null && now.difference(last) < _duplicateWindow) return;
      _lastHandled[command] = now;
    }
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

  @override
  Widget build(BuildContext context) => widget.child;
}
