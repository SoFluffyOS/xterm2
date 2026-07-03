import 'dart:async';
import 'dart:math' show max;

import 'package:xterm/src/base/observable.dart';
import 'package:xterm/src/core/buffer/buffer.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/line.dart';
import 'package:xterm/src/core/cursor.dart';
import 'package:xterm/src/core/escape/emitter.dart';
import 'package:xterm/src/core/escape/handler.dart';
import 'package:xterm/src/core/escape/parser.dart';
import 'package:xterm/src/core/input/handler.dart';
import 'package:xterm/src/core/input/keys.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/core/mouse/handler.dart';
import 'package:xterm/src/core/mouse/mode.dart';
import 'package:xterm/src/core/mouse/modifiers.dart';
import 'package:xterm/src/core/platform.dart';
import 'package:xterm/src/core/state.dart';
import 'package:xterm/src/core/tabs.dart';
import 'package:xterm/src/utils/ascii.dart';
import 'package:xterm/src/utils/circular_buffer.dart';

/// [Terminal] is an interface to interact with command line applications. It
/// translates escape sequences from the application into updates to the
/// [buffer] and events such as [onTitleChange] or [onBell], as well as
/// translating user input into escape sequences that the application can
/// understand.
class Terminal with Observable implements TerminalState, EscapeHandler {
  static const _maxHyperlinks = 4096;

  /// The number of lines that the scrollback buffer can hold. If the buffer
  /// exceeds this size, the lines at the top of the buffer will be removed.
  final int maxLines;

  /// Function that is called when the program requests the terminal to ring
  /// the bell. If not set, the terminal will do nothing.
  void Function()? onBell;

  /// Function that is called when the program requests the terminal to change
  /// the title of the window to [title].
  void Function(String title)? onTitleChange;

  /// Function that is called when the program requests the terminal to change
  /// the icon of the window. [icon] is the name of the icon.
  void Function(String icon)? onIconChange;

  /// Called when the application reports its current directory using OSC 7.
  void Function(String uri)? onCurrentDirectoryChange;

  /// Resolves the currently displayed color for OSC color queries. [code] is
  /// 4 for an indexed color or 10–12 for dynamic colors; [index] is provided
  /// only for code 4. The return value is a 24-bit RGB color.
  int? Function(int code, int? index)? onColorQuery;

  /// Function that is called when the terminal emits data to the underlying
  /// program. This is typically caused by user inputs from [textInput],
  /// [keyInput], [mouseInput], or [paste].
  void Function(String data)? onOutput;

  /// Function that is called when the dimensions of the terminal change.
  void Function(int width, int height, int pixelWidth, int pixelHeight)?
      onResize;

  /// The [TerminalInputHandler] used by this terminal. [defaultInputHandler] is
  /// used when not specified. User of this class can provide their own
  /// implementation of [TerminalInputHandler] or extend [defaultInputHandler]
  /// with [CascadeInputHandler].
  TerminalInputHandler? inputHandler;

  TerminalMouseHandler? mouseHandler;

  /// The callback that is called when the terminal receives a unrecognized
  /// escape sequence.
  void Function(String code, List<String> args)? onPrivateOSC;

  /// Flag to toggle os specific behaviors.
  final TerminalTargetPlatform platform;

  /// Characters that break selection when double clicking. If not set, the
  /// [Buffer.defaultWordSeparators] will be used.
  final Set<int>? wordSeparators;

  Terminal({
    this.maxLines = 1000,
    this.onBell,
    this.onTitleChange,
    this.onIconChange,
    this.onCurrentDirectoryChange,
    this.onColorQuery,
    this.onOutput,
    this.onResize,
    this.platform = TerminalTargetPlatform.unknown,
    this.inputHandler = defaultInputHandler,
    this.mouseHandler = defaultMouseHandler,
    this.onPrivateOSC,
    this.reflowEnabled = true,
    this.wordSeparators,
  });

  late final _parser = EscapeParser(this);

  final _emitter = const EscapeEmitter();

  final Map<int, String> _hyperlinks = {};

  final Map<String, int> _explicitHyperlinkIds = {};

  final Map<int, int> _indexedColorOverrides = {};

  int? _foregroundColorOverride;

  int? _backgroundColorOverride;

  int? _cursorColorOverride;

  int _colorRevision = 0;

  int _nextHyperlinkId = 1;

  int get colorRevision => _colorRevision;

  Iterable<MapEntry<int, int>> get indexedColorOverrides {
    return _indexedColorOverrides.entries;
  }

  int? get foregroundColorOverride => _foregroundColorOverride;

  int? get backgroundColorOverride => _backgroundColorOverride;

  int? get cursorColorOverride => _cursorColorOverride;

  late var _buffer = _mainBuffer;

  late final _mainBuffer = Buffer(
    this,
    maxLines: maxLines,
    isAltBuffer: false,
    wordSeparators: wordSeparators,
  );

  late final _altBuffer = Buffer(
    this,
    maxLines: maxLines,
    isAltBuffer: true,
    wordSeparators: wordSeparators,
  );

  final _tabStops = TabStops();

  /// The last character written to the buffer. Used to implement some escape
  /// sequences that repeat the last character.
  var _precedingCodepoint = 0;

  /* TerminalState */

  int _viewWidth = 80;

  int _viewHeight = 24;

  final _cursorStyle = CursorStyle();

  bool _insertMode = false;

  bool _lineFeedMode = false;

  bool _cursorKeysMode = false;

  bool _reverseDisplayMode = false;

  bool _originMode = false;

  bool _autoWrapMode = true;

  MouseMode _mouseMode = MouseMode.none;

  MouseReportMode _mouseReportMode = MouseReportMode.normal;

  bool _cursorBlinkMode = false;

  bool _cursorVisibleMode = true;

  TerminalCursorType? _applicationCursorType;

  TerminalCursorType? get applicationCursorType => _applicationCursorType;

  bool _appKeypadMode = false;

  bool _reportFocusMode = false;

  bool _altBufferMouseScrollMode = false;

  bool _bracketedPasteMode = false;

  bool _synchronizedUpdateMode = false;

  Timer? _synchronizedUpdateTimer;

  bool _isDisposed = false;

  /* State getters */

  /// Number of cells in a terminal row.
  @override
  int get viewWidth => _viewWidth;

  /// Number of rows in this terminal.
  @override
  int get viewHeight => _viewHeight;

  @override
  CursorStyle get cursor => _cursorStyle;

  @override
  bool get insertMode => _insertMode;

  @override
  bool get lineFeedMode => _lineFeedMode;

  @override
  bool get cursorKeysMode => _cursorKeysMode;

  @override
  bool get reverseDisplayMode => _reverseDisplayMode;

  @override
  bool get originMode => _originMode;

  @override
  bool get autoWrapMode => _autoWrapMode;

  @override
  MouseMode get mouseMode => _mouseMode;

  @override
  MouseReportMode get mouseReportMode => _mouseReportMode;

  @override
  bool get cursorBlinkMode => _cursorBlinkMode;

  @override
  bool get cursorVisibleMode => _cursorVisibleMode;

  @override
  bool get appKeypadMode => _appKeypadMode;

  @override
  bool get reportFocusMode => _reportFocusMode;

  @override
  bool get altBufferMouseScrollMode => _altBufferMouseScrollMode;

  @override
  bool get bracketedPasteMode => _bracketedPasteMode;

  /// Current active buffer of the terminal. This is initially [mainBuffer] and
  /// can be switched back and forth from [altBuffer] to [mainBuffer] when
  /// the underlying program requests it.
  Buffer get buffer => _buffer;

  Buffer get mainBuffer => _mainBuffer;

  Buffer get altBuffer => _altBuffer;

  bool get isUsingAltBuffer => _buffer == _altBuffer;

  /// Lines of the active buffer.
  IndexAwareCircularBuffer<BufferLine> get lines => _buffer.lines;

  String? hyperlinkAt(CellOffset position) {
    if (position.y < 0 || position.y >= _buffer.lines.length) return null;
    final line = _buffer.lines[position.y];
    if (position.x < 0 || position.x >= line.length) return null;

    return _hyperlinks[line.getHyperlinkId(position.x)];
  }

  /// Whether the terminal performs reflow when the viewport size changes or
  /// simply truncates lines. true by default.
  @override
  bool reflowEnabled;

  /// Writes the data from the underlying program to the terminal. Calling this
  /// updates the states of the terminal and emits events such as [onBell] or
  /// [onTitleChange] when the escape sequences in [data] request it.
  void write(String data) {
    if (_isDisposed) return;
    _parser.write(data);
    if (_synchronizedUpdateMode) return;
    notifyListeners();
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _synchronizedUpdateTimer?.cancel();
    _synchronizedUpdateTimer = null;
    _synchronizedUpdateMode = false;
    clearListeners();
    _hyperlinks.clear();
    _explicitHyperlinkIds.clear();
  }

  /// Sends a key event to the underlying program.
  ///
  /// See also:
  /// - [charInput]
  /// - [textInput]
  /// - [paste]
  bool keyInput(
    TerminalKey key, {
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
  }) {
    if (_isDisposed) return false;
    final output = inputHandler?.call(
      TerminalKeyboardEvent(
        key: key,
        shift: shift,
        alt: alt,
        ctrl: ctrl,
        state: this,
        altBuffer: isUsingAltBuffer,
        platform: platform,
      ),
    );

    if (output != null) {
      onOutput?.call(output);
      return true;
    }

    return false;
  }

  /// Similary to [keyInput], but takes a character as input instead of a
  /// [TerminalKey].
  ///
  /// See also:
  /// - [keyInput]
  /// - [textInput]
  /// - [paste]
  bool charInput(
    int charCode, {
    bool alt = false,
    bool ctrl = false,
  }) {
    if (_isDisposed) return false;
    if (ctrl) {
      // a(97) ~ z(122)
      if (charCode >= Ascii.a && charCode <= Ascii.z) {
        final output = charCode - Ascii.a + 1;
        onOutput?.call(String.fromCharCode(output));
        return true;
      }

      // [(91) ~ _(95)
      if (charCode >= Ascii.openBracket && charCode <= Ascii.underscore) {
        final output = charCode - Ascii.openBracket + 27;
        onOutput?.call(String.fromCharCode(output));
        return true;
      }
    }

    if (alt && platform != TerminalTargetPlatform.macos) {
      if (charCode >= Ascii.a && charCode <= Ascii.z) {
        final code = charCode - Ascii.a + 65;
        final input = [0x1b, code];
        onOutput?.call(String.fromCharCodes(input));
        return true;
      }
    }

    return false;
  }

  /// Sends regular text input to the underlying program.
  ///
  /// See also:
  /// - [keyInput]
  /// - [charInput]
  /// - [paste]
  void textInput(String text) {
    if (_isDisposed) return;
    onOutput?.call(text);
  }

  /// Similar to [textInput], except that when the program tells the terminal
  /// that it supports [bracketedPasteMode], the text is wrapped in escape
  /// sequences to indicate that it is a paste operation. Prefer this method
  /// over [textInput] when pasting text.
  ///
  /// See also:
  /// - [textInput]
  void paste(String text) {
    if (_isDisposed) return;
    if (_bracketedPasteMode) {
      onOutput?.call(_emitter.bracketedPaste(text));
    } else {
      textInput(text);
    }
  }

  /// Reports a terminal viewport focus change to the underlying application.
  void focusInput(bool focused) {
    if (_isDisposed) return;
    if (!_reportFocusMode) return;
    onOutput?.call(switch (focused) {
      true => _emitter.focusIn(),
      false => _emitter.focusOut(),
    });
  }

  // Handle a mouse event and return true if it was handled.
  bool mouseInput(
    TerminalMouseButton button,
    TerminalMouseButtonState buttonState,
    CellOffset position, {
    bool motion = false,
    TerminalMouseModifiers modifiers = TerminalMouseModifiers.none,
    CellOffset? pixelPosition,
  }) {
    if (_isDisposed) return false;
    final output = mouseHandler?.call(TerminalMouseEvent(
      button: button,
      buttonState: buttonState,
      position: position,
      pixelPosition: pixelPosition,
      state: this,
      platform: platform,
      motion: motion,
      modifiers: modifiers,
    ));
    if (output != null) {
      onOutput?.call(output);
      return true;
    }
    return false;
  }

  /// Resize the terminal screen. [newWidth] and [newHeight] should be greater
  /// than 0. Text reflow is currently not implemented and will be avaliable in
  /// the future.
  @override
  void resize(
    int newWidth,
    int newHeight, [
    int? pixelWidth,
    int? pixelHeight,
  ]) {
    if (_isDisposed) return;
    newWidth = max(newWidth, 1);
    newHeight = max(newHeight, 1);

    onResize?.call(newWidth, newHeight, pixelWidth ?? 0, pixelHeight ?? 0);

    //we need to resize both buffers so that they are ready when we switch between them
    _altBuffer.resize(_viewWidth, _viewHeight, newWidth, newHeight);
    _mainBuffer.resize(_viewWidth, _viewHeight, newWidth, newHeight);

    _viewWidth = newWidth;
    _viewHeight = newHeight;

    if (buffer == _altBuffer) {
      buffer.clearScrollback();
    }

    _altBuffer.resetVerticalMargins();
    _mainBuffer.resetVerticalMargins();
  }

  @override
  String toString() {
    return 'Terminal(#$hashCode, $_viewWidth x $_viewHeight, ${_buffer.height} lines)';
  }

  /* Handlers */

  @override
  void writeChar(int char) {
    _precedingCodepoint = char;
    _buffer.writeChar(char);
  }

  /* SBC */

  @override
  void bell() {
    onBell?.call();
  }

  @override
  void backspaceReturn() {
    _buffer.moveCursorX(-1);
  }

  @override
  void tab() {
    final nextStop = _tabStops.find(_buffer.cursorX + 1, _viewWidth);

    if (nextStop != null) {
      _buffer.setCursorX(nextStop);
    } else {
      _buffer.setCursorX(_viewWidth);
      _buffer.cursorGoForward(); // Enter pending-wrap state
    }
  }

  @override
  void lineFeed() {
    _buffer.lineFeed();
  }

  @override
  void carriageReturn() {
    _buffer.setCursorX(0);
  }

  @override
  void shiftOut() {
    _buffer.charset.use(1);
  }

  @override
  void shiftIn() {
    _buffer.charset.use(0);
  }

  @override
  void unknownSBC(int char) {
    // no-op
  }

  /* ANSI sequence */

  @override
  void saveCursor() {
    _buffer.saveCursor();
  }

  @override
  void restoreCursor() {
    _buffer.restoreCursor();
  }

  @override
  void index() {
    _buffer.index();
  }

  @override
  void nextLine() {
    _buffer.index();
    _buffer.setCursorX(0);
  }

  @override
  void setTapStop() {
    _tabStops.setAt(_buffer.cursorX);
  }

  @override
  void reset() {
    _synchronizedUpdateTimer?.cancel();
    _synchronizedUpdateTimer = null;
    _synchronizedUpdateMode = false;
    _buffer = _mainBuffer;
    _precedingCodepoint = 0;
    _cursorStyle.reset();
    _cursorStyle.hyperlinkId = 0;
    _insertMode = false;
    _lineFeedMode = false;
    _cursorKeysMode = false;
    _reverseDisplayMode = false;
    _originMode = false;
    _autoWrapMode = true;
    _mouseMode = MouseMode.none;
    _mouseReportMode = MouseReportMode.normal;
    _cursorBlinkMode = false;
    _cursorVisibleMode = true;
    _applicationCursorType = null;
    _appKeypadMode = false;
    _reportFocusMode = false;
    _altBufferMouseScrollMode = false;
    _bracketedPasteMode = false;
    _hyperlinks.clear();
    _explicitHyperlinkIds.clear();
    _nextHyperlinkId = 1;
    _tabStops.reset();
    _mainBuffer.reset();
    _altBuffer.reset();
  }

  @override
  void softReset() {
    _synchronizedUpdateTimer?.cancel();
    _synchronizedUpdateTimer = null;
    _synchronizedUpdateMode = false;
    _precedingCodepoint = 0;
    _cursorStyle.reset();
    _cursorStyle.hyperlinkId = 0;
    _insertMode = false;
    _lineFeedMode = false;
    _cursorKeysMode = false;
    _reverseDisplayMode = false;
    _originMode = false;
    _autoWrapMode = true;
    _mouseMode = MouseMode.none;
    _mouseReportMode = MouseReportMode.normal;
    _cursorBlinkMode = false;
    _cursorVisibleMode = true;
    _applicationCursorType = null;
    _appKeypadMode = false;
    _reportFocusMode = false;
    _altBufferMouseScrollMode = false;
    _bracketedPasteMode = false;
    _tabStops.reset();
    _buffer.charset.reset();
    _buffer.resetVerticalMargins();
  }

  @override
  void reverseIndex() {
    _buffer.reverseIndex();
  }

  @override
  void designateCharset(int charset, int name) {
    _buffer.charset.designate(charset, name);
  }

  @override
  void unkownEscape(int char) {
    // no-op
  }

  /* CSI */

  @override
  void repeatPreviousCharacter(int count) {
    if (_precedingCodepoint == 0) {
      return;
    }

    for (var i = 0; i < count; i++) {
      _buffer.writeChar(_precedingCodepoint);
    }
  }

  @override
  void setCursor(int x, int y) {
    _buffer.setCursor(x, y);
  }

  @override
  void setCursorX(int x) {
    _buffer.setCursorX(x);
  }

  @override
  void setCursorY(int y) {
    _buffer.setCursorY(y);
  }

  @override
  void moveCursorX(int offset) {
    _buffer.moveCursorX(offset);
  }

  @override
  void moveCursorY(int n) {
    _buffer.moveCursorY(n);
  }

  @override
  void clearTabStopUnderCursor() {
    _tabStops.clearAt(_buffer.cursorX);
  }

  @override
  void clearAllTabStops() {
    _tabStops.clearAll();
  }

  @override
  void sendPrimaryDeviceAttributes() {
    onOutput?.call(_emitter.primaryDeviceAttributes());
  }

  @override
  void sendSecondaryDeviceAttributes() {
    onOutput?.call(_emitter.secondaryDeviceAttributes());
  }

  @override
  void sendTertiaryDeviceAttributes() {
    onOutput?.call(_emitter.tertiaryDeviceAttributes());
  }

  @override
  void sendOperatingStatus() {
    onOutput?.call(_emitter.operatingStatus());
  }

  @override
  void sendCursorPosition() {
    onOutput?.call(_emitter.cursorPosition(_buffer.cursorX, _buffer.cursorY));
  }

  @override
  void setMargins(int top, [int? bottom]) {
    _buffer.setVerticalMargins(top, bottom ?? viewHeight - 1);
  }

  @override
  void cursorNextLine(int amount) {
    _buffer.moveCursorY(amount);
    _buffer.setCursorX(0);
  }

  @override
  void cursorPrecedingLine(int amount) {
    _buffer.moveCursorY(-amount);
    _buffer.setCursorX(0);
  }

  @override
  void eraseDisplayBelow() {
    _buffer.eraseDisplayFromCursor();
  }

  @override
  void eraseDisplayAbove() {
    _buffer.eraseDisplayToCursor();
  }

  @override
  void eraseDisplay() {
    _buffer.eraseDisplay();
  }

  @override
  void eraseScrollbackOnly() {
    _buffer.clearScrollback();
  }

  @override
  void eraseLineRight() {
    _buffer.eraseLineFromCursor();
  }

  @override
  void eraseLineLeft() {
    _buffer.eraseLineToCursor();
  }

  @override
  void eraseLine() {
    _buffer.eraseLine();
  }

  @override
  void insertLines(int amount) {
    _buffer.insertLines(amount);
  }

  @override
  void deleteLines(int amount) {
    _buffer.deleteLines(amount);
  }

  @override
  void deleteChars(int amount) {
    _buffer.deleteChars(amount);
  }

  @override
  void scrollUp(int amount) {
    _buffer.scrollUp(amount);
  }

  @override
  void scrollDown(int amount) {
    _buffer.scrollDown(amount);
  }

  @override
  void eraseChars(int amount) {
    _buffer.eraseChars(amount);
  }

  @override
  void insertBlankChars(int amount) {
    _buffer.insertBlankChars(amount);
  }

  @override
  void sendSize() {
    onOutput?.call(_emitter.size(viewHeight, viewWidth));
  }

  @override
  void unknownCSI(int finalByte) {
    // no-op
  }

  @override
  void setCursorShape(int style) {
    _applicationCursorType = switch (style) {
      0 || 1 || 2 => TerminalCursorType.block,
      3 || 4 => TerminalCursorType.underline,
      5 || 6 => TerminalCursorType.verticalBar,
      _ => _applicationCursorType,
    };
    if (style < 0 || style > 6) return;
    _cursorBlinkMode = style == 0 || style.isOdd;
  }

  /* Modes */

  @override
  void setInsertMode(bool enabled) {
    _insertMode = enabled;
  }

  @override
  void setLineFeedMode(bool enabled) {
    _lineFeedMode = enabled;
  }

  @override
  void setUnknownMode(int mode, bool enabled) {
    // no-op
  }

  /* DEC Private modes */

  @override
  void setCursorKeysMode(bool enabled) {
    _cursorKeysMode = enabled;
  }

  @override
  void setReverseDisplayMode(bool enabled) {
    _reverseDisplayMode = enabled;
  }

  @override
  void setOriginMode(bool enabled) {
    _originMode = enabled;
  }

  @override
  void setColumnMode(bool enabled) {
    // no-op
  }

  @override
  void setAutoWrapMode(bool enabled) {
    _autoWrapMode = enabled;
  }

  @override
  void setMouseMode(MouseMode mode) {
    _mouseMode = mode;
  }

  @override
  void setCursorBlinkMode(bool enabled) {
    _cursorBlinkMode = enabled;
  }

  @override
  void setCursorVisibleMode(bool enabled) {
    _cursorVisibleMode = enabled;
  }

  @override
  void useAltBuffer() {
    _buffer = _altBuffer;
  }

  @override
  void useMainBuffer() {
    _buffer = _mainBuffer;
  }

  @override
  void clearAltBuffer() {
    _altBuffer.clear();
  }

  @override
  void setAppKeypadMode(bool enabled) {
    _appKeypadMode = enabled;
  }

  @override
  void setReportFocusMode(bool enabled) {
    _reportFocusMode = enabled;
  }

  @override
  void setMouseReportMode(MouseReportMode mode) {
    _mouseReportMode = mode;
  }

  @override
  void setAltBufferMouseScrollMode(bool enabled) {
    _altBufferMouseScrollMode = enabled;
  }

  @override
  void setBracketedPasteMode(bool enabled) {
    _bracketedPasteMode = enabled;
  }

  @override
  void setSynchronizedUpdateMode(bool enabled) {
    _synchronizedUpdateTimer?.cancel();
    _synchronizedUpdateMode = enabled;
    if (!enabled) return;

    _synchronizedUpdateTimer = Timer(const Duration(milliseconds: 150), () {
      _synchronizedUpdateMode = false;
      _synchronizedUpdateTimer = null;
      notifyListeners();
    });
  }

  @override
  void setUnknownDecMode(int mode, bool enabled) {
    // no-op
  }

  /* Select Graphic Rendition (SGR) */

  @override
  void resetCursorStyle() {
    _cursorStyle.reset();
  }

  @override
  void setCursorBold() {
    _cursorStyle.setBold();
  }

  @override
  void setCursorFaint() {
    _cursorStyle.setFaint();
  }

  @override
  void setCursorItalic() {
    _cursorStyle.setItalic();
  }

  @override
  void setCursorUnderline() {
    _cursorStyle.setUnderline();
  }

  @override
  void setCursorDoubleUnderline() {
    _cursorStyle.setDoubleUnderline();
  }

  @override
  void setCursorUndercurl() {
    _cursorStyle.setUndercurl();
  }

  @override
  void setCursorDottedUnderline() {
    _cursorStyle.setDottedUnderline();
  }

  @override
  void setCursorDashedUnderline() {
    _cursorStyle.setDashedUnderline();
  }

  @override
  void setCursorBlink() {
    _cursorStyle.setBlink();
  }

  @override
  void setCursorInverse() {
    _cursorStyle.setInverse();
  }

  @override
  void setCursorInvisible() {
    _cursorStyle.setInvisible();
  }

  @override
  void setCursorStrikethrough() {
    _cursorStyle.setStrikethrough();
  }

  @override
  void setCursorOverline() {
    _cursorStyle.setOverline();
  }

  @override
  void unsetCursorBold() {
    _cursorStyle.unsetBold();
  }

  @override
  void unsetCursorFaint() {
    _cursorStyle.unsetFaint();
  }

  @override
  void unsetCursorItalic() {
    _cursorStyle.unsetItalic();
  }

  @override
  void unsetCursorUnderline() {
    _cursorStyle.unsetUnderline();
  }

  @override
  void unsetCursorBlink() {
    _cursorStyle.unsetBlink();
  }

  @override
  void unsetCursorInverse() {
    _cursorStyle.unsetInverse();
  }

  @override
  void unsetCursorInvisible() {
    _cursorStyle.unsetInvisible();
  }

  @override
  void unsetCursorStrikethrough() {
    _cursorStyle.unsetStrikethrough();
  }

  @override
  void unsetCursorOverline() {
    _cursorStyle.unsetOverline();
  }

  @override
  void setForegroundColor16(int color) {
    _cursorStyle.setForegroundColor16(color);
  }

  @override
  void setForegroundColor256(int index) {
    _cursorStyle.setForegroundColor256(index);
  }

  @override
  void setForegroundColorRgb(int r, int g, int b) {
    _cursorStyle.setForegroundColorRgb(r, g, b);
  }

  @override
  void resetForeground() {
    _cursorStyle.resetForegroundColor();
  }

  @override
  void setBackgroundColor16(int color) {
    _cursorStyle.setBackgroundColor16(color);
  }

  @override
  void setBackgroundColor256(int index) {
    _cursorStyle.setBackgroundColor256(index);
  }

  @override
  void setBackgroundColorRgb(int r, int g, int b) {
    _cursorStyle.setBackgroundColorRgb(r, g, b);
  }

  @override
  void resetBackground() {
    _cursorStyle.resetBackgroundColor();
  }

  @override
  void setUnderlineColor256(int index) {
    _cursorStyle.setUnderlineColor256(index);
  }

  @override
  void setUnderlineColorRgb(int r, int g, int b) {
    _cursorStyle.setUnderlineColorRgb(r, g, b);
  }

  @override
  void resetUnderlineColor() {
    _cursorStyle.resetUnderlineColor();
  }

  @override
  void unsupportedStyle(int param) {
    // no-op
  }

  /* OSC */

  @override
  void setTitle(String name) {
    onTitleChange?.call(name);
  }

  @override
  void setIconName(String name) {
    onIconChange?.call(name);
  }

  @override
  void setCurrentDirectory(String uri) {
    onCurrentDirectoryChange?.call(uri);
  }

  @override
  void setHyperlink(String params, String uri) {
    if (uri.isEmpty) {
      _cursorStyle.hyperlinkId = 0;
      return;
    }

    String? explicitId;
    for (final param in params.split(':')) {
      if (!param.startsWith('id=')) continue;
      explicitId = param.substring(3);
      break;
    }

    final key = explicitId == null ? null : '$explicitId\x00$uri';
    final existingId = key == null ? null : _explicitHyperlinkIds[key];
    if (existingId != null) {
      _cursorStyle.hyperlinkId = existingId;
      return;
    }
    if (_hyperlinks.length >= _maxHyperlinks) {
      _cursorStyle.hyperlinkId = 0;
      return;
    }

    final hyperlinkId = _nextHyperlinkId++;
    _hyperlinks[hyperlinkId] = uri;
    if (key != null) _explicitHyperlinkIds[key] = hyperlinkId;
    _cursorStyle.hyperlinkId = hyperlinkId;
  }

  @override
  void setIndexedColor(int index, String value) {
    if (index < 0 || index > 255) return;
    final color = _parseOscColor(value);
    if (color == null || _indexedColorOverrides[index] == color) return;
    _indexedColorOverrides[index] = color;
    _colorRevision++;
  }

  @override
  void queryIndexedColor(int index) {
    if (index < 0 || index > 255) return;
    final color = _indexedColorOverrides[index] ?? onColorQuery?.call(4, index);
    if (color == null) return;
    onOutput?.call('\x1b]4;$index;${_formatOscColor(color)}\x1b\\');
  }

  @override
  void resetIndexedColors(List<int> indices) {
    if (indices.isEmpty) {
      if (_indexedColorOverrides.isEmpty) return;
      _indexedColorOverrides.clear();
      _colorRevision++;
      return;
    }

    var changed = false;
    for (final index in indices) {
      changed = _indexedColorOverrides.remove(index) != null || changed;
    }
    if (changed) _colorRevision++;
  }

  @override
  void setDynamicColor(int code, String value) {
    final color = _parseOscColor(value);
    if (color == null) return;

    switch (code) {
      case 10:
        if (_foregroundColorOverride == color) return;
        _foregroundColorOverride = color;
        break;
      case 11:
        if (_backgroundColorOverride == color) return;
        _backgroundColorOverride = color;
        break;
      case 12:
        if (_cursorColorOverride == color) return;
        _cursorColorOverride = color;
        break;
      default:
        return;
    }
    _colorRevision++;
  }

  @override
  void queryDynamicColor(int code) {
    final override = switch (code) {
      10 => _foregroundColorOverride,
      11 => _backgroundColorOverride,
      12 => _cursorColorOverride,
      _ => null,
    };
    final color = override ?? onColorQuery?.call(code, null);
    if (color == null) return;
    onOutput?.call('\x1b]$code;${_formatOscColor(color)}\x1b\\');
  }

  @override
  void resetDynamicColor(int code) {
    switch (code) {
      case 10:
        if (_foregroundColorOverride == null) return;
        _foregroundColorOverride = null;
        break;
      case 11:
        if (_backgroundColorOverride == null) return;
        _backgroundColorOverride = null;
        break;
      case 12:
        if (_cursorColorOverride == null) return;
        _cursorColorOverride = null;
        break;
      default:
        return;
    }
    _colorRevision++;
  }

  @override
  void unknownOSC(String ps, List<String> pt) {
    onPrivateOSC?.call(ps, pt);
  }
}

int? _parseOscColor(String value) {
  if (value.startsWith('#')) {
    final hex = value.substring(1);
    if (hex.length != 3 &&
        hex.length != 6 &&
        hex.length != 9 &&
        hex.length != 12) {
      return null;
    }
    final componentLength = hex.length ~/ 3;
    return _parseOscColorComponents([
      hex.substring(0, componentLength),
      hex.substring(componentLength, componentLength * 2),
      hex.substring(componentLength * 2),
    ]);
  }

  if (!value.startsWith('rgb:')) return null;
  return _parseOscColorComponents(value.substring(4).split('/'));
}

int? _parseOscColorComponents(List<String> components) {
  if (components.length != 3) return null;
  var color = 0;
  for (final component in components) {
    if (component.isEmpty || component.length > 4) return null;
    final value = int.tryParse(component, radix: 16);
    if (value == null) return null;
    final maximum = (1 << (component.length * 4)) - 1;
    color = (color << 8) | ((value * 255 + maximum ~/ 2) ~/ maximum);
  }
  return color;
}

String _formatOscColor(int color) {
  String component(int shift) {
    final value = ((color >> shift) & 0xff) * 0x101;
    return value.toRadixString(16).padLeft(4, '0');
  }

  return 'rgb:${component(16)}/${component(8)}/${component(0)}';
}
