import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../log.dart';

part 'async_ext.dart';
part 'async_signal.dart';
part 'isolate_run.dart';
part 'result.dart';

/// Get the caller of the current function outside of this library
String _getCaller() {
  final stack = StackTrace.current.toString().split("\n");
  final caller = stack.firstWhere((element) => !element.contains("async/"));
  return caller;
}

/// Future with complete flag and synchronous retrieval of completed value
class Async<T> implements Future<Result<T>> {
  Result<T> value = const Na();
  Future<Result<T>>? future;
  Completer<Result<T>>? completer;
  AsyncSignal signal = AsyncSignal();

  bool get isCompleted => value.completed;

  bool get isSuccessful => value is Ok;

  T get unwrap => value.value;

  T? get unwrapOrNull => value.valueOrNull;

  /// Note: cancel after completion is ignored
  bool get isCancelled => !isCompleted && signal.isTriggered;

  void _recordNull() {
    value = Ok(null as T);
    future = null;
    completer = null;
  }

  Result<T> _recordValue(Result<T> value) {
    this.value = value;
    future = null;
    completer = null;
    return value;
  }

  /// Similar to Future()
  Async(FutureOr<Result<T>> Function(AsyncSignal signal) function,
      {Object? debugInfo, AsyncSignal? signal}) {
    this.signal = signal ?? this.signal;
    future = Future(() async {
      if (this.signal.isTriggered) {
        return Err(this.signal);
      }
      final result = await function(this.signal);
      _recordValue(result);
      return result;
    });
  }

  Async._build({
    this.value = const Na(),
    this.future,
    this.completer,
    AsyncSignal? signal,
  }) : signal = signal ?? AsyncSignal();

  /// Similar to Future.sync(), where function is immediately called
  Async.sync(AsyncExecutor0<T> function, {Object? debugInfo}) {
    final result = function(signal);
    if (result is Result<T>) {
      value = result;
    } else {
      future = result.then(_recordValue);
    }
  }

  Async.completer() {
    completer = Completer();
    future = completer!.future.then(_recordValue);
  }

  /// Same as Future.value()
  Async.value(dynamic value) {
    // Note that T can be void or Object, so we need to check for narrower
    // types first
    if (value is Future<Result<T>>) {
      future = value.then(_recordValue);
    } else if (value is Future<T>) {
      future = value.then((v) => _recordValue(Ok(v)));
    } else if (value is Result<T>) {
      this.value = value;
    } else if (value is T) {
      this.value = Ok(value);
    } else {
      log.w("Invalid value type: ${describeIdentity(value)}");
      throw UnimplementedError();
    }
  }

  /// If Async is initialized as a completer, this will complete it
  Future<void> complete(FutureOr<dynamic> value) async {
    if (value is Future) {
      return complete(await value);
    } else if (value is Result<T>) {
      if (completer != null) {
        completer!.complete(value);
        _recordValue(value);
      }
    } else if (value is T) {
      if (completer != null) {
        completer!.complete(Ok(value));
        _recordValue(Ok(value));
      }
    } else {
      throw UnimplementedError(
        "Invalid value type: ${describeIdentity(value)}",
      );
    }
  }

  /// If Async is initialized as a completer, this will complete it
  void completeOk(T value) => complete(Ok(value));

  Async<T> withInfo(Object? debugInfo) {
    signal.debugInfo = debugInfo ?? debugInfo;
    return this;
  }

  /// If Async is initialized as a completer, this will complete it
  void complete_() {
    completer?.complete(Ok(null as T));
    _recordNull();
  }

  /// Tell an async to terminate
  Future<void> cancel() async {
    if (isCompleted) {
      return;
    }
    signal.trigger();
    await future;
    _recordValue(Err(signal));
  }

  /// Used in await, but shouldn't be used explicitly
  @override
  Future<X> then<X>(FutureOr<X> Function(Result<T> value) onValue,
      {Function? onError}) {
    if (isCompleted) {
      return Future.value(value).then(onValue, onError: onError);
    }
    return future!.then(onValue, onError: onError);
  }

  /// Future.then()
  ///
  /// If [or] is provided, it will be executed if [function] results in Err
  ///
  /// Note that this returns a new [Async] object (because the return type
  /// is changed)
  Async<X> chain<X>(AsyncExecutor1<T, X> function, {AsyncExecutor1<T, X>? or}) {
    if (isCompleted && value.failed) {
      return Async.value(Err(signal).cast<X>());
    }
    return Async(
      (signal) async {
        if (signal.isTriggered) {
          return Err(signal);
        }
        final value = isCompleted ? this.value : await this;
        if (value.failed) {
          return value.cast();
        }
        var result = await function(value.value, signal);
        if (result.failed && or != null) {
          result = await or(value.value, signal);
        }
        return result;
      },
      signal: signal,
    );
  }

  /// Chain an action that executes when this async fails
  Async<T> onFail(AsyncExecutor1<Result<T>, T> function, {Object? debugInfo}) {
    if (isCompleted) {
      if (value.failed) {
        return Async(function.bind(value));
      } else {
        return this;
      }
    }
    return Async<T>((signal) async {
      final value = await this;
      if (value.failed) {
        return await function(value, signal);
      }
      return value;
    }, signal: signal, debugInfo: debugInfo);
  }

  /// Do a synchronous action when successful
  @override
  Async<T> whenComplete(void Function() action) {
    if (isCompleted && value is Ok) {
      action();
      return this;
    }
    future = future!.then((value) {
      if (value is Ok) {
        action();
      }
      return value;
    });
    return this;
  }

  /// Chain a synchronous action
  ///
  /// Note that this returns a new [Async] object (because the return type
  /// is changed)
  Async<X> map<X>(X Function(T value) function) {
    if (isCompleted && value.failed) {
      return Async<X>.value(value.cast());
    }
    return Async<X>((signal) async {
      final value = isCompleted ? this.value : await this;
      if (value.failed) {
        return value.cast();
      }
      return Ok(function(value.value));
    }, signal: signal);
  }

  Async<T> logFail([String? tag]) {
    return onFail((result, signal) {
      log.t((tag ?? "Async", result));
      return result;
    });
  }

  @override
  Stream<Result<T>> asStream() {
    // TODO: implement asStream
    throw UnimplementedError();
  }

  @override
  Async<T> catchError(Function onError, {bool Function(Object error)? test}) {
    if (isCompleted) {
      return this;
    }
    future = future!.catchError(onError, test: test).then(_recordValue);
    return this;
  }

  @override
  Async<T> timeout(Duration timeLimit, {AsyncOut<T> Function()? onTimeout}) {
    if (!isCompleted) {
      future = future!.timeout(timeLimit, onTimeout: () async {
        final result = onTimeout?.call();
        if (result != null) {
          return await result;
        }
        return Err();
      }).then(_recordValue);
    }
    return this;
  }
}

/// Exception to be thrown inside [AsyncCancellable]
class AsyncCancelException implements Exception {
  final String message;

  const AsyncCancelException([this.message = ""]);

  @override
  String toString() => "ACE($message)";
}
