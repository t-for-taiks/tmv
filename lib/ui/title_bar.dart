import 'dart:io';

import 'package:flutter/material.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:tmv/global/config.dart';
import 'package:tmv/global/helper.dart';
import 'package:window_manager/window_manager.dart';

import '../data_io/persistence/persistence.dart';
import '../global/global.dart';
import 'manga/manga_view.dart';

const double titleBarHeight = 24;

const double titleBarButtonWidth = 36;

void toggleMaximize() async {
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  } else {
    await windowManager.maximize();
  }
}

/// Title bar will listen to signal from [MangaViewState] and update the title
class TitleBar extends StatefulWidget implements PreferredSizeWidget {
  final SignalEmitter<MangaViewData?>? signalEmitter;

  const TitleBar({super.key, required this.signalEmitter});

  @override
  State<TitleBar> createState() => _TitleBarState();

  @override
  Size get preferredSize => const Size.fromHeight(titleBarHeight);
}

class _TitleBarState extends State<TitleBar> {
  SignalEmitter<MangaViewData?>? latestSignalEmitter;

  String title = defaultTitle;

  void listenToSignal() {
    if (widget.signalEmitter == latestSignalEmitter) return;
    latestSignalEmitter = widget.signalEmitter;
    widget.signalEmitter?.addListener((data, emitter) {
      if (emitter != latestSignalEmitter) return false;
      setState(() {
        title = data?.title ?? defaultTitle;
      });
      return true;
    });
  }

  @override
  void initState() {
    super.initState();
    listenToSignal();
  }

  @override
  void didUpdateWidget(covariant TitleBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    listenToSignal();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          textAlign: Platform.isMacOS ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: Theme.of(context).colorScheme.inverseSurface,
            fontSize: titleBarHeight * 0.5,
            height: 0.75,
            overflow: TextOverflow.ellipsis,
          ),
        )
            .gestures(
              // draggable window
              onTapDown: (_) {
                windowManager.startDragging();
              },
              // double-tap to maximize
              onDoubleTap: toggleMaximize,
            )
            .padding(horizontal: 8)
            .expanded(),

        /// Only build title bar buttons on Windows
        if (Platform.isWindows) ...[
          // minimize button
          RawMaterialButton(
            onPressed: windowManager.minimize,
            child: const Icon(Icons.horizontal_rule_rounded, size: 12),
          ).constrained(width: titleBarButtonWidth),
          // maximize button
          const RawMaterialButton(
            onPressed: toggleMaximize,
            child: Icon(Icons.crop_square_rounded, size: 12),
          ).constrained(width: titleBarButtonWidth),
          // close button
          RawMaterialButton(
            onPressed: Lifecycle.instance.shutdown.execute,
            child: const Icon(Icons.close_rounded, size: 14),
          ).constrained(width: titleBarButtonWidth),
        ],
      ],
    ).height(24).backgroundColor(Theme.of(context).colorScheme.inversePrimary);
  }
}
