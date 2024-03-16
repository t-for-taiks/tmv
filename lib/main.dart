import 'package:flutter/material.dart';
import 'package:tmv/ui/home_page.dart';
import 'package:window_manager/window_manager.dart';

import 'data_io/persistence/persistence.dart';
import 'global/global.dart';

/// Usage: exe <file_or_dir_path>
void main(List<String> arguments) async {
  /// Initialize hive
  await Lifecycle.instance.ensureReady.execute();

  /// Window manipulation on desktop platforms
  if (isDesktop) {
    // resize window
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      // size: Size(1200, 1000),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  runApp(MyApp(arguments: arguments));

  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 1024;
}

class MyApp extends StatelessWidget {
  final List<String> arguments;

  const MyApp({super.key, required this.arguments});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(),
        useMaterial3: true,
        fontFamily: "HarmonyOS_Sans_SC",
      ),
      home: MyHomePage(arguments: arguments),
    );
  }
}
