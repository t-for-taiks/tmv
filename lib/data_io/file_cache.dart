import 'package:flutter/foundation.dart';
import 'package:tmv/global/collection/collection.dart';

import '../global/config.dart';
import '../global/global.dart';
import '../global/helper.dart';

/// File cache middleware to buffer external data read
///
/// [getData] is the exposed method to retrieve data
///
/// [loadData] and [loadBatch] need to be implemented
///
/// [FileCache] manages a cache between them
abstract mixin class FileCache {
  int minimumCachedEntries = minimumMemoryCacheCount;

  int cacheSizeByteLimit = defaultMemoryCacheSize;

  bool get _isFull => _cache.totalSize >= cacheSizeByteLimit;

  /// Number of files
  int get length;

  final _cache =
      LRUPool<String, Uint8List>(sizeGetter: (data) => data.lengthInBytes);

  /// Load data into memory
  @protected
  AsyncOut<Uint8List> loadData(
    String key,
    AsyncSignal signal, {
    Priority priority = Priority.low,
  });

  /// Remove least used entry from memory
  bool _evictOne() {
    final entry = _cache.pop();
    if (entry == null) {
      return false;
    }
    return true;
  }

  /// Remove out of range entries while full
  void _releaseSpace() {
    while (_isFull && length > minimumCachedEntries && _evictOne()) {}
  }

  /// Retrieve data
  ///
  /// Will cause nearby entries to be loaded into memory
  ///
  /// [priority] default to highest priority
  @nonVirtual
  AsyncOut<Uint8List> getData(
    String key,
    AsyncSignal signal, {
    Priority priority = Priority.low,
  }) async {
    if (_cache.containsKey(key)) {
      log.t(("FileCache", "getData($key) hits"));
      return Ok(_cache.access(key));
    }
    log.t(("FileCache", "getData($key) miss"));
    _releaseSpace();
    return await loadData(key, signal, priority: priority).map((result) {
      if (!_cache.containsKey(key)) {
        _cache.push(key, result);
      }
      return _cache.access(key);
    });
  }

  void disposeCache() {
    _cache.clear();
  }
}

/// Use this mixin to disable file caching, useful if files are already cached
/// in memory
///
/// [loadData] will be directly called for each file retrieval
mixin DisabledFileCache implements FileCache {
  /// Now directly call [loadData]
  @override
  AsyncOut<Uint8List> getData(
    String key,
    AsyncSignal signal, {
    Priority priority = Priority.low,
  }) =>
      loadData(key, signal, priority: priority);
}
