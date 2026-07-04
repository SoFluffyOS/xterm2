import 'package:xterm/src/core/mouse/mode.dart';

abstract class EscapeHandler {
  void writeChar(int char);

  /* SBC */

  void enquiry();

  void bell();

  void backspaceReturn();

  void tab();

  void lineFeed();

  void carriageReturn();

  void shiftOut();

  void shiftIn();

  void unknownSBC(int char);

  /* ANSI sequence */

  void saveCursor();

  void restoreCursor();

  void index();

  void nextLine();

  void setTapStop();

  void reset();

  void softReset();

  void screenAlignmentTest();

  void reverseIndex();

  void designateCharset(int charset, int name);

  void useCharset(int charset);

  void singleShiftCharset(int charset);

  void unkownEscape(int char);

  /* CSI */

  void repeatPreviousCharacter(int n);

  void setCursor(int x, int y);

  void setCursorX(int x);

  void setCursorY(int y);

  void sendPrimaryDeviceAttributes();

  void clearTabStopUnderCursor();

  void clearAllTabStops();

  void resetTabStops();

  void moveForwardTabs(int count);

  void moveBackwardTabs(int count);

  void moveCursorX(int offset);

  void moveCursorY(int n);

  void sendSecondaryDeviceAttributes();

  void sendTertiaryDeviceAttributes();

  void sendOperatingStatus();

  void sendCursorPosition();

  void sendColorScheme();

  void sendXtVersion();

  void sendStatusString(String query);

  void sendTerminfoCapability(String query);

  void setMargins(int i, [int? bottom]);

  void cursorNextLine(int amount);

  void cursorPrecedingLine(int amount);

  void eraseDisplayBelow();

  void eraseDisplayBelowSelective();

  void eraseDisplayAbove();

  void eraseDisplayAboveSelective();

  void eraseDisplay();

  void eraseDisplaySelective();

  void eraseScrollbackOnly();

  void eraseLineRight();

  void eraseLineRightSelective();

  void eraseLineLeft();

  void eraseLineLeftSelective();

  void eraseLine();

  void eraseLineSelective();

  void insertLines(int amount);

  void deleteLines(int amount);

  void deleteChars(int amount);

  void scrollUp(int amount);

  void scrollDown(int amount);

  void eraseChars(int amount);

  void insertBlankChars(int amount);

  void unknownCSI(int finalByte);

  void setCursorShape(int style);

  void setProtectedMode(bool enabled);

  void setIsoProtectedMode(bool enabled);

  /* Modes */

  void setInsertMode(bool enabled);

  void setLineFeedMode(bool enabled);

  void setUnknownMode(int mode, bool enabled);

  /* DEC Private modes */

  void setCursorKeysMode(bool enabled);

  void setReverseDisplayMode(bool enabled);

  void setOriginMode(bool enabled);

  void setColumnMode(bool enabled);

  void setAutoWrapMode(bool enabled);

  void setMouseMode(MouseMode mode);

  void setCursorBlinkMode(bool enabled);

  void setCursorVisibleMode(bool enabled);

  void useAltBuffer();

  void useMainBuffer();

  void clearAltBuffer();

  void setAppKeypadMode(bool enabled);

  void setReportFocusMode(bool enabled);

  void setMouseReportMode(MouseReportMode mode);

  void setAltBufferMouseScrollMode(bool enabled);

  void setBracketedPasteMode(bool enabled);

  void setSynchronizedUpdateMode(bool enabled);

  void setGraphemeClusterMode(bool enabled);

  void reportMode(int mode, bool decPrivate);

  void saveDecMode(int mode);

  void restoreDecMode(int mode);

  void reportKittyKeyboardMode();

  void setKittyKeyboardMode(int mode, int behavior);

  void pushKittyKeyboardMode(int mode);

  void popKittyKeyboardModes(int count);

  void setUnknownDecMode(int mode, bool enabled);

  void resize(int cols, int rows);

  void sendSize();

  void sendPixelSize();

  void sendCellSize();

  /* Select Graphic Rendition (SGR) */

  void resetCursorStyle();

  void setCursorBold();

  void setCursorFaint();

  void setCursorItalic();

  void setCursorUnderline();

  void setCursorDoubleUnderline();

  void setCursorUndercurl();

  void setCursorDottedUnderline();

  void setCursorDashedUnderline();

  void setCursorBlink();

  void setCursorInverse();

  void setCursorInvisible();

  void setCursorStrikethrough();

  void setCursorOverline();

  void unsetCursorBold();

  void unsetCursorFaint();

  void unsetCursorItalic();

  void unsetCursorUnderline();

  void unsetCursorBlink();

  void unsetCursorInverse();

  void unsetCursorInvisible();

  void unsetCursorStrikethrough();

  void unsetCursorOverline();

  void setForegroundColor16(int color);

  void setForegroundColor256(int index);

  void setForegroundColorRgb(int r, int g, int b);

  void resetForeground();

  void setBackgroundColor16(int color);

  void setBackgroundColor256(int index);

  void setBackgroundColorRgb(int r, int g, int b);

  void resetBackground();

  void setUnderlineColor256(int index);

  void setUnderlineColorRgb(int r, int g, int b);

  void resetUnderlineColor();

  void unsupportedStyle(int param);

  /* OSC */

  void setTitle(String name);

  void setIconName(String name);

  void pushTitle();

  void popTitle();

  void setCurrentDirectory(String uri);

  void setHyperlink(String params, String uri);

  void setIndexedColor(int index, String value);

  void queryIndexedColor(int index);

  void resetIndexedColors(List<int> indices);

  void setDynamicColor(int code, String value);

  void queryDynamicColor(int code);

  void resetDynamicColor(int code);

  void storeClipboard(String selector, String data);

  void queryClipboard(String selector);

  void unknownOSC(String code, List<String> args);
}
