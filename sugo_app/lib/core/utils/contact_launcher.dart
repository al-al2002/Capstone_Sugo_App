import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ui_feedback.dart';

/// Opens the phone dialler and the maps app.
///
/// ## Why the dialler and not an in-app call
///
/// SUGO has no voice infrastructure, and a client who needs their technician
/// at the gate needs the phone, not a feature. Handing the number to the
/// platform dialler is the honest version: the user sees the number before it
/// is dialled and can cancel, and no call is placed without a second tap.
///
/// Numbers are only ever passed here once the server has released them - the
/// `technician-directory` function withholds `phone` until the caller has a
/// confirmed booking with that technician. This helper does not decide who may
/// call; it only dials what it is given.
class ContactLauncher {
  const ContactLauncher._();

  /// Opens the dialler with [phone] filled in.
  ///
  /// Returns false and explains itself if the device has no dialler - a
  /// tablet, an emulator, the web build - rather than failing silently.
  static Future<bool> call(BuildContext context, String? phone) async {
    final String number = (phone ?? '').replaceAll(RegExp(r'[^\d+]'), '');
    if (number.isEmpty) {
      UiFeedback.showInfo(
        context,
        'No phone number has been shared for this booking yet.',
      );
      return false;
    }

    final Uri uri = Uri(scheme: 'tel', path: number);
    try {
      final bool launched = await launchUrl(uri);
      if (!launched && context.mounted) {
        UiFeedback.showError(
          context,
          'This device cannot place calls. The number is $number.',
        );
      }
      return launched;
    } catch (_) {
      if (context.mounted) {
        UiFeedback.showError(
          context,
          'Could not open the dialler. The number is $number.',
        );
      }
      return false;
    }
  }

  /// Opens any URI - a `mailto:` for support, a web link - and reports
  /// whether the platform could handle it, so the caller can offer a fallback
  /// (printing the address rather than swallowing the failure).
  static Future<bool> openUri(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Opens a coordinate in whatever maps app the platform has.
  ///
  /// `geo:` is the Android standard and lets the user pick their own app;
  /// iOS and the web fall back to a Google Maps URL, which every platform can
  /// open in a browser if nothing else is installed.
  static Future<bool> directions(
    BuildContext context, {
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    final String coords = '$latitude,$longitude';
    final Uri geo = Uri.parse(
      'geo:$coords?q=${Uri.encodeComponent('$coords${label == null ? '' : '($label)'}')}',
    );
    final Uri web = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$coords',
    );

    try {
      if (await canLaunchUrl(geo)) {
        return launchUrl(geo);
      }
      return await launchUrl(web, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        UiFeedback.showError(context, 'Could not open a maps app.');
      }
      return false;
    }
  }
}
