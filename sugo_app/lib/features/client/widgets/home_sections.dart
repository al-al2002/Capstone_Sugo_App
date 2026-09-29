import 'package:flutter/material.dart';

import '../../../core/widgets/sugo_status_badge.dart';
import '../../rb_cars/models/job_enums.dart';

/// The status pill for a job, in the shared badge component.
///
/// One place decides what a status looks like, so the home screen, the
/// bookings list and the booking detail can never disagree about it - and
/// every status carries an icon as well as a colour.
SugoStatusBadge jobStatusBadge(JobStatus status, {bool dense = false}) {
  final (String label, IconData icon, SugoTone tone, bool pulse) =
      switch (status) {
        JobStatus.pending => (
          'Finding technicians',
          Icons.radar_rounded,
          SugoTone.info,
          true,
        ),
        JobStatus.matched => (
          'Choose technician',
          Icons.workspace_premium_rounded,
          SugoTone.brand,
          false,
        ),
        JobStatus.confirmed => (
          'Confirmed',
          Icons.check_circle_rounded,
          SugoTone.success,
          false,
        ),
        JobStatus.inProgress => (
          'In progress',
          Icons.build_rounded,
          SugoTone.accent,
          true,
        ),
        JobStatus.completed => (
          'Completed',
          Icons.verified_rounded,
          SugoTone.success,
          false,
        ),
        JobStatus.cancelled => (
          'Cancelled',
          Icons.cancel_rounded,
          SugoTone.neutral,
          false,
        ),
      };

  return SugoStatusBadge(
    label: label,
    icon: icon,
    tone: tone,
    pulsing: pulse,
    dense: dense,
  );
}
