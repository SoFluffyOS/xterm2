import 'dart:async';
import 'dart:convert';
import 'dart:math' show max, min;

import 'package:xterm2/src/base/observable.dart';
import 'package:xterm2/src/core/buffer/buffer.dart';
import 'package:xterm2/src/core/buffer/cell_offset.dart';
import 'package:xterm2/src/core/buffer/line.dart';
import 'package:xterm2/src/core/cell.dart';
import 'package:xterm2/src/core/color_scheme.dart';
import 'package:xterm2/src/core/cursor.dart';
import 'package:xterm2/src/core/escape/emitter.dart';
import 'package:xterm2/src/core/escape/handler.dart';
import 'package:xterm2/src/core/escape/parser.dart';
import 'package:xterm2/src/core/input/handler.dart';
import 'package:xterm2/src/core/input/keys.dart';
import 'package:xterm2/src/core/mouse/button.dart';
import 'package:xterm2/src/core/mouse/button_state.dart';
import 'package:xterm2/src/core/mouse/handler.dart';
import 'package:xterm2/src/core/mouse/mode.dart';
import 'package:xterm2/src/core/mouse/modifiers.dart';
import 'package:xterm2/src/core/platform.dart';
import 'package:xterm2/src/core/state.dart';
import 'package:xterm2/src/core/tabs.dart';
import 'package:xterm2/src/utils/ascii.dart';
import 'package:xterm2/src/utils/circular_buffer.dart';
import 'package:xterm2/src/utils/unicode_v11.dart';

enum _ProtectionMode { off, iso, dec }

enum TerminalSemanticPromptContent {
  output,
  prompt,
  input,
}

enum TerminalSemanticPromptKind {
  initial,
  right,
  continuation,
  secondary,
}

enum TerminalSemanticPromptClickMode {
  line,
  multiple,
  eventsAbsolute,
  eventsRelative,
}

enum TerminalSemanticPromptRedraw {
  disabled,
  enabled,
  last,
}

final class TerminalSemanticPromptState {
  const TerminalSemanticPromptState({
    required this.content,
    this.lastCommandExitCode,
    this.aid,
    this.promptKind,
    this.clickMode,
    this.redraw,
    this.specialKey,
    this.commandLine,
  });

  final TerminalSemanticPromptContent content;

  final int? lastCommandExitCode;

  final String? aid;

  final TerminalSemanticPromptKind? promptKind;

  final TerminalSemanticPromptClickMode? clickMode;

  final TerminalSemanticPromptRedraw? redraw;

  final bool? specialKey;

  final String? commandLine;
}

/// [Terminal] is an interface to interact with command line applications. It
/// translates escape sequences from the application into updates to the
/// [buffer] and events such as [onTitleChange] or [onBell], as well as
/// translating user input into escape sequences that the application can
/// understand.
class Terminal with Observable implements TerminalState, EscapeHandler {
  static const _maxHyperlinks = 4096;
  static const _maxHyperlinkId =
      CellAttr.hyperlinkMask >> CellAttr.hyperlinkShift;
  static const _maxKittyKeyboardModeStackDepth = 4096;
  static const _maxTitleStackDepth = 4096;
  static const _kittyKeyboardModeMask = 0x1f;
  static const _specialColorBaseIndex = 256;
  static const _specialColorCount = 5;

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

  /// Called when the application reports its remote user/host using OSC 1337.
  void Function(String value)? onRemoteHostChange;

  /// Called when the application reports an iTerm2 user variable.
  void Function(String name, String value)? onUserVariableChange;

  /// Resolves an iTerm2 session variable for OSC 1337 ReportVariable queries.
  String? Function(String name)? onITerm2VariableQuery;

  /// Called when the application sets the iTerm2 badge format.
  void Function(String format)? onITerm2BadgeFormatChange;

  /// Called when the application reports its iTerm2 shell integration version.
  void Function(String version)? onITerm2ShellIntegrationVersionChange;

  /// Called when the application sets an iTerm2 mark at the cursor.
  void Function()? onITerm2Mark;

  /// Called when the application requests an iTerm2 profile change.
  void Function(String profile)? onITerm2ProfileChange;

  /// Called when the application requests terminal focus.
  void Function()? onFocusRequest;

  /// Called when the application requests opening a URL.
  void Function(String url)? onOpenUrl;

  /// Called when the application requests user attention.
  void Function(String value)? onAttentionRequest;

  /// Called when the application requests a desktop notification using
  /// OSC 9 or OSC 777.
  void Function(String title, String body)? onNotification;

  /// Called when the application requests a mouse pointer shape using OSC 22.
  void Function(String shape)? onMouseShapeChange;

  /// Called when the application reports task progress using OSC 9;4.
  void Function(TerminalProgressReport report)? onProgressReport;

  /// Called when the application reports shell-integration prompt state using
  /// OSC 133.
  void Function(TerminalSemanticPromptState state)? onSemanticPrompt;

  /// Resolves the currently displayed color for OSC color queries. [code] is
  /// 4 for an indexed color, 5 for a special attribute color, or 10–12 for
  /// dynamic colors; [index] is provided only for code 4 or 5. The return value
  /// is a 24-bit RGB color.
  int? Function(int code, int? index)? onColorQuery;

  /// Resolves the current terminal color scheme for CSI ? 996 n queries.
  /// Return null to ignore the query.
  TerminalColorScheme? Function()? onColorSchemeQuery;

  /// Resolves the terminal version string for XTVERSION (CSI > q) queries.
  /// Return null or an empty string to use the default xterm2 version.
  String? Function()? onXtVersionQuery;

  /// Called when the application sends ENQ (0x05). Return null or an empty
  /// string to keep the request silent.
  String? Function()? onEnquiry;

  /// Called when the application requests copying text through OSC 52.
  ///
  /// [selector] is usually `c` for clipboard or `p`/`s` for primary selection.
  /// Leave this unset to deny clipboard writes.
  void Function(String selector, String text)? onClipboardStore;

  /// Called when the application requests clipboard contents through OSC 52.
  ///
  /// Return null to deny the request. The result may be asynchronous.
  FutureOr<String?> Function(String selector)? onClipboardQuery;

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
    this.onRemoteHostChange,
    this.onUserVariableChange,
    this.onITerm2VariableQuery,
    this.onITerm2BadgeFormatChange,
    this.onITerm2ShellIntegrationVersionChange,
    this.onITerm2Mark,
    this.onITerm2ProfileChange,
    this.onFocusRequest,
    this.onOpenUrl,
    this.onAttentionRequest,
    this.onNotification,
    this.onMouseShapeChange,
    this.onProgressReport,
    this.onSemanticPrompt,
    this.onColorQuery,
    this.onColorSchemeQuery,
    this.onXtVersionQuery,
    this.onEnquiry,
    this.onClipboardStore,
    this.onClipboardQuery,
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
  final Map<int, int> _specialColorOverrides = {};
  final Map<int, int> _auxiliaryDynamicColorOverrides = {};

  int? _foregroundColorOverride;

  int? _backgroundColorOverride;

  int? _cursorColorOverride;

  int? _selectionColorOverride;

  int? _selectionForegroundColorOverride;

  int _colorRevision = 0;

  String? _clipboardCaptureSelector;
  StringBuffer? _clipboardCaptureBuffer;

  TerminalSemanticPromptState _semanticPromptState =
      const TerminalSemanticPromptState(
    content: TerminalSemanticPromptContent.output,
  );

  int _nextHyperlinkId = 1;

  int get colorRevision => _colorRevision;

  TerminalSemanticPromptState get semanticPromptState => _semanticPromptState;

  Iterable<MapEntry<int, int>> get indexedColorOverrides {
    return _indexedColorOverrides.entries;
  }

  Iterable<MapEntry<int, int>> get specialColorOverrides {
    return _specialColorOverrides.entries;
  }

  int? get foregroundColorOverride => _foregroundColorOverride;

  int? get backgroundColorOverride => _backgroundColorOverride;

  int? get cursorColorOverride => _cursorColorOverride;

  int? get selectionColorOverride => _selectionColorOverride;

  int? get selectionForegroundColorOverride =>
      _selectionForegroundColorOverride;

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

  int _cellPixelWidth = 0;

  int _cellPixelHeight = 0;

  final _cursorStyle = CursorStyle();

  _ProtectionMode _protectionMode = _ProtectionMode.off;

  bool _insertMode = false;

  bool _sendReceiveMode = true;

  bool _keyboardActionMode = false;

  bool _lineFeedMode = false;

  bool _cursorKeysMode = false;

  bool _reverseDisplayMode = false;

  bool _originMode = false;

  bool _enableColumnMode = false;

  bool _slowScrollMode = false;

  bool _autoWrapMode = true;

  bool _autoRepeatMode = false;

  bool _reverseWrapMode = false;

  bool _reverseWrapExtendedMode = false;

  MouseMode _mouseMode = MouseMode.none;

  MouseReportMode _mouseReportMode = MouseReportMode.normal;

  bool _cursorBlinkMode = false;

  bool _cursorVisibleMode = true;

  TerminalCursorType? _applicationCursorType;

  TerminalCursorType? get applicationCursorType => _applicationCursorType;

  bool _appKeypadMode = false;

  bool _ignoreKeypadWithNumLockMode = true;

  bool _backarrowKeyMode = false;

  bool _reportFocusMode = false;

  bool _focused = true;

  bool _mouseShiftCaptureMode = false;

  bool _altBufferMouseScrollMode = false;

  bool _altEscPrefixMode = true;

  bool _altSendsEscapeMode = false;

  bool _bracketedPasteMode = false;

  bool _inBandSizeReportMode = false;

  bool _reportColorSchemeMode = false;

  bool _graphemeClusterMode = true;

  bool _leftRightMarginMode = false;

  bool _cursorLineHighlightMode = false;

  bool get cursorLineHighlightMode => _cursorLineHighlightMode;

  bool _attributeChangeExtentRectangular = false;

  int _keyClickVolume = 0;

  int _marginBellVolume = 0;

  int _warningBellVolume = 0;

  int _lockKeyStyle = 0;

  int _terminalModeEmulation = 0;

  int _activeStatusDisplay = 0;

  int _statusLineType = 0;

  int _conformanceLevel = 61;

  int _conformanceControls = 1;

  int _protectedFieldsAttribute = 0;

  int _transmitTerminationCharacter = 0;

  int _lineTransmitTerminationCharacter = 0;

  final _assignedColors = <int, ({int foreground, int background})>{};

  final _alternateTextColors = <int, ({int foreground, int background})>{};

  int _preferredSupplementalSetSize = 94;

  String _preferredSupplementalSetFinal = '%5';

  final _titleModes = <int>{};

  bool _synchronizedUpdateMode = false;

  Timer? _synchronizedUpdateTimer;

  final _savedDecModes = <int, bool>{};

  int _kittyKeyboardMode = 0;

  int _modifyOtherKeysMode = 0;

  final _kittyKeyboardModeStack = <int>[];

  String? _title;

  String? _iconTitle;

  final _titleStack = <String?>[];

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
  bool get reverseWrapMode => _reverseWrapMode;

  @override
  bool get reverseWrapExtendedMode => _reverseWrapExtendedMode;

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
  bool get ignoreKeypadWithNumLockMode => _ignoreKeypadWithNumLockMode;

  @override
  bool get backarrowKeyMode => _backarrowKeyMode;

  @override
  bool get reportFocusMode => _reportFocusMode;

  @override
  bool get mouseShiftCaptureMode => _mouseShiftCaptureMode;

  @override
  bool get altBufferMouseScrollMode => _altBufferMouseScrollMode;

  @override
  bool get altEscPrefixMode => _altEscPrefixMode;

  @override
  bool get altSendsEscapeMode => _altSendsEscapeMode;

  @override
  bool get bracketedPasteMode => _bracketedPasteMode;

  @override
  bool get inBandSizeReportMode => _inBandSizeReportMode;

  @override
  bool get reportColorSchemeMode => _reportColorSchemeMode;

  @override
  bool get graphemeClusterMode => _graphemeClusterMode;

  @override
  int get kittyKeyboardMode => _kittyKeyboardMode;

  @override
  int get modifyOtherKeysMode => _modifyOtherKeysMode;

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
    final hyperlinkId = hyperlinkIdAt(position);
    if (hyperlinkId == 0) return null;
    return _hyperlinks[hyperlinkId];
  }

  int hyperlinkIdAt(CellOffset position) {
    if (position.y < 0 || position.y >= _buffer.lines.length) return 0;
    final line = _buffer.lines[position.y];
    if (position.x < 0 || position.x >= line.length) return 0;
    return line.getHyperlinkId(position.x);
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
    _clipboardCaptureSelector = null;
    _clipboardCaptureBuffer = null;
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
    TerminalKeyEventType type = TerminalKeyEventType.press,
    String? text,
  }) {
    if (_isDisposed) return false;
    if (_keyboardActionMode) return false;
    final output = inputHandler?.call(
      TerminalKeyboardEvent(
        key: key,
        shift: shift,
        alt: alt,
        ctrl: ctrl,
        state: this,
        altBuffer: isUsingAltBuffer,
        platform: platform,
        type: type,
        text: text,
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
    if (_keyboardActionMode) return false;
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
    if (_keyboardActionMode) return;
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
    if (_keyboardActionMode) return;
    final sanitizedText = _sanitizePasteText(text);
    if (_bracketedPasteMode) {
      onOutput?.call(_emitter.bracketedPaste(sanitizedText));
      return;
    }

    onOutput?.call(sanitizedText.replaceAll('\n', '\r'));
  }

  static const _pasteControlReplacements = {
    0x00, // NUL
    0x03, // VINTR / Ctrl+C
    0x04, // EOT
    0x05, // ENQ
    0x08, // BS
    0x0f, // VDISCARD / Ctrl+O
    0x11, // VSTART / Ctrl+Q
    0x12, // VREPRINT / Ctrl+R
    0x13, // VSTOP / Ctrl+S
    0x15, // VKILL / Ctrl+U
    0x16, // VLNEXT / Ctrl+V
    0x17, // VWERASE / Ctrl+W
    0x1a, // VSUSP / Ctrl+Z
    0x1b, // ESC
    0x1c, // VQUIT / Ctrl+\
    0x7f, // DEL
  };

  String _sanitizePasteText(String text) {
    final codePoints = text.runes.toList(growable: false);
    var sanitized = StringBuffer();
    var changed = false;

    for (var i = 0; i < codePoints.length; i++) {
      final codePoint = codePoints[i];
      if (codePoint == 0x1b) {
        i = _skipPastedEscapeSequence(codePoints, i);
        changed = true;
        continue;
      }
      if (_shouldReplacePastedControl(codePoint)) {
        sanitized.writeCharCode(0x20);
        changed = true;
        continue;
      }
      sanitized.writeCharCode(codePoint);
    }

    return switch (changed) {
      true => sanitized.toString(),
      false => text,
    };
  }

  bool _shouldReplacePastedControl(int codePoint) {
    if (_pasteControlReplacements.contains(codePoint)) return true;
    return codePoint >= 0x80 && codePoint <= 0x9f;
  }

  int _skipPastedEscapeSequence(List<int> codePoints, int escapeIndex) {
    final nextIndex = escapeIndex + 1;
    if (nextIndex >= codePoints.length) return escapeIndex;

    final next = codePoints[nextIndex];
    if (next == 0x5b) {
      return _skipPastedCsiSequence(codePoints, nextIndex);
    }
    if (next == 0x5d) {
      return _skipPastedOscSequence(codePoints, nextIndex);
    }
    if (next == 0x50 || next == 0x5e || next == 0x5f) {
      return _skipPastedStringControl(codePoints, nextIndex);
    }

    return nextIndex;
  }

  int _skipPastedCsiSequence(List<int> codePoints, int csiIndex) {
    for (var i = csiIndex + 1; i < codePoints.length; i++) {
      final codePoint = codePoints[i];
      if (codePoint >= 0x40 && codePoint <= 0x7e) return i;
    }
    return codePoints.length - 1;
  }

  int _skipPastedOscSequence(List<int> codePoints, int oscIndex) {
    for (var i = oscIndex + 1; i < codePoints.length; i++) {
      final codePoint = codePoints[i];
      if (codePoint == 0x07) return i;
      if (codePoint == 0x1b &&
          i + 1 < codePoints.length &&
          codePoints[i + 1] == 0x5c) {
        return i + 1;
      }
    }
    return codePoints.length - 1;
  }

  int _skipPastedStringControl(List<int> codePoints, int controlIndex) {
    for (var i = controlIndex + 1; i < codePoints.length; i++) {
      if (codePoints[i] == 0x1b &&
          i + 1 < codePoints.length &&
          codePoints[i + 1] == 0x5c) {
        return i + 1;
      }
    }
    return codePoints.length - 1;
  }

  /// Reports a terminal viewport focus change to the underlying application.
  void focusInput(bool focused) {
    _focused = focused;
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
  /// than 0. Main-buffer text is reflowed when [reflowEnabled] is true.
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

    final nextCellPixelWidth = pixelWidth ?? _cellPixelWidth;
    final nextCellPixelHeight = pixelHeight ?? _cellPixelHeight;
    if (newWidth == _viewWidth &&
        newHeight == _viewHeight &&
        nextCellPixelWidth == _cellPixelWidth &&
        nextCellPixelHeight == _cellPixelHeight) {
      return;
    }

    final wasSynchronizedUpdateMode = _synchronizedUpdateMode;
    if (wasSynchronizedUpdateMode) {
      _synchronizedUpdateTimer?.cancel();
      _synchronizedUpdateTimer = null;
      _synchronizedUpdateMode = false;
    }

    onResize?.call(newWidth, newHeight, pixelWidth ?? 0, pixelHeight ?? 0);
    if (pixelWidth != null) {
      _cellPixelWidth = pixelWidth;
    }
    if (pixelHeight != null) {
      _cellPixelHeight = pixelHeight;
    }

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

    if (wasSynchronizedUpdateMode) notifyListeners();
    if (_inBandSizeReportMode) _sendInBandSizeReport();
  }

  @override
  void setColumnsPerPage(int cols) {
    resize(cols, _viewHeight);
  }

  @override
  void setLinesPerPage(int rows) {
    resize(_viewWidth, rows);
  }

  @override
  void setConformanceLevel(int level, int controls) {
    _conformanceLevel = level;
    _conformanceControls = switch (controls) {
      0 => 1,
      _ => controls,
    };
  }

  @override
  String toString() {
    return 'Terminal(#$hashCode, $_viewWidth x $_viewHeight, ${_buffer.height} lines)';
  }

  /* Handlers */

  @override
  void writeChar(int char) {
    _captureITerm2ClipboardText(String.fromCharCode(char));
    if (unicodeV11.wcwidth(char) > 0) {
      _precedingCodepoint = char;
    }
    _buffer.writeChar(char);
  }

  /* SBC */

  @override
  void enquiry() {
    final response = onEnquiry?.call();
    if (response == null || response.isEmpty) return;
    onOutput?.call(response);
  }

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
    _captureITerm2ClipboardText('\t');
    final rightLimit = _horizontalTabRightLimit();
    if (_buffer.cursorX >= rightLimit) return;

    _markHorizontalTabOrigin();

    final nextStop = _tabStops.find(_buffer.cursorX + 1, rightLimit + 1);

    if (nextStop != null) {
      _buffer.setCursorX(nextStop);
    } else {
      _buffer.setCursorX(rightLimit);
    }
  }

  void _markHorizontalTabOrigin() {
    final line = _buffer.currentLine;
    final column = _buffer.cursorX;
    if (line.getCodePoint(column) != 0) return;
    if (column > 0 && line.getWidth(column - 1) == 2) return;

    line.setCell(column, Ascii.HT, 1, _cursorStyle);
  }

  @override
  void lineFeed() {
    _captureITerm2ClipboardText('\n');
    _buffer.lineFeed();
  }

  @override
  void carriageReturn() {
    _captureITerm2ClipboardText('\r');
    _buffer.carriageReturn();
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
    _buffer.saveCursor(originMode: _originMode);
  }

  @override
  void saveCursorOrSetLeftRightMargins() {
    if (_leftRightMarginMode) {
      return setLeftRightMargins(0);
    }
    saveCursor();
  }

  @override
  void restoreCursor() {
    _originMode = _buffer.restoreCursor();
  }

  @override
  void index() {
    _buffer.index();
  }

  @override
  void nextLine() {
    _buffer.carriageReturn();
    _buffer.index();
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
    _protectionMode = _ProtectionMode.off;
    _insertMode = false;
    _sendReceiveMode = true;
    _keyboardActionMode = false;
    _lineFeedMode = false;
    _cursorKeysMode = false;
    _reverseDisplayMode = false;
    _originMode = false;
    _enableColumnMode = false;
    _slowScrollMode = false;
    _autoWrapMode = true;
    _autoRepeatMode = false;
    _reverseWrapMode = false;
    _reverseWrapExtendedMode = false;
    _mouseMode = MouseMode.none;
    _mouseReportMode = MouseReportMode.normal;
    _cursorBlinkMode = false;
    _cursorVisibleMode = true;
    _applicationCursorType = null;
    _appKeypadMode = false;
    _ignoreKeypadWithNumLockMode = true;
    _backarrowKeyMode = false;
    _reportFocusMode = false;
    _mouseShiftCaptureMode = false;
    _altBufferMouseScrollMode = false;
    _altEscPrefixMode = true;
    _altSendsEscapeMode = false;
    _bracketedPasteMode = false;
    _inBandSizeReportMode = false;
    _reportColorSchemeMode = false;
    _graphemeClusterMode = true;
    _leftRightMarginMode = false;
    _cursorLineHighlightMode = false;
    _kittyKeyboardMode = 0;
    _modifyOtherKeysMode = 0;
    _kittyKeyboardModeStack.clear();
    _title = null;
    _iconTitle = null;
    _clipboardCaptureSelector = null;
    _clipboardCaptureBuffer = null;
    _titleStack.clear();
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
    _protectionMode = _ProtectionMode.off;
    _insertMode = false;
    _sendReceiveMode = true;
    _keyboardActionMode = false;
    _lineFeedMode = false;
    _cursorKeysMode = false;
    _reverseDisplayMode = false;
    _originMode = false;
    _enableColumnMode = false;
    _slowScrollMode = false;
    _autoWrapMode = true;
    _autoRepeatMode = false;
    _reverseWrapMode = false;
    _reverseWrapExtendedMode = false;
    _mouseMode = MouseMode.none;
    _mouseReportMode = MouseReportMode.normal;
    _cursorBlinkMode = false;
    _cursorVisibleMode = true;
    _applicationCursorType = null;
    _appKeypadMode = false;
    _ignoreKeypadWithNumLockMode = true;
    _backarrowKeyMode = false;
    _reportFocusMode = false;
    _mouseShiftCaptureMode = false;
    _altBufferMouseScrollMode = false;
    _altEscPrefixMode = true;
    _altSendsEscapeMode = false;
    _bracketedPasteMode = false;
    _inBandSizeReportMode = false;
    _reportColorSchemeMode = false;
    _graphemeClusterMode = true;
    _leftRightMarginMode = false;
    _kittyKeyboardMode = 0;
    _modifyOtherKeysMode = 0;
    _kittyKeyboardModeStack.clear();
    _tabStops.reset();
    _buffer.charset.reset();
    _buffer.resetVerticalMargins();
    _buffer.resetHorizontalMargins();
  }

  @override
  void screenAlignmentTest() {
    _buffer.screenAlignmentTest();
  }

  @override
  void reverseIndex() {
    _buffer.reverseIndex();
  }

  @override
  void backIndex() {
    _buffer.backIndex();
  }

  @override
  void forwardIndex() {
    _buffer.forwardIndex();
  }

  @override
  void designateCharset(int charset, int name) {
    _buffer.charset.designate(charset, name);
  }

  @override
  void useCharset(int charset) {
    _buffer.charset.use(charset);
  }

  @override
  void singleShiftCharset(int charset) {
    _buffer.charset.singleShift(charset);
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
    _buffer.setCursor(_buffer.cursorX, y);
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
  void resetTabStops() {
    _tabStops.reset();
  }

  @override
  void moveForwardTabs(int count) {
    for (var i = 0; i < count; i++) {
      final rightLimit = _horizontalTabRightLimit();
      if (_buffer.cursorX >= rightLimit) {
        return;
      }

      final nextStop = _tabStops.find(_buffer.cursorX + 1, rightLimit + 1);
      if (nextStop == null) {
        _buffer.setCursorX(rightLimit);
        return;
      }
      _buffer.setCursorX(nextStop);
    }
  }

  @override
  void moveBackwardTabs(int count) {
    for (var i = 0; i < count; i++) {
      final leftLimit = _horizontalTabLeftLimit();
      if (_buffer.cursorX <= leftLimit) {
        return;
      }

      final previousStop = _tabStops.findPrevious(
        _buffer.cursorX - 1,
        leftLimit,
      );
      if (previousStop == null) {
        _buffer.setCursorX(leftLimit);
        return;
      }
      _buffer.setCursorX(previousStop);
    }
  }

  int _horizontalTabRightLimit() {
    return switch (_buffer.cursorX <= _buffer.marginRight) {
      true => _buffer.marginRight,
      false => _viewWidth - 1,
    };
  }

  int _horizontalTabLeftLimit() {
    return switch (_originMode) {
      true => _buffer.marginLeft,
      false => 0,
    };
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
  void sendPrivateDeviceStatusReport(List<int> params) {
    switch (params) {
      case [6]:
        onOutput?.call(
          '\x1b[?${_buffer.cursorY + 1};${_buffer.cursorX + 1};1R',
        );
      case [15]:
        onOutput?.call('\x1b[?13n');
      case [25]:
        onOutput?.call('\x1b[?23n');
      case [26]:
        onOutput?.call('\x1b[?27;1;0;1n');
      case [55]:
        onOutput?.call('\x1b[?53n');
      case [56]:
        onOutput?.call('\x1b[?57;0n');
      case [62]:
        onOutput?.call('\x1b[0*{');
      case [63, final id]:
        onOutput?.call('\x1bP$id!~0000\x1b\\');
      case [75]:
        onOutput?.call('\x1b[?70n');
      case [85]:
        onOutput?.call('\x1b[?83n');
      case _:
        return;
    }
  }

  @override
  void sendRectChecksum(
    int id,
    int page,
    int? top,
    int? left,
    int? bottom,
    int? right,
  ) {
    if (page != 1) return;
    final checksum = _rectChecksum(
      top ?? 1,
      left ?? 1,
      bottom ?? viewHeight,
      right ?? viewWidth,
    );
    final checksumText = checksum.toRadixString(16).padLeft(4, '0');
    onOutput?.call('\x1bP$id!~${checksumText.toUpperCase()}\x1b\\');
  }

  int _rectChecksum(int top, int left, int bottom, int right) {
    final topIndex = min(max(top, 1), viewHeight) - 1;
    final leftIndex = min(max(left, 1), viewWidth) - 1;
    final bottomIndex = min(max(bottom, 1), viewHeight) - 1;
    final rightIndex = min(max(right, 1), viewWidth) - 1;
    if (topIndex > bottomIndex || leftIndex > rightIndex) return 0;

    var sum = 0;
    for (var row = topIndex; row <= bottomIndex; row++) {
      final line = _buffer.lines[_buffer.scrollBack + row];
      for (var col = leftIndex; col <= rightIndex; col++) {
        sum += _cellChecksum(line, col);
      }
    }
    return (-sum) & 0xffff;
  }

  int _cellChecksum(BufferLine line, int col) {
    if (col > 0 && line.getWidth(col - 1) == 2) return 0;

    final codePoint = switch (line.getCodePoint(col)) {
      0 => 0x20,
      final value => value,
    };
    if (codePoint < 0x20) return 0;

    return codePoint +
        _checksumColor(line.getForeground(col), foreground: true) +
        _checksumColor(line.getBackground(col), foreground: false) +
        _checksumAttributes(line.getAttributes(col));
  }

  int _checksumColor(int color, {required bool foreground}) {
    final type = color & CellColor.typeMask;
    final value = switch (type) {
      CellColor.normal => _assignedChecksumColor(foreground: foreground),
      CellColor.named || CellColor.palette => color & CellColor.valueMask,
      _ => null,
    };
    if (value == null) return 0;
    if (value < 0 || value > 15) return 0;
    return switch (foreground) {
      true => value << 4,
      false => value,
    };
  }

  int? _assignedChecksumColor({required bool foreground}) {
    final color = _assignedColors[1];
    if (color == null) return null;
    return switch (foreground) {
      true => color.foreground,
      false => color.background,
    };
  }

  int _checksumAttributes(int attrs) {
    var value = 0;
    if (attrs & CellAttr.protected != 0) value |= 0x04;
    if (attrs & CellAttr.invisible != 0) value |= 0x08;
    if (attrs & CellAttr.underline != 0) value |= 0x10;
    if (attrs & CellAttr.inverse != 0) value |= 0x20;
    if (attrs & CellAttr.blink != 0) value |= 0x40;
    if (attrs & CellAttr.bold != 0) value |= 0x80;
    return value;
  }

  @override
  void sendColorScheme() {
    final colorScheme = onColorSchemeQuery?.call();
    if (colorScheme == null) return;
    onOutput?.call(_emitter.colorScheme(colorScheme));
  }

  void reportColorSchemeChange() {
    if (!_reportColorSchemeMode) return;
    sendColorScheme();
  }

  @override
  void sendXtVersion() {
    onOutput?.call(_emitter.xtVersion(onXtVersionQuery?.call()));
  }

  @override
  void sendStatusString(String query) {
    onOutput?.call(_emitter.statusString(_statusString(query)));
  }

  @override
  void sendTerminfoCapability(String query) {
    final key = _hexDecode(query);
    if (key == null) return;
    final value = _terminfoCapability(key);
    if (value == null) return;
    onOutput?.call(_emitter.terminfoCapability(key, value));
  }

  String? _hexDecode(String value) {
    if (value.length.isOdd) return null;
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i += 2) {
      final byte = int.tryParse(value.substring(i, i + 2), radix: 16);
      if (byte == null) return null;
      buffer.writeCharCode(byte);
    }
    return buffer.toString();
  }

  String? _terminfoCapability(String key) {
    final modifiedFunctionKey = _modifiedFunctionKeyCapability(key);
    if (modifiedFunctionKey != null) return modifiedFunctionKey;

    return switch (key) {
      'TN' => 'xterm-256color',
      'Co' => '256',
      'RGB' => '8',
      'colors' => '256',
      'cols' => viewWidth.toString(),
      'lines' => viewHeight.toString(),
      'Sync' => '\x1b[?2026%?%p1%{1}%-%tl%eh%;',
      'BD' => '\x1b[?2004l',
      'BE' => '\x1b[?2004h',
      'PS' => '\x1b[200~',
      'PE' => '\x1b[201~',
      'XM' => '\x1b[?1006;1000%?%p1%{1}%=%th%el%;',
      'xm' => '\x1b[<%i%p3%d;%p1%d;%p2%d;%?%p4%tM%em%;',
      'RV' => '\x1b[>c',
      'rv' => '\x1b\\[[0-9]+;[0-9]+;[0-9]+c',
      'XR' => '\x1b[>0q',
      'xr' => '\x1bP>\\|[ -~]+a\x1b\\',
      'Enmg' => '\x1b[?69h',
      'Dsmg' => '\x1b[?69l',
      'Clmg' => '\x1b[s',
      'Cmg' => '\x1b[%i%p1%d;%p2%ds',
      'Ms' => '\x1b]52;%p1%s;%p2%s\x07',
      'Ss' => '\x1b[%p1%d q',
      'Se' => '\x1b[0 q',
      'Smulx' => '\x1b[4:%p1%dm',
      'Setulc' =>
        '\x1b[58:2::%p1%{65536}%/%d:%p1%{256}%/%{255}%&%d:%p1%{255}%&%d%;m',
      'sitm' => '\x1b[3m',
      'ritm' => '\x1b[23m',
      'smxx' => '\x1b[9m',
      'rmxx' => '\x1b[29m',
      'clear' => '\x1b[H\x1b[2J',
      'E3' => '\x1b[3J',
      'fe' => '\x1b[?1004h',
      'fd' => '\x1b[?1004l',
      'kxIN' => '\x1b[I',
      'kxOUT' => '\x1b[O',
      'bel' => '\x07',
      'blink' => '\x1b[5m',
      'bold' => '\x1b[1m',
      'dim' => '\x1b[2m',
      'invis' => '\x1b[8m',
      'rev' => '\x1b[7m',
      'smul' => '\x1b[4m',
      'rmul' => '\x1b[24m',
      'smso' => '\x1b[7m',
      'rmso' => '\x1b[27m',
      'sgr0' => '\x1b(B\x1b[m',
      'op' => '\x1b[39;49m',
      'setaf' =>
        '\x1b[%?%p1%{8}%<%t3%p1%d%e%p1%{16}%<%t9%p1%{8}%-%d%e38;5;%p1%d%;m',
      'setab' =>
        '\x1b[%?%p1%{8}%<%t4%p1%d%e%p1%{16}%<%t10%p1%{8}%-%d%e48;5;%p1%d%;m',
      'setrgbf' => '\x1b[38:2:%p1%d:%p2%d:%p3%dm',
      'setrgbb' => '\x1b[48:2:%p1%d:%p2%d:%p3%dm',
      'cup' => '\x1b[%i%p1%d;%p2%dH',
      'hpa' => '\x1b[%i%p1%dG',
      'vpa' => '\x1b[%i%p1%dd',
      'cuu' => '\x1b[%p1%dA',
      'cuu1' => '\x1b[A',
      'cud' => '\x1b[%p1%dB',
      'cud1' => '\n',
      'cuf' => '\x1b[%p1%dC',
      'cuf1' => '\x1b[C',
      'cub' => '\x1b[%p1%dD',
      'cub1' => '\b',
      'ed' => '\x1b[J',
      'el' => '\x1b[K',
      'el1' => '\x1b[1K',
      'ech' => '\x1b[%p1%dX',
      'ich' => '\x1b[%p1%d@',
      'ich1' => '\x1b[@',
      'dch' => '\x1b[%p1%dP',
      'dch1' => '\x1b[P',
      'il' => '\x1b[%p1%dL',
      'il1' => '\x1b[L',
      'dl' => '\x1b[%p1%dM',
      'dl1' => '\x1b[M',
      'indn' => '\x1b[%p1%dS',
      'rin' => '\x1b[%p1%dT',
      'csr' => '\x1b[%i%p1%d;%p2%dr',
      'tbc' => '\x1b[3g',
      'hts' => '\x1bH',
      'rep' => '%p1%c\x1b[%p2%{1}%-%db',
      'smcup' => '\x1b[?1049h',
      'rmcup' => '\x1b[?1049l',
      'kbs' => '\x7f',
      'kcbt' => '\x1b[Z',
      'kent' => '\x1bOM',
      'khome' => '\x1b[H',
      'kend' => '\x1b[F',
      'kich1' => '\x1b[2~',
      'kdch1' => '\x1b[3~',
      'kpp' => '\x1b[5~',
      'knp' => '\x1b[6~',
      'kcuu1' => '\x1b[A',
      'kcud1' => '\x1b[B',
      'kcuf1' => '\x1b[C',
      'kcub1' => '\x1b[D',
      'kf1' => '\x1bOP',
      'kf2' => '\x1bOQ',
      'kf3' => '\x1bOR',
      'kf4' => '\x1bOS',
      'kf5' => '\x1b[15~',
      'kf6' => '\x1b[17~',
      'kf7' => '\x1b[18~',
      'kf8' => '\x1b[19~',
      'kf9' => '\x1b[20~',
      'kf10' => '\x1b[21~',
      'kf11' => '\x1b[23~',
      'kf12' => '\x1b[24~',
      'u6' => '\x1b[%i%d;%dR',
      'u7' => '\x1b[6n',
      'u8' => '\x1b[?%[;0123456789]c',
      'u9' => '\x1b[c',
      'kUP' || 'kri' => '\x1b[1;2A',
      'kUP3' => '\x1b[1;3A',
      'kUP4' => '\x1b[1;4A',
      'kUP5' => '\x1b[1;5A',
      'kUP6' => '\x1b[1;6A',
      'kUP7' => '\x1b[1;7A',
      'kDN' || 'kind' => '\x1b[1;2B',
      'kDN3' => '\x1b[1;3B',
      'kDN4' => '\x1b[1;4B',
      'kDN5' => '\x1b[1;5B',
      'kDN6' => '\x1b[1;6B',
      'kDN7' => '\x1b[1;7B',
      'kRIT' => '\x1b[1;2C',
      'kRIT3' => '\x1b[1;3C',
      'kRIT4' => '\x1b[1;4C',
      'kRIT5' => '\x1b[1;5C',
      'kRIT6' => '\x1b[1;6C',
      'kRIT7' => '\x1b[1;7C',
      'kLFT' => '\x1b[1;2D',
      'kLFT3' => '\x1b[1;3D',
      'kLFT4' => '\x1b[1;4D',
      'kLFT5' => '\x1b[1;5D',
      'kLFT6' => '\x1b[1;6D',
      'kLFT7' => '\x1b[1;7D',
      'kHOM' => '\x1b[1;2H',
      'kHOM3' => '\x1b[1;3H',
      'kHOM4' => '\x1b[1;4H',
      'kHOM5' => '\x1b[1;5H',
      'kHOM6' => '\x1b[1;6H',
      'kHOM7' => '\x1b[1;7H',
      'kEND' => '\x1b[1;2F',
      'kEND3' => '\x1b[1;3F',
      'kEND4' => '\x1b[1;4F',
      'kEND5' => '\x1b[1;5F',
      'kEND6' => '\x1b[1;6F',
      'kEND7' => '\x1b[1;7F',
      'kIC' => '\x1b[2;2~',
      'kIC3' => '\x1b[2;3~',
      'kIC4' => '\x1b[2;4~',
      'kIC5' => '\x1b[2;5~',
      'kIC6' => '\x1b[2;6~',
      'kIC7' => '\x1b[2;7~',
      'kDC' => '\x1b[3;2~',
      'kDC3' => '\x1b[3;3~',
      'kDC4' => '\x1b[3;4~',
      'kDC5' => '\x1b[3;5~',
      'kDC6' => '\x1b[3;6~',
      'kDC7' => '\x1b[3;7~',
      'kPRV' => '\x1b[5;2~',
      'kPRV3' => '\x1b[5;3~',
      'kPRV4' => '\x1b[5;4~',
      'kPRV5' => '\x1b[5;5~',
      'kPRV6' => '\x1b[5;6~',
      'kPRV7' => '\x1b[5;7~',
      'kNXT' => '\x1b[6;2~',
      'kNXT3' => '\x1b[6;3~',
      'kNXT4' => '\x1b[6;4~',
      'kNXT5' => '\x1b[6;5~',
      'kNXT6' => '\x1b[6;6~',
      'kNXT7' => '\x1b[6;7~',
      _ => null,
    };
  }

  String? _modifiedFunctionKeyCapability(String key) {
    if (!key.startsWith('kf')) return null;

    final number = int.tryParse(key.substring(2));
    if (number == null) return null;
    if (number < 13 || number > 63) return null;

    final group = switch (number) {
      >= 13 && <= 24 => (offset: number - 13, modifier: 2),
      >= 25 && <= 36 => (offset: number - 25, modifier: 5),
      >= 37 && <= 48 => (offset: number - 37, modifier: 6),
      >= 49 && <= 60 => (offset: number - 49, modifier: 3),
      >= 61 && <= 63 => (offset: number - 61, modifier: 4),
      _ => null,
    };
    if (group == null) return null;

    if (group.offset < 4) {
      final finalByte = switch (group.offset) {
        0 => 'P',
        1 => 'Q',
        2 => 'R',
        3 => 'S',
        _ => null,
      };
      if (finalByte == null) return null;
      return '\x1b[1;${group.modifier}$finalByte';
    }

    final base = switch (group.offset) {
      4 => 15,
      5 => 17,
      6 => 18,
      7 => 19,
      8 => 20,
      9 => 21,
      10 => 23,
      11 => 24,
      _ => null,
    };
    if (base == null) return null;
    return '\x1b[$base;${group.modifier}~';
  }

  String? _statusString(String query) {
    final titleModeStatus = _titleModeStatusString(query);
    if (titleModeStatus != null) return titleModeStatus;

    final colorStatus = _attributeColorStatusString(query);
    if (colorStatus != null) return colorStatus;

    return switch (query) {
      'm' => _sgrStatusString(),
      '>4m' => '>4;$_modifyOtherKeysMode' 'm',
      '|' => '$_transmitTerminationCharacter|',
      "'s" => "$_lineTransmitTerminationCharacter's",
      '}' => '$_protectedFieldsAttribute}',
      '"p' => '$_conformanceLevel;$_conformanceControls"p',
      '"q' => '${switch (_cursorStyle.isProtected) {
          true => 1,
          false => 0,
        }}"q',
      r'$|' => '$_viewWidth\$|',
      r'$}' => '$_activeStatusDisplay\$}',
      '*x' => '${switch (_attributeChangeExtentRectangular) {
          true => 2,
          false => 0,
        }}*x',
      '*|' => '$_viewHeight*|',
      r'$~' => '$_statusLineType\$~',
      ' q' => '${_cursorShapeStatus()} q',
      ' r' => '$_keyClickVolume r',
      ' u' => '$_marginBellVolume u',
      ' v' => '$_lockKeyStyle v',
      ' t' => '$_warningBellVolume t',
      ' ~' => '$_terminalModeEmulation ~',
      'r' => '${_buffer.marginTop + 1};${_buffer.marginBottom + 1}r',
      's' => _leftRightMarginStatusString(),
      't' => '${_viewHeight}t',
      '+q' ||
      '*}' ||
      '+r' ||
      '-q' ||
      ',z' ||
      '-r' ||
      '*u' ||
      '*r' ||
      ')p' ||
      r'$q' ||
      '*s' ||
      r'$s' ||
      '"t' ||
      '*p' ||
      'p' ||
      ',x' ||
      '+w' ||
      ' p' ||
      '"u' ||
      '-p' ||
      '){' ||
      ',{' ||
      ',y' =>
        '0$query',
      _ => null,
    };
  }

  String? _attributeColorStatusString(String query) {
    if (query.endsWith(',}')) {
      final attribute = int.tryParse(query.substring(0, query.length - 2));
      if (attribute == null || attribute < 0 || attribute > 15) return null;
      final color = _alternateTextColors[attribute];
      return '$attribute;${color?.foreground ?? 0};${color?.background ?? 0},}';
    }

    if (query.endsWith(',|')) {
      final attribute = int.tryParse(query.substring(0, query.length - 2));
      if (attribute == null || attribute < 1 || attribute > 2) return null;
      final color = _assignedColors[attribute];
      return '$attribute;${color?.foreground ?? 0};${color?.background ?? 0},|';
    }

    return null;
  }

  String? _titleModeStatusString(String query) {
    if (!query.startsWith('>') || !query.endsWith('t')) return null;
    final mode = int.tryParse(query.substring(1, query.length - 1));
    if (mode == null || mode < 0 || mode > 3) return null;
    final enabled = switch (_titleModes.contains(mode)) {
      true => 1,
      false => 0,
    };
    return '>$mode;${enabled}t';
  }

  String? _leftRightMarginStatusString() {
    if (!_leftRightMarginMode) return null;
    return '${_buffer.marginLeft + 1};${_buffer.marginRight + 1}s';
  }

  String _sgrStatusString() {
    final attributes = <int>[0];
    if (_cursorStyle.isBold) attributes.add(1);
    if (_cursorStyle.isFaint) attributes.add(2);
    if (_cursorStyle.isItalis) attributes.add(3);
    if (_cursorStyle.isUnderline) attributes.add(4);
    if (_cursorStyle.isBlink) attributes.add(5);
    if (_cursorStyle.isInverse) attributes.add(7);
    if (_cursorStyle.isInvisible) attributes.add(8);
    if (_cursorStyle.attrs & CellAttr.strikethrough != 0) attributes.add(9);
    if (_cursorStyle.isDoubleUnderline) attributes.add(21);
    if (_cursorStyle.isOverline) attributes.add(53);
    _appendSgrColor(attributes, _cursorStyle.foreground, 30, 90, 38);
    _appendSgrColor(attributes, _cursorStyle.background, 40, 100, 48);
    _appendSgrColor(attributes, _cursorStyle.underlineColor, 0, 0, 58);
    return '${attributes.join(';')}m';
  }

  void _appendSgrColor(
    List<int> attributes,
    int color,
    int namedBase,
    int brightBase,
    int extendedPrefix,
  ) {
    final type = color & CellColor.typeMask;
    final value = color & CellColor.valueMask;
    switch (type) {
      case CellColor.named:
        if (extendedPrefix == 58) {
          attributes.addAll([58, 5, value]);
          return;
        }
        if (value < 8) {
          attributes.add(namedBase + value);
          return;
        }
        attributes.add(brightBase + value - 8);
        return;
      case CellColor.palette:
        attributes.addAll([extendedPrefix, 5, value]);
        return;
      case CellColor.rgb:
        attributes.addAll([
          extendedPrefix,
          2,
          (value >> 16) & 0xFF,
          (value >> 8) & 0xFF,
          value & 0xFF,
        ]);
    }
  }

  int _cursorShapeStatus() {
    return switch ((_applicationCursorType, _cursorBlinkMode)) {
      (TerminalCursorType.block || null, true) => 1,
      (TerminalCursorType.block || null, false) => 2,
      (TerminalCursorType.underline, true) => 3,
      (TerminalCursorType.underline, false) => 4,
      (TerminalCursorType.verticalBar, true) => 5,
      (TerminalCursorType.verticalBar, false) => 6,
    };
  }

  @override
  void setMargins(int top, [int? bottom]) {
    final effectiveBottom = bottom ?? viewHeight - 1;
    if (top >= effectiveBottom) return;
    _buffer.setVerticalMargins(top, effectiveBottom);
    _buffer.setCursor(0, 0);
  }

  @override
  void setLeftRightMargins(int left, [int? right]) {
    if (!_leftRightMarginMode) return;

    final effectiveRight = right ?? viewWidth - 1;
    if (left >= effectiveRight) return;

    _buffer.setHorizontalMargins(left, effectiveRight);
    _buffer.setCursor(0, 0);
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
    _buffer.eraseDisplayFromCursor(respectProtected: _usesIsoProtection);
  }

  @override
  void eraseDisplayBelowSelective() {
    _buffer.eraseDisplayFromCursor(respectProtected: true);
  }

  @override
  void eraseDisplayAbove() {
    _buffer.eraseDisplayToCursor(respectProtected: _usesIsoProtection);
  }

  @override
  void eraseDisplayAboveSelective() {
    _buffer.eraseDisplayToCursor(respectProtected: true);
  }

  @override
  void eraseDisplay() {
    _buffer.eraseDisplay(respectProtected: _usesIsoProtection);
  }

  @override
  void eraseDisplaySelective() {
    _buffer.eraseDisplay(respectProtected: true);
  }

  @override
  void eraseScrollbackOnly() {
    _buffer.clearScrollback();
  }

  @override
  void eraseDisplayScrollComplete() {
    _buffer.scrollClear();
    _buffer.setCursor(0, 0);
  }

  @override
  void eraseLineRight() {
    _buffer.eraseLineFromCursor(respectProtected: _usesIsoProtection);
  }

  @override
  void eraseLineRightSelective() {
    _buffer.eraseLineFromCursor(respectProtected: true);
  }

  @override
  void eraseLineLeft() {
    _buffer.eraseLineToCursor(respectProtected: _usesIsoProtection);
  }

  @override
  void eraseLineLeftSelective() {
    _buffer.eraseLineToCursor(respectProtected: true);
  }

  @override
  void eraseLine() {
    _buffer.eraseLine(respectProtected: _usesIsoProtection);
  }

  @override
  void eraseLineSelective() {
    _buffer.eraseLine(respectProtected: true);
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
  void insertColumns(int amount) {
    _buffer.insertColumns(amount);
  }

  @override
  void deleteColumns(int amount) {
    _buffer.deleteColumns(amount);
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
    _buffer.eraseChars(amount, respectProtected: _usesIsoProtection);
  }

  @override
  void eraseRect(int top, int left, int bottom, int right) {
    _buffer.eraseRect(
      top,
      left,
      bottom,
      right,
      respectProtected: _usesIsoProtection,
    );
  }

  @override
  void fillRect(int char, int top, int left, int bottom, int right) {
    _buffer.fillRect(char, top, left, bottom, right);
  }

  @override
  void changeRectAttributes(
    int top,
    int left,
    int bottom,
    int right,
    int attribute,
  ) {
    _buffer.changeRectAttributes(
      top,
      left,
      bottom,
      right,
      attribute,
      rectangular: _attributeChangeExtentRectangular,
    );
  }

  @override
  void reverseRectAttributes(
    int top,
    int left,
    int bottom,
    int right,
    int attribute,
  ) {
    _buffer.reverseRectAttributes(
      top,
      left,
      bottom,
      right,
      attribute,
      rectangular: _attributeChangeExtentRectangular,
    );
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
    _buffer.copyRect(
      sourceTop,
      sourceLeft,
      sourceBottom,
      sourceRight,
      sourcePage,
      destinationTop,
      destinationLeft,
      destinationPage,
    );
  }

  @override
  void selectiveEraseRect(int top, int left, int bottom, int right) {
    _buffer.eraseRect(top, left, bottom, right, respectProtected: true);
  }

  @override
  void setAttributeChangeExtent(bool rectangular) {
    _attributeChangeExtentRectangular = rectangular;
  }

  @override
  void setKeyClickVolume(int volume) {
    _keyClickVolume = volume.clamp(0, 8);
  }

  @override
  void setMarginBellVolume(int volume) {
    _marginBellVolume = volume.clamp(0, 8);
  }

  @override
  void setWarningBellVolume(int volume) {
    _warningBellVolume = volume.clamp(0, 8);
  }

  @override
  void setLockKeyStyle(int style) {
    _lockKeyStyle = style;
  }

  @override
  void setTerminalModeEmulation(int mode) {
    _terminalModeEmulation = mode;
  }

  @override
  void setActiveStatusDisplay(int display) {
    _activeStatusDisplay = display.clamp(0, 1);
  }

  @override
  void setStatusLineType(int type) {
    _statusLineType = type.clamp(0, 2);
  }

  @override
  void setProtectedFieldsAttribute(int attribute) {
    _protectedFieldsAttribute = attribute;
  }

  @override
  void setTransmitTerminationCharacter(int character) {
    _transmitTerminationCharacter = character;
  }

  @override
  void setLineTransmitTerminationCharacter(int character) {
    _lineTransmitTerminationCharacter = character;
  }

  @override
  void setTitleMode(int mode, bool enabled) {
    if (mode < 0 || mode > 3) return;
    if (enabled) {
      _titleModes.add(mode);
      return;
    }
    _titleModes.remove(mode);
  }

  @override
  void setAssignedColor(int selector, int foreground, int background) {
    if (selector < 1 || selector > 2) return;
    if (!_isDecColor(foreground) || !_isDecColor(background)) return;

    final previous = _assignedColors[selector];
    _assignedColors[selector] = (
      foreground: foreground,
      background: background,
    );

    if (selector != 1) return;
    if (_matchesAssignedColor(_cursorStyle.foreground, previous?.foreground)) {
      _cursorStyle.foreground = _namedColor(foreground);
    }
    if (_matchesAssignedColor(_cursorStyle.background, previous?.background)) {
      _cursorStyle.background = _namedColor(background);
    }
  }

  @override
  void setAlternateTextColor(int attribute, int foreground, int background) {
    if (attribute < 0 || attribute > 15) return;
    if (!_isDecColor(foreground) || !_isDecColor(background)) return;

    _alternateTextColors[attribute] = (
      foreground: foreground,
      background: background,
    );
  }

  bool _isDecColor(int color) {
    return color >= 0 && color < 16;
  }

  bool _matchesAssignedColor(int current, int? assigned) {
    if ((current & CellColor.typeMask) == CellColor.normal) return true;
    if (assigned == null) return false;
    return current == _namedColor(assigned);
  }

  int _namedColor(int color) {
    return color | CellColor.named;
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
  void sendPixelSize() {
    final pixelWidth = viewWidth * _cellPixelWidth;
    final pixelHeight = viewHeight * _cellPixelHeight;
    onOutput?.call('\x1b[4;$pixelHeight;${pixelWidth}t');
  }

  @override
  void sendCellSize() {
    onOutput?.call('\x1b[6;$_cellPixelHeight;${_cellPixelWidth}t');
  }

  @override
  void sendWindowReport() {
    onOutput?.call('\x1b[$viewHeight;$viewWidth;1;1;1"w');
  }

  @override
  void sendTerminalStateReport(int request) {
    if (request != 1) return;
    onOutput?.call('\x1bP1\$s\x1b\\');
  }

  @override
  void assignUserPreferredSupplementalSet(int size, String charsetFinal) {
    if (size != 94 && size != 96) return;
    if (charsetFinal.isEmpty) return;
    if (charsetFinal.length > 2) return;

    _preferredSupplementalSetSize = size;
    _preferredSupplementalSetFinal = charsetFinal;
  }

  @override
  void sendUserPreferredSupplementalSet() {
    final size = switch (_preferredSupplementalSetSize) {
      96 => 1,
      _ => 0,
    };
    onOutput?.call('\x1bP$size!u$_preferredSupplementalSetFinal\x1b\\');
  }

  @override
  void sendPresentationStateReport(int request) {
    switch (request) {
      case 1:
        return _sendCursorInformationReport();
      case 2:
        return _sendTabStopReport();
    }
  }

  void _sendCursorInformationReport() {
    final row = _buffer.cursorY + 1;
    final column = _buffer.cursorX + 1;
    final rendition = _presentationRendition();
    final attributes = switch (_cursorStyle.isProtected) {
      true => 'A',
      false => '@',
    };
    final flags = switch (_originMode) {
      true => 'A',
      false => '@',
    };
    onOutput?.call(
      '\x1bP1\$u$row;$column;1;$rendition;$attributes;$flags;0;1;@BBBB\x1b\\',
    );
  }

  String _presentationRendition() {
    var rendition = 0x40;
    if (_cursorStyle.isInverse) rendition |= 0x08;
    if (_cursorStyle.isBlink) rendition |= 0x04;
    if (_cursorStyle.isUnderline) rendition |= 0x02;
    if (_cursorStyle.isBold) rendition |= 0x01;
    return String.fromCharCode(rendition);
  }

  void _sendTabStopReport() {
    final stops = <String>[];
    for (var column = 1; column < viewWidth; column++) {
      if (!_tabStops.isSetAt(column)) continue;
      stops.add('${column + 1}');
    }
    onOutput?.call('\x1bP2\$u${stops.join('/')}\x1b\\');
  }

  void _sendInBandSizeReport() {
    final pixelWidth = viewWidth * _cellPixelWidth;
    final pixelHeight = viewHeight * _cellPixelHeight;
    onOutput?.call('\x1b[48;$viewHeight;$viewWidth;$pixelHeight;$pixelWidth'
        't');
  }

  @override
  void unknownCSI(int finalByte) {
    // no-op
  }

  @override
  void setCursorShape(int style) {
    if (style == 0) {
      _applicationCursorType = null;
      _cursorBlinkMode = false;
      return;
    }

    _applicationCursorType = switch (style) {
      1 || 2 => TerminalCursorType.block,
      3 || 4 => TerminalCursorType.underline,
      5 || 6 => TerminalCursorType.verticalBar,
      _ => _applicationCursorType,
    };
    if (style < 1 || style > 6) return;
    _cursorBlinkMode = style.isOdd;
  }

  @override
  void setProtectedMode(bool enabled) {
    if (enabled) {
      _protectionMode = _ProtectionMode.dec;
      return _cursorStyle.setProtected();
    }
    _cursorStyle.unsetProtected();
  }

  @override
  void setIsoProtectedMode(bool enabled) {
    if (enabled) {
      _protectionMode = _ProtectionMode.iso;
      return _cursorStyle.setProtected();
    }
    _cursorStyle.unsetProtected();
  }

  bool get _usesIsoProtection => _protectionMode == _ProtectionMode.iso;

  /* Modes */

  @override
  void setInsertMode(bool enabled) {
    _insertMode = enabled;
  }

  @override
  void setSendReceiveMode(bool enabled) {
    _sendReceiveMode = enabled;
  }

  @override
  void setKeyboardActionMode(bool enabled) {
    _keyboardActionMode = enabled;
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
    _buffer.setCursor(0, 0);
  }

  @override
  void setColumnMode(bool enabled) {
    if (!_enableColumnMode) return;

    _buffer.resetViewport();
  }

  @override
  void setEnableColumnMode(bool enabled) {
    _enableColumnMode = enabled;
    if (!enabled) return;

    _buffer.resetViewport();
  }

  @override
  void setSlowScrollMode(bool enabled) {
    _slowScrollMode = enabled;
  }

  @override
  void setAutoWrapMode(bool enabled) {
    _autoWrapMode = enabled;
  }

  @override
  void setAutoRepeatMode(bool enabled) {
    _autoRepeatMode = enabled;
  }

  @override
  void setReverseWrapMode(bool enabled) {
    _reverseWrapMode = enabled;
  }

  @override
  void setReverseWrapExtendedMode(bool enabled) {
    _reverseWrapExtendedMode = enabled;
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
    _endScreenHyperlinkState();
    _buffer = _altBuffer;
  }

  @override
  void useMainBuffer() {
    _endScreenHyperlinkState();
    _buffer = _mainBuffer;
  }

  void _endScreenHyperlinkState() {
    _cursorStyle.hyperlinkId = 0;
    _mainBuffer.clearSavedCursorHyperlink();
    _altBuffer.clearSavedCursorHyperlink();
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
  void setIgnoreKeypadWithNumLockMode(bool enabled) {
    _ignoreKeypadWithNumLockMode = enabled;
  }

  @override
  void setBackarrowKeyMode(bool enabled) {
    _backarrowKeyMode = enabled;
  }

  @override
  void setReportFocusMode(bool enabled) {
    _reportFocusMode = enabled;
    if (!enabled) return;

    focusInput(_focused);
  }

  @override
  void setMouseShiftCaptureMode(bool enabled) {
    _mouseShiftCaptureMode = enabled;
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
  void setAltEscPrefixMode(bool enabled) {
    _altEscPrefixMode = enabled;
  }

  @override
  void setAltSendsEscapeMode(bool enabled) {
    _altSendsEscapeMode = enabled;
  }

  @override
  void setBracketedPasteMode(bool enabled) {
    _bracketedPasteMode = enabled;
  }

  @override
  void setInBandSizeReportMode(bool enabled) {
    _inBandSizeReportMode = enabled;
    if (!enabled) return;

    _sendInBandSizeReport();
  }

  @override
  void setReportColorSchemeMode(bool enabled) {
    _reportColorSchemeMode = enabled;
    if (!enabled) return;

    sendColorScheme();
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
  void setGraphemeClusterMode(bool enabled) {
    _graphemeClusterMode = enabled;
  }

  @override
  void reportMode(int mode, bool decPrivate) {
    final state = switch (decPrivate) {
      true => _decModeState(mode),
      false => _ansiModeState(mode),
    };
    final privateMarker = switch (decPrivate) {
      true => '?',
      false => '',
    };
    onOutput?.call('\x1b[$privateMarker$mode;$state\x24y');
  }

  int _ansiModeState(int mode) {
    return switch (mode) {
      2 => _reportedState(_keyboardActionMode),
      4 => _reportedState(_insertMode),
      12 => _reportedState(_sendReceiveMode),
      20 => _reportedState(_lineFeedMode),
      _ => 0,
    };
  }

  int _decModeState(int mode) {
    return switch (mode) {
      1 => _reportedState(_cursorKeysMode),
      3 => 0,
      4 => _reportedState(_slowScrollMode),
      5 => _reportedState(_reverseDisplayMode),
      6 => _reportedState(_originMode),
      7 => _reportedState(_autoWrapMode),
      8 => _reportedState(_autoRepeatMode),
      9 => _reportedState(_mouseMode == MouseMode.clickOnly),
      12 || 13 => _reportedState(_cursorBlinkMode),
      25 => _reportedState(_cursorVisibleMode),
      40 => _reportedState(_enableColumnMode),
      45 => _reportedState(_reverseWrapMode),
      47 || 1047 || 1049 => _reportedState(isUsingAltBuffer),
      1048 => _reportedState(false),
      66 => _reportedState(_appKeypadMode),
      67 => _reportedState(_backarrowKeyMode),
      69 => _reportedState(_leftRightMarginMode),
      1000 || 1001 => _reportedState(_mouseMode == MouseMode.upDownScroll),
      1002 => _reportedState(_mouseMode == MouseMode.upDownScrollDrag),
      1003 => _reportedState(_mouseMode == MouseMode.upDownScrollMove),
      1004 => _reportedState(_reportFocusMode),
      1005 => _reportedState(_mouseReportMode == MouseReportMode.utf),
      1006 => _reportedState(_mouseReportMode == MouseReportMode.sgr),
      1007 => _reportedState(_altBufferMouseScrollMode),
      1015 => _reportedState(_mouseReportMode == MouseReportMode.urxvt),
      1016 => _reportedState(_mouseReportMode == MouseReportMode.sgrPixels),
      1035 => _reportedState(_ignoreKeypadWithNumLockMode),
      1036 => _reportedState(_altEscPrefixMode),
      1039 => _reportedState(_altSendsEscapeMode),
      1045 => _reportedState(_reverseWrapExtendedMode),
      2004 => _reportedState(_bracketedPasteMode),
      2026 => _reportedState(_synchronizedUpdateMode),
      2027 => _reportedState(_graphemeClusterMode),
      2031 => _reportedState(_reportColorSchemeMode),
      2048 => _reportedState(_inBandSizeReportMode),
      _ => 0,
    };
  }

  int _reportedState(bool enabled) {
    return switch (enabled) {
      true => 1,
      false => 2,
    };
  }

  @override
  void saveDecMode(int mode) {
    final state = _decModeEnabled(mode);
    if (state == null) return;

    _savedDecModes[mode] = state;
  }

  @override
  void restoreDecMode(int mode) {
    final state = _savedDecModes[mode];
    if (state == null) return;

    _applyDecMode(mode, state);
  }

  bool? _decModeEnabled(int mode) {
    return switch (mode) {
      1 => _cursorKeysMode,
      4 => _slowScrollMode,
      5 => _reverseDisplayMode,
      6 => _originMode,
      7 => _autoWrapMode,
      8 => _autoRepeatMode,
      9 => _mouseMode == MouseMode.clickOnly,
      12 || 13 => _cursorBlinkMode,
      25 => _cursorVisibleMode,
      40 => _enableColumnMode,
      45 => _reverseWrapMode,
      47 || 1047 || 1049 => isUsingAltBuffer,
      66 => _appKeypadMode,
      67 => _backarrowKeyMode,
      69 => _leftRightMarginMode,
      1000 || 1001 => _mouseMode == MouseMode.upDownScroll,
      1002 => _mouseMode == MouseMode.upDownScrollDrag,
      1003 => _mouseMode == MouseMode.upDownScrollMove,
      1004 => _reportFocusMode,
      1005 => _mouseReportMode == MouseReportMode.utf,
      1006 => _mouseReportMode == MouseReportMode.sgr,
      1007 => _altBufferMouseScrollMode,
      1015 => _mouseReportMode == MouseReportMode.urxvt,
      1016 => _mouseReportMode == MouseReportMode.sgrPixels,
      1035 => _ignoreKeypadWithNumLockMode,
      1036 => _altEscPrefixMode,
      1039 => _altSendsEscapeMode,
      1045 => _reverseWrapExtendedMode,
      2004 => _bracketedPasteMode,
      2026 => _synchronizedUpdateMode,
      2027 => _graphemeClusterMode,
      2031 => _reportColorSchemeMode,
      2048 => _inBandSizeReportMode,
      _ => null,
    };
  }

  void _applyDecMode(int mode, bool enabled) {
    switch (mode) {
      case 1:
        return setCursorKeysMode(enabled);
      case 4:
        return setSlowScrollMode(enabled);
      case 5:
        return setReverseDisplayMode(enabled);
      case 6:
        return setOriginMode(enabled);
      case 7:
        return setAutoWrapMode(enabled);
      case 8:
        return setAutoRepeatMode(enabled);
      case 9:
        return setMouseMode(switch (enabled) {
          true => MouseMode.clickOnly,
          false => MouseMode.none,
        });
      case 12:
      case 13:
        return setCursorBlinkMode(enabled);
      case 25:
        return setCursorVisibleMode(enabled);
      case 40:
        return setEnableColumnMode(enabled);
      case 45:
        return setReverseWrapMode(enabled);
      case 47:
      case 1047:
      case 1049:
        if (enabled) {
          return useAltBuffer();
        }
        return useMainBuffer();
      case 66:
        return setAppKeypadMode(enabled);
      case 67:
        return setBackarrowKeyMode(enabled);
      case 69:
        return setLeftRightMarginMode(enabled);
      case 1000:
      case 1001:
        return setMouseMode(switch (enabled) {
          true => MouseMode.upDownScroll,
          false => MouseMode.none,
        });
      case 1002:
        return setMouseMode(switch (enabled) {
          true => MouseMode.upDownScrollDrag,
          false => MouseMode.none,
        });
      case 1003:
        return setMouseMode(switch (enabled) {
          true => MouseMode.upDownScrollMove,
          false => MouseMode.none,
        });
      case 1004:
        return setReportFocusMode(enabled);
      case 1005:
        return setMouseReportMode(switch (enabled) {
          true => MouseReportMode.utf,
          false => MouseReportMode.normal,
        });
      case 1006:
        return setMouseReportMode(switch (enabled) {
          true => MouseReportMode.sgr,
          false => MouseReportMode.normal,
        });
      case 1007:
        return setAltBufferMouseScrollMode(enabled);
      case 1015:
        return setMouseReportMode(switch (enabled) {
          true => MouseReportMode.urxvt,
          false => MouseReportMode.normal,
        });
      case 1016:
        return setMouseReportMode(switch (enabled) {
          true => MouseReportMode.sgrPixels,
          false => MouseReportMode.normal,
        });
      case 1035:
        return setIgnoreKeypadWithNumLockMode(enabled);
      case 1036:
        return setAltEscPrefixMode(enabled);
      case 1039:
        return setAltSendsEscapeMode(enabled);
      case 1045:
        return setReverseWrapExtendedMode(enabled);
      case 2004:
        return setBracketedPasteMode(enabled);
      case 2026:
        return setSynchronizedUpdateMode(enabled);
      case 2027:
        return setGraphemeClusterMode(enabled);
      case 2031:
        return setReportColorSchemeMode(enabled);
      case 2048:
        return setInBandSizeReportMode(enabled);
    }
  }

  @override
  void reportKittyKeyboardMode() {
    onOutput?.call('\x1b[?${_kittyKeyboardMode & _kittyKeyboardModeMask}u');
  }

  @override
  void setKittyKeyboardMode(int mode, int behavior) {
    final normalizedMode = mode & _kittyKeyboardModeMask;
    _kittyKeyboardMode = switch (behavior) {
      2 => _kittyKeyboardMode | normalizedMode,
      3 => _kittyKeyboardMode & ~normalizedMode,
      _ => normalizedMode,
    };
  }

  @override
  void pushKittyKeyboardMode(int mode) {
    if (_kittyKeyboardModeStack.length >= _maxKittyKeyboardModeStackDepth) {
      _kittyKeyboardModeStack.removeAt(0);
    }

    final normalizedMode = mode & _kittyKeyboardModeMask;
    _kittyKeyboardModeStack.add(normalizedMode);
    _kittyKeyboardMode = normalizedMode;
  }

  @override
  void popKittyKeyboardModes(int count) {
    if (count <= 0) return;

    final newLength = switch (count >= _kittyKeyboardModeStack.length) {
      true => 0,
      false => _kittyKeyboardModeStack.length - count,
    };
    _kittyKeyboardModeStack.length = newLength;
    _kittyKeyboardMode = switch (_kittyKeyboardModeStack.isEmpty) {
      true => 0,
      false => _kittyKeyboardModeStack.last,
    };
  }

  @override
  void setModifyOtherKeysMode(int resource, int mode) {
    if (resource != 4) return;
    _modifyOtherKeysMode = switch (mode) {
      2 => 2,
      _ => 0,
    };
  }

  @override
  void setUnknownDecMode(int mode, bool enabled) {
    // no-op
  }

  @override
  void setLeftRightMarginMode(bool enabled) {
    _leftRightMarginMode = enabled;
    if (enabled) return;

    _buffer.resetHorizontalMargins();
  }

  /* Select Graphic Rendition (SGR) */

  @override
  void resetCursorStyle() {
    _cursorStyle.reset();
    _resetAssignedTextColors();
  }

  void _resetAssignedTextColors() {
    final normalTextColor = _assignedColors[1];
    if (normalTextColor == null) return;
    _cursorStyle.foreground = _namedColor(normalTextColor.foreground);
    _cursorStyle.background = _namedColor(normalTextColor.background);
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
    final normalTextColor = _assignedColors[1];
    if (normalTextColor == null) {
      _cursorStyle.resetForegroundColor();
      return;
    }
    _cursorStyle.foreground = _namedColor(normalTextColor.foreground);
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
    final normalTextColor = _assignedColors[1];
    if (normalTextColor == null) {
      _cursorStyle.resetBackgroundColor();
      return;
    }
    _cursorStyle.background = _namedColor(normalTextColor.background);
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
    _title = name;
    onTitleChange?.call(name);
  }

  @override
  void setIconName(String name) {
    _iconTitle = name;
    onIconChange?.call(name);
  }

  @override
  void reportTitle() {
    onOutput?.call('\x1b]l${_title ?? ''}\x1b\\');
  }

  @override
  void pushTitle() {
    if (_titleStack.length >= _maxTitleStackDepth) {
      _titleStack.removeAt(0);
    }
    _titleStack.add(_title);
  }

  @override
  void popTitle() {
    if (_titleStack.isEmpty) return;
    final title = _titleStack.removeLast();
    _title = title;
    onTitleChange?.call(title ?? '');
  }

  @override
  void setCurrentDirectory(String uri) {
    onCurrentDirectoryChange?.call(uri);
  }

  @override
  void setRemoteHost(String value) {
    onRemoteHostChange?.call(value);
  }

  @override
  void reportITerm2CellSize() {
    onOutput?.call(
      '\x1b]1337;ReportCellSize=$_cellPixelHeight;$_cellPixelWidth\x1b\\',
    );
  }

  @override
  void reportITerm2Variable(String data) {
    String name;
    try {
      name = utf8.decode(base64.decode(data));
    } on FormatException {
      return;
    }

    if (name.isEmpty) return;

    final value = _resolveITerm2Variable(name);
    if (value == null) return;

    final encoded = base64.encode(utf8.encode(value));
    onOutput?.call('\x1b]1337;ReportVariable=$encoded\x1b\\');
  }

  String? _resolveITerm2Variable(String name) {
    if (onITerm2VariableQuery?.call(name) case final value?) {
      return value;
    }

    return switch (name) {
      'columns' => viewWidth.toString(),
      'rows' => viewHeight.toString(),
      'terminalIconName' => _iconTitle ?? '',
      'terminalWindowName' => _title ?? '',
      'autoName' || 'name' || 'presentationName' => _title ?? '',
      _ => null,
    };
  }

  @override
  void setITerm2BadgeFormat(String data) {
    if (data.isEmpty) {
      onITerm2BadgeFormatChange?.call('');
      return;
    }

    try {
      final value = utf8.decode(base64.decode(data));
      onITerm2BadgeFormatChange?.call(value);
    } on FormatException {
      return;
    }
  }

  @override
  void setITerm2ShellIntegrationVersion(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    onITerm2ShellIntegrationVersionChange?.call(trimmed);
  }

  @override
  void setITerm2Mark() {
    onITerm2Mark?.call();
  }

  @override
  void setITerm2Profile(String value) {
    onITerm2ProfileChange?.call(value);
  }

  @override
  void setUserVariable(String name, String data) {
    if (name.isEmpty || data.isEmpty) return;

    try {
      final value = utf8.decode(base64.decode(data));
      onUserVariableChange?.call(name, value);
    } on FormatException {
      return;
    }
  }

  @override
  void requestFocus() {
    onFocusRequest?.call();
  }

  @override
  void openUrl(String url) {
    onOpenUrl?.call(url);
  }

  @override
  void requestAttention(String value) {
    onAttentionRequest?.call(value);
  }

  @override
  void showNotification(String title, String body) {
    onNotification?.call(title, body);
  }

  @override
  void setMouseShape(String shape) {
    onMouseShapeChange?.call(shape);
  }

  @override
  void setCursorLineHighlight(bool enabled) {
    if (_cursorLineHighlightMode == enabled) return;
    _cursorLineHighlightMode = enabled;
  }

  @override
  void reportProgress(TerminalProgressReport report) {
    onProgressReport?.call(report);
  }

  @override
  void setHyperlink(String params, String uri) {
    String? explicitId;
    for (final param in params.split(':')) {
      if (!param.startsWith('id=')) continue;
      final id = param.substring(3);
      if (id.isNotEmpty) explicitId = id;
      break;
    }

    if (uri.isEmpty) {
      _cursorStyle.hyperlinkId = 0;
      return;
    }

    final key = explicitId == null ? null : '$explicitId\x00$uri';
    final existingId = key == null ? null : _explicitHyperlinkIds[key];
    if (existingId != null) {
      _cursorStyle.hyperlinkId = existingId;
      return;
    }
    if (_hyperlinks.length >= _maxHyperlinks) {
      _pruneUnusedHyperlinks();
      if (_hyperlinks.length >= _maxHyperlinks) {
        _cursorStyle.hyperlinkId = 0;
        return;
      }
    }

    final hyperlinkId = _allocateHyperlinkId();
    if (hyperlinkId == null) {
      _cursorStyle.hyperlinkId = 0;
      return;
    }

    _hyperlinks[hyperlinkId] = uri;
    if (key != null) _explicitHyperlinkIds[key] = hyperlinkId;
    _cursorStyle.hyperlinkId = hyperlinkId;
  }

  int? _allocateHyperlinkId() {
    for (var attempts = 0; attempts < _maxHyperlinkId; attempts++) {
      final hyperlinkId = _nextHyperlinkId;
      _nextHyperlinkId++;
      if (_nextHyperlinkId > _maxHyperlinkId) {
        _nextHyperlinkId = 1;
      }
      if (!_hyperlinks.containsKey(hyperlinkId)) {
        return hyperlinkId;
      }
    }
    return null;
  }

  void _pruneUnusedHyperlinks() {
    final usedIds = <int>{};
    if (_cursorStyle.hyperlinkId != 0) {
      usedIds.add(_cursorStyle.hyperlinkId);
    }

    void collectBuffer(Buffer buffer) {
      buffer.lines.forEach((line) {
        for (var column = 0; column < line.length; column++) {
          final hyperlinkId = line.getHyperlinkId(column);
          if (hyperlinkId != 0) usedIds.add(hyperlinkId);
        }
      });
    }

    collectBuffer(_mainBuffer);
    collectBuffer(_altBuffer);

    for (final hyperlinkId in _hyperlinks.keys.toList()) {
      if (!usedIds.contains(hyperlinkId)) {
        _hyperlinks.remove(hyperlinkId);
      }
    }

    for (final entry in _explicitHyperlinkIds.entries.toList()) {
      if (!_hyperlinks.containsKey(entry.value)) {
        _explicitHyperlinkIds.remove(entry.key);
      }
    }
  }

  @override
  void setIndexedColor(int index, String value) {
    final specialIndex = _specialColorIndexFromPaletteIndex(index);
    if (specialIndex != null) {
      setSpecialColor(specialIndex, value);
      return;
    }
    if (index < 0 || index > 255) return;
    final color = _parseOscColor(value);
    if (color == null || _indexedColorOverrides[index] == color) return;
    _indexedColorOverrides[index] = color;
    _colorRevision++;
  }

  @override
  void queryIndexedColor(int index) {
    final specialIndex = _specialColorIndexFromPaletteIndex(index);
    if (specialIndex != null) {
      _querySpecialColor(index, specialIndex, 4);
      return;
    }
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
      final specialIndex = _specialColorIndexFromPaletteIndex(index);
      if (specialIndex != null) {
        changed =
            _specialColorOverrides.remove(specialIndex) != null || changed;
        continue;
      }
      changed = _indexedColorOverrides.remove(index) != null || changed;
    }
    if (changed) _colorRevision++;
  }

  @override
  void setSpecialColor(int index, String value) {
    if (!_isSpecialColorIndex(index)) return;
    final color = _parseOscColor(value);
    if (color == null || _specialColorOverrides[index] == color) return;
    _specialColorOverrides[index] = color;
    _colorRevision++;
  }

  @override
  void querySpecialColor(int index) {
    _querySpecialColor(index, index, 5);
  }

  void _querySpecialColor(int reportIndex, int storageIndex, int code) {
    if (!_isSpecialColorIndex(storageIndex)) return;
    final color = _specialColorOverrides[storageIndex] ??
        onColorQuery?.call(5, storageIndex);
    if (color == null) return;
    onOutput?.call('\x1b]$code;$reportIndex;${_formatOscColor(color)}\x1b\\');
  }

  @override
  void resetSpecialColors(List<int> indices) {
    if (indices.isEmpty) {
      if (_specialColorOverrides.isEmpty) return;
      _specialColorOverrides.clear();
      _colorRevision++;
      return;
    }

    var changed = false;
    for (final index in indices) {
      if (!_isSpecialColorIndex(index)) continue;
      changed = _specialColorOverrides.remove(index) != null || changed;
    }
    if (changed) _colorRevision++;
  }

  int? _specialColorIndexFromPaletteIndex(int index) {
    final specialIndex = index - _specialColorBaseIndex;
    if (!_isSpecialColorIndex(specialIndex)) return null;
    return specialIndex;
  }

  bool _isSpecialColorIndex(int index) {
    return index >= 0 && index < _specialColorCount;
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
      case 13:
      case 14:
      case 15:
      case 16:
      case 18:
        if (_auxiliaryDynamicColorOverrides[code] == color) return;
        _auxiliaryDynamicColorOverrides[code] = color;
        break;
      case 17:
        if (_selectionColorOverride == color) return;
        _selectionColorOverride = color;
        break;
      case 19:
        if (_selectionForegroundColorOverride == color) return;
        _selectionForegroundColorOverride = color;
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
      17 => _selectionColorOverride,
      19 => _selectionForegroundColorOverride,
      _ => _auxiliaryDynamicColorOverrides[code],
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
      case 13:
      case 14:
      case 15:
      case 16:
      case 18:
        if (_auxiliaryDynamicColorOverrides.remove(code) == null) return;
        break;
      case 17:
        if (_selectionColorOverride == null) return;
        _selectionColorOverride = null;
        break;
      case 19:
        if (_selectionForegroundColorOverride == null) return;
        _selectionForegroundColorOverride = null;
        break;
      default:
        return;
    }
    _colorRevision++;
  }

  @override
  void startITerm2ClipboardCapture(String selector) {
    _clipboardCaptureSelector = _resolveITerm2ClipboardSelector(selector);
    _clipboardCaptureBuffer = StringBuffer();
  }

  @override
  void endITerm2ClipboardCapture() {
    final selector = _clipboardCaptureSelector;
    final buffer = _clipboardCaptureBuffer;
    _clipboardCaptureSelector = null;
    _clipboardCaptureBuffer = null;

    if (selector == null || buffer == null) return;
    onClipboardStore?.call(selector, buffer.toString());
  }

  void _captureITerm2ClipboardText(String text) {
    _clipboardCaptureBuffer?.write(text);
  }

  @override
  void storeClipboard(String selector, String data) {
    final clipboardSelector = _resolveClipboardSelector(selector);
    if (clipboardSelector == null) return;

    try {
      final bytes = base64.decode(data);
      final text = utf8.decode(bytes);
      onClipboardStore?.call(clipboardSelector, text);
    } on FormatException {
      return;
    }
  }

  @override
  void queryClipboard(String selector) {
    final clipboardSelector = _resolveClipboardSelector(selector);
    if (clipboardSelector == null) return;

    final callback = onClipboardQuery;
    if (callback == null) return;

    unawaited(Future<String?>.value(callback(clipboardSelector)).then((text) {
      if (_isDisposed) return;
      if (text == null) return;

      final encoded = base64.encode(utf8.encode(text));
      onOutput?.call('\x1b]52;$clipboardSelector;$encoded\x1b\\');
    }));
  }

  @override
  void unknownOSC(String ps, List<String> pt) {
    _handleSemanticPromptOsc(ps, pt);
    _handleVsCodeShellIntegrationOsc(ps, pt);
    _handleContextSignalOsc(ps, pt);
    onPrivateOSC?.call(ps, pt);
  }

  void _handleContextSignalOsc(String ps, List<String> pt) {
    if (ps != '3008' || pt.isEmpty) return;
    final action = pt.first;
    if (!action.startsWith('start=')) return;

    final contextId = action.substring(6);
    if (!_isValidContextSignalId(contextId)) return;

    final options = _parseSemanticPromptOptions(pt);
    final currentDirectory = options['cwd'];
    if (currentDirectory == null || currentDirectory.isEmpty) return;

    setCurrentDirectory(currentDirectory);
  }

  void _handleSemanticPromptOsc(String ps, List<String> pt) {
    if (ps != '133' || pt.isEmpty) return;
    final action = pt.first;
    if (action.isEmpty) return;
    final options = _parseSemanticPromptOptions(pt);

    final content = switch (action.codeUnitAt(0)) {
      0x41 || 0x4e || 0x50 => TerminalSemanticPromptContent.prompt,
      0x42 || 0x49 => TerminalSemanticPromptContent.input,
      0x43 || 0x44 => TerminalSemanticPromptContent.output,
      _ => null,
    };
    if (content == null) return;

    final exitCode = switch (action.codeUnitAt(0)) {
      0x44 => _parseSemanticPromptExitCode(pt),
      _ => _semanticPromptState.lastCommandExitCode,
    };
    final state = TerminalSemanticPromptState(
      content: content,
      lastCommandExitCode: exitCode,
      aid: options['aid'],
      promptKind: _parseSemanticPromptKind(options['k']),
      clickMode: _parseSemanticPromptClickMode(options),
      redraw: _parseSemanticPromptRedraw(options['redraw']),
      specialKey: _parseSemanticPromptBoolean(options['special_key']),
      commandLine: _parseSemanticPromptCommandLine(options),
    );
    _semanticPromptState = state;
    onSemanticPrompt?.call(state);
  }

  void _handleVsCodeShellIntegrationOsc(String ps, List<String> pt) {
    if (ps != '633' || pt.isEmpty) return;
    final action = pt.first;
    if (action.isEmpty) return;

    if (action == 'P') {
      final options = _parseSemanticPromptOptions(pt);
      final currentDirectory = options['Cwd'] ?? options['cwd'];
      if (currentDirectory != null && currentDirectory.isNotEmpty) {
        setCurrentDirectory(currentDirectory);
      }
      return;
    }

    final content = switch (action.codeUnitAt(0)) {
      0x41 => TerminalSemanticPromptContent.prompt,
      0x42 => TerminalSemanticPromptContent.input,
      0x43 || 0x44 => TerminalSemanticPromptContent.output,
      _ => null,
    };
    if (content == null) return;

    final exitCode = switch (action.codeUnitAt(0)) {
      0x44 => _parseSemanticPromptExitCode(pt),
      _ => _semanticPromptState.lastCommandExitCode,
    };
    final state = TerminalSemanticPromptState(
      content: content,
      lastCommandExitCode: exitCode,
    );
    _semanticPromptState = state;
    onSemanticPrompt?.call(state);
  }
}

bool _isValidContextSignalId(String value) {
  if (value.isEmpty || value.length > 64) return false;
  for (final codeUnit in value.codeUnits) {
    if (codeUnit < 0x20 || codeUnit > 0x7e) return false;
  }
  return true;
}

Map<String, String> _parseSemanticPromptOptions(List<String> pt) {
  final options = <String, String>{};
  for (var index = 1; index < pt.length; index++) {
    final part = pt[index];
    final separator = part.indexOf('=');
    if (separator <= 0) continue;
    final key = part.substring(0, separator);
    final value = part.substring(separator + 1);
    if (key.isEmpty) continue;
    options[key] = value;
  }
  return options;
}

int? _parseSemanticPromptExitCode(List<String> pt) {
  if (pt.length < 2) return null;
  return int.tryParse(pt[1]);
}

TerminalSemanticPromptKind? _parseSemanticPromptKind(String? value) {
  return switch (value) {
    'i' => TerminalSemanticPromptKind.initial,
    'r' => TerminalSemanticPromptKind.right,
    'c' => TerminalSemanticPromptKind.continuation,
    's' => TerminalSemanticPromptKind.secondary,
    _ => null,
  };
}

TerminalSemanticPromptClickMode? _parseSemanticPromptClickMode(
  Map<String, String> options,
) {
  final clickEvents = switch (options['click_events']) {
    '1' => TerminalSemanticPromptClickMode.eventsAbsolute,
    '2' => TerminalSemanticPromptClickMode.eventsRelative,
    _ => null,
  };
  if (clickEvents != null) return clickEvents;

  return switch (options['cl']) {
    'line' => TerminalSemanticPromptClickMode.line,
    'm' => TerminalSemanticPromptClickMode.multiple,
    _ => null,
  };
}

TerminalSemanticPromptRedraw? _parseSemanticPromptRedraw(String? value) {
  return switch (value) {
    '0' => TerminalSemanticPromptRedraw.disabled,
    '1' => TerminalSemanticPromptRedraw.enabled,
    'last' => TerminalSemanticPromptRedraw.last,
    _ => null,
  };
}

bool? _parseSemanticPromptBoolean(String? value) {
  return switch (value) {
    '0' => false,
    '1' => true,
    _ => null,
  };
}

String? _parseSemanticPromptCommandLine(Map<String, String> options) {
  final commandLine = options['cmdline'];
  if (commandLine != null) {
    return _decodeSemanticPromptPrintfQ(commandLine);
  }

  final commandLineUrl = options['cmdline_url'];
  if (commandLineUrl == null) return null;

  try {
    return Uri.decodeFull(commandLineUrl);
  } on FormatException {
    return null;
  }
}

String? _decodeSemanticPromptPrintfQ(String value) {
  final data = switch (value) {
    final text when text.startsWith(r"$'") => switch (text.endsWith("'")) {
        true => text.substring(2, text.length - 1),
        false => null,
      },
    final text when text.startsWith("'") => switch (text.endsWith("'")) {
        true => text.substring(1, text.length - 1),
        false => null,
      },
    _ => value,
  };
  if (data == null) return null;

  final result = StringBuffer();
  var index = 0;
  while (index < data.length) {
    final codeUnit = data.codeUnitAt(index);
    if (codeUnit != 0x5c) {
      result.writeCharCode(codeUnit);
      index++;
      continue;
    }

    if (index + 1 >= data.length) return null;
    final escaped = switch (data.codeUnitAt(index + 1)) {
      0x20 => 0x20,
      0x5c => 0x5c,
      0x22 => 0x22,
      0x27 => 0x27,
      0x24 => 0x24,
      0x65 => Ascii.ESC,
      0x6e => Ascii.LF,
      0x72 => Ascii.CR,
      0x74 => Ascii.HT,
      0x76 => Ascii.VT,
      _ => null,
    };
    if (escaped == null) return null;

    result.writeCharCode(escaped);
    index += 2;
  }
  return result.toString();
}

String? _resolveClipboardSelector(String selector) {
  if (selector.isEmpty) return 'c';

  for (final codeUnit in selector.codeUnits) {
    switch (codeUnit) {
      case 0x63:
        return 'c';
      case 0x70:
      case 0x73:
        return 's';
    }
  }
  return null;
}

String _resolveITerm2ClipboardSelector(String selector) {
  final name = selector.toLowerCase();
  return switch (name) {
    '' || 'rule' || 'find' || 'font' => 'c',
    'primary' || 'selection' => 's',
    _ => 'c',
  };
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
