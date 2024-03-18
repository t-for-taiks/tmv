import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:styled_widget/styled_widget.dart';
import 'package:tmv/data_io/file/file_selection.dart';
import 'package:tmv/global/collection/collection.dart';
import 'package:tmv/global/config.dart';
import 'package:tmv/ui/manga/media_display.dart';
import 'package:yaml_writer/yaml_writer.dart';

import '../../data_io/file/file_pick.dart';
import '../../data_io/persistence/manga_cache.dart';
import '../../global/helper.dart';
import '../../data_io/manga_loader.dart';
import 'manga_scroll.dart';
import '../../data_io/persistence/persistence.dart';
import '../../global/global.dart';

part 'manga_view.g.dart';

/// [MangaSource] have to be ready
@HiveType(typeId: 0)
class MangaViewData
    with BoxStorage<MangaViewData>, ReadyFlagMixin<MangaViewData> {
  MangaCache? cache;

  @HiveField(0)
  final MangaSource source;

  @HiveField(1)
  final FileSelection selection;

  @HiveField(2)
  int currentPage = 0;

  static const _boxPath = "_";

  static const _boxKey = "MangaViewData";

  @override
  String get boxPath => _boxPath;

  @override
  String get boxKey => _boxKey;

  static AsyncOut<MangaViewData> tryLoad(AsyncSignal signal) =>
      Storage.tryLoad(_boxPath, _boxKey, signal);

  void changePage(int index) {
    currentPage = index;
    markAsDirty();
  }

  /// Specified file to open (in case user opens a single file)
  String? openedFile;

  String get title => cache?.title ?? source.userShortName;

  MangaViewData(this.source, {FileSelection? selection, this.openedFile})
      : selection = selection ?? FileSelection();

  @override
  AsyncOut<void> getReady(AsyncSignal signal) =>
      source.ensureReady.execute(signal).whenComplete(() {
        selection.fileSource = () => source.files;
        if (openedFile != null) {
          final index = selection.fileIndex[openedFile] ?? -1;
          if (index != -1) {
            changePage(index);
          } else {
            log.t(("MangaView", "File not found: $openedFile"));
          }
          openedFile = null;
        }
      });

  AsyncOut<FileData> getFileData(int index,
      [Priority? priority, AsyncSignal? signal]) async {
    if (index < 0 || index >= selection.length) {
      return Err();
    }
    final file = selection.files[index];
    final additionalTextFile = selection.additionalTextFiles[index];
    final String? textData;
    if (additionalTextFile != null) {
      textData = await source.getData
          .execute(additionalTextFile, priority, signal)
          .map(utf8.decode)
          .valueOrNull();
    } else {
      textData = null;
    }
    switch (ExtensionFilter.getType(file)) {
      case ExtensionFilter.image:
        return source.getData
            .execute(file, priority, signal)
            .map((data) => ImageMemoryData(
                  bytes: data,
                  path: file,
                  additionalText: textData,
                  byteSize: data.length,
                ));
      case ExtensionFilter.video:
        switch (source) {
          case DirectoryMangaSource _:
            return VideoFileData(
              tempPath: source.getFilePath(file)!,
              path: file,
              additionalText: textData,
              byteSize: await File(source.getFilePath(file)!).length(),
            ).asOk;
          case ArchiveMangaSource():
          case WebArchiveMangaSource():
            return await source.getData.execute(file, priority, signal).chain(
                  (data, signal) => VideoFileData.buildPath(data, signal).map(
                    (tempPath) => VideoFileData(
                      tempPath: tempPath,
                      path: file,
                      additionalText: textData,
                      byteSize: data.length,
                    ),
                  ),
                );
          case NullMangaSource():
            throw UnimplementedError();
        }
      default:
        log.w(("MangaView", "Unknown file type: $file"));
        return Err();
    }
  }

  @override
  void release() {
    super.release();
    selection.dispose();
  }

  @override
  void dispose() {
    super.dispose();
    release();
  }

  Object toJsonObject() => {
        "_": "MangaViewData",
        "cache": cache?.title,
        "selection": selection.toJsonObject(),
        "currentPage": currentPage,
        "openedFile": openedFile,
      };

  @override
  String toString() => YamlWriter().write(toJsonObject());

  @override
  bool operator ==(Object other) {
    if (other is MangaViewData) {
      return source == other.source && selection == other.selection;
    }
    return false;
  }

  @override
  int get hashCode => source.hashCode;
}

class MangaView extends StatefulWidget {
  const MangaView({super.key});

  @override
  MangaViewState createState() => MangaViewState();
}

class MangaViewState extends State<MangaView>
    with ReadyFlagMixin<MangaViewState>, SignalEmitter<MangaViewData?> {
  MangaViewData? data;

  AsyncOut<void> setData(MangaViewData? value, AsyncSignal signal) async {
    notifyListeners(data);
    if (data == value) {
      if (data == null) {
        return ok;
      }
      return await data!.ensureReady.execute(signal);
    }
    data = value;
    release();
    setState(() {});
    return await whenReady(() => setState(() => notifyListeners(data)));
  }

  int get length => data!.selection.length;

  List<String> get files => data!.selection.files;

  MangaSource get source => data!.source;

  /// Pool of MediaDisplay widgets
  PriorityPool<String, MediaDisplay> children = PriorityPool();

  /// Key of the image with "hidden=false" (only one)
  String? currentShowKey;

  bool showInfo = true;

  /// Total bytes of all loaded images in [children]
  int totalBytes = 0;

  double get fillFactor => totalBytes / defaultImageCacheSize;

  /// Dynamic control of preload range
  double preloadMultiplier = 10;

  int get preloadUpper => (preloadMultiplier * forcedPreloadRangeUpper).floor();

  int get preloadLower => (preloadMultiplier * forcedPreloadRangeLower).floor();

  bool inPreloadRange(int index) =>
      index >= data!.currentPage - preloadLower &&
      index <= data!.currentPage + preloadUpper;

  @override
  void initState() {
    super.initState();
    setData.execute(data);
  }

  @override
  void dispose() {
    super.dispose();
    release();
  }

  /// If current image is not loaded, remove all non-ready images
  /// (part of [_updateChildren])
  ///
  /// This will remove the non-ready image widgets, thus calling dispose()
  /// on widgets which interrupts the loading process
  void _loadCurrent() {
    final current = data!.currentPage;
    final currentKey = files[current];
    log.t(("MangaView", "load current: $current:$currentKey"));
    children.removeWhere((key, display) => !display.isLoaded);
    // add current image widget
    children.push(
      currentKey,
      // current image is hidden until loaded
      _buildMediaDisplay(current, hidden: true),
      0,
    );
  }

  /// Show current image and hide others
  /// (part of [_updateChildren])
  void _updateHidden() {
    final current = data!.currentPage;
    final currentKey = files[current];
    if (currentShowKey != null &&
        currentShowKey != currentKey &&
        children.containsKey(currentShowKey!)) {
      log.t(
          ("MangaView", "_updateHidden: $currentKey replace $currentShowKey"));
      children.updateData(
        currentShowKey!,
        _buildMediaDisplay(
          data!.selection.fileIndex[currentShowKey]!,
          hidden: true,
        ),
      );
    }
    children.updateData(
      currentKey,
      _buildMediaDisplay(current, hidden: false),
    );
    currentShowKey = currentKey;
  }

  /// Preload priority is based on distance from current page
  /// (part of [_updateChildren])
  double _computePriority(int index) {
    final current = data!.currentPage;
    if (index < current) {
      return (current - index) / preloadLower;
    } else {
      return (index - current) / preloadUpper;
    }
  }

  /// Iterate through the preload range and return the indices to preload
  /// (part of [_updateChildren])
  int? _indexToPreload() {
    final current = data!.currentPage;
    for (int i = 1;
        i <= math.min(length, math.max(preloadLower, preloadUpper));
        i += 1) {
      if (i <= preloadUpper &&
          current + i < length &&
          !children.containsKey(files[current + i])) {
        return current + i;
      }
      if (i <= preloadLower &&
          current - i >= 0 &&
          !children.containsKey(files[current - i])) {
        return current - i;
      }
    }
    return null;
  }

  /// Reduce preload range if memory load is heavy
  /// (part of [_updateChildren])
  ///
  /// Returns true if preload range is adjusted
  bool _maybeDecreasePreloadRange() {
    if (preloadMultiplier > 1) {
      preloadMultiplier = math.max(1, preloadMultiplier * 0.8);
      log.t(("MangaView", "pM-: $preloadMultiplier"));
      return true;
    } else {
      return false;
    }
  }

  /// Increase preload range if memory load is light
  /// (part of [_updateChildren])
  bool _maybeIncreasePreloadRange() {
    if (fillFactor < 0.5 && preloadMultiplier < length.toDouble()) {
      preloadMultiplier *= 1.6;
      log.t(("MangaView", "pM+: $preloadMultiplier"));
      return true;
    }
    return false;
  }

  /// Free up memory if cache is full, but never remove images in preload range
  ///
  /// Returns true if capacity available after freeing
  bool _maybeFreeCapacity() {
    while (fillFactor > 1) {
      final entry = children.top;
      if (inPreloadRange(data!.selection.fileIndex[entry.key]!)) {
        log.t(("MangaView", "skip ${entry.key}"));
        return false;
      }
      log.t(("MangaView", "remove ${entry.key}"));
      children.pop();
    }
    return true;
  }

  /// Called on [build] to update [children]
  ///
  /// (Cannot call [setState] here. [MediaDisplay] created by [_buildMediaDisplay]
  /// will call [setState] when it's loaded)
  void _updateChildren() {
    final current = data!.currentPage;
    final currentKey = files[current];
    final fileIndex = data!.selection.fileIndex;
    log.t((
      "MangaView",
      "_updateChildren: $current:$currentKey, csk:$currentShowKey"
    ));
    if (!children.containsKey(currentKey)) {
      _loadCurrent();
      if (currentShowKey != null && children.containsKey(currentShowKey!)) {
        children.updateData(
            currentShowKey!,
            _buildMediaDisplay(
              fileIndex[currentShowKey]!,
              hidden: false,
              blurred: true,
            ));
      }
      return;
    }

    /// Check if any image is not loaded. This is performed before changing
    /// hidden, because changing hidden will make image not loaded
    final hasImageNotLoaded =
        children.values.any((display) => !display.isLoaded);

    /// When the current image is loaded, show it and hide others
    _updateHidden();

    /// If any image is not loaded, wait for them to load
    if (hasImageNotLoaded) {
      log.t(("MangaView", "waiting for load"));
      return;
    }

    /// Since all images are loaded, check on capacity and start preloading
    // if no images to preload, maybe increase preload range
    var index = _indexToPreload();
    while (_maybeIncreasePreloadRange() && index == null) {
      index = _indexToPreload();
    }
    if (index == null) {
      // no images to preload
      return;
    }
    if (fillFactor > 1) {
      log.t(("MangaView", "cache full"));

      /// Update priority for existing images
      for (final key in children.keys.toList()) {
        // Images far from current page are given lower priority
        children.updatePriority(
          key,
          _computePriority(fileIndex[key]!),
        );
      }
      // free up capacity and reduce preload range if necessary
      while (!_maybeFreeCapacity() && _maybeDecreasePreloadRange()) {}
      index = _indexToPreload();
      if (index == null) {
        return;
      }
    }
    log.t(("MangaView", "preloading $index"));

    /// Preload image
    children.push(
      files[index],
      _buildMediaDisplay(index, hidden: true),
      _computePriority(index),
    );
  }

  /// Build one single image, and triggers rebuild when loaded
  MediaDisplay _buildMediaDisplay(
    int index, {
    required bool hidden,
    bool blurred = false,
  }) {
    final image = MediaDisplay(
      key: ValueKey("${source.identifier}:$index"),
      dataSource: (signal) {
        if (signal.isTriggered || !isReady) {
          return Err(signal);
        }
        return data!.getFileData(
          index,
          hidden ? Priority.normal : Priority.high,
          signal,
        );
      },
      sizeUpdateCallback: (size) => totalBytes += size,
      hidden: hidden,
      blurred: blurred,
      debugInfo: index,
      showInfo: showInfo,
    );
    log.t((
      "MangaView",
      "build image: $index, hidden: $hidden, blurred: $blurred"
    ));
    image.buildComplete.whenComplete(() => setState(() {}));
    return image;
  }

  /// Show a message with a "open" button
  Widget _buildDefaultMessage(BuildContext context, String message) {
    final buttons = <Widget>[];

    /// "Open file" button
    buttons.add(Padding(
      padding: const EdgeInsets.only(top: 8),
      child: MaterialButton(
        onPressed: () => pickAndOpenFile.execute().chain(setData),
        color: Theme.of(context).colorScheme.inverseSurface,
        child: Text("Open file", style: Theme.of(context).textTheme.labelLarge)
            .textColor(Theme.of(context).colorScheme.onInverseSurface),
      ),
    ));

    /// "Open folder" button
    if (allowOpenDirectory) {
      buttons.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: MaterialButton(
          onPressed: () => pickAndOpenDirectory.execute().chain(setData),
          color: Theme.of(context).colorScheme.inverseSurface,
          child:
              Text("Open folder", style: Theme.of(context).textTheme.labelLarge)
                  .textColor(Theme.of(context).colorScheme.onInverseSurface),
        ),
      ));
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          message,
          style: Theme.of(context).textTheme.labelLarge,
        ).textColor(Theme.of(context).colorScheme.onSurface).center(),
        Column(children: buttons),
      ],
    );
  }

  Widget _buildDebug(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        "fillFactor: ${fillFactor.toStringAsFixed(2)}",
        "current page: ${data!.currentPage}",
        "total entries loaded: ${children.length}",
        "preloadMultiplier: ${preloadMultiplier.toStringAsFixed(2)}",
        "preloadRange: $preloadLower - $preloadUpper",
        "totalBytes: ${kb(totalBytes)}",
      ]
          .map(
            (text) => Text(
              text,
              textAlign: TextAlign.left,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
          .toList(),
    )
        .backgroundBlur(16)
        .backgroundColor(Theme.of(context).colorScheme.surface.withOpacity(0.7))
        .clipRRect(all: 8)
        .padding(all: 8);
  }

  Widget _buildContent(BuildContext context) {
    if (data == null) {
      return _buildDefaultMessage(context, "No file opened.");
    }
    if (!isReady) {
      whenReady(() => setState(() {}));
      return const Center(child: CircularProgressIndicator());
    }
    if (length == 0) {
      return _buildDefaultMessage(context, "No image found.");
    }
    _updateChildren();
    log.t(("MangaView", "build elements: ${children.keys.sorted()}"));
    return Listener(
      onPointerSignal: mouseCallback,
      // Allow pointer events to trigger on whitespace
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Stack(
            children: [
              ...children,
              if (kDebugMode) _buildDebug(context),
            ],
          ).height(double.infinity).expanded(),
          Column(
            children: [
              VerticalMangaScroll(
                index: data!.currentPage,
                title: files[data!.currentPage],
                total: length,
                switchPageCallback: gotoPage,
              ).expanded(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: showInfo
                    ? const Icon(Icons.info_rounded)
                    : const Icon(Icons.info_outline_rounded),
                onPressed: () => setState(() => showInfo = !showInfo),
                padding: const EdgeInsets.all(2),
              ),
            ],
          ).backgroundColor(
            Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Focus sets keyboard listener
    // keep focus always here to prevent losing focus (missing shortcut trigger)
    return Focus(
      autofocus: true,
      onKeyEvent: keyCallback,
      // This listener is for scrolling events
      child: _buildContent(context),
    );
  }

  void nextPage() {
    gotoPage(data!.currentPage + 1);
  }

  void prevPage() {
    gotoPage(data!.currentPage - 1);
  }

  void gotoPage(int index) {
    index = math.max(0, math.min(index, length - 1));
    if (index != data!.currentPage) {
      setState(() => data!.changePage(index));
    }
  }

  /// Callback to key actions
  /// - Page changes: Up, Down, PageUp, PageDown, Home, End
  KeyEventResult keyCallback(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      switch (event.logicalKey) {
        // Down: next page
        case LogicalKeyboardKey.arrowDown:
        case LogicalKeyboardKey.pageDown:
          nextPage();
          return KeyEventResult.handled;
        // Up: prev lage
        case LogicalKeyboardKey.arrowUp:
        case LogicalKeyboardKey.pageUp:
          prevPage();
          return KeyEventResult.handled;
        // Home: first page
        case LogicalKeyboardKey.home:
          gotoPage(0);
          return KeyEventResult.handled;
        // End: last page
        case LogicalKeyboardKey.end:
          gotoPage(length - 1);
          return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Callback to mouse actions
  /// - Scroll: switch pages
  void mouseCallback(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      scrollCallback(event);
    }
  }

  /// Switch page if there's a vertical scroll
  void scrollCallback(PointerScrollEvent event) {
    final angle = event.scrollDelta.direction;
    if (angle > math.pi / 4 && angle < math.pi * 0.75) {
      nextPage();
    } else if (angle < -math.pi / 4 && angle > -math.pi * 0.75) {
      prevPage();
    }
  }

  @override
  AsyncOut getReady(AsyncSignal signal) =>
      data?.ensureReady(signal) ?? ok.cast();

  @override
  void release() {
    super.release();
    children = PriorityPool();
    currentShowKey = null;
    totalBytes = 0;
    preloadMultiplier = 10;
  }
}
