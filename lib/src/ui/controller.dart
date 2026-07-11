import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:xterm2/src/base/disposable.dart';
import 'package:xterm2/src/core/buffer/cell_offset.dart';
import 'package:xterm2/src/core/buffer/line.dart';
import 'package:xterm2/src/core/buffer/range.dart';
import 'package:xterm2/src/core/buffer/range_block.dart';
import 'package:xterm2/src/core/buffer/range_line.dart';
import 'package:xterm2/src/ui/pointer_input.dart';
import 'package:xterm2/src/ui/selection_mode.dart';

class TerminalController with ChangeNotifier {
  TerminalController({
    SelectionMode selectionMode = SelectionMode.line,
    PointerInputs pointerInputs = const PointerInputs({
      PointerInput.tap,
      PointerInput.scroll,
    }),
    bool suspendPointerInput = false,
  })  : _selectionMode = selectionMode,
        _pointerInputs = pointerInputs,
        _suspendPointerInputs = suspendPointerInput;

  CellAnchor? _selectionBase;
  CellAnchor? _selectionExtent;

  SelectionMode get selectionMode => _selectionMode;
  SelectionMode _selectionMode;

  /// The set of pointer events which will be used as mouse input for the terminal.
  PointerInputs get pointerInput => _pointerInputs;
  PointerInputs _pointerInputs;

  /// True if sending pointer events to the terminal is suspended.
  bool get suspendedPointerInputs => _suspendPointerInputs;
  bool _suspendPointerInputs;

  List<TerminalHighlight> get highlights => _highlights;
  final _highlights = <TerminalHighlight>[];

  List<TerminalUnderline> get underlines => _underlines;
  final _underlines = <TerminalUnderline>[];

  BufferRange? get selection {
    final base = _selectionBase;
    final extent = _selectionExtent;

    if (base == null || extent == null) {
      return null;
    }

    if (!base.attached || !extent.attached) {
      return null;
    }

    return _createRange(base.offset, extent.offset);
  }

  /// Set selection on the terminal from [base] to [extent]. This method takes
  /// the ownership of [base] and [extent] and will dispose them when the
  /// selection is cleared or changed.
  void setSelection(CellAnchor base, CellAnchor extent, {SelectionMode? mode}) {
    _selectionBase?.dispose();
    _selectionBase = base;

    _selectionExtent?.dispose();
    _selectionExtent = extent;

    if (mode != null) {
      _selectionMode = mode;
    }

    notifyListeners();
  }

  BufferRange _createRange(CellOffset begin, CellOffset end) {
    switch (selectionMode) {
      case SelectionMode.line:
        return BufferRangeLine(begin, end);
      case SelectionMode.block:
        return BufferRangeBlock(begin, end);
    }
  }

  /// Controls how the terminal behaves when the user selects a range of text.
  /// The default is [SelectionMode.line]. Setting this to [SelectionMode.block]
  /// enables block selection mode.
  void setSelectionMode(SelectionMode newSelectionMode) {
    // If the new mode is the same as the old mode,
    // nothing has to be changed.
    if (_selectionMode == newSelectionMode) {
      return;
    }
    // Set the new mode.
    _selectionMode = newSelectionMode;
    notifyListeners();
  }

  /// Clears the current selection.
  void clearSelection() {
    _selectionBase?.dispose();
    _selectionBase = null;
    _selectionExtent?.dispose();
    _selectionExtent = null;
    notifyListeners();
  }

  // Select which type of pointer events are send to the terminal.
  void setPointerInputs(PointerInputs pointerInput) {
    _pointerInputs = pointerInput;
    notifyListeners();
  }

  // Toggle sending pointer events to the terminal.
  void setSuspendPointerInput(bool suspend) {
    _suspendPointerInputs = suspend;
    notifyListeners();
  }

  // Returns true if this type of PointerInput should be send to the Terminal.
  @internal
  bool shouldSendPointerInput(PointerInput pointerInput) {
    // Always return false if pointer input is suspended.
    return _suspendPointerInputs
        ? false
        : _pointerInputs.inputs.contains(pointerInput);
  }

  /// Creates a new highlight on the terminal from [p1] to [p2] with the given
  /// [color]. The highlight will be removed when the returned object is
  /// disposed.
  TerminalHighlight highlight({
    required CellAnchor p1,
    required CellAnchor p2,
    required Color color,
  }) {
    final highlight = TerminalHighlight(
      this,
      p1: p1,
      p2: p2,
      color: color,
    );

    _highlights.add(highlight);
    notifyListeners();

    highlight.registerCallback(() {
      _highlights.remove(highlight);
      notifyListeners();
    });

    return highlight;
  }

  /// Creates a temporary underline from [p1] to [p2] with the given [color].
  /// The underline will be removed when the returned object is disposed.
  TerminalUnderline underline({
    required CellAnchor p1,
    required CellAnchor p2,
    required Color color,
  }) {
    final underline = TerminalUnderline(
      this,
      p1: p1,
      p2: p2,
      color: color,
    );

    _underlines.add(underline);
    notifyListeners();

    underline.registerCallback(() {
      _underlines.remove(underline);
      notifyListeners();
    });

    return underline;
  }

  @override
  void dispose() {
    _selectionBase?.dispose();
    _selectionBase = null;
    _selectionExtent?.dispose();
    _selectionExtent = null;

    final highlights = List<TerminalHighlight>.of(_highlights);
    for (final highlight in highlights) {
      highlight.dispose();
    }

    final underlines = List<TerminalUnderline>.of(_underlines);
    for (final underline in underlines) {
      underline.dispose();
    }

    super.dispose();
  }
}

class TerminalHighlight with Disposable {
  final TerminalController owner;

  final CellAnchor p1;

  final CellAnchor p2;

  final Color color;

  TerminalHighlight(
    this.owner, {
    required this.p1,
    required this.p2,
    required this.color,
  }) {
    registerCallback(p1.dispose);
    registerCallback(p2.dispose);
  }

  /// Returns the range of the highlight. May be null if the anchors that
  /// define the highlight are not attached to the terminal.
  BufferRange? get range {
    if (!p1.attached || !p2.attached) {
      return null;
    }
    return BufferRangeLine(p1.offset, p2.offset);
  }
}

class TerminalUnderline with Disposable {
  final TerminalController owner;

  final CellAnchor p1;

  final CellAnchor p2;

  final Color color;

  TerminalUnderline(
    this.owner, {
    required this.p1,
    required this.p2,
    required this.color,
  }) {
    registerCallback(p1.dispose);
    registerCallback(p2.dispose);
  }

  /// Returns the range of the underline. May be null if the anchors that
  /// define the underline are not attached to the terminal.
  BufferRange? get range {
    if (!p1.attached || !p2.attached) {
      return null;
    }
    return BufferRangeLine(p1.offset, p2.offset);
  }
}
