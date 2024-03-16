import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'async.dart';

/// A ready flag to tell accessors whether methods are ready
///
/// The class must call [ready.complete] to signal it's ready
mixin ReadyFlagMixin<T extends ReadyFlagMixin<T>> {
  /// Resolves when ready
  Async<T>? ready;

  /// Whether data is ready
  bool get isReady => ready != null && ready!.isSuccessful;

  bool get isGettingReady => ready != null && !ready!.isCompleted;

  /// To be overridden. Will be called by [ensureReady]
  ///
  /// Never call this. Call [ensureReady] instead
  ///
  /// May through [Err] if failed
  @protected
  AsyncOut getReady(AsyncSignal signal);

  /// Make sure [getReady] is called at least once
  /// Resolves when ready
  ///
  /// Call this in constructor to prepare as soon as possible
  /// Otherwise, call this at use to lazy evaluate
  AsyncOut<T> ensureReady([AsyncSignal? signal]) {
    if (isReady) {
      return Ok(this as T);
    }
    return ready ??= getReady
        .execute(signal)
        .catchError((err) => err as Err)
        .map((_) => this as T);
  }

  /// Do something after [ensureReady]
  Async<void> whenReady(void Function() action) =>
      ensureReady.execute().whenComplete(action);

  static AsyncOut<T> makeReady<T extends ReadyFlagMixin<T>>(
          ReadyFlagMixin<T> object, AsyncSignal signal) =>
      object.ensureReady(signal);

  /// Release resources when object is no longer used, but the object can
  /// still call [ensureReady] to reinitialize
  void release() {
    ready?.cancel();
    ready = null;
  }

  /// Build a widget that shows differently based on [isReady]
  @nonVirtual
  Widget createWidget() => _ReadyFlagWidget(
        object: this,
        readyBuilder: this.buildReady,
        placeholderBuilder: this.buildPlaceholder,
      );

  /// Build the widget when ready
  Widget buildReady(BuildContext context) => const SizedBox.shrink();

  /// Build the widget when not ready
  Widget buildPlaceholder(BuildContext context) => const SizedBox.shrink();
}

typedef WidgetBuilder = Widget Function(BuildContext context);

/// A widget that builds differently based on [ReadyFlagMixin.isReady]
class _ReadyFlagWidget extends StatefulWidget {
  /// The object to check for ready
  final ReadyFlagMixin object;

  /// The builder to call when ready
  final WidgetBuilder readyBuilder;

  /// The builder to call when not ready
  final WidgetBuilder placeholderBuilder;

  _ReadyFlagWidget({
    required this.object,
    required this.readyBuilder,
    required this.placeholderBuilder,
  }) : super(key: ObjectKey(object));

  @override
  State<_ReadyFlagWidget> createState() => _ReadyFlagWidgetState();
}

class _ReadyFlagWidgetState extends State<_ReadyFlagWidget> {
  @override
  Widget build(BuildContext context) {
    if (widget.object.isReady) {
      return widget.readyBuilder(context);
    } else {
      widget.object.whenReady(() => setState(() {}));
      return widget.placeholderBuilder(context);
    }
  }
}
