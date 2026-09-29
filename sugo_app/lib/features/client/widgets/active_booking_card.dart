import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_route_line.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../../core/widgets/sugo_status_badge.dart';
import '../../bookings/models/booking_route.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_technician.dart';
import '../../tracking/models/job_tracking.dart';

/// What the active-booking card is currently saying.
///
/// The card has to cover every state between "just posted" and "being
/// repaired", and they need different words and different buttons. Deriving
/// the state once, here, is what stops the card growing a nest of `if
/// (job.status == ... && technician != null && ...)` inside its build method.
enum ActiveBookingState {
  /// Posted; the engine is still ranking technicians.
  finding,

  /// Matches are ready and the client has to choose one.
  choosing,

  /// One technician has been asked and has not answered yet.
  awaiting,

  /// Accepted. Work has not started (or is not tracked).
  confirmed,

  /// A pickup job with a live tracking row.
  travelling,

  /// Work underway.
  inProgress;

  /// Where this state sits on the booking's route. Each state maps to exactly
  /// one position, so the van can only ever be where the data says.
  SugoRoutePosition get routePosition => switch (this) {
    finding => BookingRoute.finding,
    choosing => BookingRoute.choosing,
    awaiting => BookingRoute.awaiting,
    confirmed => BookingRoute.booked,
    travelling || inProgress => BookingRoute.underway,
  };
}

/// The one booking the client most likely opened the app for.
///
/// ## Why this is a hero and not a list row
///
/// The brief's rule: "do not force users to navigate through multiple screens
/// to find their active booking". If there is a technician on the way, that is
/// the single most important fact on the phone, and it earns the first card and
/// the only two actions that matter - track them, or message them.
///
/// ## The Dispatch card (2026-09-29)
///
/// It used to be the one navy card on a white page. It is now a white card
/// built around the redesign's signature: the booking drawn as a route -
/// Posted, Matched, Booked, Fixed - with the logo's van where the job is.
/// A client sees in one glance how far along they are and what comes next,
/// which a status word alone ("Booking confirmed") never said.
///
/// The route is honest by construction: [ActiveBookingState.routePosition]
/// maps each state the dashboard derives from `jobs.status` and the tracking
/// row onto one fixed position. Nothing animates towards the next stop until
/// the data says the job reached it.
///
/// The reference code ("#A3F2B1") left the card: nobody reads it out on the
/// home screen, and it sat in the most prominent line. It is on the booking.
class ActiveBookingCard extends StatelessWidget {
  const ActiveBookingCard({
    super.key,
    required this.job,
    required this.state,
    this.technician,
    this.tracking,
    required this.onPrimary,
    this.onMessage,
    this.onCancel,
    this.moreCount = 0,
    this.onSeeAll,
  });

  final Job job;
  final ActiveBookingState state;
  final JobTechnician? technician;
  final JobTracking? tracking;

  /// Track, choose, or view - whichever [state] calls for.
  final VoidCallback onPrimary;

  /// Null before a technician has accepted: chat does not open until then, and
  /// offering it would promise something the database refuses.
  final VoidCallback? onMessage;

  /// Withdraw the request, or delete the job while nobody has taken it.
  final VoidCallback? onCancel;

  /// Other active bookings not shown here.
  final int moreCount;
  final VoidCallback? onSeeAll;

  String get _statusLabel => switch (state) {
    ActiveBookingState.finding => 'Finding technicians',
    ActiveBookingState.choosing => 'Your turn to choose',
    ActiveBookingState.awaiting => 'Waiting for an answer',
    ActiveBookingState.confirmed => 'Confirmed',
    ActiveBookingState.travelling => tracking?.stage.label ?? 'On the way',
    ActiveBookingState.inProgress => 'Repair in progress',
  };

  IconData get _statusIcon => switch (state) {
    ActiveBookingState.finding => Icons.radar_rounded,
    ActiveBookingState.choosing => Icons.touch_app_rounded,
    ActiveBookingState.awaiting => Icons.hourglass_top_rounded,
    ActiveBookingState.confirmed => Icons.check_circle_rounded,
    ActiveBookingState.travelling =>
      tracking?.stage.icon ?? Icons.directions_car_rounded,
    ActiveBookingState.inProgress => Icons.build_rounded,
  };

  SugoTone get _tone => switch (state) {
    ActiveBookingState.choosing => SugoTone.brand,
    ActiveBookingState.awaiting => SugoTone.warning,
    ActiveBookingState.confirmed => SugoTone.success,
    _ => SugoTone.info,
  };

  /// Pulses only while something is actually moving or being worked on.
  bool get _live =>
      state == ActiveBookingState.travelling ||
      state == ActiveBookingState.inProgress ||
      state == ActiveBookingState.finding;

  String get _primaryLabel => switch (state) {
    ActiveBookingState.finding => 'View request',
    ActiveBookingState.choosing => 'Choose technician',
    ActiveBookingState.awaiting => 'View request',
    ActiveBookingState.travelling => 'Track technician',
    _ => 'View booking',
  };

  IconData get _primaryIcon => switch (state) {
    ActiveBookingState.travelling => Icons.near_me_rounded,
    ActiveBookingState.choosing => Icons.groups_rounded,
    _ => Icons.receipt_long_rounded,
  };

  /// The one line of detail under the technician: an ETA while travelling, the
  /// wait while a request is out, the schedule otherwise.
  String? get _detail {
    final JobTracking? t = tracking;
    if (state == ActiveBookingState.travelling && t != null) {
      final DateTime? eta = t.projectedArrivalAt;
      if (t.isDelayed) {
        return 'Running ${t.delayLabel ?? 'late'} · ${t.freshnessLabel}';
      }
      if (eta != null && eta.isAfter(DateTime.now())) {
        final int minutes = eta.difference(DateTime.now()).inMinutes;
        return 'Arrives ${minutes < 1 ? 'any moment' : 'in about $minutes min'}'
            ' · ${t.freshnessLabel}';
      }
      return t.freshnessLabel;
    }
    if (state == ActiveBookingState.awaiting) {
      return technician?.waitingLabel ?? 'Asked just now';
    }
    final DateTime? when = job.preferredSchedule;
    if (when != null) return 'Scheduled ${Fmt.dateTime(when)}';
    if (job.servicePath != null) return job.servicePath!.label;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final JobTechnician? who = technician;
    final String? detail = _detail;

    return SugoCard(
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The status pill takes whatever the label leaves and ellipsises
          // inside it: on a 320dp phone at 1.3x text the old header squeezed
          // its label to one letter per line.
          Row(
            children: <Widget>[
              const Text('Your booking', style: AppTextStyles.overline),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SugoStatusBadge(
                    label: _statusLabel,
                    icon: _statusIcon,
                    tone: _tone,
                    pulsing: _live,
                    dense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            job.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: AppSizes.lg),
          SugoRouteLine(
            stops: BookingRoute.stops,
            position: state.routePosition,
          ),
          if (who != null || detail != null) ...<Widget>[
            const SizedBox(height: AppSizes.lg),
            Row(
              children: <Widget>[
                if (who != null) ...<Widget>[
                  SugoAvatar(
                    name: who.displayName,
                    imageUrl: who.avatarUrl,
                    size: AppSizes.avatarSm,
                  ),
                  const SizedBox(width: AppSizes.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (who != null)
                        Text(
                          who.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleSmall,
                        ),
                      if (detail != null)
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSizes.lg),
          _Actions(
            primary: SugoButton(
              label: _primaryLabel,
              icon: _primaryIcon,
              size: SugoButtonSize.medium,
              onPressed: onPrimary,
            ),
            onMessage: onMessage,
          ),
          if (onCancel != null || (moreCount > 0 && onSeeAll != null))
            Padding(
              padding: const EdgeInsets.only(top: AppSizes.xs),
              // A Wrap: on a small phone at large text the two links do not
              // fit on one line, and a Row with a Spacer overflowed.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: <Widget>[
                  if (onCancel != null)
                    TextButton(
                      onPressed: onCancel,
                      // Destructive, so the error ink - never the blue that
                      // means "go somewhere".
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      child: Text(
                        state == ActiveBookingState.awaiting
                            ? 'Cancel request'
                            : 'Delete request',
                      ),
                    ),
                  if (moreCount > 0 && onSeeAll != null)
                    TextButton(
                      onPressed: onSeeAll,
                      child: Text(
                        '$moreCount more active '
                        '${moreCount == 1 ? 'booking' : 'bookings'}',
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The main action and Message: side by side on a normal phone, stacked on a
/// narrow one, where Message beside it squeezed "Track technician" down to
/// "Track t…".
///
/// Side by side, Message takes exactly the width of its label and the main
/// action takes the rest - never a fixed split, which cut "Message" short.
class _Actions extends StatelessWidget {
  const _Actions({required this.primary, this.onMessage});

  /// Full width by default, which suits both arrangements.
  final Widget primary;
  final VoidCallback? onMessage;

  /// Below this, the pair stacks. Two medium buttons with their labels need
  /// about this much before the main one starts to ellipsise.
  static const double _sideBySide = 300;

  Widget _message({required bool expand}) => SugoButton(
    label: 'Message',
    icon: Icons.chat_bubble_outline_rounded,
    variant: SugoButtonVariant.outlined,
    size: SugoButtonSize.medium,
    expand: expand,
    onPressed: onMessage,
  );

  @override
  Widget build(BuildContext context) {
    if (onMessage == null) return primary;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < _sideBySide) {
          return Column(
            children: <Widget>[
              primary,
              const SizedBox(height: AppSizes.sm),
              _message(expand: true),
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: primary),
            const SizedBox(width: AppSizes.sm),
            _message(expand: false),
          ],
        );
      },
    );
  }
}

/// A placeholder in the card's shape, so the home screen does not jump when
/// the jobs land.
class ActiveBookingSkeleton extends StatelessWidget {
  const ActiveBookingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SugoCard(
      padding: EdgeInsets.all(AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SugoSkeleton(width: 90, height: 12),
              Spacer(),
              SugoSkeleton(width: 110, height: 22, radius: 999),
            ],
          ),
          SizedBox(height: AppSizes.md),
          SugoSkeleton(width: 200, height: 16),
          SizedBox(height: AppSizes.xl),
          SugoSkeleton(height: 10, radius: 999),
          SizedBox(height: AppSizes.xl),
          SugoSkeleton(height: AppSizes.socialButtonHeight, radius: 12),
        ],
      ),
    );
  }
}
