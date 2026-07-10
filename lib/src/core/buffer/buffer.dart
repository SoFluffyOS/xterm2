import 'dart:math' show max, min;

import 'package:characters/characters.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/line.dart';
import 'package:xterm/src/core/buffer/range.dart';
import 'package:xterm/src/core/buffer/range_block.dart';
import 'package:xterm/src/core/buffer/range_line.dart';
import 'package:xterm/src/core/charset.dart';
import 'package:xterm/src/core/cell.dart';
import 'package:xterm/src/core/cursor.dart';
import 'package:xterm/src/core/reflow.dart';
import 'package:xterm/src/core/state.dart';
import 'package:xterm/src/utils/circular_buffer.dart';
import 'package:xterm/src/utils/unicode_v11.dart';

class Buffer {
  final TerminalState terminal;

  final int maxLines;

  final bool isAltBuffer;

  /// Characters that break selection when calling [getWordBoundary]. If null,
  /// defaults to [defaultWordSeparators].
  final Set<int>? wordSeparators;

  Buffer(
    this.terminal, {
    required this.maxLines,
    required this.isAltBuffer,
    this.wordSeparators,
  }) {
    for (int i = 0; i < terminal.viewHeight; i++) {
      lines.push(_newEmptyLine());
    }

    resetVerticalMargins();
    resetHorizontalMargins();
  }

  int _cursorX = 0;

  int _cursorY = 0;

  late int _marginTop;

  late int _marginBottom;

  late int _marginLeft;

  late int _marginRight;

  var _savedCursorX = 0;

  var _savedCursorY = 0;

  var _savedOriginMode = false;

  final _savedCursorStyle = CursorStyle();

  final charset = Charset();

  /// Width of the viewport in columns. Also the index of the last column.
  int get viewWidth => terminal.viewWidth;

  /// Height of the viewport in rows. Also the index of the last line.
  int get viewHeight => terminal.viewHeight;

  /// lines of the buffer. the length of [lines] should always be equal or
  /// greater than [viewHeight].
  late final lines = IndexAwareCircularBuffer<BufferLine>(
    max(maxLines, terminal.viewHeight),
  );

  /// Total number of lines in the buffer. Always equal or greater than
  /// [viewHeight].
  int get height => lines.length;

  /// Horizontal position of the cursor relative to the top-left cornor of the
  /// screen, starting from 0.
  int get cursorX => _cursorX.clamp(0, terminal.viewWidth - 1);

  /// Vertical position of the cursor relative to the top-left cornor of the
  /// screen, starting from 0.
  int get cursorY => _cursorY;

  /// Index of the first line in the scroll region.
  int get marginTop => _marginTop;

  /// Index of the last line in the scroll region.
  int get marginBottom => _marginBottom;

  /// Index of the first column in the horizontal scroll region.
  int get marginLeft => _marginLeft;

  /// Index of the last column in the horizontal scroll region.
  int get marginRight => _marginRight;

  /// The number of lines above the viewport.
  int get scrollBack => height - viewHeight;

  /// Vertical position of the cursor relative to the top of the buffer,
  /// starting from 0.
  int get absoluteCursorY => _cursorY + scrollBack;

  /// Absolute index of the first line in the scroll region.
  int get absoluteMarginTop => _marginTop + scrollBack;

  /// Absolute index of the last line in the scroll region.
  int get absoluteMarginBottom => _marginBottom + scrollBack;

  /// Writes data to the _terminal. Terminal sequences or special characters are
  /// not interpreted and directly added to the buffer.
  ///
  /// See also: [Terminal.write]
  void write(String text) {
    for (var char in text.runes) {
      writeChar(char);
    }
  }

  /// Writes a single character to the _terminal. Escape sequences or special
  /// characters are not interpreted and directly added to the buffer.
  ///
  /// See also: [Terminal.writeChar]
  void writeChar(int codePoint) {
    codePoint = charset.translate(codePoint);

    final cellWidth = unicodeV11.wcwidth(codePoint);
    if (terminal.graphemeClusterMode &&
        (codePoint == 0xFE0E || codePoint == 0xFE0F)) {
      if (_previousSupportsEmojiVariation()) {
        _resizePreviousGrapheme(codePoint);
        _addCombiningCharacter(codePoint);
      }
      return;
    }
    if (cellWidth == 0) {
      if (!terminal.graphemeClusterMode || _joinsPreviousGrapheme(codePoint)) {
        _addCombiningCharacter(codePoint);
      }
      return;
    }
    if (cellWidth < 0) return;
    if (terminal.graphemeClusterMode && _joinRegionalIndicator(codePoint)) {
      return;
    }
    if (terminal.graphemeClusterMode && _joinsPreviousGrapheme(codePoint)) {
      if (cellWidth == 2) _setPreviousGraphemeWidth(2);
      _addCombiningCharacter(codePoint);
      return;
    }

    final rightLimit = _rightLimit;

    if (_cursorX >= rightLimit) {
      if (terminal.autoWrapMode) {
        _wrapInput();
      } else {
        _cursorX = rightLimit - 1;
      }
    }

    if (cellWidth > rightLimit - _marginLeft) {
      _cursorX = rightLimit;
      return;
    }

    if (cellWidth == 2 && _cursorX == rightLimit - 1) {
      if (!terminal.autoWrapMode) {
        _cursorX = rightLimit;
        return;
      }

      currentLine.setCell(_cursorX, 0, 1, terminal.cursor);
      _cursorX = rightLimit;
      _wrapInput();
    }

    final line = currentLine;
    if (terminal.insertMode) {
      line.insertCells(_cursorX, cellWidth, terminal.cursor);
    }
    if (!terminal.insertMode) {
      line.clearWideCellAt(_cursorX, terminal.cursor);
      if (cellWidth == 2) {
        line.clearWideCellAt(_cursorX + 1, terminal.cursor);
      }
    }
    line.setCell(_cursorX, codePoint, cellWidth, terminal.cursor);

    if (cellWidth == 2) {
      line.setCell(_cursorX + 1, 0, 0, terminal.cursor);
    }

    _cursorX += cellWidth;
  }

  void _addCombiningCharacter(int codePoint) {
    var index = 0;
    if (_cursorX >= 1) {
      index = min(_cursorX - 1, viewWidth - 1);
    }
    if (index > 0 && currentLine.getWidth(index) == 0) {
      index--;
    }
    currentLine.addCombiningCharacter(index, codePoint);
  }

  bool _resizePreviousGrapheme(int variationSelector) {
    final desiredWidth = switch (variationSelector) {
      0xFE0F => 2,
      0xFE0E => 1,
      _ => null,
    };
    if (desiredWidth == null) return false;
    return _setPreviousGraphemeWidth(desiredWidth);
  }

  bool _previousSupportsEmojiVariation() {
    final index = _previousCellIndex();
    if (index == null) return false;
    return _supportsEmojiVariation(currentLine.getCodePoint(index));
  }

  bool _setPreviousGraphemeWidth(int desiredWidth) {
    final index = _previousCellIndex();
    if (index == null || currentLine.getCodePoint(index) == 0) return false;

    final width = currentLine.getWidth(index);
    if (desiredWidth == 2 && width == 1) {
      if (index + 1 >= viewWidth) {
        if (!terminal.autoWrapMode) return false;

        final sourceLine = currentLine;
        final cellData = CellData.empty();
        sourceLine.getCellData(index, cellData);
        final combining = sourceLine.getCombiningCharacters(index);
        sourceLine.eraseCell(index, terminal.cursor);
        _cursorX = viewWidth;
        _wrapInput();
        currentLine.setCellData(0, cellData);
        currentLine.setWidth(0, 2);
        if (combining != null) {
          for (final codePoint in combining.runes) {
            currentLine.addCombiningCharacter(0, codePoint);
          }
        }
        currentLine.setCell(1, 0, 0, terminal.cursor);
        _cursorX = 2;
        return true;
      }
      currentLine.clearWideCellAt(index + 1, terminal.cursor);
      currentLine.setWidth(index, 2);
      currentLine.setCell(index + 1, 0, 0, terminal.cursor);
      if (_cursorX == index + 1) _cursorX++;
      return true;
    }

    if (desiredWidth == 1 && width == 2) {
      currentLine.setWidth(index, 1);
      currentLine.eraseCell(index + 1, terminal.cursor);
      if (_cursorX == index + 2) _cursorX--;
      return true;
    }

    return false;
  }

  int? _previousCellIndex() {
    if (_cursorX == 0) return null;
    var index = min(_cursorX - 1, viewWidth - 1);
    if (index > 0 && currentLine.getWidth(index) == 0) index--;
    return index;
  }

  bool _joinsPreviousGrapheme(int codePoint) {
    final index = _previousCellIndex();
    if (index == null) return false;

    final base = currentLine.getCodePoint(index);
    if (base == 0) return false;
    final combining = currentLine.getCombiningCharacters(index);

    if (_isEmojiModifier(codePoint)) {
      var modifierBase = base;
      if (combining != null) {
        for (final rune in combining.runes) {
          if (rune == 0x200D || rune == 0xFE0E || rune == 0xFE0F) continue;
          modifierBase = rune;
        }
      }
      if (_isEmojiModifierBase(modifierBase) == false) return false;
    }

    // Almost all terminal output is ASCII, where a new printable code point
    // always starts a new grapheme. Avoid allocating strings on that path.
    if (base < 0x80 && codePoint < 0x80 && combining == null) return false;
    if (combining == null &&
        unicodeV11.wcwidth(base) == 2 &&
        unicodeV11.wcwidth(codePoint) == 2 &&
        _isEmojiModifier(codePoint) == false &&
        _isHangul(base) == false &&
        _isHangul(codePoint) == false) {
      return false;
    }

    final previous = String.fromCharCode(base) + (combining ?? '');
    final candidate = previous + String.fromCharCode(codePoint);
    return candidate.characters.length == 1;
  }

  static bool _isEmojiModifier(int codePoint) {
    return codePoint >= 0x1F3FB && codePoint <= 0x1F3FF;
  }

  static bool _isHangul(int codePoint) {
    return codePoint >= 0x1100 && codePoint <= 0x11FF ||
        codePoint >= 0xA960 && codePoint <= 0xA97F ||
        codePoint >= 0xAC00 && codePoint <= 0xD7A3 ||
        codePoint >= 0xD7B0 && codePoint <= 0xD7FF;
  }

  static bool _isEmojiModifierBase(int codePoint) {
    return switch (codePoint) {
      0x261D || 0x26F9 || >= 0x270A && <= 0x270D => true,
      0x1F385 || >= 0x1F3C2 && <= 0x1F3C4 || 0x1F3C7 => true,
      >= 0x1F3CA && <= 0x1F3CC => true,
      >= 0x1F442 && <= 0x1F443 || >= 0x1F446 && <= 0x1F450 => true,
      >= 0x1F466 && <= 0x1F478 || 0x1F47C => true,
      >= 0x1F481 && <= 0x1F483 || >= 0x1F485 && <= 0x1F487 => true,
      0x1F48F || 0x1F491 || 0x1F4AA => true,
      >= 0x1F574 && <= 0x1F575 || 0x1F57A || 0x1F590 => true,
      >= 0x1F595 && <= 0x1F596 => true,
      >= 0x1F645 && <= 0x1F647 || >= 0x1F64B && <= 0x1F64F => true,
      0x1F6A3 || >= 0x1F6B4 && <= 0x1F6B6 => true,
      0x1F6C0 || 0x1F6CC || 0x1F90C || 0x1F90F || 0x1F918 => true,
      >= 0x1F919 && <= 0x1F91F || 0x1F926 => true,
      >= 0x1F930 && <= 0x1F939 || >= 0x1F93C && <= 0x1F93E => true,
      0x1F977 || >= 0x1F9B5 && <= 0x1F9B6 => true,
      >= 0x1F9B8 && <= 0x1F9B9 || 0x1F9BB => true,
      >= 0x1F9CD && <= 0x1F9CF || >= 0x1F9D1 && <= 0x1F9DD => true,
      >= 0x1FAC3 && <= 0x1FAC5 || >= 0x1FAF0 && <= 0x1FAF8 => true,
      _ => false,
    };
  }

  bool _joinRegionalIndicator(int codePoint) {
    if (!_isRegionalIndicator(codePoint) || _cursorX == 0) return false;
    var index = min(_cursorX - 1, viewWidth - 1);
    if (index > 0 && currentLine.getWidth(index) == 0) {
      index--;
    }
    if (!_isRegionalIndicator(currentLine.getCodePoint(index)) ||
        currentLine.getCombiningCharacters(index) != null ||
        currentLine.getWidth(index) != 1 ||
        _cursorX >= viewWidth) {
      return false;
    }

    currentLine.addCombiningCharacter(index, codePoint);
    currentLine.setWidth(index, 2);
    currentLine.setCell(_cursorX, 0, 0, terminal.cursor);
    _cursorX++;
    return true;
  }

  static bool _isRegionalIndicator(int codePoint) {
    return codePoint >= 0x1F1E6 && codePoint <= 0x1F1FF;
  }

  static bool _supportsEmojiVariation(int codePoint) {
    return switch (codePoint) {
      0x23 || 0x2A || >= 0x30 && <= 0x39 => true,
      0xA9 || 0xAE || 0x203C || 0x2049 || 0x2122 || 0x2139 => true,
      >= 0x2194 && <= 0x2199 || >= 0x21A9 && <= 0x21AA => true,
      >= 0x231A && <= 0x231B || 0x2328 || 0x23CF => true,
      >= 0x23E9 && <= 0x23F3 || >= 0x23F8 && <= 0x23FA => true,
      0x24C2 || >= 0x25AA && <= 0x25AB || 0x25B6 || 0x25C0 => true,
      >= 0x25FB && <= 0x25FE || >= 0x2600 && <= 0x2604 => true,
      0x260E || 0x2611 || >= 0x2614 && <= 0x2615 || 0x2618 || 0x261D => true,
      0x2620 || >= 0x2622 && <= 0x2623 || 0x2626 || 0x262A => true,
      >= 0x262E && <= 0x262F || >= 0x2638 && <= 0x263A => true,
      0x2640 || 0x2642 || >= 0x2648 && <= 0x2653 => true,
      >= 0x265F && <= 0x2660 || 0x2663 || >= 0x2665 && <= 0x2666 => true,
      0x2668 || 0x267B || >= 0x267E && <= 0x267F => true,
      >= 0x2692 && <= 0x2697 || 0x2699 || >= 0x269B && <= 0x269C => true,
      >= 0x26A0 && <= 0x26A1 || 0x26A7 || >= 0x26AA && <= 0x26AB => true,
      >= 0x26B0 && <= 0x26B1 || >= 0x26BD && <= 0x26BE => true,
      >= 0x26C4 && <= 0x26C5 || 0x26C8 || >= 0x26CE && <= 0x26CF => true,
      0x26D1 || >= 0x26D3 && <= 0x26D4 || >= 0x26E9 && <= 0x26EA => true,
      >= 0x26F0 && <= 0x26F5 || >= 0x26F7 && <= 0x26FA || 0x26FD => true,
      0x2702 || 0x2705 || >= 0x2708 && <= 0x270D || 0x270F => true,
      0x2712 || 0x2714 || 0x2716 || 0x271D || 0x2721 || 0x2728 => true,
      >= 0x2733 && <= 0x2734 || 0x2744 || 0x2747 || 0x274C || 0x274E => true,
      >= 0x2753 && <= 0x2755 || 0x2757 || >= 0x2763 && <= 0x2764 => true,
      >= 0x2795 && <= 0x2797 || 0x27A1 || 0x27B0 || 0x27BF => true,
      >= 0x2934 && <= 0x2935 || >= 0x2B05 && <= 0x2B07 => true,
      >= 0x2B1B && <= 0x2B1C || 0x2B50 || 0x2B55 => true,
      0x3030 || 0x303D || 0x3297 || 0x3299 => true,
      >= 0x1F000 && <= 0x1FAFF => true,
      _ => false,
    };
  }

  void _wrapInput() {
    index();
    setCursorX(_marginLeft);
    currentLine.isWrapped = true;
  }

  /// The line at the current cursor position.
  BufferLine get currentLine {
    return lines[absoluteCursorY];
  }

  void backspace() {
    if (_cursorX == 0 && currentLine.isWrapped) {
      currentLine.isWrapped = false;
      moveCursor(viewWidth - 1, -1);
    } else if (_cursorX == viewWidth) {
      moveCursor(-2, 0);
    } else {
      moveCursor(-1, 0);
    }
  }

  /// Erases the viewport from the cursor position to the end of the buffer,
  /// including the cursor position.
  void eraseDisplayFromCursor({bool respectProtected = false}) {
    eraseLineFromCursor(respectProtected: respectProtected);

    for (var i = absoluteCursorY + 1; i < height; i++) {
      final line = lines[i];
      line.isWrapped = false;
      line.eraseRange(
        0,
        viewWidth,
        terminal.cursor,
        respectProtected: respectProtected,
      );
    }
  }

  /// Erases the viewport from the top-left corner to the cursor, including the
  /// cursor.
  void eraseDisplayToCursor({bool respectProtected = false}) {
    eraseLineToCursor(respectProtected: respectProtected);

    for (var i = 0; i < _cursorY; i++) {
      final line = lines[i + scrollBack];
      line.isWrapped = false;
      line.eraseRange(
        0,
        viewWidth,
        terminal.cursor,
        respectProtected: respectProtected,
      );
    }
  }

  /// Erases the whole viewport.
  void eraseDisplay({bool respectProtected = false}) {
    for (var i = 0; i < viewHeight; i++) {
      final line = lines[i + scrollBack];
      line.isWrapped = false;
      line.eraseRange(
        0,
        viewWidth,
        terminal.cursor,
        respectProtected: respectProtected,
      );
    }
  }

  /// Erases the line from the cursor to the end of the line, including the
  /// cursor position.
  void eraseLineFromCursor({bool respectProtected = false}) {
    currentLine.isWrapped = false;
    currentLine.eraseRange(
      _cursorX,
      viewWidth,
      terminal.cursor,
      respectProtected: respectProtected,
    );
  }

  /// Erases the line from the start of the line to the cursor, including the
  /// cursor.
  void eraseLineToCursor({bool respectProtected = false}) {
    currentLine.isWrapped = false;
    currentLine.eraseRange(
      0,
      _cursorX + 1,
      terminal.cursor,
      respectProtected: respectProtected,
    );
  }

  /// Erases the line at the current cursor position.
  void eraseLine({bool respectProtected = false}) {
    currentLine.isWrapped = false;
    currentLine.eraseRange(
      0,
      viewWidth,
      terminal.cursor,
      respectProtected: respectProtected,
    );
  }

  /// Erases [count] cells starting at the cursor position.
  void eraseChars(int count, {bool respectProtected = false}) {
    final start = _cursorX;
    count = min(count, viewWidth - start);
    currentLine.eraseRange(
      start,
      start + count,
      terminal.cursor,
      respectProtected: respectProtected,
    );
  }

  void scrollDown(int count) {
    if (_usesFullHorizontalMargins) {
      _scrollDownFullWidth(count);
      return;
    }

    final width = _marginRight - _marginLeft + 1;
    for (var i = absoluteMarginBottom; i >= absoluteMarginTop; i--) {
      if (i >= absoluteMarginTop + count) {
        lines[i].copyFrom(
          lines[i - count],
          _marginLeft,
          _marginLeft,
          width,
        );
      } else {
        lines[i].eraseRange(_marginLeft, _marginRight + 1, terminal.cursor);
      }
    }
  }

  void scrollUp(int count) {
    if (_usesFullHorizontalMargins) {
      _scrollUpFullWidth(count);
      return;
    }

    final width = _marginRight - _marginLeft + 1;
    for (var i = absoluteMarginTop; i <= absoluteMarginBottom; i++) {
      if (i <= absoluteMarginBottom - count) {
        lines[i].copyFrom(
          lines[i + count],
          _marginLeft,
          _marginLeft,
          width,
        );
      } else {
        lines[i].eraseRange(_marginLeft, _marginRight + 1, terminal.cursor);
      }
    }
  }

  void _scrollDownFullWidth(int count) {
    for (var i = absoluteMarginBottom; i >= absoluteMarginTop; i--) {
      if (i >= absoluteMarginTop + count) {
        lines[i] = lines[i - count];
      } else {
        lines[i] = _newEmptyLine();
      }
    }
  }

  void _scrollUpFullWidth(int count) {
    if (_canScrollUpByPushingLines) {
      final linesToPush = min(count, viewHeight);
      for (var i = 0; i < linesToPush; i++) {
        lines.push(_newEmptyLine());
      }
      return;
    }

    for (var i = absoluteMarginTop; i <= absoluteMarginBottom; i++) {
      if (i <= absoluteMarginBottom - count) {
        lines[i] = lines[i + count];
      } else {
        lines[i] = _newEmptyLine();
      }
    }
  }

  bool get _canScrollUpByPushingLines {
    if (!isAltBuffer) return false;
    if (_marginTop != 0) return false;
    return _marginBottom == viewHeight - 1;
  }

  /// https://vt100.net/docs/vt100-ug/chapter3.html#IND IND – Index
  ///
  /// ESC D
  ///
  /// [index] causes the active position to move downward one line without
  /// changing the column position. If the active position is at the bottom
  /// margin, a scroll up is performed.
  void index() {
    if (isInVerticalMargin) {
      if (!isInHorizontalMarginOrPendingWrap) return;
      if (_cursorY == _marginBottom) {
        if (marginTop == 0 && !isAltBuffer) {
          lines.insert(absoluteMarginBottom + 1, _newEmptyLine());
        } else {
          scrollUp(1);
        }
      } else {
        moveCursorY(1);
      }
      return;
    }

    // the cursor is not in the scrollable region
    if (_cursorY >= viewHeight - 1) {
      // we are at the bottom
      if (isAltBuffer) {
        scrollUp(1);
      } else {
        lines.push(_newEmptyLine());
      }
    } else {
      // there're still lines so we simply move cursor down.
      moveCursorY(1);
    }
  }

  void lineFeed() {
    index();
    if (terminal.lineFeedMode) {
      setCursorX(0);
    }
  }

  /// https://terminalguide.namepad.de/seq/a_esc_cm/
  void reverseIndex() {
    if (isInVerticalMargin) {
      if (!isInHorizontalMarginOrPendingWrap) return;
      if (_cursorY == _marginTop) {
        scrollDown(1);
      } else {
        moveCursorY(-1);
      }
    } else {
      moveCursorY(-1);
    }
  }

  void cursorGoForward() {
    _cursorX = min(_cursorX + 1, _rightLimit);
  }

  void setCursorX(int cursorX) {
    _cursorX =
        cursorX.clamp(_minimumCursorX(cursorX), _maximumCursorX(cursorX));
  }

  void setCursorY(int cursorY) {
    _cursorY = cursorY.clamp(0, viewHeight - 1);
  }

  void moveCursorX(int offset) {
    if (offset < 0) {
      _moveCursorLeft(-offset);
      return;
    }

    setCursorX(_cursorX + offset);
  }

  void _moveCursorLeft(int count) {
    if (count <= 0) return;

    final wrapMode = _cursorLeftWrapMode;
    if (_isPendingWrap) {
      _cursorX = _rightLimit - 1;
      count -= 1;
      if (count == 0) return;
    }

    if (wrapMode == _CursorLeftWrapMode.none) {
      setCursorX(_cursorX - count);
      return;
    }

    final top = _marginTop;
    final bottom = _marginBottom;
    final right = _marginRight;
    final left = switch (_cursorX < _marginLeft) {
      true => 0,
      false => _marginLeft,
    };

    if (_cursorX == left &&
        wrapMode == _CursorLeftWrapMode.reverse &&
        _cursorY <= top) {
      _cursorX = left;
      _cursorY = top;
      return;
    }

    while (count > 0) {
      final amount = min(_cursorX - left, count);
      _cursorX -= amount;
      count -= amount;
      if (count == 0) return;

      if (_cursorY == top) {
        if (wrapMode != _CursorLeftWrapMode.reverseExtended) return;

        _cursorX = right;
        _cursorY = bottom;
        count -= 1;
        continue;
      }

      if (_cursorY == 0) return;

      if (wrapMode == _CursorLeftWrapMode.reverse) {
        if (!currentLine.isWrapped) return;
      }

      _cursorX = right;
      _cursorY -= 1;
      count -= 1;
    }
  }

  bool get _isPendingWrap {
    return _cursorX == _rightLimit;
  }

  _CursorLeftWrapMode get _cursorLeftWrapMode {
    if (!terminal.autoWrapMode) return _CursorLeftWrapMode.none;
    if (terminal.reverseWrapExtendedMode) {
      return _CursorLeftWrapMode.reverseExtended;
    }
    if (terminal.reverseWrapMode) return _CursorLeftWrapMode.reverse;
    return _CursorLeftWrapMode.none;
  }

  void moveCursorY(int offset) {
    final constrainedToMargins = terminal.originMode || isInVerticalMargin;
    final minimumY = switch (constrainedToMargins) {
      true => _marginTop,
      false => 0,
    };
    final maximumY = switch (constrainedToMargins) {
      true => _marginBottom,
      false => viewHeight - 1,
    };
    _cursorY = (_cursorY + offset).clamp(minimumY, maximumY);
  }

  void setCursor(int cursorX, int cursorY) {
    var maxCursorY = viewHeight - 1;

    if (terminal.originMode) {
      cursorY += _marginTop;
      maxCursorY = _marginBottom;
    }

    final minimumCursorX = switch (terminal.originMode) {
      true => _marginLeft,
      false => 0,
    };
    final maximumCursorX = switch (terminal.originMode) {
      true => _marginRight,
      false => viewWidth - 1,
    };
    if (terminal.originMode) {
      cursorX += _marginLeft;
    }

    _cursorX = cursorX.clamp(minimumCursorX, maximumCursorX);
    _cursorY = cursorY.clamp(0, maxCursorY);
  }

  void moveCursor(int offsetX, int offsetY) {
    moveCursorX(offsetX);
    moveCursorY(offsetY);
  }

  /// Save cursor position, charmap and text attributes.
  void saveCursor({required bool originMode}) {
    _savedCursorX = _cursorX;
    _savedCursorY = _cursorY;
    _savedOriginMode = originMode;
    _savedCursorStyle.foreground = terminal.cursor.foreground;
    _savedCursorStyle.background = terminal.cursor.background;
    _savedCursorStyle.underlineColor = terminal.cursor.underlineColor;
    _savedCursorStyle.attrs = terminal.cursor.attrs;
    _savedCursorStyle.hyperlinkId = terminal.cursor.hyperlinkId;
    charset.save();
  }

  /// Restore cursor position, charmap and text attributes.
  bool restoreCursor() {
    _cursorX = _savedCursorX;
    _cursorY = _savedCursorY;
    terminal.cursor.foreground = _savedCursorStyle.foreground;
    terminal.cursor.background = _savedCursorStyle.background;
    terminal.cursor.underlineColor = _savedCursorStyle.underlineColor;
    terminal.cursor.attrs = _savedCursorStyle.attrs;
    terminal.cursor.hyperlinkId = _savedCursorStyle.hyperlinkId;
    charset.restore();
    return _savedOriginMode;
  }

  /// Sets the vertical scrolling margin to [top] and [bottom].
  /// Both values must be between 0 and [viewHeight] - 1.
  void setVerticalMargins(int top, int bottom) {
    _marginTop = top.clamp(0, viewHeight - 1);
    _marginBottom = bottom.clamp(0, viewHeight - 1);

    _marginTop = min(_marginTop, _marginBottom);
    _marginBottom = max(_marginTop, _marginBottom);
  }

  /// Sets the horizontal scrolling margin to [left] and [right].
  /// Both values must be between 0 and [viewWidth] - 1.
  void setHorizontalMargins(int left, int right) {
    final effectiveLeft = left.clamp(0, viewWidth - 1);
    final effectiveRight = right.clamp(0, viewWidth - 1);
    if (effectiveLeft >= effectiveRight) return;

    _marginLeft = effectiveLeft;
    _marginRight = effectiveRight;
  }

  bool get isInVerticalMargin {
    return _cursorY >= _marginTop && _cursorY <= _marginBottom;
  }

  bool get isInHorizontalMargin {
    return _cursorX >= _marginLeft && _cursorX <= _marginRight;
  }

  bool get isInHorizontalMarginOrPendingWrap {
    return _cursorX >= _marginLeft && _cursorX <= _marginRight + 1;
  }

  void resetVerticalMargins() {
    setVerticalMargins(0, viewHeight - 1);
  }

  void resetHorizontalMargins() {
    _marginLeft = 0;
    _marginRight = viewWidth - 1;
  }

  void carriageReturn() {
    final left = switch (terminal.originMode || _cursorX >= _marginLeft) {
      true => _marginLeft,
      false => 0,
    };
    setCursorX(left);
  }

  int _minimumCursorX(int targetX) {
    if (terminal.originMode) return _marginLeft;
    if (_cursorX < _marginLeft && targetX < _marginLeft) return 0;
    return _marginLeft;
  }

  int _maximumCursorX(int targetX) {
    if (terminal.originMode) return _marginRight;
    if (_cursorX > _marginRight && targetX > _marginRight) {
      return viewWidth - 1;
    }
    return _marginRight;
  }

  int get _rightLimit {
    return switch (_cursorX <= _marginRight + 1) {
      true => _marginRight + 1,
      false => viewWidth,
    };
  }

  void deleteChars(int count) {
    final start = _cursorX.clamp(0, viewWidth);
    count = min(count, _rightLimit - start);
    currentLine.removeCells(start, count, terminal.cursor, _rightLimit);
  }

  bool get _usesFullHorizontalMargins {
    return _marginLeft == 0 && _marginRight == viewWidth - 1;
  }

  /// Remove all lines above the top of the viewport.
  void clearScrollback() {
    if (height <= viewHeight) {
      return;
    }

    lines.trimStart(scrollBack);
  }

  /// Clears the viewport and scrollback buffer. Then fill with empty lines.
  void clear() {
    lines.clear();
    for (int i = 0; i < viewHeight; i++) {
      lines.push(_newEmptyLine());
    }
  }

  void reset() {
    clear();
    _cursorX = 0;
    _cursorY = 0;
    _savedCursorX = 0;
    _savedCursorY = 0;
    _savedOriginMode = false;
    _savedCursorStyle.reset();
    _savedCursorStyle.hyperlinkId = 0;
    charset.reset();
    resetVerticalMargins();
    resetHorizontalMargins();
  }

  void screenAlignmentTest() {
    final viewportStart = scrollBack;
    final viewportEnd = viewportStart + viewHeight;
    for (var row = viewportStart; row < viewportEnd; row++) {
      final line = lines[row];
      line.isWrapped = false;
      for (var column = 0; column < viewWidth; column++) {
        line.setCell(column, 0x45, 1, CursorStyle.empty);
      }
    }
  }

  void resetViewport() {
    final viewportStart = scrollBack;
    final viewportEnd = viewportStart + viewHeight;
    for (var row = viewportStart; row < viewportEnd; row++) {
      final line = lines[row];
      line.isWrapped = false;
      for (var column = 0; column < viewWidth; column++) {
        line.resetCell(column);
      }
    }
    _cursorX = 0;
    _cursorY = 0;
    resetVerticalMargins();
    resetHorizontalMargins();
  }

  void insertBlankChars(int count) {
    count = min(count, _rightLimit - _cursorX);
    final style = terminal.cursor;
    currentLine.insertCells(
      _cursorX,
      count,
      CursorStyle(
        foreground: style.foreground,
        background: style.background,
        underlineColor: style.underlineColor,
        attrs: style.attrs,
      ),
      _rightLimit,
    );
  }

  void insertLines(int count) {
    if (!isInVerticalMargin || !isInHorizontalMargin) {
      return;
    }

    setCursorX(_marginLeft);

    // Number of lines from the cursor to the bottom of the scrollable region
    // including the cursor itself.
    final linesBelow = absoluteMarginBottom - absoluteCursorY + 1;

    // Number of empty lines to insert.
    final linesToInsert = min(count, linesBelow);

    // Number of lines to move up.
    final linesToMove = linesBelow - linesToInsert;

    if (!_usesFullHorizontalMargins) {
      final width = _marginRight - _marginLeft + 1;
      for (var i = 0; i < linesToMove; i++) {
        final index = absoluteMarginBottom - i;
        lines[index].copyFrom(
          lines[index - linesToInsert],
          _marginLeft,
          _marginLeft,
          width,
        );
      }

      for (var i = 0; i < linesToInsert; i++) {
        lines[absoluteCursorY + i].eraseRange(
          _marginLeft,
          _marginRight + 1,
          terminal.cursor,
        );
      }
      return;
    }

    for (var i = 0; i < linesToMove; i++) {
      final index = absoluteMarginBottom - i;
      lines[index] = lines.swap(index - linesToInsert, _newEmptyLine());
    }

    for (var i = linesToMove; i < linesToInsert; i++) {
      lines[absoluteCursorY + i] = _newEmptyLine();
    }
  }

  /// Remove [count] lines starting at the current cursor position. Lines below
  /// the removed lines are shifted up. This only affects the scrollable region.
  /// Lines outside the scrollable region are not affected.
  void deleteLines(int count) {
    if (!isInVerticalMargin || !isInHorizontalMargin) {
      return;
    }

    setCursorX(_marginLeft);

    count = min(count, absoluteMarginBottom - absoluteCursorY + 1);

    final linesToMove = absoluteMarginBottom - absoluteCursorY + 1 - count;

    if (!_usesFullHorizontalMargins) {
      final width = _marginRight - _marginLeft + 1;
      for (var i = 0; i < linesToMove; i++) {
        final index = absoluteCursorY + i;
        lines[index].copyFrom(
          lines[index + count],
          _marginLeft,
          _marginLeft,
          width,
        );
      }

      for (var i = 0; i < count; i++) {
        lines[absoluteMarginBottom - i].eraseRange(
          _marginLeft,
          _marginRight + 1,
          terminal.cursor,
        );
      }
      return;
    }

    for (var i = 0; i < linesToMove; i++) {
      final index = absoluteCursorY + i;
      lines[index] = lines[index + count];
    }

    for (var i = 0; i < count; i++) {
      lines[absoluteMarginBottom - i] = _newEmptyLine();
    }
  }

  void resize(int oldWidth, int oldHeight, int newWidth, int newHeight) {
    if (newHeight > lines.maxLength) {
      lines.maxLength = newHeight;
    }

    // 1. Adjust the height.
    if (newHeight > oldHeight) {
      // Grow larger
      for (var i = 0; i < newHeight - oldHeight; i++) {
        if (newHeight > lines.length) {
          lines.push(_newEmptyLine(newWidth));
        } else {
          _cursorY++;
        }
      }
    } else {
      // Shrink smaller
      for (var i = 0; i < oldHeight - newHeight; i++) {
        if (_cursorY > newHeight - 1) {
          _cursorY--;
        } else {
          lines.pop();
        }
      }
    }

    // Ensure cursor row is within the screen. The column is clamped after
    // width handling so reflow can preserve its logical offset.
    _cursorY = _cursorY.clamp(0, newHeight - 1);

    // 2. Adjust the width.
    if (newWidth != oldWidth) {
      if (terminal.reflowEnabled && !isAltBuffer) {
        final cursorScrollBack = max(lines.length - newHeight, 0);
        final cursorLine = _cursorY + cursorScrollBack;
        final cursorAnchor = lines[cursorLine].createAnchor(_cursorX);
        final reflowResult = reflow(lines, oldWidth, newWidth);

        while (reflowResult.length < newHeight) {
          reflowResult.add(_newEmptyLine(newWidth));
        }

        lines.replaceWith(reflowResult);
        if (cursorAnchor.attached) {
          final newScrollBack = max(lines.length - newHeight, 0);
          _cursorX = cursorAnchor.x.clamp(0, newWidth - 1);
          _cursorY = (cursorAnchor.y - newScrollBack).clamp(0, newHeight - 1);
        }
        cursorAnchor.dispose();
      } else {
        lines.forEach((item) => item.resize(newWidth));
        _cursorX = _cursorX.clamp(0, newWidth - 1);
      }
    }

    _cursorX = _cursorX.clamp(0, newWidth - 1);
    _marginLeft = 0;
    _marginRight = newWidth - 1;
  }

  /// Create a new [CellAnchor] at the specified [x] and [y] coordinates.
  CellAnchor createAnchor(int x, int y) {
    return lines[y].createAnchor(x);
  }

  /// Create a new [CellAnchor] at the specified [x] and [y] coordinates.
  CellAnchor createAnchorFromOffset(CellOffset offset) {
    return lines[offset.y].createAnchor(offset.x);
  }

  CellAnchor createAnchorFromCursor() {
    return createAnchor(cursorX, absoluteCursorY);
  }

  /// Create a new empty [BufferLine] with the current [viewWidth] if [width]
  /// is not specified.
  BufferLine _newEmptyLine([int? width]) {
    final line = BufferLine(width ?? viewWidth);
    return line;
  }

  static final defaultWordSeparators = <int>{
    0,
    r' '.codeUnitAt(0),
    r'.'.codeUnitAt(0),
    r':'.codeUnitAt(0),
    r'-'.codeUnitAt(0),
    r'\'.codeUnitAt(0),
    r'"'.codeUnitAt(0),
    r'*'.codeUnitAt(0),
    r'+'.codeUnitAt(0),
    r'/'.codeUnitAt(0),
    r'\'.codeUnitAt(0),
  };

  BufferRangeLine? getWordBoundary(CellOffset position) {
    var separators = wordSeparators ?? defaultWordSeparators;
    if (position.y >= lines.length) {
      return null;
    }

    var startLine = position.y;
    var start = position.x;
    var endLine = position.y;
    var end = position.x;

    do {
      if (start == 0) {
        if (!_lineContinuesFromPrevious(startLine)) break;
        startLine--;
        start = viewWidth;
      }
      final line = lines[startLine];
      var previous = start - 1;
      if (previous > 0 &&
          line.getWidth(previous) == 0 &&
          line.getWidth(previous - 1) == 2) {
        previous--;
      }
      final char = line.getCodePoint(previous);
      if (separators.contains(char)) {
        break;
      }
      start = previous;
    } while (true);

    do {
      if (end >= viewWidth) {
        if (!_lineContinuesToNext(endLine)) break;
        endLine++;
        end = 0;
      }
      final line = lines[endLine];
      final width = line.getWidth(end);
      if (width == 0 && end > 0 && line.getWidth(end - 1) == 2) {
        end++;
        continue;
      }
      final char = line.getCodePoint(end);
      if (separators.contains(char)) {
        break;
      }
      end += switch (width) {
        2 => 2,
        _ => 1,
      };
    } while (true);

    if (start == end && startLine == endLine) {
      return null;
    }

    return BufferRangeLine(
      CellOffset(start, startLine),
      CellOffset(end, endLine),
    );
  }

  bool _lineContinuesFromPrevious(int lineIndex) {
    return lineIndex > 0 && lines[lineIndex].isWrapped;
  }

  bool _lineContinuesToNext(int lineIndex) {
    final nextLine = lineIndex + 1;
    return nextLine < lines.length && lines[nextLine].isWrapped;
  }

  /// Get the plain text content of the buffer including the scrollback.
  /// Accepts an optional [range] to get a specific part of the buffer.
  String getText([BufferRange? range]) {
    range ??= BufferRangeLine(
      CellOffset(0, 0),
      CellOffset(viewWidth, height - 1),
    );

    range = range.normalized;

    final builder = StringBuffer();

    for (var segment in range.toSegments()) {
      if (segment.line < 0 || segment.line >= height) {
        continue;
      }
      final line = lines[segment.line];
      final joinWrappedLine = range is! BufferRangeBlock && line.isWrapped;
      if (!(segment.line == range.begin.y ||
          segment.line == 0 ||
          joinWrappedLine)) {
        builder.write("\n");
      }
      builder.write(line.getText(segment.start, segment.end));
    }

    return builder.toString();
  }

  /// Returns a debug representation of the buffer.
  @override
  String toString() {
    final builder = StringBuffer();
    final lineNumberLength = lines.length.toString().length;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      builder.write('${i.toString().padLeft(lineNumberLength)}: |${lines[i]}|');

      if (line.isWrapped) {
        builder.write(' (⏎)');
      }

      builder.write('\n');
    }

    return builder.toString();
  }
}

enum _CursorLeftWrapMode {
  none,
  reverse,
  reverseExtended,
}
