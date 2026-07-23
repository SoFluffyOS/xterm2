import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  test('Terminal search finds literal text case-insensitively', () {
    final terminal = Terminal()..resize(40, 2);
    terminal.write('Hello hello');

    final matches = terminal.search('hello');

    expect(matches, hasLength(2));
    expect(matches.first.text, 'Hello');
    expect(matches.first.range.begin, const CellOffset(0, 0));
    expect(matches.first.range.end, const CellOffset(5, 0));
    expect(matches.last.range.begin, const CellOffset(6, 0));
    expect(matches.last.range.end, const CellOffset(11, 0));
    expect(terminal.search('hello', caseSensitive: true), hasLength(1));
  });

  test('Terminal search spans soft-wrapped rows but not hard line breaks', () {
    final wrapped = Terminal()..resize(4, 3);
    wrapped.write('abcdef');

    final wrappedMatch = wrapped.search('cdef').single;
    expect(wrappedMatch.range.begin, const CellOffset(2, 0));
    expect(wrappedMatch.range.end, const CellOffset(2, 1));

    final hardBreak = Terminal()..resize(4, 3);
    hardBreak.write('ab\r\ncd');
    expect(hardBreak.search('bc'), isEmpty);
  });

  test('Terminal search preserves visual blank cells', () {
    final terminal = Terminal()..resize(20, 2);
    terminal.write('a\x1b[6Gb');

    expect(terminal.search('ab'), isEmpty);
    final match = terminal.search('a    b').single;
    expect(match.range.begin, const CellOffset(0, 0));
    expect(match.range.end, const CellOffset(6, 0));
  });

  test('Terminal search maps wide and combining graphemes to cells', () {
    final terminal = Terminal()..resize(20, 2);
    terminal.write('a😀b e\u0301');

    final emoji = terminal.search('😀').single;
    expect(emoji.range.begin, const CellOffset(1, 0));
    expect(emoji.range.end, const CellOffset(3, 0));

    final combiningMark = terminal.search('\u0301').single;
    expect(combiningMark.range.begin, const CellOffset(5, 0));
    expect(combiningMark.range.end, const CellOffset(6, 0));
  });

  test('Terminal search supports Unicode-aware whole words', () {
    final terminal = Terminal()..resize(40, 2);
    terminal.write('café cafe\u0301 caféine');

    final matches = terminal.search('café', wholeWord: true);

    expect(matches.map((match) => match.text), ['café']);
  });

  test('Terminal search supports regular expressions', () {
    final terminal = Terminal()..resize(40, 2);
    terminal.write('item-12 item-345');

    final matches = terminal.search(r'item-\d+', useRegex: true);

    expect(matches.map((match) => match.text), ['item-12', 'item-345']);
    expect(
      () => terminal.search('[', useRegex: true),
      throwsFormatException,
    );
  });

  test('Terminal search bounds allocated results', () {
    final terminal = Terminal()..resize(40, 2);
    terminal.write('a a a a a a');

    final matches = terminal.search('a', maxResults: 3);

    expect(matches, hasLength(3));
    expect(terminal.search('a', maxResults: 0), isEmpty);
  });

  test('Terminal search uses the active alternate buffer only', () {
    final terminal = Terminal()..resize(40, 2);
    terminal.write('main text');
    terminal.useAltBuffer();
    terminal.write('alternate text');

    expect(terminal.search('main'), isEmpty);
    expect(terminal.search('alternate'), hasLength(1));
  });
}
