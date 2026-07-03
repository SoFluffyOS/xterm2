import 'package:test/test.dart';
import 'package:xterm/core.dart';

void main() {
  group('Terminal.inputHandler', () {
    test('can be set to null', () {
      final terminal = Terminal(inputHandler: null);
      expect(() => terminal.keyInput(TerminalKey.keyA), returnsNormally);
    });

    test('can be changed', () {
      final handler1 = _TestInputHandler();
      final handler2 = _TestInputHandler();
      final terminal = Terminal(inputHandler: handler1);

      terminal.keyInput(TerminalKey.keyA);
      expect(handler1.events, isNotEmpty);

      terminal.inputHandler = handler2;

      terminal.keyInput(TerminalKey.keyA);
      expect(handler2.events, isNotEmpty);
    });
  });

  group('Terminal.mouseInput', () {
    test('can handle mouse events', () {
      final output = <String>[];

      final terminal = Terminal(onOutput: output.add);

      terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(10, 10),
      );

      expect(output, isEmpty);

      // enable mouse reporting
      terminal.write('\x1b[?1000h');

      terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(10, 10),
      );

      expect(output, ['\x1B[M +,']);
    });
  });

  group('Terminal.reflowEnabled', () {
    test('prevents reflow when set to false', () {
      final terminal = Terminal(reflowEnabled: false);

      terminal.write('Hello World');
      terminal.resize(5, 5);

      expect(terminal.buffer.lines[0].toString(), 'Hello');
      expect(terminal.buffer.lines[1].toString(), isEmpty);
    });

    test('preserves hidden cells when reflow is disabled', () {
      final terminal = Terminal(reflowEnabled: false);

      terminal.write('Hello World');
      terminal.resize(5, 5);
      terminal.resize(20, 5);

      expect(terminal.buffer.lines[0].toString(), 'Hello World');
      expect(terminal.buffer.lines[1].toString(), isEmpty);
    });

    test('can be set at runtime', () {
      final terminal = Terminal(reflowEnabled: true);

      terminal.resize(5, 5);
      terminal.write('Hello World');
      terminal.reflowEnabled = false;
      terminal.resize(20, 5);

      expect(terminal.buffer.lines[0].toString(), 'Hello');
      expect(terminal.buffer.lines[1].toString(), ' Worl');
      expect(terminal.buffer.lines[2].toString(), 'd');
    });
  });

  group('Terminal.mouseInput', () {
    test('applys to the main buffer', () {
      final terminal = Terminal(
        wordSeparators: {
          'z'.codeUnitAt(0),
        },
      );

      expect(
        terminal.mainBuffer.wordSeparators,
        contains('z'.codeUnitAt(0)),
      );
    });

    test('applys to the alternate buffer', () {
      final terminal = Terminal(
        wordSeparators: {
          'z'.codeUnitAt(0),
        },
      );

      expect(
        terminal.altBuffer.wordSeparators,
        contains('z'.codeUnitAt(0)),
      );
    });
  });

  group('Terminal.onPrivateOSC', () {
    test(r'works with \a end', () {
      String? lastCode;
      List<String>? lastData;

      final terminal = Terminal(
        onPrivateOSC: (String code, List<String> data) {
          lastCode = code;
          lastData = data;
        },
      );

      terminal.write('\x1b]6\x07');

      expect(lastCode, '6');
      expect(lastData, []);

      terminal.write('\x1b]66;hello world\x07');

      expect(lastCode, '66');
      expect(lastData, ['hello world']);

      terminal.write('\x1b]666;hello;world\x07');

      expect(lastCode, '666');
      expect(lastData, ['hello', 'world']);

      terminal.write('\x1b]hello;world\x07');

      expect(lastCode, 'hello');
      expect(lastData, ['world']);
    });

    test(r'works with \x1b\ end', () {
      String? lastCode;
      List<String>? lastData;

      final terminal = Terminal(
        onPrivateOSC: (String code, List<String> data) {
          lastCode = code;
          lastData = data;
        },
      );

      terminal.write('\x1b]6\x1b\\');

      expect(lastCode, '6');
      expect(lastData, []);

      terminal.write('\x1b]66;hello world\x1b\\');

      expect(lastCode, '66');
      expect(lastData, ['hello world']);

      terminal.write('\x1b]666;hello;world\x1b\\');

      expect(lastCode, '666');
      expect(lastData, ['hello', 'world']);

      terminal.write('\x1b]hello;world\x1b\\');

      expect(lastCode, 'hello');
      expect(lastData, ['world']);
    });

    test('do not receive common osc', () {
      String? lastCode;
      List<String>? lastData;

      final terminal = Terminal(
        onPrivateOSC: (String code, List<String> data) {
          lastCode = code;
          lastData = data;
        },
      );

      terminal.write('\x1b]0;hello world\x07');

      expect(lastCode, isNull);
      expect(lastData, isNull);
    });
  });

  group('Terminal synchronized updates', () {
    test('coalesces redraws until the update ends', () {
      final terminal = Terminal();
      var redraws = 0;
      terminal.addListener(() => redraws++);

      terminal.write('\x1b[?2026hfirst');
      terminal.write(' second');
      expect(redraws, 0);
      expect(terminal.buffer.lines[0].toString(), 'first second');

      terminal.write('\x1b[?2026l');
      expect(redraws, 1);
    });

    test('forces a redraw when an application omits the terminator', () async {
      final terminal = Terminal();
      var redraws = 0;
      terminal.addListener(() => redraws++);

      terminal.write('\x1b[?2026hstalled');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(redraws, 1);
      terminal.write(' recovered');
      expect(redraws, 2);
    });
  });

  test('Terminal reports focus only when DEC focus mode is enabled', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.focusInput(true);
    expect(output, isEmpty);

    terminal.write('\x1b[?1004h');
    terminal.focusInput(true);
    terminal.focusInput(false);
    expect(output, ['\x1b[I', '\x1b[O']);

    terminal.write('\x1b[?1004l');
    terminal.focusInput(true);
    expect(output, hasLength(2));
  });

  test('Terminal applies DECSCUSR cursor shape and blinking state', () {
    final terminal = Terminal();

    terminal.write('\x1b[3 q');
    expect(terminal.applicationCursorType, TerminalCursorType.underline);
    expect(terminal.cursorBlinkMode, isTrue);

    terminal.write('\x1b[6 q');
    expect(terminal.applicationCursorType, TerminalCursorType.verticalBar);
    expect(terminal.cursorBlinkMode, isFalse);

    terminal.write('\x1b[2 q');
    expect(terminal.applicationCursorType, TerminalCursorType.block);
    expect(terminal.cursorBlinkMode, isFalse);
  });

  test('Terminal bounds oversized OSC payloads across chunks', () {
    final privateOsc = <String>[];
    final terminal = Terminal(
      onPrivateOSC: (code, args) => privateOsc.add('$code;${args.join(';')}'),
    );

    terminal.write('\x1b]999;${'x' * 700}');
    terminal.write('y' * 700);
    terminal.write('\x07safe');

    expect(privateOsc, isEmpty);
    expect(terminal.buffer.lines[0].toString(), 'safe');
  });

  test('Terminal terminates oversized OSC discard state with split ST', () {
    final terminal = Terminal();

    terminal.write('\x1b]999;${'x' * 1100}\x1b');
    terminal.write('\\safe');

    expect(terminal.buffer.lines[0].toString(), 'safe');
  });
}

class _TestInputHandler implements TerminalInputHandler {
  final events = <TerminalKeyboardEvent>[];

  @override
  String? call(TerminalKeyboardEvent event) {
    events.add(event);
    return null;
  }
}
