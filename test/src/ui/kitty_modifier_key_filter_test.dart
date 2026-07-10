import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/kitty_modifier_key_filter.dart';

void main() {
  group('isKittyModifierKeyCharacter', () {
    test('detects exact Kitty modifier key sentinels', () {
      expect(isKittyModifierKeyCharacter(String.fromCharCode(57441)), isTrue);
      expect(isKittyModifierKeyCharacter(String.fromCharCode(57442)), isTrue);
      expect(isKittyModifierKeyCharacter(String.fromCharCode(57443)), isTrue);
      expect(isKittyModifierKeyCharacter(String.fromCharCode(57444)), isTrue);
      expect(isKittyModifierKeyCharacter(String.fromCharCode(57447)), isTrue);
      expect(isKittyModifierKeyCharacter(String.fromCharCode(57448)), isTrue);
      expect(isKittyModifierKeyCharacter(String.fromCharCode(57449)), isTrue);
      expect(isKittyModifierKeyCharacter(String.fromCharCode(57450)), isTrue);
    });

    test('does not treat range holes as modifier key sentinels', () {
      expect(isKittyModifierKeyCharacter(String.fromCharCode(57445)), isFalse);
      expect(isKittyModifierKeyCharacter(String.fromCharCode(57446)), isFalse);
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
