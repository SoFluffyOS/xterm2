import 'package:test/test.dart';
import 'package:xterm2/src/utils/unicode_v11.dart';

void main() {
  test('Unicode width table reports its synchronized version', () {
    expect(unicodeV11.version, '17.0');
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

  test('Unicode width table includes Emoji 17 presentation additions', () {
    for (final codePoint in <int>[
      0x1F6D8,
      0x1FA8A,
      0x1FA8E,
      0x1FAC8,
      0x1FAEA,
      0x1FAEF,
    ]) {
      expect(unicodeV11.wcwidth(codePoint), 2);
    }
  });

  test('Unicode width table includes Unicode 17 combining additions', () {
    for (final codePoint in <int>[
      0x1AE0,
      0x10D69,
      0x11B62,
      0x1611E,
      0x1E5EE,
    ]) {
      expect(unicodeV11.wcwidth(codePoint), 0);
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

  test('Unicode width ranges stay sorted and non-overlapping', () {
    for (final ranges in <List<List<int>>>[
      BMP_COMBINING,
      HIGH_COMBINING,
      BMP_WIDE,
      HIGH_WIDE,
    ]) {
      for (var index = 1; index < ranges.length; index++) {
        expect(ranges[index][0], greaterThan(ranges[index - 1][1]));
      }
    }

    for (final (combining, wide) in <(List<List<int>>, List<List<int>>)>[
      (BMP_COMBINING, BMP_WIDE),
      (HIGH_COMBINING, HIGH_WIDE),
    ]) {
      for (final combiningRange in combining) {
        for (final wideRange in wide) {
          final rangesOverlap = combiningRange[0] <= wideRange[1] &&
              wideRange[0] <= combiningRange[1];
          expect(rangesOverlap, isFalse);
        }
      }
    }
  });
}
