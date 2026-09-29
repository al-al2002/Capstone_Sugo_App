import 'package:flutter/material.dart';

import '../../../core/widgets/sugo_status_badge.dart';

/// Which filter tab a notification belongs to.
///
/// The brief lists Booking, Tracking, Messages, Payment, Service and System.
/// SUGO has no payment records and sends no system broadcasts, so those two
/// never produce an item - and the notification centre only shows a filter
/// for a category that has something in it, rather than offering tabs that
/// are always empty.
enum NotificationCategory {
  booking('Bookings', Icons.event_note_rounded),
  tracking('Tracking', Icons.near_me_rounded),
  messages('Messages', Icons.chat_bubble_rounded),
  service('Service', Icons.build_circle_rounded),
  system('System', Icons.info_rounded);

  const NotificationCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// What tapping a notification should open.
enum NotificationAction {
  /// The booking detail (or the shortlist, for a job still choosing).
  openJob,

  /// The chat thread for the job.
  openChat,

  /// Live tracking for a pickup job.
  openTracking,

  /// The technician's own dashboard, where incoming requests live.
  ///
  /// A request they have not accepted has no booking screen to open: the job
  /// row is hidden by `jobs_technician_select_assigned` until they take it.
  /// The offer card on the dashboard is the only place it exists, so that is
  /// where the notification goes.
  openOffers,
}

/// One row in the notification centre.
///
/// ## Derived, not stored
///
/// SUGO keeps no table of notifications - push messages are sent and
/// forgotten - and the user chose on 2026-09-22 not to add one. Every item
/// here is therefore *computed* from data that already exists: a job's status,
/// a match request, a tracking row, an unread chat. `NotificationFeedService`
/// does the computing.
///
/// Two consequences worth knowing:
///
/// * **Read state for chat is the server's**, because a message has a
///   `read_at`. Opening the thread clears it everywhere.
/// * **Read state for everything else is this device's**, kept in
///   `LocalPrefs` by [id]. That is why each id encodes the state it describes
///   (`job:<id>:confirmed`): the same job moving to a new status is a new
///   notification, unread again.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.at,
    required this.icon,
    required this.tone,
    required this.action,
    this.jobId,
    this.unread = false,
    this.counterpartName,
    this.counterpartAvatarUrl,
  });

  final String id;
  final NotificationCategory category;
  final String title;
  final String body;

  /// When it happened, or - for a status change the database does not
  /// timestamp - when this device first saw it.
  final DateTime at;

  final IconData icon;
  final SugoTone tone;
  final NotificationAction action;
  final String? jobId;
  final bool unread;

  /// For chat notifications: who wrote.
  final String? counterpartName;
  final String? counterpartAvatarUrl;

  AppNotification copyWith({bool? unread}) => AppNotification(
    id: id,
    category: category,
    title: title,
    body: body,
    at: at,
    icon: icon,
    tone: tone,
    action: action,
    jobId: jobId,
    unread: unread ?? this.unread,
    counterpartName: counterpartName,
    counterpartAvatarUrl: counterpartAvatarUrl,
  );
}
