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

  test('failed native resize restores the previous mini state', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'resize_failed'));
    final window = DesktopWindow();
    addTearDown(window.dispose);
    await expectLater(window.setMini(true), throwsA(isA<PlatformException>()));
    expect(window.isMini, isFalse);
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
