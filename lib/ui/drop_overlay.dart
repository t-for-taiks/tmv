import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:styled_widget/styled_widget.dart';

import '../data_io/file/file_io.dart';
import '../global/global.dart';

class MessageOverlay extends StatefulWidget {
  MessageOverlay({Key? key})
      : super(key: key ?? GlobalKey<_MessageOverlayState>());

  _MessageOverlayState get _state =>
      (key as GlobalKey<_MessageOverlayState>).currentState!;

  void showMessage(String message) => _state.showMessage(message);

  void hide() => _state.hide();

  @override
  State<StatefulWidget> createState() => _MessageOverlayState();
}

class _MessageOverlayState extends State<MessageOverlay> {
  bool _show = false;

  String _message = "";

  void showMessage(String message) => setState(() {
        _show = true;
        _message = message;
      });

  void hide() => setState(() => _show = false);

  @override
  Widget build(BuildContext context) {
    if (!_show) {
      return Container();
    }
    return Container(
      color: Theme.of(context).colorScheme.inverseSurface.withAlpha(192),
      child: Text(
        _message,
        style: Theme.of(context).textTheme.labelLarge,
      ).textColor(Theme.of(context).colorScheme.onInverseSurface).center(),
    ).constrained(width: double.infinity, height: double.infinity);
  }
}

class DropOverlay extends StatefulWidget {
  final Widget child;

  final Function(List<String>) onFilesDrop;

  final Function(List<Async<WebFile>>) onWebFilesDrop;

  const DropOverlay({
    super.key,
    required this.child,
    required this.onFilesDrop,
    required this.onWebFilesDrop,
  });

  @override
  State<StatefulWidget> createState() => _DropOverlayState();
}

class _DropOverlayState extends State<DropOverlay> {
  final overlay = MessageOverlay();

  void onEnter() => overlay.showMessage("Drag here to open");

  void onExit() => overlay.hide();

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => onEnter(),
      onDragExited: (_) => onExit(),
      onDragDone: (detail) {
        if (kIsWeb) {
          widget.onWebFilesDrop(
            detail.files
                .map((file) => WebFile.buildHandle(
                      nameGetter: () => file.name,
                      dataGetter: file.readAsBytes,
                    ))
                .toList(),
          );
        } else {
          widget.onFilesDrop(
            detail.files.map((file) => file.path).toList(),
          );
        }
      },
      child: Stack(children: [widget.child, overlay]),
    );
  }
}
