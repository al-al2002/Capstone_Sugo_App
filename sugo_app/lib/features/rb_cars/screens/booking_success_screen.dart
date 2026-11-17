import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_route_line.dart';
import '../../../core/widgets/sugo_timeline.dart';
import '../../bookings/models/booking_route.dart';
import '../../bookings/screens/bookings_list_view.dart';
import '../../bookings/screens/job_detail_screen.dart';
import '../models/job.dart';
import '../models/job_enums.dart';
import '../models/labor_price_catalog.dart';
import '../models/match_result.dart';
import '../models/technician.dart';
import '../models/job_price.dart';
import '../widgets/score_indicator.dart';
import '../widgets/urgent_countdown.dart';

/// Shown the moment a client picks their technician.
///
/// ## Why it says "request sent" and not "booking confirmed"
///
/// The brief asks for a "Booking Confirmed" screen. At this point in SUGO the
/// booking is *not* confirmed: `selectTechnician` writes the match as
/// `offered`, and the technician has to accept before `jobs.status` becomes
/// `confirmed`. A screen that announced a confirmation here would be a lie
/// with a tick on it - and the first thing the client would do is turn up
/// expecting somebody.
///
/// So it celebrates the thing that did happen, gives the reference, and is
/// explicit about the one step still outstanding. The timeline shows exactly
/// where the booking stands, which is the honest version of the same
/// reassurance - and since the Dispatch redesign the summary carries the
/// booking's route too, with the van between "Matched" and "Booked".
class BookingSuccessScreen extends StatelessWidget {
  const BookingSuccessScreen({
    super.key,
    required this.job,
    required this.technician,
    this.match,
  });

  final Job job;

  /// The technician the request went to. Null only if the snapshot was
  /// missing, in which case the screen still works without the name.
  final Technician? technician;
  final MatchResult? match;

  /// Opens this screen in place of the whole booking flow.
  ///
  /// Everything above home goes, not just the screen that booked. Arriving
  /// from a new post, the four posting steps are still on the stack under the
  /// shortlist; replacing only the shortlist left them there, so Back from
  /// this screen - or from "View booking" after it - walked into "post a
  /// task" again. Once the request is sent the flow is over, so home is the
  /// only thing left underneath.
  static Future<void> show(
    BuildContext context, {
    required Job job,
    Technician? technician,
    MatchResult? match,
  }) {
    return Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => BookingSuccessScreen(
          job: job,
          technician: technician,
          match: match,
        ),
      ),
      (Route<dynamic> route) => route.isFirst,
    );
  }

  String get _firstName =>
      technician?.displayName.split(' ').first ?? 'your technician';

  /// [_firstName] where it opens a sentence: "Your technician", not "your".
  String get _firstNameStart {
    final String name = _firstName;
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }

  LaborPrice? get _laborPrice => LaborPriceCatalog.forJob(
    deviceType: job.deviceType,
    symptomCode: job.problemSymptom,
  );

  /// A shop repair's delivery fee was worked out and saved by the server
  /// when the request was sent (2026-11-16); it is read back, not redone.
  bool get _isShopRepair => job.servicePath == ServicePath.pickup;

  double? get _distanceKm => _isShopRepair
      ? job.distanceKm
      : job.servicePath == ServicePath.homeService
      ? technician?.distanceKm
      : null;

  // The same rule as everywhere else - it used to be a copy of it.
  int? get _travelFee => _isShopRepair
      ? job.deliveryFee
      : LaborPriceCatalog.travelFee(_distanceKm);

  String get _feeLabel => !_isShopRepair
      ? 'Travel fee'
      : job.deliveryOption == DeliveryOption.self
      ? 'Delivery fee - bring it myself'
      : 'Pickup and delivery fee';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.screenPadding,
                  AppSizes.xl,
                  AppSizes.screenPadding,
                  AppSizes.xl,
                ),
                children: <Widget>[
                  const _SuccessMark(),
                  const SizedBox(height: AppSizes.xl),
                  Text(
                    'Request sent',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.displayLarge,
                  ),
                  const SizedBox(height: AppSizes.sm),
                  Text(
                    '$_firstNameStart has your job. You will be told the '
                    'moment they accept it.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.subtitle,
                  ),
                  // Urgent: they have five minutes, and what happens if not
                  // (2026-11-17).
                  if (job.urgency == Urgency.needToday) ...<Widget>[
                    const SizedBox(height: AppSizes.lg),
                    _UrgentSentCard(name: _firstNameStart),
                  ],
                  const SizedBox(height: AppSizes.xl),
                  _SummaryCard(job: job, technician: technician, match: match),
                  if (match != null) ...<Widget>[
                    const SizedBox(height: AppSizes.lg),
                    _MatchAcceptanceCard(match: match!),
                  ],
                  if (_laborPrice != null) ...<Widget>[
                    const SizedBox(height: AppSizes.lg),
                    _PriceEstimateCard(
                      labor: _laborPrice!,
                      distanceKm: _distanceKm,
                      travelFee: _travelFee,
                      feeLabel: _feeLabel,
                      pickupAndDelivery:
                          _isShopRepair &&
                          job.deliveryOption == DeliveryOption.delivery,
                      urgent: job.urgency == Urgency.needToday,
                    ),
                  ],
                  const SizedBox(height: AppSizes.lg),
                  SugoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SectionHeader(title: 'What happens next'),
                        const SizedBox(height: AppSizes.lg),
                        SugoTimeline(
                          compact: true,
                          steps: <SugoTimelineStep>[
                            const SugoTimelineStep(
                              title: 'Request sent',
                              state: SugoStepState.done,
                            ),
                            SugoTimelineStep(
                              title: '$_firstNameStart accepts',
                              state: SugoStepState.current,
                              icon: Icons.hourglass_top_rounded,
                              subtitle:
                                  'Usually within a couple of hours. You can '
                                  'take the request back any time before they '
                                  'answer.',
                            ),
                            const SugoTimelineStep(
                              title: 'Chat opens',
                              state: SugoStepState.upcoming,
                              icon: Icons.chat_bubble_rounded,
                              subtitle:
                                  'Agree a time and share photos or landmarks.',
                            ),
                            const SugoTimelineStep(
                              title: 'Repair day',
                              state: SugoStepState.upcoming,
                              icon: Icons.build_rounded,
                              subtitle:
                                  'Track a workshop pickup live, or wait for '
                                  'them at your address.',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                boxShadow: AppElevation.navBar,
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSizes.screenPadding,
                AppSizes.md,
                AppSizes.screenPadding,
                AppSizes.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SugoButton(
                    label: 'View booking',
                    icon: Icons.receipt_long_rounded,
                    onPressed: () {
                      // Replaces this screen rather than stacking on it: the
                      // success screen is a moment, not a place to come back
                      // to, and Back from the booking should reach the
                      // dashboard.
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => JobDetailScreen(
                            job: job,
                            role: BookingsRole.client,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSizes.sm),
                  SugoButton(
                    label: 'Back to home',
                    variant: SugoButtonVariant.ghost,
                    size: SugoButtonSize.medium,
                    onPressed: () => Navigator.of(
                      context,
                    ).popUntil((Route<void> route) => route.isFirst),
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

class _PriceEstimateCard extends StatelessWidget {
  const _PriceEstimateCard({
    required this.labor,
    required this.distanceKm,
    required this.travelFee,
    this.feeLabel = 'Travel fee',
    this.urgent = false,
    this.pickupAndDelivery = false,
  });

  /// Two trips: printed as "Pickup trip" and "Delivery trip" (2026-11-17).
  final bool pickupAndDelivery;

  final LaborPrice labor;
  final double? distanceKm;
  final int? travelFee;

  /// Posted as Urgent: 20% of the labor on top (2026-11-17).
  final bool urgent;

  /// "Travel fee" for a home visit; the delivery wording for a shop repair.
  final String feeLabel;

  @override
  Widget build(BuildContext context) {
    final bool hasTravel = travelFee != null;
    return SugoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Price'),
          const SizedBox(height: AppSizes.md),
          _PriceRow(label: 'Labor fee', value: labor.fee),
          if (urgent) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            _PriceRow(
              label: 'Urgent fee (20%)',
              value: LaborPriceCatalog.urgentFee(labor) == null
                  ? '+20% of labor'
                  : '₱${LaborPriceCatalog.urgentFee(labor)}',
            ),
          ],
          if (hasTravel) ...<Widget>[
            for (final ({String label, int amount}) line in JobPrice.feeLines(
              label: feeLabel,
              km: distanceKm,
              fee: travelFee!,
              pickupAndDelivery: pickupAndDelivery,
            )) ...<Widget>[
              const SizedBox(height: AppSizes.sm),
              _PriceRow(label: line.label, value: '₱${line.amount}'),
            ],
            const SizedBox(height: AppSizes.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSizes.sm),
            _PriceRow(
              label: 'Estimated total',
              // The shared rule, urgent fee included - this used to be a
              // local copy of it.
              value: LaborPriceCatalog.estimatedTotal(
                labor: labor,
                travelFee: travelFee!,
                urgentFee: urgent ? LaborPriceCatalog.urgentFee(labor) ?? 0 : 0,
              ),
              bold: true,
            ),
          ],
          const SizedBox(height: AppSizes.sm),
          const Text(
            'Estimate only. Parts and complex repairs may cost extra.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
      color: AppColors.textPrimary,
    );
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}

/// The tick. Scales in once, with the one curve allowed to overshoot.
class _SuccessMark extends StatefulWidget {
  const _SuccessMark();

  @override
  State<_SuccessMark> createState() => _SuccessMarkState();
}

class _SuccessMarkState extends State<_SuccessMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.slow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> scale = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.playful,
    );

    return Center(
      child: ScaleTransition(
        scale: scale,
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppColors.successSoft,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 38,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchAcceptanceCard extends StatelessWidget {
  const _MatchAcceptanceCard({required this.match});

  final MatchResult match;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Match quality', style: AppTextStyles.overline),
          const SizedBox(height: AppSizes.md),
          ScoreIndicator(
            label: 'Match',
            percent: match.suitabilityPercent,
            qualifier: suitabilityQualifier(match.suitabilityPercent),
          ),
          const SizedBox(height: AppSizes.sm),
          ScoreIndicator(
            label: 'Acceptance',
            percent: match.acceptancePercent,
            qualifier: acceptanceQualifier(match.acceptancePercent),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.job,
    required this.technician,
    required this.match,
  });

  final Job job;
  final Technician? technician;
  final MatchResult? match;

  @override
  Widget build(BuildContext context) {
    final Technician? tech = technician;

    return SugoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text('Booking', style: AppTextStyles.overline),
              ),
              Text(
                job.reference,
                style: AppTextStyles.titleSmall.copyWith(
                  color: AppColors.primary,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          // Where the booking stands, drawn the way the home card and the
          // booking draw it: matched, and on the way to "Booked" - the van
          // sits between them because the technician has not answered yet.
          const SizedBox(height: AppSizes.lg),
          const SugoRouteLine(
            stops: BookingRoute.stops,
            position: BookingRoute.awaiting,
          ),
          const SizedBox(height: AppSizes.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSizes.md),
          if (tech != null) ...<Widget>[
            Row(
              children: <Widget>[
                SugoAvatar(
                  name: tech.displayName,
                  imageUrl: tech.avatarUrl,
                  size: 44,
                  verified: tech.isVerified,
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        tech.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tech.specializationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.micro.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            _Row(
              label: 'Skills',
              value: tech.skillTags.isEmpty
                  ? tech.specializationLabel
                  : tech.skillTags
                        .map(Technician.labelForSkill)
                        .take(3)
                        .join(', '),
            ),
            _Row(
              label: 'Location',
              value: tech.distanceAwayLabel ?? 'Location unavailable',
            ),
          ],
          _Row(label: 'Service', value: job.title),
          if (job.servicePath != null)
            _Row(label: 'Service type', value: job.servicePath!.label),
          _Row(
            label: 'When',
            value: job.preferredSchedule == null
                ? 'Flexible — no fixed date'
                : Fmt.dateTime(job.preferredSchedule!),
          ),
          _Row(
            label: 'Where',
            value: job.hasLocation ? job.locationLabel : 'Not pinned',
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 96, child: Text(label, style: AppTextStyles.caption)),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyStrong.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Ryan has 5:00 to accept. If they do not, we send it to the next
/// technician automatically." The clock starts when this screen opens, which
/// is the moment the request was sent - within a second of the server's
/// `offered_at`, the time the sweep goes by.
class _UrgentSentCard extends StatefulWidget {
  const _UrgentSentCard({required this.name});

  final String name;

  @override
  State<_UrgentSentCard> createState() => _UrgentSentCardState();
}

class _UrgentSentCardState extends State<_UrgentSentCard> {
  late final DateTime _deadline = DateTime.now().add(MatchResult.urgentWindow);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.accentSofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.bolt_rounded, color: AppColors.accentDark),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              '${widget.name} has 5 minutes to accept your urgent request. '
              'If they do not, we send it to the next technician '
              'automatically.',
              style: AppTextStyles.micro.copyWith(
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          UrgentCountdown(deadline: _deadline),
        ],
      ),
    );
  }
}
