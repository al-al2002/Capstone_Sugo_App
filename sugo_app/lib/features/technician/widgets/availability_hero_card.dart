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
    this.onCover = false,
  });

  /// The vacation covering today, or null when they are working.
  final TimeOff? vacation;

  final VoidCallback onSetVacation;
  final VoidCallback onEndVacation;
  final VoidCallback onEditDates;

  /// Tests only.
  final DateTime Function()? clock;

  /// Drawn as a glass panel inside the dashboard's navy header (2026-11-16),
  /// instead of a navy card of its own. Same words, same actions, same
  /// vacation rules - only the drawing changes. A navy card directly under a
  /// navy header was two heroes for one glance.
  final bool onCover;

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
      child: onCover
          ? _coverStrip(away)
          : away == null
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
              body:
                  'Clients can see your profile but cannot book you until '
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
  Widget _coverStrip(TimeOff? away) {
    return away == null
        ? _CoverStrip(
            key: const ValueKey<String>('cover-working'),
            dot: _takingJobsGreen,
            badge: 'Active',
            title: 'Taking jobs',
            body: 'Visible and bookable by clients right now.',
            trailing: _SolidButton(
              icon: Icons.beach_access_rounded,
              label: 'Set vacation',
              foreground: AppColors.primary,
              onPressed: onSetVacation,
              compact: true,
            ),
          )
        : _CoverStrip(
            key: const ValueKey<String>('cover-away'),
            dot: AppColors.accent,
            badge: 'On vacation',
            title: _awayTitle(away),
            body: 'Clients can see your profile but cannot book you.',
            actions: <Widget>[
              _SolidButton(
                icon: Icons.work_outline_rounded,
                label: 'End vacation',
                foreground: AppColors.accentDark,
                onPressed: onEndVacation,
                compact: true,
              ),
              _GhostButton(
                icon: Icons.edit_calendar_rounded,
                label: 'Edit dates',
                onPressed: onEditDates,
                compact: true,
              ),
            ],
          );
  }

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
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final VoidCallback onPressed;

  /// 40px tall and pill-shaped, for the glass panel in the header.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: foreground,
        minimumSize: Size(0, compact ? 40 : AppSizes.touchTarget),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSizes.md : AppSizes.lg,
        ),
        // The family is named: a button's textStyle *replaces* the inherited
        // one, and without it this label fell back to the phone's font.
        textStyle: _buttonLabel,
        shape: compact
            ? const StadiumBorder()
            : RoundedRectangleBorder(
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
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// 40px tall and pill-shaped, for the glass panel in the header.
  final bool compact;

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
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.75),
          width: 1.3,
        ),
        minimumSize: Size(0, compact ? 40 : AppSizes.touchTarget),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSizes.md : AppSizes.lg,
        ),
        textStyle: _buttonLabel,
        shape: compact
            ? const StadiumBorder()
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
              ),
      ),
    );
  }
}

/// "Taking jobs" green, bright enough to read on the navy header. The
/// palette's success green is a text colour for white cards (#157F4B) and
/// all but disappears on navy.
const Color _takingJobsGreen = Color(0xFF34D399);

/// The availability state as a glass panel on the dashboard's navy header.
class _CoverStrip extends StatelessWidget {
  const _CoverStrip({
    super.key,
    required this.dot,
    required this.badge,
    required this.title,
    required this.body,
    this.trailing,
    this.actions = const <Widget>[],
  });

  final Color dot;
  final String badge;
  final String title;
  final String body;

  /// One action beside the title.
  final Widget? trailing;

  /// Several actions, on their own row under the text.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        // The one action sits beside the title while there is room for it;
        // on a small phone or at large text it drops under the words rather
        // than squeezing the title to nothing.
        final bool inline =
            trailing != null &&
            box.maxWidth >= 300 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.15;
        final List<Widget> below = <Widget>[
          if (trailing != null && !inline) trailing!,
          ...actions,
        ];
        return _build(inline: inline, below: below);
      },
    );
  }

  Widget _build({required bool inline, required List<Widget> below}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.md),
      // Navy-tinted glass, the same as the figures under it.
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppSizes.radius + 4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // The status light: a dot with a soft halo of its own colour.
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: dot.withValues(alpha: 0.6),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      badge.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: dot,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (inline) ...<Widget>[
                const SizedBox(width: AppSizes.sm),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: AppSizes.xs + 2),
          Text(
            body,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          if (below.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Wrap(
              spacing: AppSizes.sm,
              runSpacing: AppSizes.sm,
              children: below,
            ),
          ],
        ],
      ),
    );
  }
}
