import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:styled_widget/styled_widget.dart';
import '../../data_io/file/file_selection.dart';
import '../../data_io/file/file_io.dart';
import '../../data_io/manga_loader.dart';
import '../../data_io/persistence/manga_cache.dart';

import '../../data_io/persistence/persistence.dart';
import '../../global/global.dart';
import 'album_entry.dart';

class SelectView extends StatefulWidget {
  final bool hidden;

  final double maxWidth;
  final double maxHeight;

  final void Function(MangaCache) clickCallback;

  final Widget Function(BuildContext) pinButtonBuilder;

  const SelectView({
    super.key,
    required this.clickCallback,
    required this.maxWidth,
    required this.maxHeight,
    required this.pinButtonBuilder,
    this.hidden = true,
  });

  @override
  State createState() => _SelectViewState();
}

class _SelectViewState extends State<SelectView> {
  Async<void>? loadGalleryProcess;

  final mangaList = <MangaCache>[];

  /// Sort list once after load
  bool _mangaListFinalSorted = false;

  String searchQuery = "";

  List<MangaCache>? _filteredList;

  List<MangaCache> get filteredList {
    if (_filteredList != null) {
      return _filteredList!;
    }
    if (searchQuery.isEmpty) {
      clearSearchMaybeSort();
      return _filteredList!;
    }

    final queryList =
        searchQuery.split(" ").map(getRunesForSort).map(String.fromCharCodes);
    return _filteredList = mangaList
        .where((manga) => queryList.every(manga.searchableText!.contains))
        .toList();
  }

  /// Sort only once after load gallery is done
  void clearSearchMaybeSort() {
    if (loadGalleryProcess?.isCompleted == true && !_mangaListFinalSorted) {
      _mangaListFinalSorted = true;
      mangaList.sortByCompare(
        (manga) => getRunesForSort(manga.title),
        stringRunesCompare,
      );
    }
    searchQuery = "";
    _filteredList = mangaList;
  }

  @override
  void initState() {
    super.initState();
    loadGalleryProcess = load.execute();
  }

  Future<void> release() async {
    if (loadGalleryProcess?.isCompleted == false) {
      await loadGalleryProcess!.cancel();
    }
    _mangaListFinalSorted = false;
    loadGalleryProcess = null;
    mangaList.clear();
    searchQuery = "";
    _filteredList = null;
  }

  @override
  void didUpdateWidget(covariant SelectView oldWidget) {
    super.didUpdateWidget(oldWidget);

    /// If unsorted, sort when hidden
    if (!oldWidget.hidden && widget.hidden && searchQuery.isEmpty) {
      clearSearchMaybeSort();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hidden) {
      return const SizedBox.shrink();
    }
    return buildView(context, widget.maxWidth, widget.maxHeight);
  }

  Widget _buildLoadingIndicator(BuildContext context) {
    final progressLabel = loadGalleryProcess!.signal.progressLabel;
    final formattedProgress = loadGalleryProcess!.signal.progressFormatter();
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            if (progressLabel.isNotEmpty)
              Text(
                progressLabel,
                style: Theme.of(context).textTheme.labelSmall,
                textAlign: TextAlign.center,
              ),
            if (formattedProgress.isNotEmpty)
              Text(
                formattedProgress,
                style: Theme.of(context).textTheme.labelSmall,
                textAlign: TextAlign.center,
              ),
          ],
        ).padding(horizontal: 16, top: 16, bottom: 12),
      ),
    ).clipRRect(all: 8).center();
  }

  Widget buildView(BuildContext context, double width, double height) {
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        children: [
          /// Open button and search bar
          Row(
            children: [
              const SizedBox(width: 4),

              /// "Open folder" button
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: widget.hidden
                    ? null
                    : () async {
                        final path = await FilePicker.platform.getDirectoryPath(
                          lockParentWindow: true,
                        );
                        if (path != null &&
                            path != AppStorage.instance.galleryPath) {
                          AppStorage.instance.galleryPath = path;
                          await release();
                          loadGalleryProcess = load.execute();
                          setState(() {});
                        }
                      },
              ),
              const SizedBox(width: 4),

              /// Display gallery path
              DropdownButton(
                isExpanded: true,
                value: AppStorage.instance.galleryPath,
                hint: Text(
                  "Select a folder",
                  style: Theme.of(context).textTheme.labelLarge,
                ).opacity(0.5),
                underline: const SizedBox.shrink(),
                style: Theme.of(context).textTheme.labelLarge,
                items: AppStorage.instance.galleryHistory.whereNotNull().map(
                  (path) {
                    return DropdownMenuItem(
                      value: path,
                      child: Text(
                        path,
                        style: Theme.of(context).textTheme.labelLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ).toList(),
                onChanged: (path) async {
                  if (path != AppStorage.instance.galleryPath) {
                    AppStorage.instance.galleryPath = path;
                    await release();
                    loadGalleryProcess = load.execute();
                    setState(() {});
                  }
                },
              ).expanded(),
              const SizedBox(width: 16),

              /// Search bar
              TextField(
                onChanged: (value) {
                  searchQuery = value;
                  _filteredList = null;
                  setState(() {});
                },
                enabled: !widget.hidden,
                decoration: const InputDecoration(
                  hintText: "Search",
                  border: InputBorder.none,
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ).constrained(maxWidth: width / 3),
              const SizedBox(width: 8),

              /// Pin button
              widget.pinButtonBuilder(context),
              const SizedBox(width: 4),
            ],
          ),

          /// Gallery view
          Stack(children: [
            (MasonryGridView.extent(
              padding: const EdgeInsets.only(left: 6, right: 13),
              maxCrossAxisExtent: 150,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              itemCount: filteredList.length,
              itemBuilder: (context, index) => AlbumEntry(
                  cache: filteredList[index],
                  clickCallback: () =>
                      widget.clickCallback(filteredList[index])),
            ) as Widget)
                .padding(right: 2),
            if (loadGalleryProcess?.isCompleted != true)
              _buildLoadingIndicator(context),
          ]).expanded(),
        ],
      ).clipRect(),
    );
  }

  AsyncOut<void> load(AsyncSignal signal) async {
    if (AppStorage.instance.galleryPath == null) {
      return ok;
    }
    signal.setProgress(
      progressLabel: "Listing",
      progressFormatter: () => "",
      current: 0,
    );
    // wait for 2 seconds when hidden
    if (widget.hidden) {
      await Future.any([
        Future.delayed(const Duration(seconds: 2)),
        signal.future,
      ]);
      if (signal.isTriggered) {
        return Err(signal);
      }
    }
    // list directory
    final dirEntries = await listDirectory(
      AppStorage.instance.galleryPath!,
      includeDirectory: true,
      recursive: false,
    );
    signal.setProgress(
      total: dirEntries.length.toDouble(),
    );
    if (signal.isTriggered) {
      return Err(signal);
    }
    // build MangaSource (detect archive files and directories, skip media)
    final sources =
        (await Future.wait(dirEntries.whereNot(ExtensionFilter.media.test).map(
                  (path) =>
                      MangaSource.fromPath(path, signal).asFuture.whenComplete(
                            () =>
                                signal.setProgress(current: signal.current + 1),
                          ),
                )))
            .where(Result.isOk)
            .map((e) => e.value)
            .toList();
    signal.setProgress(
      progressLabel: "Loading",
      progressFormatter: () => "${signal.current.toInt()}/${sources.length}",
      current: 0,
      total: sources.length.toDouble(),
    );
    // sort by name
    sources.sortByCompare(
      (source) => getRunesForSort(source.userShortName),
      stringRunesCompare,
    );
    // If there are media files on root directory, make a "." instead
    if (dirEntries.any(ExtensionFilter.media.test)) {
      sources.add(DirectoryMangaSource(
        AppStorage.instance.galleryPath!,
        recursive: false,
      ));
    }
    // build MangaCache and call getReady
    final cacheStream = sources
        .map((source) => (signal) => MangaCache.createFromIdentifier
            .execute(source.identifier, signal)
            .chain(ReadyFlagMixin.makeReady))
        .executeLimited(signal, 16);
    // wait for load and add to list dynamically
    await for (final cache in cacheStream) {
      signal.setProgress(current: signal.current + 1);
      if (signal.isTriggered) {
        return Err(signal);
      }
      if (cache is Ok) {
        log.t(("Album", "Loaded ${cache.value.title}"));
        mangaList.add(cache.value);
        setState(() {});
      } else {
        log.t(("Album", "failed to load $cache"));
      }
    }
    log.d(("Album", "Loaded ${mangaList.length} albums"));
    setState(() {});
    return ok;
  }

  @override
  void dispose() {
    super.dispose();
    loadGalleryProcess?.cancel();
  }
}
