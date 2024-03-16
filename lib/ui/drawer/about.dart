import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:styled_widget/styled_widget.dart';
import 'package:tmv/global/config.dart';
import 'package:tmv/global/global.dart';
import 'package:url_launcher/url_launcher.dart';

import 'drawer.dart';

/// About drawer
Widget buildAbout(
  BuildContext context,
  double maxWidth,
  double maxHeight,
  bool show,
  bool Function(DrawerControlSignal) drawerControl,
  Widget Function(BuildContext) pinButtonBuilder,
) {
  return SizedBox(
    width: maxWidth,
    height: maxHeight,
    child: Column(
      children: [
        const SizedBox(height: 16),
        Text(
          defaultTitle,
          style: Theme.of(context).textTheme.displaySmall,
        ).fontWeight(FontWeight.w900),
        const SizedBox(height: 16),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: "Version: ${packageInfo.unwrap.version}   ",
                style: Theme.of(context).textTheme.labelMedium,
              ),
              TextSpan(
                text: "GitHub ",
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    launchUrl(Uri.parse("https://github.com/t-for-taiks/tmv"));
                  },
              ),
              WidgetSpan(
                child: Icon(
                  Icons.open_in_new_rounded,
                  size: Theme.of(context).textTheme.labelMedium?.fontSize,
                  color: Theme.of(context).colorScheme.primary,
                ),
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.ideographic,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ListTile(
          title: const Text("View dependency licenses"),
          onTap: () {
            showLicensePage(
              context: context,
              applicationName: defaultTitle,
              applicationVersion: packageInfo.unwrap.version,
              applicationLegalese: "https://github.com/t-for-taiks/tmv",
            );
          },
        ),
        ListTile(
          title: const Text("View font licenses"),
          onTap: () async {
            final license =
                await rootBundle.loadString("assets/fonts/LICENSE.txt");
            if (context.mounted) {
              showDialog(
                context: context,
                builder: (context) => Text(
                  license
                      .replaceAll(RegExp(r"[\x00-\x08\x0E-\x1F]"), "")
                      .trim(),
                  style: Theme.of(context).textTheme.bodySmall,
                )
                    .scrollable()
                    .padding(all: 16)
                    .backgroundBlur(12)
                    .backgroundColor(
                        Theme.of(context).colorScheme.surface.withOpacity(0.8))
                    .clipRRect(all: 8)
                    .constrained(maxWidth: 600)
                    .padding(vertical: 80)
                    .center(),
              );
            }
          },
        ),
      ],
    ),
  );
}
