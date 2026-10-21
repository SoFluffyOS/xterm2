import 'package:test/test.dart';
import 'package:xterm2_core/xterm2_core.dart';

void main() {
  group('BufferLine.getText()', () {
    test('should return the text', () {
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(), 'Hello World');
    });

    test('getText() should support wide characters', () {
      final text = '😀😁😂🤣😃';
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      terminal.write(text);
      expect(terminal.buffer.lines[0].getText(), equals(text));
    });

    test('preserves empty cells between selected text columns', () {
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      terminal.resize(30, 5);

      terminal.write('Claude\x1b[1;20HCode');

      expect(
        terminal.buffer.lines[0].getText(0, 23),
        equals('${'Claude'.padRight(19)}Code'),
      );
    });

    test('does not append trailing spaces for implicit ranges', () {
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      terminal.resize(30, 5);

      terminal.write('Hello');

      expect(terminal.buffer.lines[0].getText(), equals('Hello'));
    });

    test('does not insert spaces after wide characters', () {
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      terminal.resize(10, 5);

      terminal.write('😀A');

      expect(terminal.buffer.lines[0].getText(0, 3), equals('😀A'));
    });

    test('keeps zero-width combining marks in the preceding cell', () {
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      terminal.resize(20, 5);

      terminal.write('asi\u0301 nin\u0303o');

      final line = terminal.buffer.lines[0];
      expect(line.getText(), equals('asi\u0301 nin\u0303o'));
      expect(line.getTrimmedLength(), equals(8));
      expect(line.getWidth(2), equals(1));
      expect(line.getWidth(6), equals(1));

      expect(line.getCodePoint(2), 'i'.codeUnitAt(0));
      expect(line.getCombiningCharacters(2), '\u0301');

      expect(line.getCodePoint(6), 'n'.codeUnitAt(0));
      expect(line.getCombiningCharacters(6), '\u0303');
    });

    test('renders leading combining marks as spacing cells', () {
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      terminal.resize(10, 5);

      terminal.write('\u0301a');

      final line = terminal.buffer.lines[0];
      expect(line.getText(), equals('\u0301a'));
      expect(line.getTrimmedLength(), equals(2));
      expect(line.getWidth(0), equals(1));
    });

    test('keeps combining marks on the final column before wrap', () {
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      terminal.resize(3, 5);

      terminal.write('abi\u0301');

      expect(terminal.buffer.lines[0].getText(), equals('abi\u0301'));
      expect(terminal.buffer.lines[1].getText(), isEmpty);
    });

    test('can specify a range', () {
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(0, 5), 'Hello');
    });

    test('can handle invalid ranges', () {
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(0, 100), 'Hello World');
    });

    test('can handle negative ranges', () {
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(-100, 100), 'Hello World');
    });

    test('can handle reversed ranges', () {
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(5, 0), '');
    });
  });

  group('BufferLine.getTrimmedLength()', () {
    test('can get trimmed length', () {
      final line = BufferLine(10);

      final text = 'ABCDEF';

      for (var i = 0; i < text.length; i++) {
        line.setCodePoint(i, text.codeUnitAt(i));
      }

      expect(line.getTrimmedLength(), equals(text.length));
    });

    test('can get trimmed length with wide characters', () {
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      final text = '😀😁😂🤣😃';

      terminal.write(text);

      expect(terminal.buffer.lines[0].getTrimmedLength(), equals(text.length));
    });

    test('can handle length larger than the line', () {
      final line = BufferLine(10);

      final text = 'ABCDEF';

      for (var i = 0; i < text.length; i++) {
        line.setCodePoint(i, text.codeUnitAt(i));
      }

      expect(line.getTrimmedLength(1000), equals(text.length));
    });

    test('can handle negative start', () {
      final line = BufferLine(10);

      final text = 'ABCDEF';

      for (var i = 0; i < text.length; i++) {
        line.setCodePoint(i, text.codeUnitAt(i));
      }

      expect(line.getTrimmedLength(-1000), equals(0));
    });
  });

  group('BufferLine.resize', () {
    test('can resize', () {
      final line = BufferLine(10);

      final text = 'ABCDEF';

      for (var i = 0; i < text.length; i++) {
        line.setCodePoint(i, text.codeUnitAt(i));
      }

      line.resize(20);

      expect(line.length, equals(20));
    });
  });

  group('BufferLine.eraseRange', () {
    test('ignores a range that starts after the line', () {
      final line = BufferLine(512);
      line.setCodePoint(0, 'a'.codeUnitAt(0));

      line.eraseRange(844, 1050, CursorStyle.empty);

      expect(line.getCodePoint(0), equals('a'.codeUnitAt(0)));
    });

    test('ignores an empty range at the start of the line', () {
      final line = BufferLine(10);
      line.setCodePoint(0, 'a'.codeUnitAt(0));

      line.eraseRange(0, 0, CursorStyle.empty);

      expect(line.getCodePoint(0), equals('a'.codeUnitAt(0)));
    });
  });

  group('Buffer.createAnchor', () {
    test('works', () {
      final terminal = Terminal(
          reflowWithHiddenCursor: false, preserveOrphanCombiningMarks: true);
      final line = terminal.buffer.lines[3];
      final anchor = line.createAnchor(5);

      terminal.insertLines(5);
      expect(anchor.x, 5);
      expect(anchor.y, 8);

      terminal.buffer.clear();
      expect(line.attached, false);
      expect(anchor.attached, false);
    });
  });
}
