// How fast the parser takes ASCII and Cyrillic, without a view:
// `dart run benchmark/parse_benchmark.dart` from core/.
import 'dart:convert';
import 'dart:math';

import 'package:xterm2_core/xterm2_core.dart';

const _units = 4 << 20;

const _piece = 8192;

const _passes = 5;

void main() {
  final ascii = _measure(_asciiLines(_units));
  final cyrillic = _measure(_cyrillicLines(_units));
  print('ascii ${ascii.mibPerSecond.toStringAsFixed(1)}');
  print('cyrillic ${cyrillic.mibPerSecond.toStringAsFixed(1)}');
  final ratio = cyrillic.secondsPerCharacter / ascii.secondsPerCharacter;
  print('cyrillic per character ${ratio.toStringAsFixed(1)}x ascii');
}

/// The fastest of [_passes] runs of [data] through a 120×48 terminal, fed
/// 8 KiB at a time as a pty reads it, after one run to warm up.
({double mibPerSecond, double secondsPerCharacter}) _measure(String data) {
  final bytes = utf8.encode(data).length;
  final terminal = Terminal(maxLines: 1000)..resize(120, 48);
  _feed(terminal, data);
  var best = double.infinity;
  for (var pass = 0; pass < _passes; pass++) {
    final clock = Stopwatch()..start();
    _feed(terminal, data);
    best = min(best, clock.elapsedMicroseconds / 1e6);
  }
  return (
    mibPerSecond: bytes / (1 << 20) / best,
    secondsPerCharacter: best / data.length,
  );
}

void _feed(Terminal terminal, String data) {
  for (var at = 0; at < data.length; at += _piece) {
    terminal.write(data.substring(at, min(at + _piece, data.length)));
  }
}

String _asciiLines(int units) {
  final page = StringBuffer();
  var line = 0;
  while (page.length < units) {
    page.write(
      'line ${line++} the quick brown fox jumps over the lazy dog 0123456789\r\n',
    );
  }
  return page.toString();
}

String _cyrillicLines(int units) {
  final page = StringBuffer();
  var line = 0;
  while (page.length < units) {
    page.write(
      'строка ${line++} съешь же ещё этих мягких французских булок да выпей чаю\r\n',
    );
  }
  return page.toString();
}
