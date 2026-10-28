import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ting_reader_flutter/src/core/services/desktop_window.dart';
import 'package:ting_reader_flutter/src/core/state/app_state.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ting_reader/window');
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  test('mini mode toggles the existing native window', () async {
    final window = DesktopWindow();
    addTearDown(window.dispose);
    await window.setMini(true);
    expect(window.isMini, isTrue);
    await window.setMini(false);
    expect(window.isMini, isFalse);
    expect(calls.map((call) => call.method), ['setMiniMode', 'setMiniMode']);
    expect(calls.map((call) => call.arguments), [true, false]);
  });

  for (final platform in TargetPlatform.values) {
    test('desktop window capability is scoped correctly on $platform',
        () async {
      debugDefaultTargetPlatformOverride = platform;
      final window = DesktopWindow();
      addTearDown(window.dispose);
      final desktop = [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux
      ].contains(platform);
      expect(window.supported, desktop);
      expect(window.usesCustomTitleBar, platform == TargetPlatform.windows);
      await window.setMini(true);
      expect(window.isMini, desktop);
      expect(calls.length, desktop ? 1 : 0);
    });
  }

  test('failed native resize restores the previous mini state', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'resize_failed'));
    final window = DesktopWindow();
    addTearDown(window.dispose);
    await expectLater(window.setMini(true), throwsA(isA<PlatformException>()));
    expect(window.isMini, isFalse);
  });

  test('caption controls and explicit exit remain available in minimize mode',
      () async {
    final window = DesktopWindow()..closeBehavior = 'minimize';
    addTearDown(window.dispose);
    await window.close();
    await window.startDragging();
    await window.toggleMaximize();
    await window.requestExit();
    expect(calls.map((call) => call.method),
        ['close', 'startDragging', 'toggleMaximize', 'exit']);
    expect(window.closeBehavior, 'minimize');
  });

  test('saved close preference reaches the native window', () async {
    final app = AppState()..settings = {'desktop_close_behavior': 'minimize'};
    final window = DesktopWindow();
    addTearDown(app.dispose);
    addTearDown(window.dispose);
    await window.initialize(app);
    expect(calls.single.method, 'setCloseBehavior');
    expect(calls.single.arguments, 'minimize');
    app.settings = {'desktop_close_behavior': 'exit'};
    app.notifyListeners();
    expect(calls.last.arguments, 'exit');
    await window.minimize();
    await window.exit();
    expect(calls.map((call) => call.method),
        ['setCloseBehavior', 'setCloseBehavior', 'minimize', 'exit']);
  });
}
