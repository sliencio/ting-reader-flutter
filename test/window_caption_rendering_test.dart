import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ting_reader_flutter/src/features/player/desktop_window_host.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final action in WindowCaptionAction.values) {
      testWidgets('caption $action paints visible lines in $brightness',
          (tester) async {
        final key = GlobalKey();
        final background =
            brightness == Brightness.dark ? Colors.black : Colors.white;
        final foreground =
            brightness == Brightness.dark ? Colors.white : Colors.black;
        await tester.pumpWidget(MaterialApp(
            home: Center(
                child: RepaintBoundary(
          key: key,
          child: ColoredBox(
              color: background,
              child: SizedBox(
                width: 44,
                height: 34,
                child: Center(
                    child: IconTheme(
                  data: IconThemeData(color: foreground),
                  child: WindowCaptionIcon(action),
                )),
              )),
        ))));
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final pixels = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          } finally {
            image.dispose();
          }
        });
        var visible = 0;
        for (var offset = 0; offset < pixels!.lengthInBytes; offset += 4) {
          final red = pixels.getUint8(offset);
          if (brightness == Brightness.dark ? red > 128 : red < 128) visible++;
        }
        expect(visible, greaterThan(12));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
