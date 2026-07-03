import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('highlight segment offset includes render paint offset', () {
    final terminal = Terminal();
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
    final range = BufferRangeLine(
      const CellOffset(0, 2),
      const CellOffset(4, 2),
    );
    final segment = BufferSegment(range, 2, 3, 4);
    const paintOffset = Offset(30, 20);

    final segmentOffset = render.getSegmentOffset(segment, paintOffset);

    expect(segmentOffset.dx, paintOffset.dx + render.cellSize.width * 3);
    expect(segmentOffset.dy, paintOffset.dy + render.cellSize.height * 2);

    focusNode.dispose();
  });
}
