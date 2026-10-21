mixin Observable {
  final listeners = <void Function()>{};

  void addListener(void Function() listener) {
    listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    listeners.remove(listener);
  }

  void clearListeners() {
    listeners.clear();
  }

  void notifyListeners() {
    for (final listener in listeners.toList()) {
      listener();
    }
  }
}
