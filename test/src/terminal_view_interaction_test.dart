import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  testWidgets('preserves composed accented text input', (tester) async {
    final terminalOutput = <String>[];
    final terminal = Terminal(onOutput: terminalOutput.add);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TerminalView(terminal, readOnly: false, autofocus: true),
      ),
    ));

    await tester.tap(find.byType(TerminalView));
    await tester.pump(Duration(seconds: 1));

    tester.binding.testTextInput.enterText('Hola como estás?');
    await tester.binding.idle();

    expect(terminalOutput.join(), 'Hola como estás?');
  });

  testWidgets('tracked clicks do not invoke the embedding tap callback', (
    tester,
  ) async {
    final output = <String>[];
    var tapCount = 0;
    final terminal = Terminal(onOutput: output.add)..write('\x1b[?1000h');
    final controller = TerminalController(pointerInputs: PointerInputs.all());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            controller: controller,
            onTapUp: (details, offset) => tapCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TerminalView));
    await tester.pump(kDoubleTapTimeout);

    expect(output, isNotEmpty);
    expect(tapCount, 0);
  });

  testWidgets(
    'a hyperlink click under mouse tracking opens the link, unreported',
    (tester) async {
      final output = <String>[];
      final links = <String>[];
      final terminal = Terminal(
        platform: TerminalTargetPlatform.macos,
        onOutput: output.add,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              autofocus: true,
              onHyperlinkTap: links.add,
            ),
          ),
        ),
      );
      await tester.pump();
      terminal.write(
        '\x1b[?1000h\x1b[?1006h'
        '\x1b]8;;https://example.com/a\x1b\\link\x1b]8;;\x1b\\',
      );
      output.clear();
      final cell =
          tester.getTopLeft(find.byType(TerminalView)) + const Offset(4, 6);

      await tester.tapAt(cell, kind: PointerDeviceKind.mouse);
      await tester.pump(kDoubleTapTimeout);
      expect(output.join(), contains('\x1b[<0;1;1M'));
      expect(links, isEmpty);
      output.clear();

      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.tapAt(cell, kind: PointerDeviceKind.mouse);
      await tester.pump(kDoubleTapTimeout);
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );

      expect(links, ['https://example.com/a']);
      expect(output.join(), isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'motion under the hyperlink modifier is reported, a drag is not',
    (tester) async {
      // An application that underlines the link under the mouse itself
      // follows the mouse off it; the drag belongs to the link click.
      final output = <String>[];
      final terminal = Terminal(
        platform: TerminalTargetPlatform.macos,
        onOutput: output.add,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              autofocus: true,
              onHyperlinkTap: (_) {},
              controller: TerminalController(
                pointerInputs: const PointerInputs.all(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      terminal.write(
        '\x1b[?1003h\x1b[?1006h'
        '\x1b]8;;https://example.com/a\x1b\\link\x1b]8;;\x1b\\',
      );
      final origin = tester.getTopLeft(find.byType(TerminalView));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: origin + const Offset(4, 6));
      await tester.pump();
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      output.clear();

      await mouse.moveTo(origin + const Offset(204, 46));
      await tester.pump();
      expect(output.join(), contains('\x1b[<35;'));
      output.clear();

      await mouse.moveTo(origin + const Offset(4, 6));
      await tester.pump();
      output.clear();
      await mouse.down(origin + const Offset(4, 6));
      await mouse.moveTo(origin + const Offset(244, 46));
      await mouse.up();
      await tester.pump(kDoubleTapTimeout);
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      expect(output.join(), isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  group('a click with the hyperlink modifier is the application\'s', () {
    Future<List<String>> pumpTracked(
      WidgetTester tester, {
      void Function(String)? onHyperlinkTap,
    }) async {
      final output = <String>[];
      final terminal = Terminal(
        platform: TerminalTargetPlatform.macos,
        onOutput: output.add,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              autofocus: true,
              onHyperlinkTap: onHyperlinkTap,
            ),
          ),
        ),
      );
      await tester.pump();
      terminal.write(
        '\x1b[?1000h\x1b[?1006h'
        '\x1b]8;;https://example.com/a\x1b\\link\x1b]8;;\x1b\\ plain text',
      );
      output.clear();
      return output;
    }

    Future<void> commandClick(
      WidgetTester tester,
      Offset at, {
      int buttons = kPrimaryButton,
    }) async {
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
      await tester.tapAt(at, kind: PointerDeviceKind.mouse, buttons: buttons);
      await tester.pump(kDoubleTapTimeout);
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.metaLeft,
        platform: 'macos',
      );
    }

    testWidgets('beside a link', (tester) async {
      final links = <String>[];
      final output = await pumpTracked(tester, onHyperlinkTap: links.add);
      final state = tester.state<TerminalViewState>(find.byType(TerminalView));
      final cell = state.renderTerminal.cellSize;
      final plainText = state.renderTerminal.localToGlobal(
        Offset(cell.width * 8.5, cell.height * 0.5),
      );

      await commandClick(tester, plainText);

      expect(links, isEmpty);
      expect(output.join(), contains('\x1b[<0;9;1M'));
      expect(output.join(), contains('\x1b[<0;9;1m'));
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('on a link, in a view that opens no links', (tester) async {
      final output = await pumpTracked(tester);
      final link =
          tester.getTopLeft(find.byType(TerminalView)) + const Offset(4, 6);

      await commandClick(tester, link);

      expect(output.join(), contains('\x1b[<0;1;1M'));
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('with the secondary button on a link', (tester) async {
      final links = <String>[];
      final output = await pumpTracked(tester, onHyperlinkTap: links.add);
      final link =
          tester.getTopLeft(find.byType(TerminalView)) + const Offset(4, 6);

      await commandClick(tester, link, buttons: kSecondaryButton);

      expect(links, isEmpty);
      expect(output.join(), contains('\x1b[<2;1;1M'));
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });

  testWidgets('tracked double clicks release both button presses', (
    tester,
  ) async {
    final output = <String>[];
    var tapCount = 0;
    final terminal = Terminal(onOutput: output.add)
      ..write('\x1b[?1000h\x1b[?1006h');
    final controller = TerminalController(pointerInputs: PointerInputs.all());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            controller: controller,
            onTapUp: (details, offset) => tapCount += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TerminalView));
    await tester.tap(find.byType(TerminalView));
    await tester.pump(kDoubleTapTimeout);

    expect(output, hasLength(4));
    expect(output[0], endsWith('M'));
    expect(output[1], endsWith('m'));
    expect(output[2], endsWith('M'));
    expect(output[3], endsWith('m'));
    expect(tapCount, 0);
  });

  testWidgets('forwards mouse drag motion when tracking is active', (
    tester,
  ) async {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add)
      ..write('\x1b[?1003h\x1b[?1006h');
    final controller = TerminalController(pointerInputs: PointerInputs.all());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 240,
            child: TerminalView(terminal, controller: controller),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(TerminalView));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.down(center);
    await tester.pump(kPressTimeout);
    await mouse.moveBy(const Offset(40, 20));
    await tester.pump();
    await mouse.up();
    await tester.pump();

    expect(output.join(), contains('\x1b[<0;'));
    expect(output.join(), contains('\x1b[<32;'));
    expect(output.join(), contains('m'));
    expect(controller.selection, isNull);
  });

  testWidgets('shift-drag keeps local selection during mouse tracking', (
    tester,
  ) async {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add)
      ..write('selectable text')
      ..write('\x1b[?1003h\x1b[?1006h');
    final controller = TerminalController(pointerInputs: PointerInputs.all());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 240,
            child: TerminalView(terminal, controller: controller),
          ),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final center = tester.getCenter(find.byType(TerminalView));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.down(center);
    await tester.pump(kPressTimeout);
    await mouse.moveBy(const Offset(40, 0));
    await tester.pump();
    await mouse.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(output, isEmpty);
    expect(controller.selection, isNotNull);
  });

  testWidgets('drag override keeps local selection during mouse tracking', (
    tester,
  ) async {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add)
      ..write('selectable text')
      ..write('\x1b[?1003h\x1b[?1006h');
    final controller = TerminalController(pointerInputs: PointerInputs.all());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 240,
            child: TerminalView(
              terminal,
              controller: controller,
              dragOverridesMouseReporting: true,
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(TerminalView));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.down(center);
    await tester.pump(kPressTimeout);
    await mouse.moveBy(const Offset(40, 0));
    await tester.pump();
    await mouse.up();
    await tester.pump();

    expect(output, isEmpty);
    expect(controller.selection, isNotNull);
  });

  testWidgets('drag override still reports clicks to a tracking application', (
    tester,
  ) async {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add)
      ..write('\x1b[?1003h\x1b[?1006h');
    final controller = TerminalController(pointerInputs: PointerInputs.all());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 240,
            child: TerminalView(
              terminal,
              controller: controller,
              dragOverridesMouseReporting: true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TerminalView));
    await tester.pump(kDoubleTapTimeout);

    expect(output, hasLength(2));
    expect(output[0], startsWith('\x1b[<0;'));
    expect(output[0], endsWith('M'));
    expect(output[1], endsWith('m'));
    expect(controller.selection, isNull);
  });

  testWidgets('ctrl-c copies a local selection and interrupts without one', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add)..write('copy me');
    final controller = TerminalController()
      ..setSelection(
        terminal.buffer.createAnchorFromOffset(CellOffset(0, 0)),
        terminal.buffer.createAnchorFromOffset(CellOffset(4, 0)),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: TerminalView(
          terminal,
          controller: controller,
          autofocus: true,
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(clipboardText, 'copy');
    expect(output, isEmpty);

    controller.clearSelection();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(output.join(), contains('\x03'));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('reports wheel input in the main buffer when requested', (
    tester,
  ) async {
    final terminalOutput = <String>[];
    final terminal = Terminal(onOutput: terminalOutput.add)
      ..write('\x1b[?1003h\x1b[?1006h');

    await tester.pumpWidget(
      MaterialApp(
        home: TerminalView(
          terminal,
          controller: TerminalController(pointerInputs: PointerInputs.all()),
          mouseWheelSensitivity: 2,
        ),
      ),
    );

    await tester.drag(find.byType(TerminalView), const Offset(0, -100));

    expect(terminalOutput.join(), contains('\x1b[<65;'));
    expect(
      RegExp(r'\x1b\[<65;').allMatches(terminalOutput.join()),
      hasLength(greaterThanOrEqualTo(2)),
    );
  });
}
