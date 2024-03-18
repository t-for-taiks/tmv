import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yaml_writer/yaml_writer.dart';

import '../../global/global.dart';
import 'file_filter.dart';
import 'filename_sort.dart';

export 'file_filter.dart';
export 'filename_sort.dart';

part 'file_selection.g.dart';

/// Data for a file with flags
sealed class FileData {
  final String? path;

  final String? additionalText;

  final int? byteSize;

  const FileData({
    this.path,
    this.additionalText,
    this.byteSize,
  });
}

class ImageMemoryData extends FileData {
  final Uint8List bytes;

  const ImageMemoryData({
    required this.bytes,
    super.path,
    super.additionalText,
    super.byteSize,
  });
}

class VideoFileData extends FileData {
  final String tempPath;

  const VideoFileData({
    required this.tempPath,
    super.path,
    super.additionalText,
    super.byteSize,
  });

  static AsyncOut<String> buildPath(Uint8List data, AsyncSignal signal) async {
    final dir = await getTemporaryDirectory().then((dir) => dir.path);
    final path = join(dir, uuid.v4());
    if (signal.isTriggered) {
      return Err("cancelled");
    }
    final file = File(path);
    try {
      await file.create(recursive: true);
      await file.writeAsBytes(data);
    } catch (e) {
      return Err(e);
    }
    return Ok(path);
  }
}

/// A selection of files among all accessible files
@HiveType(typeId: 5)
class FileSelection {
  /// A function that returns all files, must be set before use
  List<String> Function() _fileSource = () => [];

  List<String> Function() get fileSource => _fileSource;

  set fileSource(List<String> Function() value) {
    _fileSource = value;
    _updateSelection();
  }

  FileSelection({List<String> Function()? fileSource}) {
    if (fileSource != null) {
      this.fileSource = fileSource;
    }
  }

  List<String> files = [];

  /// Text files are associated if the names match
  List<String?> additionalTextFiles = [];

  Map<String, int> fileIndex = {};

  @HiveField(0)
  FileFilter? _extensionFilter;

  FileFilter get extensionFilter => _extensionFilter ?? ExtensionFilter.media;

  set extensionFilter(FileFilter value) {
    _extensionFilter = value;
    _updateSelection();
  }

  @HiveField(1)
  FileFilter? _recursionFilter;

  FileFilter get recursionFilter => _recursionFilter ?? RecursionFilter.off;

  set recursionFilter(FileFilter value) {
    _recursionFilter = value;
    _updateSelection();
  }

  @HiveField(2)
  FileSorter? _sorter;

  FileSorter get sorter => _sorter ?? FileSorter.defaultSorter;

  set sorter(FileSorter value) {
    _sorter = value;
    _updateSelection();
  }

  bool get reversed => sorter.reversed;

  set reversed(bool value) {
    sorter.reversed = value;
    _updateSelection();
  }

  /// Number of selected files
  int get length => files.length;

  /// The final filter
  FileFilter get filter => extensionFilter & recursionFilter;

  void _updateSelection() {
    final fileList = fileSource();
    files = List.unmodifiable(
      sorter.sort(fileList.where(filter.test).toList()),
    );
    fileIndex = Map.fromEntries(
      files.mapIndexed((index, file) => MapEntry(file, index)),
    );

    final textFiles = fileList.where(ExtensionFilter.text.test).toList();
    final textMapping = <String, List<String>>{};
    for (final file in textFiles) {
      final name = basenameWithoutExtension(file);
      textMapping.putIfAbsent(name, () => []).add(file);
      final shortName = name.replaceAll(RegExp(r"\w+$"), "");
      textMapping.putIfAbsent(shortName, () => []).add(file);
    }
    // remove duplicates and empty keys
    textMapping.removeWhere((key, value) => value.length > 1 || key.isEmpty);
    additionalTextFiles = List.unmodifiable(
      files.map((file) {
        final name = basenameWithoutExtension(file);
        final shortName = name.replaceAll(RegExp(r"\w+$"), "");
        return textMapping[name]?.first ?? textMapping[shortName]?.first;
      }),
    );
  }

  Object toJsonObject() => {
        "_": runtimeType.toString(),
        "extensionFilter": extensionFilter.toString(),
        "recursionFilter": recursionFilter.toString(),
        "sorter": sorter.toString(),
        "length": length,
      };

  @override
  String toString() => YamlWriter().convert(toJsonObject());

  void dispose() {
    _fileSource = () => [];
    files = [];
    fileIndex = {};
  }
}
