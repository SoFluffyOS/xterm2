# xterm2_core

The terminal model behind [`xterm2`](https://pub.dev/packages/xterm2), in pure
Dart with no Flutter dependency: the `Terminal` state machine, screen and
scrollback buffers, VT/xterm escape-sequence parsing, and keyboard and mouse
input encoding.

Use it to run a terminal emulator where there is no UI, for example to keep a
terminal's screen on a server and redraw it for a client that reconnects.
Flutter apps should depend on `xterm2`, which renders a `Terminal` and
re-exports this package's API.

```dart
import 'package:xterm2_core/xterm2_core.dart';

final terminal = Terminal(maxLines: 10000);
terminal.write('Hello\r\n\x1b[1mbold\x1b[0m');
print(terminal.buffer.lines[0].toString()); // Hello
```

## License

MIT, see [LICENSE](LICENSE).
