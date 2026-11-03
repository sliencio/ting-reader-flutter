import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';

/// 桌面窗口的三种形态：普通窗口、小窗、小小窗。
enum DesktopWindowMode { normal, mini, micro }

class DesktopWindow extends ChangeNotifier {
  static final instance = DesktopWindow();
  static const _channel = MethodChannel('ting_reader/window');
  bool get supported =>
      !kIsWeb &&
      [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux]
          .contains(defaultTargetPlatform);
  bool get usesCustomTitleBar =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  DesktopWindowMode _mode = DesktopWindowMode.normal;
  DesktopWindowMode get mode => _mode;
  bool get isMini => _mode == DesktopWindowMode.mini;
  bool get isMicro => _mode == DesktopWindowMode.micro;
  Size normalSize = const Size(1280, 720);
  String closeBehavior = 'ask';
  bool isMaximized = false;
  Future<void> Function()? onCloseRequested;
  Future<void> Function()? onExitRequested;

  /// 系统媒体键（WM_APPCOMMAND）回调：playPause / next / previous / forward / rewind。
  void Function(String command)? mediaCommand;
  AppState? _app;
  VoidCallback? _syncPreferences;

  Future<void> initialize(AppState app) async {
    if (!supported) return;
    final previousSync = _syncPreferences;
    if (previousSync != null) _app?.removeListener(previousSync);
    _app = app;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'closeRequested') await onCloseRequested?.call();
      if (call.method == 'maximizedChanged') {
        final value = call.arguments == true;
        if (isMaximized != value) {
          isMaximized = value;
          notifyListeners();
        }
      }
      if (call.method == 'mediaCommand') {
        final command = call.arguments;
        if (command is String) mediaCommand?.call(command);
      }
    });
    void sync() {
      final value = app.settings['desktop_close_behavior']?.toString();
      final next = ['exit', 'minimize'].contains(value) ? value! : 'ask';
      if (next == closeBehavior) return;
      closeBehavior = next;
      _channel.invokeMethod<void>('setCloseBehavior', next);
      notifyListeners();
    }

    _syncPreferences = sync;
    app.addListener(sync);
    sync();
  }

  Future<void> setMode(DesktopWindowMode value) async {
    if (!supported || value == _mode) return;
    final previous = _mode;
    _mode = value;
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('setWindowMode', value.name);
    } catch (_) {
      _mode = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setMini(bool value) =>
      setMode(value ? DesktopWindowMode.mini : DesktopWindowMode.normal);

  Future<void> minimize() => _channel.invokeMethod<void>('minimize');
  Future<void> exit() => _channel.invokeMethod<void>('exit');
  Future<void> close() => _channel.invokeMethod<void>('close');
  Future<void> startDragging() => _channel.invokeMethod<void>('startDragging');

  Future<void> toggleMaximize() async {
    isMaximized = await _channel.invokeMethod<bool>('toggleMaximize') ?? false;
    notifyListeners();
  }

  Future<void> requestExit() async {
    final handler = onExitRequested;
    if (handler != null) {
      await handler();
    } else {
      await exit();
    }
  }

  @override
  void dispose() {
    final sync = _syncPreferences;
    if (sync != null) _app?.removeListener(sync);
    super.dispose();
  }
}
