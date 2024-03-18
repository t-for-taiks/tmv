import 'package:flutter/foundation.dart';
import 'package:tmv/data_io/file_cache.dart';

/// Formats for image read
const supportedImageFormats = [".jpg", ".jpeg", ".webp", ".png", ".gif"];

/// Formats for archive read
const supportedArchiveFormats = [".zip", ".cbz"];

/// Default name for app
const defaultTitle = "тaıкs' manga vıewer";

/// Limit of chars to read in an info file
const infoFileReadLimit = 8192;

/// Maximum number of images opened
const fileCountLimit = 1024;

/// Minimum preload previous pages as decoded bitmap
const forcedPreloadRangeLower = 1;

/// Minimum preload future pages as decoded bitmap
const forcedPreloadRangeUpper = 2;

/// Memory preload will only trigger after this delay
const memoryPreloadDelayMs = 500;

/// Default = 1GB
/// The last image added is allowed to surpass this limit
const defaultImageCacheSize = 1024 * 1024 * 1024;

/// Default = 1GB
/// The last image added is allowed to surpass this limit
const defaultMemoryCacheSize = 256 * 1024 * 1024;

/// Minimum number of entries in [FileCache]
const minimumMemoryCacheCount = 10;

/// File exceeding this limit will not be read
const fileReadLimit = 100 * 1024 * 1024;

/// Max size when calculating bitmap size
///
/// For some reason, when a large image is decoded,
/// the memory usage is way less than its bitmap size
// const maxImageSize = 3840 * 2160 * 4 * 1024;

/**
 * Behaviors
 */

/// Default behavior for archive source: decompress all
const archiveSourceDecompressAll = false;

/// Preload previous pages into memory (encoded)
const memoryPreloadRangeLower = 32;

/// Preload previous pages into memory (encoded)
const memoryPreloadRangeUpper = 128;

/// Enable viewing entire directory
const allowOpenDirectory = !kIsWeb;
