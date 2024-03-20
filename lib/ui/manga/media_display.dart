import "dart:async";
import "dart:math" as math;
import "dart:ui";

import "package:flutter/material.dart";
import "package:flutter_context_menu/flutter_context_menu.dart";
import "package:media_kit/media_kit.dart";
import "package:media_kit_video/media_kit_video.dart";
import "package:styled_widget/styled_widget.dart";

import "../../data_io/file/file_selection.dart";
import "../../data_io/manga_loader.dart";
import "../../data_io/persistence/thumbnail.dart";
import "../../global/config.dart";
import "../../global/global.dart";

class MediaDisplay extends StatefulWidget {
  final AsyncExecutor0<FileData> dataSource;

  final MangaSource source;

  /// Signal to parent widget, resolve when image is loaded
  ///
  /// Return the size of the image in bytes
  final Async<int> buildComplete = Async.completer();

  /// Image not visible, but data is still buffered
  final bool hidden;

  /// Image visible, but blurred to hint user that another is being loaded
  final bool blurred;

  /// Show additional text
  final bool showInfo;

  final Object? debugInfo;

  /// Flag on image load completion
  bool get isLoaded => buildComplete.isCompleted;

  /// Key is the same across rebuild, so that the widget doesn't need
  /// to be recreated when reordering images
  MediaDisplay({
    super.key,
    required this.dataSource,
    required this.source,
    required this.hidden,
    this.blurred = false,
    required this.showInfo,
    this.debugInfo,
  });

  @override
  State<StatefulWidget> createState() => _MediaDisplayState();
}

class _MediaDisplayState extends State<MediaDisplay> {
  /// File data
  FileData? data;

  Player? videoPlayer;

  VideoController? videoController;

  /// Process of decoding and displaying the image
  ///
  /// Complete when Image frame is built
  late final Async loadProcess;

  late final int totalSizeBytes;

  /// Signal to be triggered by image load completion, and completes [loadProcess]
  final Completer<void> decodeCompleter = Completer();

  late final Object? debugInfo;

  late final int mediaWidth;

  late final int mediaHeight;

  double get aspectRatio => mediaWidth / mediaHeight;

  @override
  void initState() {
    super.initState();
    debugInfo = "${widget.debugInfo} ${uuid.v4().substring(0, 8)}";
    loadProcess = load.execute();
  }

  AsyncOut<void> _getImageDimensions(AsyncSignal signal) async {
    try {
      final buffer =
          await ImmutableBuffer.fromUint8List((data as ImageMemoryData).bytes);
      final descriptor = await ImageDescriptor.encoded(buffer);
      // this is not accurate, because video is streamed from file
      totalSizeBytes =
          descriptor.width * descriptor.height * descriptor.bytesPerPixel;
      mediaWidth = descriptor.width;
      mediaHeight = descriptor.height;
      return ok;
    } catch (error, stack) {
      return Err(error, stack);
    }
  }

  AsyncOut<void> _getVideoDimensions(AsyncSignal signal) {
    mediaWidth = videoPlayer!.state.width!;
    mediaHeight = videoPlayer!.state.height!;
    // limit the number of videos to cache
    totalSizeBytes = math.max(
      (data as VideoFileData).byteSize!,
      (defaultImageCacheSize / 4).floor(),
    );
    return ok;
  }

  /// The entire process from loading image bytes data to display
  ///
  /// Return true if complete, false if canceled
  AsyncOut<void> load(AsyncSignal signal) =>
      widget.dataSource.execute(signal).chain((data, signal) async {
        if (signal.isTriggered) {
          return Err(signal);
        }
        this.data = data;
        // update widget tree to build
        setState(() {});
        log.t(("schedule", "start decode $debugInfo"));
        // wait for image to decode / video to open
        await Future.any([decodeCompleter.future, signal.future]);
        if (signal.isTriggered) {
          return Err(signal);
        }
        if (data is ImageMemoryData) {
          await _getImageDimensions.execute();
        } else if (data is VideoFileData) {
          await _getVideoDimensions.execute();
        }
        log.t(("schedule", "decode complete $debugInfo"));
        widget.buildComplete.completeOk(totalSizeBytes);
        return ok;
      });

  @override
  void didUpdateWidget(covariant MediaDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (loadProcess.isCompleted) {
      widget.buildComplete.complete(Err());
    }
    if (videoPlayer != null) {
      if (oldWidget.hidden && !widget.hidden) {
        videoPlayer!.play();
        videoPlayer!.setPlaylistMode(PlaylistMode.single);
      } else if (widget.hidden || widget.blurred) {
        videoPlayer!.pause();
      }
    }
  }

  /// This will be called when media is requested to load, but whether it's
  /// shown is determined by [MediaDisplay.hidden]
  Widget _buildImage(BuildContext context, ImageMemoryData data) {
    final image = Image(
      image: MemoryImage(data.bytes),
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
    return image;
  }

  /// This will be called when media is requested to load, but whether it's
  /// shown is determined by [MediaDisplay.hidden]
  Widget _buildVideo(BuildContext context, VideoFileData data) {
    if (videoPlayer == null) {
      videoPlayer = Player();
      videoController = VideoController(videoPlayer!);
      videoPlayer!.open(Media(data.tempPath), play: false);
      videoPlayer!.stream.width
          .firstWhere((v) => v != null)
          .then(decodeCompleter.complete)
          // if disposed before first frame, an error can be thrown. Ignore it
          .catchError((e) => null);
    }

    if (widget.hidden) {
      return const SizedBox.shrink();
    }

    return Video(controller: videoController!);
  }

  Widget _buildAdditionalText(BuildContext context) {
    if (!loadProcess.isCompleted) {
      return const SizedBox.shrink();
    }
    final view = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data!.path != null)
              Text(
                data!.path!,
                style: Theme.of(context).textTheme.labelSmall,
                softWrap: true,
              ),
            if (data!.byteSize != null)
              Text(
                "${data!.byteSize!.toKb}  ${mediaWidth}x$mediaHeight",
                style: Theme.of(context)
                    .textTheme
                    .labelSmall!
                    .copyWith(fontWeight: FontWeight.w300),
                overflow: TextOverflow.ellipsis,
              ),
            if ((data!.path != null || data!.byteSize != null) &&
                data!.additionalText != null)
              const SizedBox(height: 8),
            if (data!.additionalText != null)
              Text(
                data!.additionalText!,
                style: Theme.of(context).textTheme.bodyMedium,
              ).scrollable().constrained(maxHeight: 200),
          ],
        ).padding(all: 8).constrained(maxWidth: 200),
      ),
    );
    return Positioned(
      bottom: 16,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: widget.blurred
            ? ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: view)
            : view,
      ),
    );
  }

  ContextMenu _buildContextMenu(BuildContext context) => ContextMenu(
        entries: [
          MenuItem(
            label: "Set as Manga Cover",
            icon: Icons.image_outlined,
            onSelected: () async {
              if (!mounted || widget.hidden || widget.blurred || data == null) {
                return;
              }
              final identifier = widget.source.identifier;
              final ImageMemoryData image;
              if (data is ImageMemoryData) {
                image = data as ImageMemoryData;
              } else {
                final screenshot = await videoPlayer!.screenshot();
                if (screenshot == null) {
                  return;
                }
                image = ImageMemoryData(
                  bytes: screenshot,
                  byteSize: screenshot.length,
                );
              }
              await ThumbnailProcessor.process
                  .execute(image)
                  .map((thumbnail) => ThumbnailInfo.put(identifier, thumbnail));
            },
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const SizedBox.shrink();
    }
    Widget view;
    if (data is ImageMemoryData) {
      view = _buildImage(context, data as ImageMemoryData);
    } else if (data is VideoFileData) {
      view = _buildVideo(context, data as VideoFileData);
    } else {
      throw UnimplementedError();
    }
    if (!widget.hidden && !widget.blurred) {
      view = ContextMenuRegion(
        contextMenu: _buildContextMenu(context),
        child: view,
      );
    }
    return Stack(
      children: [
        if (!widget.blurred || !loadProcess.isCompleted)
          view
        else
          ImageFiltered(
            key: UniqueKey(),
            imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: view,
          ).aspectRatio(aspectRatio: aspectRatio).clipRect().center(),
        if (!widget.hidden && widget.showInfo) _buildAdditionalText(context),
      ],
    );
  }

  @override
  void dispose() {
    super.dispose();
    loadProcess.cancel();
    videoPlayer?.dispose();
    widget.buildComplete.complete(Err("disposed"));
  }
}
