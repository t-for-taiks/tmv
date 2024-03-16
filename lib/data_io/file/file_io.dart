import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:yaml/yaml.dart';

import '../../global/config.dart';
import '../../global/global.dart';

/// Limit size to parse yaml to 10MB
const yamlSizeLimit = 10 * 1024 * 1024;

Future<List<String>> listDirectory(
  String directoryPath, {
  bool Function(String)? condition,
  bool includeDirectory = false,
  bool recursive = true,
}) =>
    isolateRunSimple(
      () async => await Directory(directoryPath)
          .list(recursive: recursive)
          .handleError((_) {}) // Ignore files that can't be accessed
          .map((file) => file.path)
          .where(
            (path) =>
                (condition?.call(path) ?? true) &&
                (includeDirectory || FileSystemEntity.isFileSync(path)),
          )
          .take(fileCountLimit)
          .toList(),
    );

AsyncOut<List<Uint8List>> readFiles(List<String> files, AsyncSignal signal) =>
    isolateRun(
      () => files.map((file) => File(file).readAsBytesSync()).toList().asOk,
      signal,
    );

AsyncOut<Map<Key, Value>> parseYaml<Key, Value>(Uint8List bytes, AsyncSignal signal) => isolateRun(
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
