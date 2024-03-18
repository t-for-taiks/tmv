import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path/path.dart';

sealed class FileFilter {
  const FileFilter();

  bool test(String file);

  operator &(FileFilter other) => ChainedFilter([this, other], false);

  operator |(FileFilter other) => ChainedFilter([this, other], true);

  @override
  String toString() => runtimeType.toString();
}

class AllFilter extends FileFilter {
  const AllFilter();

  @override
  bool test(String file) => true;
}

class NoneFilter extends FileFilter {
  const NoneFilter();

  @override
  bool test(String file) => false;
}

class ChainedFilter extends FileFilter {
  final List<FileFilter> filters;

  /// Chain behavior: union or intersection
  final bool union;

  ChainedFilter(this.filters, this.union);

  @override
  bool test(String file) {
    if (union) {
      return filters.any((f) => f.test(file));
    } else {
      return filters.every((f) => f.test(file));
    }
  }

  @override
  String toString() =>
      'ChainedFilter(${filters.map((f) => "($f)").join(union ? ' | ' : ' & ')})';
}

class ExtensionFilter extends FileFilter {
  final Set<String> allowedExtensions;

  const ExtensionFilter(this.allowedExtensions);

  @override
  bool test(String file) =>
      allowedExtensions.contains(extension(file).toLowerCase());

  /// Image and video
  static ExtensionFilter media = image | video;

  static FileFilter getType(String path) {
    if (image.test(path)) {
      return image;
    } else if (video.test(path)) {
      return video;
    } else if (archive.test(path)) {
      return archive;
    } else if (text.test(path)) {
      return text;
    } else {
      return any;
    }
  }

  @override
  operator |(FileFilter other) {
    if (other is! ExtensionFilter) {
      return super | other;
    }
    return ExtensionFilter(
      allowedExtensions.union(other.allowedExtensions),
    );
  }

  /// Some image file extensions supported by Flutter
  static const ExtensionFilter image = ExtensionFilter({
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.tiff',
    '.tif',
    '.webp',
  });

  /// Some archive file extensions supported by Flutter
  static const ExtensionFilter archive = ExtensionFilter({
    '.zip',
    '.cbz',
    '.cbt',
    '.tar',
    '.gz',
    '.bz2',
    '.xz',
  });

  /// Some video file extensions supported by Flutter
  static const ExtensionFilter video = ExtensionFilter({
    '.webm',
    '.mkv',
    '.flv',
    '.vob',
    '.ogv',
    '.ogg',
    '.avi',
    '.mts',
    '.m2ts',
    '.ts',
    '.mov',
    '.wmv',
    '.rm',
    '.rmvb',
    '.asf',
    '.mp4',
    '.m4v',
    '.mpg',
    '.mp2',
    '.mpeg',
    '.mpe',
    '.mpv',
    '.m2v',
    '.svi',
    '.3gp',
    '.3g2',
    '.f4v',
    '.f4p',
    '.f4a',
    '.f4b',
  });

  static const ExtensionFilter text = ExtensionFilter({
    '.txt',
    '.json',
    '.yaml',
  });

  static const FileFilter any = AllFilter();

  @override
  String toString() =>
      'ExtensionFilter(${allowedExtensions.first}...${allowedExtensions.length})';
}

class RecursionFilter extends FileFilter {
  const RecursionFilter();

  @override
  bool test(String file) => !file.contains(Platform.pathSeparator);

  static const FileFilter on = RecursionFilter();

  static const FileFilter off = AllFilter();
}

class FileFilterAdapter implements TypeAdapter<FileFilter> {
  @override
  final int typeId = 3;

  @override
  FileFilter read(BinaryReader reader) {
    final type = reader.readByte();
    switch (type) {
      case 0:
        return const AllFilter();
      case 1:
        return const NoneFilter();
      case 2:
        return ChainedFilter(
          reader.readList().cast<FileFilter>(),
          reader.readBool(),
        );
      case 3:
        return ExtensionFilter(Set.from(reader.readList()));
      case 4:
        return const RecursionFilter();
      default:
        throw Exception('Unknown FileFilter type: $type');
    }
  }

  @override
  void write(BinaryWriter writer, FileFilter obj) {
    switch (obj) {
      case AllFilter _:
        writer.writeByte(0);
        break;
      case NoneFilter _:
        writer.writeByte(1);
        break;
      case ChainedFilter _:
        writer.writeByte(2);
        writer.writeList(obj.filters);
        writer.writeBool(obj.union);
        break;
      case ExtensionFilter _:
        writer.writeByte(3);
        writer.writeList(obj.allowedExtensions.toList());
        break;
      case RecursionFilter _:
        writer.writeByte(4);
        break;
    }
  }
}
