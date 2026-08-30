import 'package:xterm2/core.dart';

void main() {
  final terminal = Terminal(maxLines: 10000)..resize(120, 24);
  try {
    for (var batch = 0; batch < 7; batch++) {
      final watch = Stopwatch()..start();
      for (var index = batch * 1000; index < (batch + 1) * 1000; index++) {
        terminal.write('\x1b]8;;https://example.com/$index\x1b\\'
            'line $index\x1b]8;;\x1b\\\r\n');
      }
      print('${(batch + 1) * 1000} links: ${watch.elapsedMicroseconds} us');
    }
  } finally {
    terminal.dispose();
  }
}
