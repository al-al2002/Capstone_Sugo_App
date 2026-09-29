import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_motion.dart';
import 'sugo_card.dart';

/// A shimmering placeholder in the shape of the content that is loading.
///
/// ## Why not a spinner
///
/// A centred `CircularProgressIndicator` - which is what most of these screens
/// used before - has two problems. It says nothing about what is arriving, and
/// it occupies a different amount of space than the content does, so the
/// layout jumps when the data lands. On a list of job cards that jump is the
/// whole screen.
///
/// A skeleton fixes both: it reserves the real footprint, so nothing moves on
/// arrival, and its shape previews the content, so the wait is spent reading
/// the layout rather than watching a circle. The perceived wait is shorter for
/// it even when the actual wait is identical.
///
/// ## The shimmer
///
/// A highlight sweeps left to right on a 1.4s loop. Slow on purpose: a fast
/// shimmer reads as urgency, and urgency is the opposite of what a loading
/// state should convey. The sweep is a gradient over the existing divider and
/// surface tokens, so it introduces no colour of its own.
class SugoSkeleton extends StatefulWidget {
  const SugoSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
    this.shape = BoxShape.rectangle,
  });

  /// A circular placeholder, for an avatar.
  const SugoSkeleton.circle({super.key, required double size})
    : width = size,
      height = size,
      radius = 0,
      shape = BoxShape.circle;

  final double? width;
  final double height;
  final double radius;
  final BoxShape shape;

  @override
  State<SugoSkeleton> createState() => _SugoSkeletonState();
}

class _SugoSkeletonState extends State<SugoSkeleton>
    with SingleTickerProviderStateMixin {
  /// Created in [initState] rather than lazily.
  ///
  /// This one is reached on every path through [build], so the lazy form was
  /// not actually broken - but it was one early return away from the unmount
  /// crash documented on `_GlyphState` in `sugo_empty_state.dart`, and a
  /// shimmer is exactly the sort of widget that later grows a "skip the
  /// animation" branch.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The sweep is decoration. Under "remove animations" the placeholder holds
    // still - it still reserves the footprint, which is its real job.
    if (AppMotion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          shape: widget.shape,
          color: AppColors.divider,
          borderRadius: widget.shape == BoxShape.circle
              ? null
              : BorderRadius.circular(widget.radius),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) {
        // Travels from fully off the left to fully off the right, so the
        // highlight never parks at an edge between loops.
        final double t = _controller.value * 2 - 1;

        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            shape: widget.shape,
            borderRadius: widget.shape == BoxShape.circle
                ? null
                : BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, 0),
              end: Alignment(t + 1, 0),
              colors: const <Color>[
                AppColors.divider,
                AppColors.primarySofter,
                AppColors.divider,
              ],
              stops: const <double>[0.1, 0.5, 0.9],
            ),
          ),
        );
      },
    );
  }
}

/// A placeholder shaped like a list row: avatar, title, subtitle.
///
/// Matches the geometry of the real rows it stands in for, which is the point -
/// a skeleton that is the wrong size defeats its own purpose.
class SugoSkeletonRow extends StatelessWidget {
  const SugoSkeletonRow({super.key, this.showAvatar = true});

  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.md),
      elevation: SugoElevation.sm,
      child: Row(
        children: <Widget>[
          if (showAvatar) ...<Widget>[
            const SugoSkeleton.circle(size: 42),
            const SizedBox(width: AppSizes.md),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SugoSkeleton(height: 13, width: 150),
                SizedBox(height: AppSizes.sm),
                SugoSkeleton(height: 10, width: 90),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          const SugoSkeleton(height: 20, width: 56, radius: 999),
        ],
      ),
    );
  }
}

/// Several [SugoSkeletonRow]s, for a list that is still loading.
class SugoSkeletonList extends StatelessWidget {
  const SugoSkeletonList({super.key, this.count = 3, this.showAvatar = true});

  final int count;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(
        count,
        (_) => SugoSkeletonRow(showAvatar: showAvatar),
      ),
    );
  }
}
