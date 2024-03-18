import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tmv/data_io/persistence/manga_cache.dart';
import 'package:tmv/data_io/persistence/persistence.dart';
import 'package:tmv/data_io/persistence/thumbnail.dart';

import '../../global/global.dart';
import '../../ui/manga/manga_view.dart';
import '../file/file_selection.dart';
import '../manga_loader.dart';

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

  /// Objects that are saved to temp but not yet to permanent
  static Set<String> _dirtyObjects = {};

  static AsyncOut<void> init(AsyncSignal signal) async {
    if (hiveDisabled) {
      return ok;
    }
    WidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized();
    final dir = await getApplicationSupportDirectory();
    log.d(("persistence", "Storage dir: $dir"));
    await Hive.initFlutter(dir.path);
    Hive.registerAdapter(AppStorageAdapter());
    Hive.registerAdapter(MangaSourceAdapter());
    Hive.registerAdapter(MangaViewDataAdapter());
    Hive.registerAdapter(MangaCacheAdapter());
    Hive.registerAdapter(ThumbnailInfoAdapter());
    Hive.registerAdapter(FileFilterAdapter());
    Hive.registerAdapter(FileSorterAdapter());
    Hive.registerAdapter(FileSelectionAdapter());

    await packageInfo;

    // open temp box
    _tempBox = await tryOpenBox.execute(tempBoxPath).throwErr();
    // start auto save thread
    _autoSaveThread = Async((signal) async {
      while (!signal.isTriggered) {
        // save every 10 seconds, or when signaled
        await Future.any([
          Future.delayed(const Duration(seconds: 10)),
          signal.future,
        ]);
        // create a map of boxPath to objects
        final objects = _dirtyObjects
            .map((key) => _tempBox!.get(key) as BoxStorage)
            .toList();
        final boxMap = <String, List<BoxStorage>>{};
        for (final obj in objects) {
          boxMap.putIfAbsent(obj.boxPath!, () => []).add(obj);
        }
        // save each box (if saved, return [], else return unsaved objects)
        final unsavedObjects = await boxMap.entries
            .map(
              (entry) => (signal) =>
                  withBox<List<BoxStorage>>.execute(entry.key, (box, _) async {
                    for (final obj in entry.value) {
                      log.t(("persistence", "saving ${obj.tempKey}: $obj"));
                      await box.put(obj.boxKey, obj);
                    }
                    return const Ok(<BoxStorage>[]);
                  }).onFail(
                    (err, _) {
                      log.w((
                        "persistence",
                        "failed to save box ${entry.key}: $err"
                      ));
                      return Ok(entry.value);
                    },
                  ),
            )
            // not checking for signal here, because the signal may have been triggered
            .executeLimited()
            .expand((e) => e.value)
            .toList();
        _dirtyObjects = unsavedObjects.map((e) => e.tempKey).toSet();
      }
      return ok;
    });
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
    await tempBox.close();
    await tempBox.deleteFromDisk();
    log.w("Storage shutdown complete");
    return ok;
  }

  /// Path to a temporary box
  ///
  /// This box is opened for the entire app lifetime. Objects will be written to
  /// permanent boxes when the app is closed
  static final String tempBoxPath = uuid.v4();

  /// Temporary box stays open for the entire app lifetime
  static Box? _tempBox;

  static Box get tempBox => _tempBox!;

  /// Save to temporary location
  static AsyncOut<void> saveTemp(BoxStorage obj, AsyncSignal signal) {
    _dirtyObjects.add(obj.tempKey);
    return tempBox.put(obj.tempKey, obj).asOk;
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

  /// Try to load this object from disk
  static AsyncOut<T> tryLoad<T extends BoxStorage<T>>(
      String boxPath, String boxKey, AsyncSignal signal) async {
    if (_tempBox == null) {
      return Err("Can't load in isolate");
    }
    // if object is already in temp box, return it
    final temp = tempBox.get(BoxStorage.formatTempKey(boxPath, boxKey));
    if (temp is T) {
      temp
        ..boxPath = boxPath
        ..boxKey = boxKey;
      return Ok(temp);
    }
    // if object is found in the permanent box, return it, and save to temp box
    return await withBox<T>(boxPath, (box, signal) async {
      final result = box.get(boxKey);
      if (result == null) {
        return Err("No such key", signal);
      }
      (result as T)
        ..boxPath = boxPath
        ..boxKey = boxKey;
      await saveTemp.execute(result);
      return Ok(result);
    }, signal)
        .asFuture
        .catchError((e, s) {
      log.w("Failed to load", error: e, stackTrace: s);
      return Err(e, signal);
    });
  }

  /// Try to load this object from disk, or create a new one
  static AsyncOut<T> loadOr<T extends BoxStorage<T>>(
      String boxPath,
      String boxKey,
      AsyncSignal signal,
      AsyncExecutor0<T> objectCreator) async {
    return tryLoad<T>.execute(boxPath, boxKey, signal)
        .onFail((_, signal) async {
      final obj = await objectCreator(signal);
      if (obj is Ok) {
        obj.value.markAsDirty();
      }
      return obj;
    });
  }

  /// Try to remove this object from disk
  static AsyncOut<void> remove(
      String boxPath, String key, AsyncSignal signal) async {
    await tempBox.delete(BoxStorage.formatTempKey(boxPath, key));
    return await withBox(boxPath, (box, _) => box.delete(key).asOk, signal);
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

  /// Triggered when this object is modified
  Completer<void> _dirtySignal = Completer.sync();

  /// A thread to repeatedly check for [_dirty] and perform save
  Async? _autoSaveThread;

  /// Mark this object as modified to be saved
  void markAsDirty() {
    if (!_dirtySignal.isCompleted) {
      _dirtySignal.complete();
    }
    _autoSaveThread ??= Async((signal) async {
      while (true) {
        await Future.any([
          Future.wait([
            _dirtySignal.future,
            Future.delayed(const Duration(milliseconds: 500)),
          ]),
          signal.future,
        ]);
        if (signal.isTriggered) {
          return Err(signal);
        }
        if (_dirtySignal.isCompleted) {
          await _save.execute(signal);
          _dirtySignal = Completer.sync();
        }
      }
    });
  }

  /// Save to temporary location
  AsyncOut<void> _save(AsyncSignal signal) => Storage.saveTemp(this, signal);

  /// Force save immediately (to permanent location)
  AsyncOut<void> forceSave(AsyncSignal signal) async {
    _autoSaveThread?.cancel();
    _autoSaveThread = null;
    return await Storage.save(this, signal);
  }

  void dispose() {
    _autoSaveThread?.cancel();
  }
}
