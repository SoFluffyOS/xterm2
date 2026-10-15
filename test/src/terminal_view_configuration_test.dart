import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  test('font weight remains configurable and bold adds emphasis', () {
    const style = TerminalStyle(fontWeight: 500);
    expect(style.toTextStyle().fontWeight, FontWeight.w500);
    expect(style.toTextStyle(bold: true).fontWeight, FontWeight.w700);
    expect(style.copyWith(fontWeight: 900).toTextStyle(bold: true).fontWeight,
        FontWeight.w900);
  });

  testWidgets('copy and paste use injected callbacks', (tester) async {
    final terminal = Terminal()..write('copy me');
    final controller = TerminalController()
      ..setSelection(terminal.buffer.createAnchor(0, 0),
          terminal.buffer.createAnchor(4, 0));
    String? copied;
    var pasted = false;
    await tester.pumpWidget(MaterialApp(
      home: TerminalView(
        terminal,
        controller: controller,
        autofocus: true,
        onCopy: (text) async => copied = text,
        onPaste: () async => pasted = true,
      ),
    ));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(copied, 'copy');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(pasted, isTrue);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    terminal.dispose();
  });

  testWidgets('explicit blink overrides the application mode', (tester) async {
    final terminal = Terminal();
    await tester.pumpWidget(MaterialApp(
      home: TerminalView(terminal, autofocus: true, cursorBlink: true),
    ));
    await tester.pump();
    final render = tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .renderTerminal;
    expect(terminal.cursorBlinkMode, isFalse);
    await tester.pump(const Duration(milliseconds: 750));
    expect(render.isCursorBlinkVisible, isFalse);
    await tester.pumpWidget(MaterialApp(
      home: TerminalView(terminal, autofocus: true, cursorBlink: false),
    ));
    terminal.write('\x1b[?12h');
    await tester.pump(const Duration(milliseconds: 750));
    expect(render.isCursorBlinkVisible, isTrue);
    await tester.pumpWidget(const SizedBox());
    terminal.dispose();
  });
}
