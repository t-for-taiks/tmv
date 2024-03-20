import "dart:collection";

/// Element in a [LRUPool]
final class _LRUEntry<Key, Data> extends LinkedListEntry<_LRUEntry<Key, Data>> {
  final Key key;
  final Data data;

  _LRUEntry(this.key, this.data);
}

/// A pool that keeps track of recently used elements
class LRUPool<Key, Data> extends Iterable<Data> {
  final entryList = LinkedList<_LRUEntry<Key, Data>>();

  final entryMap = <Key, _LRUEntry<Key, Data>>{};

  /// Elements that are [lock]ed so that they're not popped during [pop]
  ///
  /// [locked] and [entryMap] are separate
  final locked = <Key, Data>{};

  /// Record change of sizes during [push] and [pop]
  int totalSize = 0;

  /// Get size of an element, default to 1 per element
  final int Function(Data data) sizeGetter;

  @override
  int get length => entryList.length + locked.length;

  LRUPool({int Function(Data)? sizeGetter})
      : sizeGetter = sizeGetter ?? ((data) => 1);

  /// Access an element and mark as recently used
  Data access(Key key, {bool lock = false}) {
    if (locked.containsKey(key)) {
      return locked[key]!;
    }
    final entry = entryMap[key]!;
    entry.unlink();
    if (lock) {
      entryMap.remove(key)!;
      locked[key] = entry.data;
    } else {
      entryList.add(entry);
    }
    return entry.data;
  }

  bool containsKey(Key key) =>
      entryMap.containsKey(key) || locked.containsKey(key);

  /// Push an element to the pool
  void push(Key key, Data data) {
    final entry = _LRUEntry(key, data);
    entryList.add(entry);
    entryMap[key] = entry;
    totalSize += sizeGetter(data);
  }

  /// Push an element to the bottom of the pool
  void pushBottom(Key key, Data data) {
    final entry = _LRUEntry(key, data);
    entryList.addFirst(entry);
    entryMap[key] = entry;
    totalSize += sizeGetter(data);
  }

  /// Pop an element if there's unlocked ones
  Data? pop() {
    if (entryList.isEmpty) {
      return null;
    }
    final entry = entryList.first;
    entry.unlink();
    entryMap.remove(entry.key);
    totalSize -= sizeGetter(entry.data);
    return entry.data;
  }

  /// Remove a specified key
  Data remove(Key key) {
    if (!locked.containsKey(key)) {
      final entry = entryMap.remove(key)!;
      entry.unlink();
      totalSize -= sizeGetter(entry.data);
      return entry.data;
    }
    final data = locked.remove(key) as Data;
    totalSize -= sizeGetter(data);
    return data;
  }

  /// Mark as locked, so it's not popped
  void lock(Key key) {
    if (locked.containsKey(key)) {
      return;
    }
    final entry = entryMap.remove(key)!;
    entry.unlink();
    locked[key] = entry.data;
  }

  /// Mark as unlocked
  void unlock(Key key) {
    if (entryMap.containsKey(key)) {
      return;
    }
    final data = locked.remove(key) as Data;
    push(key, data);
  }

  /// Unlock all locked elements
  void unlockAll() {
    for (final MapEntry(key: key, value: value) in locked.entries) {
      push(key, value);
    }
    locked.clear();
  }

  /// Iterate WITHOUT changing LRU status
  @override
  Iterator<Data> get iterator =>
      entryList.map((entry) => entry.data).followedBy(locked.values).iterator;

  void clear() {
    entryList.clear();
    entryMap.clear();
    locked.clear();
    totalSize = 0;
  }
}
