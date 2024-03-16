import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:styled_widget/styled_widget.dart';

import '../../data_io/persistence/manga_cache.dart';

/// Display a manga (from a ready [MangaCache])
class AlbumEntry extends StatefulWidget {
  final MangaCache cache;

  /// Callback when clicked
  final void Function() clickCallback;

  AlbumEntry({required this.cache, void Function()? clickCallback})
      : clickCallback = clickCallback ?? (() {}),
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
        widget.cache.thumbnail!.width / widget.cache.thumbnail!.height,
        0.5,
        1.5,
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

            /// Click callback, send signal to open selected manga
            child: GestureDetector(
              onTap: widget.clickCallback,

              /// Animate overlay
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: overlayOpacity),
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
        );
      },
    );
  }
}
