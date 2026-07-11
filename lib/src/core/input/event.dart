import 'package:xterm2/src/core/input/keys.dart';
import 'package:xterm2/src/core/platform.dart';
import 'package:xterm2/src/core/state.dart';

enum TerminalKeyEventType { press, repeat, release }

/// The key event received from the keyboard, along with the state of the
/// modifier keys and state of the terminal. Typically consumed by the
/// [TerminalInputHandler] to produce an escape sequence that can be recognized
/// by the terminal.
class TerminalKeyboardEvent {
  final TerminalKey key;

  final bool shift;

  final bool ctrl;

  final bool alt;

  final TerminalState state;

  final bool altBuffer;

  final TerminalTargetPlatform platform;

  final TerminalKeyEventType type;

  final String? text;

  TerminalKeyboardEvent({
    required this.key,
    required this.shift,
    required this.ctrl,
    required this.alt,
    required this.state,
    required this.altBuffer,
    required this.platform,
    this.type = TerminalKeyEventType.press,
    this.text,
  });

  TerminalKeyboardEvent copyWith({
    TerminalKey? key,
    bool? shift,
    bool? ctrl,
    bool? alt,
    TerminalState? state,
    bool? altBuffer,
    TerminalTargetPlatform? platform,
    TerminalKeyEventType? type,
    String? text,
  }) {
    return TerminalKeyboardEvent(
      key: key ?? this.key,
      shift: shift ?? this.shift,
      ctrl: ctrl ?? this.ctrl,
      alt: alt ?? this.alt,
      state: state ?? this.state,
      altBuffer: altBuffer ?? this.altBuffer,
      platform: platform ?? this.platform,
      type: type ?? this.type,
      text: text ?? this.text,
    );
  }

  @override
  String toString() {
    return 'TerminalKeyboardEvent(key: $key, shift: $shift, ctrl: $ctrl, alt: $alt, state: $state, altBuffer: $altBuffer, platform: $platform, type: $type, text: $text)';
  }
}

/// Translates a keyboard event into an escape sequence for the terminal.
abstract class TerminalInputHandler {
  String? call(TerminalKeyboardEvent event);
}
