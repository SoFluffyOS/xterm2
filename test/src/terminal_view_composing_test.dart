import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<List<String>> pumpTerminal(
    WidgetTester tester, {
    String setup = '',
  }) async {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add)..write(setup);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TerminalView(terminal, autofocus: true)),
      ),
    );
    await tester.tap(find.byType(TerminalView));
    await tester.pump(const Duration(seconds: 1));
    return output;
  }

  /// What the input method reports: [text] with its last [composing]
  /// characters still being composed.
  TextEditingValue platform(String text, {int composing = 0}) {
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: switch (composing) {
        0 => TextRange.empty,
        _ => TextRange(start: text.length - composing, end: text.length),
      },
    );
  }

  testWidgets('a key that types its character is left to the input method', (
    tester,
  ) async {
    final output = await pumpTerminal(tester);

    final handled = await tester.sendKeyEvent(
      LogicalKeyboardKey.keyG,
      character: 'ㅎ',
    );
    final spaceHandled = await tester.sendKeyEvent(
      LogicalKeyboardKey.space,
      character: ' ',
    );

    expect(handled, isFalse);
    expect(spaceHandled, isFalse);
    expect(output, isEmpty);
  }, variant: desktop);

  testWidgets('composed Hangul reaches the program as syllables', (
    tester,
  ) async {
    final output = await pumpTerminal(tester);

    for (final preedit in ['ㅎ', '하', '한']) {
      tester.testTextInput.updateEditingValue(platform(preedit, composing: 1));
      await tester.pump();
      expect(output, isEmpty);
    }
    tester.testTextInput.updateEditingValue(platform('한ㄱ', composing: 1));
    await tester.pump();
    expect(output.join(), '한');

    tester.testTextInput.updateEditingValue(platform('한그', composing: 1));
    tester.testTextInput.updateEditingValue(platform('한글', composing: 1));
    await tester.pump();
    expect(output.join(), '한');

    tester.testTextInput.updateEditingValue(platform('한글'));
    await tester.pump();

    expect(output.join(), '한글');
  }, variant: desktop);

  testWidgets(
      'a syllable is sent once when the next starts before the '
      'input method hears the text was cleared', (tester) async {
    final output = await pumpTerminal(tester);

    // macOS Korean, typing gksrmf then Space: each commit and the next
    // syllable's start come as two updates from one key.
    for (final update in [
      platform('ㅎ', composing: 1),
      platform('하', composing: 1),
      platform('한', composing: 1),
      platform('한'),
      platform('한ㄱ', composing: 1),
      platform('한그', composing: 1),
      platform('한글', composing: 1),
      platform('한글'),
      platform('한글 '),
    ]) {
      tester.testTextInput.updateEditingValue(update);
      await tester.pump();
    }

    expect(output.join(), '한글 ');
  }, variant: desktop);

  testWidgets('the text is cleared once the terminal handles a key itself', (
    tester,
  ) async {
    final output = await pumpTerminal(tester);
    tester.testTextInput.updateEditingValue(platform('한', composing: 1));
    tester.testTextInput.updateEditingValue(platform('한'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(output, ['한', '\r']);
    expect(tester.testTextInput.editingState?['text'], '');
  }, variant: desktop);

  testWidgets('keys go to the input method while it composes', (tester) async {
    final output = await pumpTerminal(tester);
    tester.testTextInput.updateEditingValue(platform('한', composing: 1));
    await tester.pump();

    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.arrowLeft,
    ]) {
      expect(await tester.sendKeyEvent(key), isFalse);
    }

    expect(output, isEmpty);
  }, variant: desktop);

  testWidgets('control keys send what they always did', (tester) async {
    final output = await pumpTerminal(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC, character: 'c');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(output, ['\x1b[A', '\r', '\x7f', '\t', '\x03']);
  }, variant: desktop);

  testWidgets('a program that asked for keys still gets them as keys', (
    tester,
  ) async {
    final output = await pumpTerminal(tester, setup: '\x1b[=8u');

    final handled = await tester.sendKeyEvent(
      LogicalKeyboardKey.keyA,
      character: 'a',
    );

    expect(handled, isTrue);
    expect(output, ['\x1b[97u']);
  }, variant: desktop);

  testWidgets('a key that ended a composition still does its own job', (
    tester,
  ) async {
    final output = await pumpTerminal(tester);
    tester.testTextInput.updateEditingValue(platform('한', composing: 1));
    tester.testTextInput.updateEditingValue(platform('한'));
    await tester.pump();

    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.textInput.name,
      SystemChannels.textInput.codec.encodeMethodCall(
        const MethodCall('TextInputClient.performSelectors', [
          -1,
          ['moveLeft:'],
        ]),
      ),
      (_) {},
    );

    expect(output, ['한', '\x1b[D']);
  }, variant: desktop);

  testWidgets('keys type on their own where no input method follows them', (
    tester,
  ) async {
    final output = await pumpTerminal(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');

    expect(output, ['a']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
