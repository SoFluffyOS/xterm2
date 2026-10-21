import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm2_core/xterm2_core.dart';
import 'package:xterm2/src/terminal_view.dart';
import 'package:xterm2/src/ui/controller.dart';
import 'package:xterm2/src/ui/gesture/gesture_detector.dart';
import 'package:xterm2/src/ui/pointer_input.dart';
import 'package:xterm2/src/ui/render.dart';
import 'package:xterm2/src/ui/selection_mode.dart';

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
  static const _selectionScrollVelocity = 30.0;

  static const _mouseButtons = [
    (kPrimaryMouseButton, TerminalMouseButton.left),
    (kSecondaryMouseButton, TerminalMouseButton.right),
    (kMiddleMouseButton, TerminalMouseButton.middle),
    (kBackMouseButton, TerminalMouseButton.back),
    (kForwardMouseButton, TerminalMouseButton.forward),
  ];

  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  DragStartDetails? _lastDragStartDetails;

  Offset? _lastDragPosition;

  var _applicationOwnsPointerDrag = false;

  /// A primary press withheld from a tracking application until it resolves
  /// into a click (reported on release) or a drag (never reported).
  Offset? _withheldPrimaryPress;

  var _hostOwnsPrimaryDrag = false;

  final Map<int, int> _pressedMouseButtons = {};

  final Map<int, int> _reportedMouseButtons = {};

  LongPressStartDetails? _lastLongPressStartDetails;

  EdgeDraggingAutoScroller? _selectionAutoScroller;

  ScrollableState? _selectionAutoScrollerOwner;

  @override
  void dispose() {
    _stopSelectionAutoScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMotion,
      onPointerHover: _onPointerMotion,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: TerminalGestureDetector(
        child: widget.child,
        onTapUp: (details) {
          if (!_applicationHandlesTap) widget.onTapUp?.call(details);
        },
        onSingleTapUp: onSingleTapUp,
        onRepeatedTapUp: onSingleTapUp,
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
        onDragEnd: onDragEnd,
        onDragCancel: onDragCancel,
        onDoubleTapDown: onDoubleTapDown,
        onTripleTapDown: onTripleTapDown,
      ),
    );
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      !_bypassesMouseReportingWithShift &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;

    final previousButtons = _pressedMouseButtons[event.pointer] ?? 0;
    var pressedButtons = event.buttons & ~previousButtons;
    _pressedMouseButtons[event.pointer] = event.buttons;
    if (!_shouldSendTapEvent) return;

    if (pressedButtons & kPrimaryMouseButton != 0 &&
        _dragOverridesMouseReporting &&
        _applicationHandlesTap) {
      _withheldPrimaryPress = event.localPosition;
      pressedButtons &= ~kPrimaryMouseButton;
    }

    var reportedButtons = _reportedMouseButtons[event.pointer] ?? 0;
    for (final (buttonMask, terminalButton) in _mouseButtons) {
      if (pressedButtons & buttonMask == 0) continue;
      final handled = renderTerminal.mouseEvent(
        terminalButton,
        TerminalMouseButtonState.down,
        event.localPosition,
        modifiers: _currentModifiers(),
      );
      if (handled) reportedButtons |= buttonMask;
    }
    if (reportedButtons == 0) return;
    _reportedMouseButtons[event.pointer] = reportedButtons;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;

    final previousButtons = _pressedMouseButtons[event.pointer] ?? 0;
    final releasedButtons = previousButtons & ~event.buttons;
    _updatePressedMouseButtons(event.pointer, event.buttons);
    if (releasedButtons & kPrimaryMouseButton != 0) {
      _reportWithheldClick(event.localPosition);
    }
    _releaseMouseButtons(event.pointer, releasedButtons, event.localPosition);
  }

  /// A withheld press that never became a drag is a click: report the press
  /// where it happened and the release where it ended, back to back.
  void _reportWithheldClick(Offset releasePosition) {
    final pressPosition = _withheldPrimaryPress;
    _withheldPrimaryPress = null;
    if (pressPosition == null || !_shouldSendTapEvent) return;

    final modifiers = _currentModifiers();
    final handled = renderTerminal.mouseEvent(
      TerminalMouseButton.left,
      TerminalMouseButtonState.down,
      pressPosition,
      modifiers: modifiers,
    );
    if (!handled) return;
    renderTerminal.mouseEvent(
      TerminalMouseButton.left,
      TerminalMouseButtonState.up,
      releasePosition,
      modifiers: modifiers,
    );
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;

    _withheldPrimaryPress = null;
    _pressedMouseButtons.remove(event.pointer);
    final reportedButtons = _reportedMouseButtons[event.pointer] ?? 0;
    _releaseMouseButtons(
      event.pointer,
      reportedButtons,
      event.localPosition,
    );
  }

  void _updatePressedMouseButtons(int pointer, int buttons) {
    if (buttons == 0) {
      _pressedMouseButtons.remove(pointer);
      return;
    }
    _pressedMouseButtons[pointer] = buttons;
  }

  void _releaseMouseButtons(int pointer, int buttons, Offset position) {
    final reportedButtons = _reportedMouseButtons[pointer] ?? 0;
    final buttonsToRelease = reportedButtons & buttons;
    for (final (buttonMask, terminalButton) in _mouseButtons) {
      if (buttonsToRelease & buttonMask == 0) continue;
      renderTerminal.mouseEvent(
        terminalButton,
        TerminalMouseButtonState.up,
        position,
        modifiers: _currentModifiers(),
      );
    }

    final remainingButtons = reportedButtons & ~buttonsToRelease;
    if (remainingButtons == 0) {
      _reportedMouseButtons.remove(pointer);
      return;
    }
    _reportedMouseButtons[pointer] = remainingButtons;
  }

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
    // Motion under a withheld press belongs to whichever gesture it resolves
    // into, and a local selection drag is not the application's to see.
    if (input == PointerInput.drag &&
        (_withheldPrimaryPress != null || _hostOwnsPrimaryDrag)) {
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
    if (buttons & kBackMouseButton != 0) return TerminalMouseButton.back;
    if (buttons & kForwardMouseButton != 0) return TerminalMouseButton.forward;
    return TerminalMouseButton.none;
  }

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap down event.
    var handled = details.kind == PointerDeviceKind.mouse &&
        _isMouseButtonReported(button);
    if (details.kind != PointerDeviceKind.mouse && _shouldSendTapEvent) {
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
    var handled =
        details.kind == PointerDeviceKind.mouse && _applicationHandlesTap;
    if (details.kind != PointerDeviceKind.mouse && _shouldSendTapEvent) {
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

  bool _isMouseButtonReported(TerminalMouseButton button) {
    final buttonMask = switch (button) {
      TerminalMouseButton.left => kPrimaryMouseButton,
      TerminalMouseButton.right => kSecondaryMouseButton,
      TerminalMouseButton.middle => kMiddleMouseButton,
      TerminalMouseButton.back => kBackMouseButton,
      TerminalMouseButton.forward => kForwardMouseButton,
      _ => 0,
    };
    if (buttonMask == 0) return false;
    return _reportedMouseButtons.values.any(
      (reportedButtons) => reportedButtons & buttonMask != 0,
    );
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
    return widget.terminalView.widget.shiftOverridesMouseReporting ||
        !widget.terminalView.widget.terminal.mouseShiftCaptureMode;
  }

  bool get _dragOverridesMouseReporting =>
      widget.terminalView.widget.dragOverridesMouseReporting;

  /// Whether a primary-button gesture selects locally although the
  /// application tracks the mouse.
  bool get _selectsDespiteTracking =>
      _applicationHandlesTap && _dragOverridesMouseReporting;

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
    if (_applicationHandlesTap) {
      if (!_dragOverridesMouseReporting) return;
      _withheldPrimaryPress = null;
    }
    renderTerminal.selectWord(details.localPosition);
  }

  void onTripleTapDown(TapDownDetails details) {
    if (_applicationHandlesTap) {
      if (!_dragOverridesMouseReporting) return;
      _withheldPrimaryPress = null;
    }
    renderTerminal.selectLine(details.localPosition);
  }

  bool get _applicationHandlesTap {
    if (!_shouldSendTapEvent) return false;
    return widget.terminalView.widget.terminal.mouseMode != MouseMode.none;
  }

  void onLongPressStart(LongPressStartDetails details) {
    _lastLongPressStartDetails = details;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final startDetails = _lastLongPressStartDetails;
    if (startDetails == null) return;
    renderTerminal.selectWord(
      startDetails.localPosition,
      details.localPosition,
    );
  }

  // void onLongPressUp() {}

  void onDragStart(DragStartDetails details) {
    _stopSelectionAutoScroll();
    _lastDragStartDetails = details;
    _lastDragPosition = details.localPosition;
    _hostOwnsPrimaryDrag = _selectsDespiteTracking;
    if (_hostOwnsPrimaryDrag) _withheldPrimaryPress = null;
    _applicationOwnsPointerDrag =
        _applicationHandlesTap && !_hostOwnsPrimaryDrag;
    if (_applicationOwnsPointerDrag) return;

    if (details.kind != PointerDeviceKind.mouse) {
      renderTerminal.selectWord(details.localPosition);
      return;
    }

    renderTerminal.selectCharacters(
      details.localPosition,
      null,
      _dragSelectionMode,
    );
  }

  void onDragUpdate(DragUpdateDetails details) {
    _lastDragPosition = details.localPosition;
    if (_applicationOwnsPointerDrag) return;
    _updateDragSelection();
    _startSelectionAutoScroll(details.globalPosition);
  }

  void onDragEnd(DragEndDetails details) {
    _finishDragSelection();
  }

  void onDragCancel() {
    _finishDragSelection();
  }

  void _updateDragSelection() {
    final startDetails = _lastDragStartDetails;
    final dragPosition = _lastDragPosition;
    if (startDetails == null || dragPosition == null) return;
    renderTerminal.selectCharacters(
      startDetails.localPosition,
      dragPosition,
      _dragSelectionMode,
    );
  }

  void _startSelectionAutoScroll(Offset dragPosition) {
    final scrollable = terminalView.scrollableState;
    if (scrollable == null) return;

    if (_selectionAutoScrollerOwner != scrollable) {
      _selectionAutoScroller?.stopAutoScroll();
      _selectionAutoScrollerOwner = scrollable;
      _selectionAutoScroller = EdgeDraggingAutoScroller(
        scrollable,
        velocityScalar: _selectionScrollVelocity,
        onScrollViewScrolled: _updateDragSelection,
      );
    }

    _selectionAutoScroller?.startAutoScrollIfNecessary(
      Rect.fromCenter(center: dragPosition, width: 0, height: 0),
    );
  }

  void _finishDragSelection() {
    _stopSelectionAutoScroll();
    _applicationOwnsPointerDrag = false;
    _hostOwnsPrimaryDrag = false;
    _lastDragStartDetails = null;
    _lastDragPosition = null;
  }

  void _stopSelectionAutoScroll() {
    _selectionAutoScroller?.stopAutoScroll();
  }

  SelectionMode get _dragSelectionMode {
    final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
    final altPressed = pressedKeys.contains(LogicalKeyboardKey.altLeft) ||
        pressedKeys.contains(LogicalKeyboardKey.altRight);
    return switch (altPressed) {
      true => SelectionMode.block,
      false => SelectionMode.line,
    };
  }
}
