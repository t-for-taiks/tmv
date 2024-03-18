import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

import '../../global/config.dart';
import '../../global/global.dart';

/// Limit size to parse yaml to 10MB
const yamlSizeLimit = 10 * 1024 * 1024;

sealed class ListedInfo {
  final String parentPath;

  final String relativePath;

  final String fullPath;

  ListedInfo({
    required this.fullPath,
    required this.parentPath,
  }) : relativePath = relative(fullPath, from: parentPath);
}

class ListedFileInfo extends ListedInfo {
  ListedFileInfo({required super.fullPath, required super.parentPath});
}

class ListedDirectoryInfo extends ListedInfo {
  ListedDirectoryInfo({required super.fullPath, required super.parentPath});
}

AsyncOut<List<ListedInfo>> listDirectory(
  String directoryPath,
  AsyncSignal signal, {
  bool Function(String)? condition,
  bool includeDirectory = true,
  bool recursive = true,
}) =>
    isolateRun(
        () => Directory(directoryPath)
            .list(recursive: recursive)
            .handleError((_) {}) // Ignore files that can't be accessed
            .map((file) => file.path)
            .where((path) => (condition?.call(path) ?? true))
            .map<Result<ListedInfo>>((path) {
              if (FileSystemEntity.isFileSync(path)) {
                return Ok(ListedFileInfo(
                  fullPath: path,
                  parentPath: directoryPath,
                ));
              } else if (FileSystemEntity.isDirectorySync(path) &&
                  includeDirectory) {
                return Ok(ListedDirectoryInfo(
                  fullPath: path,
                  parentPath: directoryPath,
                ));
              } else {
                return Err("Not a file or directory");
              }
            })
            .where(Result.isOk)
            .map((result) => result.value)
            .take(fileCountLimit)
            .toList()
            .asOk,
        signal);

AsyncOut<List<Uint8List>> readFiles(List<String> files, AsyncSignal signal) =>
    isolateRun(
      () => files.map((file) => File(file).readAsBytesSync()).toList().asOk,
      signal,
    );

AsyncOut<Map<Key, Value>> parseYaml<Key, Value>(
        Uint8List bytes, AsyncSignal signal) =>
    isolateRun(
      () {
        if (bytes.length > yamlSizeLimit) {
          return Err("File too large");
        }
        try {
          final result = loadYaml(utf8.decode(bytes));
          if (result is YamlMap) {
            return Ok(Map.from(result));
          } else {
            return Err("Failed to parse yaml");
          }
        } catch (e) {
          return Err(e);
        }
      },
      signal,
    );

/// Interface for a file on web platform
class WebFile with ReadyFlagMixin<WebFile> {
  final String name;
  AsyncExecutor0<Uint8List>? dataRead;
  Uint8List? data;

  WebFile({required this.name, required this.dataRead});

  static Async<WebFile> buildHandle({
    required FutureOr<String> Function() nameGetter,
    required FutureOr<Uint8List> Function() dataGetter,
  }) {
    return Async((_) async {
      final name = await nameGetter();
      return Ok(WebFile(
        name: name,
        dataRead: (signal) => dataGetter().asOk,
      ));
    });
  }

  @override
  AsyncOut getReady(AsyncSignal signal) =>
      dataRead!.execute().map((data) => this.data = data);

  /// Release resources when file is no longer used
  void dispose() {
    data = null;
    dataRead = null;
  }
}
