import 'package:flutter/foundation.dart';

import '../../../core/services/local_prefs.dart';
import '../models/job_tracking.dart';

/// Decides when the client gets the "running late" pop-up: once per trip.
///
/// ## Why a pop-up at all, when there is a banner and a push
///
/// The push reaches a phone in a pocket, and the banner sits on the tracking
/// screen. Neither reaches a client who has the app open on some other screen:
/// Android does not show a push while its app is in the foreground, and the
/// banner is only where they are not looking. A delay is the one tracking
/// event worth interrupting for, because it changes their plans. "Leave the
/// gate open a bit longer" is decided now, not when they next check.
///
/// ## Why once per trip
///
/// The ETA is resampled every couple of minutes, and a late trip stays late on
/// every sample after the first. A dialog on each one would be a nag, and
/// after the second one people stop reading dialogs. The server makes the same
/// choice for the push (`delay_notified_at`, announced once per leg).
///
/// A trip is identified by its promise, `expected_arrival_at`. The server
/// writes it once per leg and clears it on a stage change, so a new leg is a
/// new key and gets its own alert. The keys are kept on the device
/// ([LocalPrefs]), so reopening the app does not repeat the alert either.
///
/// ## Why the claim is in memory as well
///
/// The home card and the tracking screen can watch the same trip at the same
/// moment. Both see the delay on the same realtime update, and the one that
/// claims first shows the dialog. The in-memory set answers at once, before
/// either has waited on storage, so the second one always loses.
class DelayAlerts {
  const DelayAlerts._();

  static final Set<String> _claimed = <String>{};

  /// The trip this delay belongs to, or null when there is no promise to be
  /// late against yet.
  static String? keyFor(JobTracking tracking) {
    final DateTime? promise = tracking.expectedArrivalAt;
    if (promise == null) return null;
    return '${tracking.jobId}@${promise.toUtc().toIso8601String()}';
  }

  /// Whether [tracking] is a late trip worth interrupting for.
  ///
  /// Only while someone is travelling ([TrackingStage.showsMap]). Once the
  /// technician has arrived the delay is history, and the stage change has
  /// already cleared it on the server anyway.
  static bool isAlertable(JobTracking tracking) =>
      tracking.isDelayed && tracking.stage.showsMap && keyFor(tracking) != null;

  /// Whether the CLIENT's trip to the workshop is late - the technician's
  /// alert, on the one leg where the client travels (20260929000001).
  ///
  /// Kept apart from [isAlertable] on purpose. Both look at the same delay
  /// columns, and the client's own tracking screen asks [isAlertable]; if the
  /// two were one test, a client running late would be told "your technician
  /// is running late" about themselves.
  static bool isClientTripAlertable(JobTracking tracking) =>
      tracking.isDelayed && tracking.clientOnTheWay && keyFor(tracking) != null;

  /// True exactly once per trip: for the first caller to see it late.
  ///
  /// [clientTrip] asks about the client's trip instead of the technician's.
  static Future<bool> claim(
    JobTracking tracking, {
    bool clientTrip = false,
    LocalPrefs? prefs,
  }) async {
    final bool alertable = clientTrip
        ? isClientTripAlertable(tracking)
        : isAlertable(tracking);
    if (!alertable) return false;
    final String key = keyFor(tracking)!;
    if (!_claimed.add(key)) return false;

    final LocalPrefs store = prefs ?? LocalPrefs.instance;
    if ((await store.shownDelayAlerts()).contains(key)) return false;
    await store.markDelayAlertShown(key);
    return true;
  }

  /// Tests only: forgets this run's claims.
  @visibleForTesting
  static void debugReset() => _claimed.clear();
}
