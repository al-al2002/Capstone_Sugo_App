import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/time_off.dart';

/// The first thing on the technician's dashboard: can clients book me today?
///
/// Two states, told apart by the app's own two colours rather than by a
/// status word the eye has to read:
///
///   * **Taking jobs** - the brand blue, with "Set vacation".
///   * **On vacation** - the accent orange, with how long is left, when they
///     are back, and "End vacation" / "Edit dates".
///
/// It took the place of the online/offline toggle. A toggle had to be
/// remembered several times a day; this only changes when someone plans time
/// away, and says so in words a client would understand.
class AvailabilityHeroCard extends StatelessWidget {
  const AvailabilityHeroCard({
    super.key,
    required this.vacation,
    required this.onSetVacation,
    required this.onEndVacation,
    required this.onEditDates,
    this.clock,
  });

  /// The vacation covering today, or null when they are working.
  final TimeOff? vacation;

  final VoidCallback onSetVacation;
  final VoidCallback onEndVacation;
  final VoidCallback onEditDates;

  /// Tests only.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final TimeOff? away = vacation;

    return AnimatedSwitcher(
      duration: AppMotion.slow,
      switchInCurve: AppMotion.standard,
      transitionBuilder: (Widget child, Animation<double> animation) =>
          FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
              child: child,
            ),
          ),
      child: away == null
          ? _Panel(
              key: const ValueKey<String>('working'),
              colors: const <Color>[AppColors.primary, AppColors.primaryDark],
              badge: 'Active',
              title: 'Taking jobs',
              body: 'You are visible and bookable by clients right now.',
              watermark: Icons.event_available_rounded,
              actions: <Widget>[
                _SolidButton(
                  icon: Icons.beach_access_rounded,
                  label: 'Set vacation',
                  foreground: AppColors.primary,
                  onPressed: onSetVacation,
                ),
              ],
            )
          : _Panel(
              key: const ValueKey<String>('away'),
              // The text orange, not the bright one: this panel carries white
              // words, and white on the bright orange is 2.1:1 - on this
              // it is 5.0:1. Still unmistakably the "away" colour.
              colors: <Color>[
                AppColors.accentDark,
                Color.lerp(AppColors.accentDark, AppColors.navy, 0.2)!,
              ],
              badge: 'On vacation',
              title: _awayTitle(away),
              body: 'Clients can see your profile but cannot book you until '
                  'you return.',
              watermark: Icons.beach_access_rounded,
              actions: <Widget>[
                _SolidButton(
                  icon: Icons.work_outline_rounded,
                  label: 'End vacation',
                  foreground: AppColors.accentDark,
                  onPressed: onEndVacation,
                ),
                _GhostButton(
                  icon: Icons.edit_calendar_rounded,
                  label: 'Edit dates',
                  onPressed: onEditDates,
                ),
              ],
            ),
    );
  }

  /// "3 days left · back Thu, Sep 25", counting today - so a vacation that
  /// ends today reads "1 day left", as a person would say it.
  String _awayTitle(TimeOff away) {
    final DateTime now = (clock ?? DateTime.now)();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int left = away.endsOn.difference(today).inDays + 1;
    final String back = DateFormat('EEE, MMM d').format(away.backOn);
    return '$left ${left == 1 ? 'day' : 'days'} left · back $back';
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.colors,
    required this.badge,
    required this.title,
    required this.body,
    required this.watermark,
    required this.actions,
  });

  final List<Color> colors;
  final String badge;
  final String title;
  final String body;
  final IconData watermark;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(AppSizes.panelRadius),
      ),
      child: Stack(
        children: <Widget>[
          // A large, faint glyph in the corner: character without a second
          // colour, and it tells the two states apart at a glance.
          Positioned(
            right: -18,
            bottom: -26,
            child: Icon(
              watermark,
              size: 132,
              color: Colors.white.withValues(alpha: 0.13),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSizes.lg + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                Wrap(
                  spacing: AppSizes.sm,
                  runSpacing: AppSizes.sm,
                  children: actions,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// White, the panel's colour on it: the main action.
class _SolidButton extends StatelessWidget {
  const _SolidButton({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: foreground,
        minimumSize: const Size(0, AppSizes.touchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
        // The family is named: a button's textStyle *replaces* the inherited
        // one, and without it this label fell back to the phone's font.
        textStyle: _buttonLabel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        ),
      ),
    );
  }
}

const TextStyle _buttonLabel = TextStyle(
  fontFamily: AppTextStyles.fontFamily,
  fontSize: 13,
  fontWeight: FontWeight.w800,
);

/// Outlined in white: the secondary action.
class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        // Explicit: the app's outlined-button theme fills with the surface
        // colour, which would put white text on a white button here.
        backgroundColor: Colors.transparent,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.75), width: 1.3),
        minimumSize: const Size(0, AppSizes.touchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
        textStyle: _buttonLabel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        ),
      ),
    );
  }
}
