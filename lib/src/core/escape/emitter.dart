import 'package:xterm/src/core/color_scheme.dart';

class EscapeEmitter {
  const EscapeEmitter();

  static const _packageVersion = '4.0.1';
  static const _defaultXtVersion = 'xterm.dart $_packageVersion';
  static const _maxXtVersionLength = 256;

  String primaryDeviceAttributes() {
    return '\x1b[?6c';
  }

  String secondaryDeviceAttributes() {
    const model = 0;
    final version = _versionNumber(_packageVersion);
    return '\x1b[>$model;$version;1c';
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

  String colorScheme(TerminalColorScheme colorScheme) {
    final scheme = switch (colorScheme) {
      TerminalColorScheme.dark => 1,
      TerminalColorScheme.light => 2,
    };
    return '\x1b[?997;${scheme}n';
  }

  String xtVersion(String? version) {
    final payload = _sanitizeXtVersion(version);
    return '\x1bP>|$payload\x1b\\';
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

  int _versionNumber(String version) {
    final separator = version.lastIndexOf('-');
    final semver = switch (separator) {
      -1 => version,
      _ => version.substring(0, separator),
    };

    final parts = semver.split('.').reversed;
    var number = 0;
    var multiplier = 1;

    for (final part in parts) {
      number += (int.tryParse(part) ?? 0) * multiplier;
      multiplier *= 100;
    }

    return number;
  }

  String _sanitizeXtVersion(String? version) {
    final effectiveVersion = switch (version) {
      final value? when value.isNotEmpty => value,
      _ => _defaultXtVersion,
    };
    final withoutControls = effectiveVersion.replaceAll(
      RegExp('[\x00-\x1f\x7f]'),
      '',
    );
    if (withoutControls.length <= _maxXtVersionLength) return withoutControls;
    return withoutControls.substring(0, _maxXtVersionLength);
  }
}
