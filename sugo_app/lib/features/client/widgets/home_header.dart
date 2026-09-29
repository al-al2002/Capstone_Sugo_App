import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_icon_button.dart';
import '../../../core/widgets/sugo_logo.dart';
import '../../../core/widgets/sugo_search_field.dart';

/// The top of the client home: brand, the two things not on a tab, a
/// greeting, and the search.
///
/// ## The Dispatch header (2026-09-29)
///
/// The navy block from the 2026-09-28 reference is gone. The header now sits
/// on the page's own Paper ground: the SUGO mark and wordmark on the left, the
/// inbox and the bell on the right as hairline discs, then the greeting and a
/// flat search bar.
///
/// Why: the Dispatch design spends its one strong element on the booking
/// itself - the route card or the "Need a tech fix?" banner just below. A
/// navy header above a navy banner was two heroes competing for the first
/// glance, and the header won, although it is the part of the screen with
/// the least to say. On a light header the eye lands on the card.
///
/// ## Why the greeting may wrap
///
/// "Good evening, Christopher" does not fit on one line of a 320dp phone at
/// title size. It wraps to a second line rather than ellipsising: cutting
/// somebody's name off in the one place the app addresses them personally is
/// worse than not greeting them at all.
///
/// The wave emoji is gone too. It rendered in whatever emoji font the phone
/// had (a box in tests), and ui-ux-pro-max's `no-emoji-icons` rule applies
/// to decoration as much as to controls.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.name,
    required this.unreadNotifications,
    required this.unreadMessages,
    required this.onOpenNotifications,
    required this.onOpenMessages,
    required this.onSearch,
    this.topInset = 0,
    this.now,
  });

  /// The client's full name, or null before the profile has loaded.
  final String? name;
  final int unreadNotifications;

  /// Unread messages across every thread. Messages live here rather than in
  /// the bottom bar so Community can keep that tab.
  final int unreadMessages;

  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenMessages;
  final VoidCallback onSearch;

  /// The status bar's height. The header runs underneath it, so the content
  /// is pushed down by exactly this much.
  final double topInset;

  /// The time the greeting is chosen for; the clock when null. Tests pin it,
  /// or a golden taken in the afternoon fails every morning.
  final DateTime? now;

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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        topInset + AppSizes.sm,
        AppSizes.screenPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SugoLogoMark(size: 32),
              const SizedBox(width: AppSizes.sm + 2),
              Text(
                AppStrings.appName,
                style: AppTextStyles.sectionTitle.copyWith(
                  color: AppColors.primary,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              SugoIconButton(
                icon: Icons.chat_bubble_outline_rounded,
                tooltip: 'Messages',
                badgeCount: unreadMessages,
                size: 40,
                onPressed: onOpenMessages,
              ),
              const SizedBox(width: AppSizes.xs),
              SugoIconButton(
                icon: Icons.notifications_none_rounded,
                tooltip: 'Notifications',
                badgeCount: unreadNotifications,
                size: 40,
                onPressed: onOpenNotifications,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          Text(
            '$_salutation, $_firstName',
            maxLines: 2,
            style: AppTextStyles.title,
          ),
          const SizedBox(height: 2),
          const Text('What needs fixing today?', style: AppTextStyles.subtitle),
          const SizedBox(height: AppSizes.lg),
          SugoSearchField.button(
            onTap: onSearch,
            hint: 'Search a service or device',
          ),
        ],
      ),
    );
  }
}
