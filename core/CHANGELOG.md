## 1.1.0 - 2026-11-20

* Export `UnicodeV11` and `unicodeV11`, the width table the terminal lays out
  cells with, for hosts that measure text beside it.
* Add `Terminal.synchronizedUpdateMode` and `Terminal.keyOutput`, what
  `keyInput` would send without sending it.
* Add `EscapeNarrowTextHandler`: the parser hands runs of one-cell characters
  outside ASCII to a handler that takes them in one go. Cyrillic parses about
  14 times faster.
* Answer no cell size query (`CSI 16 t`) before the cell has a size in
  pixels, instead of `0;0`, so the program asks again.
* Under modifyOtherKeys mode 2, encode only keys with Control or Alt, as xterm
  does, and leave keys to the kitty handler once kitty flags are raised.
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
