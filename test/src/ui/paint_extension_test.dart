import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  testWidgets('paint phases surround backgrounds and foregrounds',
      (tester) async {
    final terminal = Terminal()
      ..resize(4, 2)
      ..write('\x1b[?25l\x1b[41m\u2588  ');
    final key = GlobalKey();
    TerminalPaintContext? frame;
    final phases = <String>[];
    await _pump(tester, terminal, key,
        extension: TerminalPaintExtension(
          beforeCellBackgrounds: (context) {
            phases.add('background');
            frame = context;
            context.canvas.drawRect(
                context.viewport, Paint()..color = const Color(0xff0000ff));
          },
          beforeCellForegrounds: (context) {
            phases.add('foreground');
            context.canvas.drawRect(
                context.cellOffset(0, 0) &
                    Size(context.cellSize.width * 2, context.cellSize.height),
                Paint()..color = const Color(0xff00ff00));
          },
          afterCellForegrounds: (context) {
            phases.add('after');
            context.canvas.drawRect(context.cellOffset(3, 0) & context.cellSize,
                Paint()..color = const Color(0xffffff00));
          },
        ));
    expect(phases, ['background', 'foreground', 'after']);
    final image = await _capture(tester, key);
    final cell = frame!.cellSize;
    expect(await _pixel(tester, image, cell.width ~/ 2, cell.height ~/ 2),
        const Color(0xffffffff));
    expect(
        await _pixel(
            tester, image, (cell.width * 1.5).floor(), cell.height ~/ 2),
        const Color(0xff00ff00));
    expect(
        await _pixel(
            tester, image, (cell.width * 2.5).floor(), cell.height ~/ 2),
        TerminalThemes.whiteOnBlack.red);
    expect(
        await _pixel(
            tester, image, (cell.width * 3.5).floor(), cell.height ~/ 2),
        const Color(0xffffff00));
    expect(
        await _pixel(
            tester, image, cell.width ~/ 2, (cell.height * 1.5).floor()),
        const Color(0xff0000ff));
    image.dispose();
  });

  testWidgets('empty extension preserves pixels and filters all text passes',
      (tester) async {
    final terminal = Terminal()
      ..resize(4, 2)
      ..write('\x1b[?25l\u2588X');
    final controller = TerminalController();
    final key = GlobalKey();
    await _pump(tester, terminal, key, controller: controller);
    final baseline = await _capture(tester, key);
    await _pump(tester, terminal, key,
        controller: controller, extension: const TerminalPaintExtension());
    final empty = await _capture(tester, key);
    expect(
        (await tester.runAsync(() => empty.toByteData()))!.buffer.asUint8List(),
        (await tester.runAsync(() => baseline.toByteData()))!
            .buffer
            .asUint8List());
    controller.setSelection(
        terminal.buffer.createAnchor(0, 0), terminal.buffer.createAnchor(1, 0));
    controller.setSearchHighlights(terminal.buffer,
        [BufferRangeLine(const CellOffset(0, 0), const CellOffset(1, 0))]);
    TerminalPaintContext? frame;
    await _pump(tester, terminal, key,
        controller: controller,
        extension: TerminalPaintExtension(
          cellForegroundFilter: (line, column) => column != 0,
          afterCellForegrounds: (context) => frame = context,
        ));
    final filtered = await _capture(tester, key);
    final center = frame!.cellSize.center(Offset.zero);
    expect(await _pixel(tester, filtered, center.dx.floor(), center.dy.floor()),
        isNot(const Color(0xffffffff)));
    terminal.buffer.lines[0].setCodePoint(0, 0x20);
    await _pump(tester, terminal, key,
        controller: controller,
        extension: TerminalPaintExtension(
            afterCellForegrounds: (context) => frame = context));
    final blank = await _capture(tester, key);
    expect(await _pixel(tester, filtered, center.dx.floor(), center.dy.floor()),
        await _pixel(tester, blank, center.dx.floor(), center.dy.floor()));
    baseline.dispose();
    empty.dispose();
    filtered.dispose();
    blank.dispose();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('callbacks isolate transforms and clips inside padded viewport',
      (tester) async {
    final terminal = Terminal()
      ..resize(4, 2)
      ..write('\x1b[?25l');
    final key = GlobalKey();
    TerminalPaintContext? frame;
    List<double>? transform;
    await _pump(tester, terminal, key,
        padding: const EdgeInsets.all(8),
        extension: TerminalPaintExtension(
          beforeCellBackgrounds: (context) {
            frame = context;
            transform = context.canvas.getTransform().toList();
            context.canvas.drawPaint(Paint()..color = const Color(0xff0000ff));
            context.canvas.translate(1000, 1000);
            context.canvas.clipRect(Rect.zero);
          },
          beforeCellForegrounds: (context) {
            expect(context.canvas.getTransform().toList(), transform);
            context.canvas.drawRect(context.cellOffset(0, 0) & context.cellSize,
                Paint()..color = const Color(0xff00ff00));
          },
          afterCellForegrounds: (context) {
            expect(context.canvas.getTransform().toList(), transform);
          },
        ));
    final image = await _capture(tester, key);
    expect(await _pixel(tester, image, 0, 0),
        TerminalThemes.whiteOnBlack.background);
    expect(await _pixel(tester, image, 9, 9), const Color(0xff00ff00));
    expect(await _pixel(tester, image, 150, 85), const Color(0xff0000ff));
    expect(frame!.viewport.width, 144);
    image.dispose();
  });

  testWidgets('geometry follows fractional scroll and scaled cell metrics',
      (tester) async {
    final terminal = Terminal()
      ..resize(4, 2)
      ..write('\x1b[?25l${List.filled(12, 'row').join('\r\n')}');
    final key = GlobalKey();
    final scroll = ScrollController();
    TerminalPaintContext? frame;
    final extension = TerminalPaintExtension(
        afterCellForegrounds: (context) => frame = context);
    await _pump(tester, terminal, key, scroll: scroll, extension: extension);
    final unscaled = frame!.cellSize;
    await _pump(tester, terminal, key,
        scroll: scroll,
        extension: extension,
        scaler: const TextScaler.linear(1.5));
    expect(frame!.cellSize.width, greaterThan(unscaled.width));
    expect(frame!.cellSize.height, greaterThan(unscaled.height));
    final height = frame!.cellSize.height;
    scroll.jumpTo(height * 2.25);
    await tester.pump();
    expect(frame!.firstRow, 2);
    expect(frame!.endRow,
        (scroll.offset + frame!.viewport.height - 0.000001) ~/ height + 1);
    expect(frame!.cellOffset(0, 2).dy - frame!.viewport.top,
        closeTo(-height * 0.25, 1));
    expect(frame!.cellOffset(1, 2).dx - frame!.cellOffset(0, 2).dx,
        frame!.cellSize.width);
    expect(identical(frame!.terminal, terminal), isTrue);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets('repaint source updates pixels and detaches on replacement',
      (tester) async {
    final terminal = Terminal()
      ..resize(4, 2)
      ..write('\x1b[?25l');
    final key = GlobalKey();
    final source = _RepaintSource();
    final replacement = _RepaintSource();
    var color = const Color(0xff00ff00);
    final extension = TerminalPaintExtension(
        repaint: source,
        afterCellForegrounds: (context) =>
            context.canvas.drawPaint(Paint()..color = color));
    await _pump(tester, terminal, key, extension: extension);
    expect(source.isListening, isTrue);
    color = const Color(0xff0000ff);
    source.notifyListeners();
    await tester.pump();
    final image = await _capture(tester, key);
    expect(await _pixel(tester, image, 20, 20), color);
    image.dispose();
    await _pump(tester, terminal, key,
        extension: TerminalPaintExtension(repaint: replacement));
    expect(source.isListening, isFalse);
    expect(replacement.isListening, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(replacement.isListening, isFalse);
    source.dispose();
    replacement.dispose();
  });

  testWidgets('foreground filtering keeps the focused cursor visible',
      (tester) async {
    final terminal = Terminal()
      ..resize(4, 2)
      ..write('\u{10eeee}\u0301\x1b[1G');
    final focus = FocusNode();
    final key = GlobalKey();
    TerminalPaintContext? frame;
    final extension = TerminalPaintExtension(
      cellForegroundFilter: (line, column) =>
          line.getCodePoint(column) != 0x10eeee,
      afterCellForegrounds: (context) => frame = context,
    );
    await _pump(tester, terminal, key, focus: focus, extension: extension);
    focus.requestFocus();
    await tester.pump();
    final image = await _capture(tester, key);
    final center = frame!.cellSize.center(Offset.zero);
    expect(await _pixel(tester, image, center.dx.floor(), center.dy.floor()),
        TerminalThemes.whiteOnBlack.cursor);
    image.dispose();
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
  });

  testWidgets('paint extension participates in text blink repaints',
      (tester) async {
    final terminal = Terminal()
      ..resize(4, 2)
      ..write('\x1b[?25l\x1b[5m\u2588');
    final key = GlobalKey();
    TerminalPaintContext? frame;
    var paints = 0;
    await _pump(tester, terminal, key, extension: TerminalPaintExtension(
      beforeCellForegrounds: (context) {
        frame = context;
        paints++;
        context.canvas.drawPaint(Paint()..color = const Color(0xff0000ff));
      },
    ));
    final first = await _capture(tester, key);
    final center = frame!.cellSize.center(Offset.zero);
    expect(await _pixel(tester, first, center.dx.floor(), center.dy.floor()),
        TerminalThemes.whiteOnBlack.foreground);
    final beforeBlink = paints;
    await tester.pump(const Duration(milliseconds: 600));
    expect(paints, greaterThan(beforeBlink));
    final blink = await _capture(tester, key);
    expect(await _pixel(tester, blink, center.dx.floor(), center.dy.floor()),
        const Color(0xff0000ff));
    first.dispose();
    blink.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> _pump(WidgetTester tester, Terminal terminal, GlobalKey key,
    {TerminalPaintExtension? extension,
    TerminalController? controller,
    EdgeInsets padding = EdgeInsets.zero,
    ScrollController? scroll,
    TextScaler scaler = TextScaler.noScaling,
    FocusNode? focus}) async {
  await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
          data: const MediaQueryData(),
          child: Center(
              child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                      width: 160,
                      height: 100,
                      child: TerminalView(terminal,
                          controller: controller,
                          focusNode: focus,
                          cursorBlink: false,
                          autoResize: false,
                          padding: padding,
                          scrollController: scroll,
                          textScaler: scaler,
                          textStyle:
                              const TerminalStyle(fontSize: 20, height: 1),
                          theme: TerminalThemes.whiteOnBlack,
                          paintExtension: extension,
                          hardwareKeyboardOnly: true,
                          readOnly: focus == null)))))));
}

Future<ui.Image> _capture(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() =>
        (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage()))!;

Future<Color> _pixel(WidgetTester tester, ui.Image image, int x, int y) async {
  final bytes = (await tester
      .runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i),
      bytes.getUint8(i + 1), bytes.getUint8(i + 2));
}

class _RepaintSource extends ChangeNotifier {
  bool get isListening => hasListeners;
}
