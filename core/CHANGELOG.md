## Unreleased

* Keep a soft-wrapped row joined to the row above when the line is erased
  from it (`EL`), as xterm does: erasing ends the line at that row instead.
  A long command zsh redraws row by row no longer copies with a line break in
  the middle.
* Report mouse motion once per cell, as the pointer crosses into it, instead
  of on every pointer event inside the same cell.

## 1.0.0 - 2026-10-21

* First release: the terminal model of `xterm2` 5.4.0 (state machine, buffers,
  VT/xterm escape-sequence parsing, input and mouse encoding) as a pure-Dart
  package without Flutter.
