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

  test('paintLine splits backgrounds from foreground glyphs', () async {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final terminal = Terminal()..write('\x1b[48;2;12;34;56mX');
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    painter.paintLineBackgrounds(canvas, Offset.zero, terminal.buffer.lines[0]);
    expect(painter.paragraphCacheLength, 0);

    painter.paintLineForegrounds(canvas, Offset.zero, terminal.buffer.lines[0]);
    expect(painter.paragraphCacheLength, 1);

    recorder.endRecording().dispose();
    painter.dispose();
  });

  test('paintLine skips undecorated space glyph layouts', () {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final terminal = Terminal()..write('   \x1b[4m \x1b[0m ');
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    painter.paintLineForegrounds(canvas, Offset.zero, terminal.buffer.lines[0]);

    expect(painter.paragraphCacheLength, 1);

    recorder.endRecording().dispose();
    painter.dispose();
  });

  test('paintLine foreground override uses separate glyph cache entry', () {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final terminal = Terminal()..write('X');
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    painter.paintLineForegrounds(canvas, Offset.zero, terminal.buffer.lines[0]);
    expect(painter.paragraphCacheLength, 1);

    painter.paintLineForegrounds(
      canvas,
      Offset.zero,
      terminal.buffer.lines[0],
      cursorColumn: 0,
      cursorForeground: const ui.Color(0xFF000000),
    );
    expect(painter.paragraphCacheLength, 2);

    recorder.endRecording().dispose();
    painter.dispose();
  });

  test('paintLine reuses glyph layout across background colors', () {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final terminal = Terminal()..write('\x1b[41mX\x1b[42mX');
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    painter.paintLineForegrounds(canvas, Offset.zero, terminal.buffer.lines[0]);

    expect(painter.paragraphCacheLength, 1);

    recorder.endRecording().dispose();
    painter.dispose();
  });

  test('TerminalPainter resolves OSC color overrides', () {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final terminal = Terminal()
      ..write(
        '\x1b]4;1;#123456\x1b\\'
        '\x1b]10;#234567;#345678;#456789\x1b\\',
      );

    painter.updateColorOverrides(
      terminal,
      terminal.colorRevision,
      terminal.indexedColorOverrides,
      terminal.foregroundColorOverride,
      terminal.backgroundColorOverride,
      terminal.cursorColorOverride,
    );

    expect(
      painter.resolveForegroundColor(CellColor.named | 1),
      const ui.Color(0xff123456),
    );
    expect(
      painter.resolveForegroundColor(CellColor.normal),
      const ui.Color(0xff234567),
    );
    expect(painter.backgroundColor, const ui.Color(0xff345678));
    expect(painter.cursorColor, const ui.Color(0xff456789));

    painter.dispose();
  });

  test('TerminalPainter falls back for invalid palette colors', () {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );

    expect(
      painter.resolveForegroundColor(CellColor.palette | 300),
      painter.foregroundColor,
    );
    expect(
      painter.resolveBackgroundColor(CellColor.palette | 300),
      painter.backgroundColor,
    );

    painter.dispose();
  });

  test('TerminalPainter dims faint text without making it transparent', () {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final cell = CellData.empty()
      ..foreground = CellColor.rgb | 0xC86432
      ..flags = CellFlags.faint;

    final color = painter.resolveCellForegroundColor(cell);

    expect(color.a, 1);
    expect(color.r, closeTo((0xC8 / 0xFF) * 0.66, 0.001));
    expect(color.g, closeTo((0x64 / 0xFF) * 0.66, 0.001));
    expect(color.b, closeTo((0x32 / 0xFF) * 0.66, 0.001));
    painter.dispose();
  });

  test('TerminalPainter dims logical foreground before inverse swap', () {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final cell = CellData.empty()
      ..foreground = CellColor.rgb | 0xC86432
      ..background = CellColor.rgb | 0x102030
      ..flags = CellFlags.faint | CellFlags.inverse;

    final foreground = painter.resolveCellForegroundColor(cell);
    final background = painter.resolveCellBackgroundColor(cell);

    expect(foreground, const ui.Color(0xFF102030));
    expect(background, isNotNull);
    if (background case final color?) {
      expect(color.a, 1);
      expect(color.r, closeTo((0xC8 / 0xFF) * 0.66, 0.001));
      expect(color.g, closeTo((0x64 / 0xFF) * 0.66, 0.001));
      expect(color.b, closeTo((0x32 / 0xFF) * 0.66, 0.001));
    }
    painter.dispose();
  });

  test('TerminalPainter invalidates colors when terminal changes', () {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final first = Terminal()..write('\x1b]4;1;#112233\x1b\\');
    final second = Terminal()..write('\x1b]4;1;#445566\x1b\\');

    void apply(Terminal terminal) {
      painter.updateColorOverrides(
        terminal,
        terminal.colorRevision,
        terminal.indexedColorOverrides,
        terminal.foregroundColorOverride,
        terminal.backgroundColorOverride,
        terminal.cursorColorOverride,
      );
    }

    apply(first);
    expect(
      painter.resolveForegroundColor(CellColor.named | 1),
      const ui.Color(0xff112233),
    );

    apply(second);
    expect(
      painter.resolveForegroundColor(CellColor.named | 1),
      const ui.Color(0xff445566),
    );

    painter.dispose();
  });

  test('TerminalPainter keeps cursors visible on low-contrast cells', () {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final cell = CellData.empty()
      ..foreground = CellColor.named
      ..background = CellColor.named;

    final colors = painter.resolveCursorColors(cell);

    expect(colors.background, painter.foregroundColor);
    expect(colors.foreground, painter.backgroundColor);

    painter.dispose();
  });

  test('TerminalPainter cell width fits visible ASCII glyphs', () {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final textStyle = painter.textStyle.toTextStyle();
    final paragraphStyle = textStyle.getParagraphStyle();
    final textStyleRun = textStyle.getTextStyle(
      textScaler: painter.textScaler,
    );

    for (final codePoint in [0x21, 0x4d, 0x57, 0x6d, 0x7e]) {
      final builder = ui.ParagraphBuilder(paragraphStyle);
      builder.pushStyle(textStyleRun);
      builder.addText(String.fromCharCode(codePoint));

      final paragraph = builder.build();
      paragraph.layout(const ui.ParagraphConstraints(width: double.infinity));

      expect(
        painter.cellSize.width,
        greaterThanOrEqualTo(paragraph.maxIntrinsicWidth),
      );
      paragraph.dispose();
    }

    painter.dispose();
  });

  test('block cursor spans the requested cell width', () async {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );

    final image = await _paintCursor(
      painter,
      Offset.zero,
      TerminalCursorType.block,
      cellWidth: 2,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final byteData = bytes;
    if (byteData == null) {
      fail('Expected cursor image bytes');
    }

    final firstCellX = (painter.cellSize.width / 2).round();
    final secondCellX = (painter.cellSize.width * 1.5).round();
    expect(_alphaAt(byteData, image.width, firstCellX, 1), greaterThan(0));
    expect(_alphaAt(byteData, image.width, secondCellX, 1), greaterThan(0));

    image.dispose();
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

  test('paintCellForeground clips glyphs to their terminal cell span',
      () async {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 40, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final cell = CellData.empty()
      ..content = 0x1F600 | (1 << CellContent.widthShift);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    painter.paintCellForeground(canvas, Offset.zero, cell);

    final picture = recorder.endRecording();
    final image = await picture.toImage(120, 60);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final byteData = bytes;
    if (byteData == null) {
      fail('Expected glyph image bytes');
    }

    final clipEnd = painter.cellSize.width.ceil();
    expect(
      _hasAnyAlphaInRect(
        byteData,
        image.width,
        0,
        0,
        clipEnd,
        image.height,
      ),
      isTrue,
    );
    expect(
      _hasAnyAlphaInRect(
        byteData,
        image.width,
        clipEnd,
        0,
        image.width,
        image.height,
      ),
      isFalse,
    );
    expect(painter.paragraphCacheLength, 1);
    image.dispose();
    painter.dispose();
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

  test('TerminalStyle compares values deeply', () {
    const style = TerminalStyle(
      fontSize: 14,
      height: 1.1,
      fontFamily: 'Mono',
      fontFamilyFallback: ['A', 'B'],
    );

    expect(
      style,
      const TerminalStyle(
        fontSize: 14,
        height: 1.1,
        fontFamily: 'Mono',
        fontFamilyFallback: ['A', 'B'],
      ),
    );
    expect(style.copyWith(fontFamilyFallback: ['A', 'C']), isNot(style));
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

  test('paintLine renders dotted underlines for procedural glyphs', () async {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final line = BufferLine(1);
    final style = CursorStyle()..setDottedUnderline();
    line.setCell(0, 0x2500, 1, style);

    final image = await _paintLine(painter, line);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final byteData = bytes;
    if (byteData == null) {
      fail('Expected line image bytes');
    }

    final underlineY = painter.cellSize.height.round() - 1;
    final paintedColumns = _paintedColumnCount(
      byteData,
      image.width,
      underlineY,
      painter.cellSize.width.floor(),
    );
    expect(paintedColumns, greaterThan(0));
    expect(paintedColumns, lessThan(painter.cellSize.width.floor()));

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

  test('paintLine keeps braille pattern blank invisible', () async {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final terminal = Terminal()..write('\u2800');

    expect(terminal.buffer.cursorX, 1);
    expect(painter.paragraphCacheLength, 0);

    final image = await _paintLine(painter, terminal.buffer.lines[0]);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final byteData = bytes;
    if (byteData == null) {
      fail('Expected line image bytes');
    }

    expect(_hasAnyAlpha(byteData, image.width, image.height), isFalse);
    expect(painter.paragraphCacheLength, 0);

    image.dispose();
    painter.dispose();
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

  test('paintLine backgrounds do not bleed into transparent cells', () async {
    final painter = TerminalPainter(
      theme: TerminalThemes.whiteOnBlack,
      textStyle: const TerminalStyle(fontSize: 20, height: 1),
      textScaler: TextScaler.noScaling,
    );
    final line = BufferLine(2)..setBackground(0, CellColor.rgb | 0x123456);

    final image = await _paintLine(painter, line);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final byteData = bytes;
    if (byteData == null) {
      fail('Expected line image bytes');
    }

    final transparentCellX = painter.cellSize.width.ceil();
    final y = (painter.cellSize.height / 2).round();
    expect(_alphaAt(byteData, image.width, transparentCellX, y), 0);

    image.dispose();
    painter.dispose();
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
  TerminalCursorType cursorType, {
  int cellWidth = 1,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  painter.paintCursor(
    canvas,
    offset,
    cursorType: cursorType,
    cellWidth: cellWidth,
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

bool _hasAnyAlphaInRect(
  ByteData byteData,
  int imageWidth,
  int left,
  int top,
  int right,
  int bottom,
) {
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      if (_alphaAt(byteData, imageWidth, x, y) != 0) return true;
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

int _paintedColumnCount(ByteData byteData, int width, int y, int endX) {
  var count = 0;
  for (var x = 0; x < endX; x++) {
    if (_alphaAt(byteData, width, x, y) != 0) {
      count++;
    }
  }
  return count;
}
