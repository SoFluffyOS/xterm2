import 'dart:async';
import 'dart:math' show max, min;
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/range.dart';
import 'package:xterm/src/core/buffer/segment.dart';
import 'package:xterm/src/core/cell.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/core/mouse/modifiers.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/cursor_type.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/src/ui/selection_mode.dart';
import 'package:xterm/src/ui/terminal_size.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/terminal_theme.dart';

typedef EditableRectCallback = void Function(Rect rect, Rect caretRect);

class RenderTerminal extends RenderBox with RelayoutWhenSystemFontsChangeMixin {
  RenderTerminal({
    required Terminal terminal,
    required TerminalController controller,
    required ViewportOffset offset,
    required EdgeInsets padding,
    required bool autoResize,
    required double backgroundOpacity,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
    required TerminalTheme theme,
    required FocusNode focusNode,
    required TerminalCursorType cursorType,
    required bool alwaysShowCursor,
    int? activeHyperlinkId,
    EditableRectCallback? onEditableRect,
    String? composingText,
  })  : _terminal = terminal,
        _controller = controller,
        _offset = offset,
        _padding = padding,
        _autoResize = autoResize,
        _backgroundOpacity = backgroundOpacity,
        _focusNode = focusNode,
        _cursorType = cursorType,
        _alwaysShowCursor = alwaysShowCursor,
        _activeHyperlinkId = activeHyperlinkId,
        _onEditableRect = onEditableRect,
        _composingText = composingText,
        _painter = TerminalPainter(
          theme: theme,
          textStyle: textStyle,
          textScaler: textScaler,
        );

  Terminal _terminal;
  set terminal(Terminal terminal) {
    if (_terminal == terminal) return;
    if (attached) _terminal.removeListener(_onTerminalChange);
    _terminal = terminal;
    _recordTerminalLayoutState();
    if (attached) _terminal.addListener(_onTerminalChange);
    _resizeTerminalIfNeeded();
    markNeedsLayout();
  }

  TerminalController _controller;
  set controller(TerminalController controller) {
    if (_controller == controller) return;
    if (attached) _controller.removeListener(_onControllerUpdate);
    _controller = controller;
    if (attached) _controller.addListener(_onControllerUpdate);
    markNeedsLayout();
  }

  ViewportOffset _offset;
  set offset(ViewportOffset value) {
    if (value == _offset) return;
    if (attached) _offset.removeListener(_onScroll);
    _offset = value;
    if (attached) _offset.addListener(_onScroll);
    markNeedsLayout();
  }

  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  bool _autoResize;
  set autoResize(bool value) {
    if (value == _autoResize) return;
    _autoResize = value;
    markNeedsLayout();
  }

  double _backgroundOpacity;
  set backgroundOpacity(double value) {
    if (value == _backgroundOpacity) return;
    _backgroundOpacity = value;
    markNeedsPaint();
  }

  set textStyle(TerminalStyle value) {
    if (value == _painter.textStyle) return;
    _painter.textStyle = value;
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    if (value == _painter.textScaler) return;
    _painter.textScaler = value;
    markNeedsLayout();
  }

  set theme(TerminalTheme value) {
    if (value == _painter.theme) return;
    _painter.theme = value;
    markNeedsPaint();
  }

  FocusNode _focusNode;
  set focusNode(FocusNode value) {
    if (value == _focusNode) return;
    if (attached) _focusNode.removeListener(_onFocusChange);
    _focusNode = value;
    if (attached) _focusNode.addListener(_onFocusChange);
    markNeedsPaint();
  }

  TerminalCursorType _cursorType;
  set cursorType(TerminalCursorType value) {
    if (value == _cursorType) return;
    _cursorType = value;
    markNeedsPaint();
  }

  bool _alwaysShowCursor;
  set alwaysShowCursor(bool value) {
    if (value == _alwaysShowCursor) return;
    _alwaysShowCursor = value;
    markNeedsPaint();
  }

  int? get activeHyperlinkId => _activeHyperlinkId;
  int? _activeHyperlinkId;
  set activeHyperlinkId(int? value) {
    if (value == _activeHyperlinkId) return;
    _activeHyperlinkId = value;
    markNeedsPaint();
  }

  EditableRectCallback? _onEditableRect;
  set onEditableRect(EditableRectCallback? value) {
    if (value == _onEditableRect) return;
    _onEditableRect = value;
    markNeedsLayout();
  }

  String? _composingText;
  set composingText(String? value) {
    if (value == _composingText) return;
    _composingText = value;
    markNeedsPaint();
  }

  TerminalSize? _viewportSize;

  final TerminalPainter _painter;

  var _stickToBottom = true;

  Timer? _cursorBlinkTimer;

  Timer? _cursorBlinkTimeout;

  Timer? _textBlinkTimer;

  bool _cursorBlinkVisible = true;

  bool _cursorBlinkWasEnabled = false;

  bool _textBlinkVisible = true;

  bool get isCursorBlinkVisible => _cursorBlinkVisible;

  Color? debugBackgroundFillColor() {
    _updatePainterColorState();
    final backgroundOverride = _painter.backgroundColorOverride;
    if (backgroundOverride == null) return null;
    return backgroundOverride.withValues(alpha: _backgroundOpacity);
  }

  var _lastTerminalLineCount = 0;

  var _lastTerminalWidth = 0;

  var _lastTerminalHeight = 0;

  void _onScroll() {
    _stickToBottom = _scrollOffset >= _maxScrollExtent;
    markNeedsLayout();
    _notifyEditableRect();
  }

  void _onFocusChange() {
    _updateCursorBlinking(force: true);
    markNeedsPaint();
  }

  void _onTerminalChange() {
    _updateCursorBlinking();
    final needsLayout =
        _terminal.buffer.lines.length != _lastTerminalLineCount ||
            _terminal.viewWidth != _lastTerminalWidth ||
            _terminal.viewHeight != _lastTerminalHeight;
    _recordTerminalLayoutState();
    if (needsLayout) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
    _notifyEditableRect();
  }

  void _recordTerminalLayoutState() {
    _lastTerminalLineCount = _terminal.buffer.lines.length;
    _lastTerminalWidth = _terminal.viewWidth;
    _lastTerminalHeight = _terminal.viewHeight;
  }

  void _onControllerUpdate() {
    markNeedsLayout();
  }

  @override
  final isRepaintBoundary = true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _recordTerminalLayoutState();
    _offset.addListener(_onScroll);
    _terminal.addListener(_onTerminalChange);
    _controller.addListener(_onControllerUpdate);
    _focusNode.addListener(_onFocusChange);
    _updateCursorBlinking(force: true);
  }

  @override
  void detach() {
    _stopCursorBlinking();
    _stopTextBlinking();
    _offset.removeListener(_onScroll);
    _terminal.removeListener(_onTerminalChange);
    _controller.removeListener(_onControllerUpdate);
    _focusNode.removeListener(_onFocusChange);
    super.detach();
  }

  @override
  void dispose() {
    _stopCursorBlinking();
    _stopTextBlinking();
    _painter.dispose();
    super.dispose();
  }

  void _updateCursorBlinking({bool force = false}) {
    final enabled = _terminal.cursorBlinkMode && _focusNode.hasFocus;
    final blinkTimerActive = _cursorBlinkTimer != null;
    if (!force &&
        enabled == _cursorBlinkWasEnabled &&
        (!enabled || blinkTimerActive)) {
      return;
    }

    _stopCursorBlinking();
    _cursorBlinkWasEnabled = enabled;
    _cursorBlinkVisible = true;
    if (!enabled || !attached) return;

    _cursorBlinkTimer = Timer.periodic(
      const Duration(milliseconds: 750),
      (_) {
        _cursorBlinkVisible = !_cursorBlinkVisible;
        markNeedsPaint();
      },
    );
    _cursorBlinkTimeout = Timer(const Duration(seconds: 5), () {
      _cursorBlinkTimer?.cancel();
      _cursorBlinkTimer = null;
      _cursorBlinkVisible = true;
      markNeedsPaint();
    });
  }

  void _stopCursorBlinking() {
    _cursorBlinkTimer?.cancel();
    _cursorBlinkTimeout?.cancel();
    _cursorBlinkTimer = null;
    _cursorBlinkTimeout = null;
    _cursorBlinkVisible = true;
  }

  void _updateTextBlinking(bool enabled) {
    if (!enabled) {
      _stopTextBlinking();
      return;
    }
    if (_textBlinkTimer != null || !attached) return;

    _textBlinkTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        _textBlinkVisible = !_textBlinkVisible;
        markNeedsPaint();
      },
    );
  }

  void _stopTextBlinking() {
    _textBlinkTimer?.cancel();
    _textBlinkTimer = null;
    _textBlinkVisible = true;
  }

  @override
  bool hitTestSelf(Offset position) {
    return true;
  }

  @override
  void systemFontsDidChange() {
    _painter.clearFontCache();
    super.systemFontsDidChange();
  }

  @override
  void performLayout() {
    size = constraints.biggest;

    _updateViewportSize();
    _recordTerminalLayoutState();

    _updateScrollOffset();

    if (_stickToBottom) {
      _offset.correctBy(_maxScrollExtent - _scrollOffset);
    }
  }

  /// Total height of the terminal in pixels. Includes scrollback buffer.
  double get _terminalHeight =>
      _terminal.buffer.lines.length * _painter.cellSize.height;

  /// The distance from the top of the terminal to the top of the viewport.
  // double get _scrollOffset => _offset.pixels;
  double get _scrollOffset {
    // return _offset.pixels ~/ _painter.cellSize.height * _painter.cellSize.height;
    return _offset.pixels;
  }

  /// The height of a terminal line in pixels. This includes the line spacing.
  /// Height of the entire terminal is expected to be a multiple of this value.
  double get lineHeight => _painter.cellSize.height;

  /// Get the top-left corner of the cell at [cellOffset] in pixels.
  Offset getOffset(CellOffset cellOffset) {
    final row = cellOffset.y;
    final col = cellOffset.x;
    final x = col * _painter.cellSize.width;
    final y = row * _painter.cellSize.height;
    return Offset(x + _padding.left, y + _padding.top - _scrollOffset);
  }

  /// Get the [CellOffset] of the cell that [offset] is in.
  CellOffset getCellOffset(Offset offset) {
    final x = offset.dx - _padding.left;
    final y = offset.dy - _padding.top + _scrollOffset;
    final row = y ~/ _painter.cellSize.height;
    final col = x ~/ _painter.cellSize.width;
    return CellOffset(
      col.clamp(0, _terminal.viewWidth - 1),
      row.clamp(0, _terminal.buffer.lines.length - 1),
    );
  }

  /// Selects entire words in the terminal that contains [from] and [to].
  void selectWord(Offset from, [Offset? to]) {
    final fromOffset = getCellOffset(from);
    final fromBoundary = _terminal.buffer.getWordBoundary(fromOffset);
    if (fromBoundary == null) return;
    if (to == null) {
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(fromBoundary.begin),
        _terminal.buffer.createAnchorFromOffset(fromBoundary.end),
        mode: SelectionMode.line,
      );
    } else {
      final toOffset = getCellOffset(to);
      final toBoundary = _terminal.buffer.getWordBoundary(toOffset);
      if (toBoundary == null) return;
      final range = fromBoundary.merge(toBoundary);
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(range.begin),
        _terminal.buffer.createAnchorFromOffset(range.end),
        mode: SelectionMode.line,
      );
    }
  }

  /// Selects characters in the terminal that starts from [from] to [to]. At
  /// least one cell is selected even if [from] and [to] are same.
  void selectCharacters(Offset from, [Offset? to]) {
    final fromPosition = getCellOffset(from);
    final fromStart = _cellSelectionStart(fromPosition);
    final fromEnd = _cellSelectionEnd(fromPosition);
    if (to == null) {
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(fromStart),
        _terminal.buffer.createAnchorFromOffset(fromEnd),
      );
    } else {
      final toPosition = getCellOffset(to);
      if (toPosition.isAfterOrSame(fromPosition)) {
        _controller.setSelection(
          _terminal.buffer.createAnchorFromOffset(fromStart),
          _terminal.buffer.createAnchorFromOffset(
            _cellSelectionEnd(toPosition),
          ),
        );
        return;
      }
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(fromEnd),
        _terminal.buffer.createAnchorFromOffset(
          _cellSelectionStart(toPosition),
        ),
      );
    }
  }

  CellOffset _cellSelectionStart(CellOffset position) {
    final line = _terminal.buffer.lines[position.y];
    if (position.x > 0 &&
        line.getWidth(position.x) == 0 &&
        line.getWidth(position.x - 1) == 2) {
      return CellOffset(position.x - 1, position.y);
    }
    return position;
  }

  CellOffset _cellSelectionEnd(CellOffset position) {
    final start = _cellSelectionStart(position);
    final line = _terminal.buffer.lines[start.y];
    final width = switch (line.getWidth(start.x)) {
      2 => 2,
      _ => 1,
    };
    return CellOffset(
      min(start.x + width, _terminal.viewWidth),
      start.y,
    );
  }

  /// Send a mouse event at [offset] with [button] being currently in [buttonState].
  bool mouseEvent(
    TerminalMouseButton button,
    TerminalMouseButtonState buttonState,
    Offset offset, {
    bool motion = false,
    TerminalMouseModifiers modifiers = TerminalMouseModifiers.none,
  }) {
    final position = getCellOffset(offset);
    return _terminal.mouseInput(
      button,
      buttonState,
      position,
      motion: motion,
      modifiers: modifiers,
      pixelPosition: CellOffset(offset.dx.floor(), offset.dy.floor()),
    );
  }

  void _notifyEditableRect() {
    final onEditableRect = _onEditableRect;
    if (onEditableRect == null) return;

    final cursor = localToGlobal(cursorOffset);

    final rect = Rect.fromLTRB(
      cursor.dx,
      cursor.dy,
      size.width,
      cursor.dy + _painter.cellSize.height,
    );

    final caretRect = cursor & cursorSize;

    onEditableRect(rect, caretRect);
  }

  /// Update the viewport size in cells based on the current widget size in
  /// pixels.
  void _updateViewportSize() {
    final viewportWidth = size.width - _padding.horizontal;
    final viewportHeight = _viewportHeight;
    if (viewportWidth < _painter.cellSize.width ||
        viewportHeight < _painter.cellSize.height) {
      return;
    }

    final viewportSize = TerminalSize(
      viewportWidth ~/ _painter.cellSize.width,
      viewportHeight ~/ _painter.cellSize.height,
    );

    if (_viewportSize != viewportSize) {
      _viewportSize = viewportSize;
      _resizeTerminalIfNeeded();
    }
  }

  /// Notify the underlying terminal that the viewport size has changed.
  void _resizeTerminalIfNeeded() {
    if (!_autoResize) {
      return;
    }
    if (_viewportSize case final viewportSize?) {
      _terminal.resize(
        viewportSize.width,
        viewportSize.height,
        _painter.cellSize.width.round(),
        _painter.cellSize.height.round(),
      );
    }
  }

  /// Update the scroll offset based on the current terminal state. This should
  /// be called in [performLayout] after the viewport size has been updated.
  void _updateScrollOffset() {
    _offset.applyViewportDimension(_viewportHeight);
    _offset.applyContentDimensions(0, _maxScrollExtent);
  }

  bool get _isComposingText {
    if (_composingText case final composingText?) {
      return composingText.isNotEmpty;
    }
    return false;
  }

  bool get _shouldShowCursor {
    if (_alwaysShowCursor || _isComposingText) return true;
    if (!_terminal.cursorVisibleMode) return false;
    if (!_terminal.cursorBlinkMode || !_focusNode.hasFocus) return true;
    return _cursorBlinkVisible;
  }

  double get _viewportHeight {
    return max(size.height - _padding.vertical, 0);
  }

  double get _maxScrollExtent {
    return max(_terminalHeight - _viewportHeight, 0.0);
  }

  double get _lineOffset {
    return -_scrollOffset + _padding.top;
  }

  /// The offset of the cursor from the top left corner of this render object.
  Offset get cursorOffset {
    final cursorColumn = _cursorRenderColumn();
    return Offset(
      _padding.left + cursorColumn * _painter.cellSize.width,
      _terminal.buffer.absoluteCursorY * _painter.cellSize.height + _lineOffset,
    );
  }

  Size get cellSize {
    return _painter.cellSize;
  }

  Size get cursorSize {
    final cursorWidth = _cursorRenderWidth(_cursorRenderColumn());
    return Size(
      _painter.cellSize.width * cursorWidth,
      _painter.cellSize.height,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas.save();
    canvas.clipRect(offset & size);
    _paint(context, offset);
    canvas.restore();
    context.setWillChangeHint();
  }

  void _paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    _updatePainterColorState();

    final backgroundOverride = _painter.backgroundColorOverride;
    if (backgroundOverride != null) {
      final paint = Paint()
        ..color = backgroundOverride.withValues(alpha: _backgroundOpacity);
      canvas.drawRect(offset & size, paint);
    }

    if (_terminal.reverseDisplayMode) {
      final paint = Paint()
        ..color =
            _painter.foregroundColor.withValues(alpha: _backgroundOpacity);
      canvas.drawRect(offset & size, paint);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(
      offset.dx + _padding.left,
      offset.dy + _padding.top,
      max(size.width - _padding.horizontal, 0),
      _viewportHeight,
    ));

    final lines = _terminal.buffer.lines;
    final charHeight = _painter.cellSize.height;

    final firstLineOffset = _scrollOffset;
    final lastLineOffset = _scrollOffset + _viewportHeight;

    final (effectFirstLine, effectLastLine) = _visibleLineRange(
      lines.length,
      firstLineOffset,
      lastLineOffset,
      charHeight,
    );

    for (var i = effectFirstLine; i <= effectLastLine; i++) {
      _painter.paintLineBackgrounds(
        canvas,
        offset.translate(
          _padding.left,
          (i * charHeight + _lineOffset).truncateToDouble(),
        ),
        lines[i],
      );
    }

    _paintHighlights(
      canvas,
      offset,
      _controller.highlights,
      effectFirstLine,
      effectLastLine,
    );

    final selection = _controller.selection;
    if (selection != null) {
      _paintSelection(
        canvas,
        offset,
        selection,
        effectFirstLine,
        effectLastLine,
      );
    }

    final cursorType = _terminal.applicationCursorType ?? _cursorType;
    final shouldPaintCursor =
        _terminal.buffer.absoluteCursorY >= effectFirstLine &&
            _terminal.buffer.absoluteCursorY <= effectLastLine &&
            _shouldShowCursor;
    final shouldPaintBlockCursor =
        shouldPaintCursor && cursorType == TerminalCursorType.block;
    final cursorRenderColumn = _cursorRenderColumn();
    final cursorRenderWidth = _cursorRenderWidth(cursorRenderColumn);
    final cursorColors = _cursorColors(cursorRenderColumn);
    final cursorForeground =
        switch (shouldPaintBlockCursor && _focusNode.hasFocus) {
      true => cursorColors.foreground,
      false => _painter.backgroundColor,
    };

    if (shouldPaintBlockCursor && _focusNode.hasFocus) {
      _painter.paintCursor(
        canvas,
        offset + _cursorRenderOffset(cursorRenderColumn),
        cursorType: cursorType,
        cellWidth: cursorRenderWidth,
        color: cursorColors.background,
      );
    }

    var hasBlinkingText = false;
    for (var i = effectFirstLine; i <= effectLastLine; i++) {
      hasBlinkingText = _painter.paintLineForegrounds(
            canvas,
            offset.translate(
              _padding.left,
              (i * charHeight + _lineOffset).truncateToDouble(),
            ),
            lines[i],
            blinkVisible: _textBlinkVisible,
            activeHyperlinkId: _activeHyperlinkId,
            cursorColumn: switch (shouldPaintBlockCursor &&
                _focusNode.hasFocus &&
                i == _terminal.buffer.absoluteCursorY) {
              true => cursorRenderColumn,
              false => null,
            },
            cursorForeground: cursorForeground,
          ) ||
          hasBlinkingText;
    }
    _updateTextBlinking(hasBlinkingText);

    _paintUnderlines(
      canvas,
      offset,
      _controller.underlines,
      effectFirstLine,
      effectLastLine,
    );

    if (shouldPaintCursor) {
      if (_isComposingText) {
        _paintComposingText(canvas, offset + cursorOffset);
      }

      if (!shouldPaintBlockCursor || !_focusNode.hasFocus) {
        _painter.paintCursor(
          canvas,
          offset + _cursorRenderOffset(cursorRenderColumn),
          cursorType: cursorType,
          hasFocus: _focusNode.hasFocus,
          cellWidth: cursorRenderWidth,
          color: cursorColors.background,
        );
      }
    }
    canvas.restore();
  }

  void _updatePainterColorState() {
    _painter.updateColorOverrides(
      _terminal,
      _terminal.colorRevision,
      _terminal.indexedColorOverrides,
      _terminal.foregroundColorOverride,
      _terminal.backgroundColorOverride,
      _terminal.cursorColorOverride,
    );
    _painter.reverseDisplay = _terminal.reverseDisplayMode;
  }

  @visibleForTesting
  (int, int) debugVisibleLineRange() {
    return _visibleLineRange(
      _terminal.buffer.lines.length,
      _scrollOffset,
      _scrollOffset + _viewportHeight,
      _painter.cellSize.height,
    );
  }

  (int, int) _visibleLineRange(
    int lineCount,
    double firstLineOffset,
    double lastLineOffset,
    double charHeight,
  ) {
    if (lineCount <= 0) return (0, -1);
    final firstLine = firstLineOffset ~/ charHeight;
    final hasVisibleHeight = lastLineOffset > firstLineOffset;
    final lastLine = switch (hasVisibleHeight) {
      true => ((lastLineOffset - 0.000001) ~/ charHeight),
      false => firstLine,
    };
    return (
      firstLine.clamp(0, lineCount - 1),
      lastLine.clamp(0, lineCount - 1),
    );
  }

  int _cursorRenderColumn() {
    final line = _terminal.buffer.lines[_terminal.buffer.absoluteCursorY];
    final cursorX = _terminal.buffer.cursorX;
    final cellData = CellData.empty();
    line.getCellData(cursorX, cellData);

    final charWidth = cellData.content >> CellContent.widthShift;
    if (charWidth != 0 || cursorX == 0) {
      return cursorX;
    }

    line.getCellData(cursorX - 1, cellData);
    final previousCharWidth = cellData.content >> CellContent.widthShift;
    if (previousCharWidth == 2) {
      return cursorX - 1;
    }

    return cursorX;
  }

  int _cursorRenderWidth(int cursorColumn) {
    final line = _terminal.buffer.lines[_terminal.buffer.absoluteCursorY];
    final cellData = CellData.empty();
    line.getCellData(cursorColumn, cellData);

    final charWidth = cellData.content >> CellContent.widthShift;
    if (charWidth == 2) {
      return 2;
    }

    return 1;
  }

  ({Color background, Color foreground}) _cursorColors(int cursorColumn) {
    final line = _terminal.buffer.lines[_terminal.buffer.absoluteCursorY];
    final cellData = CellData.empty();
    line.getCellData(cursorColumn, cellData);
    return _painter.resolveCursorColors(cellData);
  }

  Offset _cursorRenderOffset(int cursorColumn) {
    return Offset(
      _padding.left + cursorColumn * _painter.cellSize.width,
      _terminal.buffer.absoluteCursorY * _painter.cellSize.height + _lineOffset,
    );
  }

  /// Paints the text that is currently being composed in IME to [canvas] at
  /// [offset]. [offset] is usually the cursor position.
  void _paintComposingText(Canvas canvas, Offset offset) {
    final composingText = _composingText;
    if (composingText == null) {
      return;
    }

    final style = _painter.textStyle.toTextStyle(
      color: switch (_terminal.reverseDisplayMode) {
        true => _painter.resolveBackgroundColor(_terminal.cursor.background),
        false => _painter.resolveForegroundColor(_terminal.cursor.foreground),
      },
      backgroundColor: switch (_terminal.reverseDisplayMode) {
        true => _painter.foregroundColor,
        false => _painter.backgroundColor,
      },
      underline: true,
    );

    final builder = ParagraphBuilder(style.getParagraphStyle());
    builder.addPlaceholder(
      offset.dx,
      _painter.cellSize.height,
      PlaceholderAlignment.middle,
    );
    builder.pushStyle(
      style.getTextStyle(textScaler: _painter.textScaler),
    );
    builder.addText(composingText);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: size.width));

    canvas.drawParagraph(paragraph, Offset(0, offset.dy));
    paragraph.dispose();
  }

  void _paintSelection(
    Canvas canvas,
    Offset offset,
    BufferRange selection,
    int firstLine,
    int lastLine,
  ) {
    for (final segment in selection.toSegments()) {
      if (segment.line >= _terminal.buffer.lines.length) {
        break;
      }

      if (segment.line < firstLine) {
        continue;
      }

      if (segment.line > lastLine) {
        break;
      }

      _paintSegment(canvas, offset, segment, _painter.theme.selection);
    }
  }

  void _paintHighlights(
    Canvas canvas,
    Offset offset,
    List<TerminalHighlight> highlights,
    int firstLine,
    int lastLine,
  ) {
    for (var highlight in _controller.highlights) {
      final range = highlight.range?.normalized;

      if (range == null ||
          range.begin.y > lastLine ||
          range.end.y < firstLine) {
        continue;
      }

      for (var segment in range.toSegments()) {
        if (segment.line < firstLine) {
          continue;
        }

        if (segment.line > lastLine) {
          break;
        }

        _paintSegment(canvas, offset, segment, highlight.color);
      }
    }
  }

  void _paintUnderlines(
    Canvas canvas,
    Offset offset,
    List<TerminalUnderline> underlines,
    int firstLine,
    int lastLine,
  ) {
    for (final underline in underlines) {
      final range = underline.range?.normalized;

      if (range == null ||
          range.begin.y > lastLine ||
          range.end.y < firstLine) {
        continue;
      }

      for (final segment in range.toSegments()) {
        if (segment.line < firstLine) {
          continue;
        }

        if (segment.line > lastLine) {
          break;
        }

        _paintUnderline(canvas, offset, segment, underline.color);
      }
    }
  }

  @pragma('vm:prefer-inline')
  void _paintUnderline(
    Canvas canvas,
    Offset offset,
    BufferSegment segment,
    Color color,
  ) {
    final start = segment.start ?? 0;
    final end = segment.end ?? _terminal.viewWidth;
    final startOffset = getSegmentOffset(segment, offset);
    final y = startOffset.dy + _painter.cellSize.height - 1;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(startOffset.dx, y),
      Offset(startOffset.dx + (end - start) * _painter.cellSize.width, y),
      paint,
    );
  }

  @pragma('vm:prefer-inline')
  void _paintSegment(
    Canvas canvas,
    Offset offset,
    BufferSegment segment,
    Color color,
  ) {
    final start = segment.start ?? 0;
    final end = segment.end ?? _terminal.viewWidth;

    final startOffset = getSegmentOffset(segment, offset);

    _painter.paintHighlight(canvas, startOffset, end - start, color);
  }

  Offset getSegmentOffset(BufferSegment segment, Offset paintOffset) {
    final start = segment.start ?? 0;
    return paintOffset +
        Offset(
          _padding.left + start * _painter.cellSize.width,
          segment.line * _painter.cellSize.height + _lineOffset,
        );
  }
}
