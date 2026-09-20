const _bmpPrivateUseAreaStart = 0xE000;
const _bmpPrivateUseAreaEnd = 0xF8FF;

/// Returns true when [text] is a single BMP private-use character.
///
/// Kitty functional key codes live in this range and can surface as
/// `KeyEvent.character` for modifier, lock, media, and similar keys. They
/// must not be inserted as terminal text.
bool isKittyModifierKeyCharacter(String text) {
  final runes = text.runes;
  if (runes.length != 1) {
    return false;
  }

  final code = runes.first;
  return code >= _bmpPrivateUseAreaStart && code <= _bmpPrivateUseAreaEnd;
}
