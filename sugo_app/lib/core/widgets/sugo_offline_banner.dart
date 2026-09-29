import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../services/connectivity_monitor.dart';
import '../theme/app_motion.dart';

/// Wraps the whole app and slides a slim "You're offline" strip down from the
/// top when the server cannot be reached.
///
/// Installed once, in `MaterialApp.builder`, so every screen gets it without
/// knowing it exists. It is deliberately subtle - a thin strip, not a dialog:
/// the screen underneath still shows the last data it loaded, and blocking it
/// with a modal would take that away for no benefit.
///
/// The strip sits *above* the page's own content and pushes it down rather
/// than overlapping, so it never hides a screen's title or back button.
class SugoOfflineBanner extends StatelessWidget {
  const SugoOfflineBanner({super.key, required this.child, this.monitor});

  final Widget child;

  /// Tests only; the app uses the shared instance.
  final ConnectivityMonitor? monitor;

  @override
  Widget build(BuildContext context) {
    final ConnectivityMonitor source = monitor ?? ConnectivityMonitor.instance;

    return ListenableBuilder(
      listenable: source,
      builder: (BuildContext context, Widget? page) {
        final bool offline = !source.isOnline;
        final EdgeInsets padding = MediaQuery.paddingOf(context);

        return Column(
          children: <Widget>[
            AnimatedSize(
              duration: AppMotion.base,
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: offline
                  ? _Strip(topInset: padding.top)
                  : const SizedBox(width: double.infinity),
            ),
            Expanded(
              // Once the strip has consumed the status-bar inset, the page
              // below must not add it again.
              child: offline
                  ? MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: page!,
                    )
                  : page!,
            ),
          ],
        );
      },
      child: child,
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.topInset});

  final double topInset;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: "You're offline. Showing the last information we loaded.",
      excludeSemantics: true,
      child: Material(
        color: AppColors.navy,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSizes.lg,
            topInset + 6,
            AppSizes.lg,
            8,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.wifi_off_rounded, size: 15, color: Colors.white),
              SizedBox(width: AppSizes.sm),
              Flexible(
                child: Text(
                  "You're offline — showing what we last loaded",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
