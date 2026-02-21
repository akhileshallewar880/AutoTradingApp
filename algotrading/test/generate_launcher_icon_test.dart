// Run once with:  flutter test test/generate_launcher_icon_test.dart
// This renders VanTradeLogoWidget at 1024×1024 and saves it to
// assets/vantrade_launcher_icon.png for use with flutter_launcher_icons.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:algotrading/widgets/vantrade_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('generate_launcher_icon', (WidgetTester tester) async {
    // Render the logo at 512 logical pixels, then capture at 2× → 1024 px PNG
    const double logoSize = 512;
    const double targetPx = 1024;
    const double pixelRatio = targetPx / logoSize;

    final key = GlobalKey();

    // Give the test surface enough room
    tester.view.physicalSize = const Size(logoSize + 200, logoSize + 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          // transparent → only the green rounded-rect will be opaque
          backgroundColor: Colors.transparent,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: const VanTradeLogoWidget(size: logoSize),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    final outFile = File('assets/vantrade_launcher_icon.png');
    await outFile.writeAsBytes(byteData!.buffer.asUint8List());

    // ignore: avoid_print
    print('✓ Launcher icon saved → ${outFile.absolute.path}');
    expect(outFile.existsSync(), isTrue);
  });
}
