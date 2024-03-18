import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../global/config.dart';
import '../../global/global.dart';
import '../../ui/manga/manga_view.dart';
import '../manga_loader.dart';
import 'file_filter.dart';
import 'file_io.dart';

/// Tries to load specified files as current manga
///
/// Returns true if a new one is opened
AsyncOut<MangaViewData> tryOpen(List<String> paths, AsyncSignal signal) async {
  log.d(paths);
  if (paths.isEmpty) {
    throw Exception("No file to open");
  }
  if (paths.length > 1) {
    throw UnimplementedError();
  }
  final path = paths[0];
  return await MangaSource.fromPath(path, signal)
      .map((source) => MangaViewData(source, openedFile: path));
}

AsyncOut<MangaViewData> tryOpenWeb(
    List<Async<WebFile>> files, AsyncSignal signal) async {
  if (files.length > 1) {
    throw UnimplementedError();
  }
  try {
    final file = (await files[0]).value;
    if (ExtensionFilter.archive.test(file.name)) {
      return Ok(
        MangaViewData(WebArchiveMangaSource(file)),
      );
    }
  } catch (e) {
    log.w("unable to open", error: e);
    return Err(e);
  }
  return Err();
}

/// Prompt the user to pick file to open
AsyncOut<MangaViewData> pickAndOpenFile(AsyncSignal signal) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ExtensionFilter.media.allowedExtensions
        .followedBy(ExtensionFilter.archive.allowedExtensions)
        .map((s) => s.substring(1))
        .toList(),
    allowMultiple: true,
    lockParentWindow: true,
  );
  // user cancel
  if (result == null || signal.isTriggered) {
    return Err("cancelled");
  }
  if (kIsWeb) {
    return tryOpenWeb(
      result.files
          .map((file) => WebFile.buildHandle(
                nameGetter: () => file.name,
                dataGetter: () => file.bytes!,
              ))
          .toList(),
      signal,
    );
  } else {
    return tryOpen(
      result.files.map((file) => file.path!).toList(),
      signal,
    );
  }
}

AsyncOut<MangaViewData> pickAndOpenDirectory(AsyncSignal signal) async {
  if (!allowOpenDirectory) {
    return Err();
  }
  final result = await FilePicker.platform.getDirectoryPath(
    lockParentWindow: true,
  );
  // user cancel
  if (result == null) {
    return Err("cancelled");
  }
  return tryOpen([result], signal);
}
