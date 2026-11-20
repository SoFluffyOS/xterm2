import 'package:test/test.dart';
import 'package:xterm2_core/xterm2_core.dart';

void main() {
  test('a Cyrillic line goes down the fast path in one run', () {
    final terminal = _Runs();

    terminal.write('строка съешь');

    expect(terminal.runs, ['строка съешь']);
    expect(terminal.buffer.lines[0].getText(), 'строка съешь');
  });

  test('a wide character ends the run', () {
    final terminal = _Runs();

    terminal.write('жж漢жж');

    expect(terminal.runs, ['жж', 'жж']);
    expect(terminal.buffer.lines[0].getText(), 'жж漢жж');
    expect(terminal.buffer.cursorX, 6);
  });

  test('a combining character ends the run', () {
    final terminal = _Runs();

    terminal.write('жж\u0301жж');

    expect(terminal.runs, ['жж', 'жж']);
    expect(terminal.buffer.lines[0].getCombiningCharacters(1), '\u0301');
    expect(terminal.buffer.cursorX, 4);
  });

  test('a handler of ASCII text alone still gets ASCII alone', () {
    final handler = _AsciiOnly();
    final parser = EscapeParser(handler);

    parser.write('ab жж cd');

    expect(handler.texts, ['ab ', ' cd']);
    expect(String.fromCharCodes(handler.chars), 'жж');
  });

  test('the fast path leaves the buffer as the slow path does', () {
    const inputs = <(String, int, String)>[
      (
        'colours',
        80,
        '\x1b[1;31mкрасный\x1b[0m и \x1b[4:3;58;2;10;20;30mподчёркнутый\x1b[0m',
      ),
      (
        'a link',
        80,
        '\x1b]8;;https://example.com\x1b\\ссылка\x1b]8;;\x1b\\ после',
      ),
      ('a wrap', 10, 'строка, длиннее десяти клеток'),
      ('over a wide character', 80, '漢字漢字\r\x1b[Cжжж'),
      ('DEC graphics', 80, '\x1b(0qqq ж\x1b(B ж'),
      ('insert mode', 80, 'абвгд\r\x1b[4hЖЖ\x1b[4l'),
      ('no wrap', 10, '\x1b[?7lтекст, который не влезает\x1b[?7h'),
      (
        'a frame of Claude Code',
        80,
        '╭─ Привет — «ёлка», cafe\u0301 ж\u0301ж ─╮\r\n│ ✻ Готово │',
      ),
      ('letters that join', 80, '\u0915\u093Eж\u093Eж \u0600жж'),
      (
        'grapheme clustering off',
        80,
        '\x1b[?2027l\u0915\u093Eж\u093Eж строка',
      ),
    ];
    for (final (name, width, data) in inputs) {
      final fast = _Runs()..resize(width, 5);
      final slow = _Slow()..resize(width, 5);

      fast.write(data);
      slow.write(data);

      expect(
        fast.runs.any((run) => run.codeUnits.any((unit) => unit > 0x7f)),
        isTrue,
        reason: '$name: a letter outside ASCII went down the fast path',
      );
      _expectSameBuffer(fast, slow, name);
    }
  });
}

/// An escape handler that takes text in runs but knows nothing of
/// [EscapeNarrowTextHandler].
class _AsciiOnly implements EscapeHandler, EscapeTextHandler {
  final texts = <String>[];

  final chars = <int>[];

  @override
  void writeText(String text, int start, int end) {
    texts.add(text.substring(start, end));
  }

  @override
  void writeChar(int char) => chars.add(char);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Keeps every run that starts outside ASCII the parser hands over in one go.
class _Runs extends Terminal {
  final runs = <String>[];

  @override
  void writeNarrowText(String text, int start, int end) {
    runs.add(text.substring(start, end));
    super.writeNarrowText(text, start, end);
  }
}

/// The slow path: one writeChar a code unit, the way every letter outside
/// ASCII went before.
class _Slow extends Terminal {
  @override
  void writeNarrowText(String text, int start, int end) {
    for (var index = start; index < end; index++) {
      writeChar(text.codeUnitAt(index));
    }
  }
}

void _expectSameBuffer(Terminal fast, Terminal slow, String name) {
  final lines = fast.buffer.lines;
  final expected = slow.buffer.lines;
  expect(lines.length, expected.length, reason: name);
  for (var y = 0; y < lines.length; y++) {
    final line = lines[y];
    final other = expected[y];
    expect(line.length, other.length, reason: '$name, line $y');
    expect(line.isWrapped, other.isWrapped, reason: '$name, line $y');
    for (var x = 0; x < line.length; x++) {
      final at = '$name, cell $x of line $y';
      expect(line.getContent(x), other.getContent(x), reason: at);
      expect(line.getForeground(x), other.getForeground(x), reason: at);
      expect(line.getBackground(x), other.getBackground(x), reason: at);
      expect(line.getAttributes(x), other.getAttributes(x), reason: at);
      expect(line.getUnderlineColor(x), other.getUnderlineColor(x), reason: at);
      expect(
        line.getCombiningCharacters(x),
        other.getCombiningCharacters(x),
        reason: at,
      );
      expect(
        line.getSemanticContent(x),
        other.getSemanticContent(x),
        reason: at,
      );
    }
  }
  expect(fast.buffer.cursorX, slow.buffer.cursorX, reason: name);
  expect(fast.buffer.cursorY, slow.buffer.cursorY, reason: name);
}
