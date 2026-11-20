import 'package:test/test.dart';
import 'package:xterm2_core/xterm2_core.dart';

void main() {
  test('the package exports the width table the terminal measures with', () {
    // A host that lays out text beside the terminal, a table or a prompt,
    // counts cells as the terminal does.
    final terminal = Terminal()..resize(20, 1);

    terminal.write('漢ж\u{1FA89}');

    final cells = '漢ж\u{1FA89}'.runes.map(unicodeV11.wcwidth);
    expect(cells, [2, 1, 2]);
    expect(terminal.buffer.cursorX, cells.reduce((a, b) => a + b));
  });
}
