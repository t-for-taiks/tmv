import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:styled_widget/styled_widget.dart';

import '../../global/global.dart';

class ImageDisplay extends StatefulWidget {
  final AsyncExecutor0<Uint8List> imageSource;

  /// Signal to parent widget, resolve when image is loaded
  ///
  /// Returns total bytes of the image when image is loaded for the first time,
  /// otherwise resolves with 0 instantly
  /// todo: add multi-frame gif support
  final Async<int> buildComplete = Async.completer();

  /// Image not visible, but data is still buffered
  final bool hidden;

  /// Image visible, but blurred to hint user that another is being loaded
  final bool blurred;

  final Object? debugInfo;

  /// Flag on image load completion
  bool get isLoaded => buildComplete.isCompleted;

  /// Key is the same across rebuild, so that the widget doesn't need
  /// to be recreated when reordering images
  ImageDisplay({
    super.key,
    required this.imageSource,
    required this.hidden,
    this.blurred = false,
    this.debugInfo,
  });

  @override
  State<StatefulWidget> createState() => _ImageDisplayState();
}

class _ImageDisplayState extends State<ImageDisplay> {
  /// Image bytes data
  Uint8List? data;

  /// Process of decoding and displaying the image
  ///
  /// Complete when Image frame is built
  late final Async loadProcess;

  late final int totalSizeBytes;

  /// Signal to be triggered by image load completion, and completes [loadProcess]
  final Completer<void> decodeCompleter = Completer();

  late final Object? debugInfo;

  late final double aspectRatio;

  @override
  void initState() {
    super.initState();
    debugInfo = "${widget.debugInfo} ${uuid.v4().substring(0, 8)}";
    loadProcess = load.execute();
  }

  /// The entire process from loading image bytes data to display
  ///
  /// Return true if complete, false if canceled
  AsyncOut<bool> load(AsyncSignal signal) =>
      widget.imageSource.execute(signal).chain((data, signal) async {
        this.data = data;
        // read dimensions
        final buffer = await ImmutableBuffer.fromUint8List(data);
        final descriptor = await ImageDescriptor.encoded(buffer);
        totalSizeBytes =
            descriptor.width * descriptor.height * descriptor.bytesPerPixel;
        aspectRatio = descriptor.width / descriptor.height;
        if (signal.isTriggered) {
          return Err(signal);
        }
        // update widget tree to build image
        setState(() {});
        log.t(("schedule", "start decode $debugInfo"));
        // wait for image to be displayed
        await Future.any([decodeCompleter.future, signal.future]);
        if (signal.isTriggered) {
          log.t(("schedule", "decode cancelled $debugInfo"));
          return Err(signal);
        }
        log.t(("schedule", "decode complete $debugInfo"));
        widget.buildComplete.complete(totalSizeBytes);
        return Ok(decodeCompleter.isCompleted);
      });

  @override
  void didUpdateWidget(covariant ImageDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (loadProcess.isCompleted) {
      widget.buildComplete.complete(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (data != null) {
      final image = Image(
        image: MemoryImage(data!),
        frameBuilder: (context, child, frame, flag) {
          if (frame != null && !decodeCompleter.isCompleted) {
            decodeCompleter.complete(null);
          }
          return child;
        },
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        opacity: AlwaysStoppedAnimation(widget.hidden ? 0 : 1),
      );

      if (widget.blurred) {
        return ImageFiltered(
          key: UniqueKey(),
          imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: image,
        ).aspectRatio(aspectRatio: aspectRatio).clipRect().center();
      }
      return image;
    } else {
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    super.dispose();
    loadProcess.cancel();
    widget.buildComplete.complete(Err("disposed"));
  }
}
