import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm2_core/xterm2_core.dart';
import 'package:xterm2/src/ui/controller.dart';
import 'package:xterm2/src/ui/selection_mode.dart';

enum TerminalScrollTarget {
  top,
  bottom,
  pageUp,
  pageDown,
}

class TerminalScrollIntent extends Intent {
  const TerminalScrollIntent(this.target);

  final TerminalScrollTarget target;
}

enum TerminalPromptNavigationTarget {
  previous,
  next,
}

class TerminalPromptNavigationIntent extends Intent {
  const TerminalPromptNavigationIntent(this.target);

  final TerminalPromptNavigationTarget target;
}

class TerminalActions extends StatelessWidget {
  const TerminalActions({
    super.key,
    required this.terminal,
    required this.controller,
    required this.getScrollPosition,
    required this.getLineHeight,
    required this.child,
    this.onPaste,
    this.onCopy,
  });

  final Terminal terminal;

  final TerminalController controller;

  final ScrollPosition? Function() getScrollPosition;

  final double Function() getLineHeight;

  final Widget child;

  final Future<void> Function()? onPaste;
  final Future<void> Function(String text)? onCopy;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        PasteTextIntent: CallbackAction<PasteTextIntent>(
          onInvoke: (intent) async {
            if (onPaste != null) {
              await onPaste!();
              controller.clearSelection();
              return null;
            }
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            final text = data?.text;
            if (text != null) {
              terminal.paste(text);
              controller.clearSelection();
            }
            return null;
          },
        ),
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (intent) async {
            final selection = controller.selectionFor(terminal.buffer);

            if (selection == null) {
              return;
            }

            final text = terminal.buffer.getText(selection, true);

            if (onCopy != null) {
              await onCopy!(text);
            } else {
              await Clipboard.setData(ClipboardData(text: text));
            }

            return null;
          },
        ),
        SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
          onInvoke: (intent) {
            controller.setSelection(
              terminal.buffer.createAnchor(0, 0),
              terminal.buffer.createAnchor(
                terminal.viewWidth,
                terminal.buffer.height - 1,
              ),
              mode: SelectionMode.line,
            );
            return null;
          },
        ),
        TerminalScrollIntent: _TerminalScrollAction(
          terminal: terminal,
          getScrollPosition: getScrollPosition,
        ),
        TerminalPromptNavigationIntent: _TerminalPromptNavigationAction(
          terminal: terminal,
          getScrollPosition: getScrollPosition,
          getLineHeight: getLineHeight,
        ),
      },
      child: child,
    );
  }
}

class _TerminalScrollAction extends Action<TerminalScrollIntent> {
  _TerminalScrollAction({
    required this.terminal,
    required this.getScrollPosition,
  });

  final Terminal terminal;

  final ScrollPosition? Function() getScrollPosition;

  @override
  bool isEnabled(TerminalScrollIntent intent) {
    return !terminal.isUsingAltBuffer && getScrollPosition() != null;
  }

  @override
  Object? invoke(TerminalScrollIntent intent) {
    final position = getScrollPosition();
    if (position == null) return null;

    final target = switch (intent.target) {
      TerminalScrollTarget.top => position.minScrollExtent,
      TerminalScrollTarget.bottom => position.maxScrollExtent,
      TerminalScrollTarget.pageUp =>
        position.pixels - position.viewportDimension,
      TerminalScrollTarget.pageDown =>
        position.pixels + position.viewportDimension,
    };
    position.jumpTo(
      target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
    return null;
  }
}

class _TerminalPromptNavigationAction
    extends Action<TerminalPromptNavigationIntent> {
  _TerminalPromptNavigationAction({
    required this.terminal,
    required this.getScrollPosition,
    required this.getLineHeight,
  });

  final Terminal terminal;

  final ScrollPosition? Function() getScrollPosition;

  final double Function() getLineHeight;

  @override
  bool isEnabled(TerminalPromptNavigationIntent intent) {
    return !terminal.isUsingAltBuffer && getScrollPosition() != null;
  }

  @override
  Object? invoke(TerminalPromptNavigationIntent intent) {
    final position = getScrollPosition();
    if (position == null) return null;

    final lineHeight = getLineHeight();
    if (lineHeight <= 0) return null;

    final currentLine = (position.pixels / lineHeight).floor();
    final targetLine = switch (intent.target) {
      TerminalPromptNavigationTarget.previous =>
        terminal.semanticPromptLineBefore(currentLine),
      TerminalPromptNavigationTarget.next =>
        terminal.semanticPromptLineAfter(currentLine),
    };
    if (targetLine == null) return null;

    final target = targetLine * lineHeight;
    position.jumpTo(
      target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
    return null;
  }
}
