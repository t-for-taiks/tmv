import "dart:io";

import "package:flutter/foundation.dart";
import "package:intl/intl.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:uuid/uuid.dart";

import "async/async.dart";

export "log.dart";

export "async/async.dart";
export "async/ready_flag.dart";

const uuid = Uuid();

final packageInfo = Async<PackageInfo>.value(PackageInfo.fromPlatform());

bool get isDesktop {
  if (kIsWeb) {
    return false;
  }
  return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
}

/// Display number with thousand separators
String num(dynamic number) {
  if (number is int || number is double) {
    return NumberFormat("#,##0.##").format(number);
  }
  throw UnsupportedError("Invalid type ${number.runtimeType}");
}

/// Display size in B, KB, MB, etc.
String kb(dynamic number) {
  const names = ["B", "KB", "MB", "GB"];
  double value = number.toDouble();
  for (final n in names) {
    if (value >= 1024 || value <= -1024) {
      value /= 1024;
    } else {
      return "${num(value)}$n";
    }
  }
  return "${num(value)}TB";
}

extension Kb on int {
  String get toKb => kb(this);
}
