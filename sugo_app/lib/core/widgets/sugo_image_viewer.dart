import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';

/// Opens photos full-screen, zoomable, one after another.
///
/// Used for job photos on a booking and for photos sent in chat. The brief's
/// requirements, and how each is met:
///
/// * **Zoom** - pinch or double-tap, up to 4x, via `InteractiveViewer`.
/// * **Close** - a close button top-left, the system back gesture, or a
///   downward swipe when not zoomed.
/// * **View clearly** - a black ground, so neither the page tint nor the
///   status bar competes with the photo.
/// * **Aspect ratio** - `BoxFit.contain`, never `cover`: a photo of a broken
///   screen that is cropped to fit may crop out the crack.
Future<void> openSugoImageViewer(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
  String? heroTag,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (BuildContext _, Animation<double> __, Animation<double> ___) =>
          SugoImageViewer(
            urls: urls,
            initialIndex: initialIndex,
            heroTag: heroTag,
          ),
      transitionsBuilder:
          (
            BuildContext _,
            Animation<double> animation,
            Animation<double> __,
            Widget child,
          ) => FadeTransition(opacity: animation, child: child),
    ),
  );
}

class SugoImageViewer extends StatefulWidget {
  const SugoImageViewer({
    super.key,
    required this.urls,
    this.initialIndex = 0,
    this.heroTag,
  });

  final List<String> urls;
  final int initialIndex;

  /// Shared with the thumbnail that opened this, so the photo grows out of it.
  /// Only applied to the initial page.
  final String? heroTag;

  @override
  State<SugoImageViewer> createState() => _SugoImageViewerState();
}

class _SugoImageViewerState extends State<SugoImageViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  /// True while any page is zoomed in: paging and swipe-to-close are both
  /// suspended then, so panning a zoomed photo does not flip or dismiss it.
  bool _zoomed = false;

  double _drag = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double fade = (1 - (_drag.abs() / 400)).clamp(0.4, 1.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: fade),
        body: Stack(
          children: <Widget>[
            GestureDetector(
              onVerticalDragUpdate: _zoomed
                  ? null
                  : (DragUpdateDetails d) =>
                        setState(() => _drag += d.delta.dy),
              onVerticalDragEnd: _zoomed
                  ? null
                  : (DragEndDetails d) {
                      if (_drag.abs() > 120 ||
                          (d.primaryVelocity ?? 0).abs() > 900) {
                        Navigator.of(context).maybePop();
                      } else {
                        setState(() => _drag = 0);
                      }
                    },
              child: Transform.translate(
                offset: Offset(0, _drag),
                child: PageView.builder(
                  controller: _pages,
                  physics: _zoomed
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  itemCount: widget.urls.length,
                  onPageChanged: (int i) => setState(() => _index = i),
                  itemBuilder: (BuildContext context, int i) {
                    final Widget image = _ZoomablePhoto(
                      url: widget.urls[i],
                      onZoomChanged: (bool zoomed) {
                        if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                      },
                    );
                    if (i == widget.initialIndex && widget.heroTag != null) {
                      return Hero(tag: widget.heroTag!, child: image);
                    }
                    return image;
                  },
                ),
              ),
            ),

            // Controls. Over a gradient so white icons stay legible on a
            // white photo.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0x99000000), Color(0x00000000)],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.sm,
                      vertical: AppSizes.xs,
                    ),
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const Spacer(),
                        if (widget.urls.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSizes.md,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(
                                AppSizes.pillRadius,
                              ),
                            ),
                            child: Text(
                              '${_index + 1} of ${widget.urls.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const SizedBox(width: AppSizes.md),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.url, required this.onZoomChanged});

  final String url;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  late final AnimationController _animation;
  Animation<Matrix4>? _tween;
  TapDownDetails? _doubleTapAt;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final Animation<Matrix4>? tween = _tween;
        if (tween != null) _transform.value = tween.value;
      });
    _transform.addListener(_reportZoom);
  }

  void _reportZoom() {
    widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01);
  }

  @override
  void dispose() {
    _transform.removeListener(_reportZoom);
    _transform.dispose();
    _animation.dispose();
    super.dispose();
  }

  /// Double-tap toggles between fit and 2.5x centred on the tap.
  void _toggleZoom() {
    final Matrix4 from = _transform.value;
    final Matrix4 to;
    if (from.getMaxScaleOnAxis() > 1.01) {
      to = Matrix4.identity();
    } else {
      final Offset at = _doubleTapAt?.localPosition ?? Offset.zero;
      const double scale = 2.5;
      to = Matrix4.identity()
        ..translateByDouble(-at.dx * (scale - 1), -at.dy * (scale - 1), 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    }
    _tween = Matrix4Tween(begin: from, end: to).animate(
      CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic),
    );
    _animation.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (TapDownDetails d) => _doubleTapAt = d,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 4,
        child: SizedBox.expand(
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            loadingBuilder:
                (BuildContext context, Widget child, ImageChunkEvent? progress) {
                  if (progress == null) return child;
                  final int? total = progress.expectedTotalBytes;
                  return Center(
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Colors.white,
                        value: total == null
                            ? null
                            : progress.cumulativeBytesLoaded / total,
                      ),
                    ),
                  );
                },
            errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.hint,
                        size: 40,
                      ),
                      SizedBox(height: AppSizes.sm),
                      Text(
                        'This photo could not be loaded.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
