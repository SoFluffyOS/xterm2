import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('BufferLine.getText()', () {
    test('preserves combining characters on the base cell', () {
      final terminal = Terminal();

      terminal.write('e\u0301');

      final line = terminal.buffer.lines[0];
      expect(line.getText(), 'e\u0301');
      expect(line.getCombiningCharacters(0), '\u0301');
      expect(terminal.buffer.cursorX, 1);
    });

    test('preserves zero-width joiner emoji as one terminal glyph', () {
      final terminal = Terminal();
      const family = '👨‍👩‍👧‍👦';

      terminal.write(family);

      final line = terminal.buffer.lines[0];
      expect(line.getText(), family);
      expect(line.getCombiningCharacters(0), '‍👩‍👧‍👦');
      expect(terminal.buffer.cursorX, 2);
    });

    test('preserves emoji modifiers and regional indicator pairs', () {
      final terminal = Terminal();

      terminal.write('👍🏽🇻🇳🇺');

      final line = terminal.buffer.lines[0];
      expect(line.getText(), '👍🏽🇻🇳🇺');
      expect(line.getCombiningCharacters(0), '🏽');
      expect(line.getCombiningCharacters(2), '🇳');
      expect(line.getWidth(2), 2);
      expect(line.getWidth(3), 0);
      expect(terminal.buffer.cursorX, 5);
    });

    test('bounds combining characters per cell', () {
      final terminal = Terminal();

      terminal.write('e${'\u0301' * 20}');

      final combining = terminal.buffer.lines[0].getCombiningCharacters(0);
      expect(combining?.runes.length, 16);
    });

    test('should return the text', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(), 'Hello World');
    });

    test('getText() should support wide characters', () {
      final text = '😀😁😂🤣😃';
      final terminal = Terminal();
      terminal.write(text);
      expect(terminal.buffer.lines[0].getText(), equals(text));
    });

    test('can specify a range', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(0, 5), 'Hello');
    });

    test('can handle invalid ranges', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(0, 100), 'Hello World');
    });

    test('can handle negative ranges', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.lines[0].getText(-100, 100), 'Hello World');
    });

    test('can handle reversed ranges', () {
      final terminal = Terminal();
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
      final terminal = Terminal();
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

    test('preserves hidden combining characters across shrink and grow', () {
      final line = BufferLine(10);
      line.setCodePoint(5, 'e'.codeUnitAt(0));
      line.addCombiningCharacter(5, 0x0301);

      line.resize(3);
      line.resize(10);

      expect(line.getCombiningCharacters(5), '\u0301');
      expect(line.getText(), 'e\u0301');
    });
  });

  group('BufferLine combining character mutations', () {
    test('moves combining characters when cells are inserted and removed', () {
      final terminal = Terminal();
      terminal.write('e\u0301b');
      final line = terminal.buffer.lines[0];

      line.insertCells(0, 1);
      expect(line.getCombiningCharacters(1), '\u0301');
      expect(line.getText(), 'e\u0301b');

      line.removeCells(0, 1);
      expect(line.getCombiningCharacters(0), '\u0301');
      expect(line.getText(), 'e\u0301b');
    });

    test('clears combining characters when a cell is erased', () {
      final terminal = Terminal();
      terminal.write('e\u0301');
      final line = terminal.buffer.lines[0];

      line.eraseCell(0, CursorStyle.empty);

      expect(line.getCombiningCharacters(0), isNull);
    });
  });

  group('BufferLine anchors', () {
    test('move with content shifted by inserted cells', () {
      final terminal = Terminal()..resize(5, 1);
      terminal.write('abcde');
      final line = terminal.buffer.lines[0];
      final startAnchor = line.createAnchor(0);
      final middleAnchor = line.createAnchor(2);
      final droppedAnchor = line.createAnchor(4);

      line.insertCells(0, 1);

      expect(line.getText(), 'abcd');
      expect(startAnchor.attached, isTrue);
      expect(startAnchor.x, 1);
      expect(middleAnchor.attached, isTrue);
      expect(middleAnchor.x, 3);
      expect(droppedAnchor.attached, isFalse);
    });
  });

  group('Buffer.createAnchor', () {
    test('works', () {
      final terminal = Terminal();
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

  test('BufferLine.dispose detaches every anchor', () {
    final line = BufferLine(10);
    final anchors = [line.createAnchor(1), line.createAnchor(2)];

    line.dispose();

    expect(anchors.every((anchor) => anchor.line == null), isTrue);
    expect(line.anchors, isEmpty);
  });

  test('createCellData returns a non-destructive cell snapshot', () {
    final line = BufferLine(2);
    final style = CursorStyle()
      ..foreground = 0x123
      ..background = 0x456
      ..underlineColor = 0x789
      ..setBold();
    line.setCell(0, 0x41, 1, style);

    final cell = line.createCellData(0);

    expect(cell.foreground, 0x123);
    expect(cell.background, 0x456);
    expect(cell.underlineColor, 0x789);
    expect(cell.flags & CellAttr.bold, isNot(0));
    expect(cell.content & CellContent.codepointMask, 0x41);
    expect(line.getCodePoint(0), 0x41);
  });
}
