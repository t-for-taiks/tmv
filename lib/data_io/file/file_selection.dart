import 'package:collection/collection.dart';
import 'package:hive/hive.dart';
import 'package:yaml_writer/yaml_writer.dart';

import 'file_filter.dart';
export 'file_filter.dart';
import 'filename_sort.dart';
export 'filename_sort.dart';

part 'file_selection.g.dart';

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

  Map<String, int> fileIndex = {};

  @HiveField(0)
  FileFilter? _extensionFilter;

  FileFilter get extensionFilter => _extensionFilter ?? ExtensionFilter.image;

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
    files = List.unmodifiable(
      sorter.sort(fileSource().where(filter.test).toList()),
    );
    fileIndex = Map.fromEntries(
      files.mapIndexed((index, file) => MapEntry(file, index)),
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
