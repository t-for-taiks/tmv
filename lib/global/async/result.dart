part of 'async.dart';

/// Enum class to hold [Async] results
sealed class Result<T> {
  const Result();

  /// Unwrap value
  T get value {
    if (this is Ok) {
      return (this as Ok).result as T;
    }
    throw this;
  }

  bool get failed => this is! Ok;

  bool get completed => this is! Na;

  /// Convenient function to return any type for [Err] and [Na]
  Result<X> cast<X>();

  Result<T> or(Result<T> other) => this is Ok ? this : other;

  static bool isOk(Result result) => result is Ok;
}

/// Completed Async value
class Ok<T> extends Result<T> {
  final T? result;

  const Ok([this.result]);

  @override
  String toString() => "Ok($result)";

  @override
  Result<X> cast<X>() => Ok(result as X?);
}

/// Completed with error
class Err extends Result<Never> {
  final List<(Object?, String)> result;

  static Iterable<(Object?, String)> expand(Object? result,
      [String? message]) sync* {
    if (result is Err) {
      yield* expand(result.result);
    } else if (result is Iterable) {
      yield* result.expand(expand).toList();
    } else if (result is (Object?, String)) {
      yield result;
    } else if (result != null) {
      yield (result, message ?? "");
    }
  }

  /// Combine potentially multiple results
  Err([Object? result, Object? other])
      : result = expand([(result, _getCaller()), other]).toList();

  String _formatEntry((Object?, String) entry) {
    final (object, message) = entry;
    if (object == null) {
      if (message.isEmpty) {
        return "Err()";
      } else {
        return "Err($message)";
      }
    } else {
      if (message.isEmpty) {
        return "Err: $object";
      } else {
        return "Err: $object ($message)";
      }
    }
  }

  @override
  String toString() => result.map(_formatEntry).join(" -> ");

  @override
  Result<X> cast<X>() => this;
}

/// No result available yet
class Na extends Result<Never> {
  const Na();

  @override
  String toString() => "Na";

  @override
  Result<X> cast<X>() => this;
}

extension FutureOrAsResult<T> on FutureOr<T> {
  FutureOr<Result<T>> get asOk {
    if (this is Future<T>) {
      return (this as Future<T>).then((value) => Ok(value));
    }
    return Ok(this as T);
  }
}

extension FutureAsResult<T> on Future<T> {
  Future<Result<T>> get asOk => then((value) => Ok(value));
}
