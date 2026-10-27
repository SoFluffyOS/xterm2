import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:xterm2_core/xterm2_core.dart';
import 'package:xterm2/src/ui/controller.dart';

/// Paints application-owned content in a terminal's cell coordinate system.
typedef TerminalPaintCallback = void Function(TerminalPaintContext context);

/// Whether a cell's foreground (including decorations) should be painted.
///
/// Backgrounds, selection and cursor geometry are unaffected. The predicate may
/// run again for selection/search recoloring and must not mutate the buffer.
typedef TerminalCellForegroundFilter = bool Function(
    BufferLine line, int column);

/// Optional application painting and cell foreground filtering for a terminal.
///
/// Callbacks run synchronously during paint, clipped to the content viewport.
/// Each callback has isolated canvas state. Balance any canvas saves/restores,
/// and do not retain the canvas or mutate terminal/controller state during paint.
/// The caller owns [repaint] and any graphics resources.
class TerminalPaintExtension {
  const TerminalPaintExtension({
    this.beforeCellBackgrounds,
    this.beforeCellForegrounds,
    this.afterCellForegrounds,
    this.cellForegroundFilter,
    this.repaint,
  });

  /// Runs after the terminal's base fill, before cell backgrounds.
  final TerminalPaintCallback? beforeCellBackgrounds;

  /// Runs after cell backgrounds, before selection, search and cursor overlays.
  final TerminalPaintCallback? beforeCellForegrounds;

  /// Runs after text, selection/search recoloring and controller underlines,
  /// before composing text and non-block cursors. A focused block cursor is
  /// painted with the text and can be covered by this callback.
  final TerminalPaintCallback? afterCellForegrounds;

  final TerminalCellForegroundFilter? cellForegroundFilter;

  /// Requests a repaint when application-owned graphics change.
  final Listenable? repaint;
}

/// Geometry and terminal state for one paint frame.
///
/// Coordinates are logical pixels in [canvas]'s coordinate system, including
/// render-object paint offset, padding, scroll position and text scaling.
class TerminalPaintContext {
  @internal
  const TerminalPaintContext({
    required this.canvas,
    required this.viewport,
    required this.firstRow,
    required this.endRow,
    required this.cellSize,
    required this.terminal,
    required this.controller,
    required Offset paintOffset,
    required Offset bufferOffset,
  })  : _paintOffset = paintOffset,
        _bufferOffset = bufferOffset;

  final Canvas canvas;
  final Rect viewport;

  /// First visible buffer row, inclusive.
  final int firstRow;

  /// End of the visible buffer row interval, exclusive.
  final int endRow;

  final Size cellSize;
  final Terminal terminal;
  final TerminalController controller;
  final Offset _paintOffset;
  final Offset _bufferOffset;

  /// Top-left of a buffer cell, using the renderer's row pixel alignment.
  Offset cellOffset(int column, int row) =>
      _paintOffset +
      Offset(
        _bufferOffset.dx + column * cellSize.width,
        (_bufferOffset.dy + row * cellSize.height).truncateToDouble(),
      );
}
