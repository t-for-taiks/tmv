part of "async.dart";

typedef AsyncExecutor0<Out> = AsyncOut<Out> Function(AsyncSignal signal);
typedef AsyncExecutor1<In1, Out> = AsyncOut<Out> Function(
  In1 value,
  AsyncSignal signal,
);
typedef AsyncExecutor2<In1, In2, Out> = AsyncOut<Out> Function(
  In1 value1,
  In2 value2,
  AsyncSignal signal,
);
typedef AsyncExecutor3<In1, In2, In3, Out> = AsyncOut<Out> Function(
  In1 value1,
  In2 value2,
  In3 value3,
  AsyncSignal signal,
);
typedef AsyncExecutor4<In1, In2, In3, In4, Out> = AsyncOut<Out> Function(
  In1 value1,
  In2 value2,
  In3 value3,
  In4 value4,
  AsyncSignal signal,
);
typedef AsyncExecutor5<In1, In2, In3, In4, In5, Out> = AsyncOut<Out> Function(
  In1 value1,
  In2 value2,
  In3 value3,
  In4 value4,
  In5 value5,
  AsyncSignal signal,
);

typedef AsyncOut<T> = FutureOr<Result<T>>;

extension AsyncExecution<Out> on AsyncExecutor0<Out> {
  /// Execute a function with input and signal
  Async<Out> execute([AsyncSignal? signal]) {
    final async = Async<Out>((signal) => this(signal));
    async.signal = signal ?? async.signal;
    return async;
  }

  /// Chain the function with another function (but not executing yet)
  AsyncExecutor0<X> chain<X>(AsyncExecutor1<Out, X> function) =>
      (signal) => execute(signal).chain(function);
}

extension AsyncExecution1<In1, Out> on AsyncExecutor1<In1, Out> {
  /// Execute a function with input and signal
  Async<Out> execute(In1 value, [AsyncSignal? signal]) {
    final async = Async<Out>((signal) => this(value, signal));
    async.signal = signal ?? async.signal;
    return async;
  }

  /// Bind argument of the function into [AsyncExecutor0]
  AsyncExecutor0<Out> bind(In1 value) => (signal) => execute(value, signal);
}

extension AsyncExecution2<In1, In2, Out> on AsyncExecutor2<In1, In2, Out> {
  /// Execute a function with input and signal
  Async<Out> execute(In1 value1, In2 value2, [AsyncSignal? signal]) {
    final async = Async<Out>((signal) => this(value1, value2, signal));
    async.signal = signal ?? async.signal;
    return async;
  }

  /// Bind arguments of the function into [AsyncExecutor0]
  AsyncExecutor0<Out> bind(In1 value1, In2 value2) =>
      (signal) => execute(value1, value2, signal);
}

extension AsyncExecution3<In1, In2, In3, Out>
    on AsyncExecutor3<In1, In2, In3, Out> {
  /// Execute a function with input and signal
  Async<Out> execute(In1 value1, In2 value2, In3 value3,
      [AsyncSignal? signal]) {
    final async = Async<Out>((signal) => this(value1, value2, value3, signal));
    async.signal = signal ?? async.signal;
    return async;
  }

  /// Bind arguments of the function into [AsyncExecutor0]
  AsyncExecutor0<Out> bind(In1 value1, In2 value2, In3 value3) =>
      (signal) => execute(value1, value2, value3, signal);
}

extension AsyncExecution4<In1, In2, In3, In4, Out>
    on AsyncExecutor4<In1, In2, In3, In4, Out> {
  /// Execute a function with input and signal
  Async<Out> execute(In1 value1, In2 value2, In3 value3, In4 value4,
      [AsyncSignal? signal]) {
    final async =
        Async<Out>((signal) => this(value1, value2, value3, value4, signal));
    async.signal = signal ?? async.signal;
    return async;
  }

  /// Bind arguments of the function into [AsyncExecutor0]
  AsyncExecutor0<Out> bind(In1 value1, In2 value2, In3 value3, In4 value4) =>
      (signal) => execute(value1, value2, value3, value4, signal);
}

extension AsyncExecution5<In1, In2, In3, In4, In5, Out>
    on AsyncExecutor5<In1, In2, In3, In4, In5, Out> {
  /// Execute a function with input and signal
  Async<Out> execute(In1 value1, In2 value2, In3 value3, In4 value4, In5 value5,
      [AsyncSignal? signal]) {
    final async = Async<Out>(
        (signal) => this(value1, value2, value3, value4, value5, signal));
    async.signal = signal ?? async.signal;
    return async;
  }

  /// Bind arguments of the function into [AsyncExecutor0]
  AsyncExecutor0<Out> bind(
          In1 value1, In2 value2, In3 value3, In4 value4, In5 value5) =>
      (signal) => execute(value1, value2, value3, value4, value5, signal);
}

extension UnwrapAsync<T> on Async<Result<T>> {
  /// Unwrap the result of an [Async] of [Result]
  Async<T> get unwrapped => map((value) => value.value);
}

/// Shortcut to execute [Async] functions without signal
/// (because there's no signal in [Future])
extension FutureAsyncExtension<T> on FutureOr<Result<T>> {
  /// Create Async
  Async<X> chainAction<X>(AsyncOut<X> Function(T) function,
          {Object? debugInfo}) =>
      Async<T>.value(this).chain((value, signal) => function(value));

  FutureOr<Result<T>> whenDone(void Function() action) async {
    if (this is Future<Result<T>>) {
      return (this as Future<Result<T>>).whenComplete(action);
    }
    action();
    return this;
  }

  Async<T> asAsync(AsyncSignal signal) {
    if (this is Future<Result<T>>) {
      final async = Async<T>.value(this);
      async.signal = signal;
      return async;
    }
    return Async._build(value: this as Result<T>, signal: signal);
  }

  Future<Result<T>> get asFuture {
    if (this is Future<Result<T>>) {
      return this as Future<Result<T>>;
    }
    return Future.value(this);
  }

  /// Create Async and then call [Async.map]
  Async<X> map<X>(X Function(T value) function) =>
      Async<T>.value(this).map(function);

  /// Convert to a future that throws error if the result is [Err]
  Future<T> throwErr() async {
    final Result<T> result;
    if (this is Async<T> && (this as Async).isCompleted) {
      result = (this as Async<T>).value;
    } else {
      result = await this;
    }
    if (result is Err) {
      throw result;
    }
    return result.value;
  }

  Future<T?> valueOrNull() async {
    final Result<T> result;
    if (this is Async<T> && (this as Async).isCompleted) {
      result = (this as Async<T>).value;
    } else {
      result = await this;
    }
    if (result is Err) {
      return null;
    }
    return result.value;
  }
}

class LimitedExecution {
  final int threadLimit;

  int threadCount = 0;

  Completer<void>? readySignal;

  LimitedExecution(int? threadLimit) : threadLimit = threadLimit ?? 8;

  Future<Result<T>> execute<T>(
      AsyncExecutor0<T> computation, AsyncSignal signal) async {
    while (threadCount >= threadLimit) {
      readySignal ??= Completer();
      await Future.any([readySignal!.future, signal.future]);
      if (signal.isTriggered) {
        return Err(signal);
      }
    }
    threadCount += 1;
    try {
      return await computation(signal);
    } finally {
      threadCount -= 1;
      readySignal?.complete();
      readySignal = null;
    }
  }
}

extension ExecutorLimitedExecution<T> on Iterable<AsyncExecutor0<T>> {
  /// Execute a list of functions with limited thread count
  ///
  /// Results are not filtered and will be in random order
  Stream<Result<T>> executeLimited([AsyncSignal? signal, int? threadLimit]) {
    final limit = LimitedExecution(threadLimit);
    return Stream.fromFutures(
      map((computation) => limit.execute(computation, signal ?? AsyncSignal())),
    );
  }

  /// Execute a list of functions in order (no parallel)
  Stream<Result<T>> executeOrdered([AsyncSignal? signal]) async* {
    for (final computation in this) {
      yield await computation(signal ?? AsyncSignal());
    }
  }

  /// Execute until the first success
  Async<T> firstOk([AsyncSignal? signal]) => Async<T>((signal) async {
        for (final computation in this) {
          final result = await computation(signal);
          if (result is Ok) {
            return result;
          }
        }
        return Err("No success", signal);
      });
}
