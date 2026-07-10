import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

@GenerateNiceMocks([MockSpec<EscapeHandler>()])
import 'parser_test.mocks.dart';

void main() {
  group('EscapeParser', () {
    test('can parse window manipulation', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[8;24;80t');
      verify(parser.handler.resize(80, 24));
    });

    test('parses DECSCUSR with its space intermediate', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[5 q');

      verify(handler.setCursorShape(5)).called(1);
    });

    test('parses cursor tabulation control', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[W\x1b[2W\x1b[5W\x1b[?5W');

      verify(handler.setTapStop()).called(1);
      verify(handler.clearTabStopUnderCursor()).called(1);
      verify(handler.clearAllTabStops()).called(1);
      verify(handler.resetTabStops()).called(1);
    });

    test('parses cursor position aliases', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[4`\x1b[2a\x1b[3e');

      verify(handler.setCursorX(3)).called(1);
      verify(handler.moveCursorX(2)).called(1);
      verify(handler.moveCursorY(3)).called(1);
    });

    test('parses DEC private mode save and restore', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[?7;25s\x1b[?7;25r');

      verify(handler.saveDecMode(7)).called(1);
      verify(handler.saveDecMode(25)).called(1);
      verify(handler.restoreDecMode(7)).called(1);
      verify(handler.restoreDecMode(25)).called(1);
    });

    test('parses XTSHIFTESCAPE mouse shift capture', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[>1s\x1b[>0s\x1b[>s\x1b[>2s');

      verify(handler.setMouseShiftCaptureMode(true)).called(1);
      verify(handler.setMouseShiftCaptureMode(false)).called(2);
      verifyNever(handler.setMouseShiftCaptureMode(null));
    });

    test('parses DEC left and right margin mode', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[?69h\x1b[?69l');

      verify(handler.setLeftRightMarginMode(true)).called(1);
      verify(handler.setLeftRightMarginMode(false)).called(1);
    });

    test('parses DEC left and right margins', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[2;5s\x1b[3s');

      verify(handler.setLeftRightMargins(1, 4)).called(1);
      verify(handler.setLeftRightMargins(2, null)).called(1);
    });

    test('parses protected mode and selective erase', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[1"q\x1b[2"q\x1b[?J\x1b[?1J\x1b[?2J');
      parser.write('\x1b[?K\x1b[?1K\x1b[?2K');

      verify(handler.setProtectedMode(true)).called(1);
      verify(handler.setProtectedMode(false)).called(1);
      verify(handler.eraseDisplayBelowSelective()).called(1);
      verify(handler.eraseDisplayAboveSelective()).called(1);
      verify(handler.eraseDisplaySelective()).called(1);
      verify(handler.eraseLineRightSelective()).called(1);
      verify(handler.eraseLineLeftSelective()).called(1);
      verify(handler.eraseLineSelective()).called(1);
    });

    test('parses ISO protected areas', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1bV\x1bW');

      verify(handler.setIsoProtectedMode(true)).called(1);
      verify(handler.setIsoProtectedMode(false)).called(1);
    });

    test('parses grapheme cluster mode', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[?2027h\x1b[?2027l');

      verify(handler.setGraphemeClusterMode(true)).called(1);
      verify(handler.setGraphemeClusterMode(false)).called(1);
    });

    test('parses G2 and G3 character set controls', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b*0\x1b+0\x1bN\x1bO\x1bn\x1bo');

      verify(handler.designateCharset(2, 0x30)).called(1);
      verify(handler.designateCharset(3, 0x30)).called(1);
      verify(handler.singleShiftCharset(2)).called(1);
      verify(handler.singleShiftCharset(3)).called(1);
      verify(handler.useCharset(2)).called(1);
      verify(handler.useCharset(3)).called(1);
    });

    test('executes controls while waiting for charset final byte', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b(\x07\x7f0');

      verify(handler.bell()).called(1);
      verify(handler.designateCharset(0, 0x30)).called(1);
    });

    test('preserves split charset sequence across controls', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b(');
      parser.write('\x0e0');

      verify(handler.shiftOut()).called(1);
      verify(handler.designateCharset(0, 0x30)).called(1);
    });

    test('restarts escape while waiting for charset final byte', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b(\x1b[5 q');

      verifyNever(handler.designateCharset(any, any));
      verify(handler.setCursorShape(5)).called(1);
    });

    test('executes controls while waiting for hash final byte', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b#\x078');

      verify(handler.bell()).called(1);
      verify(handler.screenAlignmentTest()).called(1);
    });

    test('rejects malformed plain CSI commands', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write(
        '\x1b[?2A'
        '\x1b[1;2A'
        '\x1b[2 A'
        '\x1b[>31m'
        '\x1b[?4m'
        '\x1b[?1L',
      );

      verifyNever(handler.moveCursorY(any));
      verifyNever(handler.setCursorBold());
      verifyNever(handler.insertLines(any));
    });

    test('parses horizontal position backward alias', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\x1b[3j');

      verify(handler.moveCursorX(-3)).called(1);
    });

    test('parses 8-bit C1 controls', () {
      final handler = MockEscapeHandler();
      final parser = EscapeParser(handler);

      parser.write('\u0084\u0085\u0088\u008d\u008e\u008f\u009b2A');

      verify(handler.index()).called(1);
      verify(handler.nextLine()).called(1);
      verify(handler.setTapStop()).called(1);
      verify(handler.reverseIndex()).called(1);
      verify(handler.singleShiftCharset(2)).called(1);
      verify(handler.singleShiftCharset(3)).called(1);
      verify(handler.moveCursorY(-2)).called(1);
    });
  });
}
