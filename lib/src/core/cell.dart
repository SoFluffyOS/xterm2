import 'package:xterm/src/utils/hash_values.dart';

class CellData {
  CellData({
    required this.foreground,
    required this.background,
    required this.underlineColor,
    required this.flags,
    required this.content,
  });

  factory CellData.empty() {
    return CellData(
      foreground: 0,
      background: 0,
      underlineColor: 0,
      flags: 0,
      content: 0,
    );
  }

  int foreground;

  int background;

  int underlineColor;

  int flags;

  int content;

  int getHash() {
    final visualFlags = flags & CellAttr.visualMask;
    final hyperlinkFlag = hyperlinkId == 0 ? 0 : CellAttr.hyperlinkMarker;
    return hashValues(
      foreground,
      background,
      underlineColor,
      visualFlags | hyperlinkFlag,
      content,
    );
  }

  int get hyperlinkId =>
      (flags & CellAttr.hyperlinkMask) >> CellAttr.hyperlinkShift;

  @override
  String toString() {
    return 'CellData{foreground: $foreground, background: $background, flags: $flags, content: $content}';
  }
}

abstract class CellAttr {
  static const bold = 1 << 0;
  static const faint = 1 << 1;
  static const italic = 1 << 2;
  static const underline = 1 << 3;
  static const blink = 1 << 4;
  static const inverse = 1 << 5;
  static const invisible = 1 << 6;
  static const strikethrough = 1 << 7;
  static const overline = 1 << 8;
  static const doubleUnderline = 1 << 9;
  static const undercurl = 1 << 10;
  static const dottedUnderline = 1 << 11;
  static const dashedUnderline = 1 << 12;
  static const protected = 1 << 13;

  static const underlineMask = underline |
      doubleUnderline |
      undercurl |
      dottedUnderline |
      dashedUnderline;
  static const visualMask = 0x1fff;
  static const hyperlinkShift = 14;
  static const hyperlinkMask = 0x3ffff << hyperlinkShift;
  static const hyperlinkMarker = 1 << hyperlinkShift;
}

abstract class CellColor {
  static const valueMask = 0xFFFFFF;

  static const typeShift = 25;
  static const typeMask = 3 << typeShift;

  static const normal = 0 << typeShift;
  static const named = 1 << typeShift;
  static const palette = 2 << typeShift;
  static const rgb = 3 << typeShift;
}

abstract class CellContent {
  static const codepointMask = 0x1fffff;

  static const widthShift = 22;
  // static const widthMask = 3 << widthShift;
}
