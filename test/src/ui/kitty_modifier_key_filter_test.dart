import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/src/ui/kitty_modifier_key_filter.dart';

void main() {
  group('isKittyModifierKeyCharacter', () {
    test('detects Kitty private-use key sentinels', () {
      expect(isKittyModifierKeyCharacter(String.fromCharCode(0xE000)), isTrue);
      expect(isKittyModifierKeyCharacter(String.fromCharCode(57358)), isTrue);
      expect(isKittyModifierKeyCharacter(String.fromCharCode(57441)), isTrue);
      expect(isKittyModifierKeyCharacter(String.fromCharCode(57450)), isTrue);
      expect(isKittyModifierKeyCharacter(String.fromCharCode(0xF8FF)), isTrue);
    });

    test('does not treat neighboring planes as modifier sentinels', () {
      expect(isKittyModifierKeyCharacter(String.fromCharCode(0xDFFF)), isFalse);
      expect(isKittyModifierKeyCharacter(String.fromCharCode(0xF900)), isFalse);
    });

    test('preserves text that includes private-use characters', () {
      expect(isKittyModifierKeyCharacter('a'), isFalse);
      expect(
        isKittyModifierKeyCharacter('a${String.fromCharCode(57441)}'),
        isFalse,
      );
      expect(
        isKittyModifierKeyCharacter('${String.fromCharCode(57441)}a'),
        isFalse,
      );
    });
  });
}
