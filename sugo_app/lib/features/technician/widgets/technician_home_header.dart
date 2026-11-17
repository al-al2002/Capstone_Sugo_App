import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_brand_cover.dart';
import '../../../core/widgets/sugo_glass_icon_button.dart';
import '../../rb_cars/models/technician.dart';
import '../models/time_off.dart';
import 'availability_hero_card.dart';
import 'technician_stat_cards.dart';

/// The top of the technician's home: a status console on the dusk cover
/// (2026-11-16).
///
/// At the user's request ("renovate both dashboards"). Before, the home was a
/// row of name and buttons, then a navy availability card, then requests,
/// then - well below - the week's figures, every block the same white card.
/// Three questions a technician opens the app with are now answered in one
/// panel, in the order they are asked:
///
/// 1. **Who and what's new** - their avatar and name, the inbox and the bell.
/// 2. **Can clients book me?** - the availability panel, with the vacation
///    actions right there ([AvailabilityHeroCard] in its glass form).
/// 3. **How is my week?** - the four figures ([TechnicianStatCards], glass).
///
/// It sits on the illustrated Davao cover in its dusk light
/// ([SugoCoverStyle.technician], quiet), the same scene as the technician's
/// profile, so their screens read as one set. Everything below it on the
/// page - requests first - is now the only thing in white cards, which is
/// what makes the request the eye lands on next.
class TechnicianHomeHeader extends StatelessWidget {
  const TechnicianHomeHeader({
    super.key,
    required this.technician,
    required this.vacation,
    required this.unreadMessages,
    required this.unreadNotifications,
    required this.onOpenInbox,
    required this.onOpenNotifications,
    required this.onSetVacation,
    required this.onEndVacation,
    required this.onEditDates,
    required this.earningsToday,
    required this.jobsThisWeek,
    this.topInset = 0,
    this.now,
  });

  final Technician technician;

  /// Today's vacation, or null while taking jobs.
  final TimeOff? vacation;

  final int unreadMessages;
  final int unreadNotifications;
  final VoidCallback onOpenInbox;
  final VoidCallback onOpenNotifications;

  final VoidCallback onSetVacation;
  final VoidCallback onEndVacation;
  final VoidCallback onEditDates;

  /// The estimate, from completed jobs and the tier rate - see
  /// [TechnicianStatCards] for why it says so.
  final int earningsToday;
  final int jobsThisWeek;

  /// The status-bar height. The cover runs under the status bar.
  final double topInset;

  /// For tests and goldens: the moment the greeting is worked out from.
  final DateTime? now;

  String get _salutation {
    final int hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    final bool away = vacation != null;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: SugoBrandCover(
              style: SugoCoverStyle.technician,
              // Quiet: the console's text and panels run across the whole
              // cover, so no route crosses them.
              quiet: true,
              motifHeight: 220,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSizes.screenPadding,
              topInset + AppSizes.sm,
              AppSizes.screenPadding - 4,
              AppSizes.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    // The ring is the availability light: green while
                    // bookable, orange while away - the same two colours as
                    // the panel below it.
                    SugoAvatar(
                      name: technician.displayName,
                      imageUrl: technician.avatarUrl,
                      size: AppSizes.avatarMd,
                      verified: technician.isVerified,
                      ringColor: away
                          ? AppColors.accent
                          : const Color(0xFF34D399),
                    ),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _salutation,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          Semantics(
                            header: true,
                            child: Text(
                              technician.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SugoGlassIconButton(
                      icon: Icons.mail_outline_rounded,
                      tooltip: 'Messages',
                      badgeCount: unreadMessages,
                      onPressed: onOpenInbox,
                    ),
                    SugoGlassIconButton(
                      icon: Icons.notifications_none_rounded,
                      tooltip: 'Notifications',
                      badgeCount: unreadNotifications,
                      onPressed: onOpenNotifications,
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.lg),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: AvailabilityHeroCard(
                    vacation: vacation,
                    onSetVacation: onSetVacation,
                    onEndVacation: onEndVacation,
                    onEditDates: onEditDates,
                    clock: now == null ? null : () => now!,
                    onCover: true,
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TechnicianStatCards(
                    technician: technician,
                    earningsToday: earningsToday,
                    jobsThisWeek: jobsThisWeek,
                    onCover: true,
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
