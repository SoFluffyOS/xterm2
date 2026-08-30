import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm2/core.dart';
import 'package:xterm2/src/ui/controller.dart';
import 'package:xterm2/src/ui/infinite_scroll_view.dart';
import 'package:xterm2/src/ui/pointer_input.dart';

typedef TerminalMouseEventCallback = bool Function(
  TerminalMouseButton button,
  TerminalMouseButtonState state,
  Offset offset, {
  required TerminalMouseModifiers modifiers,
});

/// Routes scrolling gestures either to terminal scrollback or to the running
/// application based on the current terminal modes.
class TerminalScrollGestureHandler extends StatefulWidget {
  const TerminalScrollGestureHandler({
    super.key,
    required this.terminal,
    required this.terminalController,
    required this.sendMouseEvent,
    required this.getScrollPosition,
    required this.getLineHeight,
    required this.getCellWidth,
    this.simulateScroll = true,
    this.mouseWheelSensitivity = 1,
    this.shiftOverridesMouseReporting = false,
    this.readOnly = false,
    required this.child,
  });

  final Terminal terminal;

  final TerminalController terminalController;

  final TerminalMouseEventCallback sendMouseEvent;

  /// Returns the scroll position of the terminal's main buffer.
  final ScrollPosition? Function() getScrollPosition;

  /// Returns the pixel height of lines in the terminal.
  final double Function() getLineHeight;

  /// Returns the pixel width of cells in the terminal.
  final double Function() getCellWidth;

  /// Whether to simulate scroll events in the terminal when the application
  /// doesn't declare it supports mouse wheel events. true by default as it
  /// is the default behavior of most terminals.
  final bool simulateScroll;

  final int mouseWheelSensitivity;
  final bool shiftOverridesMouseReporting;

  final bool readOnly;

  final Widget child;

  @override
  State<TerminalScrollGestureHandler> createState() =>
      _TerminalScrollGestureHandlerState();
}

class _TerminalScrollGestureHandlerState
    extends State<TerminalScrollGestureHandler> {
  var handlesApplicationScroll = false;

  /// The variable that tracks the line offset in last scroll event. Used to
  /// determine how many the scroll events should be sent to the terminal.
  var lastLineOffset = 0;

  var horizontalScrollRemainder = 0.0;

  /// This variable tracks the last offset where the scroll gesture started.
  /// Used to calculate the cell offset of the terminal mouse event.
  var lastPointerPosition = Offset.zero;

  @override
  void initState() {
    widget.terminal.addListener(_onTerminalUpdated);
    handlesApplicationScroll = _shouldHandleApplicationScroll();
    super.initState();
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminalUpdated);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TerminalScrollGestureHandler oldWidget) {
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_onTerminalUpdated);
      widget.terminal.addListener(_onTerminalUpdated);
      handlesApplicationScroll = _shouldHandleApplicationScroll();
      lastLineOffset = 0;
      horizontalScrollRemainder = 0;
    }
    super.didUpdateWidget(oldWidget);
  }

  void _onTerminalUpdated() {
    final shouldHandleApplicationScroll = _shouldHandleApplicationScroll();
    if (handlesApplicationScroll == shouldHandleApplicationScroll) return;

    handlesApplicationScroll = shouldHandleApplicationScroll;
    lastLineOffset = 0;
    horizontalScrollRemainder = 0;
    setState(() {});
  }

  bool _shouldHandleApplicationScroll() {
    return widget.terminal.isUsingAltBuffer ||
        widget.terminal.mouseMode.reportScroll;
  }

  /// Send a single scroll event to the terminal. If [simulateScroll] is true,
  /// then if the application doesn't recognize mouse wheel events, this method
  /// will simulate scroll events by sending up/down arrow keys.
  void _sendScrollEvent(bool up) {
    if (widget.readOnly ||
        !widget.terminalController
            .shouldSendPointerInput(PointerInput.scroll)) {
      _scrollMainBuffer(up);
      return;
    }

    final modifiers = _currentModifiers();
    var handled = false;
    if (!modifiers.shift ||
        (!widget.shiftOverridesMouseReporting &&
            widget.terminal.mouseShiftCaptureMode)) {
      handled = widget.sendMouseEvent(
        up ? TerminalMouseButton.wheelUp : TerminalMouseButton.wheelDown,
        TerminalMouseButtonState.down,
        lastPointerPosition,
        modifiers: modifiers,
      );
    }

    if (handled) {
      for (var i = 1; i < widget.mouseWheelSensitivity.clamp(1, 10); i++) {
        widget.sendMouseEvent(
          up ? TerminalMouseButton.wheelUp : TerminalMouseButton.wheelDown,
          TerminalMouseButtonState.down,
          lastPointerPosition,
          modifiers: modifiers,
        );
      }
      return;
    }

    if (!widget.terminal.isUsingAltBuffer) {
      _scrollMainBuffer(up);
      return;
    }

    if (widget.simulateScroll) {
      widget.terminal.keyInput(
        up ? TerminalKey.arrowUp : TerminalKey.arrowDown,
      );
    }
  }

  void _scrollMainBuffer(bool up) {
    if (widget.terminal.isUsingAltBuffer) return;

    final position = widget.getScrollPosition();
    if (position == null) return;

    final lineHeight = widget.getLineHeight();
    if (lineHeight <= 0) return;

    final delta = switch (up) {
      true => -lineHeight,
      false => lineHeight,
    };
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    position.jumpTo(target.toDouble());
  }

  void _sendHorizontalScrollEvent(bool left) {
    if (widget.readOnly ||
        !widget.terminalController
            .shouldSendPointerInput(PointerInput.scroll)) {
      return;
    }

    final modifiers = _currentModifiers();
    var handled = false;
    if (!modifiers.shift ||
        (!widget.shiftOverridesMouseReporting &&
            widget.terminal.mouseShiftCaptureMode)) {
      handled = widget.sendMouseEvent(
        switch (left) {
          true => TerminalMouseButton.wheelLeft,
          false => TerminalMouseButton.wheelRight,
        },
        TerminalMouseButtonState.down,
        lastPointerPosition,
        modifiers: modifiers,
      );
    }

    if (handled) return;
    if (!widget.terminal.isUsingAltBuffer || !widget.simulateScroll) return;

    widget.terminal.keyInput(
      switch (left) {
        true => TerminalKey.arrowLeft,
        false => TerminalKey.arrowRight,
      },
    );
  }

  TerminalMouseModifiers _currentModifiers() {
    final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
    return TerminalMouseModifiers(
      shift: pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
          pressedKeys.contains(LogicalKeyboardKey.shiftRight),
      alt: pressedKeys.contains(LogicalKeyboardKey.altLeft) ||
          pressedKeys.contains(LogicalKeyboardKey.altRight),
      control: pressedKeys.contains(LogicalKeyboardKey.controlLeft) ||
          pressedKeys.contains(LogicalKeyboardKey.controlRight),
    );
  }

  void _onScroll(double offset) {
    final currentLineOffset = offset ~/ widget.getLineHeight();

    final delta = currentLineOffset - lastLineOffset;

    for (var i = 0; i < delta.abs(); i++) {
      _sendScrollEvent(delta < 0);
    }

    lastLineOffset = currentLineOffset;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    lastPointerPosition = event.localPosition;
    if (event is! PointerScrollEvent) return;

    final delta = event.scrollDelta;
    if (delta.dx == 0 || delta.dx.abs() <= delta.dy.abs()) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _onHorizontalScroll(delta.dx);
    });
  }

  void _onHorizontalScroll(double offset) {
    final cellWidth = widget.getCellWidth();
    if (cellWidth <= 0) return;

    horizontalScrollRemainder += offset;
    final columns = (horizontalScrollRemainder / cellWidth).truncate();
    if (columns == 0) return;

    for (var index = 0; index < columns.abs(); index++) {
      _sendHorizontalScrollEvent(columns < 0);
    }
    horizontalScrollRemainder -= columns * cellWidth;
  }

  @override
  Widget build(BuildContext context) {
    if (!handlesApplicationScroll) {
      return widget.child;
    }

    final scrollbackBehavior = ScrollConfiguration.of(context).copyWith(
      physics: const NeverScrollableScrollPhysics(),
    );
    final applicationScrollBehavior = ScrollConfiguration.of(context).copyWith(
      pointerAxisModifiers: const <LogicalKeyboardKey>{},
    );
    return ScrollConfiguration(
      behavior: applicationScrollBehavior,
      child: InfiniteScrollView(
        key: ValueKey(widget.terminal),
        onScroll: _onScroll,
        child: Listener(
          onPointerSignal: _onPointerSignal,
          onPointerDown: (event) {
            lastPointerPosition = event.localPosition;
          },
          child: ScrollConfiguration(
            behavior: scrollbackBehavior,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
