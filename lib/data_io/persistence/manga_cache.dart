import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:tmv/data_io/persistence/thumbnail.dart';
import 'package:yaml_writer/yaml_writer.dart';

import '../../global/global.dart';
import '../../global/helper.dart';
import '../../global/search.dart';
import '../../ui/manga/manga_view.dart';
import '../file/file_io.dart';
import '../manga_loader.dart';
import 'hive.dart';

part 'manga_cache.g.dart';

/// Info about a manga
///
/// Although it contains [MangaSource], there's no correlation between the ready
/// state of the two.
@HiveType(typeId: 6)
class MangaCache with BoxStorage<MangaCache>, ReadyFlagMixin<MangaCache> {
  /// File name to look for in the source
  static const metaInfoFiles = ["meta.txt", "info.txt"];

  /// At most 8 files will be searched for meta info
  static const metaInfoQueryLimit = 8;

  static const _boxPath = "manga_cache";

  @override
  String get boxPath => _boxPath;

  static AsyncOut<MangaCache> tryLoad(String identifier, AsyncSignal signal) async {
    // final stopwatch = Stopwatch()..start();
    final result = await Storage.tryLoad<MangaCache>(_boxPath, identifier, signal);
    // log.d("MangaCache.tryLoad $boxKey in ${stopwatch.elapsedMilliseconds}ms");
    return result;
  }

  /// Try to load MangaCache from storage, otherwise create a new one
  static AsyncOut<MangaCache> createFromIdentifier(
    String identifier,
    AsyncSignal signal,
  ) =>
      tryLoad
          .execute(identifier, signal)
          .whenComplete(() => log.t(("MangaCache", "loaded $identifier")))
          .onFail(
            (_, signal) => Ok(MangaCache.fromSource(
              MangaSource.fromIdentifier(identifier),
            )),
          )
          .catchError((error, stack) => Err(error, stack));

  /// Thumbnail of the manga cover
  @HiveField(0)
  ThumbnailInfo? thumbnail;

  ImageProvider get thumbnailImage {
    if (thumbnail == null) {
      return const AssetImage("assets/images/image_placeholder_loading.webp");
    }
    if (thumbnail!.isEmpty) {
      return const AssetImage(
          "assets/images/image_placeholder_no_preview.webp");
    }
    return MemoryImage(thumbnail!.data);
  }

  @HiveField(1)
  final MangaSource source;

  @HiveField(2)
  MangaViewData? viewData;

  @HiveField(3)
  int length = 0;

  @HiveField(4)
  Map<String, dynamic>? info;

  /// Whether the source contains sub folders or archives
  @HiveField(5)
  late final bool containsSub;

  Searchable? searchableText;

  bool loadedFromStorage;

  String get title => <String?>[
        info?["title"],
        info?["title_japanese"],
        source.userShortName
      ].firstWhere((e) => e?.isNotEmpty == true)!;

  MangaCache({
    required this.source,
    required this.thumbnail,
    required this.viewData,
    required this.length,
    required this.info,
    required this.containsSub,
  }) : loadedFromStorage = true {
    boxKey = source.identifier;
  }

  MangaCache.fromSource(this.source, [this.viewData])
      : loadedFromStorage = false {
    boxKey = source.identifier;
  }

  AsyncOut<Map<String, dynamic>> _loadInfo(AsyncSignal signal) => metaInfoFiles
      .followedBy(
        source.files.where(
          (path) => [".txt", ".yaml", ".json"].contains(extension(path)),
        ),
      )
      .take(metaInfoQueryLimit)
      .map((path) => source.getData.bind(path, null))
      .executeOrdered(signal)
      .map((result) {
        if (result is Ok) {
          log.t(("MangaCache", "read text ${result.value.length.toKb}"));
        }
        return result;
      })
      .where(Result.isOk)
      .asyncMap((result) => parseYaml<String, dynamic>(result.value, signal))
      .handleError((error) => Err(error))
      .firstWhere((result) => result is Ok, orElse: () => const Ok({}));

  AsyncOut<ThumbnailInfo> _loadThumbnail(
    MangaViewData viewData,
    AsyncSignal signal,
  ) =>
      List.generate(
        4,
        (index) => viewData.getFileData
            .bind(index, Priority.high)
            .chain(ThumbnailProcessor.process),
      )
          .executeOrdered(signal)
          .firstWhere(Result.isOk, orElse: () => Err("Can't create thumbnail"));

  @override
  AsyncOut<void> getReady(AsyncSignal signal) async {
    final stopwatch = Stopwatch()..start();
    if (!loadedFromStorage) {
      // build a temp source with recursion off
      final source = MangaSource.fromIdentifier(this.source.identifier);
      source.recursive = false;

      await source.ensureReady.execute(signal);
      length = source.length;
      log.t((
        "MangaCache",
        "MangaSource.getReady ${source.identifier} in ${stopwatch.elapsed}",
      ));
      stopwatch.reset();

      // Currently, only sub-dirs from directory sources are supported
      containsSub = source.containsSub;

      info = await _loadInfo.execute(signal).throwErr();
      log.t((
        "MangaCache",
        "MangaCache._loadInfo ${source.identifier} in ${stopwatch.elapsed}",
      ));
      stopwatch.reset();
      if (thumbnail == null) {
        final viewData = MangaViewData(source);
        await viewData.ensureReady.execute(signal);
        thumbnail = await _loadThumbnail
            .execute(viewData, signal)
            // in case there's no thumbnail generated
            // if there's a sub-dir, use an empty thumbnail
            .onFail((value, signal) =>
                containsSub ? Ok(ThumbnailInfo.empty()) : value)
            // otherwise, throw error
            .throwErr();
        await thumbnail!.readDimensions().throwErr();
        log.t((
          "MangaCache",
          "Thumbnail created ${source.identifier} in ${stopwatch.elapsed}",
        ));
        markAsDirty();
        viewData.dispose();
      }
      stopwatch.reset();
      source.dispose();
    }
    searchableText = Searchable(title + info.toString());
    viewData ??= MangaViewData(source);
    viewData!.cache = this;
    log.t((
      "MangaCache",
      "Searchable done ${source.identifier} in ${stopwatch.elapsed}",
    ));
    stopwatch.reset();
    return ok;
  }

  @override
  void release() {
    super.release();
    source.release();
    loadedFromStorage = true;
  }

  @override
  void dispose() {
    super.dispose();
    release();
    viewData?.dispose();
    viewData?.cache = null;
  }

  Object toJsonObject() => {
        "_": runtimeType.toString(),
        "source": source.toString(),
        "info": info,
        "thumbnail": thumbnail?.data.lengthInBytes.toKb,
        "viewData": viewData?.toJsonObject(),
        "loadedFromStorage": loadedFromStorage,
      };

  @override
  String toString() => YamlWriter().convert(toJsonObject());
}
