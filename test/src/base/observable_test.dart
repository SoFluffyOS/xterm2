import 'package:test/test.dart';
import 'package:xterm2/src/base/observable.dart';

void main() {
  test('Observable allows listeners to unsubscribe during notification', () {
    final observable = _TestObservable();
    final calls = <int>[];

    void firstListener() {
      calls.add(1);
      observable.removeListener(firstListener);
    }

    observable.addListener(firstListener);
    observable.addListener(() => calls.add(2));

    observable.notifyListeners();
    observable.notifyListeners();

    expect(calls, [1, 2, 2]);
  });
}

class _TestObservable with Observable {}
