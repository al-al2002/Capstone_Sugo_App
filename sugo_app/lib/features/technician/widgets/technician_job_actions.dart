import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_loading.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../tracking/widgets/route_map_card.dart';

/// What a technician does with the job they are on, on the job's own screen.
///
/// Moved here from the dashboard card on 2026-09-29, when that card became a
/// summary with a single "View job" (the user's request). Redesigned on
/// 2026-11-16, also at the user's request, around one question: *what do I do
/// next?*
///
/// ## The layout, top to bottom
///
/// 1. **Header** - what kind of job this is (home visit, pickup and delivery,
///    drop-off), so the technician never has to work it out from the buttons.
/// 2. **Destination** - home visits only: the client's address on a static
///    map, with the distance the travel fee was quoted on. A pickup's map
///    lives on the delivery screen.
/// 3. **The trip** - one large primary button. It is the thing a technician
///    does first, so it is the only filled button on the card.
/// 4. **Finishing up** - "Mark as complete" and, on a home visit, "Take it to
///    your shop", as list rows with a line saying what each one does. The
///    shop switch cannot be undone, so it should never look like a casual
///    second button next to the primary one.
/// 5. **A hint** - the one thing worth knowing for this path.
///
/// ## Why "Show route" was removed
///
/// The map used to carry its own "Show route" button. "Trip to the client"
/// opens `HomeVisitTripScreen`, which already shows the route - and the live
/// location and ETA the client sees. Two buttons to the same place made the
/// technician stop and choose, and the plain route was the wrong choice: it
/// never tells the client they have set off. The map is now a preview only
/// ([RouteMapPreview]); every other screen keeps its button.
///
/// The screen owns the calls; this widget only draws them and shows which one
/// is running ([isCompleting], [isMovingToShop]) - in its own colour with a
/// spinner, because grey reads as "not allowed" rather than "working on it".
class TechnicianJobActions extends StatelessWidget {
  const TechnicianJobActions({
    super.key,
    required this.job,
    required this.onTrip,
    required this.onComplete,
    required this.onNeedsShop,
    this.isCompleting = false,
    this.isMovingToShop = false,
    this.distanceKm,
    this.completeBlockedReason,
  });

  final Job job;
  final VoidCallback onTrip;
  final VoidCallback onComplete;
  final VoidCallback onNeedsShop;
  final bool isCompleting;
  final bool isMovingToShop;

  /// Why "Mark as complete" cannot be used yet, e.g. "Add the Before and
  /// After photos first" (the work record, 2026-11-22). Null when it can.
  /// The server refuses completion on its own too; this just says so first.
  final String? completeBlockedReason;

  /// How far the client was from this technician when they were matched -
  /// the distance the travel fee was quoted on. Shown under the address when
  /// known; never estimated here.
  final double? distanceKm;

  bool get _isHomeVisit => job.servicePath == ServicePath.homeService;
  bool get _isPickup => job.servicePath == ServicePath.pickup;

  /// A shop repair the technician collects and brings back (2026-11-17): the
  /// client's address is where both trips go, so it is on the card too.
  bool get _collectsAndReturns => _isPickup && !job.isSelfDropOff;
  bool get _busy => isCompleting || isMovingToShop;

  @override
  Widget build(BuildContext context) {
    final _JobKind kind = _JobKind.of(job);

    return SugoCard(
      pressable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header(kind: kind),
          const SizedBox(height: AppSizes.lg),

          if ((_isHomeVisit || _collectsAndReturns) &&
              job.hasLocation) ...<Widget>[
            _Destination(job: job, distanceKm: distanceKm),
            const SizedBox(height: AppSizes.md),
          ],

          if (_isHomeVisit || _isPickup) ...<Widget>[
            _TripButton(
              title: kind.tripTitle,
              subtitle: kind.tripSubtitle,
              onTap: _busy ? null : onTrip,
            ),
            const SizedBox(height: AppSizes.md),
          ],

          _ActionGroup(
            children: <Widget>[
              _ActionRow(
                icon: Icons.task_alt_rounded,
                tone: AppColors.success,
                toneSoft: AppColors.successSoft,
                title: 'Mark as complete',
                subtitle:
                    completeBlockedReason ??
                    'Two quick questions, then it closes',
                busyLabel: 'Completing…',
                isBusy: isCompleting,
                onTap: _busy || completeBlockedReason != null
                    ? null
                    : onComplete,
              ),
              // The escape hatch. A technician can only honestly answer "can
              // this be fixed here?" once they are standing in front of it.
              if (_isHomeVisit)
                _ActionRow(
                  icon: Icons.store_mall_directory_outlined,
                  tone: AppColors.warning,
                  toneSoft: AppColors.warningSoft,
                  title: 'Take it to your shop',
                  subtitle: "Can't fix it here? Collect the unit",
                  busyLabel: 'Switching…',
                  isBusy: isMovingToShop,
                  onTap: _busy ? null : onNeedsShop,
                ),
            ],
          ),

          const SizedBox(height: AppSizes.md),
          _Hint(text: kind.hint),
        ],
      ),
    );
  }
}

/// Everything that changes with the kind of job, in one place, so the
/// header, the trip button and the hint can never disagree.
class _JobKind {
  const _JobKind({
    required this.icon,
    required this.label,
    required this.detail,
    required this.tripTitle,
    required this.tripSubtitle,
    required this.hint,
  });

  factory _JobKind.of(Job job) {
    if (job.servicePath == ServicePath.homeService) {
      return const _JobKind(
        icon: Icons.home_repair_service_rounded,
        label: 'Home visit',
        detail: "You fix it at the client's address",
        tripTitle: 'Trip to the client',
        tripSubtitle: 'Route and live ETA for the client',
        hint:
            'Start the trip when you set off, so the client can follow you '
            'and knows if you are running late.',
      );
    }
    if (job.servicePath == ServicePath.pickup && job.isSelfDropOff) {
      return const _JobKind(
        icon: Icons.storefront_rounded,
        label: 'Drop-off',
        detail: 'The client brings it to your shop',
        tripTitle: 'Drop-off and collection',
        tripSubtitle: 'Receive the unit, then hand it back',
        hint:
            'The client brings it to your shop and collects it. Mark it '
            'received there when it arrives.',
      );
    }
    if (job.servicePath == ServicePath.pickup) {
      return const _JobKind(
        icon: Icons.local_shipping_rounded,
        label: 'Pickup',
        detail: 'You collect it and bring it back',
        tripTitle: 'Pickup and delivery',
        tripSubtitle: 'Route to the client, both trips',
        hint:
            'Two trips to the client\'s address: collect it, then bring it '
            'back fixed. The pickup and delivery fee covers both. Your '
            'location is shared from the pickup screen, so the client can see '
            'where their appliance is.',
      );
    }
    return const _JobKind(
      icon: Icons.fact_check_outlined,
      label: 'Diagnosis',
      detail: 'Work out what is wrong first',
      tripTitle: '',
      tripSubtitle: '',
      hint: 'Mark it complete once the diagnosis is settled.',
    );
  }

  final IconData icon;
  final String label;
  final String detail;
  final String tripTitle;
  final String tripSubtitle;
  final String hint;
}

/// "Your job" with the kind of job under it, beside its icon.
class _Header extends StatelessWidget {
  const _Header({required this.kind});

  final _JobKind kind;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: AppSizes.iconTile,
          height: AppSizes.iconTile,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppSizes.radius),
          ),
          child: Icon(kind.icon, size: 22, color: AppColors.primary),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Your job', style: AppTextStyles.sectionTitle),
              const SizedBox(height: 2),
              Text(
                '${kind.label} · ${kind.detail}',
                style: AppTextStyles.micro,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The client's address: a static map on top, the address under it, one
/// bordered tile - so it reads as a single place, not a map and a caption.
class _Destination extends StatelessWidget {
  const _Destination({required this.job, required this.distanceKm});

  final Job job;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final double? km = distanceKm;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          RouteMapPreview(
            latitude: job.latitude!,
            longitude: job.longitude!,
            height: 150,
          ),
          Padding(
            padding: const EdgeInsets.all(AppSizes.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.place_rounded,
                    size: 18,
                    color: AppColors.accentDark,
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Client address', style: AppTextStyles.micro),
                      const SizedBox(height: 2),
                      Text(
                        job.locationLabel,
                        style: AppTextStyles.bodyStrong.copyWith(
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (km != null) ...<Widget>[
                  const SizedBox(width: AppSizes.sm),
                  _DistancePill(km: km),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "4.2 km" beside the address.
class _DistancePill extends StatelessWidget {
  const _DistancePill({required this.km});

  final double km;

  @override
  Widget build(BuildContext context) {
    final String label = km < 1
        ? '${(km * 1000).round()} m'
        : '${km.toStringAsFixed(1)} km';

    return Semantics(
      label: 'About $label away',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.sm,
          vertical: AppSizes.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.primarySofter,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.near_me_rounded,
              size: 13,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSizes.xs),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card's one primary action: a large filled button with a line saying
/// what opening it does.
class _TripButton extends StatelessWidget {
  const _TripButton({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;

  /// Null while another action is running.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;

    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.5,
        duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.fast,
        child: Material(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md,
                  vertical: AppSizes.sm + 2,
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.navigation_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The finishing actions, as rows in one outlined group with hairlines
/// between them.
class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: AppSizes.md + 40 + AppSizes.md,
                color: AppColors.divider,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One finishing action: its icon in its own colour, a title, and a line
/// saying what happens. While it runs, the title becomes a spinner and a
/// label in that same colour.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.tone,
    required this.toneSoft,
    required this.title,
    required this.subtitle,
    required this.busyLabel,
    required this.isBusy,
    required this.onTap,
  });

  final IconData icon;
  final Color tone;
  final Color toneSoft;
  final String title;
  final String subtitle;
  final String busyLabel;
  final bool isBusy;

  /// Null while any action is running, this one included.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Dim the rows that are waiting on another action, not the one working.
    final bool dimmed = onTap == null && !isBusy;
    final Duration duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.fast;

    return Semantics(
      button: true,
      enabled: onTap != null,
      child: AnimatedOpacity(
        opacity: dimmed ? 0.5 : 1,
        duration: duration,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.md,
                vertical: AppSizes.sm + 2,
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: toneSoft,
                      borderRadius: BorderRadius.circular(AppSizes.sm + 2),
                    ),
                    child: Icon(icon, size: 20, color: tone),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        AnimatedSwitcher(
                          duration: duration,
                          layoutBuilder: _alignStart,
                          child: isBusy
                              ? IconTheme(
                                  key: const ValueKey<String>('busy'),
                                  data: IconThemeData(color: tone),
                                  child: DefaultTextStyle.merge(
                                    style: AppTextStyles.bodyStrong.copyWith(
                                      color: tone,
                                    ),
                                    child: SugoButtonProgress(label: busyLabel),
                                  ),
                                )
                              : Text(
                                  title,
                                  key: const ValueKey<String>('idle'),
                                  style: AppTextStyles.bodyStrong,
                                ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: AppTextStyles.caption.copyWith(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  if (!isBusy) ...<Widget>[
                    const SizedBox(width: AppSizes.sm),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: AppColors.hint,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// AnimatedSwitcher centres by default; a title belongs on the left.
  static Widget _alignStart(Widget? current, List<Widget> previous) {
    return Stack(
      alignment: AlignmentDirectional.centerStart,
      children: <Widget>[...previous, if (current != null) current],
    );
  }
}

/// A quiet line of advice at the foot of the card.
class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.sm + 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.caption.copyWith(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
