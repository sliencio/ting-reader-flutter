import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ting_reader_flutter/l10n/app_localizations.dart';
import 'package:ting_reader_flutter/src/features/player/playback_settings_dialog.dart';

Future<void> openSettings(WidgetTester tester,
    {required Future<void> Function(int, int) onSave}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<bool>(
            context: context,
            builder: (_) => PlaybackSettingsDialog(
              intro: 0,
              outro: 0,
              volume: 1,
              onVolumeChanged: (_) {},
              onSave: onSave,
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform 键盘弹出时保存按钮可点击，键盘可以显式收起', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      (int, int)? saved;
      await openSettings(tester, onSave: (intro, outro) async {
        saved = (intro, outro);
      });
      final intro = find.byKey(const ValueKey('skip_intro'));
      final outro = find.byKey(const ValueKey('skip_outro'));
      await tester.enterText(intro, '30');
      await tester.enterText(outro, '15');
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(380));
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Hide keyboard'));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.showKeyboard(outro);
      await tester.tap(find.text('Playback Settings'));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.showKeyboard(outro);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved, (30, 15));
      expect(find.byType(PlaybackSettingsDialog), findsNothing);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('秒数无效时保留面板，保存过程中不重复提交', (tester) async {
    final pending = Completer<void>();
    var saves = 0;
    await openSettings(tester, onSave: (_, __) {
      saves++;
      return pending.future;
    });
    final intro = find.byKey(const ValueKey('skip_intro'));
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.enterText(intro, '999999999999999999999999999999');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('Enter a valid number of seconds'), findsOneWidget);
    await tester.enterText(intro, '30');
    await tester.tap(save);
    await tester.pump();
    await tester.tap(save);
    expect(saves, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(PlaybackSettingsDialog), findsNothing);
  });
}
