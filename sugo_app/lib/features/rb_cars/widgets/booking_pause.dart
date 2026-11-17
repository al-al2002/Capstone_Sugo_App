import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';

/// The book-and-cancel cooldown on the client's side (2026-11-17).
///
/// The rule (on the server, `booking_cooldown_until`): a client who cancels 2
/// bookings within an hour - "Cancel request", or "Delete request" while a
/// technician is booked - waits 2 minutes before booking again. Every
/// booking reaches a real technician, and on an urgent job it buzzes their
/// phone, so booking and cancelling on repeat wastes their time.
///
/// The wording explains rather than scolds: an honest client who changed
/// their mind twice sees the same banner as a troll, and it should read as a
/// short wait, not an accusation.

/// "1:45" - minutes and seconds left, never negative.
String bookingPauseLabel(Duration left) {
  final Duration d = left.isNegative ? Duration.zero : left;
  final int seconds = (d.inMilliseconds / 1000).ceil();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Shown right after the cancel that started a pause, so the countdown on
/// the booking screen is not a surprise.
void showBookingPausedNotice(BuildContext context, DateTime until) {
  UiFeedback.showInfo(
    context,
    'You have cancelled 2 bookings within an hour, so booking is paused '
    'for ${bookingPauseLabel(until.difference(DateTime.now()))}.',
  );
}

/// The countdown on "Choose a technician" while booking is paused.
///
/// Ticks once a second and calls [onDone] once at zero, when booking opens
/// again. The server's own clock decides; this only shows it.
class BookingPauseBanner extends StatefulWidget {
  const BookingPauseBanner({
    super.key,
    required this.until,
    required this.onDone,
    this.clock,
  });

  final DateTime until;
  final VoidCallback onDone;

  /// For tests: what "now" is.
  final DateTime Function()? clock;

  @override
  State<BookingPauseBanner> createState() => _BookingPauseBannerState();
}

class _BookingPauseBannerState extends State<BookingPauseBanner> {
  Timer? _ticker;
  bool _doneSent = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  Duration get _left => widget.until.difference(_now());

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(BookingPauseBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.until != widget.until) {
      _doneSent = false;
      _start();
    }
  }

  void _start() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_left <= Duration.zero) _finish();
    });
  }

  void _finish() {
    _ticker?.cancel();
    if (_doneSent) return;
    _doneSent = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String left = bookingPauseLabel(_left);

    return Semantics(
      liveRegion: true,
      label: 'Booking paused. You can book again in $left.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSizes.md),
        decoration: BoxDecoration(
          color: AppColors.accentSofter,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          border: Border.all(color: AppColors.accentSoft),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.timer_outlined,
                size: 20,
                color: AppColors.accentDark,
              ),
            ),
            const SizedBox(width: AppSizes.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'You can book again in $left',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'You cancelled 2 bookings within an hour. Each booking '
                    'alerts a real technician, so booking pauses for 2 '
                    'minutes. Your post and these matches are kept.',
                    style: AppTextStyles.micro.copyWith(height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
