import 'package:test/test.dart';
import 'package:xterm/core.dart';

void main() {
  test('Terminal sets a horizontal tab stop at the cursor', () {
    final terminal = Terminal()..resize(20, 5);

    terminal.write('\x1b[3gabc\x1bH\r\t');

    expect(terminal.buffer.cursorX, 3);
  });

  test('Terminal applies cursor tabulation control', () {
    final clearAllTerminal = Terminal()..resize(20, 5);
    clearAllTerminal.write('\x1b[3g\x1b[5W\t');
    expect(clearAllTerminal.buffer.cursorX, 19);

    final resetTerminal = Terminal()..resize(20, 5);
    resetTerminal.write('\x1b[3g\x1b[?5W\t');
    expect(resetTerminal.buffer.cursorX, 8);

    final setTerminal = Terminal()..resize(20, 5);
    setTerminal.write('\x1b[5W\x1b[12G\x1b[W\r\t');
    expect(setTerminal.buffer.cursorX, 11);

    final clearCurrentTerminal = Terminal()..resize(20, 5);
    clearCurrentTerminal.write('\x1b[5W\x1b[12G\x1b[W\x1b[2W\r\t');
    expect(clearCurrentTerminal.buffer.cursorX, 19);
  });

  test('Terminal moves across multiple horizontal tab stops', () {
    final terminal = Terminal()..resize(20, 3);

    terminal.write('\x1b[2I');
    expect(terminal.buffer.cursorX, 16);

    terminal.write('\x1b[Z');
    expect(terminal.buffer.cursorX, 8);

    terminal.write('\x1b[9Z');
    expect(terminal.buffer.cursorX, 0);

    terminal.write('\x1b[9I');
    expect(terminal.buffer.cursorX, 19);
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

  test('Terminal restores origin mode with saved cursor', () {
    final terminal = Terminal()..resize(8, 4);

    terminal.write('\x1b[?69h\x1b[3;6s\x1b[2;4r\x1b[?6h');
    terminal.saveCursor();
    terminal.write('\x1b[?6l');
    terminal.restoreCursor();
    terminal.write('\x1b[1;1HX');

    expect(terminal.originMode, true);
    expect(terminal.buffer.lines[1].getCodePoint(2), 0x58);
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

  test('Terminal constrains origin-mode cursor movement to margins', () {
    final terminal = Terminal()..resize(10, 6);

    terminal.write('\x1b[2;5r');
    expect(terminal.buffer.cursorX, 0);
    expect(terminal.buffer.cursorY, 0);

    terminal.write('\x1b[?6h');
    expect(terminal.buffer.cursorY, 1);

    terminal.write('\x1b[99B');
    expect(terminal.buffer.cursorY, 4);

    terminal.write('\x1b[99A');
    expect(terminal.buffer.cursorY, 1);

    terminal.write('\x1b[2d');
    expect(terminal.buffer.cursorY, 2);

    terminal.write('\x1b[?6l');
    expect(terminal.buffer.cursorY, 0);
  });

  test('Terminal relative cursor movement respects scrolling margins', () {
    final terminal = Terminal()..resize(10, 6);

    terminal.write('\x1b[2;5r\x1b[3;1H\x1b[99A');
    expect(terminal.buffer.cursorY, 1);

    terminal.write('\x1b[99B');
    expect(terminal.buffer.cursorY, 4);

    terminal.write('\x1b[1;1H\x1b[99A');
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

  test('Terminal VS16 expands an emoji grapheme to two cells', () {
    final terminal = Terminal()..resize(10, 2);

    terminal.write('\u2764\ufe0fx');

    final line = terminal.buffer.lines[0];
    expect(line.getWidth(0), 2);
    expect(line.getWidth(1), 0);
    expect(line.getCombiningCharacters(0), '\ufe0f');
    expect(line.getCodePoint(2), 0x78);
  });

  test('Terminal VS15 narrows a wide emoji grapheme', () {
    final terminal = Terminal()..resize(10, 2);

    terminal.write('\u231a\ufe0ex');

    final line = terminal.buffer.lines[0];
    expect(line.getWidth(0), 1);
    expect(line.getCombiningCharacters(0), '\ufe0e');
    expect(line.getCodePoint(1), 0x78);
  });

  test('Terminal can disable grapheme width adjustment', () {
    final terminal = Terminal()..resize(10, 2);

    terminal.write('\x1b[?2027l\u2764\ufe0fx');

    final line = terminal.buffer.lines[0];
    expect(line.getWidth(0), 1);
    expect(line.getCodePoint(1), 0x78);
  });

  test('Terminal ignores emoji variation selectors on invalid bases', () {
    final terminal = Terminal()..resize(10, 2);

    terminal.write('x\ufe0fy');

    final line = terminal.buffer.lines[0];
    expect(line.getWidth(0), 1);
    expect(line.getCombiningCharacters(0), isNull);
    expect(line.getCodePoint(1), 0x79);
  });

  test('Terminal disables extended grapheme joining with mode 2027', () {
    final terminal = Terminal()..resize(12, 2);

    terminal.write('\x1b[?2027l\u{1F468}\u200d\u{1F469}');

    final line = terminal.buffer.lines[0];
    expect(line.getCodePoint(0), 0x1F468);
    expect(line.getCodePoint(2), 0x1F469);
    expect(terminal.buffer.cursorX, 4);
  });

  test('Terminal wraps a VS16-expanded grapheme at the right edge', () {
    final terminal = Terminal()..resize(3, 2);

    terminal.write('ab\u2764\ufe0f');

    expect(terminal.buffer.lines[0].toString(), 'ab');
    final wrappedLine = terminal.buffer.lines[1];
    expect(wrappedLine.isWrapped, isTrue);
    expect(wrappedLine.getCodePoint(0), 0x2764);
    expect(wrappedLine.getWidth(0), 2);
    expect(wrappedLine.getCombiningCharacters(0), '\ufe0f');
    expect(terminal.buffer.cursorX, 2);
  });

  test('Terminal drops VS16-expanded graphemes that cannot fit', () {
    final terminal = Terminal()..resize(1, 2);

    terminal.write('\u2764\ufe0fx');

    final firstLine = terminal.buffer.lines[0];
    final secondLine = terminal.buffer.lines[1];
    expect(firstLine.getCodePoint(0), 0x2764);
    expect(firstLine.getWidth(0), 1);
    expect(firstLine.getCombiningCharacters(0), isNull);
    expect(secondLine.getCodePoint(0), 0x78);
    expect(secondLine.getWidth(0), 1);
    expect(terminal.buffer.cursorX, 0);
  });

  test('Terminal expands width when a ZWJ grapheme gains a wide codepoint', () {
    final terminal = Terminal()..resize(10, 2);

    terminal.write('\u2764\u200d\u{1F525}x');

    final line = terminal.buffer.lines[0];
    expect(line.getCodePoint(0), 0x2764);
    expect(line.getCombiningCharacters(0), '\u200d\u{1F525}');
    expect(line.getWidth(0), 2);
    expect(line.getWidth(1), 0);
    expect(line.getCodePoint(2), 0x78);
  });

  test('Terminal keeps invalid emoji modifiers separate from text', () {
    final terminal = Terminal()..resize(8, 2);

    terminal.write('"\u{1F3FF}"');

    final line = terminal.buffer.lines[0];
    expect(line.getCodePoint(0), '"'.codeUnitAt(0));
    expect(line.getWidth(0), 1);
    expect(line.getCodePoint(1), 0x1F3FF);
    expect(line.getWidth(1), 2);
    expect(line.getWidth(2), 0);
    expect(line.getCodePoint(3), '"'.codeUnitAt(0));
    expect(terminal.buffer.cursorX, 4);
  });

  test('Terminal joins emoji modifiers to valid bases', () {
    final terminal = Terminal();

    terminal.write('\u{1F44B}\u{1F3FF}');

    final line = terminal.buffer.lines[0];
    expect(line.getCodePoint(0), 0x1F44B);
    expect(line.getCombiningCharacters(0), '\u{1F3FF}');
    expect(line.getWidth(0), 2);
    expect(terminal.buffer.cursorX, 2);
  });

  test('Terminal keeps invalid ZWJ sequences from merging text', () {
    final terminal = Terminal();

    terminal.write('A\u200dB');

    final line = terminal.buffer.lines[0];
    expect(line.getCodePoint(0), 'A'.codeUnitAt(0));
    expect(line.getCombiningCharacters(0), '\u200d');
    expect(line.getCodePoint(1), 'B'.codeUnitAt(0));
    expect(terminal.buffer.cursorX, 2);
  });

  test('Terminal keeps Indic conjuncts in one grapheme cell', () {
    final terminal = Terminal();

    terminal.write('\u0915\u094d\u0937');

    final line = terminal.buffer.lines[0];
    expect(line.getCodePoint(0), 0x0915);
    expect(line.getCombiningCharacters(0), '\u094d\u0937');
    expect(terminal.buffer.cursorX, 1);
  });

  test('Terminal wraps a widening ZWJ grapheme at the right edge', () {
    final terminal = Terminal()..resize(3, 2);

    terminal.write('ab\u2764\u200d\u{1F525}');

    expect(terminal.buffer.lines[0].toString(), 'ab');
    final wrappedLine = terminal.buffer.lines[1];
    expect(wrappedLine.isWrapped, isTrue);
    expect(wrappedLine.getText(), '\u2764\u200d\u{1F525}');
    expect(wrappedLine.getWidth(0), 2);
    expect(terminal.buffer.cursorX, 2);
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

  test('Terminal tracks OSC 133 semantic prompt state', () {
    final states = <TerminalSemanticPromptState>[];
    final terminal = Terminal(onSemanticPrompt: states.add);

    terminal.write('\x1b]133;A\x1b\\');
    terminal.write('\x1b]133;B\x1b\\');
    terminal.write('\x1b]133;C\x1b\\');
    terminal.write('\x1b]133;D;2\x1b\\');

    expect(
      states.map((state) => state.content),
      [
        TerminalSemanticPromptContent.prompt,
        TerminalSemanticPromptContent.input,
        TerminalSemanticPromptContent.output,
        TerminalSemanticPromptContent.output,
      ],
    );
    expect(terminal.semanticPromptState.lastCommandExitCode, 2);
  });

  test('Terminal pushes and restores window titles', () {
    final titles = <String>[];
    final terminal = Terminal(onTitleChange: titles.add);

    terminal.write('\x1b]2;first\x1b\\\x1b[22t');
    terminal.write('\x1b]2;second\x1b\\\x1b[23t');
    terminal.write('\x1b[23t');

    expect(titles, ['first', 'second', 'first']);
  });

  test('Terminal ignores icon title stack operations', () {
    final titles = <String>[];
    final terminal = Terminal(onTitleChange: titles.add);

    terminal.write('\x1b]2;first\x1b\\\x1b[22;1t');
    terminal.write('\x1b]2;second\x1b\\\x1b[23;1t');
    terminal.write('\x1b[22;2t\x1b]2;third\x1b\\\x1b[23;2t');

    expect(titles, ['first', 'second', 'third', 'second']);
  });

  test('Terminal ignores title reporting requests', () {
    final titles = <String>[];
    final terminal = Terminal(onTitleChange: titles.add);

    terminal.write('\x1b]2;first\x1b\\\x1b[21t');
    terminal.write('\x1b]2;second\x1b\\\x1b[23t');

    expect(titles, ['first', 'second']);
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

  test('Terminal does not terminate DCS with BEL', () {
    final terminal = Terminal();

    terminal.write('\x1bPignored\x07still ignored\x1b\\after');

    expect(terminal.buffer.lines[0].toString(), 'after');
  });

  test('Terminal resumes split escape sequences interrupted by DCS', () {
    final terminal = Terminal();

    terminal.write('\x1bPignored\x1b');
    terminal.write('[32mG');

    final line = terminal.buffer.lines[0];
    expect(line.toString(), 'G');
    expect(line.getForeground(0), CellColor.named | NamedColor.green);
  });

  test('Terminal resumes split escape sequences interrupted by APC', () {
    final terminal = Terminal();

    terminal.write('\x1b_ignored\x1b');
    terminal.write('[31mR');

    final line = terminal.buffer.lines[0];
    expect(line.toString(), 'R');
    expect(line.getForeground(0), CellColor.named | NamedColor.red);
  });

  test('Terminal cancels DCS with CAN', () {
    final terminal = Terminal();

    terminal.write('\x1bPignored\x18N');

    expect(terminal.buffer.lines[0].toString(), 'N');
  });

  test('Terminal discards unsupported APC PM and SOS payloads', () {
    final terminal = Terminal();

    terminal.write('a\x1b_payload\x1b\\b');
    terminal.write('\x1b^payload\x07still ignored\x1b\\c');
    terminal.write('\x1bXpayload\x1b\\d');

    expect(terminal.buffer.lines[0].toString(), 'abcd');
  });

  test('Terminal supports 8-bit C1 OSC DCS and string controls', () {
    final output = <String>[];
    final titles = <String>[];
    final terminal = Terminal(
      onOutput: output.add,
      onTitleChange: titles.add,
    );

    terminal.write(
      '\u009d2;c1 title\u009c'
      '\u009b31mX'
      '\u009fignored\u009cY'
      '\u0090\$qm\u009c',
    );

    expect(titles, ['c1 title']);
    expect(terminal.buffer.lines[0].toString(), 'XY');
    expect(
      terminal.buffer.lines[0].getForeground(0),
      CellColor.named | NamedColor.red,
    );
    expect(output, ['\x1bP1\$r0;31m\x1b\\']);
  });

  test('Terminal paste sanitizes bracketed and non-bracketed payloads', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.paste('a\nb\r\nc\x03');
    terminal.write('\x1b[?2004h');
    terminal.paste('safe\x1b[201~\x03\x00\x08\x7f');
    terminal.paste('x\x1b]52;c;AAAA\x07y\x1bPignored\x1b\\z');

    expect(output, [
      'a\rb\r\rc ',
      '\x1b[200~safe    \x1b[201~',
      '\x1b[200~xyz\x1b[201~',
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

    test('resize disables synchronized update mode', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      var redraws = 0;
      terminal.addListener(() => redraws++);

      terminal.write('\x1b[?2026hstalled');
      terminal.resize(100, 24);
      terminal.write('\x1b[?2026\x24p');

      expect(redraws, 2);
      expect(output, ['\x1b[?2026;2\x24y']);
    });

    test('reports synchronized update mode state', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?2026h\x1b[?2026\x24p');
      terminal.write('\x1b[?2026l\x1b[?2026\x24p');

      expect(output, [
        '\x1b[?2026;1\x24y',
        '\x1b[?2026;2\x24y',
      ]);
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
      '\x1b[?45h'
      '\x1b[?45\x24p'
      '\x1b[?1045h'
      '\x1b[?1045\x24p'
      '\x1b[?25l'
      '\x1b[?25\x24p'
      '\x1b[?9999\x24p',
    );

    expect(output, [
      '\x1b[4;1\x24y',
      '\x1b[20;2\x24y',
      '\x1b[?7;1\x24y',
      '\x1b[?45;1\x24y',
      '\x1b[?1045;1\x24y',
      '\x1b[?25;2\x24y',
      '\x1b[?9999;0\x24y',
    ]);
  });

  test('Terminal protects cells from selective line erase', () {
    final terminal = Terminal()..resize(6, 3);

    terminal.write('\x1b[1"qAB\x1b[2"qCD\r\x1b[?K');

    expect(terminal.buffer.lines[0].toString(), 'AB');
    expect(
      terminal.buffer.lines[0].getAttributes(0) & CellAttr.protected,
      isNot(0),
    );
    expect(terminal.buffer.lines[0].getAttributes(2) & CellAttr.protected, 0);
  });

  test('Terminal protects cells from selective display erase', () {
    final terminal = Terminal()..resize(6, 3);

    terminal.write('\x1b[1"qA\r\nB\x1b[2"q\r\nC\x1b[H\x1b[?J');

    expect(terminal.buffer.lines[0].toString(), 'A');
    expect(terminal.buffer.lines[1].toString(), 'B');
    expect(terminal.buffer.lines[2].toString(), '');
  });

  test('Terminal ISO protected areas survive normal erase operations', () {
    final terminal = Terminal()..resize(8, 3);

    terminal.write('\x1bVAB\x1bWCD\r\x1b[K');

    expect(terminal.buffer.lines[0].toString(), 'AB');
  });

  test('Terminal DEC protected areas do not survive normal erase', () {
    final terminal = Terminal()..resize(8, 3);

    terminal.write('\x1b[1"qAB\x1b[2"qCD\r\x1b[K');

    expect(terminal.buffer.lines[0].toString(), '');
  });

  test('Terminal ISO protected areas survive erase characters', () {
    final terminal = Terminal()..resize(8, 3);

    terminal.write('\x1bVAB\x1bWCD\r\x1b[4X');

    expect(terminal.buffer.lines[0].toString(), 'AB');
    expect(terminal.buffer.lines[0].getAttributes(2) & CellAttr.protected, 0);
  });

  test('Terminal saves and restores DEC private mode state', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.write(
      '\x1b[?2026h'
      '\x1b[?7;25;2026s'
      '\x1b[?7;25;2026l'
      '\x1b[?7\x24p'
      '\x1b[?25\x24p'
      '\x1b[?2026\x24p'
      '\x1b[?7;25;2026r'
      '\x1b[?7\x24p'
      '\x1b[?25\x24p'
      '\x1b[?2026\x24p'
      '\x1b[?2026l',
    );

    expect(output, [
      '\x1b[?7;2\x24y',
      '\x1b[?25;2\x24y',
      '\x1b[?2026;2\x24y',
      '\x1b[?7;1\x24y',
      '\x1b[?25;1\x24y',
      '\x1b[?2026;1\x24y',
    ]);
  });

  test('Terminal reports Alacritty-compatible device attributes', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.write('\x1b[c\x1b[>c');

    expect(output, [
      '\x1b[?6c',
      '\x1b[>0;40001;1c',
    ]);
  });

  test('Terminal reports Ghostty-compatible color scheme DSR', () {
    final output = <String>[];
    final terminal = Terminal(
      onOutput: output.add,
      onColorSchemeQuery: () => TerminalColorScheme.dark,
    );

    terminal.write('\x1b[?996n');
    terminal.onColorSchemeQuery = () => TerminalColorScheme.light;
    terminal.write('\x1b[?996n');

    expect(output, [
      '\x1b[?997;1n',
      '\x1b[?997;2n',
    ]);
  });

  test('Terminal ignores color scheme DSR without callback', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.write('\x1b[?996n');

    expect(output, isEmpty);
  });

  test('Terminal reports XTVERSION with default and callback values', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.write('\x1b[>q');
    terminal.onXtVersionQuery = () => 'lumide-term 1.0';
    terminal.write('\x1b[>0q');

    expect(output, [
      '\x1bP>|xterm.dart 4.0.1\x1b\\',
      '\x1bP>|lumide-term 1.0\x1b\\',
    ]);
  });

  test('Terminal sanitizes and bounds XTVERSION callback output', () {
    final output = <String>[];
    final terminal = Terminal(
      onOutput: output.add,
      onXtVersionQuery: () => 'bad\x1b[31m${'x' * 300}',
    );

    terminal.write('\x1b[>q');

    expect(output.single, startsWith('\x1bP>|bad[31m'));
    expect(output.single, hasLength('\x1bP>|\x1b\\'.length + 256));
  });

  test('Terminal answers ENQ through optional callback', () {
    final output = <String>[];
    final terminal = Terminal(
      onOutput: output.add,
      onEnquiry: () => 'OK',
    );

    terminal.write('\x05');

    expect(output, ['OK']);
  });

  test('Terminal ignores ENQ without callback or empty response', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.write('\x05');
    terminal.onEnquiry = () => '';
    terminal.write('\x05');

    expect(output, isEmpty);
  });

  test('Terminal reports DECRQSS status strings', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add)..resize(80, 24);

    terminal.write(
      '\x1b[1;3;4m'
      '\x1b[3;10r'
      '\x1b[5 q'
      '\x1bP\$qm\x1b\\'
      '\x1bP\$qr\x1b\\'
      '\x1bP\$q q\x1b\\'
      '\x1bP\$qx\x1b\\',
    );

    expect(output, [
      '\x1bP1\$r0;1;3;4m\x1b\\',
      '\x1bP1\$r3;10r\x1b\\',
      '\x1bP1\$r5 q\x1b\\',
      '\x1bP0\$r\x1b\\',
    ]);
  });

  test('Terminal includes active colors in DECRQSS SGR reports', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.write(
      '\x1b[38;5;123;48;2;1;2;3;58;5;4m'
      '\x1bP\$qm\x1b\\',
    );

    expect(
      output,
      ['\x1bP1\$r0;38;5;123;48;2;1;2;3;58;5;4m\x1b\\'],
    );
  });

  test('Terminal reports DECRQSS left and right margins when enabled', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add)..resize(80, 24);

    terminal.write('\x1bP\$qs\x1b\\');
    terminal.write('\x1b[?69h\x1b[3;10s\x1bP\$qs\x1b\\');

    expect(output, [
      '\x1bP0\$r\x1b\\',
      '\x1bP1\$r3;10s\x1b\\',
    ]);
  });

  test('Terminal handles split DECRQSS payloads', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.write('\x1bP\$');
    terminal.write('qm\x1b');
    terminal.write('\\');

    expect(output, ['\x1bP1\$r0m\x1b\\']);
  });

  test('Terminal reports XTGETTCAP capabilities', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add)..resize(80, 24);

    terminal.write(
      '\x1bP+q'
      '544E;436F;524742;6C696E6573;'
      '4245;5053;53796E63;584D;456E6D67;'
      '4D73;5373;5365;536D756C78;536574756C63;'
      '7369746D;7269746D;736D7878;726D7878;626164'
      '\x1b\\',
    );

    expect(output, [
      '\x1bP1+r544E=787465726D2D323536636F6C6F72\x1b\\',
      '\x1bP1+r436F=323536\x1b\\',
      '\x1bP1+r524742=38\x1b\\',
      '\x1bP1+r6C696E6573=3234\x1b\\',
      '\x1bP1+r4245=1B5B3F3230303468\x1b\\',
      '\x1bP1+r5053=1B5B3230307E\x1b\\',
      '\x1bP1+r53796E63='
          '1B5B3F32303236253F257031257B317D252D25746C256568253B'
          '\x1b\\',
      '\x1bP1+r584D='
          '1B5B3F313030363B31303030253F257031257B317D253D25746825656C253B'
          '\x1b\\',
      '\x1bP1+r456E6D67=1B5B3F363968\x1b\\',
      '\x1bP1+r4D73=1B5D35323B25703125733B257032257307\x1b\\',
      '\x1bP1+r5373=1B5B25703125642071\x1b\\',
      '\x1bP1+r5365=1B5B302071\x1b\\',
      '\x1bP1+r536D756C78=1B5B343A25703125646D\x1b\\',
      '\x1bP1+r536574756C63='
          '1B5B35383A323A3A257031257B36353533367D252F25643A257031257B3235367D'
          '252F257B3235357D252625643A257031257B3235357D25262564253B6D'
          '\x1b\\',
      '\x1bP1+r7369746D=1B5B336D\x1b\\',
      '\x1bP1+r7269746D=1B5B32336D\x1b\\',
      '\x1bP1+r736D7878=1B5B396D\x1b\\',
      '\x1bP1+r726D7878=1B5B32396D\x1b\\',
    ]);
  });

  test('Terminal handles split XTGETTCAP payloads', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.write('\x1bP+q');
    terminal.write('436F\x1b');
    terminal.write('\\');

    expect(output, ['\x1bP1+r436F=323536\x1b\\']);
  });

  test('Terminal reports common terminfo rendering capabilities', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);
    final capabilities = {
      'clear': '\x1b[H\x1b[2J',
      'E3': '\x1b[3J',
      'fe': '\x1b[?1004h',
      'fd': '\x1b[?1004l',
      'kxIN': '\x1b[I',
      'kxOUT': '\x1b[O',
      'bold': '\x1b[1m',
      'dim': '\x1b[2m',
      'invis': '\x1b[8m',
      'rev': '\x1b[7m',
      'smul': '\x1b[4m',
      'rmul': '\x1b[24m',
      'sgr0': '\x1b(B\x1b[m',
      'op': '\x1b[39;49m',
      'setrgbf': '\x1b[38:2:%p1%d:%p2%d:%p3%dm',
      'setrgbb': '\x1b[48:2:%p1%d:%p2%d:%p3%dm',
      'cup': '\x1b[%i%p1%d;%p2%dH',
      'ech': '\x1b[%p1%dX',
      'indn': '\x1b[%p1%dS',
      'rin': '\x1b[%p1%dT',
      'rep': '%p1%c\x1b[%p2%{1}%-%db',
      'smcup': '\x1b[?1049h',
      'rmcup': '\x1b[?1049l',
    };

    terminal.write(
      '\x1bP+q'
      '${capabilities.keys.map(_hexEncode).join(';')};626164'
      '\x1b\\',
    );

    expect(
      output,
      capabilities.entries.map((entry) {
        return '\x1bP1+r${_hexEncode(entry.key)}=${_hexEncode(entry.value)}\x1b\\';
      }).toList(),
    );
  });

  test('Terminal reports common terminfo keyboard capabilities', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);
    final capabilities = {
      'kbs': '\x7f',
      'kcbt': '\x1b[Z',
      'kent': '\x1bOM',
      'khome': '\x1b[H',
      'kend': '\x1b[F',
      'kich1': '\x1b[2~',
      'kdch1': '\x1b[3~',
      'kpp': '\x1b[5~',
      'knp': '\x1b[6~',
      'kcuu1': '\x1b[A',
      'kcud1': '\x1b[B',
      'kcuf1': '\x1b[C',
      'kcub1': '\x1b[D',
      'kf1': '\x1bOP',
      'kf2': '\x1bOQ',
      'kf3': '\x1bOR',
      'kf4': '\x1bOS',
      'kf5': '\x1b[15~',
      'kf6': '\x1b[17~',
      'kf7': '\x1b[18~',
      'kf8': '\x1b[19~',
      'kf9': '\x1b[20~',
      'kf10': '\x1b[21~',
      'kf11': '\x1b[23~',
      'kf12': '\x1b[24~',
      'u6': '\x1b[%i%d;%dR',
      'u7': '\x1b[6n',
      'u8': '\x1b[?%[;0123456789]c',
      'u9': '\x1b[c',
    };

    terminal.write(
      '\x1bP+q'
      '${capabilities.keys.map(_hexEncode).join(';')};626164'
      '\x1b\\',
    );

    expect(
      output,
      capabilities.entries.map((entry) {
        return '\x1bP1+r${_hexEncode(entry.key)}=${_hexEncode(entry.value)}\x1b\\';
      }).toList(),
    );
  });

  test('Terminal reports modified navigation terminfo capabilities', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);
    final capabilities = {
      'kUP': '\x1b[1;2A',
      'kri': '\x1b[1;2A',
      'kUP5': '\x1b[1;5A',
      'kDN': '\x1b[1;2B',
      'kind': '\x1b[1;2B',
      'kDN7': '\x1b[1;7B',
      'kRIT3': '\x1b[1;3C',
      'kLFT6': '\x1b[1;6D',
      'kHOM': '\x1b[1;2H',
      'kEND7': '\x1b[1;7F',
      'kIC5': '\x1b[2;5~',
      'kDC4': '\x1b[3;4~',
      'kPRV6': '\x1b[5;6~',
      'kNXT3': '\x1b[6;3~',
    };

    terminal.write(
      '\x1bP+q'
      '${capabilities.keys.map(_hexEncode).join(';')};626164'
      '\x1b\\',
    );

    expect(
      output,
      capabilities.entries.map((entry) {
        return '\x1bP1+r${_hexEncode(entry.key)}=${_hexEncode(entry.value)}\x1b\\';
      }).toList(),
    );
  });

  test('Terminal reports modified function-key terminfo capabilities', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);
    final capabilities = {
      'kf13': '\x1b[1;2P',
      'kf24': '\x1b[24;2~',
      'kf25': '\x1b[1;5P',
      'kf36': '\x1b[24;5~',
      'kf37': '\x1b[1;6P',
      'kf48': '\x1b[24;6~',
      'kf49': '\x1b[1;3P',
      'kf60': '\x1b[24;3~',
      'kf61': '\x1b[1;4P',
      'kf63': '\x1b[1;4R',
    };

    terminal.write(
      '\x1bP+q'
      '${capabilities.keys.map(_hexEncode).join(';')};6B663634'
      '\x1b\\',
    );

    expect(
      output,
      capabilities.entries.map((entry) {
        return '\x1bP1+r${_hexEncode(entry.key)}=${_hexEncode(entry.value)}\x1b\\';
      }).toList(),
    );
  });

  test('Terminal reports text area and cell pixel sizes', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add)..resize(80, 24, 9, 18);

    terminal.write('\x1b[14t\x1b[16t\x1b[18t');

    expect(output, [
      '\x1b[4;432;720t',
      '\x1b[6;18;9t',
      '\x1b[8;24;80t',
    ]);
  });

  test('Terminal skips no-op resizes', () {
    final resizes = <(int, int, int, int)>[];
    final terminal = Terminal();

    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      resizes.add((width, height, pixelWidth, pixelHeight));
    };
    terminal.resize(100, 30, 9, 18);
    terminal.resize(100, 30, 9, 18);
    terminal.resize(100, 30);
    terminal.resize(100, 30, 10, 18);

    expect(resizes, [
      (100, 30, 9, 18),
      (100, 30, 10, 18),
    ]);
    expect(terminal.viewWidth, 100);
  });

  test('Terminal reports one-based cursor position', () {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    terminal.write('\x1b[3;5H\x1b[6n');

    expect(output, ['\x1b[3;5R']);
  });

  test('Terminal supports reverse wrap mode for cursor left', () {
    final terminal = Terminal()..resize(5, 3);

    terminal.write('\x1b[?45hABCDE1\x1b[2DX');

    expect(terminal.buffer.lines[0].toString(), 'ABCDX');
    expect(terminal.buffer.lines[1].toString(), '1');
  });

  test('Terminal reverse wrap stops at unwrapped previous line', () {
    final terminal = Terminal()..resize(5, 3);

    terminal.write('\x1b[?45hABCD\r\n1\x1b[2DX');

    expect(terminal.buffer.lines[0].toString(), 'ABCD');
    expect(terminal.buffer.lines[1].toString(), 'X');
  });

  test('Terminal supports extended reverse wrap mode', () {
    final terminal = Terminal()..resize(5, 3);

    terminal.write('\x1b[?1045hABCD\r\n1\x1b[2DX');

    expect(terminal.buffer.lines[0].toString(), 'ABCDX');
    expect(terminal.buffer.lines[1].toString(), '1');
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

  test('Terminal supports G2 and G3 character set invocation', () {
    final terminal = Terminal()..resize(12, 2);

    terminal.write(
      '\x1b*0\x1bNqq'
      '\x1b+0\x1boqq'
      '\x0fq',
    );

    final line = terminal.buffer.lines[0];
    expect(line.getCodePoint(0), 0x2500);
    expect(line.getCodePoint(1), 0x71);
    expect(line.getCodePoint(2), 0x2500);
    expect(line.getCodePoint(3), 0x2500);
    expect(line.getCodePoint(4), 0x71);
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

  test('Terminal ignores C0 controls inside OSC payloads', () {
    final titles = <String>[];
    final terminal = Terminal(onTitleChange: titles.add);

    terminal.write('\x1b]2;a\nb\x07');

    expect(titles, ['ab']);
  });

  test('Terminal cancels OSC with CAN and restarts it with ESC', () {
    final titles = <String>[];
    final terminal = Terminal(onTitleChange: titles.add);

    terminal.write('\x1b]2;ignored\x18N');
    terminal.write('\x1b]2;ignored\x1b[32mG');

    final line = terminal.buffer.lines[0];
    expect(titles, isEmpty);
    expect(line.toString(), 'NG');
    expect(line.getForeground(0), CellColor.normal);
    expect(line.getForeground(1), CellColor.named | NamedColor.green);
  });

  test('Terminal bounds oversized CSI payloads across chunks', () {
    final terminal = Terminal();

    terminal.write('\x1b[${'1;' * 100}');
    terminal.write('2;' * 100);
    terminal.write('mSafe');

    expect(terminal.buffer.lines[0].toString(), 'Safe');
  });

  test('Terminal resumes escapes after oversized CSI payloads', () {
    final terminal = Terminal();

    terminal.write('\x1b[${'1;' * 200}\x1b');
    terminal.write('[32mG');

    final line = terminal.buffer.lines[0];
    expect(line.toString(), 'G');
    expect(line.getForeground(0), CellColor.named | NamedColor.green);
  });

  test('Terminal executes embedded CSI controls without cancelling it', () {
    var bells = 0;
    final terminal = Terminal(onBell: () => bells++)..resize(5, 3);

    terminal.write('\x1b[31\x07mR');
    terminal.write('\x1b[0m\x1b[2\nCX');

    expect(bells, 1);
    expect(
      terminal.buffer.lines[0].getForeground(0),
      CellColor.named | NamedColor.red,
    );
    expect(terminal.buffer.lines[1].getCodePoint(3), 'X'.codeUnitAt(0));
  });

  test('Terminal preserves ESC state across controls and chunks', () {
    var bells = 0;
    final terminal = Terminal(onBell: () => bells++);

    terminal.write('\x1b\x07');
    terminal.write('[31mR');
    terminal.write('\x1b\x1b[32mG');

    final line = terminal.buffer.lines[0];
    expect(bells, 1);
    expect(line.toString(), 'RG');
    expect(line.getForeground(0), CellColor.named | NamedColor.red);
    expect(line.getForeground(1), CellColor.named | NamedColor.green);
  });

  test('Terminal cancels CSI with CAN and restarts it with ESC', () {
    final terminal = Terminal();

    terminal.write('\x1b[31\x18mN');
    terminal.write('\x1b[31\x1b[32mG');

    final line = terminal.buffer.lines[0];
    expect(line.toString(), 'mNG');
    expect(line.getForeground(0), CellColor.normal);
    expect(line.getForeground(1), CellColor.normal);
    expect(line.getForeground(2), CellColor.named | NamedColor.green);
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

  test('Terminal does not apply malformed SGR color operands as styles', () {
    final terminal = Terminal();

    terminal.write(
      '\x1b[38;2;1;2mF'
      '\x1b[0m'
      '\x1b[48;5mB'
      '\x1b[0m'
      '\x1b[58;9mU',
    );

    final line = terminal.buffer.lines[0];
    expect(line.getForeground(0), CellColor.normal);
    expect(line.getBackground(1), CellColor.normal);
    expect(line.getUnderlineColor(2), CellColor.normal);
    expect(
      line.createCellData(0).flags & (CellFlags.bold | CellFlags.faint),
      0,
    );
    expect(line.createCellData(2).flags & CellAttr.strikethrough, 0);
  });

  test('Terminal ignores out-of-range SGR color values', () {
    final terminal = Terminal();

    terminal.write(
      '\x1b[38;5;300m'
      '\x1b[48;5;300m'
      '\x1b[58;5;300m'
      '\x1b[38;2;256;1;2m'
      '\x1b[48;2;1;256;2m'
      '\x1b[58;2;1;2;256m'
      'Safe',
    );

    final line = terminal.buffer.lines[0];
    expect(line.toString(), 'Safe');
    expect(line.getForeground(0), CellColor.normal);
    expect(line.getBackground(0), CellColor.normal);
    expect(line.getUnderlineColor(0), CellColor.normal);
  });

  test('Terminal supports colon-delimited SGR truecolor foreground', () {
    final terminal = Terminal();

    terminal.write('\x1b[38:2:1:2:3mX');

    expect(
      terminal.buffer.lines[0].getForeground(0),
      CellColor.rgb | 0x010203,
    );
  });

  test('Terminal supports colon-delimited SGR truecolor color space', () {
    final terminal = Terminal();

    terminal.write('\x1b[38:2::1:2:3mF');
    terminal.write('\x1b[48:2:0:4:5:6mB');
    terminal.write('\x1b[58:2::7:8:9mU');

    final line = terminal.buffer.lines[0];
    expect(line.getForeground(0), CellColor.rgb | 0x010203);
    expect(line.getBackground(1), CellColor.rgb | 0x040506);
    expect(line.getUnderlineColor(2), CellColor.rgb | 0x070809);
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

    test('cursor position aliases treat zero as one', () {
      final terminal = Terminal()..resize(10, 5);

      terminal.write('\x1b[3;3H\x1b[0`\x1b[0a\x1b[0eX');

      expect(terminal.buffer.cursorX, 2);
      expect(terminal.buffer.cursorY, 3);
      expect(terminal.buffer.lines[3].getCodePoint(1), 'X'.codeUnitAt(0));
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

    test('erase characters ignores horizontal margins', () {
      final terminal = Terminal()..resize(6, 3);

      terminal.write('abcdef\x1b[?69h\x1b[2;4s\x1b[1;4H\x1b[2X');

      expect(terminal.buffer.lines[0].getText(0, 6), 'abcf');
      expect(terminal.buffer.lines[0].getCodePoint(3), 0);
      expect(terminal.buffer.lines[0].getCodePoint(4), 0);
      expect(terminal.buffer.lines[0].getCodePoint(5), 0x66);
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

  group('Terminal left and right margins', () {
    test('DECSLRM is ignored until DECLRMM is enabled', () {
      final terminal = Terminal()..resize(6, 3);

      terminal.write('\x1b[2;4s');

      expect(terminal.buffer.marginLeft, 0);
      expect(terminal.buffer.marginRight, 5);
    });

    test('DECSLRM sets horizontal margins and homes cursor', () {
      final terminal = Terminal()..resize(6, 3);

      terminal.write('\x1b[?69h\x1b[2;4s');

      expect(terminal.buffer.marginLeft, 1);
      expect(terminal.buffer.marginRight, 3);
      expect(terminal.buffer.cursorX, 0);
      expect(terminal.buffer.cursorY, 0);
    });

    test('CSI s sets full horizontal margins when DECLRMM is enabled', () {
      final terminal = Terminal()..resize(6, 3);

      terminal.write('\x1b[?69h\x1b[2;4s\x1b[2;3H\x1b[s');

      expect(terminal.buffer.marginLeft, 0);
      expect(terminal.buffer.marginRight, 5);
      expect(terminal.buffer.cursorX, 0);
      expect(terminal.buffer.cursorY, 0);
    });

    test('CSI s saves cursor when DECLRMM is disabled', () {
      final terminal = Terminal()..resize(6, 3);

      terminal.write('\x1b[2;3H\x1b[s\x1b[1;1H\x1b[u');

      expect(terminal.buffer.cursorX, 2);
      expect(terminal.buffer.cursorY, 1);
    });

    test('DECLRMM reset clears horizontal margins', () {
      final terminal = Terminal()..resize(6, 3);

      terminal.write('\x1b[?69h\x1b[2;4s\x1b[?69l');

      expect(terminal.buffer.marginLeft, 0);
      expect(terminal.buffer.marginRight, 5);
    });

    test('carriage return respects left margin after the margin', () {
      final terminal = Terminal()..resize(6, 3);

      terminal.write('\x1b[?69h\x1b[3;5s\x1b[1;6H\rX');

      expect(terminal.buffer.cursorX, 3);
      expect(terminal.buffer.lines[0].getCodePoint(2), 0x58);
    });

    test('carriage return before left margin moves to zero', () {
      final terminal = Terminal()..resize(6, 3);

      terminal.write('\x1b[?69h\x1b[3;5s\x1b[1;1H\rX');

      expect(terminal.buffer.lines[0].getCodePoint(0), 0x58);
    });

    test('origin mode uses left margin for absolute cursor position', () {
      final terminal = Terminal()..resize(6, 3);

      terminal.write('\x1b[?69h\x1b[3;5s\x1b[?6h\x1b[1;1HX');

      expect(terminal.buffer.lines[0].getCodePoint(2), 0x58);
    });

    test('auto wrap returns to left margin at right margin', () {
      final terminal = Terminal()..resize(6, 3);

      terminal.write('\x1b[?69h\x1b[2;4s\x1b[1;2Habcde');

      expect(terminal.buffer.lines[0].getCodePoint(1), 0x61);
      expect(terminal.buffer.lines[0].getCodePoint(2), 0x62);
      expect(terminal.buffer.lines[0].getCodePoint(3), 0x63);
      expect(terminal.buffer.lines[1].getCodePoint(1), 0x64);
      expect(terminal.buffer.lines[1].getCodePoint(2), 0x65);
    });

    test('wide characters wrap before right margin', () {
      final terminal = Terminal()..resize(6, 3);

      terminal.write('\x1b[?69h\x1b[2;4s\x1b[1;4Hあ');

      expect(terminal.buffer.lines[0].getCodePoint(3), 0);
      expect(terminal.buffer.lines[1].getCodePoint(1), 0x3042);
      expect(terminal.buffer.lines[1].getWidth(1), 2);
    });

    test('delete characters shifts only inside horizontal margins', () {
      final terminal = Terminal()..resize(6, 3);

      terminal.write('abcdef\x1b[?69h\x1b[2;4s\x1b[1;2H\x1b[P');

      expect(terminal.buffer.lines[0].getCodePoint(0), 0x61);
      expect(terminal.buffer.lines[0].getCodePoint(1), 0x63);
      expect(terminal.buffer.lines[0].getCodePoint(2), 0x64);
      expect(terminal.buffer.lines[0].getCodePoint(3), 0);
      expect(terminal.buffer.lines[0].getCodePoint(4), 0x65);
      expect(terminal.buffer.lines[0].getCodePoint(5), 0x66);
    });

    test('insert blank characters shifts only inside horizontal margins', () {
      final terminal = Terminal()..resize(6, 3);

      terminal.write('abcdef\x1b[?69h\x1b[2;4s\x1b[1;2H\x1b[@');

      expect(terminal.buffer.lines[0].getCodePoint(0), 0x61);
      expect(terminal.buffer.lines[0].getCodePoint(1), 0);
      expect(terminal.buffer.lines[0].getCodePoint(2), 0x62);
      expect(terminal.buffer.lines[0].getCodePoint(3), 0x63);
      expect(terminal.buffer.lines[0].getCodePoint(4), 0x65);
      expect(terminal.buffer.lines[0].getCodePoint(5), 0x66);
    });

    test('insert lines shifts only horizontal margin cells', () {
      final terminal = Terminal()..resize(6, 4);

      terminal.write('abcdef\r\nghijkl\r\nmnopqr\r\nstuvwx');
      terminal.write('\x1b[?69h\x1b[2;4s\x1b[2;2H\x1b[L');

      expect(terminal.buffer.lines[1].getText(0, 6), 'gkl');
      expect(terminal.buffer.lines[2].getText(0, 6), 'mhijqr');
      expect(terminal.buffer.lines[3].getText(0, 6), 'snopwx');
    });

    test('delete lines shifts only horizontal margin cells', () {
      final terminal = Terminal()..resize(6, 4);

      terminal.write('abcdef\r\nghijkl\r\nmnopqr\r\nstuvwx');
      terminal.write('\x1b[?69h\x1b[2;4s\x1b[2;2H\x1b[M');

      expect(terminal.buffer.lines[1].getText(0, 6), 'gnopkl');
      expect(terminal.buffer.lines[2].getText(0, 6), 'mtuvqr');
      expect(terminal.buffer.lines[3].getText(0, 6), 'swx');
    });

    test('scroll up shifts only horizontal margin cells', () {
      final terminal = Terminal()..resize(6, 4);

      terminal.write('abcdef\r\nghijkl\r\nmnopqr\r\nstuvwx');
      terminal.write('\x1b[?69h\x1b[2;4s\x1b[2;4r\x1b[S');

      expect(terminal.buffer.lines[1].getText(0, 6), 'gnopkl');
      expect(terminal.buffer.lines[2].getText(0, 6), 'mtuvqr');
      expect(terminal.buffer.lines[3].getText(0, 6), 'swx');
    });

    test('index outside horizontal margins does not scroll', () {
      final terminal = Terminal()..resize(6, 4);

      terminal.write('abcdef\r\nghijkl\r\nmnopqr\r\nstuvwx');
      terminal.write('\x1b[?69h\x1b[3;5s\x1b[2;3r\x1b[3;1H\x1bDX');

      expect(terminal.buffer.lines[1].getText(0, 6), 'ghijkl');
      expect(terminal.buffer.lines[2].getText(0, 6), 'Xnopqr');
    });

    test('reverse index outside horizontal margins does not scroll', () {
      final terminal = Terminal()..resize(6, 4);

      terminal.write('abcdef\r\nghijkl\r\nmnopqr\r\nstuvwx');
      terminal.write('\x1b[?69h\x1b[3;5s\x1b[2;3r\x1b[2;1H\x1bMX');

      expect(terminal.buffer.lines[1].getText(0, 6), 'Xhijkl');
      expect(terminal.buffer.lines[2].getText(0, 6), 'mnopqr');
    });

    test('next line uses carriage-return horizontal margin', () {
      final terminal = Terminal()..resize(6, 4);

      terminal.write('abcdef\r\nghijkl\r\nmnopqr\r\nstuvwx');
      terminal.write('\x1b[?69h\x1b[3;5s\x1b[2;3r\x1b[3;5H\x1bEX');

      expect(terminal.buffer.lines[1].getText(0, 6), 'ghopql');
      expect(terminal.buffer.lines[2].getText(0, 6), 'mnXr');
      expect(terminal.buffer.lines[2].getCodePoint(3), 0);
      expect(terminal.buffer.lines[2].getCodePoint(4), 0);
    });

    test('horizontal tab stops at right margin', () {
      final terminal = Terminal()..resize(10, 3);

      terminal.write('\x1b[?69h\x1b[4;7s\x1b[1;2H\tX');

      expect(terminal.buffer.lines[0].getCodePoint(6), 0x58);
      expect(terminal.buffer.cursorX, 7);
    });

    test('cursor forward tab stops at right margin', () {
      final terminal = Terminal()..resize(10, 3);

      terminal.write('\x1b[?69h\x1b[4;7s\x1b[1;5H\x1b[IX');

      expect(terminal.buffer.lines[0].getCodePoint(6), 0x58);
      expect(terminal.buffer.cursorX, 7);
    });

    test('cursor backward tab stops at left margin in origin mode', () {
      final terminal = Terminal()..resize(10, 3);

      terminal.write('\x1b[?69h\x1b[4;7s\x1b[?6h\x1b[1;3H\x1b[ZX');

      expect(terminal.buffer.lines[0].getCodePoint(3), 0x58);
      expect(terminal.buffer.cursorX, 4);
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

  test('Terminal ignores empty OSC 8 URI with explicit id', () {
    final terminal = Terminal();

    terminal.write(
      '\x1b]8;;https://example.com\x1b\\a'
      '\x1b]8;id=keep;\x1b\\b'
      '\x1b]8;;\x1b\\c',
    );

    expect(terminal.hyperlinkAt(const CellOffset(0, 0)), 'https://example.com');
    expect(terminal.hyperlinkAt(const CellOffset(1, 0)), 'https://example.com');
    expect(terminal.hyperlinkAt(const CellOffset(2, 0)), isNull);
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

  test('Terminal prunes erased OSC 8 hyperlinks before rejecting new ones', () {
    final terminal = Terminal()..resize(2, 1);

    for (var index = 0; index < 4096; index++) {
      terminal.write(
        '\x1b]8;;https://example.com/$index\x1b\\x\x1b]8;;\x1b\\'
        '\r\x1b[2K',
      );
    }

    terminal.write(
      '\x1b]8;;https://example.com/after-prune\x1b\\x\x1b]8;;\x1b\\',
    );

    expect(
      terminal.hyperlinkAt(const CellOffset(0, 0)),
      'https://example.com/after-prune',
    );
  });

  test('Terminal insert blank chars shifts hyperlinks without linking blanks',
      () {
    final terminal = Terminal()..resize(10, 2);

    terminal.write('\x1b]8;;https://example.com\x1b\\ABC');
    terminal.write('\r\x1b[2@');

    final line = terminal.buffer.lines[0];
    expect(line.getCodePoint(0), 0);
    expect(line.getCodePoint(1), 0);
    expect(line.getText(2, 5), 'ABC');
    expect(terminal.hyperlinkAt(const CellOffset(0, 0)), isNull);
    expect(terminal.hyperlinkAt(const CellOffset(1, 0)), isNull);
    expect(
      terminal.hyperlinkAt(const CellOffset(2, 0)),
      'https://example.com',
    );
    expect(
      terminal.hyperlinkAt(const CellOffset(4, 0)),
      'https://example.com',
    );
  });

  test('Terminal insert blank chars clears hyperlinks pushed past line end',
      () {
    final terminal = Terminal()..resize(3, 1);

    terminal.write('\x1b]8;;https://example.com\x1b\\ABC');
    terminal.write('\r\x1b[3@');

    final line = terminal.buffer.lines[0];
    for (var column = 0; column < 3; column++) {
      expect(line.getCodePoint(column), 0);
    }
    for (var column = 0; column < 3; column++) {
      expect(terminal.hyperlinkAt(CellOffset(column, 0)), isNull);
    }
  });

  test('Terminal delete chars shifts hyperlinks without linking tail blanks',
      () {
    final terminal = Terminal()..resize(5, 1);

    terminal.write('A\x1b]8;;https://example.com\x1b\\BCD');
    terminal.write('\r\x1b[P');

    final line = terminal.buffer.lines[0];
    expect(line.getText(0, 3), 'BCD');
    expect(line.getCodePoint(3), 0);
    expect(terminal.hyperlinkAt(const CellOffset(0, 0)), 'https://example.com');
    expect(terminal.hyperlinkAt(const CellOffset(2, 0)), 'https://example.com');
    expect(terminal.hyperlinkAt(const CellOffset(3, 0)), isNull);
  });

  test('Terminal scroll up clears stale hyperlink cells', () {
    final terminal = Terminal()..resize(5, 5);

    terminal.write('\x1b]8;;https://example.com\x1b\\ABC\x1b]8;;\x1b\\');
    terminal.write('\r\nDEF\r\nGHI');
    terminal.write('\x1b[2;2H\x1b[S');

    expect(terminal.buffer.lines[0].getText(0, 3), 'DEF');
    expect(terminal.buffer.lines[1].getText(0, 3), 'GHI');
    for (var column = 0; column < 3; column++) {
      expect(terminal.hyperlinkAt(CellOffset(column, 0)), isNull);
      expect(terminal.hyperlinkAt(CellOffset(column, 1)), isNull);
    }
  });

  test('Terminal screen switching clears active OSC 8 hyperlink state', () {
    final terminal = Terminal()..resize(5, 2);

    terminal.write('\x1b]8;;https://example.com/main\x1b\\A');
    terminal.write('\x1b[?1049hB');

    expect(terminal.isUsingAltBuffer, isTrue);
    expect(terminal.hyperlinkAt(const CellOffset(0, 0)), isNull);

    terminal.write('\x1b]8;;https://example.com/alt\x1b\\C');
    expect(
      terminal.hyperlinkAt(const CellOffset(1, 0)),
      'https://example.com/alt',
    );

    terminal.write('\x1b[?1049lD');

    expect(terminal.isUsingAltBuffer, isFalse);
    expect(
      terminal.hyperlinkAt(const CellOffset(0, 0)),
      'https://example.com/main',
    );
    expect(terminal.hyperlinkAt(const CellOffset(1, 0)), isNull);
  });
}

String _hexEncode(String value) {
  return value.codeUnits.map((unit) {
    return unit.toRadixString(16).padLeft(2, '0').toUpperCase();
  }).join();
}

class _TestInputHandler implements TerminalInputHandler {
  final events = <TerminalKeyboardEvent>[];

  @override
  String? call(TerminalKeyboardEvent event) {
    events.add(event);
    return null;
  }
}
