import 'dart:collection';

class ByteConsumer {
  final _queue = ListQueue<_StringBlock>();

  final _consumed = ListQueue<_StringBlock>();

  var _currentOffset = 0;

  var _remainingCodeUnits = 0;

  var _totalConsumed = 0;

  var _rollbackAvailable = 0;

  void add(String data) {
    if (data.isEmpty) return;
    _queue.addLast(_StringBlock(data));
    _remainingCodeUnits += data.length;
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
    final codeUnitLength = _codePointCodeUnitLength(
      data,
      _currentOffset,
      first,
    );
    _currentOffset += codeUnitLength;
    _remainingCodeUnits -= codeUnitLength;
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

      final previousOffset = _previousRuneOffset(
        _queue.first.data,
        _currentOffset,
      );
      _remainingCodeUnits += _currentOffset - previousOffset;
      _currentOffset = previousOffset;
      remaining--;
    }
    _totalConsumed -= n;
    _rollbackAvailable -= n;
  }

  /// Rolls back to the state when this consumer had [length] runes.
  void rollbackTo(int length) {
    rollback(length - this.length);
  }

  int get length {
    var count = 0;
    var isFirst = true;
    for (final block in _queue) {
      final start = switch (isFirst) {
        true => _currentOffset,
        false => 0,
      };
      count += _countRunes(block.data, start);
      isFirst = false;
    }
    return count;
  }

  int get totalConsumed => _totalConsumed;

  bool get isEmpty => _remainingCodeUnits == 0;

  bool get isNotEmpty => _remainingCodeUnits != 0;

  String get currentBlock {
    _advancePastConsumedBlocks();
    return _queue.first.data;
  }

  int get currentCodeUnitOffset {
    _advancePastConsumedBlocks();
    return _currentOffset;
  }

  int get printableAsciiRunLength {
    _advancePastConsumedBlocks();
    final data = _queue.first.data;
    var offset = _currentOffset;
    while (offset < data.length) {
      final codeUnit = data.codeUnitAt(offset);
      if (codeUnit < 0x20 || codeUnit > 0x7e) break;
      offset++;
    }
    return offset - _currentOffset;
  }

  void consumeAsciiCodeUnits(int count) {
    _advancePastConsumedBlocks();
    final available = _queue.first.data.length - _currentOffset;
    if (count < 0 || count > available) {
      throw RangeError.range(count, 0, available, 'count');
    }
    _currentOffset += count;
    _remainingCodeUnits -= count;
    _totalConsumed += count;
    _rollbackAvailable += count;
  }

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
    _remainingCodeUnits = 0;
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
  const _StringBlock(this.data);

  final String data;
}

int _countRunes(String data, int start) {
  var count = 0;
  var offset = start;
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
