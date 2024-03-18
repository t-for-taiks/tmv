import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tmv/data_io/file/file_pick.dart';
import 'package:tmv/ui/drawer/about.dart';
import 'package:tmv/ui/drawer/drawer.dart';
import 'package:tmv/ui/title_bar.dart';

import '../global/global.dart';
import 'drawer/select_view.dart';
import 'drop_overlay.dart';
import 'manga/manga_view.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.arguments});

  /// Startup arguments
  final List<String> arguments;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final GlobalKey<MangaViewState> mangaViewKey =
      GlobalKey(debugLabel: "mangaView");

  final GlobalKey drawerKey = GlobalKey(debugLabel: "drawer");

  MangaViewData? get mangaViewData => mangaViewKey.currentState?.data;

  DrawerViewState? get drawer => drawerKey.currentState as DrawerViewState?;

  AsyncOut<void> _applyData(MangaViewData? data, [AsyncSignal? signal]) async =>
      await mangaViewKey.currentState?.setData.execute(data, signal) ??
      ok;

  @override
  void initState() {
    super.initState();
    if (widget.arguments.isNotEmpty) {
      tryOpen.execute(widget.arguments).map(_applyData);
    } else {
      // don't restore session for now
      // MangaViewData.tryLoad.execute().map(_applyData);
    }
  }

  /// Build center view
  Widget buildView(BuildContext context) => DrawerView(
        key: drawerKey,
        drawerEntries: [
          DrawerEntry(
            icon: const Icon(Icons.photo_library_outlined),
            viewBuilder:
                (context, width, height, show, drawerControl, pinBuilder) =>
                    SelectView(
              key: GlobalObjectKey(this),
              maxWidth: width,
              maxHeight: height,
              openMangaCallback: (cache) {
                drawerControl(DrawerControlSignal.closeIfNotPinned);
                _applyData(cache.viewData);
              },
              pinButtonBuilder: pinBuilder,
              hidden: !show,
            ),
            neverDestroy: true,
          ),
          const DrawerEntry(
            icon: Icon(Icons.info_outline_rounded),
            viewBuilder: buildAbout,
          ),
        ],
        child: MangaView(key: mangaViewKey),
      );

  @override
  Widget build(BuildContext context) {
    if (mangaViewKey.currentState == null) {
      // make sure the manga view is built and passed to title bar
      // because TitleBar needs update signal from MangaView
      Future(() => setState(() {}));
    }
    return Scaffold(
      appBar:
          isDesktop ? TitleBar(signalEmitter: mangaViewKey.currentState) : null,
      body: Shortcuts(
        shortcuts: {
          // ctrl O: open file
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyO):
              const OpenFileIntent(),
          // ctrl shift O: open file
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift,
              LogicalKeyboardKey.keyO): const OpenDirectoryIntent(),
          // ctrl W: close file
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyW):
              const CloseMangaIntent(),
          // escape: close file
          LogicalKeySet(LogicalKeyboardKey.escape): const CloseMangaIntent(),
        },
        child: Actions(
          dispatcher: const ActionDispatcher(),
          actions: {
            OpenFileIntent:
                CallbackAction(onInvoke: (_) => pickAndOpenFile.execute()),
            OpenDirectoryIntent:
                CallbackAction(onInvoke: (_) => pickAndOpenDirectory.execute()),
            CloseMangaIntent: CallbackAction(
              onInvoke: (_) {
                if (drawer?.isOpen == true) {
                  drawer?.close();
                } else {
                  _applyData(null);
                }
                return null;
              },
            )
          },
          child: DropOverlay(
            child: SafeArea(child: buildView(context)),
            onFilesDrop: (files) => tryOpen.execute(files).map(_applyData),
            onWebFilesDrop: (files) =>
                tryOpenWeb.execute(files).map(_applyData),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    // Storage.shutdown.execute();
  }
}

class OpenFileIntent extends Intent {
  const OpenFileIntent();
}

class OpenDirectoryIntent extends Intent {
  const OpenDirectoryIntent();
}

class CloseMangaIntent extends Intent {
  const CloseMangaIntent();
}
