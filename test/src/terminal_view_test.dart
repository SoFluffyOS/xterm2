import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:xterm2/src/ui/shortcut/actions.dart';
import 'package:xterm2/xterm.dart';

import '../_fixture/_fixture.dart';

@GenerateNiceMocks([MockSpec<TerminalInputHandler>()])
import 'terminal_view_test.mocks.dart';

const _lightTheme = TerminalTheme(
  cursor: Color(0xff111111),
  selection: Color(0xffcccccc),
  foreground: Color(0xff111111),
  background: Color(0xffffffff),
  black: Color(0xff000000),
  red: Color(0xffaa0000),
  green: Color(0xff00aa00),
  yellow: Color(0xffaa5500),
  blue: Color(0xff0000aa),
  magenta: Color(0xffaa00aa),
  cyan: Color(0xff00aaaa),
  white: Color(0xffaaaaaa),
  brightBlack: Color(0xff555555),
  brightRed: Color(0xffff5555),
  brightGreen: Color(0xff55ff55),
  brightYellow: Color(0xffffff55),
  brightBlue: Color(0xff5555ff),
  brightMagenta: Color(0xffff55ff),
  brightCyan: Color(0xff55ffff),
  brightWhite: Color(0xffffffff),
  searchHitBackground: Color(0xffffff2b),
  searchHitBackgroundCurrent: Color(0xff31ff26),
  searchHitForeground: Color(0xff000000),
);

void main() {
  testWidgets('terminal writes avoid layout when geometry is unchanged', (
    tester,
  ) async {
    final terminal = Terminal();
    await tester.pumpWidget(MaterialApp(home: TerminalView(terminal)));
    await tester.pump();
    final state = tester.state<TerminalViewState>(find.byType(TerminalView));

    terminal.write('text');

    expect(state.renderTerminal.debugNeedsLayout, isFalse);
  });

  testWidgets('TerminalView answers color queries from its theme', (
    tester,
  ) async {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);
    await tester.pumpWidget(MaterialApp(
      home: TerminalView(
        terminal,
        theme: TerminalThemes.whiteOnBlack,
      ),
    ));

    terminal.write(
      '\x1b]4;1;?\x1b\\'
      '\x1b]10;?;?;?\x1b\\'
      '\x1b[?996n',
    );

    expect(output, [
      '\x1b]4;1;rgb:cdcd/3131/3131\x1b\\',
      '\x1b]10;rgb:ffff/ffff/ffff\x1b\\',
      '\x1b]11;rgb:0000/0000/0000\x1b\\',
      '\x1b]12;rgb:aeae/afaf/adad\x1b\\',
      '\x1b[?997;1n',
    ]);

    await tester.pumpWidget(const SizedBox());
    expect(terminal.onColorQuery, isNull);
    expect(terminal.onColorSchemeQuery, isNull);
  });

  testWidgets('TerminalView reports color scheme changes when requested', (
    tester,
  ) async {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    await tester.pumpWidget(MaterialApp(
      home: TerminalView(
        terminal,
        theme: TerminalThemes.whiteOnBlack,
      ),
    ));

    terminal.write('\x1b[?2031h');

    await tester.pumpWidget(MaterialApp(
      home: TerminalView(
        terminal,
        theme: _lightTheme,
      ),
    ));

    terminal.write('\x1b[?2031l');

    await tester.pumpWidget(MaterialApp(
      home: TerminalView(
        terminal,
        theme: TerminalThemes.whiteOnBlack,
      ),
    ));

    expect(output, [
      '\x1b[?997;1n',
      '\x1b[?997;2n',
    ]);
  });

  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'htop golden test',
    (tester) async {
      final terminal = Terminal();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal),
        ),
      ));

      terminal.write(TestFixtures.htop_80x25_3s());
      await tester.pump();

      await expectLater(
        find.byType(TerminalView),
        matchesGoldenFile('_goldens/htop_80x25_3s.png'),
      );
    },
    skip: !Platform.isMacOS,
  );

  testWidgets(
    'color golden test',
    (tester) async {
      final terminal = Terminal();

      // terminal.lineFeedMode = true;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            textStyle: TerminalStyle(fontSize: 8),
          ),
        ),
      ));

      terminal.write(TestFixtures.colors().replaceAll('\n', '\r\n'));
      await tester.pump();

      await expectLater(
        find.byType(TerminalView),
        matchesGoldenFile('_goldens/colors.png'),
      );
    },
    skip: !Platform.isMacOS,
  );

  group('TerminalView.readOnly', () {
    testWidgets('works', (tester) async {
      final terminalOutput = <String>[];
      final terminal = Terminal(onOutput: terminalOutput.add);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal, readOnly: true, autofocus: true),
        ),
      ));

      // https://github.com/flutter/flutter/issues/11181#issuecomment-314936646
      await tester.tap(find.byType(TerminalView));
      await tester.pump(Duration(seconds: 1));

      binding.testTextInput.enterText('ls -al');
      await binding.idle();

      expect(terminalOutput.join(), isEmpty);
    });

    testWidgets('does not block input when false', (tester) async {
      final terminalOutput = <String>[];
      final terminal = Terminal(onOutput: terminalOutput.add);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal, readOnly: false, autofocus: true),
        ),
      ));

      // https://github.com/flutter/flutter/issues/11181#issuecomment-314936646
      await tester.tap(find.byType(TerminalView));
      await tester.pump(Duration(seconds: 1));

      binding.testTextInput.enterText('ls -al');
      await binding.idle();

      expect(terminalOutput.join(), 'ls -al');
    });
  });

  group('TerminalView.focusNode', () {
    testWidgets('reports focus changes when requested by the application', (
      tester,
    ) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add)..write('\x1b[?1004h');
      final terminalFocus = FocusNode();
      final otherFocus = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              SizedBox(
                height: 200,
                child: TerminalView(terminal, focusNode: terminalFocus),
              ),
              Focus(focusNode: otherFocus, child: const SizedBox()),
            ],
          ),
        ),
      );

      terminalFocus.requestFocus();
      await tester.pump();
      otherFocus.requestFocus();
      await tester.pump();

      expect(output, ['\x1b[I', '\x1b[I', '\x1b[O']);
      await tester.pumpWidget(const SizedBox());
      terminalFocus.dispose();
      otherFocus.dispose();
    });

    testWidgets('is not listened when terminal is disposed', (tester) async {
      final terminal = Terminal();

      final focusNode = FocusNode();

      final isActive = ValueNotifier(true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: isActive,
            builder: (context, isActive, child) {
              if (!isActive) {
                return Container();
              }
              return TerminalView(
                terminal,
                focusNode: focusNode,
                autofocus: true,
              );
            },
          ),
        ),
      ));

      // ignore: invalid_use_of_protected_member
      expect(focusNode.hasListeners, isTrue);

      isActive.value = false;
      await tester.pumpAndSettle();

      // ignore: invalid_use_of_protected_member
      expect(focusNode.hasListeners, isFalse);
    });

    testWidgets('does not dispose external focus node', (tester) async {
      final terminal = Terminal();

      final focusNode = FocusNode();

      final isActive = ValueNotifier(true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: isActive,
            builder: (context, isActive, child) {
              if (!isActive) {
                return Container();
              }
              return TerminalView(
                terminal,
                focusNode: focusNode,
                autofocus: true,
              );
            },
          ),
        ),
      ));

      isActive.value = false;
      await tester.pumpAndSettle();

      expect(() => focusNode.addListener(() {}), returnsNormally);
    });
  });

  testWidgets('TerminalView renders and times out cursor blinking', (
    tester,
  ) async {
    final terminal = Terminal()..write('\x1b[1 q');
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: TerminalView(
          terminal,
          focusNode: focusNode,
          autofocus: true,
        ),
      ),
    );
    await tester.pump();

    final state = tester.state<TerminalViewState>(find.byType(TerminalView));
    expect(state.renderTerminal.isCursorBlinkVisible, isTrue);

    await tester.pump(const Duration(milliseconds: 750));
    expect(state.renderTerminal.isCursorBlinkVisible, isFalse);

    await tester.pump(const Duration(milliseconds: 750));
    expect(state.renderTerminal.isCursorBlinkVisible, isTrue);

    await tester.pump(const Duration(seconds: 5));
    expect(state.renderTerminal.isCursorBlinkVisible, isTrue);

    terminal.write('x');
    await tester.pump();
    expect(state.renderTerminal.isCursorBlinkVisible, isTrue);

    await tester.pump(const Duration(milliseconds: 750));
    expect(state.renderTerminal.isCursorBlinkVisible, isFalse);

    await tester.pumpWidget(const SizedBox());
    focusNode.dispose();
  });

  testWidgets('TerminalView activates OSC 8 hyperlinks with modifier', (
    tester,
  ) async {
    final terminal = Terminal()
      ..write('\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\');
    String? activatedUri;

    await tester.pumpWidget(
      MaterialApp(
        home: TerminalView(
          terminal,
          onHyperlinkTap: (uri) => activatedUri = uri,
        ),
      ),
    );

    final state = tester.state<TerminalViewState>(find.byType(TerminalView));
    final position = state.renderTerminal.localToGlobal(const Offset(2, 2));

    await tester.tapAt(position);
    await tester.pump();

    expect(activatedUri, isNull);
    expect(state.renderTerminal.activeHyperlinkId, isNull);

    final modifierKey = switch (defaultTargetPlatform == TargetPlatform.macOS) {
      true => LogicalKeyboardKey.metaLeft,
      false => LogicalKeyboardKey.controlLeft,
    };
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(position));
    await tester.sendKeyDownEvent(modifierKey);
    await tester.pump();

    expect(state.renderTerminal.activeHyperlinkId, isNotNull);

    await tester.tapAt(position);
    await tester.pump();

    expect(activatedUri, 'https://example.com');

    await tester.sendKeyUpEvent(modifierKey);
    await tester.pump();

    expect(state.renderTerminal.activeHyperlinkId, isNull);
  });

  testWidgets(
      'TerminalView activates hovered OSC 8 links when modifier is held',
      (tester) async {
    final terminal = Terminal()
      ..write('\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\');
    String? activatedUri;

    await tester.pumpWidget(
      MaterialApp(
        home: TerminalView(
          terminal,
          onHyperlinkTap: (uri) => activatedUri = uri,
        ),
      ),
    );

    final state = tester.state<TerminalViewState>(find.byType(TerminalView));
    final position = state.renderTerminal.localToGlobal(const Offset(2, 2));
    final modifierKey = switch (defaultTargetPlatform == TargetPlatform.macOS) {
      true => LogicalKeyboardKey.metaLeft,
      false => LogicalKeyboardKey.controlLeft,
    };
    final pointer = TestPointer(1, PointerDeviceKind.mouse);

    await tester.sendKeyDownEvent(modifierKey);
    await tester.sendEventToBinding(pointer.hover(position));
    await tester.pump();

    expect(state.renderTerminal.activeHyperlinkId, isNotNull);

    await tester.tapAt(position);
    await tester.pump();

    expect(activatedUri, 'https://example.com');

    await tester.sendKeyUpEvent(modifierKey);
  });

  testWidgets('TerminalView reports hovered cell offsets', (tester) async {
    final terminal = Terminal()..write('abcdef');
    CellOffset? hoveredOffset;
    var exited = false;

    await tester.pumpWidget(
      MaterialApp(
        home: TerminalView(
          terminal,
          onHover: (_, offset) => hoveredOffset = offset,
          onExit: (_) => exited = true,
        ),
      ),
    );

    final state = tester.state<TerminalViewState>(find.byType(TerminalView));
    final position = state.renderTerminal.localToGlobal(
      Offset(state.renderTerminal.cellSize.width * 2.5, 2),
    );
    final pointer = TestPointer(1, PointerDeviceKind.mouse);

    await tester.sendEventToBinding(pointer.hover(position));
    await tester.pump();

    expect(hoveredOffset, const CellOffset(2, 0));

    await tester.sendEventToBinding(pointer.hover(const Offset(-10, -10)));
    await tester.pump();

    expect(exited, isTrue);
  });

  group('TerminalController.pointerInputs', () {
    testWidgets('reports pointer motion requested by the application', (
      tester,
    ) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add)
        ..write('\x1b[?1003h\x1b[?1006h');
      final controller = TerminalController(pointerInputs: PointerInputs.all());

      await tester.pumpWidget(
        MaterialApp(
          home: TerminalView(terminal, controller: controller),
        ),
      );

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(4, 4)));
      await tester.pump();

      expect(output, isNotEmpty);
      expect(output.last, startsWith('\x1b[<35;'));
    });

    testWidgets('works', (tester) async {
      final output = <String>[];

      final terminal = Terminal(onOutput: output.add);

      // enable mouse reporting
      terminal.write('\x1b[?1000h');

      final terminalView = TerminalController(
        pointerInputs: PointerInputs.all(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              controller: terminalView,
            ),
          ),
        ),
      );

      final pointer = TestPointer(1, PointerDeviceKind.mouse);

      await tester.sendEventToBinding(pointer.down(Offset(1, 1)));

      await tester.pumpAndSettle();

      expect(output, isNotEmpty);
    });

    testWidgets('does not respond when disabled', (tester) async {
      final output = <String>[];

      final terminal = Terminal(onOutput: output.add);

      // enable mouse reporting
      terminal.write('\x1b[?1000h');

      final terminalView = TerminalController(
        pointerInputs: PointerInputs.none(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              controller: terminalView,
            ),
          ),
        ),
      );

      final pointer = TestPointer(1, PointerDeviceKind.mouse);

      await tester.sendEventToBinding(pointer.down(Offset(1, 1)));

      await tester.pumpAndSettle();

      expect(output, isEmpty);
    });

    testWidgets('shift bypasses mouse reporting for selection', (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add)..write('abcdef');
      terminal.write('\x1b[?1002h');

      final controller = TerminalController(
        pointerInputs: PointerInputs.all(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              controller: controller,
            ),
          ),
        ),
      );

      final state = tester.state<TerminalViewState>(find.byType(TerminalView));
      final cellSize = state.renderTerminal.cellSize;
      final start = state.renderTerminal.localToGlobal(
        Offset(cellSize.width * 0.5, cellSize.height * 0.5),
      );
      final end = state.renderTerminal.localToGlobal(
        Offset(cellSize.width * 3.5, cellSize.height * 0.5),
      );
      final pointer = TestPointer(1, PointerDeviceKind.mouse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(pointer.down(start));
      await tester.pump();
      await tester.sendEventToBinding(pointer.move(end));
      await tester.pump();
      await tester.sendEventToBinding(pointer.up());
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(output, isEmpty);
      final selection = controller.selection;
      expect(selection, isNotNull);
      if (selection != null) {
        expect(terminal.buffer.getText(selection), 'abcd');
      }
    });

    testWidgets('XTSHIFTESCAPE captures shift mouse reporting', (
      tester,
    ) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add)..write('abcdef');
      terminal.write('\x1b[?1002h\x1b[?1006h\x1b[>1s');

      final controller = TerminalController(
        pointerInputs: PointerInputs.all(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              controller: controller,
            ),
          ),
        ),
      );

      final state = tester.state<TerminalViewState>(find.byType(TerminalView));
      final cellSize = state.renderTerminal.cellSize;
      final position = state.renderTerminal.localToGlobal(
        Offset(cellSize.width * 0.5, cellSize.height * 0.5),
      );
      final pointer = TestPointer(1, PointerDeviceKind.mouse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(pointer.down(position));
      await tester.pump();
      await tester.sendEventToBinding(pointer.up());
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(output, contains('\x1b[<4;1;1M'));
      expect(controller.selection, isNull);
    });

    testWidgets('reports scroll at local terminal coordinates', (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.write('\x1b[?1049h\x1b[?1000h\x1b[?1006h');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(left: 40, top: 30),
              child: TerminalView(terminal),
            ),
          ),
        ),
      );

      final state = tester.state<TerminalViewState>(find.byType(TerminalView));
      final position = state.renderTerminal.localToGlobal(
        const Offset(2, 2),
      );

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: Offset(0, state.renderTerminal.lineHeight),
        ),
      );
      await tester.pump();

      expect(output, isNotEmpty);
      expect(output.last, '\x1b[<65;1;1M');
    });

    testWidgets('reports scroll from the main buffer', (tester) async {
      final output = <String>[];
      final terminal = Terminal(maxLines: 100, onOutput: output.add);
      final scrollController = ScrollController();
      terminal.write(List.generate(100, (index) => '$index\r\n').join());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: TerminalView(
                terminal,
                scrollController: scrollController,
              ),
            ),
          ),
        ),
      );

      terminal.write('\x1b[?1000h\x1b[?1006h');
      await tester.pump();

      final state = tester.state<TerminalViewState>(find.byType(TerminalView));
      final position = state.renderTerminal.localToGlobal(const Offset(2, 2));
      final scrollOffsetBefore = scrollController.offset;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: Offset(0, -state.renderTerminal.lineHeight),
        ),
      );
      await tester.pump();

      expect(output, contains('\x1b[<64;1;1M'));
      expect(scrollController.offset, scrollOffsetBefore);
    });

    testWidgets('restores main-buffer scrollback after mouse reporting', (
      tester,
    ) async {
      final output = <String>[];
      final terminal = Terminal(maxLines: 100, onOutput: output.add);
      final scrollController = ScrollController();
      terminal.write(List.generate(100, (index) => '$index\r\n').join());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: TerminalView(
                terminal,
                scrollController: scrollController,
              ),
            ),
          ),
        ),
      );

      terminal.write('\x1b[?1000h\x1b[?1006h');
      await tester.pump();
      terminal.write('\x1b[?1000l');
      await tester.pump();

      final scrollOffsetBefore = scrollController.offset;
      final state = tester.state<TerminalViewState>(find.byType(TerminalView));
      final position = state.renderTerminal.localToGlobal(const Offset(2, 2));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: Offset(0, -state.renderTerminal.lineHeight),
        ),
      );
      await tester.pump();

      expect(scrollController.offset, lessThan(scrollOffsetBefore));
      expect(output, isEmpty);
    });

    testWidgets('accumulates precision scroll deltas', (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.write('\x1b[?1000h\x1b[?1006h');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(terminal),
          ),
        ),
      );

      final state = tester.state<TerminalViewState>(find.byType(TerminalView));
      final position = state.renderTerminal.localToGlobal(const Offset(2, 2));
      final partialDelta = state.renderTerminal.lineHeight * 0.6;
      for (var index = 0; index < 2; index++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: position,
            scrollDelta: Offset(0, partialDelta),
          ),
        );
        await tester.pump();
      }

      expect(output, ['\x1b[<65;1;1M']);
    });
  });

  group('TerminalView.autofocus', () {
    testWidgets('works', (tester) async {
      final terminal = Terminal();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              autofocus: true,
              focusNode: focusNode,
            ),
          ),
        ),
      );

      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('works in hardwareKeyboardOnly mode', (tester) async {
      final terminal = Terminal();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              autofocus: true,
              focusNode: focusNode,
              hardwareKeyboardOnly: true,
            ),
          ),
        ),
      );

      expect(focusNode.hasFocus, isTrue);
    });
  });

  group('TerminalView.hardwareKeyboardOnly', () {
    testWidgets('works', (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              autofocus: true,
              hardwareKeyboardOnly: true,
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);

      expect(output.join(), 'abc');
    });
  });

  group('TerminalView shortcuts', () {
    testWidgets('select all includes scrollback', (tester) async {
      final terminal = Terminal(maxLines: 10)..resize(4, 2);
      final controller = TerminalController();

      terminal.write('line1\r\nline2\r\nline3');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              controller: controller,
              autofocus: true,
              shortcuts: {
                SingleActivator(LogicalKeyboardKey.keyA):
                    const SelectAllTextIntent(SelectionChangedCause.keyboard),
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TerminalView));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);

      expect(
        terminal.buffer.getText(controller.selection),
        startsWith('line1\nline2\nline3'),
      );

      controller.dispose();
    });

    testWidgets('copy selection trims trailing whitespace', (tester) async {
      final terminal = Terminal(maxLines: 10)..resize(5, 3);
      final controller = TerminalController();
      String? clipboardText;

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              final arguments = call.arguments;
              if (arguments is Map) {
                clipboardText = arguments['text'] as String?;
              }
              return null;
            case 'Clipboard.getData':
              return {'text': clipboardText};
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      terminal.write('1AB  \r\n2EFGH');
      controller.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(3, 1),
      );

      late BuildContext actionContext;
      await tester.pumpWidget(
        MaterialApp(
          home: TerminalActions(
            terminal: terminal,
            controller: controller,
            child: Builder(
              builder: (context) {
                actionContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final result =
          Actions.invoke(actionContext, CopySelectionTextIntent.copy);
      if (result is Future) {
        await result;
      }

      expect(clipboardText, '1AB\n2EF');

      controller.dispose();
    });
  });

  group('TerminalView selection gestures', () {
    testWidgets('alt drag creates a rectangular block selection', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 10)..resize(5, 3);
      final controller = TerminalController();

      terminal.write('abcde\r\nfghij');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              controller: controller,
              autoResize: false,
              autofocus: true,
            ),
          ),
        ),
      );

      final state = tester.state<TerminalViewState>(find.byType(TerminalView));
      final cellSize = state.renderTerminal.cellSize;
      final start = state.renderTerminal.localToGlobal(
        Offset(cellSize.width * 1.5, cellSize.height * 0.5),
      );
      final end = state.renderTerminal.localToGlobal(
        Offset(cellSize.width * 3.5, cellSize.height * 1.5),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(start);
      await gesture.moveTo(end);
      await tester.pump();
      await gesture.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

      expect(controller.selection, isA<BufferRangeBlock>());
      expect(terminal.buffer.getText(controller.selection), 'bcd\nghi');

      controller.dispose();
    });

    testWidgets('triple click selects a soft-wrapped line', (tester) async {
      final terminal = Terminal(maxLines: 10)..resize(5, 4);
      final controller = TerminalController();

      terminal.write('old\r\nhelloworld\r\nafter');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalView(
              terminal,
              controller: controller,
              autoResize: false,
              autofocus: true,
            ),
          ),
        ),
      );

      final state = tester.state<TerminalViewState>(find.byType(TerminalView));
      final cellSize = state.renderTerminal.cellSize;
      final position = state.renderTerminal.localToGlobal(
        Offset(cellSize.width * 1.5, cellSize.height * 2.5),
      );

      await tester.tapAt(position);
      await tester.tapAt(position);
      await tester.tapAt(position);

      expect(
        terminal.buffer.getText(controller.selection),
        startsWith('helloworld'),
      );

      controller.dispose();
    });
  });

  group('TerminalView.textScaler', () {
    testWidgets('works', (tester) async {
      final terminal = Terminal();

      final textScaler = ValueNotifier(TextScaler.linear(1.0));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<TextScaler>(
              valueListenable: textScaler,
              builder: (context, textScaler, child) {
                return TerminalView(
                  terminal,
                  textScaler: textScaler,
                );
              },
            ),
          ),
        ),
      );

      terminal.write('Hello World');
      await tester.pump();

      await expectLater(
        find.byType(TerminalView),
        matchesGoldenFile('_goldens/text_scale_factor@1x.png'),
      );

      textScaler.value = TextScaler.linear(2.0);
      await tester.pump();

      await expectLater(
        find.byType(TerminalView),
        matchesGoldenFile('_goldens/text_scale_factor@2x.png'),
      );
    });

    testWidgets('can obtain textScaler from parent', (tester) async {
      final terminal = Terminal();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: TerminalView(
                terminal,
              ),
            ),
          ),
        ),
      );

      terminal.write('Hello World');
      await tester.pump();

      await expectLater(
        find.byType(TerminalView),
        matchesGoldenFile('_goldens/text_scale_factor@2x.png'),
      );
    });
  });

  group('TerminalView.inputHandler', () {
    testWidgets('works', (tester) async {
      final terminalOutput = <String>[];
      final terminal = Terminal(onOutput: terminalOutput.add);

      await tester.pumpWidget(MaterialApp(
        home: TerminalView(terminal, autofocus: true),
      ));

      await tester.tap(find.byType(TerminalView));
      await tester.pump(Duration(seconds: 1));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);

      await tester.pumpAndSettle();

      expect(terminalOutput.join(), '\x04');
    });

    testWidgets('can convert text input to key events', (tester) async {
      final inputHandler = MockTerminalInputHandler();
      when(inputHandler.call(any)).thenAnswer((invocation) => 'AAA');

      final terminalOutput = <String>[];
      final terminal = Terminal(
        inputHandler: inputHandler,
        onOutput: terminalOutput.add,
      );

      await tester.pumpWidget(MaterialApp(
        home: TerminalView(terminal, autofocus: true),
      ));

      await tester.tap(find.byType(TerminalView));
      await tester.pump(Duration(seconds: 1));

      binding.testTextInput.enterText('c');
      await binding.idle();

      await tester.pumpAndSettle();

      verify(inputHandler.call(any));
      expect(terminalOutput.join(), 'AAA');
    });

    testWidgets('forwards Kitty key release events', (tester) async {
      final terminalOutput = <String>[];
      final terminal = Terminal(onOutput: terminalOutput.add);
      terminal.write('\x1b[=2u');

      await tester.pumpWidget(MaterialApp(
        home: TerminalView(terminal, autofocus: true),
      ));
      await tester.tap(find.byType(TerminalView));
      await tester.pump(const Duration(seconds: 1));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);

      expect(terminalOutput, ['\x1b[A', '\x1b[1;1:3A']);
    });

    testWidgets('encodes unmapped text with Kitty associated text', (
      tester,
    ) async {
      final terminalOutput = <String>[];
      final terminal = Terminal(onOutput: terminalOutput.add);
      terminal.write('\x1b[=24u');

      await tester.pumpWidget(MaterialApp(
        home: TerminalView(terminal, autofocus: true),
      ));
      await tester.tap(find.byType(TerminalView));
      await tester.pump(const Duration(seconds: 1));

      binding.testTextInput.enterText('é');
      await binding.idle();

      binding.testTextInput.enterText('你好');
      await binding.idle();

      expect(terminalOutput, ['\x1b[233;;233u', '你好']);
    });

    testWidgets('falls back to shifted printable symbols', (tester) async {
      final terminalOutput = <String>[];
      final terminal = Terminal(onOutput: terminalOutput.add);

      await tester.pumpWidget(MaterialApp(
        home: TerminalView(terminal, autofocus: true),
      ));
      await tester.tap(find.byType(TerminalView));
      await tester.pump(const Duration(seconds: 1));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.digit2,
        character: '',
        physicalKey: PhysicalKeyboardKey.digit2,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(terminalOutput, ['@']);
    });

    testWidgets('does not fall back to printable symbols for shortcuts', (
      tester,
    ) async {
      final terminalOutput = <String>[];
      final terminal = Terminal(onOutput: terminalOutput.add);

      await tester.pumpWidget(MaterialApp(
        home: TerminalView(terminal, autofocus: true),
      ));
      await tester.tap(find.byType(TerminalView));
      await tester.pump(const Duration(seconds: 1));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.digit2,
        character: '',
        physicalKey: PhysicalKeyboardKey.digit2,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

      expect(terminalOutput, isEmpty);
    });

    testWidgets('forwards the platform command modifier to Kitty input', (
      tester,
    ) async {
      final terminalOutput = <String>[];
      final terminal = Terminal(onOutput: terminalOutput.add);
      terminal.write('\x1b[=1u');

      await tester.pumpWidget(MaterialApp(
        home: TerminalView(terminal, autofocus: true),
      ));
      await tester.tap(find.byType(TerminalView));
      await tester.pump(const Duration(seconds: 1));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

      expect(terminalOutput, contains('\x1b[50;9u'));
    });
  });

  group('TerminalView.simulateScroll', () {
    testWidgets('works', (tester) async {
      final terminalOutput = <String>[];
      final terminal = Terminal(onOutput: terminalOutput.add);
      terminal.useAltBuffer();

      await tester.pumpWidget(MaterialApp(
        home: TerminalView(terminal, autofocus: true, simulateScroll: true),
      ));

      await tester.drag(find.byType(TerminalView), const Offset(0, -100));

      expect(terminalOutput.join(), contains('\x1B[B'));
    });

    testWidgets('does nothing when disabled', (tester) async {
      final terminalOutput = <String>[];
      final terminal = Terminal(onOutput: terminalOutput.add);
      terminal.useAltBuffer();

      await tester.pumpWidget(MaterialApp(
        home: TerminalView(terminal, autofocus: true, simulateScroll: false),
      ));

      await tester.drag(find.byType(TerminalView), const Offset(0, -100));

      expect(terminalOutput.join(), isEmpty);
    });

    testWidgets('does nothing when read only', (tester) async {
      final terminalOutput = <String>[];
      final terminal = Terminal(onOutput: terminalOutput.add);
      terminal.useAltBuffer();

      await tester.pumpWidget(MaterialApp(
        home: TerminalView(
          terminal,
          autofocus: true,
          readOnly: true,
          simulateScroll: true,
        ),
      ));

      await tester.drag(find.byType(TerminalView), const Offset(0, -100));

      expect(terminalOutput.join(), isEmpty);
    });

    testWidgets('respects disabled scroll pointer input', (tester) async {
      final terminalOutput = <String>[];
      final terminal = Terminal(onOutput: terminalOutput.add);
      terminal.useAltBuffer();
      final controller = TerminalController(
        pointerInputs: PointerInputs.none(),
      );

      await tester.pumpWidget(MaterialApp(
        home: TerminalView(
          terminal,
          autofocus: true,
          controller: controller,
          simulateScroll: true,
        ),
      ));

      await tester.drag(find.byType(TerminalView), const Offset(0, -100));

      expect(terminalOutput.join(), isEmpty);
    });
  });
}
