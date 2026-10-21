import 'package:test/test.dart';
import 'package:xterm2_core/src/terminal.dart';

void main() {
  test('reflow() can reflow a single line', () {
    final terminal = Terminal(reflowWithHiddenCursor: false);

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
    final terminal = Terminal(reflowWithHiddenCursor: false);

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
    final terminal = Terminal(reflowWithHiddenCursor: false);

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

  test('lines has correct length after reflow', () {
    final terminal = Terminal(reflowWithHiddenCursor: false);

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

  group('a hidden cursor in the main buffer', () {
    // DECTCEM off: what every full-screen agent CLI leaves set for as long as
    // it runs, which is also the state a restored session ends in.
    const hideCursor = '\x1b[?25l';

    test('truncates the buffer on resize by default', () {
      final terminal = Terminal(reflowWithHiddenCursor: false)..resize(20, 10);

      terminal.write('${hideCursor}1234567890abcdefg');
      terminal.resize(10, 10);

      // The application is expected to redraw, so its cells are dropped
      // rather than reflowed.
      expect(terminal.buffer.lines[0].toString(), '1234567890');
      expect(terminal.buffer.lines[1].toString(), isEmpty);
    });

    test('still reflows when the buffer holds restored history', () {
      final terminal = Terminal(reflowWithHiddenCursor: true)..resize(20, 10);

      terminal.write('${hideCursor}1234567890abcdefg');
      terminal.resize(10, 10);

      expect(terminal.buffer.lines[0].toString(), '1234567890');
      expect(terminal.buffer.lines[1].toString(), 'abcdefg');
      expect(terminal.buffer.lines[1].isWrapped, isTrue);
    });

    test('keeps scrollback that a wider viewport would have trimmed', () {
      final terminal = Terminal(maxLines: 100, reflowWithHiddenCursor: true)
        ..resize(20, 4);

      terminal.write(hideCursor);
      for (var line = 0; line < 12; line++) {
        terminal.write('line-$line\r\n');
      }
      final before = terminal.buffer.lines.length;

      terminal.resize(20, 8);

      // Growing the viewport consumed scrollback to fill it, which for
      // restored history is history the user came to read.
      expect(terminal.buffer.lines.length, before);
      expect(terminal.buffer.lines[0].toString(), 'line-0');
    });
  });
}
