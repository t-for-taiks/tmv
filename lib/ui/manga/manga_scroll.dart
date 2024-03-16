import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:styled_widget/styled_widget.dart';

class VerticalMangaScroll extends StatelessWidget {
  /// Current page starting from 0
  final int index;

  /// Title of the manga
  final String title;

  /// Total number of pages
  final int total;

  /// Traceable key to access widget after render
  final GlobalKey globalKey = GlobalKey();

  /// Parent callback to switch page
  final void Function(int) switchPageCallback;

  static const double scrollBlockHeight = 32;

  static const double scrollTickHeight = 4;

  final tooltipController = JustTheController();

  VerticalMangaScroll({
    super.key,
    required this.index,
    required this.title,
    required this.total,
    required this.switchPageCallback,
  });

  TextStyle buildTextStyle(BuildContext context) => TextStyle(
        fontSize: 10,
        color: Theme.of(context).colorScheme.onInverseSurface,
      );

  Widget buildScrollBlock(BuildContext context) => SizedBox(
        width: scrollBlockHeight,
        height: scrollBlockHeight,
        child: JustTheTooltip(
          backgroundColor: Theme.of(context).colorScheme.inverseSurface,
          preferredDirection: AxisDirection.left,
          // controller: tooltipController,
          // triggerMode: TooltipTriggerMode.manual,
          offset: 8,
          fadeInDuration: const Duration(),
          fadeOutDuration: const Duration(),
          content: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
          ).padding(horizontal: 6, top: 2, bottom: 4),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
              color: Theme.of(context).colorScheme.inverseSurface,
            ),
            child: Column(
              children: [
                Text(
                  "${index + 1}",
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onInverseSurface,
                    fontWeight: FontWeight.bold,
                  ),
                )
                    .padding(left: 3, right: 2)
                    .center()
                    .fittedBox()
                    .constrained(height: 15.5),
                Divider(
                    height: 1,
                    thickness: 1,
                    color: Theme.of(context).colorScheme.onInverseSurface),
                Text(
                  "$total",
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onInverseSurface,
                  ),
                )
                    .padding(left: 3, right: 2)
                    .center()
                    .fittedBox()
                    .constrained(height: 15.5),
              ],
            ),
          ),
        ),
      );

  /// Distance between two ticks
  double tickDistance(double totalHeight) {
    return (totalHeight - scrollBlockHeight) / (total - 1);
  }

  Widget buildScrollTicks(BuildContext context, double height) {
    // If there are too many pages, instead just render a block
    if (total >= 100) {
      return Container(
        height: height - scrollBlockHeight,
        width: scrollTickHeight,
        decoration: BoxDecoration(
          borderRadius:
              const BorderRadius.all(Radius.circular(scrollTickHeight)),
          color: Colors.grey.withAlpha(64),
        ),
      ).center();
    }
    return Stack(
      children: List.generate(
        total,
        (index) => Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: scrollTickHeight,
              width: scrollTickHeight,
              margin: EdgeInsets.only(
                top: index * tickDistance(height) +
                    (scrollBlockHeight - scrollTickHeight) / 2,
              ),
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.all(Radius.circular(scrollTickHeight)),
                color: Colors.grey.withAlpha(64),
              ),
            )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // do not show when there's only one item
    if (total == 1) {
      return const SizedBox.shrink();
    }
    return Container(
      width: scrollBlockHeight,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Listener(
        onPointerDown: pointerCallback,
        onPointerMove: pointerCallback,
        // onPointerUp: (_) => tooltipController.hideTooltip(),
        // onPointerCancel: (_) => tooltipController.hideTooltip(),
        behavior: HitTestBehavior.opaque,
        child: LayoutBuilder(
            key: globalKey,
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              return Stack(
                children: [
                  // Left padding to visually compensate for round corner
                  buildScrollTicks(context, height).padding(left: 1),
                  buildScrollBlock(context)
                      .padding(top: index * tickDistance(height)),
                ],
              );
            }),
      ),
    );
  }

  void pointerCallback(PointerEvent event) {
    // Primary down or drag
    // Note that in a drag, pointer may get outside of widget
    if (event.down && event.buttons & kPrimaryButton != 0) {
      // tooltipController.showTooltip();
      final height = globalKey.currentContext!.size!.height;
      const yMin = scrollBlockHeight / 2;
      final delta = tickDistance(height);
      final targetIndex = ((event.localPosition.dy - yMin) / delta).round();
      switchPageCallback(targetIndex);
    }
  }
}
