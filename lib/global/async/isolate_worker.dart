import "dart:async";
import "dart:isolate";

import "package:collection/collection.dart";
import "package:flutter/services.dart";

import "../collection/collection.dart";
import "../global.dart";

/// Implement this class to create a functional Isolate
abstract class IsolateWorker<In, Out> {
  /// Called when Isolate is created
  FutureOr<void> initIsolate() {}

  /// Handler to process each message
  FutureOr<Result<Out>> process(In input);

  /// Called when Isolate is terminated
  FutureOr<void> shutdown() {}
}

class _PriorityIsolateEntry<In, Out> {
  final IsolateManager<In, Out> isolate;
  Completer<Result<Out>>? completer;

  _PriorityIsolateEntry(this.isolate);

  bool get isCompleted => completer == null || completer!.isCompleted;
}

class PriorityIsolatePoolManager<Key, In, Out> {
  final queue = UniquePriorityStream<Key, (In, Completer<Result<Out>>)>();

  /// Isolates that are currently processing jobs
  final isolatePool = <_PriorityIsolateEntry<In, Out>>[];

  late final Async<void> _managerThread;

  /// Create a thread to manage queue
  PriorityIsolatePoolManager() {
    _managerThread = Async((signal) async {
      await for (final (_, (input, completer)) in queue.stream()) {
        assert(isolatePool.isNotEmpty);
        if (isolatePool.none((e) => e.isCompleted)) {
          await Future.any(isolatePool
              .map((e) => e.completer!.future as Future)
              .followedBy([signal.future]));
        }
        if (signal.isTriggered) {
          completer.complete(Err(signal));
          break;
        }
        final entry = isolatePool.firstWhere((e) => e.isCompleted);
        entry.completer = completer;
        unawaited(entry.isolate.process(input).then(completer.complete));
      }
      return ok;
    });
  }

  /// Create isolates to process jobs
  AsyncOut<PriorityIsolatePoolManager<Key, In, Out>> createIsolates(
    int isolateCount,
    FutureOr<IsolateWorker<In, Out>> Function() workerCreator,
    AsyncSignal signal,
  ) async {
    assert(isolatePool.isEmpty);
    for (var i = 0; i < isolateCount; i++) {
      isolatePool.add(
        _PriorityIsolateEntry(await IsolateManager.spawn(workerCreator)),
      );
    }
    return Ok(this);
  }

  /// Process input with specific priority (lower is better)
  AsyncOut<Out> processWithPriority(
    Key key,
    In input,
    Comparable priority,
    AsyncSignal signal,
  ) async {
    final completer = Completer<Result<Out>>();
    queue.push(key, priority, (input, completer));
    await Future.any([completer.future, signal.future]);
    if (signal.isTriggered && queue.remove(key)) {
      return Err(signal);
    }
    return await completer.future;
  }

  void dispose() {
    _managerThread.cancel();
    for (final entry in isolatePool) {
      entry.isolate.dispose();
    }
    while (queue.isNotEmpty) {
      final (_, (_, completer)) = queue.pop();
      completer.complete(Err());
    }
    queue.dispose();
  }
}

/// Message to Isolate with this id doesn't need response
const _idJobNoReply = -1;

/// This object is passed to isolate to signal termination
class _IsolateTerminationSignal {
  const _IsolateTerminationSignal();
}

/// Isolate boilerplate
class IsolateManager<In, Out> {
  final SendPort _commands;
  final ReceivePort _responses;
  final Map<int, Completer<Result<Out>>> _pendingJobs = {};
  int _idCounter = 0;
  bool _closed = false;

  /// Send input object for [IsolateWorker] to process. No response needed
  void send(In input) {
    _commands.send((_idJobNoReply, input));
  }

  /// Send input object for [IsolateWorker] to process
  Future<Result<Out>> process(In input) async {
    if (_closed) throw StateError("Closed");
    final completer = Completer<Result<Out>>.sync();
    _idCounter += 1;
    _pendingJobs.putIfAbsent(_idCounter, () => completer);
    _commands.send((_idCounter, input));
    return await completer.future;
  }

  /// Create an Isolate with specific [workerCreator]
  static Future<IsolateManager<In, Out>>
      spawn<In, Out, W extends IsolateWorker<In, Out>>(
    FutureOr<W> Function() workerCreator,
  ) async {
    // Create a receive port and add its initial message handler
    final initPort = RawReceivePort();
    final connection = Completer<(ReceivePort, SendPort)>.sync();
    initPort.handler = (initialMessage) {
      final commandPort = initialMessage as SendPort;
      connection.complete((
        ReceivePort.fromRawReceivePort(initPort),
        commandPort,
      ));
    };

    // Spawn the isolate.
    try {
      await Isolate.spawn(
        _startRemoteIsolate<W, In, Out>,
        (initPort.sendPort, workerCreator, RootIsolateToken.instance!),
      );
    } on Object {
      initPort.close();
      rethrow;
    }

    final (ReceivePort receivePort, SendPort sendPort) =
        await connection.future;

    return IsolateManager(receivePort, sendPort);
  }

  IsolateManager(this._responses, this._commands) {
    _responses.listen(_handleResponsesFromIsolate);
  }

  // on manager receives response: set task complete
  void _handleResponsesFromIsolate(dynamic message) {
    final (id, response) = message as (int, dynamic);
    final completer = _pendingJobs.remove(id)!;

    if (response is RemoteError) {
      completer.completeError(response);
    } else {
      if (response == null && response is! Result<Out>) {
        log.w("response null");
      }
      completer.complete(response);
    }

    if (_closed && _pendingJobs.isEmpty) _responses.close();
  }

  static void _startRemoteIsolate<W extends IsolateWorker<IN, OUT>, IN, OUT>(
    (SendPort, FutureOr<W> Function(), RootIsolateToken) message,
  ) async {
    final (sendPort, workerCreator, rootToken) = message;
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);

    // create isolate environment
    final worker = await workerCreator();
    await worker.initIsolate();
    // isolate handles message
    receivePort.listen((message) async {
      // log.e("message receive");
      if (message is _IsolateTerminationSignal) {
        receivePort.close();
        await worker.shutdown();
        return;
      }
      final (id, input) = message as (int, IN);
      try {
        final output = await worker.process(input);
        if (id != _idJobNoReply) {
          sendPort.send((id, output));
        }
      } catch (e) {
        sendPort.send((id, RemoteError(e.toString(), "")));
      }
      // log.e("message send");
    });
  }

  void close() {
    if (!_closed) {
      _closed = true;
      _commands.send(const _IsolateTerminationSignal());
      if (_pendingJobs.isEmpty) {
        _responses.close();
      }
    }
  }

  void dispose() => close();
}
