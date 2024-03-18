import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart';
import 'package:image_size_getter/image_size_getter.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../../global/global.dart';
import '../../global/async/isolate_worker.dart';
import '../file/file_selection.dart';

part 'thumbnail.g.dart';

/// Used to calculate thumbnail size for images (total pixel)
const int thumbnailSize = 200000;

/// Used as thumbnail size for videos
const int thumbnailPreferredDimension = 500;

const int thumbnailIsolateCount = 4;

/// Only images larger than this size will be processed to thumbnail
const int minimumByteSizeToCreateThumbnail = 1024; // 512KB

typedef _PIM = PriorityIsolatePoolManager<int, FileData, ThumbnailInfo>;

@HiveType(typeId: 7)
class ThumbnailInfo {
  @HiveField(0)
  final Uint8List data;
  @HiveField(1)
  int? width;
  @HiveField(2)
  int? height;

  ThumbnailInfo({
    required this.data,
    this.width,
    this.height,
  });

  factory ThumbnailInfo.empty() => ThumbnailInfo(
        data: Uint8List(0),
        width: 100,
        height: 100,
      );

  /// Empty thumbnail for folder
  static Future<ThumbnailInfo> folder() async => ThumbnailInfo(
        data: await rootBundle
            .load("assets/images/image_placeholder_no_preview.webp")
            .then((b) => b.buffer.asUint8List()),
        width: 640,
        height: 640,
      );

  /// In case width and height are not provided
  AsyncOut<void> readDimensions() {
    if (width != null && height != null) {
      return ok;
    }
    return ImmutableBuffer.fromUint8List(data)
        .then(ImageDescriptor.encoded)
        .then((descriptor) {
      width = descriptor.width;
      height = descriptor.height;
      return ok;
    });
  }

  bool get isEmpty => data.isEmpty;
}

/// Isolate that processes image to thumbnail
class ThumbnailProcessor {
  static final manager = _PIM();

  static int _key = 0;

  static Completer<void>? _initialized;

  static int _generateKey() => _key += 1;

  static Future<_PIM> _maybeInitialize() => Future.sync(() async {
        if (_initialized == null) {
          _initialized = Completer();
          await manager.createIsolates.execute(
            thumbnailIsolateCount,
            () => ThumbnailWorker(),
          );
          _initialized!.complete();
        } else if (!_initialized!.isCompleted) {
          await _initialized!.future;
        }
        return manager;
      });

  /// Process an image to thumbnail
  static AsyncOut<ThumbnailInfo> process(FileData file, AsyncSignal signal) =>
      _maybeInitialize().then((manager) => manager.processWithPriority(
            _generateKey(),
            file,
            0,
            signal,
          ));

// /// Process an image to thumbnail only if it's larger than [minimumByteSizeToCreateThumbnail]
// static AsyncOut<ThumbnailInfo> maybeProcess(Uint8List input, AsyncSignal signal) {
//   if (input.lengthInBytes < minimumByteSizeToCreateThumbnail) {
//     log.t(("Thumbnail", "skipped processing image (${kb(input.lengthInBytes)})"));
//     return Ok(input);
//   }
//   return _maybeInitialize().then((manager) => manager.processWithPriority(
//         _generateKey(),
//         input,
//         0,
//         signal,
//       ));
// }
}

class ThumbnailWorker extends IsolateWorker<FileData, ThumbnailInfo> {
  Result<ThumbnailInfo> _processImage(Uint8List data) {
    /// todo: decode is taking too long (for dart native library)
    final image = decodeImage(data, frame: 0);
    if (image == null) {
      log.d(("Thumbnail", "Failed to decode image"));
      return Err("Failed to decode image");
    }
    log.t((
      "Thumbnail",
      "Decoded image (${image.width}x${image.height}, ${kb(image.lengthInBytes)})"
    ));
    final scale = math.pow(thumbnailSize / (image.width * image.height), 0.5);
    final width = (image.width * scale).ceil();
    final height = (image.height * scale).ceil();
    final thumbnail = encodeJpg(
      copyResize(
        image,
        width: width,
        height: height,
        backgroundColor: ColorUint8.rgb(0, 0, 0),
        interpolation: Interpolation.linear,
      ),
      quality: 80,
    );
    log.t((
      "Thumbnail",
      "Complete processing thumbnail (${width}x$height, ${kb(thumbnail.lengthInBytes)})"
    ));
    return Ok(ThumbnailInfo(data: thumbnail, width: width, height: height));
  }

  Future<Result<ThumbnailInfo>> _processVideo(String source) async {
    final tempPath =
        await getTemporaryDirectory().then((d) => join(d.path, uuid.v4()));
    return FcNativeVideoThumbnail()
        .getVideoThumbnail(
      srcFile: source,
      destFile: tempPath,
      width: thumbnailPreferredDimension,
      height: thumbnailPreferredDimension,
      keepAspectRatio: true,
      format: "jpeg",
      quality: 80,
    )
        .then((v) {
      return v;
    }).then((success) async {
      if (!success) {
        return Err("Failed to create thumbnail");
      }
      // we can't generate descriptor in isolate
      final thumbnailData = File(tempPath).readAsBytesSync();
      try {
        final size = ImageSizeGetter.getSize(MemoryInput(thumbnailData));
        return Ok(ThumbnailInfo(
          data: thumbnailData,
          width: size.width,
          height: size.height,
        ));
      } on UnsupportedError catch (e) {
        // if format is not supported, leave the size getting to main isolate
        return Ok(ThumbnailInfo(data: thumbnailData));
      }
    });
  }

  @override
  AsyncOut<ThumbnailInfo> process(FileData input) {
    log.t(("Thumbnail", "Start processing data (${kb(input.byteSize)})"));
    switch (input) {
      case ImageMemoryData _:
        return _processImage(input.bytes);
      case VideoFileData _:
        return _processVideo(input.tempPath);
    }
  }
}
