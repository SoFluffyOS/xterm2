class EscapeEmitter {
  const EscapeEmitter();

  String primaryDeviceAttributes() {
    return '\x1b[?1;2c';
  }

  String secondaryDeviceAttributes() {
    const model = 0;
    const version = 0;
    return '\x1b[>$model;$version;0c';
  }

  String tertiaryDeviceAttributes() {
    return '\x1bP!|00000000\x1b\\';
  }

  String operatingStatus() {
    return '\x1b[0n';
  }

  String cursorPosition(int x, int y) {
    return '\x1b[${y + 1};${x + 1}R';
  }

  String bracketedPaste(String text) {
    final filtered = text.replaceAll(RegExp('[\x1b\x03]'), '');
    return '\x1b[200~$filtered\x1b[201~';
  }

  String size(int rows, int cols) {
    return '\x1b[8;$rows;${cols}t';
  }

  String focusIn() => '\x1b[I';

  String focusOut() => '\x1b[O';
}
