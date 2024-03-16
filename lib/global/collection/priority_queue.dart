import 'dart:async';

import 'package:collection/collection.dart';

/// A priority queue with unique keys, so that its values can be updated
class UniquePriority<Key, Data> {
  /// Queue that tracks both key and priority
  final queue = PriorityQueue<(Key, Comparable)>(
        (left, right) => Comparable.compare(left.$2, right.$2),
  );

  /// Record data
  ///
  /// On key removal, data is immediately removed
  final dataStorage = <Key, Data>{};

  /// Record current priority for each key in queue
  final lookup = <Key, Comparable>{};

  /// Get size of an element
  final int Function(Data) sizeGetter;

  /// Total size of all elements, default to [length]
  int size = 0;

  int get length => lookup.length;

  /// When value of a key is updated, the old value is kept here
  ///
  /// The old record will not be removed from [queue] immediately. Instead,
  /// old records will be checked and ignored during [_trim] as they leave queue
  final toDiscard = <(Key, Comparable), int>{};

  bool get isEmpty => queue.isEmpty;

  bool get isNotEmpty => !isEmpty;

  bool containsKey(Key key) => lookup.containsKey(key);

  Map<Key, Data> get data => dataStorage;

  UniquePriority({int Function(Data)? sizeGetter})
      : sizeGetter = sizeGetter ?? ((data) => 1);

  /// Make a key-value pair labeled to be discarded when at queue top
  void _markForDiscard(Key key) {
    final priority = lookup.remove(key) as Comparable;
    toDiscard.update((key, priority), (count) => count + 1, ifAbsent: () => 1);
  }

  /// Add an entry, possibly overwriting old ones with the same key
  void push(Key key, Comparable priority, Data data) {
    queue.add((key, priority));
    if (dataStorage.containsKey(key)) {
      size -= sizeGetter(dataStorage[key] as Data);
    }
    dataStorage[key] = data;
    size += sizeGetter(data);
    if (lookup.containsKey(key)) {
      _markForDiscard(key);
      _trim();
    }
    lookup[key] = priority;
  }

  /// Update priority of an existing entry
  void updatePriority(Key key, Comparable priority) {
    if (!lookup.containsKey(key)) {
      return;
    }
    queue.add((key, priority));
    _markForDiscard(key);
    _trim();
    lookup[key] = priority;
  }

  /// Remove existing entry of a key. Returns true if successful
  bool remove(Key key) {
    if (!lookup.containsKey(key)) {
      return false;
    }
    size -= sizeGetter(dataStorage.remove(key) as Data);
    _markForDiscard(key);
    _trim();
    return true;
  }

  /// Pop discarded entries from queue (if they're on queue top)
  void _trim() {
    while (isNotEmpty) {
      final pair = queue.first;
      if (toDiscard.containsKey(pair)) {
        queue.removeFirst();
        final count = toDiscard.remove(pair)!;
        if (count > 1) {
          toDiscard[pair] = count - 1;
        }
      } else {
        break;
      }
    }
  }

  /// Pop the entry with lowest value
  (Key, Data) pop() {
    final (key, _) = queue.removeFirst();
    lookup.remove(key);
    _trim();
    final data = dataStorage.remove(key) as Data;
    size -= sizeGetter(data);
    return (key, data);
  }

  /// Pop everything
  Iterable<(Key, Data)> flush() {
    final output = <(Key, Data)>[];
    while (isNotEmpty) {
      output.add(pop());
    }
    return output;
  }

  /// Clear everything
  void clear() {
    queue.clear();
    lookup.clear();
    toDiscard.clear();
    dataStorage.clear();
    size = 0;
  }

  void dispose() => clear();
}

/// Provide a stream for async process
class UniquePriorityStream<Key, Data> extends UniquePriority<Key, Data> {
  bool isDestroyed = false;

  Completer<void>? newEntrySignal;

  /// Stream of entries, will end when [dispose] is called
  Stream<(Key, Data)> stream() async* {
    while (!isDestroyed) {
      while (isEmpty) {
        assert(newEntrySignal == null);
        newEntrySignal = Completer.sync();
        await newEntrySignal!.future;
        newEntrySignal = null;
        if (isDestroyed) {
          return;
        }
      }
      yield pop();
    }
  }

  /// Push an entry and trigger the stream
  @override
  void push(Key key, Comparable priority, Data data) {
    super.push(key, priority, data);
    newEntrySignal?.complete(null);
  }

  @override
  void dispose() {
    super.dispose();
    isDestroyed = true;
    newEntrySignal?.complete(null);
  }
}
