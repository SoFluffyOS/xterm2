import 'package:test/test.dart';
import 'package:xterm2_core/xterm2_core.dart';

void main() {
  group('BufferLine.compact', () {
    test('releases trailing all-zero capacity and keeps the text', () {
      final line = BufferLine(200);
      final text = 'Hello';
      for (var i = 0; i < text.length; i++) {
        line.setCodePoint(i, text.codeUnitAt(i));
      }
      final bytesBefore = line.data.lengthInBytes;

      line.compact();

      expect(line.data.lengthInBytes, lessThan(bytesBefore));
      expect(line.length, equals(text.length));
      expect(line.getText(), equals(text));
    });

    test('keeps cells that only carry a styled erase', () {
      final line = BufferLine(200);
      line.setCodePoint(0, 'a'.codeUnitAt(0));
      final style = CursorStyle();
      style.setBackgroundColor256(4);
      line.eraseRange(1, 40, style);

      line.compact();

      expect(line.length, equals(40));
      expect(line.getBackground(39), equals(style.background));
      expect(line.getText(), equals('a'));
    });

    test('keeps the placeholder cell of a trailing wide character', () {
      final line = BufferLine(200);
      line.setCell(0, '😀'.runes.first, 2, CursorStyle.empty);
      line.setCell(1, 0, 0, CursorStyle.empty);

      line.compact();

      expect(line.length, equals(2));
      expect(line.getWidth(0), equals(2));
    });

    test('skips reallocation when nothing meaningful would be released', () {
      final line = BufferLine(64);
      for (var i = 0; i < 60; i++) {
        line.setCodePoint(i, 'x'.codeUnitAt(0));
      }
      final data = line.data;

      line.compact();

      expect(identical(line.data, data), isTrue);
    });

    test('clamps anchors beyond the compacted length', () {
      final line = BufferLine(200);
      line.setCodePoint(0, 'a'.codeUnitAt(0));
      final anchor = line.createAnchor(150);

      line.compact();

      expect(anchor.x, equals(line.length));
    });

    test('regrows with zero cells through resize', () {
      final line = BufferLine(200);
      line.setCodePoint(0, 'a'.codeUnitAt(0));
      line.compact();

      line.resize(120);

      expect(line.length, equals(120));
      expect(line.getCodePoint(119), equals(0));
      expect(line.getText(), equals('a'));
    });
  });

  group('BufferLine.eraseRange beyond the line length', () {
    test('regrows for a styled erase so the color persists', () {
      final line = BufferLine(10);
      final style = CursorStyle();
      style.setBackgroundColor256(2);

      line.eraseRange(0, 20, style);

      expect(line.length, equals(20));
      expect(line.getBackground(19), equals(style.background));
    });

    test('still clamps a default erase', () {
      final line = BufferLine(10);

      line.eraseRange(0, 20, CursorStyle.empty);

      expect(line.length, equals(10));
    });
  });

  group('Buffer history compaction', () {
    test('compacts rows as they scroll out of the viewport', () {
      final terminal = Terminal(maxLines: 100);
      terminal.resize(80, 5);
      for (var i = 0; i < 20; i++) {
        terminal.write('line $i\r\n');
      }

      final history = terminal.buffer.lines[0];
      expect(history.getText(), equals('line 0'));
      expect(history.data.lengthInBytes, equals(history.length * 16));
      expect(history.length, lessThan(80));

      // Viewport rows keep their full-width allocation for in-place edits.
      final viewportTop = terminal.buffer.scrollBack;
      final viewportRow = terminal.buffer.lines[viewportTop];
      expect(viewportRow.length, greaterThanOrEqualTo(80));
    });

    test('keeps selection word boundaries working on compacted rows', () {
      final terminal = Terminal(maxLines: 100);
      terminal.resize(80, 5);
      for (var i = 0; i < 20; i++) {
        terminal.write('word$i extra\r\n');
      }

      final boundary = terminal.buffer.getWordBoundary(CellOffset(2, 0));
      expect(boundary, isNotNull);
      expect(terminal.buffer.getText(boundary), equals('word0'));

      // Beyond the compacted length reads as empty space, not a crash.
      final empty = terminal.buffer.getWordBoundary(CellOffset(70, 0));
      expect(empty, isNull);
    });

    test('re-compacts history after a width resize', () {
      final terminal = Terminal(maxLines: 100);
      terminal.resize(80, 5);
      for (var i = 0; i < 20; i++) {
        terminal.write('line $i\r\n');
      }

      terminal.resize(120, 5);

      final history = terminal.buffer.lines[0];
      expect(history.getText(), equals('line 0'));
      expect(history.data.lengthInBytes, equals(history.length * 16));
      expect(history.length, lessThan(120));
    });

    test('history text survives shrinking reflow', () {
      final terminal = Terminal(maxLines: 100);
      terminal.resize(80, 5);
      for (var i = 0; i < 20; i++) {
        terminal.write('line $i\r\n');
      }

      terminal.resize(40, 5);

      expect(terminal.buffer.lines[0].getText(), equals('line 0'));
    });
  });
}
