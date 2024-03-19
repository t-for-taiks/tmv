import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/src/hive_impl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../../global/global.dart';
import '../../ui/manga/manga_view.dart';
import '../file/file_selection.dart';
import '../manga_loader.dart';
import 'manga_cache.dart';
import 'persistence.dart';
import 'thumbnail.dart';

export 'package:hive_flutter/hive_flutter.dart';

/// If not supported or otherwise inaccessible, this will disable hive storage
const bool hiveDisabled = kIsWeb;

class Storage {
  /// Periodically save all objects
  static late final Async<void> _autoSaveThread;

  /// Opened boxes (excluding temp)
  static final Map<String, Box> _openedBoxes = {};

  /// Reference count for each box
  ///
  /// 0: Box is being closed or opened. Do not access until it's removed
  /// negative: Box is not used, and can be closed
  ///
  /// When a box is done being used, and RefCount reaches 0, it will be assigned
  /// a random negative number, and will be closed after a short delay (if the
  /// number is the same)
  static final Map<String, int> _boxRefCount = {};

  /// Objects updated but not saved yet
  static Map<String, Map<String, BoxStorage>> _dirtyObjects = {};

  /// Objects cached in memory
  static final Map<String, BoxStorage> _tempObjects = {};

  static AsyncOut<void> init(AsyncSignal signal) async {
    WidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized();

    await packageInfo;

    if (!hiveDisabled) {
      await getApplicationSupportDirectory()
          .then((dir) => Hive.initFlutter(dir.path));
      Hive
        ..registerAdapter(AppStorageAdapter())
        ..registerAdapter(MangaSourceAdapter())
        ..registerAdapter(MangaViewDataAdapter())
        ..registerAdapter(MangaCacheAdapter())
        ..registerAdapter(ThumbnailInfoAdapter())
        ..registerAdapter(FileFilterAdapter())
        ..registerAdapter(FileSorterAdapter())
        ..registerAdapter(FileSelectionAdapter());

      // start auto save thread
      _autoSaveThread = Async((signal) async {
        while (!signal.isTriggered) {
          // save every 10 seconds, or when signaled
          await Future.any([
            Future.delayed(const Duration(seconds: 10)),
            signal.future,
          ]);
          // save each box
          _dirtyObjects = await _dirtyObjects.entries
              .map(
                (entry) => (signal) =>
                    withBox<MapEntry<String, Map<String, BoxStorage>>>.execute(
                        entry.key, (box, _) async {
                      for (final obj in entry.value.values) {
                        log.t(("persistence", "saving ${obj.tempKey}: $obj"));
                        await box.put(obj.boxKey, obj);
                      }
                      return Ok(MapEntry(entry.key, {}));
                    }).onFail(
                      (err, _) {
                        log.w((
                          "persistence",
                          "failed to save box ${entry.key}: $err"
                        ));
                        return Ok(entry);
                      },
                    ),
              )
              // not checking for signal here, because the signal may have been triggered
              .executeLimited()
              .map((entry) => entry.value)
              .toList()
              .then(Map.fromEntries);
        }
        return ok;
      });
    }

    // initialize app storage
    await AppStorage.init(signal);

    return ok;
  }

  /// Close temp box and write all objects back
  static AsyncOut<void> shutdown(AsyncSignal signal) async {
    if (hiveDisabled) {
      return ok;
    }
    log.w("Shutting down");
    // force shutdown after 1 second timeout
    await Future.any([
      _autoSaveThread.cancel(),
      Future.delayed(const Duration(seconds: 1)),
    ]);
    log.w("Storage shutdown complete");
    return ok;
  }

  /// Add to [_dirtyObjects]
  static void markAsDirty(BoxStorage obj) {
    _tempObjects.putIfAbsent(obj.tempKey, () => obj);
    _dirtyObjects.putIfAbsent(obj.boxPath!, () => {})[obj.boxKey!] = obj;
  }

  /// Save to permanent location
  static AsyncOut<void> save(BoxStorage obj, AsyncSignal signal) =>
      withBox(obj.boxPath!, (box, _) => box.put(obj.boxKey, obj).asOk, signal);

  static AsyncOut<T> withBox<T>(String boxPath, AsyncExecutor1<Box, T> function,
      AsyncSignal signal) async {
    // busy wait if box is just closing (ref count = 0)
    while (_boxRefCount[boxPath] == 0) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    final Box box;
    if (_boxRefCount.containsKey(boxPath) && _boxRefCount[boxPath]! > 0) {
      box = _openedBoxes[boxPath]!;
      _boxRefCount[boxPath] = _boxRefCount[boxPath]! + 1;
    } else {
      // this will block other threads from reopening or closing the box
      _boxRefCount[boxPath] = 0;
      final result = await tryOpenBox.execute(boxPath, signal);
      if (result is Ok) {
        assert(_boxRefCount[boxPath] == 0);
        box = result.value;
        _openedBoxes.putIfAbsent(boxPath, () => box);
        _boxRefCount[boxPath] = 1;
      } else {
        return Err(result);
      }
    }
    try {
      return await function(box, signal);
    } finally {
      _boxRefCount.update(boxPath, (value) => value - 1);
      if (_boxRefCount[boxPath] == 0) {
        // close the box after a short delay
        final marker = -1 - Random().nextInt(0xffffffff);
        _boxRefCount[boxPath] = marker;
        Future(() async {
          await Future.delayed(const Duration(seconds: 5));
          if (_boxRefCount[boxPath] == marker) {
            _boxRefCount[boxPath] = 0;
            await box.close();
            log.w("box close: $boxPath");
            _openedBoxes.remove(boxPath);
            _boxRefCount.remove(boxPath);
          }
        });
      }
    }
  }

  static AsyncOut<T> putIfAbsent<T extends BoxStorage<T>>(String boxPath,
      String boxKey, AsyncExecutor0<T>? value, AsyncSignal signal) async {
    if (hiveDisabled) {
      return value?.execute(signal) ?? Err(["Hive disabled", signal]);
    }
    // if object is already in temp box, return it
    final tempKey = BoxStorage.formatTempKey(boxPath, boxKey);
    if (_tempObjects.containsKey(tempKey)) {
      return Ok(_tempObjects[tempKey] as T);
    }
    // fet in permanent box or create it, and save to temp box
    final result = await withBox<T>.execute(
      boxPath,
      (box, signal) =>
          (box.get(boxKey) as T?)?.asOk ?? value?.execute(signal) ?? Err(),
      signal,
    );
    if (result is Ok) {
      result.value
        ..boxPath = boxPath
        ..boxKey = boxKey;
      markAsDirty(result.value);
    }
    return result;
  }

  static T? findTemp<T extends BoxStorage<T>>(String boxPath, String boxKey) =>
      _tempObjects[BoxStorage.formatTempKey(boxPath, boxKey)] as T?;

  /// Remove from cache
  static void dropTemp(BoxStorage obj) {
    _tempObjects.remove(obj.tempKey);
  }

  /// Try to remove this object from disk
  static AsyncOut<void> remove(
      String boxPath, String boxKey, AsyncSignal signal) async {
    _tempObjects.remove(BoxStorage.formatTempKey(boxPath, boxKey));
    _dirtyObjects[boxPath]?.remove(boxKey);
    return await withBox(boxPath, (box, _) => box.delete(boxKey).asOk, signal);
  }

  /// Try to open box
  ///
  /// Will fail if another process is using,
  /// or if the platform does not support Hive
  static AsyncOut<Box> tryOpenBox(String boxPath, AsyncSignal signal) async {
    if (hiveDisabled) {
      return Err(["Hive disabled", signal]);
    }
    try {
      return Ok(await Hive.openBox(boxPath));
    } catch (e) {
      log.w("Failed to open box", error: e);
      return Err(e, signal);
    }
    // // try recreating the box
    // try {
    //   log.w("Recreating box");
    //   await Future.delayed(const Duration(milliseconds: 500));
    //   await Hive.deleteBoxFromDisk(boxPath);
    //   return Ok(await Hive.openBox(boxPath));
    // } catch (e) {
    //   log.w("Failed to recreate box", error: e);
    //   return Err(e, signal);
    // }
  }
}

/// Mixin for objects that are stored in a box
mixin BoxStorage<T> {
  /// Path to the box where this object is stored
  ///
  /// Override get to return a fixed value for the class
  String? boxPath;

  /// Key of this object in the box
  ///
  /// Override get to return a fixed value for the class
  String? boxKey;

  static String formatTempKey(String boxPath, String boxKey) =>
      "$boxPath/$boxKey";

  /// Key in the temporary box
  String get tempKey => formatTempKey(boxPath!, boxKey!);

  @override
  operator ==(Object other) {
    if (other is BoxStorage) {
      return other.tempKey == tempKey;
    }
    return false;
  }

  /// Mark this object as modified to be saved
  void markAsDirty() {
    Storage.markAsDirty(this);
  }

  /// Force save immediately (to permanent location)
  AsyncOut<void> forceSave(AsyncSignal signal) async {
    return await Storage.save(this, signal);
  }

  /// Remove this object from cache storage
  void dispose() {
    Storage.dropTemp(this);
  }
}
