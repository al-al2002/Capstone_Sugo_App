import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/local_prefs.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_list_tile.dart';
import '../models/app_notification.dart';

/// What the client wants to be told about, and where.
///
/// ## Why the two sections are separate, and worded carefully
///
/// **In the app** controls the notification centre and the bell's badge. These
/// are local filters, and they say so.
///
/// **On this phone** is push, and it is a single switch rather than a row of
/// per-type switches. That is not laziness: push is sent by `notify-event` on
/// the server, which decides what to send from the job's own data and has no
/// per-category preference to read. Offering "booking pushes off, message
/// pushes on" would be four switches that quietly do nothing.
///
/// The one switch does something real - it deletes this device's token, which
/// is the only per-device control the backend actually exposes - and the
/// wording says exactly that.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final LocalPrefs _prefs = LocalPrefs.instance;

  /// The categories worth offering a switch for. `system` is omitted because
  /// nothing in SUGO currently produces one.
  static const List<NotificationCategory> _channels = <NotificationCategory>[
    NotificationCategory.booking,
    NotificationCategory.tracking,
    NotificationCategory.messages,
    NotificationCategory.service,
  ];

  static const String _pushChannel = 'push';

  final Map<String, bool> _values = <String, bool>{};
  bool _loading = true;
  bool _busy = false;

  String? get _uid => SupabaseService.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String? uid = _uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    for (final NotificationCategory c in _channels) {
      _values[c.name] = await _prefs.notificationEnabled(uid, c.name);
    }
    _values[_pushChannel] = await _prefs.notificationEnabled(uid, _pushChannel);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setChannel(NotificationCategory c, bool value) async {
    final String? uid = _uid;
    if (uid == null) return;
    setState(() => _values[c.name] = value);
    await _prefs.setNotificationEnabled(uid, c.name, value);
  }

  Future<void> _setPush(bool value) async {
    final String? uid = _uid;
    if (uid == null || _busy) return;

    setState(() {
      _busy = true;
      _values[_pushChannel] = value;
    });

    // The switch is the record of intent; the token is the effect. Saving
    // first means a failure to reach the server leaves the two disagreeing
    // for one session rather than silently reverting what the user chose.
    await _prefs.setNotificationEnabled(uid, _pushChannel, value);
    if (value) {
      await PushNotificationService.register();
    } else {
      await PushNotificationService.unregister();
    }

    if (!mounted) return;
    setState(() => _busy = false);
    UiFeedback.showSuccess(
      context,
      value
          ? 'Push notifications are on for this phone.'
          : 'This phone will stop receiving SUGO notifications.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const SugoAppBar(title: 'Notifications'),
      // A skeleton of the settings rows while they load, so the list does not
      // jump into place around a centred spinner.
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(AppSizes.screenPadding),
              child: SugoSkeletonList(count: 4, showAvatar: false),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.screenPadding,
                AppSizes.lg,
                AppSizes.screenPadding,
                AppSizes.xxl,
              ),
              children: <Widget>[
                SugoListGroup(
                  title: 'In the app',
                  children: <Widget>[
                    for (final NotificationCategory c in _channels)
                      SugoListTile(
                        icon: c.icon,
                        title: c.label,
                        subtitle: _describe(c),
                        showChevron: false,
                        trailing: Switch(
                          value: _values[c.name] ?? true,
                          onChanged: (bool v) => _setChannel(c, v),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSizes.md),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.xs,
                  ),
                  child: Text(
                    'These control what appears in your notification centre '
                    'and the badge on the bell.',
                    style: AppTextStyles.micro,
                  ),
                ),
                const SizedBox(height: AppSizes.xl),
                SugoListGroup(
                  title: 'On this phone',
                  children: <Widget>[
                    SugoListTile(
                      icon: Icons.notifications_active_rounded,
                      title: 'Push notifications',
                      subtitle:
                          'Booking updates and messages while SUGO is closed',
                      showChevron: false,
                      trailing: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            )
                          : Switch(
                              value: _values[_pushChannel] ?? true,
                              onChanged: _setPush,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.md),
                SugoCard(
                  elevation: SugoElevation.sm,
                  background: AppColors.primarySofter,
                  borderColor: AppColors.primarySoft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: Text(
                          'Turning this off removes this phone from SUGO\'s '
                          'notification list. Your other devices keep '
                          'receiving them. Android and iOS also have their own '
                          'notification permission for SUGO in system '
                          'settings.',
                          style: AppTextStyles.caption,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static String _describe(NotificationCategory c) => switch (c) {
    NotificationCategory.booking =>
      'Requests, acceptances and cancellations',
    NotificationCategory.tracking => 'Pickup progress and delays',
    NotificationCategory.messages => 'New messages from your technician',
    NotificationCategory.service => 'Work started, finished and rating asks',
    NotificationCategory.system => 'Announcements from SUGO',
  };
}
