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
  });
}
