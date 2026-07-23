import 'dart:typed_data';

import 'package:xterm2/src/core/buffer/buffer.dart';
import 'package:xterm2/src/core/buffer/cell_offset.dart';
import 'package:xterm2/src/core/buffer/line.dart';
import 'package:xterm2/src/core/buffer/range_line.dart';
import 'package:xterm2/src/terminal.dart';

const _defaultSearchResultLimit = 1000;

final _wordCodePoint = RegExp(
  r'^[\p{L}\p{M}\p{N}\p{Pc}\u200C\u200D]$',
  unicode: true,
);

/// A terminal buffer search match.
final class TerminalSearchMatch {
  const TerminalSearchMatch({
    required this.range,
    required this.text,
  });

  /// The matched cell range. The end offset is exclusive.
  final BufferRangeLine range;

  /// The text matched in the terminal buffer.
  final String text;
}

/// Search support for terminal scrollback and the active viewport.
extension TerminalSearch on Terminal {
  /// Finds [query] in the active buffer.
  ///
  /// Soft-wrapped physical rows are searched as one logical line. Search
  /// results are capped by [maxResults] so repeated output cannot cause
  /// unbounded result allocation.
  List<TerminalSearchMatch> search(
    String query, {
    bool caseSensitive = false,
    bool wholeWord = false,
    bool useRegex = false,
    int maxResults = _defaultSearchResultLimit,
  }) {
    if (query.isEmpty || maxResults <= 0) {
      return const [];
    }

    final pattern = switch (useRegex) {
      true => query,
      false => RegExp.escape(query),
    };
    final expression = RegExp(
      pattern,
      caseSensitive: caseSensitive,
      unicode: true,
    );
    final results = <TerminalSearchMatch>[];
    final buffer = this.buffer;
    final textBuffer = StringBuffer();
    final searchCells = _SearchCells();
    var lineIndex = 0;

    while (lineIndex < buffer.lines.length && results.length < maxResults) {
      final logicalLine = _buildLogicalLine(
        buffer,
        lineIndex,
        textBuffer,
        searchCells,
      );
      lineIndex = logicalLine.nextLineIndex;
      if (logicalLine.text.isEmpty || logicalLine.cells.isEmpty) continue;

      for (final match in expression.allMatches(logicalLine.text)) {
        if (match.start == match.end) continue;
        if (wholeWord && !_isWholeWord(logicalLine.text, match)) continue;

        final startCell = logicalLine.cells.cellAt(buffer, match.start);
        final endCell = logicalLine.cells.cellAt(buffer, match.end - 1);
        if (startCell == null || endCell == null) continue;

        results.add(
          TerminalSearchMatch(
            range: BufferRangeLine(
              CellOffset(startCell.x, startCell.y),
              CellOffset(endCell.x + endCell.width, endCell.y),
            ),
            text: logicalLine.text.substring(match.start, match.end),
          ),
        );
        if (results.length >= maxResults) break;
      }
    }

    return results;
  }
}

final class _LogicalLine {
  const _LogicalLine({
    required this.text,
    required this.cells,
    required this.nextLineIndex,
  });

  final String text;
  final _SearchCells cells;
  final int nextLineIndex;
}

final class _SearchCell {
  const _SearchCell({
    required this.x,
    required this.y,
    required this.width,
  });

  final int x;
  final int y;
  final int width;
}

final class _SearchCells {
  var _textStarts = Int32List(256);
  var _columns = Int32List(256);
  var _lines = Int32List(256);
  var length = 0;

  bool get isEmpty => length == 0;

  void clear() {
    length = 0;
  }

  void add({
    required int textStart,
    required int column,
    required int line,
  }) {
    if (length == _textStarts.length) {
      final nextLength = _textStarts.length * 2;
      _textStarts = _grow(_textStarts, nextLength);
      _columns = _grow(_columns, nextLength);
      _lines = _grow(_lines, nextLength);
    }
    _textStarts[length] = textStart;
    _columns[length] = column;
    _lines[length] = line;
    length++;
  }

  _SearchCell? cellAt(Buffer buffer, int textOffset) {
    var low = 0;
    var high = length - 1;
    while (low <= high) {
      final middle = low + ((high - low) >> 1);
      if (_textStarts[middle] <= textOffset) {
        low = middle + 1;
        continue;
      }
      high = middle - 1;
    }
    if (high < 0) return null;

    final x = _columns[high];
    final y = _lines[high];
    final width = buffer.lines[y].getWidth(x);
    return _SearchCell(
      x: x,
      y: y,
      width: switch (width) {
        0 => 1,
        _ => width,
      },
    );
  }

  Int32List _grow(Int32List source, int length) {
    final result = Int32List(length);
    result.setRange(0, source.length, source);
    return result;
  }
}

_LogicalLine _buildLogicalLine(
  Buffer buffer,
  int firstLineIndex,
  StringBuffer text,
  _SearchCells cells,
) {
  text.clear();
  cells.clear();
  var lineIndex = firstLineIndex;

  while (lineIndex < buffer.lines.length) {
    final line = buffer.lines[lineIndex];
    final nextLineIndex = lineIndex + 1;
    final continuesToNext = nextLineIndex < buffer.lines.length &&
        buffer.lines[nextLineIndex].isWrapped;
    _appendSearchableLine(
      text,
      cells,
      line,
      lineIndex,
      includeFullWidth: continuesToNext,
      viewWidth: buffer.viewWidth,
    );
    lineIndex = nextLineIndex;
    if (!continuesToNext) break;
  }

  return _LogicalLine(
    text: text.toString(),
    cells: cells,
    nextLineIndex: lineIndex,
  );
}

void _appendSearchableLine(
  StringBuffer text,
  _SearchCells cells,
  BufferLine line,
  int lineIndex, {
  required bool includeFullWidth,
  required int viewWidth,
}) {
  final end = switch (includeFullWidth) {
    true => viewWidth,
    false => line.getTrimmedLength(viewWidth),
  };
  for (var column = 0; column < end; column++) {
    final codePoint = line.getCodePoint(column);
    final width = line.getWidth(column);
    final isWideSpacer =
        width == 0 && column > 0 && line.getWidth(column - 1) == 2;
    if (isWideSpacer) continue;

    final textStart = text.length;
    text.writeCharCode(switch (codePoint) {
      0 => 0x20,
      _ => codePoint,
    });
    final combiningCharacters = line.getCombiningCharacters(column);
    if (combiningCharacters != null) {
      text.write(combiningCharacters);
    }
    cells.add(
      textStart: textStart,
      column: column,
      line: lineIndex,
    );
  }
}

bool _isWholeWord(String text, RegExpMatch match) {
  final before = _codePointBefore(text, match.start);
  final after = _codePointAt(text, match.end);
  return !_isWordCodePoint(before) && !_isWordCodePoint(after);
}

int? _codePointBefore(String text, int offset) {
  if (offset <= 0) return null;
  final trailing = text.codeUnitAt(offset - 1);
  if (trailing < 0xdc00 || trailing > 0xdfff || offset < 2) {
    return trailing;
  }
  final leading = text.codeUnitAt(offset - 2);
  if (leading < 0xd800 || leading > 0xdbff) return trailing;
  return 0x10000 + ((leading - 0xd800) << 10) + trailing - 0xdc00;
}

int? _codePointAt(String text, int offset) {
  if (offset >= text.length) return null;
  final leading = text.codeUnitAt(offset);
  if (leading < 0xd800 || leading > 0xdbff || offset + 1 >= text.length) {
    return leading;
  }
  final trailing = text.codeUnitAt(offset + 1);
  if (trailing < 0xdc00 || trailing > 0xdfff) return leading;
  return 0x10000 + ((leading - 0xd800) << 10) + trailing - 0xdc00;
}

bool _isWordCodePoint(int? value) {
  if (value == null) return false;
  return _wordCodePoint.hasMatch(String.fromCharCode(value));
}
