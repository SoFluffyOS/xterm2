import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/src/ui/char_metrics.dart';
import 'package:xterm2/xterm.dart';

void main() {
  test('calcCharSize returns stable positive metrics', () {
    const style = TerminalStyle(fontSize: 14);

    final first = calcCharSize(style, TextScaler.noScaling);
    final second = calcCharSize(style, TextScaler.noScaling);

    expect(first.width, greaterThan(0));
    expect(first.height, greaterThan(0));
    expect(second, first);
  });
}
