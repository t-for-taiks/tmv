import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:path/path.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:tmv/data_io/manga_loader.dart';
import 'package:tmv/ui/drawer/about.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yaml_writer/yaml_writer.dart';

import '../../data_io/persistence/manga_cache.dart';

/// Display a manga (from a ready [MangaCache])
class AlbumEntry extends StatefulWidget {
  final MangaCache cache;

  /// Callback when clicked
  final void Function() openMangaCallback;

  /// Callback when opened as gallery
  final void Function() openGalleryCallback;

  AlbumEntry({
    required this.cache,
    void Function()? openMangaCallback,
    void Function()? openGalleryCallback,
  })  : openMangaCallback = openMangaCallback ?? (() {}),
        openGalleryCallback = openGalleryCallback ?? (() {}),
        super(key: ValueKey(cache));

  @override
  State createState() => _AlbumEntryState();
}

class _AlbumEntryState extends State<AlbumEntry> {
  /// Overlay is shown when the mouse enters
  ///
  /// Set to 0 or 1, and tween will animate it
  double overlayOpacity = 0;

  double get aspectRatio => clampDouble(
        widget.cache.thumbnail!.width! / widget.cache.thumbnail!.height!,
        0.5,
        1.5,
      );

  ContextMenu _buildContextMenu(BuildContext context) => ContextMenu(
        entries: [
          // const MenuHeader(text: "Context Menu"),
          MenuItem(
            label: 'Open as Manga',
            icon: Icons.file_open_outlined,
            onSelected: () {
              widget.openMangaCallback();
            },
          ),
          MenuItem(
            label: 'Open as Gallery',
            icon: Icons.drive_folder_upload,
            onSelected: () {
              if (widget.cache.source is DirectoryMangaSource) {
                widget.openGalleryCallback();
              } else {
                showDefaultDialog(
                    context: context,
                    child: const Text("Only support directories for now"));
              }
            },
          ),
          MenuItem(
            label: 'Show Info',
            icon: Icons.info_outline_rounded,
            onSelected: () {
              showDialog(
                context: context,
                builder: (context) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.memory(widget.cache.thumbnail!.data)
                        .constrained(maxWidth: 300),
                    const SizedBox(width: 16),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.cache.title,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "${widget.cache.source.path ?? "<unknown path>"}\n${widget.cache.length} files",
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall!
                              .copyWith(fontWeight: FontWeight.w300),
                          softWrap: true,
                        ).opacity(0.5),
                        if (widget.cache.info?.isNotEmpty == true)
                          const SizedBox(height: 16),
                        if (widget.cache.info?.isNotEmpty == true)
                          Text(
                            YamlWriter().write(widget.cache.info!).trim(),
                            style: Theme.of(context).textTheme.bodySmall,
                            softWrap: true,
                          ),
                      ],
                    ).scrollable().expanded(),
                  ],
                )
                    .padding(all: 16)
                    .backgroundBlur(12)
                    .backgroundColor(
                      Theme.of(context).colorScheme.surface.withOpacity(0.8),
                    )
                    .clipRRect(all: 8)
                    .constrained(maxWidth: 600)
                    .padding(vertical: 80)
                    .center(),
              );
            },
          ),
          MenuItem(
            label: 'Open in File Explorer',
            icon: Icons.screen_search_desktop_outlined,
            onSelected: () {
              if (widget.cache.source.path == null) {
                showDefaultDialog(
                  context: context,
                  child: const Text("No path available"),
                );
                return;
              }
              if (FileSystemEntity.isFileSync(widget.cache.source.path!)) {
                launchUrl(toUri(dirname(widget.cache.source.path!)));
              } else {
                launchUrl(toUri(widget.cache.source.path!));
              }
            },
          )
        ],
      );

  @override
  void initState() {
    super.initState();
    assert(widget.cache.isReady);
  }

  @override
  Widget build(BuildContext context) {
    /// Get width constrain
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        /// Force aspect ratio
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: width / aspectRatio,
          ),

          /// Show overlay when mouse enters
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => overlayOpacity = 1),
            onExit: (_) => setState(() => overlayOpacity = 0),

            /// Context menu
            child: ContextMenuRegion(
              contextMenu: _buildContextMenu(context),

              /// Click callback, send signal to open selected manga
              child: GestureDetector(
                onTap: () {
                  if (widget.cache.containsSub) {
                    widget.openGalleryCallback();
                  } else {
                    widget.openMangaCallback();
                  }
                },

                /// Animate overlay
                child: TweenAnimationBuilder<double>(
                  tween: Tween(
                      begin: 0,
                      end:
                          widget.cache.thumbnail!.isEmpty ? 1 : overlayOpacity),
                  duration: const Duration(milliseconds: 200),
                  builder: (context, value, child) => Stack(
                    children: [
                      /// Thumbnail + blur if hovered
                      ImageFiltered(
                        imageFilter:
                            ImageFilter.blur(sigmaX: value, sigmaY: value),
                        child: Container(
                          width: width,
                          height: width / aspectRatio,
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: widget.cache.thumbnailImage,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ).clipRect(),

                      /// When hovered, add a text overlay
                      ColoredBox(
                        color: Theme.of(context)
                            .colorScheme
                            .inverseSurface
                            .withOpacity(value * .6),
                        child: Text(
                          widget.cache.title,
                          style: Theme.of(context).textTheme.labelSmall,
                          textAlign: TextAlign.center,
                        )
                            .textColor(
                              Theme.of(context).colorScheme.onInverseSurface,
                            )
                            .fontWeight(FontWeight.w700)
                            .opacity(value)
                            .padding(horizontal: 8)
                            .center(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
