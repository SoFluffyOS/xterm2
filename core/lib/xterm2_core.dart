/// Terminal state machine, buffers and escape-sequence handling, without
/// Flutter.
library;

export 'package:xterm2_core/src/base/observable.dart';
export 'package:xterm2_core/src/core/buffer/buffer.dart';
export 'package:xterm2_core/src/core/buffer/cell_flags.dart';
export 'package:xterm2_core/src/core/buffer/cell_offset.dart';
export 'package:xterm2_core/src/core/buffer/line.dart';
export 'package:xterm2_core/src/core/buffer/range.dart';
export 'package:xterm2_core/src/core/buffer/range_block.dart';
export 'package:xterm2_core/src/core/buffer/range_line.dart';
export 'package:xterm2_core/src/core/buffer/segment.dart';
export 'package:xterm2_core/src/core/cell.dart';
export 'package:xterm2_core/src/core/color.dart';
export 'package:xterm2_core/src/core/color_scheme.dart';
export 'package:xterm2_core/src/core/cursor.dart';
export 'package:xterm2_core/src/core/escape/handler.dart';
export 'package:xterm2_core/src/core/escape/parser.dart';
export 'package:xterm2_core/src/core/input/handler.dart';
export 'package:xterm2_core/src/core/input/keys.dart';
export 'package:xterm2_core/src/core/mouse/button.dart';
export 'package:xterm2_core/src/core/mouse/button_state.dart';
export 'package:xterm2_core/src/core/mouse/handler.dart';
export 'package:xterm2_core/src/core/mouse/mode.dart';
export 'package:xterm2_core/src/core/mouse/modifiers.dart';
export 'package:xterm2_core/src/core/platform.dart';
export 'package:xterm2_core/src/core/state.dart';
export 'package:xterm2_core/src/terminal.dart';
export 'package:xterm2_core/src/terminal_search.dart';
export 'package:xterm2_core/src/utils/lookup_table.dart';
