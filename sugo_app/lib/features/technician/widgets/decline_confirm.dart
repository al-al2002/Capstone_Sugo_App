import 'package:flutter/material.dart';

import '../../../core/widgets/sugo_dialog.dart';

/// Asks a technician to confirm declining an offer, and returns whether they
/// did (2026-11-23, at the user's request: "are you sure you want to decline
/// this?").
///
/// A decline cannot be undone and the client is told at once, so a stray tap
/// must not send it. The title is the question, as every SUGO confirmation
/// is ("Decline this request?", not "Are you sure?"); "Keep it" is the easy
/// way out, and a tap outside counts as keeping it.
Future<bool> confirmDeclineOffer(BuildContext context) {
  return showSugoConfirmDialog(
    context: context,
    title: 'Decline this request?',
    message:
        'Are you sure you want to decline it? The client is told right away '
        'and can choose another technician. You cannot undo this.',
    confirmLabel: 'Decline',
    cancelLabel: 'Keep it',
    destructive: true,
    icon: Icons.do_not_disturb_on_rounded,
  );
}
