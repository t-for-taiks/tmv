import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart';

import '../../global/global.dart';
import '../../global/async/isolate_worker.dart';

part 'thumbnail.g.dart';

const int thumbnailSize = 200000;

const int thumbnailIsolateCount = 4;

/// Only images larger than this size will be processed to thumbnail
const int minimumByteSizeToCreateThumbnail = 1024; // 512KB

typedef _PIM = PriorityIsolatePoolManager<int, Uint8List, ThumbnailInfo>;

@HiveType(typeId: 7)
class ThumbnailInfo {
  @HiveField(0)
  final Uint8List data;
  @HiveField(1)
  final int width;
  @HiveField(2)
  final int height;

  const ThumbnailInfo({
    required this.data,
    required this.width,
    required this.height,
  });

  factory ThumbnailInfo.empty() => ThumbnailInfo(
        data: Uint8List(0),
        width: 100,
        height: 100,
      );

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
  static AsyncOut<ThumbnailInfo> process(Uint8List input, AsyncSignal signal) =>
      _maybeInitialize().then((manager) => manager.processWithPriority(
            _generateKey(),
            input,
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

class ThumbnailWorker extends IsolateWorker<Uint8List, ThumbnailInfo> {
  @override
  FutureOr<Result<ThumbnailInfo>> process(Uint8List input) {
    log.t(("Thumbnail", "Start processing data (${kb(input.lengthInBytes)})"));

    /// todo: decode is taking too long (for dart native library)
    final image = decodeImage(input, frame: 0);
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
}
