class TerminalMouseModifiers {
  static const none = TerminalMouseModifiers();

  static const _shiftMask = 4;
  static const _altMask = 8;
  static const _controlMask = 16;

  final bool shift;

  final bool alt;

  final bool control;

  const TerminalMouseModifiers({
    this.shift = false,
    this.alt = false,
    this.control = false,
  });

  int get reportOffset {
    var offset = 0;
    if (shift) {
      offset += _shiftMask;
    }
    if (alt) {
      offset += _altMask;
    }
    if (control) {
      offset += _controlMask;
    }
    return offset;
  }
}
