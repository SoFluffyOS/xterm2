import 'package:test/test.dart';
import 'package:xterm2/src/utils/unicode_v11.dart';

void main() {
  test('Unicode width table reports its synchronized version', () {
    expect(unicodeV11.version, '16.0');
  });

  test('Unicode width table includes Emoji 16 presentation additions', () {
    for (final codePoint in <int>[
      0x1FA89,
      0x1FA8F,
      0x1FABE,
      0x1FAC6,
      0x1FADC,
      0x1FADF,
      0x1FAE9,
    ]) {
      expect(unicodeV11.wcwidth(codePoint), 2);
    }
  });

  test('Unicode width table matches Ghostty default ignorable controls', () {
    for (final codePoint in <int>[
      0x00AD,
      0x13439,
      0x1343F,
      0x13440,
      0x13455,
    ]) {
      expect(unicodeV11.wcwidth(codePoint), 0);
    }
  });
}
