import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

/// Keeps every client the terminal attaches, as Flutter's [TextInput]
/// keeps the last one after its connection closes.
class _RecordingControl with TextInputControl {
  final clients = <TextInputClient>[];

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    clients.add(client);
  }
}

void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  late _RecordingControl control;

  setUp(() {
    control = _RecordingControl();
    TextInput.setInputControl(control);
  });

  tearDown(TextInput.restorePlatformInputControl);

  Future<List<String>> pumpTerminal(
    WidgetTester tester, {
    FocusNode? focusNode,
  }) async {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal, autofocus: true, focusNode: focusNode),
        ),
      ),
    );
    await tester.tap(find.byType(TerminalView));
    await tester.pump(const Duration(seconds: 1));
    return output;
  }

  const typed = TextEditingValue(
    text: 'x',
    selection: TextSelection.collapsed(offset: 1),
  );

  testWidgets('a disposed terminal leaves its client holding nothing', (
    tester,
  ) async {
    final output = await pumpTerminal(tester);
    final client = control.clients.single;

    await tester.pumpWidget(const SizedBox());
    client.updateEditingValue(typed);
    client.performSelector('deleteBackward:');
    client.performAction(TextInputAction.newline);
    client.connectionClosed();

    expect(client.currentTextEditingValue, TextEditingValue.empty);
    expect(output, isEmpty);
  }, variant: desktop);

  testWidgets(
    'losing focus lets the client go, and focus again takes a new one',
    (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final output = await pumpTerminal(tester, focusNode: focusNode);
      final first = control.clients.single;

      focusNode.unfocus();
      await tester.pump();
      first.updateEditingValue(typed);
      expect(output, isEmpty);
      expect(first.currentTextEditingValue, TextEditingValue.empty);

      focusNode.requestFocus();
      await tester.pump();
      final second = control.clients.last;
      expect(second, isNot(same(first)));
      second.updateEditingValue(typed);
      expect(output, ['x']);
    },
    variant: desktop,
  );
}
