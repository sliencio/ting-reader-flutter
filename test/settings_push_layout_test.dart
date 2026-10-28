import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ting_reader_flutter/src/features/settings_push_layout.dart';

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux
  ]) {
    testWidgets('settings push the full page on $platform', (tester) async {
      final desktop = [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux
      ].contains(platform);
      final size = desktop ? const Size(1440, 1000) : const Size(390, 844);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const pageKey = ValueKey('main-page');
      const panelKey = ValueKey('settings-panel');
      var open = false;
      late StateSetter update;
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(platform: platform),
          home: StatefulBuilder(builder: (context, setState) {
            update = setState;
            return SettingsPushLayout(
              open: open,
              onClose: () => update(() => open = false),
              panel: const Material(
                  key: panelKey, child: Text('Settings content')),
              child: const Material(
                  key: pageKey, child: Text('Bookshelf content')),
            );
          })));
      final before = tester.getRect(find.byKey(pageKey));
      final state = tester.element(find.byKey(pageKey));
      update(() => open = true);
      await tester.pumpAndSettle();
      final after = tester.getRect(find.byKey(pageKey));
      expect(after.left, closeTo(desktop ? 420 : size.width * 0.88, 0.01));
      expect(after.width, closeTo(before.width, 0.001));
      expect(after.height, closeTo(before.height, 0.001));
      expect(tester.getTopLeft(find.byKey(panelKey)).dx, 0);
      expect(identical(tester.element(find.byKey(pageKey)), state), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(pageKey)).left,
          closeTo(before.left, 0.001));
      update(() => open = true);
      await tester.pumpAndSettle();
      await tester.tapAt(Offset(size.width - 8, size.height / 2));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(pageKey)).left,
          closeTo(before.left, 0.001));
      expect(tester.takeException(), isNull);
    });
  }
}
