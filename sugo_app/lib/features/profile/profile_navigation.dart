import 'package:flutter/material.dart';

import '../rb_cars/screens/technician_detail_screen.dart';
import 'screens/client_profile_screen.dart';

/// Opens the right profile for a person, whichever role they have.
///
/// ## Why one function
///
/// Names now appear in three places - the bookings list, the technician's jobs,
/// and every Community byline - and each is a person of one of two kinds. If
/// each call site chose the screen itself, a fourth call site would eventually
/// open a technician's name on the client screen, or vice versa. Deciding here
/// means the rule is written once.
///
/// A technician opens the full technician profile (reviews, past work,
/// booking). A client opens the public client profile. Anyone else - an admin,
/// or an account whose role is unknown - opens nothing rather than a screen
/// that would fail to load.
Future<void> openPersonProfile(
  BuildContext context, {
  required String userId,
  required String? role,
  String? name,
  String? avatarUrl,
}) async {
  if (userId.isEmpty) return;

  final Widget? screen = switch (role) {
    'technician' => TechnicianDetailScreen(technicianId: userId),
    'client' => ClientProfileScreen(
      clientId: userId,
      initialName: name,
      initialAvatarUrl: avatarUrl,
    ),
    _ => null,
  };

  if (screen == null) return;

  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => screen),
  );
}
