import 'dart:ui';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:styled_widget/styled_widget.dart';

/// A builder for the view of a drawer entry
///
/// If [DrawerEntry.neverDestroy] is true, [show] can be false when the view is
/// not visible, in which case builder should return an empty widget
///
/// Because the view can be moved from drawer to navigation bar, it must use a
/// global key if it needs to keep its state
typedef DrawerViewBuilder = Widget Function(
  BuildContext context,
  double maxWidth,
  double maxHeight,
  bool show,
  bool Function(DrawerControlSignal) drawerControl,
  Widget Function(BuildContext) pinButtonBuilder,
);

class DrawerEntry {
  final Icon icon;
  final DrawerViewBuilder viewBuilder;

  /// If true, this entry will always be in widget tree (but invisible)
  final bool neverDestroy;

  const DrawerEntry({
    required this.icon,
    required this.viewBuilder,
    this.neverDestroy = false,
  });
}

/// Children of drawer can send signals to control the drawer
enum DrawerControlSignal {
  open,
  close,
  toggle,
  pin,
  unpin,
  togglePin,
  closeIfNotPinned,
}

/// A vertical navigation bar that shows view as drawer
class DrawerView extends StatefulWidget {
  final List<DrawerEntry> drawerEntries;

  final Widget child;

  const DrawerView({
    super.key,
    required this.drawerEntries,
    required this.child,
  });

  @override
  State<StatefulWidget> createState() => DrawerViewState();
}

class DrawerViewState extends State<DrawerView> {
  bool pinned = false;

  /// Index of the opened child, -1 if none
  int activeIndex = -1;

  bool get isOpen => activeIndex != -1;

  /// Width of the opened view
  double openWidth(double maxWidth) => math.min(maxWidth * 0.6, 600);

  /// Width of the navigation bar
  static const double navigationWidth = 50;

  void close() => drawerControlCallback(DrawerControlSignal.close);

  /// Return true if state is changed
  bool drawerControlCallback(DrawerControlSignal signal, [int? index]) {
    int newIndex = activeIndex;
    bool newPinned = pinned;
    switch (signal) {
      case DrawerControlSignal.open:
        newIndex = index!;
        break;
      case DrawerControlSignal.close:
        newIndex = -1;
        break;
      case DrawerControlSignal.toggle:
        newIndex = activeIndex == index! ? -1 : index;
        break;
      case DrawerControlSignal.pin:
        newPinned = true;
        break;
      case DrawerControlSignal.unpin:
        newPinned = false;
        break;
      case DrawerControlSignal.togglePin:
        newPinned = !pinned;
        break;
      case DrawerControlSignal.closeIfNotPinned:
        if (!pinned) {
          newIndex = -1;
        }
        break;
    }
    if (newIndex != activeIndex || newPinned != pinned) {
      setState(() {
        activeIndex = newIndex;
        pinned = newPinned;
      });
      return true;
    }
    return false;
  }

  /// This builder will be passed to the view builder
  Widget pinButtonBuilder(BuildContext context) => IconButton(
        onPressed: () => drawerControlCallback(DrawerControlSignal.togglePin),
        icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
      );

  /// Build the active view
  Widget _buildActive(double maxWidth, double maxHeight) =>
      widget.drawerEntries[activeIndex]
          .viewBuilder(
            context,
            openWidth(maxWidth),
            maxHeight,
            true,
            (signal) => drawerControlCallback(signal, activeIndex),
            pinButtonBuilder,
          )
          .constrained(
            maxWidth: openWidth(maxWidth),
            maxHeight: maxHeight,
          );

  /// Build the navigation bar
  Widget _buildBar(BuildContext context, double maxWidth, double maxHeight) =>
      SizedBox(
        width: navigationWidth,
        height: maxHeight,
        child: Container(
          color: Color.alphaBlend(
            Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
            Theme.of(context).colorScheme.surfaceContainer,
          ),
          child: Column(
            children: [
              Wrap(
                direction: Axis.vertical,
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: widget.drawerEntries
                    .mapIndexed((index, entry) => IconButton(
                          onPressed: () => drawerControlCallback(
                            DrawerControlSignal.toggle,
                            index,
                          ),
                          icon: entry.icon,
                        ))
                    .toList(),
              ).padding(vertical: 8),
            ],
          ),
        ),
      );

  /// [Row] {
  ///   Navigation bar,
  ///   Active view if pinned,
  ///   [Stack] {
  ///     Main view ([DrawerView.child]),
  ///     Unpinned active view with blur background,
  ///     Hidden views,
  ///   }
  /// }
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      final maxHeight = constraints.maxHeight;

      /// Hidden views with [DrawerEntry.neverDestroy] flag
      final hiddenViews = widget.drawerEntries
          .where((entry) => entry.neverDestroy)
          .whereIndexed((index, element) => index != activeIndex)
          .mapIndexed((index, entry) => entry.viewBuilder(
                context,
                0,
                0,
                false,
                (signal) => drawerControlCallback(signal, index),
                pinButtonBuilder,
              ));

      return Row(children: [
        /// Navigation bar
        _buildBar(context, maxWidth, maxHeight),

        /// Active view if pinned
        if (pinned && activeIndex >= 0) _buildActive(maxWidth, maxHeight),
        Stack(
          children: [
            /// Main view
            widget.child,

            /// Unpinned active view with blur background
            if (!pinned && activeIndex >= 0)
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.2),
                  child: const SizedBox.expand(),
                ),
              ),

            if (!pinned && activeIndex >= 0)
              Row(
                children: [
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withOpacity(0.7),
                      child: _buildActive(maxWidth, maxHeight),
                    ),
                  ).clipRect(),
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: close,
                      child: const SizedBox.expand(),
                    ),
                  ).clipRect().expanded(),
                ],
              ),

            /// Hidden views
            ...hiddenViews,
          ],
        ).clipRect().expanded(),
      ]);
    });
  }
}
