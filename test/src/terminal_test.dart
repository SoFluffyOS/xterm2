import 'package:test/test.dart';
import 'package:xterm/core.dart';

void main() {
  group('Terminal.maxLines', () {
    test('never truncates the viewport', () {
      final terminal = Terminal(maxLines: 2);

      for (var i = 0; i < 39; i++) {
        terminal.write('line $i\r\n');
      }
      terminal.write('line 39');

      expect(terminal.lines.length, terminal.viewHeight);
      expect(terminal.buffer.currentLine.toString(), startsWith('line 39'));

      terminal.resize(80, 30);

      expect(terminal.lines.length, 30);
      expect(terminal.buffer.currentLine.toString(), startsWith('line 39'));
    });
  });

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

  test('Terminal reports OSC 7 current directory URIs', () {
    String? currentDirectory;
    final terminal = Terminal(
      onCurrentDirectoryChange: (uri) => currentDirectory = uri,
    );

    terminal.write('\x1b]7;file://localhost/tmp/my%20project\x1b\\');

    expect(currentDirectory, 'file://localhost/tmp/my%20project');
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

  test('Terminal restores main cursor when leaving 1049 alternate screen', () {
    final terminal = Terminal()..resize(5, 5);

    terminal.write('\x1b[3;4H');
    expect(terminal.buffer.cursorX, 3);
    expect(terminal.buffer.cursorY, 2);

    terminal.write('\x1b[?1049h');
    terminal.write('\x1b[1;1Halt');
    expect(terminal.isUsingAltBuffer, isTrue);
    expect(terminal.buffer.cursorX, 3);
    expect(terminal.buffer.cursorY, 0);

    terminal.write('\x1b[?1049l');

    expect(terminal.isUsingAltBuffer, isFalse);
    expect(terminal.buffer.cursorX, 3);
    expect(terminal.buffer.cursorY, 2);
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

  test('Terminal bounds oversized CSI payloads across chunks', () {
    final terminal = Terminal();

    terminal.write('\x1b[${'1;' * 100}');
    terminal.write('2;' * 100);
    terminal.write('mSafe');

    expect(terminal.buffer.lines[0].toString(), 'Safe');
  });

  test('Terminal ignores incomplete SGR color sequences', () {
    final terminal = Terminal();

    expect(
      () => terminal.write(
        '\x1b[38m'
        '\x1b[38;2;1;2m'
        '\x1b[38;5m'
        '\x1b[48m'
        '\x1b[48;2;1;2m'
        '\x1b[48;5m'
        'Safe',
      ),
      returnsNormally,
    );
    expect(terminal.buffer.lines[0].toString(), 'Safe');
  });

  test('Terminal supports colon-delimited SGR truecolor foreground', () {
    final terminal = Terminal();

    terminal.write('\x1b[38:2:1:2:3mX');

    expect(
      terminal.buffer.lines[0].getForeground(0),
      CellColor.rgb | 0x010203,
    );
  });

  test('Terminal supports colon-delimited SGR truecolor background', () {
    final terminal = Terminal();

    terminal.write('\x1b[48:2:4:5:6mX');

    expect(
      terminal.buffer.lines[0].getBackground(0),
      CellColor.rgb | 0x040506,
    );
  });

  group('Terminal CSI zero defaults', () {
    test('scroll margins treat zero as default', () {
      final terminal = Terminal()..resize(5, 5);

      terminal.write('\x1b[2;4r');
      expect(terminal.buffer.marginTop, 1);
      expect(terminal.buffer.marginBottom, 3);

      terminal.write('\x1b[0;0r');
      expect(terminal.buffer.marginTop, 0);
      expect(terminal.buffer.marginBottom, 4);
    });

    test('scroll margins treat omitted top as one', () {
      final terminal = Terminal()..resize(5, 5);

      terminal.write('\x1b[;3r');

      expect(terminal.buffer.marginTop, 0);
      expect(terminal.buffer.marginBottom, 2);
    });

    test('cursor position treats omitted row as one', () {
      final terminal = Terminal()..resize(5, 3);

      terminal.write('\x1b[;3HX');

      expect(terminal.buffer.lines[0].toString(), 'X');
      expect(terminal.buffer.lines[0].getCodePoint(2), 'X'.codeUnitAt(0));
    });

    test('cursor position treats omitted column as one', () {
      final terminal = Terminal()..resize(5, 3);

      terminal.write('\x1b[2;HX');

      expect(terminal.buffer.lines[1].toString(), 'X');
      expect(terminal.buffer.lines[1].getCodePoint(0), 'X'.codeUnitAt(0));
    });

    test('delete characters treats zero as one', () {
      final terminal = Terminal()..resize(5, 3);

      terminal.write('abcde\r\x1b[2C\x1b[0P');

      expect(terminal.buffer.lines[0].toString(), 'abde');
    });

    test('erase characters treats zero as one', () {
      final terminal = Terminal()..resize(5, 3);

      terminal.write('abcde\r\x1b[2C\x1b[0X');

      expect(terminal.buffer.lines[0].getCodePoint(2), 0);
      expect(terminal.buffer.lines[0].toString(), 'abde');
    });

    test('insert blank characters treats zero as one', () {
      final terminal = Terminal()..resize(5, 3);

      terminal.write('abcde\r\x1b[2C\x1b[0@');

      expect(terminal.buffer.lines[0].getCodePoint(2), 0);
      expect(terminal.buffer.lines[0].toString(), 'abcd');
    });

    test('insert lines treats zero as one', () {
      final terminal = Terminal()..resize(5, 5);
      terminal.write('one\r\ntwo\r\nthree');

      terminal.setCursor(0, 1);
      terminal.write('\x1b[0L');

      expect(terminal.buffer.lines[0].toString(), 'one');
      expect(terminal.buffer.lines[1].toString(), '');
      expect(terminal.buffer.lines[2].toString(), 'two');
    });

    test('delete lines treats zero as one', () {
      final terminal = Terminal()..resize(5, 5);
      terminal.write('one\r\ntwo\r\nthree');

      terminal.setCursor(0, 1);
      terminal.write('\x1b[0M');

      expect(terminal.buffer.lines[0].toString(), 'one');
      expect(terminal.buffer.lines[1].toString(), 'three');
      expect(terminal.buffer.lines[2].toString(), '');
    });
  });

  test('Terminal stores and closes OSC 8 hyperlinks in packed cells', () {
    final terminal = Terminal();

    terminal.write(
      '\x1b]8;id=docs;https://example.com/a;b\x1b\\'
      'link'
      '\x1b[0m'
      '\x1b]8;;\x1b\\ plain',
    );

    for (var column = 0; column < 4; column++) {
      expect(
        terminal.hyperlinkAt(CellOffset(column, 0)),
        'https://example.com/a;b',
      );
    }
    expect(terminal.hyperlinkAt(const CellOffset(4, 0)), isNull);
  });

  test('Terminal preserves OSC 8 hyperlinks across wrapped lines', () {
    final terminal = Terminal()..resize(3, 3);

    terminal.write('\x1b]8;;https://example.com\x1b\\abcdef\x1b]8;;\x1b\\');

    expect(
      terminal.hyperlinkAt(const CellOffset(0, 0)),
      'https://example.com',
    );
    expect(
      terminal.hyperlinkAt(const CellOffset(0, 1)),
      'https://example.com',
    );
  });

  test('Terminal clears OSC 8 metadata when linked cells are erased', () {
    final terminal = Terminal()
      ..write('\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\');

    terminal.write('\r\x1b[2K');

    expect(terminal.hyperlinkAt(const CellOffset(0, 0)), isNull);
  });

  test('Terminal bounds the OSC 8 hyperlink registry', () {
    final terminal = Terminal(maxLines: 100);
    for (var index = 0; index < 4096; index++) {
      terminal.write(
        '\x1b]8;;https://example.com/$index\x1b\\x\x1b]8;;\x1b\\',
      );
    }

    final overflowPosition = CellOffset(
      terminal.buffer.cursorX,
      terminal.buffer.absoluteCursorY,
    );
    terminal.write(
      '\x1b]8;;https://example.com/overflow\x1b\\x\x1b]8;;\x1b\\',
    );

    expect(terminal.hyperlinkAt(overflowPosition), isNull);
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
