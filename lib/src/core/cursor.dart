import 'package:xterm/src/core/cell.dart';

enum TerminalCursorType {
  block,
  underline,
  verticalBar,
}

class CursorStyle {
  int foreground;

  int background;

  int underlineColor;

  int attrs;

  int hyperlinkId;

  CursorStyle({
    this.foreground = 0,
    this.background = 0,
    this.underlineColor = 0,
    this.attrs = 0,
    this.hyperlinkId = 0,
  });

  static final empty = CursorStyle();

  void setBold() {
    attrs |= CellAttr.bold;
  }

  void setFaint() {
    attrs |= CellAttr.faint;
  }

  void setItalic() {
    attrs |= CellAttr.italic;
  }

  void setUnderline() {
    attrs &= ~CellAttr.underlineMask;
    attrs |= CellAttr.underline;
  }

  void setBlink() {
    attrs |= CellAttr.blink;
  }

  void setInverse() {
    attrs |= CellAttr.inverse;
  }

  void setInvisible() {
    attrs |= CellAttr.invisible;
  }

  void setStrikethrough() {
    attrs |= CellAttr.strikethrough;
  }

  void setOverline() {
    attrs |= CellAttr.overline;
  }

  void setProtected() {
    attrs |= CellAttr.protected;
  }

  void setDoubleUnderline() {
    attrs &= ~CellAttr.underlineMask;
    attrs |= CellAttr.doubleUnderline;
  }

  void setUndercurl() {
    attrs &= ~CellAttr.underlineMask;
    attrs |= CellAttr.undercurl;
  }

  void setDottedUnderline() {
    attrs &= ~CellAttr.underlineMask;
    attrs |= CellAttr.dottedUnderline;
  }

  void setDashedUnderline() {
    attrs &= ~CellAttr.underlineMask;
    attrs |= CellAttr.dashedUnderline;
  }

  void unsetBold() {
    attrs &= ~CellAttr.bold;
  }

  void unsetFaint() {
    attrs &= ~CellAttr.faint;
  }

  void unsetItalic() {
    attrs &= ~CellAttr.italic;
  }

  void unsetUnderline() {
    attrs &= ~CellAttr.underlineMask;
  }

  void unsetBlink() {
    attrs &= ~CellAttr.blink;
  }

  void unsetInverse() {
    attrs &= ~CellAttr.inverse;
  }

  void unsetInvisible() {
    attrs &= ~CellAttr.invisible;
  }

  void unsetStrikethrough() {
    attrs &= ~CellAttr.strikethrough;
  }

  void unsetOverline() {
    attrs &= ~CellAttr.overline;
  }

  void unsetProtected() {
    attrs &= ~CellAttr.protected;
  }

  bool get isBold => (attrs & CellAttr.bold) != 0;

  bool get isFaint => (attrs & CellAttr.faint) != 0;

  bool get isItalis => (attrs & CellAttr.italic) != 0;

  bool get isUnderline => (attrs & CellAttr.underline) != 0;

  bool get isDoubleUnderline => (attrs & CellAttr.doubleUnderline) != 0;

  bool get isUndercurl => (attrs & CellAttr.undercurl) != 0;

  bool get isDottedUnderline => (attrs & CellAttr.dottedUnderline) != 0;

  bool get isDashedUnderline => (attrs & CellAttr.dashedUnderline) != 0;

  bool get isBlink => (attrs & CellAttr.blink) != 0;

  bool get isInverse => (attrs & CellAttr.inverse) != 0;

  bool get isInvisible => (attrs & CellAttr.invisible) != 0;

  bool get isOverline => (attrs & CellAttr.overline) != 0;

  bool get isProtected => (attrs & CellAttr.protected) != 0;

  void setForegroundColor16(int color) {
    foreground = color | CellColor.named;
  }

  void setForegroundColor256(int color) {
    foreground = color | CellColor.palette;
  }

  void setForegroundColorRgb(int r, int g, int b) {
    foreground = (r << 16) | (g << 8) | b | CellColor.rgb;
  }

  void resetForegroundColor() {
    foreground = 0; // | CellColor.normal;
  }

  void setBackgroundColor16(int color) {
    background = color | CellColor.named;
  }

  void setBackgroundColor256(int color) {
    background = color | CellColor.palette;
  }

  void setBackgroundColorRgb(int r, int g, int b) {
    background = (r << 16) | (g << 8) | b | CellColor.rgb;
  }

  void resetBackgroundColor() {
    background = 0; // | CellColor.normal;
  }

  void setUnderlineColor256(int color) {
    underlineColor = color | CellColor.palette;
  }

  void setUnderlineColorRgb(int r, int g, int b) {
    underlineColor = (r << 16) | (g << 8) | b | CellColor.rgb;
  }

  void resetUnderlineColor() {
    underlineColor = 0;
  }

  void reset() {
    foreground = 0;
    background = 0;
    underlineColor = 0;
    attrs = 0;
  }
}

class CursorPosition {
  int x;

  int y;

  CursorPosition(this.x, this.y);
}
