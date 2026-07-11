import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm2/src/core/mouse/button.dart';
import 'package:xterm2/src/core/mouse/button_state.dart';
import 'package:xterm2/src/core/mouse/mode.dart';
import 'package:xterm2/src/core/mouse/modifiers.dart';
import 'package:xterm2/src/terminal_view.dart';
import 'package:xterm2/src/ui/controller.dart';
import 'package:xterm2/src/ui/gesture/gesture_detector.dart';
import 'package:xterm2/src/ui/pointer_input.dart';
import 'package:xterm2/src/ui/render.dart';

class TerminalGestureHandler extends StatefulWidget {
  const TerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onSingleTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
  });

  final TerminalViewState terminalView;

  final TerminalController terminalController;

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final bool readOnly;

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  DragStartDetails? _lastDragStartDetails;

  LongPressStartDetails? _lastLongPressStartDetails;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerMove: _onPointerMotion,
      onPointerHover: _onPointerMotion,
      child: TerminalGestureDetector(
        child: widget.child,
        onTapUp: widget.onTapUp,
        onSingleTapUp: onSingleTapUp,
        onTapDown: onTapDown,
        onSecondaryTapDown: onSecondaryTapDown,
        onSecondaryTapUp: onSecondaryTapUp,
        onTertiaryTapDown: onTertiaryTapDown,
        onTertiaryTapUp: onTertiaryTapUp,
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        // onLongPressUp: onLongPressUp,
        onDragStart: onDragStart,
        onDragUpdate: onDragUpdate,
        onDoubleTapDown: onDoubleTapDown,
      ),
    );
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      !_bypassesMouseReportingWithShift &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  void _onPointerMotion(PointerEvent event) {
    final input = switch (event.buttons) {
      0 => PointerInput.move,
      _ => PointerInput.drag,
    };
    if (widget.readOnly ||
        _bypassesMouseReportingWithShift ||
        !widget.terminalController.shouldSendPointerInput(input)) {
      return;
    }

    renderTerminal.mouseEvent(
      _buttonForButtons(event.buttons),
      TerminalMouseButtonState.down,
      event.localPosition,
      motion: true,
      modifiers: _currentModifiers(),
    );
  }

  TerminalMouseButton _buttonForButtons(int buttons) {
    if (buttons & kPrimaryMouseButton != 0) return TerminalMouseButton.left;
    if (buttons & kSecondaryMouseButton != 0) return TerminalMouseButton.right;
    if (buttons & kMiddleMouseButton != 0) return TerminalMouseButton.middle;
    return TerminalMouseButton.none;
  }

  bool get _terminalReportsDrag {
    if (widget.readOnly ||
        _bypassesMouseReportingWithShift ||
        !widget.terminalController.shouldSendPointerInput(PointerInput.drag)) {
      return false;
    }
    return switch (widget.terminalView.widget.terminal.mouseMode) {
      MouseMode.upDownScrollDrag || MouseMode.upDownScrollMove => true,
      _ => false,
    };
  }

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap down event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
        modifiers: _currentModifiers(),
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap up event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
        modifiers: _currentModifiers(),
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  TerminalMouseModifiers _currentModifiers() {
    final shift = _isShiftPressed;
    final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
    return TerminalMouseModifiers(
      shift: shift,
      alt: pressedKeys.contains(LogicalKeyboardKey.altLeft) ||
          pressedKeys.contains(LogicalKeyboardKey.altRight),
      control: pressedKeys.contains(LogicalKeyboardKey.controlLeft) ||
          pressedKeys.contains(LogicalKeyboardKey.controlRight),
    );
  }

  bool get _isShiftPressed {
    final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
    return pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
        pressedKeys.contains(LogicalKeyboardKey.shiftRight);
  }

  bool get _bypassesMouseReportingWithShift {
    if (!_isShiftPressed) return false;
    return !widget.terminalView.widget.terminal.mouseShiftCaptureMode;
  }

  void onTapDown(TapDownDetails details) {
    // onTapDown is special, as it will always call the supplied callback.
    // The TerminalView depends on it to bring the terminal into focus.
    _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );
  }

  void onSingleTapUp(TapUpDetails details) {
    _tapUp(widget.onSingleTapUp, details, TerminalMouseButton.left);
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.middle);
  }

  void onDoubleTapDown(TapDownDetails details) {
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressStart(LongPressStartDetails details) {
    _lastLongPressStartDetails = details;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    renderTerminal.selectWord(
      _lastLongPressStartDetails!.localPosition,
      details.localPosition,
    );
  }

  // void onLongPressUp() {}

  void onDragStart(DragStartDetails details) {
    _lastDragStartDetails = details;
    if (_terminalReportsDrag) return;

    details.kind == PointerDeviceKind.mouse
        ? renderTerminal.selectCharacters(details.localPosition)
        : renderTerminal.selectWord(details.localPosition);
  }

  void onDragUpdate(DragUpdateDetails details) {
    if (_terminalReportsDrag) return;
    renderTerminal.selectCharacters(
      _lastDragStartDetails!.localPosition,
      details.localPosition,
    );
  }
}
