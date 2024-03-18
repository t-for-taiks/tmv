import 'dart:io';

import 'package:flutter/services.dart';
import 'package:yaml_writer/yaml_writer.dart';

import '../../global/global.dart';
import 'hive.dart';
export 'hive.dart';

part 'persistence.g.dart';

/// Wraps initialization with a ReadyFlagMixin, to ensure the init is run once
///
/// Call `Lifecycle.instance.ensureReady()`
class Lifecycle with ReadyFlagMixin<Lifecycle> {
  static final Lifecycle instance = Lifecycle();

  @override
  AsyncOut getReady(AsyncSignal signal) => Storage.init.execute(signal);

  Future<Never> shutdown(AsyncSignal signal) async {
    try {
      await Storage.shutdown.execute().timeout(const Duration(seconds: 2));
    } finally {
      SystemNavigator.pop();
      exit(0);
    }
  }
}

@HiveType(typeId: 2)
class AppStorage with BoxStorage<AppStorage> {
  static const _boxPath = "_";

  static const _boxKey = "app_storage";

  @override
  String get boxPath => _boxPath;

  @override
  String get boxKey => _boxKey;

  static AppStorage? _instance;

  static AppStorage get instance => _instance!;

  static AsyncOut<void> init(AsyncSignal signal) async {
    _instance =
        await Storage.tryLoad<AppStorage>.execute(_boxPath, _boxKey, signal)
            .logFail("?")
            .onFail((_, signal) => Ok(AppStorage()))
            .throwErr();
    _instance!.galleryPath = null;
    return ok;
  }

  @HiveField(0)
  var galleryHistory = <String?>[];

  static const _galleryHistoryLimit = 10;

  String? get galleryPath => galleryHistory.firstOrNull;

  set galleryPath(String? value) {
    galleryHistory = [
      value,
      ...galleryHistory.where((e) => e != value).take(_galleryHistoryLimit - 1),
    ];
    markAsDirty();
  }

  Object toJsonObject() => {
        "_": runtimeType.toString(),
        "galleryHistory": galleryHistory,
      };

  @override
  String toString() => YamlWriter().write(toJsonObject());

  AppStorage();
}
