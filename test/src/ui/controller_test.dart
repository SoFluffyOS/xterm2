import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('TerminalController', () {
    test('dispose releases selection anchors', () {
      final terminal = Terminal();
      final controller = TerminalController();
      final base = terminal.buffer.createAnchor(0, 0);
      final extent = terminal.buffer.createAnchor(2, 2);
      controller.setSelection(base, extent);

      controller.dispose();

      expect(base.attached, isFalse);
      expect(extent.attached, isFalse);
    });

    testWidgets('setSelectionRange works', (tester) async {
      final terminal = Terminal();
      final terminalView = TerminalController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            controller: terminalView,
          ),
        ),
      ));

      terminalView.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 2),
      );

      await tester.pump();

      expect(terminalView.selection, isNotNull);
    });

    testWidgets('setSelectionMode changes BufferRange type', (tester) async {
      final terminal = Terminal();
      final terminalView = TerminalController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            controller: terminalView,
          ),
        ),
      ));

      terminalView.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 2),
      );

      expect(terminalView.selection, isA<BufferRangeLine>());

      terminalView.setSelectionMode(SelectionMode.block);

      expect(terminalView.selection, isA<BufferRangeBlock>());
    });

    testWidgets('clearSelection works', (tester) async {
      final terminal = Terminal();
      final terminalView = TerminalController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            controller: terminalView,
          ),
        ),
      ));

      terminalView.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 2),
      );

      expect(terminalView.selection, isNotNull);

      terminalView.clearSelection();

      expect(terminalView.selection, isNull);
    });
  });

  group('TerminalController.highlight', () {
    test('dispose releases highlight anchors', () {
      final terminal = Terminal();
      final controller = TerminalController();
      final start = terminal.buffer.createAnchor(5, 5);
      final end = terminal.buffer.createAnchor(5, 10);
      controller.highlight(
        p1: start,
        p2: end,
        color: Colors.yellow,
      );

      controller.dispose();

      expect(start.attached, isFalse);
      expect(end.attached, isFalse);
      expect(controller.highlights, isEmpty);
    });

    test('highlight dispose releases owned anchors', () {
      final terminal = Terminal();
      final controller = TerminalController();
      final start = terminal.buffer.createAnchor(5, 5);
      final end = terminal.buffer.createAnchor(5, 10);
      final highlight = controller.highlight(
        p1: start,
        p2: end,
        color: Colors.yellow,
      );

      highlight.dispose();

      expect(start.attached, isFalse);
      expect(end.attached, isFalse);
    });

    test('works', () {
      final terminal = Terminal();
      final controller = TerminalController();

      final highlight = controller.highlight(
        p1: terminal.buffer.createAnchor(5, 5),
        p2: terminal.buffer.createAnchor(5, 10),
        color: Colors.yellow,
      );
      assert(controller.highlights.length == 1);

      highlight.dispose();
      assert(controller.highlights.isEmpty);
    });
  });
}
