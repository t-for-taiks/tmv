part of "async.dart";

const int _isolateRunLimit = 8;

int _isolateRunCount = 0;

Completer<void>? _isolateRunSignal;

/// Call [Isolate.run] only on supported platforms
Future<T> isolateRunSimple<T>(FutureOr<T> Function() computation) async {
  if (kIsWeb) {
    return compute((_) => computation(), null);
  } else {
    return Isolate.run(computation);
  }
}

/// Call [Isolate.run] only on supported platforms
///
/// Limit number of threads to execute to [_isolateRunLimit]
///
/// Note that a job cannot be cancelled once started, because [AsyncSignal]
/// cannot be passed to another isolate
AsyncOut<T> isolateRun<T>(
  AsyncOut<T> Function() computation,
  AsyncSignal signal,
) async {
  if (kIsWeb) {
    return compute((_) => computation(), null);
  }
  if (signal.isTriggered) {
    return Err(signal);
  }
  while (_isolateRunCount >= _isolateRunLimit) {
    _isolateRunSignal ??= Completer();
    await Future.any([_isolateRunSignal!.future, signal.future]);
    if (signal.isTriggered) {
      return Err(signal);
    }
  }
  _isolateRunCount += 1;
  try {
    return await Isolate.run(computation);
  } finally {
    _isolateRunCount -= 1;
    _isolateRunSignal?.complete();
    _isolateRunSignal = null;
  }
}
