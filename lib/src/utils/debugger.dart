import 'package:xterm/src/core/escape/handler.dart';
import 'package:xterm/src/core/escape/parser.dart';
import 'package:xterm/src/core/mouse/mode.dart';
import 'package:xterm/src/base/observable.dart';

class TerminalCommand {
  TerminalCommand(
    this.start,
    this.end,
    this.chars,
    this.escapedChars,
    this.explanation,
    this.error,
  );

  final int start;

  final int end;

  final String chars;

  final String escapedChars;

  final List<String> explanation;

  final bool error;
}

class TerminalDebugger with Observable {
  late final _parser = EscapeParser(_handler);

  late final _handler = _TerminalDebuggerHandler(recordCommand);

  final recorded = <int>[];

  final commands = <TerminalCommand>[];

  void write(String chunk) {
    recorded.addAll(chunk.runes);
    _parser.write(chunk);
    notifyListeners();
  }

  void recordCommand(String explanation, {bool error = false}) {
    final start = _parser.tokenBegin;
    final end = _parser.tokenEnd;

    if (commands.isNotEmpty && commands.last.end == end) {
      commands.last.explanation.add(explanation);
    } else {
      final charCodes = recorded.sublist(start, end);
      final chars = String.fromCharCodes(charCodes);
      final escapedChars = _escape(chars);
      commands.add(
        TerminalCommand(start, end, chars, escapedChars, [explanation], error),
      );
    }
  }

  String getRecord(TerminalCommand command) {
    final charCodes = recorded.sublist(0, command.end);
    return String.fromCharCodes(charCodes);
  }

  static String _escape(String chars) {
    final escaped = StringBuffer();
    for (final char in chars.runes) {
      if (char == 0x1b) {
        escaped.write('ESC');
      } else if (char < 32) {
        escaped.write('^0x${char.toRadixString(16)}');
      } else if (char == 127) {
        escaped.write('^?');
      } else {
        escaped.writeCharCode(char);
      }
    }
    return escaped.toString();
  }
}

class _TerminalDebuggerHandler implements EscapeHandler {
  _TerminalDebuggerHandler(this.onCommand);

  final void Function(String explanation, {bool error}) onCommand;

  @override
  void writeChar(int char) {
    onCommand('writeChar(${String.fromCharCode(char)})');
  }

  /* SBC */

  @override
  void enquiry() {
    onCommand('enquiry');
  }

  @override
  void bell() {
    onCommand('bell');
  }

  @override
  void backspaceReturn() {
    onCommand('backspaceReturn');
  }

  @override
  void tab() {
    onCommand('tab');
  }

  @override
  void lineFeed() {
    onCommand('lineFeed');
  }

  @override
  void carriageReturn() {
    onCommand('carriageReturn');
  }

  @override
  void shiftOut() {
    onCommand('shiftOut');
  }

  @override
  void shiftIn() {
    onCommand('shiftIn');
  }

  @override
  void unknownSBC(int char) {
    onCommand('unkownSBC(${String.fromCharCode(char)})', error: true);
  }

  /* ANSI sequence */

  @override
  void saveCursor() {
    onCommand('saveCursor');
  }

  @override
  void saveCursorOrSetLeftRightMargins() {
    onCommand('saveCursorOrSetLeftRightMargins');
  }

  @override
  void restoreCursor() {
    onCommand('restoreCursor');
  }

  @override
  void index() {
    onCommand('index');
  }

  @override
  void nextLine() {
    onCommand('nextLine');
  }

  @override
  void setTapStop() {
    onCommand('setTapStop');
  }

  @override
  void reset() {
    onCommand('reset');
  }

  @override
  void softReset() {
    onCommand('softReset');
  }

  @override
  void screenAlignmentTest() {
    onCommand('screenAlignmentTest');
  }

  @override
  void reverseIndex() {
    onCommand('reverseIndex');
  }

  @override
  void backIndex() {
    onCommand('backIndex');
  }

  @override
  void forwardIndex() {
    onCommand('forwardIndex');
  }

  @override
  void designateCharset(int charset, int name) {
    onCommand('designateCharset($charset, $name)');
  }

  @override
  void useCharset(int charset) {
    onCommand('useCharset($charset)');
  }

  @override
  void singleShiftCharset(int charset) {
    onCommand('singleShiftCharset($charset)');
  }

  @override
  void unkownEscape(int char) {
    onCommand('unkownEscape(${String.fromCharCode(char)})', error: true);
  }

  /* CSI */

  @override
  void repeatPreviousCharacter(int count) {
    onCommand('repeatPreviousCharacter($count)');
  }

  @override
  void unknownCSI(int finalByte) {
    onCommand('unkownCSI(${String.fromCharCode(finalByte)})', error: true);
  }

  @override
  void setCursorShape(int style) {
    onCommand('setCursorShape($style)');
  }

  @override
  void setProtectedMode(bool enabled) {
    onCommand('setProtectedMode($enabled)');
  }

  @override
  void setIsoProtectedMode(bool enabled) {
    onCommand('setIsoProtectedMode($enabled)');
  }

  @override
  void setCursor(int x, int y) {
    onCommand('setCursor($x, $y)');
  }

  @override
  void setCursorX(int x) {
    onCommand('setCursorX($x)');
  }

  @override
  void setCursorY(int y) {
    onCommand('setCursorY($y)');
  }

  @override
  void sendPrimaryDeviceAttributes() {
    onCommand('sendPrimaryDeviceAttributes');
  }

  @override
  void clearTabStopUnderCursor() {
    onCommand('clearTabStopUnderCursor');
  }

  @override
  void clearAllTabStops() {
    onCommand('clearAllTabStops');
  }

  @override
  void resetTabStops() {
    onCommand('resetTabStops');
  }

  @override
  void moveForwardTabs(int count) {
    onCommand('moveForwardTabs($count)');
  }

  @override
  void moveBackwardTabs(int count) {
    onCommand('moveBackwardTabs($count)');
  }

  @override
  void moveCursorX(int offset) {
    onCommand('moveCursorX($offset)');
  }

  @override
  void moveCursorY(int n) {
    onCommand('moveCursorY($n)');
  }

  @override
  void sendSecondaryDeviceAttributes() {
    onCommand('sendSecondaryDeviceAttributes');
  }

  @override
  void sendTertiaryDeviceAttributes() {
    onCommand('sendTertiaryDeviceAttributes');
  }

  @override
  void sendOperatingStatus() {
    onCommand('sendOperatingStatus');
  }

  @override
  void sendCursorPosition() {
    onCommand('sendCursorPosition');
  }

  @override
  void sendColorScheme() {
    onCommand('sendColorScheme');
  }

  @override
  void sendXtVersion() {
    onCommand('sendXtVersion');
  }

  @override
  void sendStatusString(String query) {
    onCommand('sendStatusString($query)');
  }

  @override
  void sendTerminfoCapability(String query) {
    onCommand('sendTerminfoCapability($query)');
  }

  @override
  void setMargins(int i, [int? bottom]) {
    onCommand('setMargins($i, $bottom)');
  }

  @override
  void setLeftRightMargins(int left, [int? right]) {
    onCommand('setLeftRightMargins($left, $right)');
  }

  @override
  void setLeftRightMarginMode(bool enabled) {
    onCommand('setLeftRightMarginMode($enabled)');
  }

  @override
  void cursorNextLine(int amount) {
    onCommand('cursorNextLine($amount)');
  }

  @override
  void cursorPrecedingLine(int amount) {
    onCommand('cursorPrecedingLine($amount)');
  }

  @override
  void eraseDisplayBelow() {
    onCommand('eraseDisplayBelow');
  }

  @override
  void eraseDisplayBelowSelective() {
    onCommand('eraseDisplayBelowSelective');
  }

  @override
  void eraseDisplayAbove() {
    onCommand('eraseDisplayAbove');
  }

  @override
  void eraseDisplayAboveSelective() {
    onCommand('eraseDisplayAboveSelective');
  }

  @override
  void eraseDisplay() {
    onCommand('eraseDisplay');
  }

  @override
  void eraseDisplaySelective() {
    onCommand('eraseDisplaySelective');
  }

  @override
  void eraseScrollbackOnly() {
    onCommand('eraseScrollbackOnly');
  }

  @override
  void eraseLineRight() {
    onCommand('eraseLineRight');
  }

  @override
  void eraseLineRightSelective() {
    onCommand('eraseLineRightSelective');
  }

  @override
  void eraseLineLeft() {
    onCommand('eraseLineLeft');
  }

  @override
  void eraseLineLeftSelective() {
    onCommand('eraseLineLeftSelective');
  }

  @override
  void eraseLine() {
    onCommand('eraseLine');
  }

  @override
  void eraseLineSelective() {
    onCommand('eraseLineSelective');
  }

  @override
  void insertLines(int amount) {
    onCommand('insertLines($amount)');
  }

  @override
  void deleteLines(int amount) {
    onCommand('deleteLines($amount)');
  }

  @override
  void deleteChars(int amount) {
    onCommand('deleteChars($amount)');
  }

  @override
  void insertColumns(int amount) {
    onCommand('insertColumns($amount)');
  }

  @override
  void deleteColumns(int amount) {
    onCommand('deleteColumns($amount)');
  }

  @override
  void scrollUp(int amount) {
    onCommand('scrollUp($amount)');
  }

  @override
  void scrollDown(int amount) {
    onCommand('scrollDown($amount)');
  }

  @override
  void eraseChars(int amount) {
    onCommand('eraseChars($amount)');
  }

  @override
  void eraseRect(int top, int left, int bottom, int right) {
    onCommand('eraseRect($top, $left, $bottom, $right)');
  }

  @override
  void fillRect(int char, int top, int left, int bottom, int right) {
    onCommand('fillRect($char, $top, $left, $bottom, $right)');
  }

  @override
  void changeRectAttributes(
    int top,
    int left,
    int bottom,
    int right,
    int attribute,
  ) {
    onCommand('changeRectAttributes($top, $left, $bottom, $right, '
        '$attribute)');
  }

  @override
  void reverseRectAttributes(
    int top,
    int left,
    int bottom,
    int right,
    int attribute,
  ) {
    onCommand('reverseRectAttributes($top, $left, $bottom, $right, '
        '$attribute)');
  }

  @override
  void copyRect(
    int sourceTop,
    int sourceLeft,
    int sourceBottom,
    int sourceRight,
    int sourcePage,
    int destinationTop,
    int destinationLeft,
    int destinationPage,
  ) {
    onCommand(
      'copyRect($sourceTop, $sourceLeft, $sourceBottom, $sourceRight, '
      '$sourcePage, $destinationTop, $destinationLeft, $destinationPage)',
    );
  }

  @override
  void selectiveEraseRect(int top, int left, int bottom, int right) {
    onCommand('selectiveEraseRect($top, $left, $bottom, $right)');
  }

  @override
  void setAttributeChangeExtent(bool rectangular) {
    onCommand('setAttributeChangeExtent($rectangular)');
  }

  @override
  void setKeyClickVolume(int volume) {
    onCommand('setKeyClickVolume($volume)');
  }

  @override
  void setMarginBellVolume(int volume) {
    onCommand('setMarginBellVolume($volume)');
  }

  @override
  void setWarningBellVolume(int volume) {
    onCommand('setWarningBellVolume($volume)');
  }

  @override
  void setActiveStatusDisplay(int display) {
    onCommand('setActiveStatusDisplay($display)');
  }

  @override
  void setStatusLineType(int type) {
    onCommand('setStatusLineType($type)');
  }

  @override
  void setProtectedFieldsAttribute(int attribute) {
    onCommand('setProtectedFieldsAttribute($attribute)');
  }

  @override
  void insertBlankChars(int amount) {
    onCommand('insertBlankChars($amount)');
  }

  @override
  void resize(int cols, int rows) {
    onCommand('resize($cols, $rows)');
  }

  @override
  void setColumnsPerPage(int cols) {
    onCommand('setColumnsPerPage($cols)');
  }

  @override
  void setLinesPerPage(int rows) {
    onCommand('setLinesPerPage($rows)');
  }

  @override
  void setConformanceLevel(int level, int controls) {
    onCommand('setConformanceLevel($level, $controls)');
  }

  @override
  void sendSize() {
    onCommand('sendSize');
  }

  @override
  void sendPixelSize() {
    onCommand('sendPixelSize');
  }

  @override
  void sendCellSize() {
    onCommand('sendCellSize');
  }

  /* Modes */

  @override
  void setInsertMode(bool enabled) {
    onCommand('setInsertMode($enabled)');
  }

  @override
  void setSendReceiveMode(bool enabled) {
    onCommand('setSendReceiveMode($enabled)');
  }

  @override
  void setKeyboardActionMode(bool enabled) {
    onCommand('setKeyboardActionMode($enabled)');
  }

  @override
  void setLineFeedMode(bool enabled) {
    onCommand('setLineFeedMode($enabled)');
  }

  @override
  void setUnknownMode(int mode, bool enabled) {
    onCommand('setUnknownMode($mode, $enabled)', error: true);
  }

  /* DEC Private modes */

  @override
  void setCursorKeysMode(bool enabled) {
    onCommand('setCursorKeysMode($enabled)');
  }

  @override
  void setReverseDisplayMode(bool enabled) {
    onCommand('setReverseDisplayMode($enabled)');
  }

  @override
  void setOriginMode(bool enabled) {
    onCommand('setOriginMode($enabled)');
  }

  @override
  void setColumnMode(bool enabled) {
    onCommand('setColumnMode($enabled)');
  }

  @override
  void setEnableColumnMode(bool enabled) {
    onCommand('setEnableColumnMode($enabled)');
  }

  @override
  void setSlowScrollMode(bool enabled) {
    onCommand('setSlowScrollMode($enabled)');
  }

  @override
  void setAutoWrapMode(bool enabled) {
    onCommand('setAutoWrapMode($enabled)');
  }

  @override
  void setAutoRepeatMode(bool enabled) {
    onCommand('setAutoRepeatMode($enabled)');
  }

  @override
  void setReverseWrapMode(bool enabled) {
    onCommand('setReverseWrapMode($enabled)');
  }

  @override
  void setReverseWrapExtendedMode(bool enabled) {
    onCommand('setReverseWrapExtendedMode($enabled)');
  }

  @override
  void setMouseMode(MouseMode mode) {
    onCommand('setMouseMode($mode)');
  }

  @override
  void setCursorBlinkMode(bool enabled) {
    onCommand('setCursorBlinkMode($enabled)');
  }

  @override
  void setCursorVisibleMode(bool enabled) {
    onCommand('setCursorVisibleMode($enabled)');
  }

  @override
  void useAltBuffer() {
    onCommand('useAltBuffer');
  }

  @override
  void useMainBuffer() {
    onCommand('useMainBuffer');
  }

  @override
  void clearAltBuffer() {
    onCommand('clearAltBuffer');
  }

  @override
  void setAppKeypadMode(bool enabled) {
    onCommand('setAppKeypadMode($enabled)');
  }

  @override
  void setIgnoreKeypadWithNumLockMode(bool enabled) {
    onCommand('setIgnoreKeypadWithNumLockMode($enabled)');
  }

  @override
  void setBackarrowKeyMode(bool enabled) {
    onCommand('setBackarrowKeyMode($enabled)');
  }

  @override
  void setReportFocusMode(bool enabled) {
    onCommand('setReportFocusMode($enabled)');
  }

  @override
  void setMouseShiftCaptureMode(bool enabled) {
    onCommand('setMouseShiftCaptureMode($enabled)');
  }

  @override
  void setMouseReportMode(MouseReportMode mode) {
    onCommand('setMouseReportMode($mode)');
  }

  @override
  void setAltBufferMouseScrollMode(bool enabled) {
    onCommand('setAltBufferMouseScrollMode($enabled)');
  }

  @override
  void setAltEscPrefixMode(bool enabled) {
    onCommand('setAltEscPrefixMode($enabled)');
  }

  @override
  void setAltSendsEscapeMode(bool enabled) {
    onCommand('setAltSendsEscapeMode($enabled)');
  }

  @override
  void setBracketedPasteMode(bool enabled) {
    onCommand('setBracketedPasteMode($enabled)');
  }

  @override
  void setInBandSizeReportMode(bool enabled) {
    onCommand('setInBandSizeReportMode($enabled)');
  }

  @override
  void setReportColorSchemeMode(bool enabled) {
    onCommand('setReportColorSchemeMode($enabled)');
  }

  @override
  void setSynchronizedUpdateMode(bool enabled) {
    onCommand('setSynchronizedUpdateMode($enabled)');
  }

  @override
  void setGraphemeClusterMode(bool enabled) {
    onCommand('setGraphemeClusterMode($enabled)');
  }

  @override
  void reportMode(int mode, bool decPrivate) {
    onCommand('reportMode($mode, $decPrivate)');
  }

  @override
  void saveDecMode(int mode) {
    onCommand('saveDecMode($mode)');
  }

  @override
  void restoreDecMode(int mode) {
    onCommand('restoreDecMode($mode)');
  }

  @override
  void reportKittyKeyboardMode() {
    onCommand('reportKittyKeyboardMode');
  }

  @override
  void setKittyKeyboardMode(int mode, int behavior) {
    onCommand('setKittyKeyboardMode($mode, $behavior)');
  }

  @override
  void pushKittyKeyboardMode(int mode) {
    onCommand('pushKittyKeyboardMode($mode)');
  }

  @override
  void popKittyKeyboardModes(int count) {
    onCommand('popKittyKeyboardModes($count)');
  }

  @override
  void setModifyOtherKeysMode(int resource, int mode) {
    onCommand('setModifyOtherKeysMode($resource, $mode)');
  }

  @override
  void setUnknownDecMode(int mode, bool enabled) {
    onCommand('setUnknownDecMode($mode, $enabled)', error: true);
  }

  /* Select Graphic Rendition (SGR) */

  @override
  void resetCursorStyle() {
    onCommand('resetCursorStyle');
  }

  @override
  void setCursorBold() {
    onCommand('setCursorBold');
  }

  @override
  void setCursorFaint() {
    onCommand('setCursorFaint');
  }

  @override
  void setCursorItalic() {
    onCommand('setCursorItalic');
  }

  @override
  void setCursorUnderline() {
    onCommand('setCursorUnderline');
  }

  @override
  void setCursorDoubleUnderline() {
    onCommand('setCursorDoubleUnderline');
  }

  @override
  void setCursorUndercurl() {
    onCommand('setCursorUndercurl');
  }

  @override
  void setCursorDottedUnderline() {
    onCommand('setCursorDottedUnderline');
  }

  @override
  void setCursorDashedUnderline() {
    onCommand('setCursorDashedUnderline');
  }

  @override
  void setCursorBlink() {
    onCommand('setCursorBlink');
  }

  @override
  void setCursorInverse() {
    onCommand('setCursorInverse');
  }

  @override
  void setCursorInvisible() {
    onCommand('setCursorInvisible');
  }

  @override
  void setCursorStrikethrough() {
    onCommand('setCursorStrikethrough');
  }

  @override
  void setCursorOverline() {
    onCommand('setCursorOverline');
  }

  @override
  void unsetCursorBold() {
    onCommand('unsetCursorBold');
  }

  @override
  void unsetCursorFaint() {
    onCommand('unsetCursorFaint');
  }

  @override
  void unsetCursorItalic() {
    onCommand('unsetCursorItalic');
  }

  @override
  void unsetCursorUnderline() {
    onCommand('unsetCursorUnderline');
  }

  @override
  void unsetCursorBlink() {
    onCommand('unsetCursorBlink');
  }

  @override
  void unsetCursorInverse() {
    onCommand('unsetCursorInverse');
  }

  @override
  void unsetCursorInvisible() {
    onCommand('unsetCursorInvisible');
  }

  @override
  void unsetCursorStrikethrough() {
    onCommand('unsetCursorStrikethrough');
  }

  @override
  void unsetCursorOverline() {
    onCommand('unsetCursorOverline');
  }

  @override
  void setForegroundColor16(int color) {
    onCommand('setForegroundColor16($color)');
  }

  @override
  void setForegroundColor256(int index) {
    onCommand('setForegroundColor256($index)');
  }

  @override
  void setForegroundColorRgb(int r, int g, int b) {
    onCommand('setForegroundColorRgb($r, $g, $b)');
  }

  @override
  void resetForeground() {
    onCommand('resetForeground');
  }

  @override
  void setBackgroundColor16(int color) {
    onCommand('setBackgroundColor16($color)');
  }

  @override
  void setBackgroundColor256(int index) {
    onCommand('setBackgroundColor256($index)');
  }

  @override
  void setBackgroundColorRgb(int r, int g, int b) {
    onCommand('setBackgroundColorRgb($r, $g, $b)');
  }

  @override
  void resetBackground() {
    onCommand('resetBackground');
  }

  @override
  void setUnderlineColor256(int index) {
    onCommand('setUnderlineColor256($index)');
  }

  @override
  void setUnderlineColorRgb(int r, int g, int b) {
    onCommand('setUnderlineColorRgb($r, $g, $b)');
  }

  @override
  void resetUnderlineColor() {
    onCommand('resetUnderlineColor');
  }

  @override
  void unsupportedStyle(int param) {
    onCommand('unsupportedStyle($param)', error: true);
  }

  /* OSC */

  @override
  void setTitle(String name) {
    onCommand('setTitle($name)');
  }

  @override
  void setIconName(String name) {
    onCommand('setIconName($name)');
  }

  @override
  void reportTitle() {
    onCommand('reportTitle');
  }

  @override
  void pushTitle() {
    onCommand('pushTitle');
  }

  @override
  void popTitle() {
    onCommand('popTitle');
  }

  @override
  void setCurrentDirectory(String uri) {
    onCommand('setCurrentDirectory($uri)');
  }

  @override
  void setHyperlink(String params, String uri) {
    onCommand('setHyperlink($params, $uri)');
  }

  @override
  void setIndexedColor(int index, String value) {
    onCommand('setIndexedColor($index, $value)');
  }

  @override
  void queryIndexedColor(int index) {
    onCommand('queryIndexedColor($index)');
  }

  @override
  void resetIndexedColors(List<int> indices) {
    onCommand('resetIndexedColors($indices)');
  }

  @override
  void setDynamicColor(int code, String value) {
    onCommand('setDynamicColor($code, $value)');
  }

  @override
  void queryDynamicColor(int code) {
    onCommand('queryDynamicColor($code)');
  }

  @override
  void resetDynamicColor(int code) {
    onCommand('resetDynamicColor($code)');
  }

  @override
  void storeClipboard(String selector, String data) {
    onCommand('storeClipboard($selector, $data)');
  }

  @override
  void queryClipboard(String selector) {
    onCommand('queryClipboard($selector)');
  }

  @override
  void unknownOSC(String code, List<String> args) {
    onCommand('unknownOSC($code, $args)', error: true);
  }
}
