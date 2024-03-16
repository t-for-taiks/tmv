part of 'async.dart';

typedef ProgressCallback = void Function(double current, double total);

/// Object passed to every [Async] call, providing more features
/// - interrupt an Async
/// - show progress
class AsyncSignal {
  Completer<void> signal = Completer.sync();

  Object? debugInfo;

  /// Callback for progress update
  final progressCallbackList = <ProgressCallback>[];

  /// Progress total
  double total = 1;

  /// Progress current
  double current = 0;

  /// Progress ratio 0-1
  double get ratio => current / total;

  String get percentage => "${(ratio * 100).toStringAsFixed(0)}%";

  AsyncSignal({this.debugInfo}) {
    debugInfo ??= _getCaller();
  }

  bool get isTriggered => signal.isCompleted;

  Future get future => signal.future;

  void trigger() {
    if (!signal.isCompleted) {
      signal.complete(null);
    }
  }

  /// Update progress
  void setProgress({double? current, double? total}) {
    this.current = current ?? this.current;
    this.total = total ?? this.total;
    for (final callback in progressCallbackList) {
      callback(this.current, this.total);
    }
  }

  void addProgressListener(ProgressCallback callback) {
    progressCallbackList.add(callback);
  }

  @override
  String toString() => "${describeIdentity(this)}: $debugInfo";
}
