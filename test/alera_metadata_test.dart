import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  test('history compaction preserves graphemes, OSC 8 and underline colors',
      () {
    final terminal = Terminal(maxLines: 64)..resize(100, 3);
    addTearDown(terminal.dispose);
    terminal.write('\x1b]8;;https://example.com\x1b\\'
        '\x1b[4;58;2;1;2;3me\u0301界'
        '\x1b]8;;\x1b\\\x1b[0m\r\n2\r\n3\r\n4');
    final line = terminal.buffer.lines[0];
    expect(line.length, 3);
    expect(line.getText(), 'e\u0301界');
    expect(line.getCombiningCharacters(0), '\u0301');
    expect(line.getUnderlineColor(0), isNot(0));
    expect(terminal.hyperlinkAt(const CellOffset(1, 0)), 'https://example.com');
    terminal.resize(2, 3);
    expect(terminal.buffer.getText(), contains('e\u0301界'));
    expect(terminal.hyperlinkAt(const CellOffset(0, 1)), 'https://example.com');
  });

  test('copying beyond compacted storage supplies empty cells', () {
    final source = BufferLine(100)..compact();
    final destination = BufferLine(20);
    destination.copyFrom(source, 10, 0, 20);
    expect(destination.getText(), isEmpty);
  });

  test('clipboard policy sees raw selectors and can deny decoding', () {
    final requests = <String>[];
    final copies = <String>[];
    final terminal = Terminal(
      clipboardDecoder: (selector, encoded) {
        requests.add('$selector:$encoded');
        return selector == 'c' && encoded == 'YQ==' ? 'a' : null;
      },
      onClipboardStore: (_, text) => copies.add(text),
      allowITerm2ClipboardCapture: false,
    );
    addTearDown(terminal.dispose);
    terminal.write('\x1b]52;;YQ==\x07\x1b]52;c;YQ==\x07');
    terminal.write('\x1b]1337;CopyToClipboard=c\x07secret'
        '\x1b]1337;EndCopy\x07');
    expect(requests, [':YQ==', 'c:YQ==']);
    expect(copies, ['a']);
    expect(terminal.buffer.getText(), contains('secret'));
  });

  test('clipboard queries remain silent without a read callback', () async {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);
    terminal.write('\x1b]52;c;?\x07');
    terminal.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(output, isEmpty);
  });
}
