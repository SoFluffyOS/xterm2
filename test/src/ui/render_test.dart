import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/src/ui/render.dart';
import 'package:xterm2/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bottom-follow scrollback growth schedules layout', () {
    final offset = _TestViewportOffset();
    final setup = _createRenderTerminal(offset: offset);
    final render = setup.render;
    final owner = PipelineOwner();

    render.attach(owner);
    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));

    expect(render.debugNeedsLayout, isFalse);

    setup.terminal.write('a\r\nb\r\nc\r\nd\r\ne\r\nf\r\ng\r\n');

    expect(render.debugNeedsLayout, isTrue);

    render.detach();
    setup.focusNode.dispose();
  });

  test('scroll-complete erase returns viewport to bottom', () {
    final offset = _TestViewportOffset();
    final setup = _createRenderTerminal(offset: offset);
    final render = setup.render;
    final owner = PipelineOwner();

    render.attach(owner);
    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));
    offset.jumpTo(0);

    setup.terminal.write('a\r\nb\r\nc\x1b[22J');
    expect(render.debugNeedsLayout, isTrue);

    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));

    expect(offset.pixels, offset.maxScrollExtent);

    render.detach();
    setup.focusNode.dispose();
  });

  test('full display erase returns viewport to bottom', () {
    final offset = _TestViewportOffset();
    final setup = _createRenderTerminal(offset: offset);
    final render = setup.render;
    final owner = PipelineOwner();

    render.attach(owner);
    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));
    setup.terminal.write('a\r\nb\r\nc\r\nd\r\ne\r\nf\r\ng\r\n');
    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));
    offset.jumpTo(0);

    setup.terminal.write('\x1b[H\x1b[2J');
    expect(render.debugNeedsLayout, isTrue);

    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));

    expect(offset.pixels, offset.maxScrollExtent);

    render.detach();
    setup.focusNode.dispose();
  });

  test('direct terminal clear returns viewport to bottom', () {
    final offset = _TestViewportOffset();
    final setup = _createRenderTerminal(offset: offset);
    final render = setup.render;
    final owner = PipelineOwner();

    render.attach(owner);
    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));
    setup.terminal.write('a\r\nb\r\nc\r\nd\r\ne\r\nf\r\ng\r\n');
    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));
    offset.jumpTo(0);

    setup.terminal.clear();
    expect(render.debugNeedsLayout, isTrue);

    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));

    expect(offset.pixels, offset.maxScrollExtent);
    expect(setup.terminal.buffer.scrollBack, 0);

    render.detach();
    setup.focusNode.dispose();
  });

  test('alternate screen switch clears the active selection', () {
    final setup = _createRenderTerminal();
    final render = setup.render;
    final owner = PipelineOwner();
    setup.controller.setSelection(
      setup.terminal.buffer.createAnchor(0, 0),
      setup.terminal.buffer.createAnchor(2, 0),
    );

    render.attach(owner);
    render.layout(
      BoxConstraints.tight(
        Size(render.cellSize.width * 10, render.cellSize.height * 5),
      ),
    );

    setup.terminal.write('\x1b[?1049h');

    expect(setup.controller.selection, isNull);

    render.detach();
    setup.focusNode.dispose();
  });

  test('normal output preserves user scrollback position', () {
    final offset = _TestViewportOffset();
    final setup = _createRenderTerminal(offset: offset);
    final render = setup.render;
    final owner = PipelineOwner();

    render.attach(owner);
    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));
    setup.terminal.write('a\r\nb\r\nc\r\nd\r\ne\r\nf\r\ng\r\n');
    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));
    offset.jumpTo(0);

    setup.terminal.write('h\r\n');
    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));

    expect(offset.pixels, 0);

    render.detach();
    setup.focusNode.dispose();
  });

  test('selection updates repaint without scheduling layout', () {
    final setup = _createRenderTerminal();
    final render = setup.render;
    final owner = PipelineOwner();

    render.attach(owner);
    render.layout(
      BoxConstraints.tight(
        Size(render.cellSize.width * 10, render.cellSize.height * 5),
      ),
    );

    setup.controller.setSelection(
      setup.terminal.buffer.createAnchor(0, 0),
      setup.terminal.buffer.createAnchor(2, 0),
    );

    expect(render.debugNeedsLayout, isFalse);
    expect(render.debugNeedsPaint, isTrue);

    render.detach();
    setup.focusNode.dispose();
  });

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

  test('line selection includes soft-wrapped logical line', () {
    final setup = _createRenderTerminal();
    final render = setup.render;
    final cellSize = render.cellSize;
    setup.terminal.resize(5, 4);
    setup.terminal.write('old\r\nhelloworld\r\nafter');

    render.selectLine(
      Offset(cellSize.width * 1.5, cellSize.height * 2.5),
    );

    final selection = setup.controller.selection;
    expect(selection?.begin, const CellOffset(0, 1));
    expect(selection?.end, const CellOffset(5, 2));
    expect(setup.terminal.buffer.getText(selection), 'helloworld');

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

  test('terminal underlines dispose with controller', () {
    final setup = _createRenderTerminal();
    final controller = setup.controller;
    final terminal = setup.terminal;
    terminal.write('https://example.com');

    final underline = controller.underline(
      p1: terminal.buffer.createAnchor(0, 0),
      p2: terminal.buffer.createAnchor(19, 0),
      color: const Color(0xffffffff),
    );

    expect(controller.underlines, contains(underline));

    underline.dispose();

    expect(controller.underlines, isEmpty);

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

  test('mouse reporting uses viewport cells when scrolled', () {
    final output = <String>[];
    final offset = _TestViewportOffset();
    final setup = _createRenderTerminal(offset: offset, onOutput: output.add);
    final render = setup.render;
    final owner = PipelineOwner();

    render.attach(owner);
    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));
    setup.terminal
      ..write('\x1b[?1000h\x1b[?1006h')
      ..write('a\r\nb\r\nc\r\nd\r\ne\r\nf\r\ng\r\n');
    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10,
      render.cellSize.height * 5,
    )));
    offset.jumpTo(render.cellSize.height * 2);

    render.mouseEvent(
      TerminalMouseButton.left,
      TerminalMouseButtonState.down,
      Offset(render.cellSize.width * 2, render.cellSize.height * 3),
    );

    expect(output.last, '\x1b[<0;3;4M');

    render.detach();
    setup.focusNode.dispose();
  });

  test('sgr pixel mouse reporting excludes padding', () {
    final output = <String>[];
    final setup = _createRenderTerminal(
      padding: const EdgeInsets.only(left: 7, top: 11),
      onOutput: output.add,
    );
    final render = setup.render;
    final owner = PipelineOwner();

    render.attach(owner);
    render.layout(BoxConstraints.tight(Size(
      render.cellSize.width * 10 + 7,
      render.cellSize.height * 5 + 11,
    )));
    setup.terminal.write('\x1b[?1000h\x1b[?1016h');

    render.mouseEvent(
      TerminalMouseButton.left,
      TerminalMouseButtonState.down,
      const Offset(27, 41),
    );

    expect(output.last, '\x1b[<0;21;31M');

    render.detach();
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
  ViewportOffset? offset,
  void Function(String)? onOutput,
}) {
  final terminal = Terminal(onOutput: onOutput)..resize(10, 5);
  final controller = TerminalController();
  final focusNode = FocusNode();
  final render = RenderTerminal(
    terminal: terminal,
    controller: controller,
    offset: offset ?? ViewportOffset.fixed(0),
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

class _TestViewportOffset extends ViewportOffset {
  double _pixels = 0;

  double maxScrollExtent = 0;

  @override
  bool get allowImplicitScrolling => false;

  @override
  bool get hasPixels => true;

  @override
  double get pixels => _pixels;

  @override
  ScrollDirection get userScrollDirection => ScrollDirection.idle;

  @override
  Future<void> animateTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) async {
    jumpTo(to);
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    this.maxScrollExtent = maxScrollExtent;
    return true;
  }

  @override
  bool applyViewportDimension(double viewportDimension) {
    return true;
  }

  @override
  void correctBy(double correction) {
    _pixels += correction;
  }

  @override
  void jumpTo(double pixels) {
    _pixels = pixels;
    notifyListeners();
  }
}
