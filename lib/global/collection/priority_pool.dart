import 'package:collection/collection.dart';

final class _PriorityPoolEntry<Key, Data>
    implements Comparable<_PriorityPoolEntry<Key, Data>> {
  final Key key;
  Data data;
  Comparable priority;

  _PriorityPoolEntry({
    required this.key,
    required this.data,
    required this.priority,
  });

  @override
  int compareTo(_PriorityPoolEntry<Key, Data> other) =>
      Comparable.compare(other.priority, priority);
}

/// Pool with mutable priorities, reordering is done upon [pop]
class PriorityPool<Key, Data> extends Iterable<Data> {
  final Map<Key, _PriorityPoolEntry<Key, Data>> _map = {};

  final _queue = PriorityQueue<_PriorityPoolEntry<Key, Data>>();

  @override
  int get length => _map.length;

  @override
  bool get isEmpty => _map.isEmpty;

  void push(Key key, Data data, Comparable priority) {
    _map[key] = _PriorityPoolEntry(key: key, data: data, priority: priority);
    _queue.clear();
  }

  void updatePriority(Key key, Comparable priority) {
    _map[key]!.priority = priority;
    _queue.clear();
  }

  void updateData(Key key, Data data) => _map[key]!.data = data;

  Data operator [](Key key) => _map[key]!.data;

  bool containsKey(Key key) => _map.containsKey(key);

  Iterable<Key> get keys => _map.keys;

  Iterable<Data> get values => _map.values.map((e) => e.data);

  Iterable<MapEntry<Key, Data>> get entries =>
      _map.entries.map((e) => MapEntry(e.key, e.value.data));

  @override
  Iterator<Data> get iterator => _map.entries.map((e) => e.value.data).iterator;

  void removeWhere(bool Function(Key, Data) predicate) {
    _map.removeWhere((_, entry) => predicate(entry.key, entry.data));
    _queue.clear();
  }

  (Key, Data) remove(Key key) {
    final entry = _map.remove(key)!;
    _queue.clear();
    return (entry.key, entry.data);
  }

  (Key, Data) pop() {
    if (_queue.isEmpty) {
      _queue.addAll(_map.values);
    }
    final entry = _queue.removeFirst();
    _map.remove(entry.key);
    return (entry.key, entry.data);
  }

  /// Get the lowest priority item without removing it
  ({Key key, Data data, Comparable priority}) get top {
    if (_queue.isEmpty) {
      _queue.addAll(_map.values);
    }
    final entry = _queue.first;
    return (
      key: entry.key,
      data: entry.data,
      priority: entry.priority,
    );
  }
}
