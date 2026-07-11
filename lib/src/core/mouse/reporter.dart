import 'package:xterm2/src/core/buffer/cell_offset.dart';
import 'package:xterm2/src/core/mouse/mode.dart';
import 'package:xterm2/src/core/mouse/button.dart';
import 'package:xterm2/src/core/mouse/button_state.dart';
import 'package:xterm2/src/core/mouse/modifiers.dart';

abstract class MouseReporter {
  static String? report(
    TerminalMouseButton button,
    TerminalMouseButtonState state,
    CellOffset position,
    MouseReportMode reportMode, {
    bool motion = false,
    TerminalMouseModifiers modifiers = TerminalMouseModifiers.none,
    CellOffset? pixelPosition,
  }) {
    // x and y offsets have to be incremented by 1 as the offset if 0-based,
    // The position has to be reported using 1-based coordinates.
    final x = position.x + 1;
    final y = position.y + 1;
    switch (reportMode) {
      case MouseReportMode.normal:
      case MouseReportMode.utf:
        final maxPosition = switch (reportMode) {
          MouseReportMode.normal => 223,
          MouseReportMode.utf => 2015,
          _ => throw StateError('Unexpected mouse report mode'),
        };
        if (x > maxPosition || y > maxPosition) {
          return null;
        }

        // Button ID 3 is used to signal a button release.
        final baseButtonID =
            state == TerminalMouseButtonState.up ? 3 : button.id;
        var buttonID = baseButtonID + modifiers.reportOffset;
        if (motion) {
          buttonID += 32;
        }
        // The button ID is reported as shifted by 32 to produce a printable
        // character.
        final btn = String.fromCharCode(32 + buttonID);
        final col = String.fromCharCode(32 + x);
        final row = String.fromCharCode(32 + y);
        return "\x1b[M$btn$col$row";
      case MouseReportMode.sgr:
      case MouseReportMode.sgrPixels:
        final reportX = switch (reportMode) {
          MouseReportMode.sgrPixels => (pixelPosition ?? position).x + 1,
          _ => x,
        };
        final reportY = switch (reportMode) {
          MouseReportMode.sgrPixels => (pixelPosition ?? position).y + 1,
          _ => y,
        };
        var buttonID = button.id + modifiers.reportOffset;
        if (motion) {
          buttonID += 32;
        }
        final upDown = state == TerminalMouseButtonState.down ? 'M' : 'm';
        return "\x1b[<$buttonID;$reportX;$reportY$upDown";
      case MouseReportMode.urxvt:
        // The button ID uses the same id as to report it as in normal mode.
        final baseButtonID =
            state == TerminalMouseButtonState.up ? 3 : button.id;
        var buttonID = 32 + baseButtonID + modifiers.reportOffset;
        if (motion) {
          buttonID += 32;
        }
        return "\x1b[$buttonID;$x;${y}M";
    }
  }
}
