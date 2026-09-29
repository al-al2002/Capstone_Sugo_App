import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';
import 'sugo_card.dart';

/// What a screen shows when it has nothing to show.
///
/// ## Why this is a shared widget and not a `Center(child: Text('No jobs'))`
///
/// Empty states are the screens a user sees *first* - before they have posted
/// a job, before anyone has answered their question, before a technician has
/// been offered work. They are the app's first impression far more often than
/// the populated state is, and they were the most neglected part of the old
/// UI: a grey icon and four words, different on every screen.
///
/// Three slots, in the order they earn attention:
///
/// 1. **A glyph on a soft wash**, so the space reads as intentionally empty
///    rather than broken or still loading.
/// 2. **A title that says what is missing**, phrased as a state and not an
///    apology - "No questions yet", never "Oops, nothing found!".
/// 3. **A line explaining what fills it**, and where possible a button that
///    does exactly that. An empty state with a way out converts; one without
///    is a dead end.
///
/// ## The variants
///
/// [SugoEmptyState.error] and [SugoEmptyState.loading] exist so that the three
/// states a list can be in are drawn by one widget at one size. When empty,
/// error and loading are built separately they end up different heights, and
/// the surrounding layout jumps as the data resolves.
class SugoEmptyState extends StatelessWidget {
  const SugoEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.tint = AppColors.primarySoft,
    this.foreground = AppColors.primary,
    this.compact = false,
  }) : _isLoading = false;

  /// Something went wrong. Same shape, warning tones, and the action is a
  /// retry rather than a next step.
  const SugoEmptyState.error({
    super.key,
    required this.message,
    this.title = 'Something went wrong',
    this.icon = Icons.cloud_off_rounded,
    this.actionLabel = 'Try again',
    this.onAction,
    this.compact = false,
  }) : tint = AppColors.warningSoft,
       foreground = AppColors.warning,
       _isLoading = false;

  /// Still fetching. Keeps the footprint of the populated state so the layout
  /// does not jump when the data lands.
  const SugoEmptyState.loading({
    super.key,
    this.message = 'Just a moment…',
    this.title = '',
    this.icon = Icons.hourglass_empty_rounded,
    this.compact = false,
  }) : actionLabel = null,
       onAction = null,
       tint = AppColors.primarySoft,
       foreground = AppColors.primary,
       _isLoading = true;

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color tint;
  final Color foreground;

  /// Tighter padding, for an empty state inside a card rather than filling a
  /// tab.
  final bool compact;

  final bool _isLoading;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.lg,
        vertical: compact ? AppSizes.lg : AppSizes.xl + AppSizes.xs,
      ),
      elevation: SugoElevation.sm,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Glyph(
            icon: icon,
            tint: tint,
            foreground: foreground,
            spinning: _isLoading,
          ),
          const SizedBox(height: AppSizes.lg),
          if (title.isNotEmpty) ...<Widget>[
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleSmall.copyWith(fontSize: 15),
            ),
            const SizedBox(height: AppSizes.xs + 2),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.subtitle.copyWith(height: 1.5),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: AppSizes.lg + AppSizes.xs),
            SizedBox(
              height: AppSizes.socialButtonHeight,
              child: FilledButton.icon(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: foreground,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.xl,
                  ),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The glyph, on a two-ring soft wash.
///
/// The outer ring is the same tint at lower opacity, which gives the icon a
/// halo instead of a hard-edged disc. A single flat circle behind an icon is
/// the thing that makes an empty state look like a placeholder nobody
/// finished.
class _Glyph extends StatefulWidget {
  const _Glyph({
    required this.icon,
    required this.tint,
    required this.foreground,
    required this.spinning,
  });

  final IconData icon;
  final Color tint;
  final Color foreground;
  final bool spinning;

  @override
  State<_Glyph> createState() => _GlyphState();
}

class _GlyphState extends State<_Glyph> with SingleTickerProviderStateMixin {
  /// Created in [initState], never lazily.
  ///
  /// This was `late final _controller = AnimationController(vsync: this, ...)`,
  /// which only runs on first access - and the only thing that touched it was
  /// the spinning branch of [build]. A non-spinning empty state therefore
  /// never created it, so [dispose] was the first access, and constructing a
  /// controller there calls `createTicker`, which looks up `TickerMode` on an
  /// element that has already been deactivated:
  ///
  ///     Looking up a deactivated widget's ancestor is unsafe.
  ///
  /// That throw happens *during* unmount, so the tree is left half torn down,
  /// and every frame after it reports `RenderBox was not laid out` and
  /// `Cannot hit test a render box with no size` - dozens of them, none of
  /// which name the real cause.
  ///
  /// A `late final` field on a `State` is only safe when `build` reaches it on
  /// every path. When it does not, initialise it here.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.spinning) _controller.repeat();
  }

  @override
  void didUpdateWidget(_Glyph old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.spinning && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget glyph = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: widget.tint, shape: BoxShape.circle),
      child: Icon(widget.icon, size: 26, color: widget.foreground),
    );

    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: widget.tint.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: widget.spinning
          ? RotationTransition(turns: _controller, child: glyph)
          : TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.85, end: 1),
              duration: AppMotion.slow,
              curve: AppMotion.playful,
              builder: (BuildContext context, double scale, Widget? child) =>
                  Transform.scale(scale: scale, child: child),
              child: glyph,
            ),
    );
  }
}
