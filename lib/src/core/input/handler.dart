export 'package:xterm/src/core/input/event.dart';
export 'package:xterm/src/core/input/kitty_handler.dart';

import 'package:xterm/src/core/input/event.dart';
import 'package:xterm/src/core/input/keys.dart';
import 'package:xterm/src/core/input/keytab/keytab.dart';
import 'package:xterm/src/core/input/kitty_handler.dart';
import 'package:xterm/src/core/platform.dart';

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
  KeytabInputHandler(),
  CtrlInputHandler(),
  AltInputHandler(),
]);

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
    if (!event.ctrl || event.shift || event.alt) {
      return null;
    }

    final key = event.key;
    if (key.index < TerminalKey.keyA.index ||
        key.index > TerminalKey.keyZ.index) {
      return null;
    }
    final input = key.index - TerminalKey.keyA.index + 1;
    return String.fromCharCode(input);
  }
}

/// Translates Alt plus a letter into an escape-prefixed character.
class AltInputHandler implements TerminalInputHandler {
  const AltInputHandler();

  @override
  String? call(TerminalKeyboardEvent event) {
    if (event.type == TerminalKeyEventType.release) {
      return null;
    }
    if (!event.alt || event.ctrl || event.shift) {
      return null;
    }
    if (event.platform == TerminalTargetPlatform.macos) {
      return null;
    }

    final key = event.key;
    if (key.index < TerminalKey.keyA.index ||
        key.index > TerminalKey.keyZ.index) {
      return null;
    }
    final charCode = key.index - TerminalKey.keyA.index + 65;
    return String.fromCharCodes([0x1b, charCode]);
  }
}
