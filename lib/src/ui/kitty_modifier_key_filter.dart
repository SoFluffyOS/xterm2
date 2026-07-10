const _kittyModifierKeyCodes = {
  57441, // Shift Left
  57442, // Control Left
  57443, // Alt Left
  57444, // Meta Left
  57447, // Shift Right
  57448, // Control Right
  57449, // Alt Right
  57450, // Meta Right
};

/// Returns true when [text] is Flutter's Windows modifier-key sentinel.
///
/// The values are Kitty keyboard protocol private-use key codes. They can
/// surface as `KeyEvent.character` for raw modifier keys on Windows and should
/// not be inserted as terminal text.
bool isKittyModifierKeyCharacter(String text) {
  final runes = text.runes;
  if (runes.length != 1) {
    return false;
  }

  return _kittyModifierKeyCodes.contains(runes.first);
}
