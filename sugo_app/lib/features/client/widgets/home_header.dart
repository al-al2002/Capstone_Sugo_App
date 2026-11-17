import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_brand_cover.dart';
import '../../../core/widgets/sugo_glass_icon_button.dart';
import '../../../core/widgets/sugo_logo.dart';
import '../../../core/widgets/sugo_search_field.dart';

/// The top of the client home: brand, inbox and bell, a greeting, the
/// invitation to book, and the search.
///
/// ## The 2026-11-16 renovation
///
/// At the user's request ("renovate both dashboards"). The header now sits on
/// the illustrated Davao cover ([SugoBrandCover], daylight), the same scene
/// as the client's profile, so the home, the posting flow and the profile
/// read as one app.
///
/// **One hero, still.** A navy header was removed on 2026-09-29 because it
/// competed with the navy "Need a tech fix?" banner under it - two heroes
/// for the first glance. That reasoning is kept, not ignored: the banner is
/// now *inside* the header. With no booking under way the header carries the
/// invitation and its button ([onBookNow]); with one, the header is just the
/// greeting and the white booking card below is the one strong element.
///
/// **The search floats.** It overlaps the header's bottom edge on a soft
/// shadow, so it reads as the doorway between the header and the page - and
/// stays where a thumb finds it.
///
/// ## Why the greeting may wrap
///
/// "Good evening, Christopher" does not fit on one line of a 320dp phone at
/// title size. It wraps rather than ellipsising: cutting somebody's name off
/// in the one place the app addresses them personally is worse than not
/// greeting them at all.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.name,
    required this.unreadNotifications,
    required this.unreadMessages,
    required this.onOpenNotifications,
    required this.onOpenMessages,
    required this.onSearch,
    this.onBookNow,
    this.topInset = 0,
    this.now,
  });

  final String? name;
  final int unreadNotifications;

  /// Unread messages across every thread. The inbox is not a tab, so its
  /// count lives here.
  final int unreadMessages;

  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenMessages;
  final VoidCallback onSearch;

  /// "Book a technician". Null hides the invitation - the dashboard passes
  /// it only when no booking is under way.
  final VoidCallback? onBookNow;

  /// The status-bar height. The cover runs under the status bar.
  final double topInset;

  /// For tests and goldens: the moment the greeting is worked out from.
  final DateTime? now;

  /// Half the search bar's height: how far it hangs below the cover.
  static const double _searchOverlap = 24;

  String get _salutation {
    final int hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName {
    final String full = (name ?? '').trim();
    if (full.isEmpty) return 'there';
    return full.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: _searchOverlap),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(28),
            ),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: SugoBrandCover(
                    style: SugoCoverStyle.client,
                    // Quiet: the greeting runs across the whole cover, so
                    // the skyline stays low and no route crosses the words.
                    quiet: true,
                    topInset: topInset + 56,
                    motifHeight: 160,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSizes.screenPadding,
                    topInset + AppSizes.xs,
                    AppSizes.screenPadding - 4,
                    _searchOverlap + AppSizes.lg + 2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const SugoLogoMark(size: 30, onDark: true),
                          const SizedBox(width: AppSizes.sm + 2),
                          Text(
                            AppStrings.appName,
                            style: AppTextStyles.sectionTitle.copyWith(
                              color: Colors.white,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const Spacer(),
                          SugoGlassIconButton(
                            icon: Icons.chat_bubble_outline_rounded,
                            tooltip: 'Messages',
                            badgeCount: unreadMessages,
                            onPressed: onOpenMessages,
                          ),
                          SugoGlassIconButton(
                            icon: Icons.notifications_none_rounded,
                            tooltip: 'Notifications',
                            badgeCount: unreadNotifications,
                            onPressed: onOpenNotifications,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSizes.md),
                      Semantics(
                        header: true,
                        child: Text(
                          '$_salutation, $_firstName',
                          maxLines: 2,
                          style: AppTextStyles.title.copyWith(
                            color: Colors.white,
                            fontSize: 22,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        onBookNow == null
                            ? 'What needs fixing today?'
                            : 'Trusted technicians near you, ready to help.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                      if (onBookNow != null) ...<Widget>[
                        const SizedBox(height: AppSizes.md),
                        _BookButton(onPressed: onBookNow!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: AppSizes.screenPadding,
          right: AppSizes.screenPadding,
          bottom: 0,
          // The standard card depth on the field's own radius: lifted off
          // the cover's edge, no heavier than any card on the page.
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSizes.radius),
              boxShadow: AppElevation.md,
            ),
            child: SugoSearchField.button(
              onTap: onSearch,
              hint: 'Search a service or device',
            ),
          ),
        ),
      ],
    );
  }
}

/// The header's one call to action, white on the navy cover.
class _BookButton extends StatelessWidget {
  const _BookButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('Book a technician'),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primary,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
        shape: const StadiumBorder(),
        // Named: a button's textStyle replaces the theme's, not merges.
        textStyle: const TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
