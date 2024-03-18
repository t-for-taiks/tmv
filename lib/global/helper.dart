sealed class Priority implements Comparable<Priority> {
  final int value;

  const Priority(this.value);

  @override
  int compareTo(Priority other) => -value.compareTo(other.value);

  /// Shortcut to create a [HighPriority] object
  static Priority get high => HighPriority();

  /// Shortcut to create a [NormalPriority] object
  static Priority get normal => NormalPriority();

  /// Shortcut to create a [LowPriority] object
  static const Priority low = LowPriority();
}

/// Newer objects of this class will have higher priority
/// (last come first serve)
class HighPriority extends Priority {
  static int counter = 1;

  HighPriority() : super(counter += 1);
}

/// Newer objects of this class will have lower priority
/// (first come first serve)
class NormalPriority extends Priority {
  static int counter = 0;

  NormalPriority() : super(counter -= 1);
}

/// Objects of this class will have same priority
class LowPriority extends Priority {
  const LowPriority() : super(-0x1000000000000);
}

mixin SignalEmitter<T> {
  final listeners = <bool Function(T, SignalEmitter<T>)>[];

  /// Add a listener to the signal, when the listener returns false, it will be
  /// removed
  void addListener(bool Function(T, SignalEmitter<T>) listener) =>
      listeners.add(listener);

  void notifyListeners(T signal) {
    listeners.retainWhere((listener) => listener(signal, this));
  }
}
