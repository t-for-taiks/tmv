import "dart:async";
import "dart:typed_data";

import "package:archive/archive_io.dart";

import "../data_io/file/file_selection.dart";
import "async/isolate_worker.dart";
import "config.dart";
import "global.dart";

/// An object of this class is an Isolate thread that does archive decompression
/// on one archive
///
/// All methods are run in an Isolate
class ArchiveDecompressWorker
    implements IsolateWorker<String?, (Uint8List?, List<String>?)> {
  final String archivePath;

  /// Opened socket
  late final Archive archive;

  ArchiveDecompressWorker({required this.archivePath});

  /// Create a constructor that can be passed to another Isolate,
  /// during the process of Isolate spawning
  static ArchiveDecompressWorker Function() makeConstructor(
    String archivePath,
  ) =>
      () => ArchiveDecompressWorker(archivePath: archivePath);

  /// On init: open archive file socket
  @override
  void initIsolate() => archive = openArchiveFile(archivePath);

  /// Input: file name
  ///
  /// Output: decompressed data
  ///
  /// Return archive list if input is null
  @override
  Result<(Uint8List?, List<String>?)> process(String? input) {
    if (input == null) {
      return Ok((
        null,
        archive.files.map((file) => file.name).toList()..sortedNames(),
      ));
    }
    final file = archive.findFile(input);
    if (file == null) {
      // log.w("file not found: $input");
      return Err("file not found");
    }
    if (file.size > fileReadLimit) {
      log.w("file too large: $input ${file.size.toKb}");
      return Err("file too large");
    }
    if (file.content == null) {
      log.w("content null");
      return Err("content null");
    }
    final data = file.content as Uint8List;
    // free the copy of data
    file.clear();
    return Ok((data, null));
  }

  @override
  FutureOr<void> shutdown() => archive.clear();
}

Archive openArchiveFile(String archivePath) =>
    ZipDecoder().decodeBuffer(InputFileStream(archivePath));

AsyncOut<List<String>> listArchiveFile(
        String archivePath, AsyncSignal signal) =>
    isolateRun(
        () => openArchiveFile(archivePath)
            .files
            .map((file) => file.name)
            .sortedNames()
            .asOk,
        signal);

/// Unzip archive data in memory into name list and data list
AsyncOut<Map<String, Uint8List>> unzipRawArchive(
  Uint8List archiveData,
  AsyncSignal signal, {
  bool Function(String)? nameFilter,
  int? count,
}) {
  nameFilter ??= (_) => true;
  count ??= fileCountLimit;
  return isolateRun(() {
    final archive = ZipDecoder().decodeBytes(archiveData);
    final files =
        archive.files.where((file) => nameFilter!(file.name)).take(count!);
    return Map.fromEntries(
      files.map((file) => MapEntry(file.name, file.content as Uint8List)),
    ).asOk;
  }, signal);
}
