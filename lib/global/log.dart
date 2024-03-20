import "package:collection/collection.dart";
import "package:logger/logger.dart";

Logger get log => Log.instance;

class MyLogFilter extends DevelopmentFilter {
  @override
  bool shouldLog(LogEvent event) {
    final String category;
    try {
      if (event.level.index >= Level.warning.index) return true;
      if (event.message is List) {
        category = (event.message[0] as String).toLowerCase();
      } else if (event.message is Record) {
        category = (event.message.$1 as String).toLowerCase();
      } else {
        return true;
      }
    } catch (e) {
      return true;
    }
    return <String>[
      "persistence",
      "isolate",
      "schedule",
      "FileCache",
      "MangaSource",
      "MangaView",
      // "MangaCache",
      "Thumbnail",
      "album",
    ].none((s) => category.startsWith(s.toLowerCase()));
  }
}

class Log extends Logger {
  Log._()
      : super(
          // printer: PrettyPrinter(printTime: true),
          printer: PrettyPrinter(methodCount: 1, noBoxingByDefault: false),
          filter: MyLogFilter(),
          level: Level.trace,
        );
  static final instance = Log._();
}
