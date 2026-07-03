import 'package:test/test.dart';
import 'package:xterm/src/base/disposable.dart';
import 'package:xterm/src/base/event.dart';

void main() {
  test('Disposable invokes registered callbacks once', () {
    final disposable = _TestDisposable();
    var calls = 0;
    disposable.registerCallback(() => calls++);

    disposable.dispose();
    disposable.dispose();

    expect(calls, 1);
    expect(disposable.disposed, isTrue);
  });

  test('EventSubscription disposal is idempotent', () {
    final emitter = EventEmitter<int>();
    var calls = 0;
    final subscription = emitter((_) => calls++);

    subscription.dispose();
    subscription.dispose();
    emitter.emit(1);

    expect(calls, 0);
    expect(subscription.disposed, isTrue);
  });
}

class _TestDisposable with Disposable {}
