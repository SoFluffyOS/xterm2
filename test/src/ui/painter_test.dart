import 'dart:typed_data';

import 'dart:ui' as ui;
import 'package:flutter/widgets.dart'
    show TextDecoration, TextDecorationStyle, TextScaler;
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('reverse display swaps normal cell backgrounds', () {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(),
      textScaler: TextScaler.noScaling,
    );
    final cell = CellData.empty();

    expect(painter.resolveCellBackgroundColor(cell), isNull);

    painter.reverseDisplay = true;
    expect(
      painter.resolveCellBackgroundColor(cell),
      TerminalThemes.whiteOnBlack.foreground,
    );

    cell.flags = CellFlags.inverse;
    expect(painter.resolveCellBackgroundColor(cell), isNull);
    painter.dispose();
  });

  test('paintLine hides blinking text during the off phase', () async {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final terminal = Terminal()..write('\x1b[5mX');
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    final hasBlinkingText = painter.paintLine(
      canvas,
      Offset.zero,
      terminal.buffer.lines[0],
      blinkVisible: false,
    );

    expect(hasBlinkingText, isTrue);
    expect(painter.paragraphCacheLength, 0);

    painter.paintLine(canvas, Offset.zero, terminal.buffer.lines[0]);
    expect(painter.paragraphCacheLength, 1);

    recorder.endRecording().dispose();
    painter.dispose();
  });

  test('paintLine shapes combining characters with their base glyph', () async {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final baseTerminal = Terminal()..write('X');
    final combinedTerminal = Terminal()..write('X\u0338');
    expect(
      combinedTerminal.buffer.lines[0].getCombiningCharacters(0),
      '\u0338',
    );

    final baseImage = await _paintLine(
      painter,
      baseTerminal.buffer.lines[0],
    );
    final combinedImage = await _paintLine(
      painter,
      combinedTerminal.buffer.lines[0],
    );

    expect(painter.paragraphCacheLength, 2);
    expect(combinedTerminal.buffer.cursorX, 1);

    baseImage.dispose();
    combinedImage.dispose();
  });

  test('TerminalStyle combines text decorations', () {
    final style = const TerminalStyle().toTextStyle(
      decorationColor: const ui.Color(0xFFFF0000),
      underline: true,
      decorationStyle: TextDecorationStyle.dashed,
      strikethrough: true,
      overline: true,
    );
    final decoration = style.decoration;
    if (decoration == null) {
      fail('Expected text decoration');
    }

    expect(decoration.contains(TextDecoration.underline), isTrue);
    expect(decoration.contains(TextDecoration.lineThrough), isTrue);
    expect(decoration.contains(TextDecoration.overline), isTrue);
    expect(style.decorationStyle, TextDecorationStyle.dashed);
    expect(style.decorationColor, const ui.Color(0xFFFF0000));
  });

  test('TerminalStyle renders double underline style', () {
    final style = const TerminalStyle().toTextStyle(
      doubleUnderline: true,
      decorationStyle: TextDecorationStyle.dashed,
    );

    expect(style.decoration, TextDecoration.underline);
    expect(style.decorationStyle, TextDecorationStyle.double);
  });

  test('paintLine strikes through procedural glyphs', () async {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final line = BufferLine(1);
    final style = CursorStyle()..setStrikethrough();
    line.setCell(0, 0x2502, 1, style);

    final image = await _paintLine(painter, line);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final byteData = bytes;
    if (byteData == null) {
      fail('Expected line image bytes');
    }

    final strikeY = (painter.cellSize.height / 2).round();
    expect(_hasAlphaNear(byteData, image.width, 1, strikeY), isTrue);

    image.dispose();
  });

  test('paintLine skips invisible cell foregrounds', () async {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final line = BufferLine(1);
    final style = CursorStyle()..setInvisible();
    line.setCell(0, 'X'.codeUnitAt(0), 1, style);

    final image = await _paintLine(painter, line);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final byteData = bytes;
    if (byteData == null) {
      fail('Expected line image bytes');
    }

    expect(_hasAnyAlpha(byteData, image.width, image.height), isFalse);

    image.dispose();
  });

  test('paintLine batches same-color backgrounds without seams', () async {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final line = BufferLine(4);
    for (var i = 0; i < line.length; i++) {
      line.setBackground(i, CellColor.rgb | 0x123456);
    }

    final image = await _paintLine(painter, line);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final byteData = bytes;
    if (byteData == null) {
      fail('Expected line image bytes');
    }

    final paintedWidth = (painter.cellSize.width * line.length).ceil();
    final y = (painter.cellSize.height / 2).round();
    for (var x = 0; x < paintedWidth; x++) {
      final alpha = _alphaAt(byteData, image.width, x, y);
      expect(alpha, greaterThan(0));
    }

    image.dispose();
  });

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

Future<ui.Image> _paintLine(
  TerminalPainter painter,
  BufferLine line,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  painter.paintLine(
    canvas,
    ui.Offset.zero,
    line,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(120, 40);
  picture.dispose();
  return image;
}

bool _hasAlphaInRow(ByteData byteData, int width, int y) {
  for (var x = 0; x < width; x++) {
    final alpha = _alphaAt(byteData, width, x, y);
    if (alpha != 0) {
      return true;
    }
  }
  return false;
}

bool _hasAlphaInColumn(ByteData byteData, int width, int x, int startY) {
  for (var y = startY; y < startY + 20; y++) {
    final alpha = _alphaAt(byteData, width, x, y);
    if (alpha != 0) {
      return true;
    }
  }
  return false;
}

int _alphaAt(ByteData byteData, int width, int x, int y) {
  return byteData.getUint8((y * width + x) * 4 + 3);
}

bool _hasAnyAlpha(ByteData byteData, int width, int height) {
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (_alphaAt(byteData, width, x, y) != 0) {
        return true;
      }
    }
  }
  return false;
}

bool _hasAlphaNear(ByteData byteData, int width, int x, int y) {
  for (var offsetY = -1; offsetY <= 1; offsetY++) {
    if (_alphaAt(byteData, width, x, y + offsetY) != 0) {
      return true;
    }
  }
  return false;
}
