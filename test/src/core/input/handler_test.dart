import 'package:test/test.dart';
import 'package:xterm/src/core/input/keytab/keytab.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('defaultInputHandler', () {
    test('supports numpad enter', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.keyInput(TerminalKey.numpadEnter);
      expect(output, ['\r']);
    });

    test('encodes alt backspace as escape delete', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.backspace, alt: true);

      expect(output, ['\x1b\x7f']);
    });

    test('keeps cursor keys normal in application keypad mode', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b=');
      terminal.keyInput(TerminalKey.arrowUp);

      expect(output, ['\x1b[A']);
    });

    test('uses application cursor keys in DECCKM mode', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?1h');
      terminal.keyInput(TerminalKey.arrowUp);

      expect(output, ['\x1bOA']);
    });

    test('keeps legacy control encoding when Kitty mode is disabled', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.keyA, ctrl: true);

      expect(output, ['\x01']);
    });

    test('disambiguates modified textual keys in Kitty mode', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=1u');
      terminal.keyInput(TerminalKey.keyA, ctrl: true);
      terminal.keyInput(TerminalKey.escape);

      expect(output, ['\x1b[97;5u', '\x1b[27u']);
    });

    test('reports all textual keys as Kitty escape sequences', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=8u');
      terminal.keyInput(TerminalKey.keyA);
      terminal.keyInput(TerminalKey.digit0, shift: true);

      expect(output, ['\x1b[97u', '\x1b[48;2u']);
    });

    test('encodes escape when Kitty event reporting is enabled', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=2u');
      terminal.keyInput(TerminalKey.escape);

      expect(output, ['\x1b[27u']);
    });

    test('disambiguates shifted control keys in Kitty mode', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=1u');
      terminal.keyInput(TerminalKey.backspace, shift: true);
      terminal.keyInput(TerminalKey.enter, shift: true);
      terminal.keyInput(TerminalKey.tab, shift: true);

      expect(output, ['\x1b[127;2u', '\x1b[13;2u', '\x1b[9;2u']);
    });

    test('reports Kitty alternate key codes', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=12u');
      terminal.keyInput(TerminalKey.keyA, shift: true);

      expect(output, ['\x1b[97:65;2u']);
    });

    test('uses Kitty functional and numpad key codes', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=1u');
      terminal.keyInput(TerminalKey.f13);
      terminal.keyInput(TerminalKey.numpad0, alt: true);

      expect(output, ['\x1b[57376u', '\x1b[57399;3u']);
    });

    test('reports Kitty repeat and release events', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=3u');
      terminal.keyInput(
        TerminalKey.keyA,
        ctrl: true,
        type: TerminalKeyEventType.repeat,
      );
      terminal.keyInput(
        TerminalKey.keyA,
        type: TerminalKeyEventType.release,
      );
      terminal.keyInput(
        TerminalKey.arrowUp,
        type: TerminalKeyEventType.release,
      );

      expect(output, ['\x1b[97;5:2u', '\x1b[97;1:3u', '\x1b[1;1:3A']);
    });

    test('does not emit key releases outside Kitty event reporting', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      final handled = terminal.keyInput(
        TerminalKey.arrowUp,
        type: TerminalKeyEventType.release,
      );

      expect(handled, isFalse);
      expect(output, isEmpty);
    });

    test('reports associated text codepoints', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=24u');
      terminal.keyInput(TerminalKey.keyA, text: 'a');
      terminal.keyInput(TerminalKey.none, text: 'é');

      expect(output, ['\x1b[97;1;97u', '\x1b[233;1;233u']);
    });
  });

  group('KeytabInputHandler', () {
    test('can insert modifier code', () {
      final handler = KeytabInputHandler(
        Keytab.parse(r'key Home +AnyMod : "\E[1;*H"'),
      );

      final terminal = Terminal(inputHandler: handler);

      late String output;

      terminal.onOutput = (data) {
        output = data;
      };

      terminal.keyInput(TerminalKey.home, ctrl: true);

      expect(output, '\x1b[1;5H');

      terminal.keyInput(TerminalKey.home, shift: true);

      expect(output, '\x1b[1;2H');
    });
  });
}
