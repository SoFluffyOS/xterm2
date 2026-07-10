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
    expect(selection?.begin, const CellOffset(2, 1));
    expect(selection?.end, const CellOffset(5, 0));

    setup.focusNode.dispose();
  });

  test('character selection includes one cell when drag is collapsed', () {
    final setup = _createRenderTerminal();
    final render = setup.render;
    final cellSize = render.cellSize;

    render.selectCharacters(
      Offset(cellSize.width * 2.5, cellSize.height * 0.5),
    );

    final selection = setup.controller.selection;
    expect(selection?.begin, const CellOffset(2, 0));
    expect(selection?.end, const CellOffset(3, 0));

    setup.focusNode.dispose();
  });

  test('character selection snaps to both cells of a wide grapheme', () {
    final setup = _createRenderTerminal();
    final render = setup.render;
    final cellSize = render.cellSize;
    setup.terminal.write('好');

    render.selectCharacters(
      Offset(cellSize.width * 1.5, cellSize.height * 0.5),
    );

    final selection = setup.controller.selection;
    expect(selection?.begin, const CellOffset(0, 0));
    expect(selection?.end, const CellOffset(2, 0));
    expect(setup.terminal.buffer.getText(selection), '好');

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

  test('content geometry includes safe-area padding', () {
    const padding = EdgeInsets.fromLTRB(7, 11, 13, 17);
    final setup = _createRenderTerminal(padding: padding);
    final render = setup.render;
    final segment = BufferSegment(
      BufferRangeLine(const CellOffset(0, 0), const CellOffset(2, 0)),
      0,
      1,
      2,
    );

    expect(render.cursorOffset, Offset(padding.left, padding.top));
    expect(
      render.getSegmentOffset(segment, const Offset(3, 5)),
      Offset(3 + padding.left + render.cellSize.width, 5 + padding.top),
    );
    expect(
      render.getCellOffset(
        Offset(
          padding.left + render.cellSize.width / 2,
          padding.top + render.cellSize.height / 2,
        ),
      ),
      const CellOffset(0, 0),
    );

    setup.focusNode.dispose();
  });

  test('auto resize excludes safe-area padding from terminal cells', () {
    const padding = EdgeInsets.fromLTRB(7, 11, 13, 17);
    final setup = _createRenderTerminal(
      padding: padding,
      autoResize: true,
    );
    final render = setup.render;
    final size = Size(
      render.cellSize.width * 8 + padding.horizontal,
      render.cellSize.height * 4 + padding.vertical,
    );

    render.layout(BoxConstraints.tight(size));

    expect(setup.terminal.viewWidth, 8);
    expect(setup.terminal.viewHeight, 4);

    setup.focusNode.dispose();
  });

  test('OSC background override honors configured background opacity', () {
    final setup = _createRenderTerminal(backgroundOpacity: 0.5);
    final render = setup.render;
    final terminal = setup.terminal;

    terminal.write('\x1b]11;#ff0000\x1b\\');

    final color = render.debugBackgroundFillColor();
    if (color == null) {
      fail('Expected background override color');
    }

    expect(color.a, 0.5);
    expect(color.r, 1);
    expect(color.g, 0);
    expect(color.b, 0);

    setup.focusNode.dispose();
  });

  test('visible line range excludes fully clipped boundary row', () {
    final setup = _createRenderTerminal();
    final render = setup.render;
    final cellSize = render.cellSize;

    render.layout(BoxConstraints.tight(Size(
      cellSize.width * 10,
      cellSize.height,
    )));

    expect(render.debugVisibleLineRange(), (4, 4));

    render.layout(BoxConstraints.tight(Size(
      cellSize.width * 10,
      cellSize.height * 1.5,
    )));

    expect(render.debugVisibleLineRange(), (3, 4));

    setup.focusNode.dispose();
  });
}

({
  RenderTerminal render,
  Terminal terminal,
  TerminalController controller,
  FocusNode focusNode,
}) _createRenderTerminal({
  EdgeInsets padding = EdgeInsets.zero,
  bool autoResize = false,
  double backgroundOpacity = 1,
}) {
  final terminal = Terminal()..resize(10, 5);
  final controller = TerminalController();
  final focusNode = FocusNode();
  final render = RenderTerminal(
    terminal: terminal,
    controller: controller,
    offset: ViewportOffset.fixed(0),
    padding: padding,
    autoResize: autoResize,
    backgroundOpacity: backgroundOpacity,
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
