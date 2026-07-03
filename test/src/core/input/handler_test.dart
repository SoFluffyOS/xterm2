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
