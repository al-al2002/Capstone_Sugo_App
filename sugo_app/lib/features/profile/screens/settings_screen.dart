import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/session/session_state.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_dialog.dart';
import '../../../core/widgets/sugo_list_tile.dart';
import '../../../core/widgets/sugo_logo.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../../help/help_screen.dart';
import '../../notifications/screens/notification_settings_screen.dart';
import 'profile_setup_screen.dart';
import 'saved_addresses_screen.dart';

/// Settings, grouped by what each group is actually about.
///
/// ## Why the groups, and why they are short
///
/// The brief asks for Account, Notifications, Privacy, Location, Appearance,
/// Help and About, and warns against one giant list. Three of those would be
/// empty in SUGO today, and an empty settings page is worse than no page:
///
/// * **Appearance** - the app has one theme. A "Dark mode" switch that does
///   nothing is a promise, and a promise in settings is a support ticket.
/// * **Privacy** and **Location** - SUGO stores no toggleable privacy state.
///   What it *does* with a location and who can see a phone number are facts
///   worth stating, so they appear as explanations rather than as switches
///   that change nothing.
///
/// So the page is short on purpose. Every row here either changes something
/// or explains something the user cannot see for themselves.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SessionProfile? profile = context.watch<SessionController>().profile;
    final bool isActive = profile?.registrationStatus == 'active';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const SugoAppBar(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPadding,
          AppSizes.lg,
          AppSizes.screenPadding,
          AppSizes.xxl,
        ),
        children: <Widget>[
          SugoListGroup(
            title: 'Account',
            children: <Widget>[
              if (isActive)
                SugoListTile(
                  icon: Icons.photo_camera_outlined,
                  title: (profile?.isTechnician ?? false)
                      ? 'Photo and workshop'
                      : 'Profile photo',
                  subtitle: 'Your name is fixed to your verified ID',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ProfileSetupScreen.edit(),
                    ),
                  ),
                ),
              if (profile?.isClient ?? false)
                SugoListTile(
                  icon: Icons.location_on_outlined,
                  title: 'Saved addresses',
                  subtitle: 'Home, work, anywhere you need repairs',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SavedAddressesScreen(),
                    ),
                  ),
                ),
              SugoListTile(
                icon: Icons.mail_outline_rounded,
                title: 'Email',
                subtitle:
                    context.watch<AuthController>().user?.email ??
                    'Signed in',
                showChevron: false,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.xl),
          SugoListGroup(
            title: 'Alerts',
            children: <Widget>[
              SugoListTile(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                subtitle: 'What you are told about, and on which phone',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.xl),
          SugoListGroup(
            title: 'Privacy & location',
            children: <Widget>[
              SugoListTile(
                icon: Icons.shield_outlined,
                title: 'Who can see your details',
                subtitle: 'Phone numbers, addresses and chats',
                onTap: () => _showPrivacy(context),
              ),
              SugoListTile(
                icon: Icons.my_location_rounded,
                title: 'How SUGO uses location',
                subtitle: 'Distances, tracking, and when it stops',
                onTap: () => _showLocation(context),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.xl),
          SugoListGroup(
            title: 'Support',
            children: <Widget>[
              SugoListTile(
                icon: Icons.help_outline_rounded,
                title: 'Help & support',
                subtitle: 'Answers, and how to reach a person',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
                ),
              ),
              SugoListTile(
                icon: Icons.info_outline_rounded,
                title: 'About SUGO',
                onTap: () => _showAbout(context),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.xl),
          SugoListGroup(
            children: <Widget>[
              SugoListTile(
                icon: Icons.logout_rounded,
                title: 'Sign out',
                subtitle: 'You will need your password to return',
                destructive: true,
                onTap: () => _confirmSignOut(context),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.xl),
          Center(
            child: Column(
              children: <Widget>[
                const SugoLogo(fontSize: 20, showTagline: false),
                const SizedBox(height: AppSizes.sm),
                Text('Version 1.0.0', style: AppTextStyles.micro),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _confirmSignOut(BuildContext context) async {
    final bool out = await showSugoConfirmDialog(
      context: context,
      icon: Icons.logout_rounded,
      title: 'Sign out?',
      message: 'You will need your email and password to sign in again.',
      confirmLabel: 'Sign out',
      cancelLabel: 'Stay',
      destructive: true,
    );
    if (out && context.mounted) {
      await context.read<AuthController>().signOut();
    }
  }

  /// What the app actually does with personal data, in plain words.
  ///
  /// Everything stated here is enforced by a policy or a function in the
  /// database, not by the UI - which is why it can be stated at all.
  static void _showPrivacy(BuildContext context) {
    showSugoBottomSheet<void>(
      context: context,
      title: 'Who can see your details',
      builder: (BuildContext sheetContext) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Point(
            icon: Icons.call_rounded,
            title: 'Your phone number',
            body:
                'Released to a technician only once you have a confirmed '
                'booking with them. Browsing profiles never exposes it, in '
                'either direction.',
          ),
          _Point(
            icon: Icons.home_rounded,
            title: 'Your address',
            body:
                'Sent to the technician on a job you booked, and to nobody '
                'else. Technicians you did not book see only a distance.',
          ),
          _Point(
            icon: Icons.forum_rounded,
            title: 'Your messages',
            body:
                'A chat belongs to one job, and only its two people can open '
                'it. Messages and photos cannot be deleted by either side, '
                'because they are the record if the work is disputed.',
          ),
          _Point(
            icon: Icons.badge_rounded,
            title: 'Your ID',
            body:
                'Seen by the SUGO review team during verification. It is '
                'never shown to other users.',
          ),
        ],
      ),
    );
  }

  static void _showLocation(BuildContext context) {
    showSugoBottomSheet<void>(
      context: context,
      title: 'How SUGO uses location',
      builder: (BuildContext sheetContext) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Point(
            icon: Icons.straighten_rounded,
            title: 'Distances on the home screen',
            body:
                'Taken from your saved address or a position your phone had '
                'already cached. SUGO does not ask for a fresh fix just to '
                'label a card.',
          ),
          _Point(
            icon: Icons.near_me_rounded,
            title: 'Live tracking',
            body:
                'Only a technician shares live position, only while a job is '
                'travelling, and only with the client on that job. It stops '
                'when the job is delivered.',
          ),
          _Point(
            icon: Icons.map_rounded,
            title: 'Pinning a job',
            body:
                'The pin you set on a booking is stored with that booking so '
                'the technician can find you. Deleting a saved address does '
                'not change a booking already made.',
          ),
        ],
      ),
    );
  }

  static void _showAbout(BuildContext context) {
    showSugoBottomSheet<void>(
      context: context,
      title: 'About SUGO',
      subtitle: AppStrings.tagline,
      builder: (BuildContext sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'SUGO connects people in Davao with verified technicians for '
            'computers, phones, appliances, networks and CCTV. Post what is '
            'broken and the matching engine ranks the three best technicians '
            'for that job - on skill, distance, rating and availability - and '
            'explains why each one was chosen.',
            style: AppTextStyles.body,
          ),
          const SizedBox(height: AppSizes.lg),
          SugoCard(
            elevation: SugoElevation.sm,
            background: AppColors.primarySofter,
            borderColor: AppColors.primarySoft,
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.school_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Text(
                    'Built as an undergraduate capstone project. Payments are '
                    'settled directly between clients and technicians; SUGO '
                    'does not process money.',
                    style: AppTextStyles.micro,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Text('Version 1.0.0', style: AppTextStyles.micro),
        ],
      ),
    );
  }
}

/// One explained fact inside a settings sheet.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppSizes.radius),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppTextStyles.titleSmall),
                const SizedBox(height: 3),
                Text(body, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
