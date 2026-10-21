import 'package:test/test.dart';
import 'package:xterm2_core/src/core/mouse/reporter.dart';
import 'package:xterm2_core/xterm2_core.dart';

void main() {
  group('MouseReporter', () {
    test('report() supports normal mode', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.normal,
      );

      expect(output, equals('\x1B[M !!'));
    });

    test('report() supports utf mode', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.utf,
      );

      expect(output, equals('\x1B[M !!'));
    });

    test('report() drops legacy mouse coordinates outside encodable range', () {
      expect(
        MouseReporter.report(
          TerminalMouseButton.left,
          TerminalMouseButtonState.down,
          CellOffset(223, 0),
          MouseReportMode.normal,
        ),
        isNull,
      );
      expect(
        MouseReporter.report(
          TerminalMouseButton.left,
          TerminalMouseButtonState.down,
          CellOffset(2015, 0),
          MouseReportMode.utf,
        ),
        isNull,
      );
    });

    test('report() supports sgr mode', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.sgr,
      );

      expect(output, equals('\x1B[<0;1;1M'));
    });

    test('report() marks sgr mouse motion', () {
      final output = MouseReporter.report(
        TerminalMouseButton.none,
        TerminalMouseButtonState.down,
        CellOffset(4, 6),
        MouseReportMode.sgr,
        motion: true,
      );

      expect(output, equals('\x1B[<35;5;7M'));
    });

    test('report() encodes sgr wheel buttons', () {
      expect(
        MouseReporter.report(
          TerminalMouseButton.wheelUp,
          TerminalMouseButtonState.down,
          CellOffset(0, 0),
          MouseReportMode.sgr,
        ),
        '\x1B[<64;1;1M',
      );
      expect(
        MouseReporter.report(
          TerminalMouseButton.wheelDown,
          TerminalMouseButtonState.down,
          CellOffset(0, 0),
          MouseReportMode.sgr,
        ),
        '\x1B[<65;1;1M',
      );
    });

    test('report() encodes extended buttons in textual protocols', () {
      expect(
        MouseReporter.report(
          TerminalMouseButton.back,
          TerminalMouseButtonState.down,
          const CellOffset(0, 0),
          MouseReportMode.sgr,
        ),
        '\x1b[<128;1;1M',
      );
      expect(
        MouseReporter.report(
          TerminalMouseButton.forward,
          TerminalMouseButtonState.down,
          const CellOffset(0, 0),
          MouseReportMode.urxvt,
        ),
        '\x1b[161;1;1M',
      );
    });

    test('report() rejects extended buttons in byte protocols', () {
      expect(
        MouseReporter.report(
          TerminalMouseButton.back,
          TerminalMouseButtonState.down,
          const CellOffset(0, 0),
          MouseReportMode.normal,
        ),
        isNull,
      );
      expect(
        MouseReporter.report(
          TerminalMouseButton.forward,
          TerminalMouseButtonState.down,
          const CellOffset(0, 0),
          MouseReportMode.utf,
        ),
        isNull,
      );
    });

    test('report() supports sgr pixels mode', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(4, 6),
        MouseReportMode.sgrPixels,
        pixelPosition: CellOffset(30, 40),
      );

      expect(output, equals('\x1B[<0;31;41M'));
    });

    test('report() encodes mouse modifiers', () {
      final modifiers = TerminalMouseModifiers(
        shift: true,
        alt: true,
        control: true,
      );

      expect(
        MouseReporter.report(
          TerminalMouseButton.left,
          TerminalMouseButtonState.down,
          CellOffset(0, 0),
          MouseReportMode.sgr,
          modifiers: modifiers,
        ),
        '\x1B[<28;1;1M',
      );
      expect(
        MouseReporter.report(
          TerminalMouseButton.left,
          TerminalMouseButtonState.down,
          CellOffset(0, 0),
          MouseReportMode.normal,
          modifiers: modifiers,
        ),
        '\x1B[M<!!',
      );
      expect(
        MouseReporter.report(
          TerminalMouseButton.left,
          TerminalMouseButtonState.down,
          CellOffset(0, 0),
          MouseReportMode.urxvt,
          modifiers: modifiers,
        ),
        '\x1B[60;1;1M',
      );
    });

    test('report() combines mouse motion and modifiers', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(2, 3),
        MouseReportMode.sgr,
        motion: true,
        modifiers: const TerminalMouseModifiers(shift: true),
      );

      expect(output, equals('\x1B[<36;3;4M'));
    });

    test('report() supports urxvt mode', () {
      final output = MouseReporter.report(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(0, 0),
        MouseReportMode.urxvt,
      );

      expect(output, equals('\x1B[32;1;1M'));
    });
  });
}
