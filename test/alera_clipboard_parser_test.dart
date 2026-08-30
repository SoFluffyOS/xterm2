import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  test('clipboard policy rejects other protocols and extra OSC 52 fields', () {
    final decoded = <String>[];
    final queries = <String>[];
    final terminal = Terminal(
      allowKittyClipboard: false,
      clipboardDecoder: (_, data) {
        decoded.add(data);
        return null;
      },
      onClipboardQuery: (selector) {
        queries.add(selector);
        return null;
      },
    );
    addTearDown(terminal.dispose);
    terminal.write('\x1b]5522;type=write;YQ==\x07');
    terminal.write('\x1b]52;c;YQ==;trailing\x07');
    terminal.write('\x1b]52;c;?;trailing\x07');
    expect(decoded, isEmpty);
    expect(queries, isEmpty);
    terminal.write('\x1b]52;c;YQ==\x07');
    expect(decoded, ['YQ==']);
  });

  for (final size in [7000, 98304]) {
    test('OSC 52 accepts $size decoded bytes across chunks', () {
      final copies = <String>[];
      final terminal =
          Terminal(onClipboardStore: (_, text) => copies.add(text));
      addTearDown(terminal.dispose);
      final text = 'a' * size;
      final encoded = base64.encode(utf8.encode(text));
      terminal.write('\x1b]52;c;${encoded.substring(0, 4000)}');
      terminal.write(encoded.substring(4000));
      terminal.write('\x1b');
      expect(copies, isEmpty);
      terminal.write('\\safe');
      expect(copies, [text]);
      expect(terminal.buffer.getText(), startsWith('safe'));
    });
  }

  for (final (label, terminator) in [
    ('BEL', '\x07'),
    ('ST', '\x1b\\'),
    ('C1 ST', '\x9c'),
  ]) {
    for (final extra in [1, 4]) {
      test('OSC 52 discards oversized payload by $extra with $label', () {
        final decoded = <String>[];
        final terminal = Terminal(clipboardDecoder: (_, data) {
          decoded.add(data);
          return null;
        });
        addTearDown(terminal.dispose);
        terminal.write('\x1b]52;c;${'A' * (128 * 1024 + extra)}');
        terminal.write(terminator.substring(0, 1));
        terminal.write('${terminator.substring(1)}safe');
        expect(decoded, isEmpty);
        expect(terminal.buffer.getText(), startsWith('safe'));
      });
    }
  }

  test('large generic OSC and oversized clipboard headers remain bounded', () {
    final titles = <String>[];
    final copies = <String>[];
    final terminal = Terminal(
      onTitleChange: titles.add,
      clipboardDecoder: (_, data) {
        copies.add(data);
        return null;
      },
    );
    addTearDown(terminal.dispose);
    terminal.write('\x1b]2;${'a' * 8192}\x07');
    terminal.write('\x1b]52;${'c' * 8192};YQ==\x07safe');
    expect(titles, isEmpty);
    expect(copies, isEmpty);
    expect(terminal.buffer.getText(), startsWith('safe'));
  });
}
