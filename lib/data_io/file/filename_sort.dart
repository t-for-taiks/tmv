import "dart:io";

import "package:collection/collection.dart";
import "package:hive/hive.dart";
import "package:lpinyin/lpinyin.dart";

enum DirectorySortBehavior {
  /// Directories are listed first
  directoryFirst,

  /// Files are listed first
  filesFirst,

  /// Files and directories are mixed
  mixed,
}

sealed class FileSorter {
  bool reversed;

  FileSorter({this.reversed = false});

  List<String> sort(List<String> files);

  static FileSorter defaultSorter = DefaultFileSorter();

  @override
  String toString() => runtimeType.toString();
}

class DefaultFileSorter extends FileSorter {
  final DirectorySortBehavior behavior;

  DefaultFileSorter({
    this.behavior = DirectorySortBehavior.directoryFirst,
    super.reversed = false,
  });

  @override
  List<String> sort(List<String> files) => sortFiles(
        files,
        behavior: behavior,
        reversed: reversed,
      );

  @override
  String toString() => "DefaultFileSorter($behavior, reversed: $reversed)";
}

class FileSorterAdapter implements TypeAdapter<FileSorter> {
  @override
  final int typeId = 4;

  @override
  FileSorter read(BinaryReader reader) {
    final reversed = reader.readBool();
    final behavior = reader.readByte();
    return DefaultFileSorter(
      behavior: DirectorySortBehavior.values[behavior],
      reversed: reversed,
    );
  }

  @override
  void write(BinaryWriter writer, FileSorter obj) {
    switch (obj) {
      case DefaultFileSorter sorter:
        writer.writeBool(sorter.reversed);
        writer.writeByte(sorter.behavior.index);
        break;
    }
  }
}

bool _isDigit(int c) => c >= 48 && c <= 57;

int _readNumber(Iterator<int> it) {
  int result = 0;
  while (_isDigit(it.current)) {
    result = result * 10 + (it.current - 48);
    if (!it.moveNext()) {
      break;
    }
  }
  return result;
}

String _sep = Platform.pathSeparator;

int stringRunesCompare(List<int> left, List<int> right) {
  // use an optimized approach to zip-iterate both strings
  // tracking whether it's currently pointing a digit
  final iterA = left.iterator;
  final iterB = right.iterator;
  while (iterA.moveNext() && iterB.moveNext()) {
    // if we hit numbers simultaneously, exhaust the numbers and compare
    if (_isDigit(iterA.current) && _isDigit(iterB.current)) {
      final compare = _readNumber(iterA).compareTo(_readNumber(iterB));
      if (compare != 0) {
        return compare;
      } else {
        continue;
      }
    }
    // otherwise, compare the two values
    final compare = iterA.current.compareTo(iterB.current);
    if (compare != 0) {
      return compare;
    }
  }
  // there can be identical names such as "000.jpg" and "0.jpg"
  return left.length.compareTo(right.length);
}

List<int> getRunesForSort(String str) => str.runes.expand((rune) sync* {
      if (rune >= 65 && rune <= 90) {
        yield rune + 32;
      } else if (rune >= 0x4e00 && rune <= 0x9fff) {
        yield* PinyinHelper.convertToPinyinArray(
              String.fromCharCode(rune),
              PinyinFormat.WITHOUT_TONE,
            ).firstOrNull?.runes ??
            [rune];
      } else if (rune > 32) {
        // ignore whitespace
        yield rune;
      }
    }).toList();

extension StringSortExtension on Iterable<String> {
  /// Sort strings on multiple parts of filename
  List<String> sortedNames() =>
      sortedByCompare(getRunesForSort, stringRunesCompare);
}

/// High-efficiency sort on multiple parts of filename
///
/// Only applicable on filenames with no directory depth
///
/// Sort result sample:
/// - 1file.jpg
/// - 2file.jpg
/// - 10file.jpg
/// - file1.jpg
/// - file2.jpg
/// - file10.jpg
List<String> sortFilenames(List<String> files) =>
    files.sortedByCompare(getRunesForSort, stringRunesCompare);

/// Tree node used to construct directory tree
class _FileTreeNode {
  /// Sub-directories
  final Map<String, _FileTreeNode> directories = {};

  /// Sub-files
  final List<String> files = [];

  Iterable<String> enumerateDirectories({
    String prefix = "",
    DirectorySortBehavior behavior = DirectorySortBehavior.directoryFirst,
    bool reversed = false,
  }) sync* {
    assert(behavior != DirectorySortBehavior.mixed);
    final sortedDirs = sortFilenames(directories.keys.toList());
    for (final dir in (reversed ? sortedDirs.reversed : sortedDirs)) {
      final path = prefix + dir + _sep;
      yield* directories[dir]!.enumerate(
        prefix: path,
        behavior: behavior,
        reversed: reversed,
      );
    }
  }

  Iterable<String> enumerateFiles({
    String prefix = "",
    DirectorySortBehavior behavior = DirectorySortBehavior.directoryFirst,
    bool reversed = false,
  }) sync* {
    assert(behavior != DirectorySortBehavior.mixed);
    final sortedFiles = sortFilenames(files);
    for (final file in (reversed ? sortedFiles.reversed : sortedFiles)) {
      yield prefix + file;
    }
  }

  Iterable<String> enumerate({
    String prefix = "",
    DirectorySortBehavior behavior = DirectorySortBehavior.directoryFirst,
    bool reversed = false,
  }) sync* {
    switch (behavior) {
      case DirectorySortBehavior.directoryFirst:
        yield* enumerateDirectories(
          prefix: prefix,
          behavior: behavior,
          reversed: reversed,
        );
        yield* enumerateFiles(
          prefix: prefix,
          behavior: behavior,
          reversed: reversed,
        );
        break;
      case DirectorySortBehavior.filesFirst:
        yield* enumerateFiles(
          prefix: prefix,
          behavior: behavior,
          reversed: reversed,
        );
        yield* enumerateDirectories(
          prefix: prefix,
          behavior: behavior,
          reversed: reversed,
        );
        break;
      case DirectorySortBehavior.mixed:
        final mixedSort = sortFiles(
          [...directories.keys, ...files],
          behavior: behavior,
          reversed: reversed,
        );
        for (final key in mixedSort) {
          if (directories.containsKey(key)) {
            yield* directories[key]!.enumerate(
              prefix: prefix + key + _sep,
              behavior: behavior,
              reversed: reversed,
            );
          } else {
            yield prefix + key;
          }
        }
    }
  }
}

/// Build directory tree and then sort files
List<String> sortFiles(
  Iterable<String> files, {
  DirectorySortBehavior behavior = DirectorySortBehavior.directoryFirst,
  bool reversed = false,
}) {
  final root = _FileTreeNode();

  /// put all files into tree
  for (final path in files) {
    final components = path.split(Platform.pathSeparator);
    final basename = components.removeLast();
    var node = root;
    for (final dir in components) {
      node = node.directories.putIfAbsent(dir, _FileTreeNode.new);
    }
    node.files.add(basename);
  }

  /// get result
  return root
      .enumerate(
        behavior: behavior,
        reversed: reversed,
      )
      .toList();
}
