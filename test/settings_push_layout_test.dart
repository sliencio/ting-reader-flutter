import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ting_reader_flutter/src/features/settings_push_layout.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform 左右滑动控制设置，保留点击和纵向滚动操作', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var open = false;
      var opens = 0;
      var closes = 0;
      var clicks = 0;
      var volume = 0.2;
      const pageKey = ValueKey('swipe-page');
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        home: StatefulBuilder(builder: (context, update) {
          return SettingsPushLayout(
            open: open,
            swipeEnabled: true,
            onOpen: () => update(() {
              open = true;
              opens++;
            }),
            onClose: () => update(() {
              open = false;
              closes++;
            }),
            panel: const Material(child: Text('Settings')),
            child: Material(
              key: pageKey,
              child: ListView(children: [
                TextButton(onPressed: () => clicks++, child: const Text('Tap')),
                Slider(
                    value: volume,
                    onChanged: (value) => update(() => volume = value)),
                const SizedBox(height: 1200),
              ]),
            ),
          );
        }),
      ));
      final page = tester.element(find.byKey(pageKey));
      await tester.tap(find.text('Tap'));
      expect(clicks, 1);
      await tester.timedDragFrom(const Offset(150, 350), const Offset(20, 0),
          const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(open, isFalse);
      await tester.drag(find.byType(Slider), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(volume, greaterThan(0.2));
      expect(opens, 0);
      await tester.dragFrom(const Offset(90, 350), const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(open, isTrue);
      expect(opens, 1);
      expect(tester.getRect(find.byKey(pageKey)).left, 72);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      await tester.dragFrom(const Offset(220, 600), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));
      expect(open, isTrue);
      await tester.dragFrom(const Offset(260, 350), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(open, isFalse);
      expect(closes, 1);
      expect(identical(tester.element(find.byKey(pageKey)), page), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

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
      var clicks = 0;
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
              child: Material(
                  key: pageKey,
                  child: Center(
                      child: TextButton(
                          onPressed: () => clicks++,
                          child: const Text('Bookshelf content')))),
            );
          })));
      final before = tester.getRect(find.byKey(pageKey));
      final state = tester.element(find.byKey(pageKey));
      update(() => open = true);
      await tester.pumpAndSettle();
      final after = tester.getRect(find.byKey(pageKey));
      expect(after.left, closeTo(desktop ? 280 : 72, 0.01));
      expect(after.width, closeTo(before.width - after.left, 0.001));
      expect(after.height, closeTo(before.height, 0.001));
      expect(tester.getTopLeft(find.byKey(panelKey)).dx, 0);
      expect(identical(tester.element(find.byKey(pageKey)), state), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(pageKey)).left,
          closeTo(before.left, 0.001));
      update(() => open = true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bookshelf content'));
      await tester.pumpAndSettle();
      expect(clicks, 1);
      expect(tester.getRect(find.byKey(pageKey)).left, greaterThan(0));
      expect(
          find.descendant(
              of: find.byType(SettingsPushLayout),
              matching: find.byType(ModalBarrier)),
          findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(pageKey)).left,
          closeTo(before.left, 0.001));
      expect(tester.takeException(), isNull);
    });
  }
}
