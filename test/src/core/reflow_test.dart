import 'package:test/test.dart';
import 'package:xterm2/src/terminal.dart';

void main() {
  test('reflow() can reflow a single line', () {
    final terminal = Terminal();

    terminal.write('1234567890abcdefg');
    terminal.resize(10, 10);

    expect(terminal.buffer.lines[0].toString(), '1234567890');
    expect(terminal.buffer.lines[1].toString(), 'abcdefg');
    expect(terminal.buffer.lines[0].isWrapped, isFalse);
    expect(terminal.buffer.lines[1].isWrapped, isTrue);

    terminal.resize(13, 10);

    expect(terminal.buffer.lines[0].toString(), '1234567890abc');
    expect(terminal.buffer.lines[1].toString(), 'defg');
    expect(terminal.buffer.lines[0].isWrapped, isFalse);
    expect(terminal.buffer.lines[1].isWrapped, isTrue);

    terminal.resize(20, 10);

    expect(terminal.buffer.lines[0].toString(), '1234567890abcdefg');
    expect(terminal.buffer.lines[0].isWrapped, isFalse);
  });

  test('reflow() can reflow a single line to multiple lines', () {
    final terminal = Terminal();

    terminal.write('1234567890abcdefg');
    terminal.resize(5, 10);

    expect(terminal.buffer.lines[0].toString(), '12345');
    expect(terminal.buffer.lines[1].toString(), '67890');
    expect(terminal.buffer.lines[2].toString(), 'abcde');
    expect(terminal.buffer.lines[3].toString(), 'fg');

    expect(terminal.buffer.lines[0].isWrapped, isFalse);
    expect(terminal.buffer.lines[1].isWrapped, isTrue);
    expect(terminal.buffer.lines[2].isWrapped, isTrue);
    expect(terminal.buffer.lines[3].isWrapped, isTrue);

    terminal.resize(6, 10);

    expect(terminal.buffer.lines[0].toString(), '123456');
    expect(terminal.buffer.lines[1].toString(), '7890ab');
    expect(terminal.buffer.lines[2].toString(), 'cdefg');

    expect(terminal.buffer.lines[0].isWrapped, isFalse);
    expect(terminal.buffer.lines[1].isWrapped, isTrue);
    expect(terminal.buffer.lines[2].isWrapped, isTrue);
  });

  test('reflow() can reflow wide characters', () {
    final terminal = Terminal();

    terminal.write('床前明月光疑是地上霜');
    terminal.resize(10, 10);

    expect(terminal.buffer.lines[0].toString(), '床前明月光');
    expect(terminal.buffer.lines[1].toString(), '疑是地上霜');

    terminal.resize(9, 10);

    expect(terminal.buffer.lines[0].toString(), '床前明月');
    expect(terminal.buffer.lines[1].toString(), '光疑是地');
    expect(terminal.buffer.lines[2].toString(), '上霜');

    terminal.resize(11, 10);

    expect(terminal.buffer.lines[0].toString(), '床前明月光');
    expect(terminal.buffer.lines[1].toString(), '疑是地上霜');

    terminal.resize(13, 10);
    expect(terminal.buffer.lines[0].toString(), '床前明月光疑');
    expect(terminal.buffer.lines[1].toString(), '是地上霜');
  });

  test('reflow() drops wide characters that cannot fit one column', () {
    final terminal = Terminal()..resize(2, 2);
    terminal.write('界');

    terminal.resize(1, 2);

    expect(terminal.buffer.lines[0].toString(), isEmpty);
    expect(terminal.buffer.lines[0].getCodePoint(0), 0);
    expect(terminal.buffer.lines[0].getWidth(0), 0);
  });

  test('reflow() preserves combining characters', () {
    final terminal = Terminal()..resize(8, 5);
    terminal.write('abcde\u0301fgh');

    terminal.resize(4, 5);

    expect(terminal.buffer.getText(), startsWith('abcde\u0301fgh'));
    expect(terminal.buffer.lines[1].getCombiningCharacters(0), '\u0301');

    terminal.resize(8, 5);

    expect(terminal.buffer.getText(), startsWith('abcde\u0301fgh'));
    expect(terminal.buffer.lines[0].getCombiningCharacters(4), '\u0301');
  });

  test('reflow() tracks cursor when shrinking wrapped content', () {
    final terminal = Terminal()..resize(10, 5);

    terminal.write('1234567890abcdefg');
    expect(terminal.buffer.cursorX, 7);
    expect(terminal.buffer.cursorY, 1);

    terminal.resize(5, 5);

    expect(terminal.buffer.lines[0].toString(), '12345');
    expect(terminal.buffer.lines[1].toString(), '67890');
    expect(terminal.buffer.lines[2].toString(), 'abcde');
    expect(terminal.buffer.lines[3].toString(), 'fg');
    expect(terminal.buffer.cursorX, 2);
    expect(terminal.buffer.absoluteCursorY, 3);
  });

  test('reflow() tracks cursor when growing wrapped content', () {
    final terminal = Terminal()..resize(5, 5);

    terminal.write('1234567890abcdefg');
    expect(terminal.buffer.cursorX, 2);
    expect(terminal.buffer.cursorY, 3);

    terminal.resize(10, 5);

    expect(terminal.buffer.lines[0].toString(), '1234567890');
    expect(terminal.buffer.lines[1].toString(), 'abcdefg');
    expect(terminal.buffer.cursorX, 7);
    expect(terminal.buffer.absoluteCursorY, 1);
  });

  test('lines has correct length after reflow', () {
    final terminal = Terminal();

    terminal.write('1234567890abcdefg');
    terminal.resize(10, 10);

    for (var i = 0; i < 10; i++) {
      expect(terminal.buffer.lines[i].length, 10);
    }

    terminal.resize(13, 10);
    for (var i = 0; i < 10; i++) {
      expect(terminal.buffer.lines[i].length, 13);
    }
  });
}
