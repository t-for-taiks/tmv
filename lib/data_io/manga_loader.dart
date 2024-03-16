import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart';
import 'package:tmv/global/async/isolate_worker.dart';

import '../global/archive.dart';
import '../global/config.dart';
import '../global/global.dart';
import 'file_cache.dart';
import 'file/file_io.dart';
import 'file/filename_sort.dart';
import '../global/helper.dart';

/// Exception to be thrown if the source file is missing
class MangaSourceInvalidException implements Exception {
  /// Wrap functions to throw [MangaSourceInvalidException] instead
  static T wrap<T>(T Function() operation) {
    try {
      return operation();
    } catch (e) {
      log.w("Exception captured", error: e);
      throw MangaSourceInvalidException();
    }
  }

  /// Used in [Future.onError]
  static Never throwInstead(Object? error, StackTrace? stack) {
    log.w("Exception captured", error: error, stackTrace: stack);
    throw MangaSourceInvalidException();
  }
}

/// An enum for manga data source
sealed class MangaSource with ReadyFlagMixin<MangaSource> {
  /// This is a unique identifier to any manga
  @override
  String toString();

  /// Short name displayed in UI
  String get userShortName;

  /// Relative paths of files (used as key to get data)
  List<String> get files;

  int get length;

  /// Get data from a relative path
  AsyncOut<Uint8List> getData(
    String key,
    AsyncSignal signal, {
    Priority priority = Priority.low,
  });

  void dispose();

  @override
  bool operator ==(Object other) {
    if (other is MangaSource) {
      return identifier == other.identifier;
    }
    return false;
  }

  @override
  int get hashCode => identifier.hashCode;

  static AsyncOut<MangaSource> fromPath(
    String path,
    AsyncSignal signal,
  ) async {
    if (await FileSystemEntity.isFile(path)) {
      if (isSupportedArchiveFormat(path)) {
        return Ok(ArchiveMangaSource(path));
      } else if (isSupportedImageFormat(path)) {
        return Ok(DirectoryMangaSource(dirname(path)));
      } else {
        return Err("Unsupported file format");
      }
    } else if (await FileSystemEntity.isDirectory(path)) {
      return Ok(DirectoryMangaSource(path));
    } else {
      return Err("Not a file: $path");
    }
  }

  static MangaSource fromIdentifier(String identifier) {
    switch (identifier[0]) {
      case "0":
        return NullMangaSource(identifier.substring(1));
      case "1":
        return ArchiveMangaSource(identifier.substring(1));
      case "2":
        return DirectoryMangaSource(
          identifier.substring(2),
          recursive: identifier[1] == "r",
        );
      case "3":
        throw Exception("Cannot reopen file from last session");
      default:
        throw UnsupportedError("unknown value ${identifier[0]}");
    }
  }
}

/// Serialization of [MangaSource]
///
/// Fields:
/// - sourceType
///   - "0": null
///   - "1": archive
///   - "2": directory
///   - "3": web archive (for id purpose only)
/// - (according to type)
extension MangaSourceSerialization on MangaSource {
  String get identifier {
    switch (this) {
      case NullMangaSource _:
        return "0";
      case ArchiveMangaSource obj:
        return "1${obj.archivePath}";
      case DirectoryMangaSource obj:
        return "2${obj.recursive ? "r" : "n"}${obj.directoryPath}";
      case WebArchiveMangaSource obj:
        return "3${identityHashCode(obj)}";
    }
  }
}

/// Unknown data source
class NullMangaSource with ReadyFlagMixin<MangaSource> implements MangaSource {
  final String message;

  NullMangaSource(this.message);

  @override
  void dispose() {}

  @override
  AsyncOut getReady(AsyncSignal signal) => const Ok();

  @override
  List<String> get files => [];

  @override
  int get length => 0;

  @override
  AsyncOut<Uint8List> getData(
    String key,
    AsyncSignal signal, {
    Priority? priority = Priority.low,
  }) =>
      Ok(Uint8List(0));

  @override
  String toString() => "NullMangaSource($message)";

  @override
  String get userShortName => "";
}

/// Data from a zip archive
class ArchiveMangaSource
    with ReadyFlagMixin<MangaSource>, FileCache
    implements MangaSource {
  final String archivePath;

  /// A seperated Isolate will handle file read and decompression
  PriorityIsolatePoolManager<String, String, Uint8List>? decompressIsolate;

  /// Paths of files inside archive
  @override
  List<String> files = [];

  /// Decompressed data (if the entire archive is decompressed in memory)
  ///
  /// If the archive is not entirely stored here, it will depend on [FileCache]
  /// to manage storage.
  Map<String, Uint8List>? data;

  @override
  int get length => files.length;

  ArchiveMangaSource(this.archivePath);

  @override
  AsyncOut<Uint8List> loadData(
    String key,
    AsyncSignal signal, {
    Priority priority = Priority.low,
  }) =>
      ensureReady.execute(signal).chain((_, signal) async {
        if (data != null) {
          return Ok(data![key]!);
        }
        return await decompressIsolate!.processWithPriority.execute(
          key,
          key,
          priority,
          signal,
        );
      });

  /// Initialize by decompressing all data
  AsyncOut<void> loadAll(AsyncSignal signal) =>
      ensureReady.execute(signal).chain((_, signal) async {
        if (data != null) {
          return const Ok();
        }
        final list = <Uint8List>[];
        for (final key in files) {
          final result = await loadData(key, signal);
          if (result is! Ok) {
            return result.cast();
          }
          list.add(result.value);
        }
        data = Map.fromEntries(
          list.mapIndexed((index, value) => MapEntry(files[index], value)),
        );
        return const Ok();
      });

  @override
  String toString() => "ArchiveMangaSource($archivePath)";

  @override
  String get userShortName => basenameWithoutExtension(archivePath);

  /// Parse file list from archive
  @override
  AsyncOut getReady(AsyncSignal signal) async {
    try {
      files = await listArchiveFile(archivePath, signal).throwErr();
    } catch (e) {
      log.d("error opening archive $archivePath", error: e);
      return Err(e, signal);
    }
    if (signal.isTriggered) {
      return Err(signal);
    }
    decompressIsolate = PriorityIsolatePoolManager();
    await decompressIsolate!.createIsolates(
      1,
      ArchiveDecompressWorker.makeConstructor(archivePath),
      signal,
    );
    // log.t("discovered ${files.length} files from $archivePath");
    return const Ok();
  }

  @override
  void release() {
    super.release();
    dispose();
  }

  @override
  void dispose() {
    data = null;
    files.clear();
    disposeCache();
    decompressIsolate?.dispose();
    decompressIsolate = null;
  }
}

/// Archive uploaded to web platform
///
/// Archive will be decompressed and stored in memory
class WebArchiveMangaSource
    with ReadyFlagMixin<MangaSource>
    implements MangaSource {
  final WebFile archiveFile;

  Map<String, Uint8List> fileData = {};

  WebArchiveMangaSource(this.archiveFile);

  @override
  List<String> get files => fileData.keys.toList();

  @override
  void dispose() {}

  /// Read and decompress data from archive, store in [fileData],
  /// then close the archive file (releasing memory)
  @override
  AsyncOut getReady(AsyncSignal signal) async {
    try {
      final archive = archiveFile;
      return await archive.dataRead!
          .execute(signal)
          .chain(unzipRawArchive)
          .map((unzipped) {
        fileData = unzipped;
        archive.dispose();
        return const Ok();
      });
    } catch (e) {
      log.d("error opening web archive $archiveFile", error: e);
      return Err(e, signal);
    }
  }

  @override
  void release() {
    log.d(("MangaView", "releasing $this is ignored: can't reinitialize"));
  }

  String get name => archiveFile.name;

  @override
  String get userShortName => name;

  @override
  int get length => fileData.length;

  @override
  AsyncOut<Uint8List> getData(
    String key,
    AsyncSignal signal, {
    Priority priority = Priority.low,
  }) =>
      ensureReady.execute(signal).map((_) => fileData[key]!);
}

/// Data from files in a directory
class DirectoryMangaSource
    with ReadyFlagMixin<MangaSource>, FileCache
    implements MangaSource {
  final String directoryPath;

  final bool recursive;

  /// Paths of files (including directory prefix)
  @override
  List<String> files = [];

  DirectoryMangaSource(this.directoryPath, {this.recursive = true});

  @override
  String toString() => "DirectoryMangaSource($directoryPath)";

  @override
  String get userShortName => basename(directoryPath);

  @override
  AsyncOut getReady(AsyncSignal signal) async {
    try {
      final path = directoryPath.toString();
      final dir = Directory(path);
      if (await dir.exists()) {
        files = sortFiles(await listDirectory(
          directoryPath,
          recursive: recursive,
        ));
      }
      // log.t("discovered ${files.length} files from $directoryPath");
      return const Ok();
    } catch (e) {
      return Err(e, signal);
    }
  }

  @override
  void release() {
    super.release();
    files.clear();
  }

  @override
  int get length => files.length;

  @override
  AsyncOut<Uint8List> loadData(
    String key,
    AsyncSignal signal, {
    Priority priority = Priority.low,
  }) async {
    try {
      final file =
          File(isWithin(directoryPath, key) ? key : join(directoryPath, key));
      final size = await file.length();
      if (size > fileReadLimit) {
        log.w("file too large: $key, ${size.toKb}");
        return Err("File too large");
      }
      return Ok(await file.readAsBytes());
    } catch (error) {
      // log.w("error reading file $key", error: error, stackTrace: stack);
      return Err(error, signal);
    }
  }

  @override
  void dispose() {}
}

class MangaSourceAdapter extends TypeAdapter<MangaSource> {
  @override
  final int typeId = 1;

  @override
  MangaSource read(BinaryReader reader) {
    return MangaSource.fromIdentifier(reader.readString());
  }

  @override
  void write(BinaryWriter writer, MangaSource obj) {
    writer.writeString(obj.identifier);
  }
}
