import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/color_scheme.dart';
import 'package:xterm/src/core/input/event.dart';
import 'package:xterm/src/core/input/keys.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/cursor_type.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';
import 'package:xterm/src/ui/gesture/gesture_handler.dart';
import 'package:xterm/src/ui/input_map.dart';
import 'package:xterm/src/ui/keyboard_listener.dart';
import 'package:xterm/src/ui/keyboard_visibility.dart';
import 'package:xterm/src/ui/kitty_modifier_key_filter.dart';
import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/src/ui/scroll_handler.dart';
import 'package:xterm/src/ui/shortcut/actions.dart';
import 'package:xterm/src/ui/shortcut/shortcuts.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/terminal_theme.dart';
import 'package:xterm/src/ui/themes.dart';

class TerminalView extends StatefulWidget {
  const TerminalView(
    this.terminal, {
    super.key,
    this.controller,
    this.theme = TerminalThemes.defaultTheme,
    this.textStyle = const TerminalStyle(),
    this.textScaler,
    this.padding,
    this.scrollController,
    this.autoResize = true,
    this.backgroundOpacity = 1,
    this.focusNode,
    this.autofocus = false,
    this.onTapUp,
    this.onHyperlinkTap,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.mouseCursor = SystemMouseCursors.text,
    this.keyboardType = TextInputType.emailAddress,
    this.keyboardAppearance = Brightness.dark,
    this.cursorType = TerminalCursorType.block,
    this.alwaysShowCursor = false,
    this.deleteDetection = false,
    this.shortcuts,
    this.onKeyEvent,
    this.readOnly = false,
    this.hardwareKeyboardOnly = false,
    this.simulateScroll = true,
  });

  /// The underlying terminal that this widget renders.
  final Terminal terminal;

  final TerminalController? controller;

  /// The theme to use for this terminal.
  final TerminalTheme theme;

  /// The style to use for painting characters.
  final TerminalStyle textStyle;

  final TextScaler? textScaler;

  /// Padding around the inner [Scrollable] widget.
  final EdgeInsets? padding;

  /// Scroll controller for the inner [Scrollable] widget.
  final ScrollController? scrollController;

  /// Should this widget automatically notify the underlying terminal when its
  /// size changes. [true] by default.
  final bool autoResize;

  /// Opacity of the terminal background. Set to 0 to make the terminal
  /// background transparent.
  final double backgroundOpacity;

  /// An optional focus node to use as the focus node for this widget.
  final FocusNode? focusNode;

  /// True if this widget will be selected as the initial focus when no other
  /// node in its scope is currently focused.
  final bool autofocus;

  /// Callback for when the user taps on the terminal.
  final void Function(TapUpDetails, CellOffset)? onTapUp;

  /// Called when a cell containing an OSC 8 hyperlink is tapped.
  final void Function(String uri)? onHyperlinkTap;

  /// Function called when the user taps on the terminal with a secondary
  /// button.
  final void Function(TapDownDetails, CellOffset)? onSecondaryTapDown;

  /// Function called when the user stops holding down a secondary button.
  final void Function(TapUpDetails, CellOffset)? onSecondaryTapUp;

  /// The mouse cursor for mouse pointers that are hovering over the terminal.
  /// [SystemMouseCursors.text] by default.
  final MouseCursor mouseCursor;

  /// The type of information for which to optimize the text input control.
  /// [TextInputType.emailAddress] by default.
  final TextInputType keyboardType;

  /// The appearance of the keyboard. [Brightness.dark] by default.
  ///
  /// This setting is only honored on iOS devices.
  final Brightness keyboardAppearance;

  /// The type of cursor to use. [TerminalCursorType.block] by default.
  final TerminalCursorType cursorType;

  /// Whether to always show the cursor. This is useful for debugging.
  /// [false] by default.
  final bool alwaysShowCursor;

  /// Workaround to detect delete key for platforms and IMEs that does not
  /// emit hardware delete event. Prefered on mobile platforms. [false] by
  /// default.
  final bool deleteDetection;

  /// Shortcuts for this terminal. This has higher priority than input handler
  /// of the terminal If not provided, [defaultTerminalShortcuts] will be used.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Keyboard event handler of the terminal. This has higher priority than
  /// [shortcuts] and input handler of the terminal.
  final FocusOnKeyEventCallback? onKeyEvent;

  /// True if no input should send to the terminal.
  final bool readOnly;

  /// True if only hardware keyboard events should be used as input. This will
  /// also prevent any on-screen keyboard to be shown.
  final bool hardwareKeyboardOnly;

  /// If true, when the terminal is in alternate buffer (for example running
  /// vim, man, etc), if the application does not declare that it can handle
  /// scrolling, the terminal will simulate scrolling by sending up/down arrow
  /// keys to the application. This is standard behavior for most terminal
  /// emulators. True by default.
  final bool simulateScroll;

  @override
  State<TerminalView> createState() => TerminalViewState();
}

class TerminalViewState extends State<TerminalView> {
  late FocusNode _focusNode;

  late final ShortcutManager _shortcutManager;

  final _customTextEditKey = GlobalKey<CustomTextEditState>();

  final _scrollableKey = GlobalKey<ScrollableState>();

  final _viewportKey = GlobalKey();

  String? _composingText;

  int? _hoveredHyperlinkId;

  var _hyperlinkModifierPressed = false;

  late TerminalController _controller;

  late ScrollController _scrollController;

  late final int? Function(int, int?) _colorQuery = _resolveColorQuery;

  late final void Function(String, String) _clipboardStore = _storeClipboard;

  late final Future<String?> Function(String) _clipboardQuery = _queryClipboard;

  RenderTerminal get renderTerminal {
    final context = _viewportKey.currentContext;
    if (context == null) {
      throw StateError('Terminal viewport is not mounted');
    }

    final renderObject = context.findRenderObject();
    if (renderObject is RenderTerminal) {
      return renderObject;
    }

    throw StateError('Terminal viewport render object is not available');
  }

  @override
  void initState() {
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_reportFocusChange);
    _controller = widget.controller ?? TerminalController();
    _scrollController = widget.scrollController ?? ScrollController();
    _shortcutManager = ShortcutManager(
      shortcuts: widget.shortcuts ?? defaultTerminalShortcuts,
    );
    _installColorQuery(widget.terminal);
    _installColorSchemeQuery(widget.terminal);
    _installClipboardHandlers(widget.terminal);
    super.initState();
  }

  @override
  void didUpdateWidget(TerminalView oldWidget) {
    if (oldWidget.terminal != widget.terminal) {
      _removeColorQuery(oldWidget.terminal);
      _removeColorSchemeQuery(oldWidget.terminal);
      _removeClipboardHandlers(oldWidget.terminal);
      _installColorQuery(widget.terminal);
      _installColorSchemeQuery(widget.terminal);
      _installClipboardHandlers(widget.terminal);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_reportFocusChange);
      if (oldWidget.focusNode == null) {
        _focusNode.dispose();
      }
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_reportFocusChange);
    }
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller == null) {
        _controller.dispose();
      }
      _controller = widget.controller ?? TerminalController();
    }
    if (oldWidget.scrollController != widget.scrollController) {
      if (oldWidget.scrollController == null) {
        _scrollController.dispose();
      }
      _scrollController = widget.scrollController ?? ScrollController();
    }
    _shortcutManager.shortcuts = widget.shortcuts ?? defaultTerminalShortcuts;
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _removeColorQuery(widget.terminal);
    _removeColorSchemeQuery(widget.terminal);
    _removeClipboardHandlers(widget.terminal);
    _focusNode.removeListener(_reportFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    _shortcutManager.dispose();
    super.dispose();
  }

  void _installColorQuery(Terminal terminal) {
    terminal.onColorQuery ??= _colorQuery;
  }

  void _removeColorQuery(Terminal terminal) {
    if (terminal.onColorQuery == _colorQuery) {
      terminal.onColorQuery = null;
    }
  }

  void _installColorSchemeQuery(Terminal terminal) {
    terminal.onColorSchemeQuery ??= _resolveColorSchemeQuery;
  }

  void _removeColorSchemeQuery(Terminal terminal) {
    if (terminal.onColorSchemeQuery == _resolveColorSchemeQuery) {
      terminal.onColorSchemeQuery = null;
    }
  }

  void _installClipboardHandlers(Terminal terminal) {
    terminal.onClipboardStore ??= _clipboardStore;
    terminal.onClipboardQuery ??= _clipboardQuery;
  }

  void _removeClipboardHandlers(Terminal terminal) {
    if (terminal.onClipboardStore == _clipboardStore) {
      terminal.onClipboardStore = null;
    }
    if (terminal.onClipboardQuery == _clipboardQuery) {
      terminal.onClipboardQuery = null;
    }
  }

  void _storeClipboard(String selector, String text) {
    if (!_focusNode.hasFocus) return;
    unawaited(Clipboard.setData(ClipboardData(text: text)));
  }

  Future<String?> _queryClipboard(String selector) async {
    if (!_focusNode.hasFocus) return null;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  int? _resolveColorQuery(int code, int? index) {
    if (code == 4) {
      if (index == null) return null;
      return PaletteBuilder(widget.theme).paletteColor(index).toARGB32() &
          0x00ffffff;
    }
    final color = switch (code) {
      10 => widget.theme.foreground,
      11 => widget.theme.background,
      12 => widget.theme.cursor,
      _ => null,
    };
    if (color == null) return null;
    return color.toARGB32() & 0x00ffffff;
  }

  TerminalColorScheme _resolveColorSchemeQuery() {
    final luminance = widget.theme.background.computeLuminance();
    final isDark = luminance < 0.5;
    return switch (isDark) {
      true => TerminalColorScheme.dark,
      false => TerminalColorScheme.light,
    };
  }

  void _reportFocusChange() {
    widget.terminal.focusInput(_focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Scrollable(
      key: _scrollableKey,
      controller: _scrollController,
      viewportBuilder: (context, offset) {
        return _TerminalView(
          key: _viewportKey,
          terminal: widget.terminal,
          controller: _controller,
          offset: offset,
          padding: MediaQuery.of(context).padding,
          autoResize: widget.autoResize,
          backgroundOpacity: widget.backgroundOpacity,
          textStyle: widget.textStyle,
          textScaler: widget.textScaler ?? MediaQuery.textScalerOf(context),
          theme: widget.theme,
          focusNode: _focusNode,
          cursorType: widget.cursorType,
          alwaysShowCursor: widget.alwaysShowCursor,
          activeHyperlinkId: _activeHyperlinkId,
          onEditableRect: _onEditableRect,
          composingText: _composingText,
        );
      },
    );

    child = TerminalScrollGestureHandler(
      terminal: widget.terminal,
      simulateScroll: widget.simulateScroll,
      readOnly: widget.readOnly,
      getCellOffset: (offset) => renderTerminal.getCellOffset(offset),
      getLineHeight: () => renderTerminal.lineHeight,
      child: child,
    );

    if (!widget.hardwareKeyboardOnly) {
      child = CustomTextEdit(
        key: _customTextEditKey,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        inputType: widget.keyboardType,
        keyboardAppearance: widget.keyboardAppearance,
        deleteDetection: widget.deleteDetection,
        onInsert: _onInsert,
        onDelete: () {
          _scrollToBottom();
          widget.terminal.keyInput(TerminalKey.backspace);
        },
        onComposing: _onComposing,
        onAction: (action) {
          _scrollToBottom();
          // Android sends TextInputAction.newline when the user presses the virtual keyboard's enter key.
          if (action == TextInputAction.done ||
              action == TextInputAction.newline) {
            widget.terminal.keyInput(TerminalKey.enter);
          }
        },
        onKeyEvent: _handleKeyEvent,
        readOnly: widget.readOnly,
        child: child,
      );
    } else if (!widget.readOnly) {
      // Only listen for key input from a hardware keyboard.
      child = CustomKeyboardListener(
        child: child,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onInsert: _onInsert,
        onComposing: _onComposing,
        onKeyEvent: _handleKeyEvent,
      );
    }

    child = TerminalActions(
      terminal: widget.terminal,
      controller: _controller,
      child: child,
    );

    child = KeyboardVisibilty(
      onKeyboardShow: _onKeyboardShow,
      child: child,
    );

    child = TerminalGestureHandler(
      terminalView: this,
      terminalController: _controller,
      onTapUp: _onTapUp,
      onTapDown: _onTapDown,
      onSecondaryTapDown:
          widget.onSecondaryTapDown != null ? _onSecondaryTapDown : null,
      onSecondaryTapUp:
          widget.onSecondaryTapUp != null ? _onSecondaryTapUp : null,
      readOnly: widget.readOnly,
      child: child,
    );

    child = MouseRegion(
      cursor: switch (_activeHyperlinkId) {
        null => widget.mouseCursor,
        _ => SystemMouseCursors.click,
      },
      onHover: _onPointerHover,
      onExit: (_) => _setHoveredHyperlinkId(null),
      child: child,
    );

    child = Container(
      color:
          widget.theme.background.withValues(alpha: widget.backgroundOpacity),
      padding: widget.padding,
      child: child,
    );

    return child;
  }

  void requestKeyboard() {
    _customTextEditKey.currentState?.requestKeyboard();
  }

  void closeKeyboard() {
    _customTextEditKey.currentState?.closeKeyboard();
  }

  Rect get cursorRect {
    return renderTerminal.cursorOffset & renderTerminal.cursorSize;
  }

  Rect get globalCursorRect {
    return renderTerminal.localToGlobal(renderTerminal.cursorOffset) &
        renderTerminal.cursorSize;
  }

  void _onTapUp(TapUpDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    final hyperlink = switch (_hyperlinkModifierPressed) {
      true => widget.terminal.hyperlinkAt(offset),
      false => null,
    };
    if (hyperlink != null) widget.onHyperlinkTap?.call(hyperlink);
    widget.onTapUp?.call(details, offset);
  }

  int? get _activeHyperlinkId {
    if (!_hyperlinkModifierPressed) return null;
    return _hoveredHyperlinkId;
  }

  void _onPointerHover(PointerHoverEvent event) {
    final offset = renderTerminal.getCellOffset(event.localPosition);
    final hyperlinkId = widget.terminal.hyperlinkIdAt(offset);
    _setHoveredHyperlinkId(switch (hyperlinkId) {
      0 => null,
      _ => hyperlinkId,
    });
  }

  void _setHoveredHyperlinkId(int? hyperlinkId) {
    if (_hoveredHyperlinkId == hyperlinkId) return;
    setState(() => _hoveredHyperlinkId = hyperlinkId);
  }

  void _updateHyperlinkModifierState() {
    final pressed = switch (defaultTargetPlatform) {
      TargetPlatform.macOS => HardwareKeyboard.instance.isMetaPressed,
      _ => HardwareKeyboard.instance.isControlPressed,
    };
    if (_hyperlinkModifierPressed == pressed) return;
    setState(() => _hyperlinkModifierPressed = pressed);
  }

  void _onTapDown(_) {
    if (_controller.selection != null) {
      _controller.clearSelection();
    } else {
      if (!widget.hardwareKeyboardOnly) {
        _customTextEditKey.currentState?.requestKeyboard();
      } else {
        _focusNode.requestFocus();
      }
    }
  }

  void _onSecondaryTapDown(TapDownDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    widget.onSecondaryTapDown?.call(details, offset);
  }

  void _onSecondaryTapUp(TapUpDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    widget.onSecondaryTapUp?.call(details, offset);
  }

  bool get hasInputConnection {
    return _customTextEditKey.currentState?.hasInputConnection == true;
  }

  void _onInsert(String text) {
    if (isKittyModifierKeyCharacter(text)) {
      return;
    }
    final mappedKey = charToTerminalKey(text);
    if (mappedKey == null && text.runes.length != 1) {
      widget.terminal.textInput(text);
      _scrollToBottom();
      return;
    }
    final key = mappedKey ?? TerminalKey.none;

    // On mobile platforms there is no guarantee that virtual keyboard will
    // generate hardware key events. So we need first try to send the key
    // as a hardware key event. If it fails, then we send it as a text input.
    final consumed = widget.terminal.keyInput(key, text: text);

    if (!consumed) {
      widget.terminal.textInput(text);
    }

    _scrollToBottom();
  }

  void _onComposing(String? text) {
    setState(() => _composingText = text);
  }

  KeyEventResult _handleKeyEvent(FocusNode focusNode, KeyEvent event) {
    _updateHyperlinkModifierState();

    final resultOverride = widget.onKeyEvent?.call(focusNode, event);
    if (resultOverride != null && resultOverride != KeyEventResult.ignored) {
      return resultOverride;
    }

    final context = focusNode.context;
    if (context == null) {
      return KeyEventResult.ignored;
    }

    // ignore: invalid_use_of_protected_member
    final shortcutResult = _shortcutManager.handleKeypress(
      context,
      event,
    );

    if (shortcutResult != KeyEventResult.ignored) {
      return shortcutResult;
    }

    final key = keyToTerminalKey(event.logicalKey);
    var text = event.character;
    if (text != null && isKittyModifierKeyCharacter(text)) {
      text = null;
    }
    if (key == null && text == null) {
      return KeyEventResult.ignored;
    }

    final eventType = switch (event) {
      KeyRepeatEvent() => TerminalKeyEventType.repeat,
      KeyUpEvent() => TerminalKeyEventType.release,
      _ => TerminalKeyEventType.press,
    };
    final terminalKey = key ?? TerminalKey.none;

    final handled = widget.terminal.keyInput(
      terminalKey,
      ctrl: HardwareKeyboard.instance.isControlPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
      type: eventType,
      text: switch (eventType) {
        TerminalKeyEventType.release => null,
        _ => text,
      },
    );

    if (handled) {
      _scrollToBottom();
    }

    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _onKeyboardShow() {
    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  void _onEditableRect(Rect rect, Rect caretRect) {
    _customTextEditKey.currentState?.setEditableRect(rect, caretRect);
  }

  void _scrollToBottom() {
    final position = _scrollableKey.currentState?.position;
    if (position != null) {
      position.jumpTo(position.maxScrollExtent);
    }
  }
}

class _TerminalView extends LeafRenderObjectWidget {
  const _TerminalView({
    super.key,
    required this.terminal,
    required this.controller,
    required this.offset,
    required this.padding,
    required this.autoResize,
    required this.backgroundOpacity,
    required this.textStyle,
    required this.textScaler,
    required this.theme,
    required this.focusNode,
    required this.cursorType,
    required this.alwaysShowCursor,
    this.activeHyperlinkId,
    this.onEditableRect,
    this.composingText,
  });

  final Terminal terminal;

  final TerminalController controller;

  final ViewportOffset offset;

  final EdgeInsets padding;

  final bool autoResize;

  final double backgroundOpacity;

  final TerminalStyle textStyle;

  final TextScaler textScaler;

  final TerminalTheme theme;

  final FocusNode focusNode;

  final TerminalCursorType cursorType;

  final bool alwaysShowCursor;

  final int? activeHyperlinkId;

  final EditableRectCallback? onEditableRect;

  final String? composingText;

  @override
  RenderTerminal createRenderObject(BuildContext context) {
    return RenderTerminal(
      terminal: terminal,
      controller: controller,
      offset: offset,
      padding: padding,
      autoResize: autoResize,
      backgroundOpacity: backgroundOpacity,
      textStyle: textStyle,
      textScaler: textScaler,
      theme: theme,
      focusNode: focusNode,
      cursorType: cursorType,
      alwaysShowCursor: alwaysShowCursor,
      activeHyperlinkId: activeHyperlinkId,
      onEditableRect: onEditableRect,
      composingText: composingText,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderTerminal renderObject) {
    renderObject
      ..terminal = terminal
      ..controller = controller
      ..offset = offset
      ..padding = padding
      ..autoResize = autoResize
      ..backgroundOpacity = backgroundOpacity
      ..textStyle = textStyle
      ..textScaler = textScaler
      ..theme = theme
      ..focusNode = focusNode
      ..cursorType = cursorType
      ..alwaysShowCursor = alwaysShowCursor
      ..activeHyperlinkId = activeHyperlinkId
      ..onEditableRect = onEditableRect
      ..composingText = composingText;
  }
}
