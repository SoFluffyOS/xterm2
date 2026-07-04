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
  });
}
