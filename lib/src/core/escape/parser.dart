import 'package:xterm/src/core/color.dart';
import 'package:xterm/src/core/mouse/mode.dart';
import 'package:xterm/src/core/escape/handler.dart';
import 'package:xterm/src/utils/ascii.dart';
import 'package:xterm/src/utils/byte_consumer.dart';
import 'package:xterm/src/utils/char_code.dart';
import 'package:xterm/src/utils/lookup_table.dart';

/// [EscapeParser] translates control characters and escape sequences into
/// function calls that the terminal can handle.
///
/// Design goals:
///  * Zero object allocation during processing.
///  * No internal state. Same input will always produce same output.
class EscapeParser {
  static const _maxCsiRawLength = 256;

  static const _maxCsiParams = 32;

  static const _maxOscRawLength = 1024;

  static const _maxOscParams = 256;

  static const _maxDcsRawLength = 256;

  static const _escFinalIncomplete = -1;

  static const _escFinalCancelled = -2;

  final EscapeHandler handler;

  EscapeParser(this.handler);

  bool _isByteValue(int value) {
    return value >= 0 && value <= 0xff;
  }

  int _sgrTrueColorStart(int modeIndex) {
    if (_csi.separatorAfter(modeIndex) == Ascii.colon &&
        modeIndex + 4 < _csi.params.length) {
      return modeIndex + 2;
    }
    return modeIndex + 1;
  }

  final _queue = ByteConsumer();

  /// Start of sequence or character being processed. Useful for debugging.
  var tokenBegin = 0;

  /// End of sequence or character being processed. Useful for debugging.
  int get tokenEnd => _queue.totalConsumed;

  void write(String chunk) {
    _queue.unrefConsumedBlocks();
    _queue.add(chunk);
    _process();
  }

  void _process() {
    while (_queue.isNotEmpty) {
      if (_pendingEscape) {
        tokenBegin = _queue.totalConsumed;
        final processed = _processPendingEscape();
        if (!processed) {
          _queue.rollback(tokenEnd - tokenBegin);
          return;
        }
        continue;
      }

      if (_discardingCsi) {
        _discardCsiInput();
        if (_discardingCsi) return;
        continue;
      }

      if (_discardingOsc) {
        _discardOscInput();
        if (_discardingOsc) return;
        continue;
      }

      if (_discardingStringControl) {
        _discardStringControlInput();
        if (_discardingStringControl) return;
        continue;
      }

      if (_collectingDcs) {
        _collectDcsInput();
        if (_collectingDcs) return;
        continue;
      }

      tokenBegin = _queue.totalConsumed;
      final char = _queue.consume();

      if (char == Ascii.ESC) {
        final processed = _processEscape();
        if (!processed) {
          _queue.rollback(tokenEnd - tokenBegin);
          return;
        }
      } else if (char >= 0x80 && char <= 0x9F) {
        final processed = _processC1(char);
        if (!processed) {
          _queue.rollback(tokenEnd - tokenBegin);
          return;
        }
      } else {
        _processChar(char);
      }
    }
  }

  bool _processC1(int char) {
    switch (char) {
      case 0x84:
        handler.index();
        return true;
      case 0x85:
        handler.nextLine();
        return true;
      case 0x88:
        handler.setTapStop();
        return true;
      case 0x8D:
        handler.reverseIndex();
        return true;
      case 0x8E:
        handler.singleShiftCharset(2);
        return true;
      case 0x8F:
        handler.singleShiftCharset(3);
        return true;
      case 0x90:
        return _escHandleDcs();
      case 0x98:
      case 0x9E:
      case 0x9F:
        return _escHandleStringControl();
      case 0x9B:
        return _escHandleCSI();
      case 0x9C:
        return true;
      case 0x9D:
        return _escHandleOSC();
      default:
        handler.unknownSBC(char);
        return true;
    }
  }

  void _processChar(int char) {
    if (char > _sbcHandlers.maxIndex) {
      handler.writeChar(char);
      return;
    }

    final sbcHandler = _sbcHandlers[char];
    if (sbcHandler == null) {
      handler.unkownEscape(char);
      return;
    }

    sbcHandler();
  }

  /// Processes a sequence of characters that starts with an escape character.
  /// Returns [true] if the sequence was processed, [false] if it was not.
  bool _processEscape() {
    _pendingEscape = true;
    if (_queue.isEmpty) return true;

    final escapeBegin = _queue.totalConsumed;
    final processed = _processPendingEscape();
    if (!processed) {
      _queue.rollback(_queue.totalConsumed - escapeBegin);
    }
    return true;
  }

  bool _pendingEscape = false;

  int _consumeEscFinalByte() {
    while (_queue.isNotEmpty) {
      final char = _queue.consume();
      if (char == Ascii.ESC) {
        _pendingEscape = true;
        return _escFinalCancelled;
      }
      if (char == 0x18 || char == 0x1a) {
        return _escFinalCancelled;
      }
      if (char >= 0x80 && char <= 0x9f) {
        _queue.rollback(1);
        return _escFinalCancelled;
      }
      if (char < Ascii.space) {
        if (char <= 0x0f) {
          _sbcHandlers[char]?.call();
        }
        continue;
      }
      if (char == Ascii.DEL) continue;

      return char;
    }

    return _escFinalIncomplete;
  }

  bool _processPendingEscape() {
    if (_queue.isEmpty) return false;

    final char = _queue.consume();
    if (char == Ascii.ESC) return true;
    if (char == 0x18 || char == 0x1a) {
      _pendingEscape = false;
      return true;
    }
    if (char >= 0x80 && char <= 0x9f) {
      _pendingEscape = false;
      _queue.rollback(1);
      return true;
    }
    if (char < Ascii.space) {
      if (char <= 0x0f) {
        _sbcHandlers[char]?.call();
      }
      return true;
    }
    if (char == Ascii.DEL) return true;

    final escapeHandler = _escHandlers[char];
    if (escapeHandler == null) {
      _pendingEscape = false;
      handler.unkownEscape(char);
      return true;
    }

    _pendingEscape = false;
    final processed = escapeHandler();
    if (!processed) _pendingEscape = true;
    return processed;
  }

  late final _sbcHandlers = FastLookupTable<_SbcHandler>({
    0x05: handler.enquiry,
    0x07: handler.bell,
    0x08: handler.backspaceReturn,
    0x09: handler.tab,
    0x0a: handler.lineFeed,
    0x0b: handler.lineFeed,
    0x0c: handler.lineFeed,
    0x0d: handler.carriageReturn,
    0x0e: handler.shiftOut,
    0x0f: handler.shiftIn,
  });

  late final _escHandlers = FastLookupTable<_EscHandler>({
    '['.charCode: _escHandleCSI,
    ']'.charCode: _escHandleOSC,
    '7'.charCode: _escHandleSaveCursor,
    '8'.charCode: _escHandleRestoreCursor,
    'D'.charCode: _escHandleIndex,
    'E'.charCode: _escHandleNextLine,
    'H'.charCode: _escHandleTabSet,
    'M'.charCode: _escHandleReverseIndex,
    'N'.charCode: _escHandleSingleShift2,
    'O'.charCode: _escHandleSingleShift3,
    'P'.charCode: _escHandleDcs,
    'V'.charCode: _escHandleStartProtectedArea,
    'W'.charCode: _escHandleEndProtectedArea,
    'X'.charCode: _escHandleStringControl,
    '^'.charCode: _escHandleStringControl,
    '_'.charCode: _escHandleStringControl,
    'c'.charCode: _escHandleReset,
    // 'c'.charCode: _unsupportedHandler,
    '#'.charCode: _escHandleHash,
    '('.charCode: _escHandleDesignateCharset0, //  SCS - G0
    ')'.charCode: _escHandleDesignateCharset1, //  SCS - G1
    '*'.charCode: _escHandleDesignateCharset2, // SCS - G2
    '+'.charCode: _escHandleDesignateCharset3, // SCS - G3
    'n'.charCode: _escHandleLockingShift2,
    'o'.charCode: _escHandleLockingShift3,
    '>'.charCode: _escHandleResetAppKeypadMode, // TODO: Normal Keypad
    '='.charCode: _escHandleSetAppKeypadMode, // TODO: Application Keypad
  });

  /// `ESC V` Start of Protected Area (SPA).
  bool _escHandleStartProtectedArea() {
    handler.setIsoProtectedMode(true);
    return true;
  }

  /// `ESC W` End of Protected Area (EPA).
  bool _escHandleEndProtectedArea() {
    handler.setIsoProtectedMode(false);
    return true;
  }

  /// `ESC 7` Save Cursor (DECSC)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_a7/
  bool _escHandleSaveCursor() {
    handler.saveCursor();
    return true;
  }

  /// `ESC 8` Restore Cursor (DECRC)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_a8/
  bool _escHandleRestoreCursor() {
    handler.restoreCursor();
    return true;
  }

  /// `ESC D` Index (IND)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_cd/
  bool _escHandleIndex() {
    handler.index();
    return true;
  }

  /// `ESC E` Next Line (NEL)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_ce/
  bool _escHandleNextLine() {
    handler.nextLine();
    return true;
  }

  /// `ESC H` Horizontal Tab Set (HTS)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_ch/
  bool _escHandleTabSet() {
    handler.setTapStop();
    return true;
  }

  /// `ESC c` Full Reset (RIS)
  bool _escHandleReset() {
    handler.reset();
    return true;
  }

  /// `ESC # 8` DEC Screen Alignment Test (DECALN).
  bool _escHandleHash() {
    final command = _consumeEscFinalByte();
    if (command == _escFinalIncomplete) return false;
    if (command == _escFinalCancelled) return true;
    if (command == '8'.charCode) {
      handler.screenAlignmentTest();
      return true;
    }
    handler.unkownEscape(command);
    return true;
  }

  /// `ESC M` Reverse Index (RI)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_cm/
  bool _escHandleReverseIndex() {
    handler.reverseIndex();
    return true;
  }

  bool _escHandleDesignateCharset0() {
    final name = _consumeEscFinalByte();
    if (name == _escFinalIncomplete) return false;
    if (name == _escFinalCancelled) return true;
    handler.designateCharset(0, name);
    return true;
  }

  bool _escHandleDesignateCharset1() {
    final name = _consumeEscFinalByte();
    if (name == _escFinalIncomplete) return false;
    if (name == _escFinalCancelled) return true;
    handler.designateCharset(1, name);
    return true;
  }

  bool _escHandleDesignateCharset2() {
    final name = _consumeEscFinalByte();
    if (name == _escFinalIncomplete) return false;
    if (name == _escFinalCancelled) return true;
    handler.designateCharset(2, name);
    return true;
  }

  bool _escHandleDesignateCharset3() {
    final name = _consumeEscFinalByte();
    if (name == _escFinalIncomplete) return false;
    if (name == _escFinalCancelled) return true;
    handler.designateCharset(3, name);
    return true;
  }

  bool _escHandleSingleShift2() {
    handler.singleShiftCharset(2);
    return true;
  }

  bool _escHandleSingleShift3() {
    handler.singleShiftCharset(3);
    return true;
  }

  bool _escHandleLockingShift2() {
    handler.useCharset(2);
    return true;
  }

  bool _escHandleLockingShift3() {
    handler.useCharset(3);
    return true;
  }

  /// `ESC >` Reset Application Keypad Mode (DECKPNM)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_x3c_greater_than/
  bool _escHandleResetAppKeypadMode() {
    handler.setAppKeypadMode(false);
    return true;
  }

  /// `ESC =` Set Application Keypad Mode (DECKPAM)
  ///
  /// https://terminalguide.namepad.de/seq/a_esc_x3d_equals/
  bool _escHandleSetAppKeypadMode() {
    handler.setAppKeypadMode(true);
    return true;
  }

  bool _escHandleStringControl() {
    _discardingStringControl = true;
    _discardStringControlSawEscape = false;
    _discardStringControlInput();
    return true;
  }

  bool _escHandleDcs() {
    _collectingDcs = true;
    _dcsSawEscape = false;
    _dcsOverflowed = false;
    _dcsBuffer.clear();
    _collectDcsInput();
    return true;
  }

  bool _escHandleCSI() {
    final consumed = _consumeCsi();
    if (!consumed) return false;
    if (_csiOverflowed) return true;

    final csiHandler = _csiHandlers[_csi.finalByte];

    if (csiHandler == null) {
      handler.unknownCSI(_csi.finalByte);
    } else {
      csiHandler();
    }

    return true;
  }

  /// The last parsed [_Csi]. This is a mutable singletion by design to reduce
  /// object allocations.
  final _csi = _Csi(finalByte: 0, params: [], intermediates: []);

  bool _csiOverflowed = false;

  bool _discardingCsi = false;

  /// Parse a CSI from the head of the queue. Return false if the CSI isn't
  /// complete. After a CSI is successfully parsed, [_csi] is updated.
  bool _consumeCsi() {
    if (_queue.isEmpty) {
      return false;
    }

    _csi.params.clear();
    _csi.intermediates.clear();
    _csi.paramSeparators.clear();
    _csiOverflowed = false;
    var rawLength = 0;

    // Test whether the CSI has a private marker such as `?`, `>`, or `=`.
    // Semicolon is a parameter separator and must not be consumed here.
    final prefix = _queue.peek();
    if (prefix >= Ascii.lessThan && prefix <= Ascii.questionMark) {
      _csi.prefix = prefix;
      _queue.consume();
      rawLength++;
    } else {
      _csi.prefix = null;
    }

    var param = 0;
    var hasParam = false;
    var hasParamSeparator = false;
    while (true) {
      // The sequence isn't completed, just ignore it.
      if (_queue.isEmpty) {
        return false;
      }

      final char = _queue.consume();
      rawLength++;

      if (rawLength > _maxCsiRawLength) {
        _csiOverflowed = true;
        if (char == 0x18 || char == 0x1a) return true;
        if (char == Ascii.ESC) {
          _pendingEscape = true;
          return true;
        }
        if (char >= 0x80 && char <= 0x9f) {
          _queue.rollback(1);
          return true;
        }
        if (char < Ascii.space) {
          if (char <= 0x0f) {
            _sbcHandlers[char]?.call();
          }
          _discardingCsi = true;
          _discardCsiInput();
          return true;
        }
        if (char >= Ascii.atSign && char <= Ascii.tilde) {
          _csi.finalByte = char;
          return true;
        }
        _discardingCsi = true;
        _discardCsiInput();
        return true;
      }

      // CAN and SUB cancel the active control sequence. The next byte is
      // processed from the ground state.
      if (char == 0x18 || char == 0x1a) {
        _csiOverflowed = true;
        return true;
      }

      // ESC and C1 controls interrupt the active CSI and start their own
      // sequence. Put the byte back so the outer parser can process it.
      if (char == Ascii.ESC || (char >= 0x80 && char <= 0x9f)) {
        _queue.rollback(1);
        _csiOverflowed = true;
        return true;
      }

      // C0 controls are valid inside CSI sequences. Execute the controls we
      // support and otherwise ignore them without invalidating the sequence.
      if (char < Ascii.space) {
        if (char <= 0x0f) {
          _sbcHandlers[char]?.call();
        }
        continue;
      }

      if (char == Ascii.semicolon || char == Ascii.colon) {
        if (_csi.params.length < _maxCsiParams) {
          _csi.params.add(switch (hasParam) {
            true => param,
            false => 0,
          });
          _csi.paramSeparators.add(char);
        }
        param = 0;
        hasParam = false;
        hasParamSeparator = true;
        continue;
      }

      if (char >= Ascii.num0 && char <= Ascii.num9) {
        hasParam = true;
        param *= 10;
        param += char - Ascii.num0;
        continue;
      }

      if (char > Ascii.NULL && char < Ascii.num0) {
        _csi.intermediates.add(char);
        continue;
      }

      if (char >= Ascii.atSign && char <= Ascii.tilde) {
        if ((hasParam || hasParamSeparator) &&
            _csi.params.length < _maxCsiParams) {
          _csi.params.add(param);
        }

        _csi.finalByte = char;
        return true;
      }
    }
  }

  void _discardCsiInput() {
    while (_queue.isNotEmpty) {
      final char = _queue.consume();

      if (char == 0x18 || char == 0x1a) {
        _discardingCsi = false;
        return;
      }

      if (char == Ascii.ESC) {
        _discardingCsi = false;
        _pendingEscape = true;
        return;
      }

      if (char >= 0x80 && char <= 0x9f) {
        _discardingCsi = false;
        _queue.rollback(1);
        return;
      }

      if (char < Ascii.space) {
        if (char <= 0x0f) {
          _sbcHandlers[char]?.call();
        }
        continue;
      }

      if (char < Ascii.atSign || char > Ascii.tilde) continue;

      _discardingCsi = false;
      return;
    }
  }

  late final _csiHandlers = FastLookupTable<_CsiHandler>({
    '`'.codeUnitAt(0): _csiHandleCursorHorizontalAbsolute,
    'a'.codeUnitAt(0): _csiHandleCursorHorizontalRelative,
    'b'.codeUnitAt(0): _csiHandleRepeatPreviousCharacter,
    'c'.codeUnitAt(0): _csiHandleSendDeviceAttributes,
    'd'.codeUnitAt(0): _csiHandleLinePositionAbsolute,
    'e'.codeUnitAt(0): _csiHandleCursorVerticalRelative,
    'f'.codeUnitAt(0): _csiHandleCursorPosition,
    'g'.codeUnitAt(0): _csiHandelClearTabStop,
    'h'.codeUnitAt(0): _csiHandleMode,
    'j'.codeUnitAt(0): _csiHandleCursorBackward,
    'l'.codeUnitAt(0): _csiHandleMode,
    'm'.codeUnitAt(0): _csiHandleSgr,
    'n'.codeUnitAt(0): _csiHandleDeviceStatusReport,
    'p'.codeUnitAt(0): _csiHandleSoftReset,
    'q'.codeUnitAt(0): _csiHandleCursorStyle,
    'r'.codeUnitAt(0): _csiHandleSetMargins,
    's'.codeUnitAt(0): _csiHandleSaveModeOrCursor,
    'u'.codeUnitAt(0): _csiHandleKittyKeyboardMode,
    't'.codeUnitAt(0): _csiWindowManipulation,
    'A'.codeUnitAt(0): _csiHandleCursorUp,
    'B'.codeUnitAt(0): _csiHandleCursorDown,
    'C'.codeUnitAt(0): _csiHandleCursorForward,
    'D'.codeUnitAt(0): _csiHandleCursorBackward,
    'E'.codeUnitAt(0): _csiHandleCursorNextLine,
    'F'.codeUnitAt(0): _csiHandleCursorPrecedingLine,
    'G'.codeUnitAt(0): _csiHandleCursorHorizontalAbsolute,
    'H'.codeUnitAt(0): _csiHandleCursorPosition,
    'I'.codeUnitAt(0): _csiHandleCursorForwardTabulation,
    'J'.codeUnitAt(0): _csiHandleEraseDisplay,
    'K'.codeUnitAt(0): _csiHandleEraseLine,
    'L'.codeUnitAt(0): _csiHandleInsertLines,
    'M'.codeUnitAt(0): _csiHandleDeleteLines,
    'P'.codeUnitAt(0): _csiHandleDelete,
    'S'.codeUnitAt(0): _csiHandleScrollUp,
    'T'.codeUnitAt(0): _csiHandleScrollDown,
    'W'.codeUnitAt(0): _csiHandleCursorTabulationControl,
    'X'.codeUnitAt(0): _csiHandleEraseCharacters,
    'Z'.codeUnitAt(0): _csiHandleCursorBackwardTabulation,
    '@'.codeUnitAt(0): _csiHandleInsertBlankCharacters,
  });

  void _csiHandleCursorStyle() {
    if (_csi.intermediates.length == 1 &&
        _csi.intermediates.single == Ascii.doubleQuotes) {
      final mode = switch (_csi.params) {
        [] => 0,
        [final value] => value,
        _ => null,
      };
      if (mode == null) return;

      switch (mode) {
        case 0:
        case 2:
          return handler.setProtectedMode(false);
        case 1:
          return handler.setProtectedMode(true);
      }
      return;
    }

    if (_csi.prefix == Ascii.greaterThan &&
        _csi.intermediates.isEmpty &&
        _csi.params.length <= 1) {
      return handler.sendXtVersion();
    }

    if (_csi.intermediates.length != 1 ||
        _csi.intermediates.single != Ascii.space) {
      return handler.unknownCSI(_csi.finalByte);
    }

    final style = switch (_csi.params) {
      [final style] => style,
      _ => 0,
    };
    handler.setCursorShape(style);
  }

  void _csiHandleKittyKeyboardMode() {
    if (_csi.intermediates.isNotEmpty) return;
    switch (_csi.prefix) {
      case Ascii.questionMark:
        return handler.reportKittyKeyboardMode();
      case Ascii.equal:
        final mode = switch (_csi.params.isEmpty) {
          true => 0,
          false => _csi.params[0],
        };
        final behavior = switch (_csi.params.length >= 2) {
          true => _csi.params[1],
          false => 1,
        };
        return handler.setKittyKeyboardMode(mode, behavior);
      case Ascii.greaterThan:
        final mode = switch (_csi.params.isEmpty) {
          true => 0,
          false => _csi.params[0],
        };
        return handler.pushKittyKeyboardMode(mode);
      case Ascii.lessThan:
        final count = switch (_csi.params.isEmpty || _csi.params[0] == 0) {
          true => 1,
          false => _csi.params[0],
        };
        return handler.popKittyKeyboardModes(count);
      case null:
        return handler.restoreCursor();
      default:
        return handler.unknownCSI(_csi.finalByte);
    }
  }

  void _csiHandleSoftReset() {
    if (_csi.intermediates.length == 1 &&
        _csi.intermediates.single == Ascii.dollarSign) {
      final mode = switch (_csi.params) {
        [final value, ...] => value,
        _ => 0,
      };
      return handler.reportMode(mode, _csi.prefix == Ascii.questionMark);
    }
    if (_csi.intermediates.length != 1 ||
        _csi.intermediates.single != Ascii.exclamationMark) {
      return handler.unknownCSI(_csi.finalByte);
    }

    handler.softReset();
  }

  /// `ESC [ Ps a` Cursor Horizontal Position Relative (HPR)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sa/
  void _csiHandleCursorHorizontalRelative() {
    if (!_isPlainCsi()) return;
    handler.moveCursorX(_firstParamOrDefault(1));
  }

  /// `ESC [ Ps b` Repeat Previous Character (REP)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sb/
  void _csiHandleRepeatPreviousCharacter() {
    if (!_isPlainCsi()) return;
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.repeatPreviousCharacter(amount);
  }

  /// `ESC [ Ps c` Device Attributes (DA)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sc/
  void _csiHandleSendDeviceAttributes() {
    if (_csi.intermediates.isNotEmpty || _csi.params.length > 1) return;
    switch (_csi.prefix) {
      case Ascii.greaterThan:
        return handler.sendSecondaryDeviceAttributes();
      case Ascii.equal:
        return handler.sendTertiaryDeviceAttributes();
      case null:
        return handler.sendPrimaryDeviceAttributes();
    }
  }

  /// `ESC [ Ps d` Cursor Vertical Position Absolute (VPA)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sd/
  void _csiHandleLinePositionAbsolute() {
    if (!_isPlainCsi()) return;
    var y = 1;

    if (_csi.params.isNotEmpty) {
      y = _csi.params[0];
      if (y == 0) y = 1;
    }

    handler.setCursorY(y - 1);
  }

  /// `ESC [ Ps e` Cursor Vertical Position Relative (VPR)
  ///
  /// https://terminalguide.namepad.de/seq/csi_se/
  void _csiHandleCursorVerticalRelative() {
    if (!_isPlainCsi()) return;
    handler.moveCursorY(_firstParamOrDefault(1));
  }

  /// `ESC [ Ps ; Ps f` Alias: Set Cursor Position
  ///
  /// https://terminalguide.namepad.de/seq/csi_sf/
  void _csiHandleCursorPosition() {
    if (!_isPlainCsi(maxParams: 2)) return;
    var row = 1;
    var col = 1;

    if (_csi.params.isNotEmpty) {
      row = _csi.params[0];
      if (row == 0) row = 1;
    }
    if (_csi.params.length >= 2) {
      col = _csi.params[1];
      if (col == 0) col = 1;
    }

    handler.setCursor(col - 1, row - 1);
  }

  /// `ESC [ Ps g` Tab Clear (TBC)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sg/
  void _csiHandelClearTabStop() {
    if (!_isPlainCsi()) return;
    var cmd = 0;

    if (_csi.params.length == 1) {
      cmd = _csi.params[0];
    }

    switch (cmd) {
      case 0:
        return handler.clearTabStopUnderCursor();
      case 3:
        return handler.clearAllTabStops();
    }
  }

  /// `ESC [ Ps W` Cursor Tabulation Control (CTC)
  void _csiHandleCursorTabulationControl() {
    if (_csi.intermediates.isNotEmpty || _csi.params.length > 1) return;
    if (_csi.prefix == Ascii.questionMark) {
      if (_csi.params.length == 1 && _csi.params.single == 5) {
        return handler.resetTabStops();
      }
      return;
    }

    if (_csi.prefix != null) return;

    final command = switch (_csi.params) {
      [] => 0,
      [final value] => value,
      _ => null,
    };
    if (command == null) return;

    switch (command) {
      case 0:
        return handler.setTapStop();
      case 2:
        return handler.clearTabStopUnderCursor();
      case 5:
        return handler.clearAllTabStops();
    }
  }

  /// - `ESC [ [ Pm ] h Set Mode (SM)` https://terminalguide.namepad.de/seq/csi_sm/
  /// - `ESC [ ? [ Pm ] h` Set Mode (?) (SM) https://terminalguide.namepad.de/seq/csi_sh__p/
  /// - `ESC [ [ Pm ] l` Reset Mode (RM) https://terminalguide.namepad.de/seq/csi_rm/
  /// - `ESC [ ? [ Pm ] l` Reset Mode (?) (RM) https://terminalguide.namepad.de/seq/csi_sl__p/
  void _csiHandleMode() {
    if (_csi.intermediates.isNotEmpty ||
        (_csi.prefix != null && _csi.prefix != Ascii.questionMark)) {
      return;
    }
    final isEnabled = _csi.finalByte == Ascii.h;

    final isDecModes = _csi.prefix == Ascii.questionMark;

    if (isDecModes) {
      for (var mode in _csi.params) {
        _setDecMode(mode, isEnabled);
      }
    } else {
      for (var mode in _csi.params) {
        _setMode(mode, isEnabled);
      }
    }
  }

  /// `ESC [ [ Ps ] m` Select Graphic Rendition (SGR)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sm/
  void _csiHandleSgr() {
    if (_csi.prefix != null || _csi.intermediates.isNotEmpty) return;
    final params = _csi.params;

    if (params.isEmpty) {
      return handler.resetCursorStyle();
    }

    // This is a workaround for a bug in the analyzer.
    // ignore: dead_code
    for (var i = 0; i < _csi.params.length; i++) {
      final param = params[i];
      if (param == 4 &&
          i + 1 < params.length &&
          _csi.separatorAfter(i) == Ascii.colon) {
        switch (params[i + 1]) {
          case 0:
            handler.unsetCursorUnderline();
            break;
          case 1:
            handler.setCursorUnderline();
            break;
          case 2:
            handler.setCursorDoubleUnderline();
            break;
          case 3:
            handler.setCursorUndercurl();
            break;
          case 4:
            handler.setCursorDottedUnderline();
            break;
          case 5:
            handler.setCursorDashedUnderline();
            break;
        }
        i++;
        continue;
      }
      switch (param) {
        case 0:
          handler.resetCursorStyle();
          continue;
        case 1:
          handler.setCursorBold();
          continue;
        case 2:
          handler.setCursorFaint();
          continue;
        case 3:
          handler.setCursorItalic();
          continue;
        case 4:
          handler.setCursorUnderline();
          continue;
        case 5:
          handler.setCursorBlink();
          continue;
        case 6:
          handler.setCursorBlink();
          continue;
        case 7:
          handler.setCursorInverse();
          continue;
        case 8:
          handler.setCursorInvisible();
          continue;
        case 9:
          handler.setCursorStrikethrough();
          continue;
        case 53:
          handler.setCursorOverline();
          continue;

        case 21:
          handler.setCursorDoubleUnderline();
          continue;
        case 22:
          handler.unsetCursorBold();
          handler.unsetCursorFaint();
          continue;
        case 23:
          handler.unsetCursorItalic();
          continue;
        case 24:
          handler.unsetCursorUnderline();
          continue;
        case 25:
          handler.unsetCursorBlink();
          continue;
        case 27:
          handler.unsetCursorInverse();
          continue;
        case 28:
          handler.unsetCursorInvisible();
          continue;
        case 29:
          handler.unsetCursorStrikethrough();
          continue;
        case 55:
          handler.unsetCursorOverline();
          continue;

        case 30:
          handler.setForegroundColor16(NamedColor.black);
          continue;
        case 31:
          handler.setForegroundColor16(NamedColor.red);
          continue;
        case 32:
          handler.setForegroundColor16(NamedColor.green);
          continue;
        case 33:
          handler.setForegroundColor16(NamedColor.yellow);
          continue;
        case 34:
          handler.setForegroundColor16(NamedColor.blue);
          continue;
        case 35:
          handler.setForegroundColor16(NamedColor.magenta);
          continue;
        case 36:
          handler.setForegroundColor16(NamedColor.cyan);
          continue;
        case 37:
          handler.setForegroundColor16(NamedColor.white);
          continue;
        case 38:
          if (i + 1 >= params.length) {
            continue;
          }
          final mode = params[i + 1];
          switch (mode) {
            case 2:
              final start = _sgrTrueColorStart(i + 1);
              if (start + 2 >= params.length) {
                i = params.length;
                break;
              }
              final r = params[start];
              final g = params[start + 1];
              final b = params[start + 2];
              if (_isByteValue(r) && _isByteValue(g) && _isByteValue(b)) {
                handler.setForegroundColorRgb(r, g, b);
              }
              i = start + 2;
              break;
            case 5:
              if (i + 2 >= params.length) {
                i = params.length;
                break;
              }
              final index = params[i + 2];
              if (_isByteValue(index)) {
                handler.setForegroundColor256(index);
              }
              i += 2;
              break;
            default:
              i += 1;
              break;
          }
          continue;
        case 39:
          handler.resetForeground();
          continue;

        case 40:
          handler.setBackgroundColor16(NamedColor.black);
          continue;
        case 41:
          handler.setBackgroundColor16(NamedColor.red);
          continue;
        case 42:
          handler.setBackgroundColor16(NamedColor.green);
          continue;
        case 43:
          handler.setBackgroundColor16(NamedColor.yellow);
          continue;
        case 44:
          handler.setBackgroundColor16(NamedColor.blue);
          continue;
        case 45:
          handler.setBackgroundColor16(NamedColor.magenta);
          continue;
        case 46:
          handler.setBackgroundColor16(NamedColor.cyan);
          continue;
        case 47:
          handler.setBackgroundColor16(NamedColor.white);
          continue;
        case 48:
          if (i + 1 >= params.length) {
            continue;
          }
          final mode = params[i + 1];
          switch (mode) {
            case 2:
              final start = _sgrTrueColorStart(i + 1);
              if (start + 2 >= params.length) {
                i = params.length;
                break;
              }
              final r = params[start];
              final g = params[start + 1];
              final b = params[start + 2];
              if (_isByteValue(r) && _isByteValue(g) && _isByteValue(b)) {
                handler.setBackgroundColorRgb(r, g, b);
              }
              i = start + 2;
              break;
            case 5:
              if (i + 2 >= params.length) {
                i = params.length;
                break;
              }
              final index = params[i + 2];
              if (_isByteValue(index)) {
                handler.setBackgroundColor256(index);
              }
              i += 2;
              break;
            default:
              i += 1;
              break;
          }
          continue;
        case 49:
          handler.resetBackground();
          continue;
        case 58:
          if (i + 1 >= params.length) {
            continue;
          }
          final mode = params[i + 1];
          switch (mode) {
            case 2:
              final start = _sgrTrueColorStart(i + 1);
              if (start + 2 >= params.length) {
                i = params.length;
                break;
              }
              final r = params[start];
              final g = params[start + 1];
              final b = params[start + 2];
              if (_isByteValue(r) && _isByteValue(g) && _isByteValue(b)) {
                handler.setUnderlineColorRgb(r, g, b);
              }
              i = start + 2;
              break;
            case 5:
              if (i + 2 >= params.length) {
                i = params.length;
                break;
              }
              final index = params[i + 2];
              if (_isByteValue(index)) {
                handler.setUnderlineColor256(index);
              }
              i += 2;
              break;
            default:
              i += 1;
              break;
          }
          continue;
        case 59:
          handler.resetUnderlineColor();
          continue;

        case 90:
          handler.setForegroundColor16(NamedColor.brightBlack);
          continue;
        case 91:
          handler.setForegroundColor16(NamedColor.brightRed);
          continue;
        case 92:
          handler.setForegroundColor16(NamedColor.brightGreen);
          continue;
        case 93:
          handler.setForegroundColor16(NamedColor.brightYellow);
          continue;
        case 94:
          handler.setForegroundColor16(NamedColor.brightBlue);
          continue;
        case 95:
          handler.setForegroundColor16(NamedColor.brightMagenta);
          continue;
        case 96:
          handler.setForegroundColor16(NamedColor.brightCyan);
          continue;
        case 97:
          handler.setForegroundColor16(NamedColor.brightWhite);
          continue;

        case 100:
          handler.setBackgroundColor16(NamedColor.brightBlack);
          continue;
        case 101:
          handler.setBackgroundColor16(NamedColor.brightRed);
          continue;
        case 102:
          handler.setBackgroundColor16(NamedColor.brightGreen);
          continue;
        case 103:
          handler.setBackgroundColor16(NamedColor.brightYellow);
          continue;
        case 104:
          handler.setBackgroundColor16(NamedColor.brightBlue);
          continue;
        case 105:
          handler.setBackgroundColor16(NamedColor.brightMagenta);
          continue;
        case 106:
          handler.setBackgroundColor16(NamedColor.brightCyan);
          continue;
        case 107:
          handler.setBackgroundColor16(NamedColor.brightWhite);
          continue;

        default:
          handler.unsupportedStyle(param);
          continue;
      }
    }
  }

  /// `ESC [ Ps n` Device Status Report [Dispatch] (DSR)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sn/
  void _csiHandleDeviceStatusReport() {
    if (_csi.intermediates.isNotEmpty || _csi.params.length > 1) return;
    if (_csi.params.isEmpty) return;

    if (_csi.prefix == Ascii.questionMark) {
      switch (_csi.params[0]) {
        case 996:
          return handler.sendColorScheme();
      }
      return;
    }

    if (_csi.prefix != null) return;

    switch (_csi.params[0]) {
      case 5:
        return handler.sendOperatingStatus();
      case 6:
        return handler.sendCursorPosition();
    }
  }

  /// `ESC [ Ps ; Ps r` Set Top and Bottom Margins (DECSTBM)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sr/
  void _csiHandleSetMargins() {
    if (_csi.intermediates.isNotEmpty) return;
    if (_csi.prefix == Ascii.questionMark) {
      for (final mode in _csi.params) {
        handler.restoreDecMode(mode);
      }
      return;
    }

    if (_csi.prefix != null) return;

    var top = 0;
    int? bottom;

    if (_csi.params.length > 2) return;

    if (_csi.params.isNotEmpty) {
      final topParam = _csi.params[0];
      top = switch (topParam) {
        0 => 0,
        _ => topParam - 1,
      };

      if (_csi.params.length == 2) {
        final bottomParam = _csi.params[1];
        bottom = switch (bottomParam) {
          0 => null,
          _ => bottomParam - 1,
        };
      }
    }

    handler.setMargins(top, bottom);
  }

  /// `ESC [ ? Pm s` Save DEC Private Mode Values
  ///
  /// `ESC [ s` Save Cursor (SCOSC)
  ///
  /// `ESC [ Ps ; Ps s` Set Left and Right Margins (DECSLRM)
  void _csiHandleSaveModeOrCursor() {
    if (_csi.intermediates.isNotEmpty) return;
    if (_csi.prefix == null && _csi.params.isEmpty) {
      return handler.saveCursorOrSetLeftRightMargins();
    }

    if (_csi.prefix == null) {
      if (_csi.params.length > 2) return;

      var left = 0;
      int? right;

      if (_csi.params.isNotEmpty) {
        final leftParam = _csi.params[0];
        left = switch (leftParam) {
          0 => 0,
          _ => leftParam - 1,
        };

        if (_csi.params.length == 2) {
          final rightParam = _csi.params[1];
          right = switch (rightParam) {
            0 => null,
            _ => rightParam - 1,
          };
        }
      }

      return handler.setLeftRightMargins(left, right);
    }

    if (_csi.prefix != Ascii.questionMark) return;

    for (final mode in _csi.params) {
      handler.saveDecMode(mode);
    }
  }

  /// `ESC [ Ps t` Window operations [DISPATCH]
  ///
  /// https://terminalguide.namepad.de/seq/csi_st/
  void _csiWindowManipulation() {
    if (_csi.prefix != null || _csi.intermediates.isNotEmpty) return;
    // The sequence needs at least one parameter.
    if (_csi.params.isEmpty) {
      return;
    }
    // Most the commands in this group are either of the scope of this package,
    // or should be disabled for security risks.
    switch (_csi.params.first) {
      // Window handling is currently not in the scope of the package.
      case 1: // Restore Terminal Window (show window if minimized)
      case 2: // Minimize Terminal Window
      case 3: // Set Terminal Window Position
      case 4: // Set Terminal Window Size in Pixels
      case 5: // Raise Terminal Window
      case 6: // Lower Terminal Window
      case 7: // Refresh/Redraw Terminal Window
        return;
      case 8: // Set Terminal Window Size (in characters)
        // This CSI contains 2 more parameters: width and height.
        if (_csi.params.length != 3) {
          return;
        }
        final rows = _csi.params[1];
        final cols = _csi.params[2];
        handler.resize(cols, rows);
        return;
      // Window handling is currently no in the scope of the package.
      case 9: // Maximize Terminal Window
      case 10: // Alias: Maximize Terminal Window
      case 11: // Report Terminal Window State
      case 13: // Report Terminal Window Position
      case 15: // Report Screen Size in Pixels
        return;
      case 14: // Report Terminal Window Size in Pixels
        handler.sendPixelSize();
        return;
      case 16: // Report Cell Size in Pixels
        handler.sendCellSize();
        return;
      case 18: // Report Terminal Size (in characters)
        handler.sendSize();
        return;
      // Screen handling is currently no in the scope of the package.
      case 19: // Report Screen Size (in characters)
      // Disabled as these can a security risk.
      case 20: // Get Icon Title
      case 21: // Get Terminal Title
        return;
      case 22: // Push Terminal Title
        if (_csi.params.length > 3) return;
        if (_csi.params.length > 1 && !_isWindowTitleType(_csi.params[1])) {
          return;
        }
        handler.pushTitle();
        return;
      case 23: // Pop Terminal Title
        if (_csi.params.length > 3) return;
        if (_csi.params.length > 1 && !_isWindowTitleType(_csi.params[1])) {
          return;
        }
        handler.popTitle();
        return;
      // Unknown CSI.
      default:
        return;
    }
  }

  bool _isWindowTitleType(int type) {
    return type == 0 || type == 2;
  }

  /// `ESC [ Ps A` Cursor Up (CUU)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ca/
  void _csiHandleCursorUp() {
    if (!_isPlainCsi()) return;
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorY(-amount);
  }

  /// `ESC [ Ps B` Cursor Down (CUD)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cb/
  void _csiHandleCursorDown() {
    if (!_isPlainCsi()) return;
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorY(amount);
  }

  /// `ESC [ Ps C` Cursor Right (CUF)
  ///
  /// Cursor Right (CUF)
  void _csiHandleCursorForward() {
    if (!_isPlainCsi()) return;
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorX(amount);
  }

  /// `ESC [ Ps D` Cursor Left (CUB)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cd/
  void _csiHandleCursorBackward() {
    if (!_isPlainCsi()) return;
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorX(-amount);
  }

  /// `ESC [ Ps E` Cursor Next Line (CNL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ce/
  void _csiHandleCursorNextLine() {
    if (!_isPlainCsi()) return;
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.cursorNextLine(amount);
  }

  /// `ESC [ Ps F` Cursor Previous Line (CPL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cf/
  void _csiHandleCursorPrecedingLine() {
    if (!_isPlainCsi()) return;
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.cursorPrecedingLine(amount);
  }

  void _csiHandleCursorHorizontalAbsolute() {
    if (!_isPlainCsi()) return;
    var x = 1;

    if (_csi.params.isNotEmpty) {
      x = _csi.params[0];
      if (x == 0) x = 1;
    }

    handler.setCursorX(x - 1);
  }

  /// ESC [ Ps J Erase Display [Dispatch] (ED)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cj/
  void _csiHandleEraseDisplay() {
    if (_csi.intermediates.isNotEmpty || _csi.params.length > 1) return;
    final selective = _csi.prefix == Ascii.questionMark;
    if (_csi.prefix != null && !selective) return;

    var cmd = 0;

    if (_csi.params.length == 1) {
      cmd = _csi.params[0];
    }

    switch (cmd) {
      case 0:
        if (selective) return handler.eraseDisplayBelowSelective();
        return handler.eraseDisplayBelow();
      case 1:
        if (selective) return handler.eraseDisplayAboveSelective();
        return handler.eraseDisplayAbove();
      case 2:
        if (selective) return handler.eraseDisplaySelective();
        return handler.eraseDisplay();
      case 3:
        if (selective) return;
        return handler.eraseScrollbackOnly();
    }
  }

  /// `ESC [ Ps K` Erase Line [Dispatch] (EL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ck/
  void _csiHandleEraseLine() {
    if (_csi.intermediates.isNotEmpty || _csi.params.length > 1) return;
    final selective = _csi.prefix == Ascii.questionMark;
    if (_csi.prefix != null && !selective) return;

    var cmd = 0;

    if (_csi.params.length == 1) {
      cmd = _csi.params[0];
    }

    switch (cmd) {
      case 0:
        if (selective) return handler.eraseLineRightSelective();
        return handler.eraseLineRight();
      case 1:
        if (selective) return handler.eraseLineLeftSelective();
        return handler.eraseLineLeft();
      case 2:
        if (selective) return handler.eraseLineSelective();
        return handler.eraseLine();
    }
  }

  /// `ESC [ Ps L` Insert Line (IL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cl/
  void _csiHandleInsertLines() {
    if (!_isPlainCsi()) return;
    final amount = _firstParamOrDefault(1);
    handler.insertLines(amount);
  }

  /// ESC [ Ps M Delete Line (DL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cm/
  void _csiHandleDeleteLines() {
    if (!_isPlainCsi()) return;
    final amount = _firstParamOrDefault(1);
    handler.deleteLines(amount);
  }

  /// ESC [ Ps P Delete Character (DCH)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cp/
  void _csiHandleDelete() {
    if (!_isPlainCsi()) return;
    final amount = _firstParamOrDefault(1);
    handler.deleteChars(amount);
  }

  /// `ESC [ Ps S` Scroll Up (SU)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cs/
  void _csiHandleScrollUp() {
    if (!_isPlainCsi()) return;
    final amount = _firstParamOrDefault(1);
    handler.scrollUp(amount);
  }

  /// `ESC [ Ps T `Scroll Down (SD)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ct_1param/
  void _csiHandleScrollDown() {
    if (!_isPlainCsi()) return;
    final amount = _firstParamOrDefault(1);
    handler.scrollDown(amount);
  }

  /// `ESC [ Ps X` Erase Character (ECH)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cx/
  void _csiHandleEraseCharacters() {
    if (!_isPlainCsi()) return;
    final amount = _firstParamOrDefault(1);
    handler.eraseChars(amount);
  }

  /// `ESC [ Ps @` Insert Blanks (ICH)
  ///
  /// https://terminalguide.namepad.de/seq/csi_x40_at/
  ///
  /// Inserts amount spaces at current cursor position moving existing cell
  /// contents to the right. The contents of the amount right-most columns in
  /// the scroll region are lost. The cursor position is not changed.
  void _csiHandleInsertBlankCharacters() {
    if (!_isPlainCsi()) return;
    final amount = _firstParamOrDefault(1);
    handler.insertBlankChars(amount);
  }

  void _csiHandleCursorForwardTabulation() {
    if (!_isPlainCsi()) return;
    handler.moveForwardTabs(_firstParamOrDefault(1));
  }

  void _csiHandleCursorBackwardTabulation() {
    if (!_isPlainCsi()) return;
    handler.moveBackwardTabs(_firstParamOrDefault(1));
  }

  int _firstParamOrDefault(int defaultValue) {
    if (_csi.params.isEmpty) {
      return defaultValue;
    }

    final value = _csi.params[0];
    if (value == 0) {
      return defaultValue;
    }

    return value;
  }

  bool _isPlainCsi({int maxParams = 1}) {
    return _csi.prefix == null &&
        _csi.intermediates.isEmpty &&
        _csi.params.length <= maxParams;
  }

  void _setMode(int mode, bool enabled) {
    switch (mode) {
      case 4:
        return handler.setInsertMode(enabled);
      case 20:
        return handler.setLineFeedMode(enabled);
      default:
        return handler.setUnknownMode(mode, enabled);
    }
  }

  void _setDecMode(int mode, bool enabled) {
    switch (mode) {
      case 1:
        return handler.setCursorKeysMode(enabled);
      case 3:
        return handler.setColumnMode(enabled);
      case 5:
        return handler.setReverseDisplayMode(enabled);
      case 6:
        return handler.setOriginMode(enabled);
      case 7:
        return handler.setAutoWrapMode(enabled);
      case 9:
        return enabled
            ? handler.setMouseMode(MouseMode.clickOnly)
            : handler.setMouseMode(MouseMode.none);
      case 12:
      case 13:
        return handler.setCursorBlinkMode(enabled);
      case 25:
        return handler.setCursorVisibleMode(enabled);
      case 45:
        return handler.setReverseWrapMode(enabled);
      case 47:
        if (enabled) {
          return handler.useAltBuffer();
        } else {
          return handler.useMainBuffer();
        }
      case 66:
        return handler.setAppKeypadMode(enabled);
      case 69:
        return handler.setLeftRightMarginMode(enabled);
      case 1000:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScroll)
            : handler.setMouseMode(MouseMode.none);
      case 1001:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScroll)
            : handler.setMouseMode(MouseMode.none);
      case 1002:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScrollDrag)
            : handler.setMouseMode(MouseMode.none);
      case 1003:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScrollMove)
            : handler.setMouseMode(MouseMode.none);
      case 1004:
        return handler.setReportFocusMode(enabled);
      case 1005:
        return enabled
            ? handler.setMouseReportMode(MouseReportMode.utf)
            : handler.setMouseReportMode(MouseReportMode.normal);
      case 1006:
        return enabled
            ? handler.setMouseReportMode(MouseReportMode.sgr)
            : handler.setMouseReportMode(MouseReportMode.normal);
      case 1007:
        return handler.setAltBufferMouseScrollMode(enabled);
      case 1015:
        return enabled
            ? handler.setMouseReportMode(MouseReportMode.urxvt)
            : handler.setMouseReportMode(MouseReportMode.normal);
      case 1016:
        return enabled
            ? handler.setMouseReportMode(MouseReportMode.sgrPixels)
            : handler.setMouseReportMode(MouseReportMode.normal);
      case 1045:
        return handler.setReverseWrapExtendedMode(enabled);
      case 1047:
        if (enabled) {
          handler.useAltBuffer();
        } else {
          handler.clearAltBuffer();
          handler.useMainBuffer();
        }
        return;
      case 1048:
        if (enabled) {
          return handler.saveCursor();
        } else {
          return handler.restoreCursor();
        }
      case 1049:
        if (enabled) {
          handler.saveCursor();
          handler.clearAltBuffer();
          handler.useAltBuffer();
        } else {
          handler.useMainBuffer();
          handler.restoreCursor();
        }
        return;
      case 2004:
        return handler.setBracketedPasteMode(enabled);
      case 2026:
        return handler.setSynchronizedUpdateMode(enabled);
      case 2027:
        return handler.setGraphemeClusterMode(enabled);
      default:
        return handler.setUnknownDecMode(mode, enabled);
    }
  }

  /// Parse a OSC sequence from the queue. Returns true if a sequence was
  /// found and handled.
  bool _escHandleOSC() {
    final consumed = _consumeOsc();
    if (!consumed) {
      return false;
    }

    if (_oscOverflowed) return true;

    if (_osc.isEmpty) {
      return true;
    }

    // Common OSCs
    if (_osc.length >= 2) {
      final ps = _osc[0];
      final pt = _osc[1];

      switch (ps) {
        case '0':
          handler.setTitle(pt);
          handler.setIconName(pt);
          return true;
        case '1':
          handler.setIconName(pt);
          return true;
        case '2':
          handler.setTitle(pt);
          return true;
        case '7':
          handler.setCurrentDirectory(pt);
          return true;
        case '8':
          if (_osc.length < 3) return true;
          handler.setHyperlink(pt, _osc.sublist(2).join(';'));
          return true;
        case '4':
          for (var i = 1; i + 1 < _osc.length; i += 2) {
            final index = int.tryParse(_osc[i]);
            if (index == null) continue;
            final value = _osc[i + 1];
            if (value == '?') {
              handler.queryIndexedColor(index);
              continue;
            }
            handler.setIndexedColor(index, value);
          }
          return true;
        case '10':
        case '11':
        case '12':
          final firstCode = int.parse(ps);
          for (var i = 1; i < _osc.length; i++) {
            final code = firstCode + i - 1;
            final value = _osc[i];
            if (value == '?') {
              handler.queryDynamicColor(code);
              continue;
            }
            handler.setDynamicColor(code, value);
          }
          return true;
        case '52':
          if (_osc.length < 3) return true;
          final data = _osc[2];
          if (data == '?') {
            handler.queryClipboard(_osc[1]);
            return true;
          }
          handler.storeClipboard(_osc[1], data);
          return true;
      }
    }

    final ps = _osc[0];
    switch (ps) {
      case '104':
        final indices = <int>[];
        for (var i = 1; i < _osc.length; i++) {
          final index = int.tryParse(_osc[i]);
          if (index != null) indices.add(index);
        }
        handler.resetIndexedColors(indices);
        return true;
      case '110':
      case '111':
      case '112':
        handler.resetDynamicColor(int.parse(ps) - 100);
        return true;
    }

    // Private extensions
    handler.unknownOSC(_osc[0], _osc.sublist(1));

    return true;
  }

  final _osc = <String>[];

  bool _oscOverflowed = false;

  bool _discardingOsc = false;

  bool _discardOscSawEscape = false;

  bool _consumeOsc() {
    _osc.clear();
    _oscOverflowed = false;
    final param = StringBuffer();
    var rawLength = 0;

    while (true) {
      if (_queue.isEmpty) {
        return false;
      }

      final char = _queue.consume();
      rawLength++;

      if (rawLength > _maxOscRawLength) {
        _osc.clear();
        _oscOverflowed = true;
        _discardingOsc = true;
        _discardOscSawEscape = char == Ascii.ESC;
        _discardOscInput();
        return true;
      }

      // OSC terminates with BEL
      if (char == Ascii.BEL) {
        _osc.add(param.toString());
        return true;
      }

      if (char == 0x9C) {
        _osc.add(param.toString());
        return true;
      }

      if (char == 0x18 || char == 0x1a) {
        _osc.clear();
        _oscOverflowed = true;
        return true;
      }

      if (char >= 0x80 && char <= 0x9f) {
        _queue.rollback(1);
        _osc.clear();
        _oscOverflowed = true;
        return true;
      }

      /// OSC terminates with ST
      if (char == Ascii.ESC) {
        if (_queue.isEmpty) {
          return false;
        }

        if (_queue.consume() == Ascii.backslash) {
          _osc.add(param.toString());
          return true;
        }

        _queue.rollback(2);
        _osc.clear();
        _oscOverflowed = true;
        return true;
      }

      // C0 controls other than BEL are ignored inside OSC payloads.
      if (char < Ascii.space) continue;

      /// Parse next parameter
      if (char == Ascii.semicolon) {
        if (_osc.length < _maxOscParams - 1) {
          _osc.add(param.toString());
        }
        param.clear();
        continue;
      }

      param.writeCharCode(char);
    }
  }

  void _discardOscInput() {
    while (_queue.isNotEmpty) {
      final char = _queue.consume();

      if (_discardOscSawEscape) {
        _discardOscSawEscape = false;
        if (char == Ascii.backslash) {
          _discardingOsc = false;
          return;
        }
        _discardingOsc = false;
        _pendingEscape = true;
        _queue.rollback(1);
        return;
      }

      if (char == Ascii.BEL) {
        _discardingOsc = false;
        return;
      }

      if (char == 0x9C) {
        _discardingOsc = false;
        return;
      }

      if (char == 0x18 || char == 0x1a) {
        _discardingOsc = false;
        return;
      }

      if (char >= 0x80 && char <= 0x9f) {
        _discardingOsc = false;
        _queue.rollback(1);
        return;
      }

      if (char == Ascii.ESC) {
        _discardOscSawEscape = true;
      }
    }
  }

  bool _discardingStringControl = false;

  bool _discardStringControlSawEscape = false;

  void _discardStringControlInput() {
    while (_queue.isNotEmpty) {
      final char = _queue.consume();

      if (_discardStringControlSawEscape) {
        _discardStringControlSawEscape = false;
        if (char == Ascii.backslash) {
          _discardingStringControl = false;
          return;
        }
        _discardingStringControl = false;
        _pendingEscape = true;
        _queue.rollback(1);
        return;
      }

      if (char == 0x9C) {
        _discardingStringControl = false;
        return;
      }

      if (char == 0x18 || char == 0x1a) {
        _discardingStringControl = false;
        return;
      }

      if (char >= 0x80 && char <= 0x9f) {
        _discardingStringControl = false;
        _queue.rollback(1);
        return;
      }

      if (char == Ascii.ESC) {
        _discardStringControlSawEscape = true;
      }
    }
  }

  bool _collectingDcs = false;

  bool _dcsSawEscape = false;

  bool _dcsOverflowed = false;

  final _dcsBuffer = StringBuffer();

  void _collectDcsInput() {
    while (_queue.isNotEmpty) {
      final char = _queue.consume();

      if (_dcsSawEscape) {
        _dcsSawEscape = false;
        if (char == Ascii.backslash) {
          _collectingDcs = false;
          _handleDcs();
          return;
        }
        _collectingDcs = false;
        _dcsBuffer.clear();
        _pendingEscape = true;
        _queue.rollback(1);
        return;
      }

      if (char == 0x9C) {
        _collectingDcs = false;
        _handleDcs();
        return;
      }

      if (char == 0x18 || char == 0x1a) {
        _collectingDcs = false;
        _dcsBuffer.clear();
        return;
      }

      if (char >= 0x80 && char <= 0x9f) {
        _collectingDcs = false;
        _dcsBuffer.clear();
        _queue.rollback(1);
        return;
      }

      if (char == Ascii.ESC) {
        _dcsSawEscape = true;
        continue;
      }

      _writeDcsChar(char);
    }
  }

  void _writeDcsChar(int char) {
    if (_dcsOverflowed) return;
    if (_dcsBuffer.length >= _maxDcsRawLength) {
      _dcsOverflowed = true;
      return;
    }
    _dcsBuffer.writeCharCode(char);
  }

  void _handleDcs() {
    if (_dcsOverflowed) return;
    final payload = _dcsBuffer.toString();
    if (payload.startsWith('\$q')) {
      handler.sendStatusString(payload.substring(2));
      return;
    }
    if (!payload.startsWith('+q')) return;
    for (final query in payload.substring(2).split(';')) {
      if (query.isEmpty) continue;
      handler.sendTerminfoCapability(query);
    }
  }
}

class _Csi {
  _Csi({
    required this.params,
    required this.finalByte,
    required this.intermediates,
  }) : paramSeparators = [];

  int? prefix;

  List<int> params;

  final List<int> paramSeparators;

  int finalByte;

  final List<int> intermediates;

  int? separatorAfter(int paramIndex) {
    if (paramIndex < 0 || paramIndex >= paramSeparators.length) {
      return null;
    }
    return paramSeparators[paramIndex];
  }

  @override
  String toString() {
    return params.join(';') + String.fromCharCode(finalByte);
  }
}

/// Function that handles a sequence of characters that starts with an escape.
/// Returns [true] if the sequence was processed, [false] if it was not.
typedef _EscHandler = bool Function();

typedef _SbcHandler = void Function();

typedef _CsiHandler = void Function();
