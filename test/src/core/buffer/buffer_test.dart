import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('Buffer.writeChar()', () {
    test('shifts cells in insert mode', () {
      final terminal = Terminal()..resize(5, 3);
      terminal.write('abcde\r\x1b[2C\x1b[4hX');

      expect(terminal.buffer.lines[0].toString(), 'abXcd');
    });

    test('shifts two cells for wide glyphs in insert mode', () {
      final terminal = Terminal()..resize(6, 3);
      terminal.write('abcd\r\x1b[C\x1b[4h界');

      expect(terminal.buffer.lines[0].toString(), 'a界bcd');
      expect(terminal.buffer.lines[0].getWidth(1), 2);
      expect(terminal.buffer.lines[0].getWidth(2), 0);
    });

    test('overwrites cells after insert mode is disabled', () {
      final terminal = Terminal()..resize(5, 3);
      terminal.write('abcde\r\x1b[2C\x1b[4hX\x1b[4lY');

      expect(terminal.buffer.lines[0].toString(), 'abXYd');
    });

    test('wraps a wide character before the right margin', () {
      final terminal = Terminal()..resize(4, 3);

      terminal.write('abc界');

      expect(terminal.buffer.lines[0].toString(), 'abc');
      expect(terminal.buffer.lines[1].toString(), '界');
      expect(terminal.buffer.lines[1].isWrapped, isTrue);
      expect(terminal.buffer.lines[1].getWidth(0), 2);
      expect(terminal.buffer.lines[1].getWidth(1), 0);
      expect(terminal.buffer.cursorX, 2);
      expect(terminal.buffer.cursorY, 1);
      expect(terminal.buffer.getText(), startsWith('abc界'));
    });

    test('overwrites the last column when autowrap is disabled', () {
      final terminal = Terminal()..resize(4, 3);
      terminal.write('\x1b[?7labcdX');

      expect(terminal.buffer.lines[0].toString(), 'abcX');
      expect(terminal.buffer.cursorY, 0);
    });

    test('suppresses a wide character that cannot fit without wrap', () {
      final terminal = Terminal()..resize(4, 3);
      terminal.write('\x1b[?7labc界X');

      expect(terminal.buffer.lines[0].toString(), 'abcX');
      expect(terminal.buffer.cursorY, 0);
    });

    test('overwriting wide glyph trailing spacer clears the wide glyph', () {
      final terminal = Terminal()..resize(4, 3);
      terminal.write('界\r\x1b[CX');

      final line = terminal.buffer.lines[0];
      expect(line.toString(), 'X');
      expect(line.getCodePoint(0), 0);
      expect(line.getWidth(0), 0);
      expect(line.getCodePoint(1), 'X'.codeUnitAt(0));
      expect(line.getWidth(1), 1);
    });

    test('overwriting across a wide glyph clears its spacer', () {
      final terminal = Terminal()..resize(5, 3);
      terminal.write('a界d\r界');

      final line = terminal.buffer.lines[0];
      expect(line.toString(), '界d');
      expect(line.getWidth(0), 2);
      expect(line.getWidth(1), 0);
      expect(line.getCodePoint(2), 0);
      expect(line.getWidth(2), 0);
      expect(line.getCodePoint(3), 'd'.codeUnitAt(0));
    });
  });

  group('Buffer.getText()', () {
    test('should return the text', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.getText(), startsWith('Hello World'));
    });

    test('can handle line wrap', () {
      final terminal = Terminal();
      terminal.resize(10, 10);

      final line1 = 'This is a long line that should wrap';
      final line2 = 'This is a short line';
      final line3 = 'This is a long long long long line that should wrap';
      final line4 = 'Short';

      terminal.write('$line1\r\n');
      terminal.write('$line2\r\n');
      terminal.write('$line3\r\n');
      terminal.write('$line4\r\n');

      final lines = terminal.buffer.getText().split('\n');
      expect(lines[0], line1);
      expect(lines[1], line2);
      expect(lines[2], line3);
      expect(lines[3], line4);
    });

    test('can handle negative start', () {
      final terminal = Terminal();

      terminal.write('Hello World');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(-100, -100), CellOffset(100, 100)),
        ),
        startsWith('Hello World'),
      );
    });

    test('can handle invalid end', () {
      final terminal = Terminal();

      terminal.write('Hello World');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(0, 0), CellOffset(100, 100)),
        ),
        startsWith('Hello World'),
      );
    });

    test('can handle reversed range', () {
      final terminal = Terminal();

      terminal.write('Hello World');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(5, 5), CellOffset(0, 0)),
        ),
        startsWith('Hello World'),
      );
    });

    test('can handle block range', () {
      final terminal = Terminal();

      terminal.write('Hello World\r\n');
      terminal.write('Nice to meet you\r\n');

      expect(
        terminal.buffer.getText(
          BufferRangeBlock(CellOffset(2, 0), CellOffset(5, 1)),
        ),
        startsWith('llo\nce '),
      );
    });
  });

  group('Buffer.resize()', () {
    test('should resize the buffer', () {
      final terminal = Terminal();
      terminal.resize(10, 10);

      expect(terminal.viewWidth, 10);
      expect(terminal.viewHeight, 10);

      for (var i = 0; i < terminal.lines.length; i++) {
        final line = terminal.lines[i];
        expect(line.length, 10);
      }

      terminal.resize(20, 20);

      expect(terminal.viewWidth, 20);
      expect(terminal.viewHeight, 20);

      for (var i = 0; i < terminal.lines.length; i++) {
        final line = terminal.lines[i];
        expect(line.length, 20);
      }
    });
  });

  group('Buffer.deleteLines()', () {
    test('works', () {
      final terminal = Terminal();
      terminal.resize(10, 10);

      for (var i = 1; i <= 10; i++) {
        terminal.write('line$i');

        if (i < 10) {
          terminal.write('\r\n');
        }
      }

      terminal.setMargins(3, 7);
      terminal.setCursor(0, 5);

      terminal.buffer.deleteLines(1);

      expect(terminal.buffer.lines[2].toString(), 'line3');
      expect(terminal.buffer.lines[3].toString(), 'line4');
      expect(terminal.buffer.lines[4].toString(), 'line5');
      expect(terminal.buffer.lines[5].toString(), 'line7');
      expect(terminal.buffer.lines[6].toString(), 'line8');
      expect(terminal.buffer.lines[7].toString(), '');
      expect(terminal.buffer.lines[8].toString(), 'line9');
      expect(terminal.buffer.lines[9].toString(), 'line10');
    });
  });

  group('Buffer.insertLines()', () {
    test('works', () {
      final terminal = Terminal();

      for (var i = 0; i < 10; i++) {
        terminal.write('line$i\r\n');
      }

      print(terminal.buffer);

      terminal.setMargins(2, 6);
      terminal.setCursor(0, 4);

      print(terminal.buffer.absoluteCursorY);

      terminal.buffer.insertLines(1);

      print(terminal.buffer);

      expect(terminal.buffer.lines[3].toString(), 'line3');
      expect(terminal.buffer.lines[4].toString(), ''); // inserted
      expect(terminal.buffer.lines[5].toString(), 'line4'); // moved
      expect(terminal.buffer.lines[6].toString(), 'line5'); // moved
      expect(terminal.buffer.lines[7].toString(), 'line7');
    });

    test('has no effect if cursor is out of scroll region', () {
      final terminal = Terminal();

      for (var i = 0; i < 10; i++) {
        terminal.write('line$i\r\n');
      }

      terminal.setMargins(2, 6);
      terminal.setCursor(0, 1);

      terminal.buffer.insertLines(1);

      expect(terminal.buffer.lines[2].toString(), 'line2');
      expect(terminal.buffer.lines[3].toString(), 'line3');
      expect(terminal.buffer.lines[4].toString(), 'line4');
      expect(terminal.buffer.lines[5].toString(), 'line5');
      expect(terminal.buffer.lines[6].toString(), 'line6');
      expect(terminal.buffer.lines[7].toString(), 'line7');
    });
  });

  group('Buffer.getWordBoundary supports custom word separators', () {
    test('can set word separators', () {
      final terminal = Terminal(wordSeparators: {'o'.codeUnitAt(0)});

      terminal.write('Hello World');

      expect(
        terminal.mainBuffer.getWordBoundary(CellOffset(0, 0)),
        BufferRangeLine(CellOffset(0, 0), CellOffset(4, 0)),
      );

      expect(
        terminal.mainBuffer.getWordBoundary(CellOffset(5, 0)),
        BufferRangeLine(CellOffset(5, 0), CellOffset(7, 0)),
      );
    });
  });

  test('does not delete lines beyond the scroll region', () {
    final terminal = Terminal();
    terminal.resize(10, 10);

    for (var i = 1; i <= 10; i++) {
      terminal.write('line$i');

      if (i < 10) {
        terminal.write('\r\n');
      }
    }

    terminal.setMargins(3, 7);
    terminal.setCursor(0, 5);

    terminal.buffer.deleteLines(20);

    expect(terminal.buffer.lines[2].toString(), 'line3');
    expect(terminal.buffer.lines[3].toString(), 'line4');
    expect(terminal.buffer.lines[4].toString(), 'line5');
    expect(terminal.buffer.lines[5].toString(), '');
    expect(terminal.buffer.lines[6].toString(), '');
    expect(terminal.buffer.lines[7].toString(), '');
    expect(terminal.buffer.lines[8].toString(), 'line9');
    expect(terminal.buffer.lines[9].toString(), 'line10');
  });

  group('Buffer.eraseDisplayFromCursor()', () {
    test('works', () {
      final terminal = Terminal();
      terminal.resize(3, 3);
      terminal.write('123\r\n456\r\n789');

      terminal.setCursor(1, 1);
      terminal.buffer.eraseDisplayFromCursor();

      expect(terminal.buffer.lines[0].toString(), '123');
      expect(terminal.buffer.lines[1].toString(), '4');
      expect(terminal.buffer.lines[2].toString(), '');
    });
  });

  group('Buffer.eraseLineToCursor()', () {
    test('erases the cursor cell', () {
      final terminal = Terminal();
      terminal.resize(5, 3);
      terminal.write('abcde');

      terminal.setCursor(2, 0);
      terminal.buffer.eraseLineToCursor();

      expect(terminal.buffer.lines[0].toString(), 'de');
      expect(terminal.buffer.lines[0].getCodePoint(2), 0);
    });
  });

  group('Buffer.eraseDisplayToCursor()', () {
    test('erases the cursor cell', () {
      final terminal = Terminal();
      terminal.resize(3, 3);
      terminal.write('123\r\n456\r\n789');

      terminal.setCursor(1, 1);
      terminal.buffer.eraseDisplayToCursor();

      expect(terminal.buffer.lines[0].toString(), '');
      expect(terminal.buffer.lines[1].toString(), '6');
      expect(terminal.buffer.lines[1].getCodePoint(1), 0);
      expect(terminal.buffer.lines[2].toString(), '789');
    });
  });
}
