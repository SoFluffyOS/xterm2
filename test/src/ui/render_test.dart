import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('character selection expands forward endpoint across rows', () {
    final setup = _createRenderTerminal();
    final render = setup.render;
    final cellSize = render.cellSize;

    render.selectCharacters(
      Offset(cellSize.width * 5.5, cellSize.height * 0.5),
      Offset(cellSize.width * 1.5, cellSize.height * 1.5),
    );

    final selection = setup.controller.selection;
    expect(selection?.begin, const CellOffset(5, 0));
    expect(selection?.end, const CellOffset(2, 1));

    setup.focusNode.dispose();
  });

  test('character selection preserves backward endpoint across rows', () {
    final setup = _createRenderTerminal();
    final render = setup.render;
    final cellSize = render.cellSize;

    render.selectCharacters(
      Offset(cellSize.width * 1.5, cellSize.height * 1.5),
      Offset(cellSize.width * 5.5, cellSize.height * 0.5),
    );

    final selection = setup.controller.selection;
    expect(selection?.begin, const CellOffset(1, 1));
    expect(selection?.end, const CellOffset(5, 0));

    setup.focusNode.dispose();
  });

  test('highlight segment offset includes render paint offset', () {
    final setup = _createRenderTerminal();
    final render = setup.render;
    final range = BufferRangeLine(
      const CellOffset(0, 2),
      const CellOffset(4, 2),
    );
    final segment = BufferSegment(range, 2, 3, 4);
    const paintOffset = Offset(30, 20);

    final segmentOffset = render.getSegmentOffset(segment, paintOffset);

    expect(segmentOffset.dx, paintOffset.dx + render.cellSize.width * 3);
    expect(segmentOffset.dy, paintOffset.dy + render.cellSize.height * 2);

    setup.focusNode.dispose();
  });

  test('cursor offset uses wide glyph origin when cursor is on spacer', () {
    final setup = _createRenderTerminal();
    final render = setup.render;
    final terminal = setup.terminal;

    terminal.write('好');
    terminal.buffer.setCursor(1, 0);

    expect(render.cursorOffset.dx, 0);
    expect(render.cursorSize.width, render.cellSize.width * 2);

    setup.focusNode.dispose();
  });
}

({
  RenderTerminal render,
  Terminal terminal,
  TerminalController controller,
  FocusNode focusNode,
}) _createRenderTerminal() {
  final terminal = Terminal()..resize(10, 5);
  final controller = TerminalController();
  final focusNode = FocusNode();
  final render = RenderTerminal(
    terminal: terminal,
    controller: controller,
    offset: ViewportOffset.fixed(0),
    padding: EdgeInsets.zero,
    autoResize: false,
    textStyle: const TerminalStyle(fontSize: 20, height: 1),
    textScaler: TextScaler.noScaling,
    theme: TerminalThemes.whiteOnBlack,
    focusNode: focusNode,
    cursorType: TerminalCursorType.block,
    alwaysShowCursor: false,
  );
  return (
    render: render,
    terminal: terminal,
    controller: controller,
    focusNode: focusNode,
  );
}
