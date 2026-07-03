import 'dart:typed_data';

import 'dart:ui' as ui;
import 'package:flutter/widgets.dart' show TextScaler;
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('underline cursor is painted at the requested row offset', () async {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    const offset = ui.Offset(10, 20);

    final image = await _paintCursor(
      painter,
      offset,
      TerminalCursorType.underline,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final byteData = bytes;
    if (byteData == null) {
      fail('Expected cursor image bytes');
    }

    final expectedY = (offset.dy + painter.cellSize.height - 1).round();
    expect(
      _hasAlphaInRow(byteData, image.width, expectedY),
      isTrue,
    );
    expect(
      _hasAlphaInRow(
          byteData, image.width, painter.cellSize.height.round() - 1),
      isFalse,
    );

    image.dispose();
  });

  test('vertical bar cursor is painted at the requested row offset', () async {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    const offset = ui.Offset(10, 20);

    final image = await _paintCursor(
      painter,
      offset,
      TerminalCursorType.verticalBar,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final byteData = bytes;
    if (byteData == null) {
      fail('Expected cursor image bytes');
    }

    final expectedX = offset.dx.round();
    expect(
      _hasAlphaInColumn(byteData, image.width, expectedX, offset.dy.round()),
      isTrue,
    );
    expect(
      _hasAlphaInColumn(byteData, image.width, expectedX, 0),
      isFalse,
    );

    image.dispose();
  });
}

Future<ui.Image> _paintCursor(
  TerminalPainter painter,
  ui.Offset offset,
  TerminalCursorType cursorType,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  painter.paintCursor(
    canvas,
    offset,
    cursorType: cursorType,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(80, 80);
  picture.dispose();
  return image;
}

bool _hasAlphaInRow(ByteData byteData, int width, int y) {
  for (var x = 0; x < width; x++) {
    final alpha = byteData.getUint8((y * width + x) * 4 + 3);
    if (alpha != 0) {
      return true;
    }
  }
  return false;
}

bool _hasAlphaInColumn(ByteData byteData, int width, int x, int startY) {
  for (var y = startY; y < startY + 20; y++) {
    final alpha = byteData.getUint8((y * width + x) * 4 + 3);
    if (alpha != 0) {
      return true;
    }
  }
  return false;
}
