import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';

class DesktopWindow extends ChangeNotifier {
  static final instance = DesktopWindow();
  static const _channel = MethodChannel('ting_reader/window');
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool isMini = false;
  Size normalSize = const Size(1280, 720);
  String closeBehavior = 'ask';
  bool isMaximized = false;
  Future<void> Function()? onCloseRequested;
  Future<void> Function()? onExitRequested;
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

  Future<void> setMini(bool value) async {
    if (!supported || value == isMini) return;
    isMini = value;
    notifyListeners();
    try {
      await _channel.invokeMethod<void>('setMiniMode', value);
    } catch (_) {
      isMini = !value;
      notifyListeners();
      rethrow;
    }
  }

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
