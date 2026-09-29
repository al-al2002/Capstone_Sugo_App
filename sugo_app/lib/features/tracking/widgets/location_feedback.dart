import 'package:flutter/material.dart';

import '../../../core/utils/ui_feedback.dart';
import '../services/tracking_service.dart';

/// Says why location could not be switched on, with a "Settings" button when
/// there is a settings page that fixes it.
///
/// Every trip screen ends up here after [TrackingService.prepareLocation] has
/// already done what it could - asked for permission, shown Android's "Turn
/// on location?" - so what is left needs the person, and the button takes
/// them to the one place that can help.
void showLocationBlocked(BuildContext context, LocationReadiness readiness) {
  final bool canFix = readiness.fix != LocationFix.none;
  UiFeedback.showError(
    context,
    readiness.reason ?? 'Location is not available on this phone.',
    actionLabel: canFix ? 'Settings' : null,
    onAction: canFix ? () => readiness.openFix() : null,
  );
}
