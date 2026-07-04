import 'package:test/test.dart';
import 'package:xterm/core.dart';

void main() {
  test('Terminal sets a horizontal tab stop at the cursor', () {
    final terminal = Terminal()..resize(20, 5);

    terminal.write('\x1b[3gabc\x1bH\r\t');

    expect(terminal.buffer.cursorX, 3);
  });

  test('Terminal applies a full reset', () {
    final terminal = Terminal()..resize(20, 5);
    terminal.write(
      '\x1b[?1h\x1b[?7l\x1b[?25l\x1b[4h\x1b[5m'
      '\x1b[3gabc\x1bH\x1b[?1049hcontent\x1bc',
    );

    expect(terminal.isUsingAltBuffer, isFalse);
    expect(
      terminal.buffer.lines.toList().every((line) => line.getText().isEmpty),
      isTrue,
    );
    expect(terminal.buffer.cursorX, 0);
    expect(terminal.buffer.cursorY, 0);
    expect(terminal.cursorKeysMode, isFalse);
    expect(terminal.autoWrapMode, isTrue);
    expect(terminal.cursorVisibleMode, isTrue);
    expect(terminal.insertMode, isFalse);
    expect(terminal.cursor.attrs, 0);

    terminal.write('\t');
    expect(terminal.buffer.cursorX, 8);
  });

  test('Terminal applies a DEC soft reset', () {
    final terminal = Terminal()..resize(20, 5);

    terminal.write(
      '\x1b[?1h\x1b[?7l\x1b[4h\x1b[5m\x1b[2;4rcontent\x1b[!p',
    );

    expect(terminal.buffer.lines[0].toString(), 'content');
    expect(terminal.cursorKeysMode, isFalse);
    expect(terminal.autoWrapMode, isTrue);
    expect(terminal.insertMode, isFalse);
    expect(terminal.cursor.attrs, 0);
    expect(terminal.buffer.marginTop, 0);
    expect(terminal.buffer.marginBottom, terminal.viewHeight - 1);
  });

  test('Terminal applies the DEC screen alignment test', () {
    final terminal = Terminal(maxLines: 10)..resize(4, 2);
    terminal.write('scrollback\ncontent');
    final scrollbackText = terminal.buffer.lines[0].toString();
    terminal.write('\x1b#');
    terminal.write('8');

    expect(terminal.buffer.lines[0].toString(), scrollbackText);
    expect(
      terminal.buffer.lines
          .toList()
          .skip(terminal.buffer.scrollBack)
          .map((line) => line.toString()),
      everyElement('EEEE'),
    );
    expect(
      terminal.buffer.lines[terminal.buffer.lines.length - 1].getAttributes(0),
      0,
    );
  });

  test('Terminal applies DECCOLM screen reset side effects', () {
    final terminal = Terminal(maxLines: 10)..resize(4, 2);
    terminal.write('scrollback\n\x1b[31;44mcontent\x1b[2;2r\x1b[2;3H');
    final scrollback = terminal.buffer.lines
        .toList()
        .take(terminal.buffer.scrollBack)
        .map((line) => line.toString())
        .toList();

    terminal.write('\x1b[?3h');

    expect(
      terminal.buffer.lines
          .toList()
          .take(terminal.buffer.scrollBack)
          .map((line) => line.toString()),
      scrollback,
    );
    expect(
      terminal.buffer.lines
          .toList()
          .skip(terminal.buffer.scrollBack)
          .every((line) => line.toString().isEmpty),
      isTrue,
    );
    expect(terminal.buffer.cursorX, 0);
    expect(terminal.buffer.cursorY, 0);
    expect(terminal.buffer.marginTop, 0);
    expect(terminal.buffer.marginBottom, terminal.viewHeight - 1);
    expect(
      terminal.buffer.lines[terminal.buffer.lines.length - 1].getAttributes(0),
      0,
    );
  });

  test('Terminal dispose clears listeners and stops deferred updates',
      () async {
    var updates = 0;
    final terminal = Terminal()..addListener(() => updates++);

    terminal.write('\x1b[?2026h');
    terminal.dispose();
    terminal.write('ignored');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(updates, 0);
    expect(terminal.buffer.currentLine.toString(), isEmpty);
  });

  test('Terminal applies partial and zero cursor positions', () {
    final terminal = Terminal()..resize(20, 10);

    terminal.write('\x1b[5H');
    expect(terminal.buffer.cursorX, 0);
    expect(terminal.buffer.cursorY, 4);

    terminal.write('\x1b[0;0H');
    expect(terminal.buffer.cursorX, 0);
    expect(terminal.buffer.cursorY, 0);

    terminal.write('\x1b[0d');
    expect(terminal.buffer.cursorY, 0);
  });

  test('Terminal treats rapid blink SGR as blinking text', () {
    final terminal = Terminal()..resize(20, 5);

    terminal.write('\x1b[6mrapid');

    expect(terminal.cursor.isBlink, isTrue);
  });

  test('Terminal allocates two cells for modern Unicode emoji', () {
    final terminal = Terminal()..resize(10, 2);

    terminal.write('\u{1FAE0}x');

    final line = terminal.buffer.lines[0];
    expect(line.getWidth(0), 2);
    expect(line.getWidth(1), 0);
    expect(line.getCodePoint(2), 0x78);
  });

  test('Terminal attaches modern Unicode combining marks', () {
    final terminal = Terminal()..resize(10, 2);

    terminal.write('a\u{1E2AE}x');

    final line = terminal.buffer.lines[0];
    expect(line.getCombiningCharacters(0), '\u{1E2AE}');
    expect(line.getCodePoint(1), 0x78);
  });

  test('Terminal resets bold and faint intensity with SGR 22', () {
    final terminal = Terminal()..resize(20, 5);

    terminal.write('\x1b[1;2mbold-faint\x1b[22mplain');

    final styledAttrs = terminal.buffer.lines[0].getAttributes(0);
    expect(styledAttrs & CellAttr.bold, isNot(0));
    expect(styledAttrs & CellAttr.faint, isNot(0));
    expect(terminal.cursor.isBold, isFalse);
    expect(terminal.cursor.isFaint, isFalse);
  });

  test('Terminal applies overline SGR', () {
    final terminal = Terminal()..resize(20, 5);

    terminal.write('\x1b[53mover\x1b[55mplain');

    expect(
      terminal.buffer.lines[0].getAttributes(0) & CellAttr.overline,
      isNot(0),
    );
    expect(terminal.cursor.isOverline, isFalse);
  });

  test('Terminal applies double underline SGR', () {
    final terminal = Terminal()..resize(20, 5);

    terminal.write('\x1b[21mdouble\x1b[24mplain');

    expect(
      terminal.buffer.lines[0].getAttributes(0) & CellAttr.doubleUnderline,
      isNot(0),
    );
    expect(terminal.cursor.isDoubleUnderline, isFalse);
  });

  test('Terminal applies colon underline style SGR', () {
    final terminal = Terminal()..resize(20, 5);

    terminal
        .write('\x1b[4:3mcurly\x1b[4:4mdotted\x1b[4:5mdashed\x1b[4:0mplain');

    final line = terminal.buffer.lines[0];
    expect(line.getAttributes(0) & CellAttr.undercurl, isNot(0));
    expect(line.getAttributes(5) & CellAttr.dottedUnderline, isNot(0));
    expect(line.getAttributes(11) & CellAttr.dashedUnderline, isNot(0));
    expect(terminal.cursor.isDashedUnderline, isFalse);
  });

  test('Terminal keeps semicolon underline and italic SGR distinct', () {
    final terminal = Terminal()..resize(20, 5);

    terminal.write('\x1b[4;3mtext');

    final attrs = terminal.buffer.lines[0].getAttributes(0);
    expect(attrs & CellAttr.underline, isNot(0));
    expect(attrs & CellAttr.italic, isNot(0));
    expect(attrs & CellAttr.undercurl, 0);
  });

  test('Terminal applies underline color SGR', () {
    final terminal = Terminal()..resize(20, 5);

    terminal.write('\x1b[4;58;2;12;34;56mcolor\x1b[59mplain');

    expect(
      terminal.buffer.lines[0].getUnderlineColor(0),
      equals(0x0c2238 | CellColor.rgb),
    );
    expect(terminal.cursor.underlineColor, 0);
  });

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
    test('filters mouse motion according to tracking mode', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?1002h\x1b[?1006h');
      expect(
        terminal.mouseInput(
          TerminalMouseButton.none,
          TerminalMouseButtonState.down,
          CellOffset(1, 2),
          motion: true,
        ),
        isFalse,
      );
      expect(
        terminal.mouseInput(
          TerminalMouseButton.left,
          TerminalMouseButtonState.down,
          CellOffset(1, 2),
          motion: true,
        ),
        isTrue,
      );

      terminal.write('\x1b[?1003h');
      expect(
        terminal.mouseInput(
          TerminalMouseButton.none,
          TerminalMouseButtonState.down,
          CellOffset(2, 3),
          motion: true,
        ),
        isTrue,
      );
      expect(output, ['\x1b[<32;2;3M', '\x1b[<35;3;4M']);
    });

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

      expect(output, ['\x1B[M ++']);
    });

    test('reports mouse modifiers', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?1000h\x1b[?1006h');
      terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        modifiers: const TerminalMouseModifiers(
          shift: true,
          control: true,
        ),
      );

      expect(output, ['\x1B[<20;1;1M']);
    });

    test('reports sgr pixel mouse coordinates', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?1000h\x1b[?1016h');
      terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(2, 3),
        pixelPosition: CellOffset(20, 30),
      );

      expect(output, ['\x1B[<0;21;31M']);
    });

    test('ignores invalid collapsed mouse mode', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?10061000h');
      terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(10, 10),
      );

      expect(output, isEmpty);
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

  test('Terminal applies and resets OSC color overrides', () {
    final terminal = Terminal();

    terminal.write(
      '\x1b]4;1;#abc;42;rgb:ffff/8000/0000\x1b\\'
      '\x1b]10;#112233;#445566;#778899\x1b\\',
    );

    expect(
      Map<int, int>.fromEntries(terminal.indexedColorOverrides),
      {1: 0xaabbcc, 42: 0xff8000},
    );
    expect(terminal.foregroundColorOverride, 0x112233);
    expect(terminal.backgroundColorOverride, 0x445566);
    expect(terminal.cursorColorOverride, 0x778899);

    terminal.write(
      '\x1b]104;1\x1b\\'
      '\x1b]110\x1b\\'
      '\x1b]111\x1b\\'
      '\x1b]112\x1b\\',
    );

    expect(
      Map<int, int>.fromEntries(terminal.indexedColorOverrides),
      {42: 0xff8000},
    );
    expect(terminal.foregroundColorOverride, isNull);
    expect(terminal.backgroundColorOverride, isNull);
    expect(terminal.cursorColorOverride, isNull);

    terminal.write('\x1b]104\x1b\\');
    expect(terminal.indexedColorOverrides, isEmpty);
  });

  test('Terminal ignores malformed OSC colors', () {
    final terminal = Terminal();

    terminal.write(
      '\x1b]4;1;#12;300;#ffffff\x1b\\'
      '\x1b]10;rgb:gg/00/00\x1b\\',
    );

    expect(terminal.indexedColorOverrides, isEmpty);
    expect(terminal.foregroundColorOverride, isNull);
    expect(terminal.colorRevision, 0);
  });

  test('Terminal answers OSC color queries', () {
    final output = <String>[];
    final terminal = Terminal(
      onOutput: output.add,
      onColorQuery: (code, index) {
        if (code == 4 && index == 2) return 0x123456;
        if (code == 11) return 0xabcdef;
        return null;
      },
    );
    terminal.write('\x1b]4;1;#010203\x1b\\');

    terminal.write(
      '\x1b]4;1;?;2;?\x1b\\'
      '\x1b]11;?\x1b\\'
      '\x1b]12;?\x1b\\',
    );

    expect(output, [
      '\x1b]4;1;rgb:0101/0202/0303\x1b\\',
      '\x1b]4;2;rgb:1212/3434/5656\x1b\\',
      '\x1b]11;rgb:abab/cdcd/efef\x1b\\',
    ]);
  });

  test('Terminal applies bulk OSC palette updates', () {
    final terminal = Terminal();
    final sequence = StringBuffer('\x1b]4');
    for (var index = 0; index < 32; index++) {
      sequence.write(';$index;#${index.toRadixString(16).padLeft(6, '0')}');
    }
    sequence.write('\x1b\\');

    terminal.write(sequence.toString());

    expect(terminal.indexedColorOverrides.length, 32);
    expect(
      Map<int, int>.fromEntries(terminal.indexedColorOverrides)[31],
      0x00001f,
    );
  });

  test('Terminal handles OSC 52 clipboard store and query', () async {
    final stores = <(String, String)>[];
    final output = <String>[];
    final terminal = Terminal(
      onOutput: output.add,
      onClipboardStore: (selector, text) => stores.add((selector, text)),
      onClipboardQuery: (selector) => switch (selector) {
        'c' => 'paste me',
        _ => null,
      },
    );

    terminal.write('\x1b]52;c;Y29weSBtZQ==\x1b\\');
    terminal.write('\x1b]52;p;cHJpbWFyeQ==\x1b\\');
    terminal.write('\x1b]52;x;aWdub3JlZA==\x1b\\');
    terminal.write('\x1b]52;c;?\x1b\\');
    await Future<void>.delayed(Duration.zero);

    expect(stores, [('c', 'copy me'), ('s', 'primary')]);
    expect(output, ['\x1b]52;c;cGFzdGUgbWU=\x1b\\']);
  });

  test('Terminal ignores malformed OSC 52 payloads', () {
    final stores = <(String, String)>[];
    final terminal = Terminal(
      onClipboardStore: (selector, text) => stores.add((selector, text)),
    );

    terminal.write('\x1b]52;c;not base64\x1b\\');
    terminal.write('\x1b]52;x;Y29weQ==\x1b\\');

    expect(stores, isEmpty);
  });

  test('Terminal discards unsupported DCS payloads until terminator', () {
    final terminal = Terminal();

    terminal.write('before\x1bPqbinary;data');
    terminal.write('\x1b\\after');

    expect(terminal.buffer.lines[0].toString(), 'beforeafter');
  });

  test('Terminal discards unsupported APC PM and SOS payloads', () {
    final terminal = Terminal();

    terminal.write('a\x1b_payload\x1b\\b');
    terminal.write('\x1b^payload\x07c');
    terminal.write('\x1bXpayload\x1b\\d');

    expect(terminal.buffer.lines[0].toString(), 'abcd');
  });

  test('Terminal paste sanitizes bracketed and non-bracketed payloads', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.paste('a\nb\r\nc');
    terminal.write('\x1b[?2004h');
    terminal.paste('safe\x1b[201~\x03');

    expect(output, [
      'a\rb\rc',
      '\x1b[200~safe[201~\x1b[201~',
    ]);
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

  test('Terminal reports ANSI and DEC private mode state', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.write(
      '\x1b[4h'
      '\x1b[4\x24p'
      '\x1b[20\x24p'
      '\x1b[?7\x24p'
      '\x1b[?25l'
      '\x1b[?25\x24p'
      '\x1b[?9999\x24p',
    );

    expect(output, [
      '\x1b[4;1\x24y',
      '\x1b[20;2\x24y',
      '\x1b[?7;1\x24y',
      '\x1b[?25;2\x24y',
      '\x1b[?9999;0\x24y',
    ]);
  });

  test('Terminal negotiates Kitty keyboard modes', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.write('\x1b[=1u');
    expect(terminal.kittyKeyboardMode, 1);

    terminal.write('\x1b[=2;2u');
    expect(terminal.kittyKeyboardMode, 3);

    terminal.write('\x1b[=1;3u');
    expect(terminal.kittyKeyboardMode, 2);

    terminal.write('\x1b[?u');
    expect(output, ['\x1b[?2u']);
  });

  test('Terminal pushes and pops Kitty keyboard mode stack', () {
    final terminal = Terminal();

    terminal.write('\x1b[>1u\x1b[>3u');
    expect(terminal.kittyKeyboardMode, 3);

    terminal.write('\x1b[<u');
    expect(terminal.kittyKeyboardMode, 1);

    terminal.write('\x1b[<99u');
    expect(terminal.kittyKeyboardMode, 0);
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

  test('Terminal applies application keypad mode escapes', () {
    final terminal = Terminal();

    terminal.write('\x1b=');
    expect(terminal.appKeypadMode, isTrue);

    terminal.write('\x1b>');
    expect(terminal.appKeypadMode, isFalse);
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
