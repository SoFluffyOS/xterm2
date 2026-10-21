part of 'buffer.dart';

extension _BufferResize on Buffer {
  void _resizeViewport(
      int oldWidth, int oldHeight, int newWidth, int newHeight) {
    if (newHeight > lines.maxLength) {
      lines.maxLength = newHeight;
    }

    final clearApplication = !isAltBuffer &&
        !terminal.cursorVisibleMode &&
        !terminal.reflowWithHiddenCursor;
    final reflowMain =
        terminal.reflowEnabled && !isAltBuffer && !clearApplication;
    // Only the live application redraws discarded cells; restored history does not.
    if (newHeight > oldHeight && clearApplication && scrollBack > 0) {
      lines.trimStart(min(newHeight - oldHeight, scrollBack));
    }
    // 1. Adjust the height.
    if (newHeight > oldHeight) {
      // Grow larger
      for (var i = 0; i < newHeight - oldHeight; i++) {
        if (newHeight > lines.length) {
          lines.push(_newEmptyLine(newWidth));
        } else {
          _cursorY++;
          if (reflowMain) _savedCursorY++;
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
    if (reflowMain) _savedCursorY = _savedCursorY.clamp(0, newHeight - 1);

    // 2. Adjust the width.
    if (newWidth != oldWidth) {
      if (reflowMain) {
        final cursorScrollBack = max(lines.length - newHeight, 0);
        final cursorLine = _cursorY + cursorScrollBack;
        final cursorPendingWrap = _cursorX >= _rightLimit;
        final cursorAnchorX = switch (cursorPendingWrap) {
          true => max(0, _cursorX - 1),
          false => _cursorX,
        };
        final cursorAnchor = lines[cursorLine].createAnchor(cursorAnchorX);
        final savedCursorLine = _savedCursorY + cursorScrollBack;
        final savedCursorAnchorX = switch (_savedPendingWrap) {
          true => max(0, _savedCursorX - 1),
          false => _savedCursorX,
        };
        final savedCursorAnchor =
            lines[savedCursorLine].createAnchor(savedCursorAnchorX);
        final reflowResult = reflow(lines, oldWidth, newWidth);

        while (reflowResult.length < newHeight) {
          reflowResult.add(_newEmptyLine(newWidth));
        }

        lines.replaceWith(reflowResult);
        if (cursorAnchor.attached) {
          final newScrollBack = max(lines.length - newHeight, 0);
          _cursorX = _reflowedCursorX(
            cursorAnchor,
            pendingWrap: cursorPendingWrap,
            newWidth: newWidth,
          );
          _cursorY = (cursorAnchor.y - newScrollBack).clamp(0, newHeight - 1);
        }
        if (savedCursorAnchor.attached) {
          final newScrollBack = max(lines.length - newHeight, 0);
          final savedCursorAtRightEdge = savedCursorAnchor.x == newWidth - 1;
          _savedCursorX = _reflowedCursorX(
            savedCursorAnchor,
            pendingWrap: _savedPendingWrap,
            newWidth: newWidth,
          );
          _savedCursorY =
              (savedCursorAnchor.y - newScrollBack).clamp(0, newHeight - 1);
          _savedPendingWrap = _savedPendingWrap && savedCursorAtRightEdge;
        } else {
          _savedCursorX = _savedCursorX.clamp(0, newWidth - 1);
          _savedPendingWrap = false;
        }
        cursorAnchor.dispose();
        savedCursorAnchor.dispose();
      } else {
        lines.forEach((item) => item.resize(newWidth,
            clearNewCells: isAltBuffer || clearApplication));
        _cursorX = _cursorX.clamp(0, newWidth - 1);
      }
    }

    for (var i = 0; i < lines.length; i++) {
      if (i < lines.length - newHeight) {
        lines[i].compact();
      } else if (lines[i].length < newWidth) {
        lines[i].resize(newWidth);
      }
    }
    _cursorX = _cursorX.clamp(0, newWidth);
    _marginLeft = 0;
    _marginRight = newWidth - 1;
  }

  int _reflowedCursorX(
    CellAnchor anchor, {
    required bool pendingWrap,
    required int newWidth,
  }) {
    if (pendingWrap && anchor.x == newWidth - 1) return newWidth;
    final offset = switch (pendingWrap) {
      true => 1,
      false => 0,
    };
    return (anchor.x + offset).clamp(0, newWidth - 1);
  }
}
