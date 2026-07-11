import 'package:xterm2/src/base/event.dart';

mixin Disposable {
  final _disposables = <Disposable>[];

  bool get disposed => _disposed;
  bool _disposed = false;

  Event get onDisposed => _onDisposed.event;
  final _onDisposed = EventEmitter();

  void register(Disposable disposable) {
    assert(!_disposed);
    _disposables.add(disposable);
  }

  void registerCallback(void Function() callback) {
    assert(!_disposed);
    _disposables.add(_DisposeCallback(callback));
  }

  void dispose() {
    if (_disposed) return;

    _disposed = true;
    for (final disposable in _disposables) {
      disposable.dispose();
    }
    _disposables.clear();
    _onDisposed.emit(null);
  }
}

class _DisposeCallback with Disposable {
  final void Function() callback;

  _DisposeCallback(this.callback);

  @override
  void dispose() {
    if (disposed) return;

    super.dispose();
    callback();
  }
}
