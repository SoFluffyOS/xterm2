const _initialColumns = 80;
const _defaultInterval = 8;

/// Manages the tab stop state for a terminal.
class TabStops {
  final _stops = List<bool>.filled(_initialColumns, false, growable: true);

  var _useDefaultForNewColumns = true;

  TabStops() {
    _initialize();
  }

  /// Initializes the tab stops to the default 8 column intervals.
  void _initialize() {
    for (var i = 0; i < _stops.length; i += _defaultInterval) {
      _stops[i] = true;
    }
  }

  void _ensureLength(int length) {
    if (length <= _stops.length) return;
    final previousLength = _stops.length;
    _stops.addAll(List<bool>.filled(length - previousLength, false));
    if (!_useDefaultForNewColumns) return;

    var index = previousLength;
    final remainder = index % _defaultInterval;
    if (remainder != 0) {
      index += _defaultInterval - remainder;
    }
    for (; index < length; index += _defaultInterval) {
      _stops[index] = true;
    }
  }

  /// Finds the next tab stop index, which satisfies [start] <= index < [end].
  int? find(int start, int end) {
    if (start >= end) {
      return null;
    }
    _ensureLength(end);
    for (var i = start; i < end; i++) {
      if (_stops[i]) {
        return i;
      }
    }
    return null;
  }

  /// Sets the tab stop at [index]. If there is already a tab stop at [index],
  /// this method does nothing.
  ///
  /// See also:
  /// * [clearAt] which does the opposite.
  void setAt(int index) {
    RangeError.checkNotNegative(index, 'index');
    _ensureLength(index + 1);
    _stops[index] = true;
  }

  /// Clears the tab stop at [index]. If there is no tab stop at [index], this
  /// method does nothing.
  void clearAt(int index) {
    RangeError.checkNotNegative(index, 'index');
    _ensureLength(index + 1);
    _stops[index] = false;
  }

  /// Clears all tab stops without resetting them to the default 8 column
  /// intervals.
  void clearAll() {
    _stops.fillRange(0, _stops.length, false);
    _useDefaultForNewColumns = false;
  }

  /// Returns true if there is a tab stop at [index].
  bool isSetAt(int index) {
    RangeError.checkNotNegative(index, 'index');
    _ensureLength(index + 1);
    return _stops[index];
  }

  /// Resets the tab stops to the default 8 column intervals.
  void reset() {
    _stops.fillRange(0, _stops.length, false);
    _useDefaultForNewColumns = true;
    _initialize();
  }
}
