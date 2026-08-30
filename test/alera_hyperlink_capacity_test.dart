import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  test('full hyperlink tables preserve links and eventually reclaim erasures',
      () {
    final terminal = _fullHyperlinkTerminal();
    addTearDown(terminal.dispose);
    terminal.setHyperlink('', 'https://example.com/full');
    expect(terminal.cursor.hyperlinkId, 0);
    terminal.write('\x1b[1;1H ');

    for (var attempt = 0; attempt <= 256; attempt++) {
      terminal.setHyperlink('', 'https://example.com/reclaimed');
      if (terminal.cursor.hyperlinkId != 0) break;
    }
    expect(terminal.cursor.hyperlinkId, isNot(0));
    terminal.write('\x1b[1;1Hx');
    terminal.setHyperlink('', '');
    expect(terminal.hyperlinkAt(const CellOffset(0, 0)),
        'https://example.com/reclaimed');
    expect(
        terminal.hyperlinkAt(const CellOffset(1, 0)), 'https://example.com/1');

    // Reclaiming a single slot must still allow another erasure to recover.
    terminal.write('\x1b[1;1H ');
    for (var attempt = 0; attempt <= 256; attempt++) {
      terminal.setHyperlink('', 'https://example.com/later');
      if (terminal.cursor.hyperlinkId != 0) break;
    }
    expect(terminal.cursor.hyperlinkId, isNot(0));
  });

  test('reset permits fresh hyperlinks after a full registry', () {
    final terminal = _fullHyperlinkTerminal();
    addTearDown(terminal.dispose);
    terminal.setHyperlink('', 'https://example.com/full');
    terminal.reset();
    terminal.write('\x1b]8;;https://example.com/fresh\x1b\\x');
    expect(terminal.hyperlinkAt(const CellOffset(0, 0)),
        'https://example.com/fresh');
  });
}

Terminal _fullHyperlinkTerminal() {
  final terminal = Terminal(maxLines: 100)..resize(128, 40);
  for (var index = 0; index < 4096; index++) {
    terminal.write('\x1b]8;;https://example.com/$index\x1b\\x'
        '\x1b]8;;\x1b\\');
  }
  return terminal;
}
