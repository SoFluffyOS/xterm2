import 'package:test/test.dart';
import 'package:xterm2/src/core/input/keytab/keytab.dart';
import 'package:xterm2/xterm.dart';

void main() {
  group('defaultInputHandler', () {
    test('supports numpad enter', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.keyInput(TerminalKey.numpadEnter);
      expect(output, ['\r']);
    });

    test('supports DEC application keypad with NumLock compatibility mode', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b=');
      terminal.keyInput(TerminalKey.numpad1);
      terminal.write('\x1b[?1035l');
      terminal.keyInput(TerminalKey.numpad1);
      terminal.keyInput(TerminalKey.numpadAdd);
      terminal.keyInput(TerminalKey.numpadEnter);
      terminal.keyInput(TerminalKey.numpadEqual);
      terminal.keyInput(TerminalKey.numpadComma);
      terminal.write('\x1b[?1035h');
      terminal.keyInput(TerminalKey.numpad1);

      expect(output, ['\x1bOq', '\x1bOk', '\x1bOM', '\x1bOX', '\x1bOl']);
    });

    test('honors ANSI keyboard action mode', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[2h');
      expect(terminal.keyInput(TerminalKey.keyA), isFalse);
      terminal.charInput(0x61, ctrl: true);
      terminal.textInput('text');
      terminal.paste('paste');
      terminal.write('\x1b[2l');
      expect(terminal.keyInput(TerminalKey.numpadEnter), isTrue);

      expect(output, ['\r']);
    });

    test('encodes alt backspace as escape delete', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.backspace, alt: true);

      expect(output, ['\x1b\x7f']);
    });

    test('supports xterm alt escape prefix modes', () {
      final output = <String>[];
      final terminal = Terminal(
        onOutput: output.add,
        platform: TerminalTargetPlatform.linux,
      );

      terminal.keyInput(TerminalKey.keyA, alt: true);
      terminal.write('\x1b[?1036l');
      terminal.keyInput(TerminalKey.keyA, alt: true);
      terminal.write('\x1b[?1036h');
      terminal.keyInput(TerminalKey.keyA, alt: true);

      expect(output, ['\x1bA', '\x1bA']);
    });

    test('supports macOS alt sends escape mode', () {
      final output = <String>[];
      final terminal = Terminal(
        onOutput: output.add,
        platform: TerminalTargetPlatform.macos,
      );

      terminal.keyInput(TerminalKey.keyA, alt: true);
      terminal.write('\x1b[?1039h');
      terminal.keyInput(TerminalKey.keyA, alt: true);
      terminal.write('\x1b[?1039l');
      terminal.keyInput(TerminalKey.keyA, alt: true);

      expect(output, ['\x1bA']);
    });

    test('supports DEC backarrow key mode', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.backspace);
      terminal.write('\x1b[?67h');
      terminal.keyInput(TerminalKey.backspace);
      terminal.keyInput(TerminalKey.backspace, alt: true);
      terminal.write('\x1b[?67l');
      terminal.keyInput(TerminalKey.backspace);

      expect(output, ['\x7f', '\b', '\x1b\b', '\x7f']);
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

    test('supports legacy control punctuation chords', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.keyInput(TerminalKey.space, ctrl: true);
      terminal.keyInput(TerminalKey.bracketLeft, ctrl: true);
      terminal.keyInput(TerminalKey.backslash, ctrl: true);
      terminal.keyInput(TerminalKey.bracketRight, ctrl: true);
      terminal.keyInput(TerminalKey.digit6, ctrl: true, shift: true, text: '^');
      terminal.keyInput(TerminalKey.slash, ctrl: true);
      terminal.keyInput(TerminalKey.minus, ctrl: true, shift: true, text: '_');

      expect(output, ['\x00', '\x1b', '\x1c', '\x1d', '\x1e', '\x1f', '\x1f']);
    });

    test('does not treat Ctrl+Shift+letter as legacy control input', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      final handled =
          terminal.keyInput(TerminalKey.keyA, ctrl: true, shift: true);

      expect(handled, isFalse);
      expect(output, isEmpty);
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

    test('keeps unmodified Kitty control keys legacy', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=1u');
      terminal.keyInput(TerminalKey.enter);
      terminal.keyInput(TerminalKey.backspace);
      terminal.keyInput(TerminalKey.tab);
      terminal.write('\x1b[?67h');
      terminal.keyInput(TerminalKey.backspace);

      expect(output, ['\r', '\x7f', '\t', '\x7f']);
    });

    test('keeps unmodified Kitty control key releases silent', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=3u');
      terminal.keyInput(TerminalKey.enter, type: TerminalKeyEventType.release);
      terminal.keyInput(
        TerminalKey.backspace,
        type: TerminalKeyEventType.release,
      );
      terminal.keyInput(TerminalKey.tab, type: TerminalKeyEventType.release);

      expect(output, isEmpty);
    });

    test('reports unmodified Kitty control key releases in report-all mode',
        () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=11u');
      terminal.keyInput(TerminalKey.enter, type: TerminalKeyEventType.release);
      terminal.keyInput(
        TerminalKey.backspace,
        type: TerminalKeyEventType.release,
      );
      terminal.keyInput(TerminalKey.tab, type: TerminalKeyEventType.release);

      expect(output, ['\x1b[13;1:3u', '\x1b[127;1:3u', '\x1b[9;1:3u']);
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
      terminal.keyInput(TerminalKey.numpadComma);

      expect(output, ['\x1b[57376u', '\x1b[57399;3u', '\x1b[57416u']);
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

    test('omits Kitty associated text for modified keys', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=24u');
      terminal.keyInput(TerminalKey.keyJ, ctrl: true, text: 'j');
      terminal.keyInput(TerminalKey.keyJ, alt: true, text: 'j');
      terminal.keyInput(TerminalKey.keyJ, shift: true, text: 'J');

      expect(output, ['\x1b[106;5u', '\x1b[106;3u', '\x1b[106;2;74u']);
    });

    test('omits Kitty control-character alternates', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[=12u');
      terminal.keyInput(TerminalKey.keyA, text: '\x01');

      expect(output, ['\x1b[97u']);
    });

    test('supports xterm modifyOtherKeys mode 2', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[>4;2m');
      terminal.keyInput(TerminalKey.keyH, ctrl: true, shift: true, text: 'H');
      terminal.keyInput(TerminalKey.digit8, alt: true, text: '8');
      terminal.write('\x1b[>4;0m');
      terminal.keyInput(TerminalKey.keyH, ctrl: true);

      expect(output, ['\x1b[27;6;72~', '\x1b[27;3;56~', '\x08']);
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
