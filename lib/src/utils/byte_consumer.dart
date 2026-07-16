import 'dart:collection';

class ByteConsumer {
  final _queue = ListQueue<_StringBlock>();

  final _consumed = ListQueue<_StringBlock>();

  var _currentOffset = 0;

  var _length = 0;

  var _totalConsumed = 0;

  var _rollbackAvailable = 0;

  void add(String data) {
    if (data.isEmpty) return;
    final block = _StringBlock(data, _countRunes(data));
    _queue.addLast(block);
    _length += block.runeLength;
  }

  int peek() {
    final result = consume();
    rollback();
    return result;
  }

  int consume() {
    _advancePastConsumedBlocks();
    final data = _queue.first.data;
    final first = data.codeUnitAt(_currentOffset);
    final codePoint = _decodeCodePoint(data, _currentOffset, first);
    _currentOffset += _codePointCodeUnitLength(data, _currentOffset, first);
    _length--;
    _totalConsumed++;
    _rollbackAvailable++;
    return codePoint;
  }

  /// Rolls back the last [n] calls to [consume].
  void rollback([int n = 1]) {
    if (n < 0 || n > _rollbackAvailable) {
      throw RangeError.range(n, 0, _rollbackAvailable, 'n');
    }

    var remaining = n;
    while (remaining > 0) {
      if (_currentOffset == 0) {
        final block = _consumed.removeLast();
        _queue.addFirst(block);
        _currentOffset = block.data.length;
      }

      _currentOffset = _previousRuneOffset(
        _queue.first.data,
        _currentOffset,
      );
      remaining--;
    }
    _totalConsumed -= n;
    _rollbackAvailable -= n;
    _length += n;
  }

  /// Rolls back to the state when this consumer had [length] runes.
  void rollbackTo(int length) {
    rollback(length - _length);
  }

  int get length => _length;

  int get totalConsumed => _totalConsumed;

  bool get isEmpty => _length == 0;

  bool get isNotEmpty => _length != 0;

  /// Unreferences blocks consumed before the current parsing transaction.
  void unrefConsumedBlocks() {
    _consumed.clear();
    while (_queue.isNotEmpty && _currentOffset >= _queue.first.data.length) {
      _currentOffset -= _queue.removeFirst().data.length;
    }
    _rollbackAvailable = 0;
  }

  /// Resets the consumer to its initial state.
  void reset() {
    _queue.clear();
    _consumed.clear();
    _currentOffset = 0;
    _totalConsumed = 0;
    _rollbackAvailable = 0;
    _length = 0;
  }

  void _advancePastConsumedBlocks() {
    while (_currentOffset >= _queue.first.data.length) {
      final block = _queue.removeFirst();
      _consumed.addLast(block);
      _currentOffset -= block.data.length;
    }
  }
}

class _StringBlock {
  const _StringBlock(this.data, this.runeLength);

  final String data;

  final int runeLength;
}

int _countRunes(String data) {
  var count = 0;
  var offset = 0;
  while (offset < data.length) {
    final first = data.codeUnitAt(offset);
    offset += _codePointCodeUnitLength(data, offset, first);
    count++;
  }
  return count;
}

int _decodeCodePoint(String data, int offset, int first) {
  if (!_isHighSurrogate(first) || offset + 1 >= data.length) {
    return first;
  }

  final second = data.codeUnitAt(offset + 1);
  if (!_isLowSurrogate(second)) return first;
  return 0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00);
}

int _codePointCodeUnitLength(String data, int offset, int first) {
  if (!_isHighSurrogate(first) || offset + 1 >= data.length) return 1;
  return switch (_isLowSurrogate(data.codeUnitAt(offset + 1))) {
    true => 2,
    false => 1,
  };
}

int _previousRuneOffset(String data, int offset) {
  final previous = offset - 1;
  if (previous <= 0 || !_isLowSurrogate(data.codeUnitAt(previous))) {
    return previous;
  }
  return switch (_isHighSurrogate(data.codeUnitAt(previous - 1))) {
    true => previous - 1,
    false => previous,
  };
}

bool _isHighSurrogate(int codeUnit) {
  return codeUnit >= 0xd800 && codeUnit <= 0xdbff;
}

bool _isLowSurrogate(int codeUnit) {
  return codeUnit >= 0xdc00 && codeUnit <= 0xdfff;
}
