import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm2/src/ui/shortcut/actions.dart';

Map<ShortcutActivator, Intent> get defaultTerminalShortcuts {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return _defaultShortcuts;
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return _defaultAppleShortcuts;
  }
}

final _defaultShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
      CopySelectionTextIntent.copy,
  const SingleActivator(LogicalKeyboardKey.insert, control: true):
      CopySelectionTextIntent.copy,
  SingleActivator(
    LogicalKeyboardKey.keyV,
    control: true,
    shift: true,
  ): const PasteTextIntent(SelectionChangedCause.keyboard),
  const SingleActivator(LogicalKeyboardKey.insert, shift: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(
    LogicalKeyboardKey.keyA,
    control: true,
    shift: true,
  ): const SelectAllTextIntent(SelectionChangedCause.keyboard),
  const SingleActivator(LogicalKeyboardKey.home, shift: true):
      const TerminalScrollIntent(TerminalScrollTarget.top),
  const SingleActivator(LogicalKeyboardKey.end, shift: true):
      const TerminalScrollIntent(TerminalScrollTarget.bottom),
  const SingleActivator(LogicalKeyboardKey.pageUp, shift: true):
      const TerminalScrollIntent(TerminalScrollTarget.pageUp),
  const SingleActivator(LogicalKeyboardKey.pageDown, shift: true):
      const TerminalScrollIntent(TerminalScrollTarget.pageDown),
  const SingleActivator(
    LogicalKeyboardKey.arrowUp,
    control: true,
    shift: true,
  ): const TerminalPromptNavigationIntent(
    TerminalPromptNavigationTarget.previous,
  ),
  const SingleActivator(
    LogicalKeyboardKey.arrowDown,
    control: true,
    shift: true,
  ): const TerminalPromptNavigationIntent(
    TerminalPromptNavigationTarget.next,
  ),
};

final _defaultAppleShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyC, meta: true):
      CopySelectionTextIntent.copy,
  SingleActivator(LogicalKeyboardKey.keyV, meta: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyA, meta: true):
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
  const SingleActivator(LogicalKeyboardKey.home, shift: true):
      const TerminalScrollIntent(TerminalScrollTarget.top),
  const SingleActivator(LogicalKeyboardKey.end, shift: true):
      const TerminalScrollIntent(TerminalScrollTarget.bottom),
  const SingleActivator(LogicalKeyboardKey.pageUp, shift: true):
      const TerminalScrollIntent(TerminalScrollTarget.pageUp),
  const SingleActivator(LogicalKeyboardKey.pageDown, shift: true):
      const TerminalScrollIntent(TerminalScrollTarget.pageDown),
  const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true):
      const TerminalPromptNavigationIntent(
    TerminalPromptNavigationTarget.previous,
  ),
  const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true):
      const TerminalPromptNavigationIntent(
    TerminalPromptNavigationTarget.next,
  ),
  const SingleActivator(
    LogicalKeyboardKey.arrowUp,
    meta: true,
    shift: true,
  ): const TerminalPromptNavigationIntent(
    TerminalPromptNavigationTarget.previous,
  ),
  const SingleActivator(
    LogicalKeyboardKey.arrowDown,
    meta: true,
    shift: true,
  ): const TerminalPromptNavigationIntent(
    TerminalPromptNavigationTarget.next,
  ),
};

/// Clipboard shortcuts for embedders that provide their own navigation and search.
Map<ShortcutActivator, Intent> get clipboardTerminalShortcuts {
  final apple = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return {
    SingleActivator(LogicalKeyboardKey.keyC,
        control: !apple,
        meta: apple,
        shift: !apple): CopySelectionTextIntent.copy,
    SingleActivator(LogicalKeyboardKey.keyV, control: !apple, meta: apple):
        const PasteTextIntent(SelectionChangedCause.keyboard),
    SingleActivator(LogicalKeyboardKey.keyA, control: !apple, meta: apple):
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
  };
}
