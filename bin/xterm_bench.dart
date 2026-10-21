import 'package:xterm2_core/xterm2_core.dart';

void main(List<String> args) async {
  final lines = 1000;

  final terminal = Terminal(maxLines: lines);

  bench('write $lines lines', () {
    for (var i = 0; i < lines; i++) {
      terminal.write('https://github.com/TerminalStudio/dartssh2\r\n');
    }
  });

  bench('search $lines line', () {
    final matches = terminal.search('github.com');
    print('count: ${matches.length}');
  });
}

void bench(String description, void Function() f) {
  final sw = Stopwatch()..start();
  f();
  print('$description took ${sw.elapsedMilliseconds}ms');
}
