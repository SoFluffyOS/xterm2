import 'package:test/test.dart';
import 'package:xterm2/src/utils/byte_consumer.dart';

void main() {
  test('consumes fragmented ASCII without changing offsets', () {
    final consumer = ByteConsumer()
      ..add('abc')
      ..add('def');

    expect(consumer.length, 6);
    expect(_consumeAll(consumer), 'abcdef'.runes);
    expect(consumer.totalConsumed, 6);
  });

  test('decodes supplementary code points lazily', () {
    final consumer = ByteConsumer()..add('a😀b');

    expect(consumer.length, 3);
    expect(consumer.consume(), 0x61);
    expect(consumer.peek(), 0x1f600);
    expect(consumer.consume(), 0x1f600);
    expect(consumer.consume(), 0x62);
  });

  test('matches Runes behavior for malformed surrogates', () {
    final malformed = String.fromCharCodes([0xd800, 0x61, 0xdc00]);
    final consumer = ByteConsumer()..add(malformed);

    expect(_consumeAll(consumer), malformed.runes);
  });

  test('rolls back across string block boundaries', () {
    final consumer = ByteConsumer()
      ..add('a😀')
      ..add('bc');

    expect(consumer.consume(), 0x61);
    expect(consumer.consume(), 0x1f600);
    expect(consumer.consume(), 0x62);
    consumer.rollback(2);

    expect(consumer.length, 3);
    expect(consumer.totalConsumed, 1);
    expect(_consumeAll(consumer), '😀bc'.runes);
  });

  test('rolls back to a recorded rune length', () {
    final consumer = ByteConsumer()..add('a😀bc');
    final initialLength = consumer.length;

    consumer.consume();
    consumer.consume();
    consumer.rollbackTo(initialLength);

    expect(_consumeAll(consumer), 'a😀bc'.runes);
  });

  test('drops consumed blocks before accepting more output', () {
    final consumer = ByteConsumer()..add('first');
    _consumeAll(consumer);

    consumer.unrefConsumedBlocks();
    consumer.add('second');

    expect(_consumeAll(consumer), 'second'.runes);
  });

  test('handles large ASCII output without changing parser semantics', () {
    final text = 'x' * 1024 * 1024;
    final consumer = ByteConsumer()..add(text);

    expect(consumer.length, text.length);
    var consumed = 0;
    while (consumer.isNotEmpty) {
      if (consumer.consume() != 0x78) {
        fail('ASCII output changed at rune $consumed');
      }
      consumed++;
    }
    expect(consumed, text.length);
    expect(consumer, isEmpty);
  });

  test('reports remaining rune length without eager block metadata', () {
    final consumer = ByteConsumer()
      ..add('a😀')
      ..add('b😁c');

    expect(consumer.length, 5);
    expect(consumer.consume(), 0x61);
    expect(consumer.length, 4);
    expect(consumer.consume(), 0x1f600);
    expect(consumer.length, 3);

    consumer.rollback(2);

    expect(consumer.length, 5);
    expect(_consumeAll(consumer), 'a😀b😁c'.runes);
  });

  test('consumes printable ASCII runs without crossing controls or blocks', () {
    final consumer = ByteConsumer()
      ..add('abc\x1b')
      ..add('def');

    expect(consumer.printableAsciiRunLength, 3);
    expect(consumer.currentBlock, 'abc\x1b');
    expect(consumer.currentCodeUnitOffset, 0);

    consumer.consumeAsciiCodeUnits(3);
    expect(consumer.totalConsumed, 3);
    expect(consumer.consume(), 0x1b);
    expect(consumer.printableAsciiRunLength, 3);

    consumer.consumeAsciiCodeUnits(3);
    expect(consumer.totalConsumed, 7);
    expect(consumer, isEmpty);

    consumer.rollback(3);
    expect(_consumeAll(consumer), 'def'.runes);
  });
}

List<int> _consumeAll(ByteConsumer consumer) {
  final output = <int>[];
  while (consumer.isNotEmpty) {
    output.add(consumer.consume());
  }
  return output;
}
