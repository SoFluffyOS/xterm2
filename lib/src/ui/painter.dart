import 'dart:math' show max, min;
import 'dart:ui';
import 'package:flutter/painting.dart';

import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';
import 'package:xterm/src/ui/procedural_glyphs.dart';
import 'package:xterm/xterm.dart';

const _dimColorFactor = 0.66;

/// Encapsulates the logic for painting various terminal elements.
class TerminalPainter {
  TerminalPainter({
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
  })  : _textStyle = textStyle,
        _theme = theme,
        _textScaler = textScaler;

  /// A lookup table from terminal colors to Flutter colors.
  late var _colorPalette = PaletteBuilder(_theme).build();

  /// Size of each character in the terminal.
  late var _cellSize = _measureCharSize();

  /// The cached for cells in the terminal. Should be cleared when the same
  /// cell no longer produces the same visual output. For example, when
  /// [_textStyle] is changed, or when the system font changes.
  final _paragraphCache = ParagraphCache(10240);

  /// Reused during cell painting to avoid allocating objects per visible cell.
  final _foregroundPaint = Paint();
  final _backgroundPaint = Paint();

  final Map<int, Color> _indexedColorOverrides = {};

  int _colorRevision = -1;

  Object? _colorSource;

  Color? _foregroundColorOverride;

  Color? _backgroundColorOverride;

  Color? _cursorColorOverride;

  TerminalStyle get textStyle => _textStyle;
  TerminalStyle _textStyle;
  set textStyle(TerminalStyle value) {
    if (value == _textStyle) return;
    _textStyle = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  TextScaler get textScaler => _textScaler;
  TextScaler _textScaler = TextScaler.linear(1.0);
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  TerminalTheme get theme => _theme;
  TerminalTheme _theme;
  set theme(TerminalTheme value) {
    if (value == _theme) return;
    _theme = value;
    _colorPalette = PaletteBuilder(value).build();
    _paragraphCache.clear();
  }

  bool get reverseDisplay => _reverseDisplay;
  bool _reverseDisplay = false;
  set reverseDisplay(bool value) {
    if (value == _reverseDisplay) return;
    _reverseDisplay = value;
    _paragraphCache.clear();
  }

  Size _measureCharSize() {
    final textStyle = _textStyle.toTextStyle();
    final paragraphStyle = textStyle.getParagraphStyle();
    final textStyleRun = textStyle.getTextStyle(textScaler: _textScaler);

    var width = 0.0;
    var height = 0.0;
    for (var codePoint = 0x21; codePoint <= 0x7e; codePoint++) {
      final builder = ParagraphBuilder(paragraphStyle);
      builder.pushStyle(textStyleRun);
      builder.addText(String.fromCharCode(codePoint));

      final paragraph = builder.build();
      paragraph.layout(ParagraphConstraints(width: double.infinity));

      width = max(width, paragraph.maxIntrinsicWidth);
      height = max(height, paragraph.height);
      paragraph.dispose();
    }

    return Size(width, height);
  }

  /// The size of each character in the terminal.
  Size get cellSize => _cellSize;

  int get paragraphCacheLength => _paragraphCache.length;

  Color get foregroundColor => _foregroundColorOverride ?? _theme.foreground;

  Color get backgroundColor => _backgroundColorOverride ?? _theme.background;

  Color get cursorColor => _cursorColorOverride ?? _theme.cursor;

  Color? get backgroundColorOverride => _backgroundColorOverride;

  void updateColorOverrides(
    Object source,
    int revision,
    Iterable<MapEntry<int, int>> indexedColors,
    int? foreground,
    int? background,
    int? cursor,
  ) {
    if (identical(_colorSource, source) && _colorRevision == revision) return;
    _colorSource = source;
    _colorRevision = revision;
    _indexedColorOverrides
      ..clear()
      ..addEntries(indexedColors.map(
        (entry) => MapEntry(entry.key, Color(0xff000000 | entry.value)),
      ));
    _foregroundColorOverride = switch (foreground) {
      final value? => Color(0xff000000 | value),
      null => null,
    };
    _backgroundColorOverride = switch (background) {
      final value? => Color(0xff000000 | value),
      null => null,
    };
    _cursorColorOverride = switch (cursor) {
      final value? => Color(0xff000000 | value),
      null => null,
    };
    _paragraphCache.clear();
  }

  /// When the set of font available to the system changes, call this method to
  /// clear cached state related to font rendering.
  void clearFontCache() {
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  void dispose() {
    _paragraphCache.dispose();
  }

  /// Paints the cursor based on the current cursor type.
  void paintCursor(
    Canvas canvas,
    Offset offset, {
    required TerminalCursorType cursorType,
    bool hasFocus = true,
    int cellWidth = 1,
    Color? color,
  }) {
    final cursorSize = Size(_cellSize.width * cellWidth, _cellSize.height);
    final paint = Paint()
      ..color = color ?? cursorColor
      ..strokeWidth = 1;

    if (!hasFocus) {
      paint.style = PaintingStyle.stroke;
      canvas.drawRect(offset & cursorSize, paint);
      return;
    }

    switch (cursorType) {
      case TerminalCursorType.block:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(offset & cursorSize, paint);
        return;
      case TerminalCursorType.underline:
        return canvas.drawLine(
          offset.translate(0, _cellSize.height - 1),
          offset.translate(cursorSize.width, _cellSize.height - 1),
          paint,
        );
      case TerminalCursorType.verticalBar:
        return canvas.drawLine(
          offset,
          offset.translate(0, _cellSize.height),
          paint,
        );
    }
  }

  @pragma('vm:prefer-inline')
  void paintHighlight(Canvas canvas, Offset offset, int length, Color color) {
    final endOffset =
        offset.translate(length * _cellSize.width, _cellSize.height);

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    canvas.drawRect(
      Rect.fromPoints(offset, endOffset),
      paint,
    );
  }

  /// Paints [line] to [canvas] at [offset]. The x offset of [offset] is usually
  /// 0, and the y offset is the top of the line.
  bool paintLine(
    Canvas canvas,
    Offset offset,
    BufferLine line, {
    bool blinkVisible = true,
  }) {
    paintLineBackgrounds(canvas, offset, line);
    return paintLineForegrounds(
      canvas,
      offset,
      line,
      blinkVisible: blinkVisible,
    );
  }

  void paintLineBackgrounds(
    Canvas canvas,
    Offset offset,
    BufferLine line,
  ) {
    final cellData = CellData.empty();

    var backgroundRunStart = 0;
    var backgroundRunEnd = 0;
    Color? backgroundRunColor;

    for (var i = 0; i < line.length; i++) {
      line.getCellData(i, cellData, includeUnderlineColor: false);

      final charWidth = cellData.content >> CellContent.widthShift;
      final cellSpan = switch (charWidth == 2) {
        true => 2,
        false => 1,
      };
      final color = resolveCellBackgroundColor(cellData);
      final runColor = backgroundRunColor;

      if (color == null) {
        if (runColor != null) {
          paintBackgroundRun(
            canvas,
            offset,
            backgroundRunStart,
            backgroundRunEnd,
            runColor,
          );
        }
        backgroundRunColor = null;
        backgroundRunStart = i + cellSpan;
        backgroundRunEnd = backgroundRunStart;

        if (charWidth == 2) {
          i++;
        }
        continue;
      }

      if (runColor != null && runColor == color && backgroundRunEnd == i) {
        backgroundRunEnd += cellSpan;

        if (charWidth == 2) {
          i++;
        }
        continue;
      }

      if (runColor != null) {
        paintBackgroundRun(
          canvas,
          offset,
          backgroundRunStart,
          backgroundRunEnd,
          runColor,
        );
      }

      backgroundRunColor = color;
      backgroundRunStart = i;
      backgroundRunEnd = i + cellSpan;

      if (charWidth == 2) {
        i++;
      }
    }

    final runColor = backgroundRunColor;
    if (runColor != null) {
      paintBackgroundRun(
        canvas,
        offset,
        backgroundRunStart,
        backgroundRunEnd,
        runColor,
      );
    }
  }

  bool paintLineForegrounds(
    Canvas canvas,
    Offset offset,
    BufferLine line, {
    bool blinkVisible = true,
    int? activeHyperlinkId,
    int? cursorColumn,
    Color? cursorForeground,
  }) {
    final cellData = CellData.empty();
    final cellWidth = _cellSize.width;
    final hasCombiningCharacters = line.hasCombiningCharacters;
    var hasBlinkingText = false;
    for (var i = 0; i < line.length; i++) {
      line.getCellData(i, cellData);

      final charWidth = cellData.content >> CellContent.widthShift;
      if (cellData.content & CellContent.codepointMask == 0) {
        if (charWidth == 2) {
          i++;
        }
        continue;
      }

      final cellOffset = offset.translate(i * cellWidth, 0);
      if (cellData.flags & CellFlags.blink != 0) {
        hasBlinkingText = true;
      }

      paintCellForeground(
        canvas,
        cellOffset,
        cellData,
        combiningCharacters: switch (hasCombiningCharacters) {
          true => line.getCombiningCharacters(i),
          false => null,
        },
        blinkVisible: blinkVisible,
        activeHyperlinkId: activeHyperlinkId,
        foregroundOverride: switch (i == cursorColumn) {
          true => cursorForeground,
          false => null,
        },
      );

      if (charWidth == 2) {
        i++;
      }
    }
    return hasBlinkingText;
  }

  @pragma('vm:prefer-inline')
  void paintCell(Canvas canvas, Offset offset, CellData cellData) {
    paintCellBackground(canvas, offset, cellData);
    paintCellForeground(canvas, offset, cellData);
  }

  /// Paints the character in the cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellForeground(
    Canvas canvas,
    Offset offset,
    CellData cellData, {
    String? combiningCharacters,
    bool blinkVisible = true,
    int? activeHyperlinkId,
    Color? foregroundOverride,
  }) {
    final charCode = cellData.content & CellContent.codepointMask;
    if (charCode == 0) return;

    final cellFlags = cellData.flags;
    if (cellFlags & CellFlags.invisible != 0) return;
    if (cellFlags & CellFlags.blink != 0 && !blinkVisible) return;

    final isActiveHyperlink =
        cellData.hyperlinkId != 0 && cellData.hyperlinkId == activeHyperlinkId;
    final color = resolveCellForegroundColor(
      cellData,
      foregroundOverride: foregroundOverride,
    );
    final decorationColor = switch (cellData.underlineColor) {
      0 => color,
      _ => resolveForegroundColor(cellData.underlineColor),
    };

    _foregroundPaint.color = color;
    if (combiningCharacters == null &&
        paintProceduralGlyph(
          canvas,
          offset,
          _cellSize,
          charCode,
          _foregroundPaint,
        )) {
      if (isActiveHyperlink ||
          cellFlags &
                  (CellFlags.underline |
                      CellAttr.undercurl |
                      CellAttr.dottedUnderline |
                      CellAttr.dashedUnderline) !=
              0) {
        _paintUnderlineDecoration(
          canvas,
          offset,
          decorationColor,
          cellFlags,
          isHyperlink: isActiveHyperlink,
        );
      }
      if (cellFlags & CellAttr.doubleUnderline != 0) {
        _foregroundPaint.color = decorationColor;
        canvas.drawLine(
          offset.translate(0, _cellSize.height - 3),
          offset.translate(_cellSize.width, _cellSize.height - 3),
          _foregroundPaint,
        );
        canvas.drawLine(
          offset.translate(0, _cellSize.height - 1),
          offset.translate(_cellSize.width, _cellSize.height - 1),
          _foregroundPaint,
        );
      }
      if (cellFlags & CellAttr.strikethrough != 0) {
        canvas.drawLine(
          offset.translate(0, _cellSize.height / 2),
          offset.translate(_cellSize.width, _cellSize.height / 2),
          _foregroundPaint,
        );
      }
      if (cellFlags & CellAttr.overline != 0) {
        canvas.drawLine(
          offset,
          offset.translate(_cellSize.width, 0),
          _foregroundPaint,
        );
      }
      return;
    }

    final visualFlags = cellData.flags & CellAttr.visualMask;
    final hyperlinkFlag = switch (isActiveHyperlink) {
      true => CellAttr.hyperlinkMarker,
      false => 0,
    };
    final cacheKey = (
      color,
      decorationColor,
      visualFlags | hyperlinkFlag,
      cellData.content,
      _textScaler,
      combiningCharacters,
    );
    var paragraph = _paragraphCache.getLayoutFromCache(cacheKey);

    if (paragraph == null) {
      final style = _textStyle.toTextStyle(
        color: color,
        decorationColor: decorationColor,
        bold: cellFlags & CellFlags.bold != 0,
        italic: cellFlags & CellFlags.italic != 0,
        underline: _hasUnderline(cellFlags) || isActiveHyperlink,
        doubleUnderline: cellFlags & CellAttr.doubleUnderline != 0,
        decorationStyle: _decorationStyle(cellFlags),
        strikethrough: cellFlags & CellAttr.strikethrough != 0,
        overline: cellFlags & CellAttr.overline != 0,
      );

      // Flutter does not draw an underline below a space which is not between
      // other regular characters. As only single characters are drawn, this
      // will never produce an underline below a space in the terminal. As a
      // workaround the regular space CodePoint 0x20 is replaced with
      // the CodePoint 0xA0. This is a non breaking space and a underline can be
      // drawn below it.
      var char = String.fromCharCode(charCode);
      if (charCode == 0x2800) {
        char = String.fromCharCode(0xA0);
      }
      if ((_hasUnderline(cellFlags) || isActiveHyperlink) && charCode == 0x20) {
        char = String.fromCharCode(0xA0);
      }
      if (combiningCharacters != null) {
        char += combiningCharacters;
      }

      paragraph = _paragraphCache.performAndCacheLayout(
        char,
        style,
        _textScaler,
        cacheKey,
      );
    }

    final charWidth = cellData.content >> CellContent.widthShift;
    final cellSpan = switch (charWidth) {
      2 => 2,
      _ => 1,
    };
    final allocatedWidth = _cellSize.width * cellSpan;
    if (paragraph.maxIntrinsicWidth <= allocatedWidth &&
        paragraph.height <= _cellSize.height) {
      canvas.drawParagraph(paragraph, offset);
      return;
    }
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        offset.dx,
        offset.dy,
        allocatedWidth,
        _cellSize.height,
      ),
    );
    canvas.drawParagraph(paragraph, offset);
    canvas.restore();
  }

  @pragma('vm:prefer-inline')
  bool _hasUnderline(int cellFlags) {
    return cellFlags & CellAttr.underlineMask != 0;
  }

  @pragma('vm:prefer-inline')
  TextDecorationStyle _decorationStyle(int cellFlags) {
    if (cellFlags & CellAttr.undercurl != 0) {
      return TextDecorationStyle.wavy;
    }
    if (cellFlags & CellAttr.dottedUnderline != 0) {
      return TextDecorationStyle.dotted;
    }
    if (cellFlags & CellAttr.dashedUnderline != 0) {
      return TextDecorationStyle.dashed;
    }
    return TextDecorationStyle.solid;
  }

  void _paintUnderlineDecoration(
    Canvas canvas,
    Offset offset,
    Color color,
    int cellFlags, {
    required bool isHyperlink,
  }) {
    if (cellFlags & CellAttr.undercurl != 0) {
      _paintWavyUnderline(canvas, offset, color);
      return;
    }
    if (cellFlags & CellAttr.dottedUnderline != 0) {
      _paintDottedUnderline(canvas, offset, color);
      return;
    }
    if (cellFlags & CellAttr.dashedUnderline != 0) {
      _paintDashedUnderline(canvas, offset, color);
      return;
    }
    if (cellFlags & CellFlags.underline == 0 && !isHyperlink) {
      return;
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.drawLine(
      offset.translate(0, _cellSize.height - 1),
      offset.translate(_cellSize.width, _cellSize.height - 1),
      paint,
    );
  }

  void _paintWavyUnderline(Canvas canvas, Offset offset, Color color) {
    final baseline = offset.dy + _cellSize.height - 2;
    final amplitude = (_cellSize.height / 12).clamp(1.0, 2.0).toDouble();
    final segmentWidth = (_cellSize.width / 2).clamp(3.0, 6.0).toDouble();
    final path = Path()..moveTo(offset.dx, baseline);
    var x = offset.dx;
    var waveUp = true;
    while (x < offset.dx + _cellSize.width) {
      final controlY = switch (waveUp) {
        true => baseline - amplitude,
        false => baseline + amplitude,
      };
      final nextX = (x + segmentWidth)
          .clamp(offset.dx, offset.dx + _cellSize.width)
          .toDouble();
      path.quadraticBezierTo(
        x + segmentWidth / 2,
        controlY,
        nextX,
        baseline,
      );
      x = nextX;
      waveUp = !waveUp;
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, paint);
  }

  void _paintDottedUnderline(Canvas canvas, Offset offset, Color color) {
    final y = offset.dy + _cellSize.height - 1;
    final radius = (_cellSize.height / 18).clamp(0.75, 1.25).toDouble();
    final step = (radius * 4).clamp(3.0, 5.0).toDouble();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    var x = offset.dx + radius;
    while (x < offset.dx + _cellSize.width) {
      canvas.drawCircle(Offset(x, y), radius, paint);
      x += step;
    }
  }

  void _paintDashedUnderline(Canvas canvas, Offset offset, Color color) {
    final y = offset.dy + _cellSize.height - 1;
    final dashWidth = (_cellSize.width / 3).clamp(3.0, 6.0).toDouble();
    final gapWidth = (dashWidth / 2).clamp(1.0, 3.0).toDouble();
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    var x = offset.dx;
    while (x < offset.dx + _cellSize.width) {
      final endX = (x + dashWidth)
          .clamp(offset.dx, offset.dx + _cellSize.width)
          .toDouble();
      canvas.drawLine(Offset(x, y), Offset(endX, y), paint);
      x = endX + gapWidth;
    }
  }

  /// Paints the background of a cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellBackground(Canvas canvas, Offset offset, CellData cellData) {
    final color = resolveCellBackgroundColor(cellData);
    if (color == null) return;

    _backgroundPaint.color = color;
    final doubleWidth = cellData.content >> CellContent.widthShift == 2;
    final widthScale = switch (doubleWidth) {
      true => 2,
      false => 1,
    };
    final size = Size(_cellSize.width * widthScale, _cellSize.height);
    canvas.drawRect(offset & size, _backgroundPaint);
  }

  @pragma('vm:prefer-inline')
  void paintBackgroundRun(
    Canvas canvas,
    Offset offset,
    int start,
    int end,
    Color color,
  ) {
    _backgroundPaint.color = color;
    final runOffset = offset.translate(start * _cellSize.width, 0);
    final runSize = Size(
      (end - start) * _cellSize.width,
      _cellSize.height,
    );
    canvas.drawRect(runOffset & runSize, _backgroundPaint);
  }

  /// Get the effective background color for a cell, or null when the cell uses
  /// the normal transparent terminal background.
  @pragma('vm:prefer-inline')
  Color? resolveCellBackgroundColor(CellData cellData) {
    final colorType = cellData.background & CellColor.typeMask;

    final inverse =
        (cellData.flags & CellFlags.inverse != 0) != _reverseDisplay;
    if (inverse) {
      return _resolveLogicalForegroundColor(cellData);
    }

    if (colorType == CellColor.normal) return null;

    return resolveBackgroundColor(cellData.background);
  }

  Color resolveCellForegroundColor(
    CellData cellData, {
    Color? foregroundOverride,
  }) {
    final inverse =
        (cellData.flags & CellFlags.inverse != 0) != _reverseDisplay;
    final color = foregroundOverride ??
        switch (inverse) {
          false => _resolveLogicalForegroundColor(cellData),
          true => resolveBackgroundColor(cellData.background),
        };
    return color;
  }

  Color _resolveLogicalForegroundColor(CellData cellData) {
    final color = resolveForegroundColor(cellData.foreground);
    if (cellData.flags & CellFlags.faint == 0) return color;
    return color.withValues(
      red: color.r * _dimColorFactor,
      green: color.g * _dimColorFactor,
      blue: color.b * _dimColorFactor,
    );
  }

  ({Color background, Color foreground}) resolveCursorColors(
    CellData cellData,
  ) {
    final inverse =
        (cellData.flags & CellFlags.inverse != 0) != _reverseDisplay;
    final cellForeground = switch (inverse) {
      true => resolveBackgroundColor(cellData.background),
      false => _resolveLogicalForegroundColor(cellData),
    };
    final cellBackground = switch (inverse) {
      true => _resolveLogicalForegroundColor(cellData),
      false => resolveBackgroundColor(cellData.background),
    };

    if (_contrastRatio(cellForeground, cellBackground) < 1.5) {
      return (
        background: foregroundColor,
        foreground: backgroundColor,
      );
    }
    return (
      background: cursorColor,
      foreground: cellBackground,
    );
  }

  /// Get the effective foreground color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveForegroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return foregroundColor;
      case CellColor.named:
      case CellColor.palette:
        return _indexedColorOverrides[colorValue] ??
            _paletteColorOrDefault(colorValue, foregroundColor);
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  /// Get the effective background color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveBackgroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return backgroundColor;
      case CellColor.named:
      case CellColor.palette:
        return _indexedColorOverrides[colorValue] ??
            _paletteColorOrDefault(colorValue, backgroundColor);
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  Color _paletteColorOrDefault(int colorValue, Color defaultColor) {
    if (colorValue < 0 || colorValue >= _colorPalette.length) {
      return defaultColor;
    }
    return _colorPalette[colorValue];
  }
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = max(firstLuminance, secondLuminance);
  final darker = min(firstLuminance, secondLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}
