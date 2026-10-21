part of 'line.dart';

/// Releases all-zero history capacity while retaining styled cells and metadata.
extension BufferLineCompaction on BufferLine {
  void compact() {
    var keepCells = _length;
    while (keepCells > 0) {
      final offset = (keepCells - 1) * _cellSize;
      if ((_underlineColors?[keepCells - 1] ?? 0) != 0 ||
          _data[offset + _cellForeground] != 0 ||
          _data[offset + _cellBackground] != 0 ||
          _data[offset + _cellAttributes] != 0 ||
          _data[offset + _cellContent] != 0) {
        break;
      }
      keepCells--;
    }
    // Keep the all-zero placeholder cell of a trailing wide character, so the
    // pair stays addressable as two cells like everywhere else in the buffer.
    if (keepCells > 0 && keepCells < _length && getWidth(keepCells - 1) == 2) {
      keepCells++;
    }
    final keepWords = keepCells * _cellSize;
    if (_data.length - keepWords < 64) {
      return;
    }
    _data = _data.sublist(0, keepWords);
    _length = keepCells;
    _combiningCharacters?.removeWhere((index, _) => index >= keepCells);
    _underlineColors?.removeWhere((index, _) => index >= keepCells);
    for (var i = 0; i < _anchors.length; i++) {
      final anchor = _anchors[i];
      if (anchor.x > _length) {
        anchor.reposition(_length);
      }
    }
  }
}
