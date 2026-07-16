import 'package:xterm2/src/core/buffer/line.dart';
import 'package:xterm2/src/utils/circular_buffer.dart';

class _LineBuilder {
  _LineBuilder([this._capacity = 80]) {
    _result = BufferLine(_capacity);
  }

  final int _capacity;

  late BufferLine _result;

  int _length = 0;

  int get length => _length;

  bool get isEmpty => _length == 0;

  bool get isNotEmpty => _length != 0;

  /// Adds a range of cells from [src] to the builder. Anchors within the range
  /// will be reparented to the new line returned by [take].
  void add(BufferLine src, int start, int length) {
    _result.copyFrom(src, start, _length, length);
    _length += length;
  }

  /// Reuses the given [line] as the initial buffer for this builder.
  void setBuffer(BufferLine line, int length) {
    _result = line;
    _length = length;
  }

  void addAnchor(CellAnchor anchor, int offset) {
    anchor.reparent(_result, _length + offset);
  }

  BufferLine take({required bool wrapped}) {
    final result = _result;
    result.isWrapped = wrapped;
    // result.resize(_length);

    _result = BufferLine(_capacity);
    _length = 0;

    return result;
  }
}

/// Holds a the state of reflow operation of a single logical line.
class _LineReflow {
  final int oldWidth;

  final int newWidth;

  _LineReflow(this.oldWidth, this.newWidth);

  final _lines = <BufferLine>[];

  _LineBuilder? _builder;

  _LineBuilder get _activeBuilder {
    final existing = _builder;
    if (existing != null) return existing;
    final created = _LineBuilder(newWidth);
    _builder = created;
    return created;
  }

  /// Adds a line to the reflow operation. This method will try to reuse the
  /// given line if possible.
  void add(BufferLine line) {
    final trimmedLength = line.getTrimmedLength(oldWidth);

    // A fast path for empty lines
    if (trimmedLength == 0) {
      _lines.add(line);
      return;
    }

    // We already have some content in the buffer, so we copy the content into
    // the builder instead of reusing the line.
    final builder = _builder;
    if (_lines.isNotEmpty || (builder != null && builder.isNotEmpty)) {
      _addPart(line, from: 0, to: trimmedLength);
      return;
    }

    if (newWidth >= oldWidth) {
      // Reuse the line to avoid copying the content and object allocation.
      _activeBuilder.setBuffer(line, trimmedLength);
    } else {
      _lines.add(line);

      if (trimmedLength > newWidth) {
        if (line.getWidth(newWidth - 1) == 2) {
          _addPart(line, from: newWidth - 1, to: trimmedLength);
        } else {
          _addPart(line, from: newWidth, to: trimmedLength);
        }
      }
    }

    line.resize(newWidth);

    if (line.getWidth(newWidth - 1) == 2) {
      line.resetCell(newWidth - 1);
    }
  }

  /// Adds part of [line] from [from] to [to] to the reflow operation.
  /// Anchors within the range will be removed from [line] and reparented to
  /// the new line(s) returned by [finish].
  void _addPart(BufferLine line, {required int from, required int to}) {
    final builder = _activeBuilder;
    var cellsLeft = to - from;

    while (cellsLeft > 0) {
      final bufferRemainingCells = newWidth - builder.length;

      // How many cells we should copy in this iteration.
      var cellsToCopy = cellsLeft;

      // Whether the buffer is filled up in this iteration.
      var lineFilled = false;

      if (cellsToCopy >= bufferRemainingCells) {
        cellsToCopy = bufferRemainingCells;
        lineFilled = true;
      }

      // Leave the last cell to the next iteration if it's a wide char.
      if (lineFilled && line.getWidth(from + cellsToCopy - 1) == 2) {
        cellsToCopy--;
      }

      // A wide cell cannot be represented in a one-column terminal. Dropping
      // it matches normal input behavior and, critically, guarantees that the
      // reflow loop keeps making progress.
      if (cellsToCopy == 0 && builder.isEmpty) {
        final wideCellWidth = line.getWidth(from);
        assert(wideCellWidth == 2);
        from += wideCellWidth;
        cellsLeft -= wideCellWidth;
        continue;
      }

      for (var anchor in line.anchors.toList()) {
        if (anchor.x >= from && anchor.x <= from + cellsToCopy) {
          builder.addAnchor(anchor, anchor.x - from);
        }
      }

      builder.add(line, from, cellsToCopy);

      from += cellsToCopy;
      cellsLeft -= cellsToCopy;

      // Create a new line if the buffer is filled up.
      if (lineFilled) {
        _lines.add(builder.take(wrapped: _lines.isNotEmpty));
      }
    }

    if (line.anchors.isNotEmpty) {
      for (var anchor in line.anchors.toList()) {
        if (anchor.x >= to) {
          builder.addAnchor(anchor, anchor.x - to);
        }
      }
    }
  }

  /// Finalizes the reflow operation and returns the result.
  List<BufferLine> finish() {
    final builder = _builder;
    if (builder != null && builder.isNotEmpty) {
      _lines.add(builder.take(wrapped: _lines.isNotEmpty));
    }

    return _lines;
  }
}

List<BufferLine> reflow(
  IndexAwareCircularBuffer<BufferLine> lines,
  int oldWidth,
  int newWidth,
) {
  final result = <BufferLine>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final continuesOnNextLine = i + 1 < lines.length && lines[i + 1].isWrapped;
    if (!line.isWrapped &&
        !continuesOnNextLine &&
        line.getTrimmedLength(oldWidth) <= newWidth) {
      result.add(line);
      continue;
    }

    final reflow = _LineReflow(oldWidth, newWidth);

    reflow.add(line);

    for (var offset = i + 1; offset < lines.length; offset++) {
      final nextLine = lines[offset];

      if (!nextLine.isWrapped) {
        break;
      }

      i++;

      reflow.add(nextLine);
    }

    result.addAll(reflow.finish());
  }

  for (var line in result) {
    line.resize(newWidth);
  }

  return result;
}
