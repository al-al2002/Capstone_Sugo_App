import 'package:flutter/foundation.dart';

/// A tapped push notification, waiting for a screen to act on it.
///
/// ## Why a hand-off rather than navigating straight away
///
/// A tap can arrive before there is anywhere to go. Opening the app from a
/// notification starts it cold: splash, session restore, the auth gate
/// deciding between dashboards - and only then is there a screen that knows
/// who is signed in and can open "this job" or "this chat" for them.
///
/// So the tap is parked here, and each dashboard takes it when it is on
/// screen: straight away if the app was already running, or on its first
/// frame after a cold start. Nothing is lost in between, and nothing tries to
/// push a route onto a navigator that is still deciding what it shows.
class NotificationTap {
  const NotificationTap({required this.type, this.jobId, this.name});

  factory NotificationTap.fromData(Map<String, dynamic> data) {
    String? text(String key) {
      final Object? value = data[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return NotificationTap(
      type: text('type') ?? 'unknown',
      jobId: text('job_id'),
      name: text('name'),
    );
  }

  /// What happened: `message`, `stage`, `return_method`, `booked`,
  /// `completed` or `job_delay` - the `data.type` the server sent.
  final String type;

  /// The job it is about, when there is one.
  final String? jobId;

  /// The other person's name, sent with messages for the chat's title.
  final String? name;
}

class NotificationRouter {
  const NotificationRouter._();

  /// The tap not yet acted on. Dashboards listen to this.
  static final ValueNotifier<NotificationTap?> pending =
      ValueNotifier<NotificationTap?>(null);

  static void deliver(Map<String, dynamic> data) {
    pending.value = NotificationTap.fromData(data);
  }

  /// Takes the pending tap, so exactly one screen acts on it.
  static NotificationTap? take() {
    final NotificationTap? tap = pending.value;
    pending.value = null;
    return tap;
  }
}
