enum TerminalMouseButton {
  left(id: 0),

  middle(id: 1),

  right(id: 2),

  none(id: 3),

  wheelUp(id: 64, isWheel: true),

  wheelDown(id: 65, isWheel: true),

  wheelLeft(id: 66, isWheel: true),

  wheelRight(id: 67, isWheel: true),
  ;

  /// The id that is used to report a button press or release to the terminal.
  ///
  /// Mouse wheel directions use protocol button IDs 64 through 67.
  final int id;

  /// Whether this button is a mouse wheel button.
  final bool isWheel;

  const TerminalMouseButton({required this.id, this.isWheel = false});
}
