import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../models/technician.dart';
import 'technician_avatar.dart';

/// The "send your request" moment (2026-11-17).
///
/// It used to be a plain `AlertDialog` with two text buttons - the one point
/// in the flow where the client commits to a person, dressed as a system
/// prompt. Now it is a sheet about that person: their photo lands with a
/// small overshoot and a few rings pulse out from it, the price sits under
/// their name, and Send is a full-width button under the thumb.
///
/// Motion is finite on purpose. The rings pulse three times and stop, so the
/// sheet settles (and widget tests can `pumpAndSettle`), and under reduced
/// motion nothing moves at all.
///
/// Returns true when the client sends, false or null when they back out.
/// [contentBuilder] gets a `StateSetter`, so content with its own choice -
/// the shop repair's bring-it-myself / delivery switch - can rebuild the
/// sheet as the fee changes.
Future<bool?> showBookingRequestSheet({
  required BuildContext context,
  required Technician? technician,
  required String name,
  required bool busy,
  required Widget Function(StateSetter setSheetState) contentBuilder,
}) {
  return showSugoBottomSheet<bool>(
    context: context,
    builder: (BuildContext sheetContext) => StatefulBuilder(
      builder: (BuildContext _, StateSetter setSheetState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSizes.sm),
          Center(
            child: _PulsingAvatar(technician: technician, busy: busy),
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            busy ? '$name is on another job' : 'Send your request to $name?',
            textAlign: TextAlign.center,
            style: AppTextStyles.headline,
          ),
          if (technician != null && technician.rating > 0) ...<Widget>[
            const SizedBox(height: AppSizes.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 3),
                Text(
                  '${technician.rating.toStringAsFixed(1)} · '
                  '${technician.totalJobs} jobs done',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSizes.lg),
          Container(
            padding: const EdgeInsets.all(AppSizes.lg),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppSizes.radius),
              border: Border.all(color: AppColors.border),
            ),
            child: contentBuilder(setSheetState),
          ),
          const SizedBox(height: AppSizes.lg),
          PrimaryButton(
            label: busy ? 'Send and wait' : 'Send request',
            icon: Icons.send_rounded,
            onPressed: () => Navigator.of(sheetContext).pop(true),
          ),
          const SizedBox(height: AppSizes.xs),
          TextButton(
            onPressed: () => Navigator.of(sheetContext).pop(false),
            child: Text(busy ? 'Choose someone else' : 'Keep looking'),
          ),
        ],
      ),
    ),
  );
}

/// The technician's photo, landing with an overshoot while rings pulse out.
class _PulsingAvatar extends StatefulWidget {
  const _PulsingAvatar({required this.technician, required this.busy});

  final Technician? technician;
  final bool busy;

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  static const double _avatar = 76;
  static const double _box = 124;
  static const int _pulses = 3;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Finite: three pulses, then still. Nothing at all under reduced motion.
    if (!AppMotion.reduced(context)) _pulse.repeat(count: _pulses);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color ring = widget.busy ? AppColors.warning : AppColors.secondary;
    final Technician? technician = widget.technician;

    return SizedBox(
      width: _box,
      height: _box,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // Two rings, half a cycle apart, growing and fading.
          AnimatedBuilder(
            animation: _pulse,
            builder: (BuildContext context, Widget? _) => Stack(
              alignment: Alignment.center,
              children: <Widget>[
                for (final double offset in const <double>[0, 0.5])
                  _Ring(
                    progress: _pulse.isAnimating
                        ? (_pulse.value + offset) % 1
                        : 1,
                    color: ring,
                    from: _avatar,
                    to: _box,
                  ),
              ],
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.6, end: 1),
            duration: AppMotion.reduced(context)
                ? Duration.zero
                : AppMotion.slow,
            curve: AppMotion.playful,
            builder: (BuildContext context, double scale, Widget? child) =>
                Transform.scale(scale: scale, child: child),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                if (technician != null)
                  TechnicianAvatar(
                    technician: technician,
                    size: _avatar,
                    borderColor: ring,
                  )
                else
                  CircleAvatar(
                    radius: _avatar / 2,
                    backgroundColor: AppColors.primarySoft,
                    child: const Icon(
                      Icons.engineering_rounded,
                      size: 34,
                      color: AppColors.primaryDark,
                    ),
                  ),
                // What is about to happen: a request goes out - or, for a
                // busy technician, the reason to think twice.
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: widget.busy
                          ? AppColors.warning
                          : AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                    child: Icon(
                      widget.busy ? Icons.handyman_rounded : Icons.send_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.progress,
    required this.color,
    required this.from,
    required this.to,
  });

  /// 0 = at the avatar's edge, 1 = fully out and invisible.
  final double progress;
  final Color color;
  final double from;
  final double to;

  @override
  Widget build(BuildContext context) {
    final double size = from + (to - from) * progress;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: 0.45 * (1 - progress)),
          width: 2,
        ),
      ),
    );
  }
}
