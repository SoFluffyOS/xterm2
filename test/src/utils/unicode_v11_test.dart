import 'package:test/test.dart';
import 'package:xterm/src/utils/unicode_v11.dart';

void main() {
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
}
