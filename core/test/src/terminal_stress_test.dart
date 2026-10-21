import 'dart:math';

import 'package:test/test.dart';
import 'package:xterm2_core/xterm2_core.dart';

void main() {
  test('Terminal survives deterministic output and resize stress', () {
    final random = Random(0x5eeda11);
    final terminal = Terminal(maxLines: 500)..resize(80, 24);

    for (var iteration = 0; iteration < 20000; iteration++) {
      final length = random.nextInt(128);
      final codeUnits = List<int>.generate(
        length,
        (_) => random.nextInt(0x100),
        growable: false,
      );
      terminal.write(String.fromCharCodes(codeUnits));

      if (iteration % 13 == 0) {
        terminal.resize(random.nextInt(159) + 1, random.nextInt(79) + 1);
      }

      final lineCount = terminal.buffer.lines.length;
      if (lineCount != 0) {
        final row = random.nextInt(lineCount);
        final column = random.nextInt(terminal.viewWidth);
        terminal.hyperlinkIdAt(CellOffset(column, row));
      }
    }
  });
}
