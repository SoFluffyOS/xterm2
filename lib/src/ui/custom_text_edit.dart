import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextEdit extends StatefulWidget {
  CustomTextEdit({
    super.key,
    required this.child,
    required this.onInsert,
    required this.onDelete,
    required this.onComposing,
    required this.onAction,
    required this.onKeyEvent,
    this.onSelector,
    required this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    // this.initEditingState = TextEditingValue.empty,
    int? viewId,
    this.inputType = TextInputType.text,
    this.inputAction = TextInputAction.newline,
    this.keyboardAppearance = Brightness.light,
    this.deleteDetection = false,
  }) : viewId = viewId ?? PlatformDispatcher.instance.implicitView?.viewId {
    if (this.viewId == null) {
      throw Exception('Cannot open input connection without a valid viewId.');
    }
  }

  final Widget child;

  final void Function(String) onInsert;

  final void Function() onDelete;

  final void Function(String?) onComposing;

  final void Function(TextInputAction) onAction;

  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  /// A macOS editing command, such as `moveLeft:`: what a key still has to
  /// do after it ended a composition, as the key itself never arrives.
  final void Function(String selector)? onSelector;

  final FocusNode focusNode;

  final bool autofocus;

  final bool readOnly;

  final TextInputType inputType;

  final TextInputAction inputAction;

  final Brightness keyboardAppearance;

  final bool deleteDetection;

  final int? viewId;

  @override
  CustomTextEditState createState() => CustomTextEditState();
}

class CustomTextEditState extends State<CustomTextEdit> with TextInputClient {
  TextInputConnection? _connection;

  @override
  void initState() {
    widget.focusNode.addListener(_onFocusChange);
    super.initState();
  }

  @override
  void didUpdateWidget(CustomTextEdit oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }

    if (!_shouldCreateInputConnection) {
      _closeInputConnectionIfNeeded();
    } else {
      if (oldWidget.readOnly && widget.focusNode.hasFocus) {
        _openInputConnection();
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _closeInputConnectionIfNeeded();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }

  bool get hasInputConnection => _connection != null && _connection!.attached;

  void requestKeyboard() {
    if (widget.focusNode.hasFocus) {
      _openInputConnection();
    } else {
      widget.focusNode.requestFocus();
    }
  }

  void closeKeyboard() {
    if (hasInputConnection) {
      _connection?.close();
    }
  }

  void setEditingState(TextEditingValue value) {
    _currentEditingState = value;
    _connection?.setEditingState(value);
  }

  void setEditableRect(Rect rect, Rect caretRect) {
    if (!hasInputConnection) {
      return;
    }

    _connection?.setEditableSizeAndTransform(
      rect.size,
      Matrix4.translationValues(0, 0, 0),
    );

    _connection?.setCaretRect(caretRect);
  }

  void _onFocusChange() {
    if (!widget.focusNode.hasFocus) {
      _discardComposing();
    }
    _openOrCloseInputConnectionIfNeeded();
  }

  KeyEventResult _onKeyEvent(FocusNode focusNode, KeyEvent event) {
    if (!_currentEditingState.composing.isCollapsed) {
      return KeyEventResult.skipRemainingHandlers;
    }

    final result = widget.onKeyEvent(focusNode, event);
    if (result == KeyEventResult.handled) {
      _resetEditingState();
    }
    return result;
  }

  void _openOrCloseInputConnectionIfNeeded() {
    if (widget.focusNode.hasFocus && widget.focusNode.consumeKeyboardToken()) {
      _openInputConnection();
    } else if (!widget.focusNode.hasFocus) {
      _closeInputConnectionIfNeeded();
    }
  }

  bool get _shouldCreateInputConnection => kIsWeb || !widget.readOnly;

  void _openInputConnection() {
    if (!_shouldCreateInputConnection) {
      return;
    }

    if (hasInputConnection) {
      _connection!.show();
    } else {
      final config = TextInputConfiguration(
        viewId: widget.viewId,
        inputType: widget.inputType,
        inputAction: widget.inputAction,
        keyboardAppearance: widget.keyboardAppearance,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
      );

      _connection = TextInput.attach(this, config);

      _connection!.show();

      // setEditableRect(Rect.zero, Rect.zero);

      _currentEditingState = _initEditingState;
      _sent = '';
      _connection!.setEditingState(_initEditingState);
    }
  }

  void _closeInputConnectionIfNeeded() {
    if (_connection != null && _connection!.attached) {
      _connection!.close();
      _connection = null;
    }
  }

  TextEditingValue get _initEditingState => widget.deleteDetection
      ? const TextEditingValue(
          text: '  ',
          selection: TextSelection.collapsed(offset: 2),
        )
      : const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        );

  late var _currentEditingState = _initEditingState.copyWith();

  @override
  TextEditingValue? get currentTextEditingValue {
    return _currentEditingState;
  }

  @override
  AutofillScope? get currentAutofillScope {
    return null;
  }

  /// The committed text sent to the terminal since the editing text was
  /// last cleared.
  ///
  /// An input method that commits one syllable as it starts the next, as
  /// Korean does, keeps composing: what it committed is sent at once
  /// instead of waiting for the whole word. Tracked by content, so text an
  /// input method rewrote after committing it is sent again.
  String _sent = '';

  /// The editing text is cleared past this length, when nothing is being
  /// composed, so it doesn't grow without end between keys the terminal
  /// handles itself.
  static const _maximumEditingLength = 4096;

  /// Whether the editing text is kept until the input method is idle,
  /// instead of cleared after each commit: on desktop systems, whose input
  /// methods compose from the keys the terminal leaves them.
  ///
  /// Clearing after each commit races such an input method: a Korean one
  /// commits a syllable and starts the next as two updates from one key,
  /// and a clear arriving between them sends the syllable twice and drops
  /// the next one's first letter. Phones' keyboards and [deleteDetection]
  /// rely on the clear, so they keep it.
  bool get _keepsEditingText {
    if (kIsWeb || widget.deleteDetection) {
      return false;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    _currentEditingState = value;

    if (!_keepsEditingText) {
      _updateClearingEachCommit(value);
      return;
    }

    final text = value.text;
    final composing = value.composing;
    final isComposing = composing.isValid && !composing.isCollapsed;
    final committedEnd = switch (isComposing) {
      true => composing.start,
      false => text.length,
    };
    final initLength = _initEditingState.text.length;
    final committed = switch (committedEnd < initLength) {
      true => '',
      false => text.substring(initLength, committedEnd),
    };

    _sendCommitted(committed);
    widget.onComposing(switch (isComposing) {
      true => composing.textInside(text),
      false => null,
    });

    if (!isComposing && text.length > _maximumEditingLength) {
      _resetEditingState();
    }
  }

  void _updateClearingEachCommit(TextEditingValue value) {
    if (!value.composing.isCollapsed) {
      widget.onComposing(value.composing.textInside(value.text));
      return;
    }

    widget.onComposing(null);

    if (value.text.length < _initEditingState.text.length) {
      widget.onDelete();
    } else {
      final inserted = value.text.substring(_initEditingState.text.length);
      if (inserted.isNotEmpty) {
        widget.onInsert(inserted);
      }
    }

    if (value.text != _initEditingState.text) {
      _resetEditingState();
    }
  }

  /// Sends what [committed] adds to the text sent already, after a delete
  /// for each character of that text it no longer has.
  void _sendCommitted(String committed) {
    if (committed == _sent) {
      return;
    }

    final sentRunes = _sent.runes.toList();
    final committedRunes = committed.runes.toList();
    var kept = 0;
    while (kept < sentRunes.length &&
        kept < committedRunes.length &&
        sentRunes[kept] == committedRunes[kept]) {
      kept++;
    }

    _sent = committed;
    for (var removed = kept; removed < sentRunes.length; removed++) {
      widget.onDelete();
    }
    if (kept < committedRunes.length) {
      widget.onInsert(String.fromCharCodes(committedRunes.sublist(kept)));
    }
  }

  void _resetEditingState() {
    _sent = '';
    if (_currentEditingState.text == _initEditingState.text) {
      return;
    }

    _currentEditingState = _initEditingState;
    _connection?.setEditingState(_initEditingState);
  }

  /// Drops what the input method was composing, unsent, as the terminal
  /// loses the keyboard.
  void _discardComposing() {
    final composing = _currentEditingState.composing;
    if (composing.isValid && !composing.isCollapsed) {
      widget.onComposing(null);
    }

    _sent = '';
    _currentEditingState = _initEditingState;
  }

  @override
  void performSelector(String selectorName) {
    // A key pressed while composing is the input method's.
    if (!_currentEditingState.composing.isCollapsed) {
      return;
    }

    widget.onSelector?.call(selectorName);
    _resetEditingState();
  }

  @override
  void performAction(TextInputAction action) {
    widget.onAction(action);
    if (_keepsEditingText) {
      _resetEditingState();
    }
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    // print('updateFloatingCursor $point');
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    // print('showAutocorrectionPromptRect');
  }

  @override
  void connectionClosed() {
    _discardComposing();
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    // print('performPrivateCommand $action');
  }

  @override
  void insertTextPlaceholder(Size size) {
    // print('insertTextPlaceholder');
  }

  @override
  void removeTextPlaceholder() {
    // print('removeTextPlaceholder');
  }

  @override
  void showToolbar() {
    // print('showToolbar');
  }
}
