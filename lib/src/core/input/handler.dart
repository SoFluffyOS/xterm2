export 'package:xterm2/src/core/input/event.dart';
export 'package:xterm2/src/core/input/kitty_handler.dart';

import 'package:xterm2/src/core/input/event.dart';
import 'package:xterm2/src/core/input/keys.dart';
import 'package:xterm2/src/core/input/keytab/keytab.dart';
import 'package:xterm2/src/core/input/kitty_handler.dart';
import 'package:xterm2/src/core/platform.dart';

/// Chains input handlers and returns the first non-null result.
class CascadeInputHandler implements TerminalInputHandler {
  final List<TerminalInputHandler> _handlers;

  const CascadeInputHandler(this._handlers);

  @override
  String? call(TerminalKeyboardEvent event) {
    for (final handler in _handlers) {
      final result = handler(event);
      if (result != null) {
        return result;
      }
    }
    return null;
  }
}

/// The default terminal input handler chain.
const defaultInputHandler = CascadeInputHandler([
  KittyKeyboardInputHandler(),
  ModifyOtherKeysInputHandler(),
  BackspaceInputHandler(),
  ApplicationKeypadInputHandler(),
  ExtendedFunctionKeyInputHandler(),
  KeytabInputHandler(),
  CtrlInputHandler(),
  AltInputHandler(),
]);

/// Translates Backspace according to DEC Backarrow Key Mode (DECBKM).
class BackspaceInputHandler implements TerminalInputHandler {
  const BackspaceInputHandler();

  @override
  String? call(TerminalKeyboardEvent event) {
    if (event.type == TerminalKeyEventType.release) return null;
    if (event.key != TerminalKey.backspace) return null;
    if (!event.state.backarrowKeyMode) return null;

    final prefix = switch (event.alt) {
      true => '\x1b',
      false => '',
    };
    return '$prefix\b';
  }
}

/// Translates numpad keys in application keypad mode.
class ApplicationKeypadInputHandler implements TerminalInputHandler {
  const ApplicationKeypadInputHandler();

  @override
  String? call(TerminalKeyboardEvent event) {
    if (event.type == TerminalKeyEventType.release) return null;
    if (!event.state.appKeypadMode) return null;
    if (event.state.ignoreKeypadWithNumLockMode) return null;

    final suffix = switch (event.key) {
      TerminalKey.numpad0 => 'p',
      TerminalKey.numpad1 => 'q',
      TerminalKey.numpad2 => 'r',
      TerminalKey.numpad3 => 's',
      TerminalKey.numpad4 => 't',
      TerminalKey.numpad5 => 'u',
      TerminalKey.numpad6 => 'v',
      TerminalKey.numpad7 => 'w',
      TerminalKey.numpad8 => 'x',
      TerminalKey.numpad9 => 'y',
      TerminalKey.numpadDecimal => 'n',
      TerminalKey.numpadDivide => 'o',
      TerminalKey.numpadMultiply => 'j',
      TerminalKey.numpadSubtract => 'm',
      TerminalKey.numpadAdd => 'k',
      TerminalKey.numpadEnter => 'M',
      TerminalKey.numpadEqual => 'X',
      TerminalKey.numpadComma => 'l',
      _ => null,
    };
    if (suffix == null) return null;

    return '\x1bO$suffix';
  }
}

/// Translates F13-F24 to the xterm-compatible shifted F1-F12 sequences.
class ExtendedFunctionKeyInputHandler implements TerminalInputHandler {
  const ExtendedFunctionKeyInputHandler();

  static const _sequences = [
    '\x1b[1;2P',
    '\x1b[1;2Q',
    '\x1b[1;2R',
    '\x1b[1;2S',
    '\x1b[15;2~',
    '\x1b[17;2~',
    '\x1b[18;2~',
    '\x1b[19;2~',
    '\x1b[20;2~',
    '\x1b[21;2~',
    '\x1b[23;2~',
    '\x1b[24;2~',
  ];

  @override
  String? call(TerminalKeyboardEvent event) {
    if (event.type == TerminalKeyEventType.release) return null;
    if (event.ctrl || event.alt || event.shift) return null;

    final index = event.key.index - TerminalKey.f13.index;
    if (index < 0 || index >= _sequences.length) return null;
    return _sequences[index];
  }
}

/// Translates textual keys using xterm modifyOtherKeys mode 2.
class ModifyOtherKeysInputHandler implements TerminalInputHandler {
  const ModifyOtherKeysInputHandler();

  @override
  String? call(TerminalKeyboardEvent event) {
    if (event.type == TerminalKeyEventType.release) return null;
    if (event.state.modifyOtherKeysMode != 2) return null;

    final codepoint = _codepoint(event);
    if (codepoint == null) return null;
    if (!_shouldModify(event, codepoint)) return null;

    return '\x1b[27;${_encodedModifiers(event)};$codepoint~';
  }

  int? _codepoint(TerminalKeyboardEvent event) {
    final text = event.text;
    if (text != null && text.runes.length == 1) {
      return text.runes.first;
    }

    final key = event.key;
    if (key.index >= TerminalKey.keyA.index &&
        key.index <= TerminalKey.keyZ.index) {
      final base = key.index - TerminalKey.keyA.index;
      return event.shift ? base + 65 : base + 97;
    }
    if (key.index >= TerminalKey.digit1.index &&
        key.index <= TerminalKey.digit9.index) {
      return key.index - TerminalKey.digit1.index + 49;
    }
    return switch (key) {
      TerminalKey.digit0 => 48,
      TerminalKey.space => 32,
      TerminalKey.minus => 45,
      TerminalKey.equal => 61,
      TerminalKey.bracketLeft => 91,
      TerminalKey.bracketRight => 93,
      TerminalKey.backslash || TerminalKey.intlBackslash => 92,
      TerminalKey.semicolon => 59,
      TerminalKey.quote => 39,
      TerminalKey.backquote => 96,
      TerminalKey.comma => 44,
      TerminalKey.period => 46,
      TerminalKey.slash => 47,
      _ => null,
    };
  }

  bool _shouldModify(TerminalKeyboardEvent event, int codepoint) {
    if (codepoint >= 0x40 && codepoint <= 0x7f) return true;
    if (event.ctrl || event.alt) return true;
    return event.shift && codepoint == 0x20;
  }

  int _encodedModifiers(TerminalKeyboardEvent event) {
    var modifiers = 1;
    if (event.shift) modifiers += 1;
    if (event.alt) modifiers += 2;
    if (event.ctrl) modifiers += 4;
    return modifiers;
  }
}

/// Translates key events according to a keytab file.
class KeytabInputHandler implements TerminalInputHandler {
  const KeytabInputHandler([this.keytab]);

  final Keytab? keytab;

  @override
  String? call(TerminalKeyboardEvent event) {
    if (event.type == TerminalKeyEventType.release) {
      return null;
    }
    final keytab = this.keytab ?? Keytab.defaultKeytab;
    final record = keytab.find(
      event.key,
      ctrl: event.ctrl,
      alt: event.alt,
      shift: event.shift,
      newLineMode: event.state.lineFeedMode,
      appCursorKeys: event.state.cursorKeysMode,
      appKeyPad: event.state.appKeypadMode,
      appScreen: event.altBuffer,
      macos: event.platform == TerminalTargetPlatform.macos,
    );
    if (record == null) {
      return null;
    }

    final result = record.action.unescapedValue();
    return insertModifiers(event, result);
  }

  String insertModifiers(TerminalKeyboardEvent event, String action) {
    final code = switch ((event.shift, event.alt, event.ctrl)) {
      (true, true, true) => '8',
      (false, true, true) => '7',
      (true, false, true) => '6',
      (false, false, true) => '5',
      (true, true, false) => '4',
      (false, true, false) => '3',
      (true, false, false) => '2',
      (false, false, false) => null,
    };
    if (code == null) {
      return action;
    }
    return action.replaceAll('*', code);
  }
}

/// Translates Ctrl plus a letter into a C0 control character.
class CtrlInputHandler implements TerminalInputHandler {
  const CtrlInputHandler();

  @override
  String? call(TerminalKeyboardEvent event) {
    if (event.type == TerminalKeyEventType.release) {
      return null;
    }
    if (!event.ctrl) {
      return null;
    }

    final key = event.key;
    if (!event.shift &&
        key.index >= TerminalKey.keyA.index &&
        key.index <= TerminalKey.keyZ.index) {
      final input = key.index - TerminalKey.keyA.index + 1;
      return _withAltPrefix(input, event.alt);
    }

    final text = event.text;
    final textCodePoint = switch (text?.runes.toList(growable: false)) {
      [final codePoint] => codePoint,
      _ => null,
    };
    final control = switch ((key, textCodePoint)) {
      (TerminalKey.space, _) || (_, 0x20) => 0x00,
      (TerminalKey.bracketLeft, _) || (_, 0x5B) => 0x1B,
      (TerminalKey.backslash, _) || (TerminalKey.intlBackslash, _) => 0x1C,
      (_, 0x5C) => 0x1C,
      (TerminalKey.bracketRight, _) || (_, 0x5D) => 0x1D,
      (TerminalKey.digit6, _) || (_, 0x5E) => 0x1E,
      (TerminalKey.slash, _) ||
      (TerminalKey.minus, _) ||
      (_, 0x2F) ||
      (_, 0x5F) =>
        0x1F,
      _ => null,
    };
    if (control == null) return null;
    return _withAltPrefix(control, event.alt);
  }

  String _withAltPrefix(int control, bool alt) {
    final value = String.fromCharCode(control);
    return switch (alt) {
      true => '\x1b$value',
      false => value,
    };
  }
}

/// Translates Alt plus printable text into legacy terminal input.
class AltInputHandler implements TerminalInputHandler {
  const AltInputHandler();

  @override
  String? call(TerminalKeyboardEvent event) {
    if (event.type == TerminalKeyEventType.release) {
      return null;
    }
    if (!event.alt || event.ctrl || event.superKey) {
      return null;
    }
    if (event.platform == TerminalTargetPlatform.macos) {
      if (!event.state.altSendsEscapeMode) return null;
    } else {
      if (!event.state.altEscPrefixMode) return null;
    }

    final text = _legacyText(event);
    if (text == null) return null;

    final codePoint = text.runes.single;
    if (codePoint > 0x7f) return text;
    return '\x1b$text';
  }

  String? _legacyText(TerminalKeyboardEvent event) {
    final text = event.text;
    if (text != null && text.runes.length == 1) {
      final codePoint = text.runes.first;
      if (codePoint >= 0x20 && codePoint != 0x7f) {
        if (event.platform != TerminalTargetPlatform.macos ||
            codePoint <= 0x7f) {
          return text;
        }
      }
    }

    final key = event.key;
    if (key.index < TerminalKey.keyA.index ||
        key.index > TerminalKey.keyZ.index) {
      return null;
    }
    final base = switch (event.shift) {
      true => 0x41,
      false => 0x61,
    };
    return String.fromCharCode(key.index - TerminalKey.keyA.index + base);
  }
}
