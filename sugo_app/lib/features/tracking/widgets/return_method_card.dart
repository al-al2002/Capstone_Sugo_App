import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../rb_cars/models/technician_profile_details.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../rb_cars/services/technician_directory_service.dart';
import '../models/job_tracking.dart';
import '../services/tracking_service.dart';
import 'route_map_card.dart';

/// "How do you want it back?" - the client's choice on a workshop repair.
///
/// Shown on shop-pickup jobs, and on home visits that became one ("needs
/// shop"), from the moment a technician has the job until the unit starts
/// back. Two answers:
///
///   * **Deliver it to me** - the default; the technician brings it back.
///   * **I'll pick it up** - the client collects it at the workshop. The
///     technician sees "Client will pick up" on their Jobs list and cannot
///     record a delivery, and the client gets the in-app route to the shop
///     straight away.
///
/// The rules live in `set_return_method()`; this card only offers what the
/// server would accept, and shows its refusal word for word when it does not.
class ReturnMethodCard extends StatefulWidget {
  const ReturnMethodCard({
    super.key,
    required this.jobId,
    required this.technicianId,
    this.stage,
    this.service,
  });

  final String jobId;

  /// Whose workshop the route leads to.
  final String technicianId;

  /// Where the unit is, or null when the technician has not started yet.
  final TrackingStage? stage;

  /// Tests only.
  final TrackingService? service;

  @override
  State<ReturnMethodCard> createState() => _ReturnMethodCardState();
}

class _ReturnMethodCardState extends State<ReturnMethodCard> {
  late final TrackingService _service = widget.service ?? TrackingService();

  ReturnMethod? _method;

  /// The option being saved, for its spinner.
  ReturnMethod? _saving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ReturnMethod method = await _service.returnMethod(widget.jobId);
    if (!mounted) return;
    setState(() => _method = method);
  }

  /// Once it is waiting at the shop there is no route back to delivery - the
  /// server refuses it - so the delivery option says so instead of spinning
  /// into an error.
  bool get _waitingAtShop => widget.stage == TrackingStage.readyForCollection;

  Future<void> _choose(ReturnMethod method) async {
    if (_saving != null || method == _method) return;

    if (_waitingAtShop && method == ReturnMethod.delivery) {
      UiFeedback.showInfo(
        context,
        'It is already waiting at the shop. Message the technician to arrange '
        'a delivery.',
      );
      return;
    }

    setState(() => _saving = method);
    try {
      final ReturnMethod saved = await _service.setReturnMethod(
        widget.jobId,
        method,
      );
      if (!mounted) return;
      setState(() => _method = saved);
      UiFeedback.showSuccess(
        context,
        saved == ReturnMethod.clientPickup
            ? 'Got it - the technician will know you are collecting it.'
            : 'Got it - the technician will bring it back to you.',
      );
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ReturnMethod? method = _method;
    if (method == null) {
      return const SugoSkeleton(height: 172, radius: AppSizes.panelRadius);
    }

    return SugoCard(
      pressable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('How do you want it back?', style: AppTextStyles.bodyStrong),
          const SizedBox(height: 2),
          Text(
            'You can change this until it heads back to you.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSizes.md),
          _OptionTile(
            icon: Icons.delivery_dining_rounded,
            title: 'Deliver it to me',
            body: 'The technician brings it back once it is fixed.',
            selected: method == ReturnMethod.delivery,
            busy: _saving == ReturnMethod.delivery,
            onTap: () => _choose(ReturnMethod.delivery),
          ),
          const SizedBox(height: AppSizes.sm),
          _OptionTile(
            icon: Icons.storefront_rounded,
            title: "I'll pick it up",
            body: 'Collect it at the workshop yourself. We will show you the way.',
            selected: method == ReturnMethod.clientPickup,
            busy: _saving == ReturnMethod.clientPickup,
            onTap: () => _choose(ReturnMethod.clientPickup),
          ),

          // The route opens the moment they choose to collect, not only when
          // the unit is ready - they can see where the shop is and plan it.
          AnimatedSize(
            duration: AppMotion.slow,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: method == ReturnMethod.clientPickup
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSizes.lg),
                    child: _WorkshopRoute(
                      jobId: widget.jobId,
                      technicianId: widget.technicianId,
                      ready: _waitingAtShop,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(AppSizes.tileRadius);

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: AppMotion.base,
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: selected ? AppColors.primarySofter : AppColors.surface,
              borderRadius: radius,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: AppMotion.base,
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppSizes.radius),
                  ),
                  child: Icon(
                    icon,
                    size: 21,
                    color: selected ? Colors.white : AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: AppTextStyles.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: AppTextStyles.caption.copyWith(height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: busy
                      ? const CircularProgressIndicator(strokeWidth: 2.2)
                      : Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 22,
                          color: selected ? AppColors.primary : AppColors.hint,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The map and route to the workshop, once the client is collecting.
///
/// The shop location comes from `technician_profile`, which releases it to a
/// client with a booking (20260916000008) - which a client collecting their
/// own repair has. Best effort: without a recorded address the card still
/// says what to do.
class _WorkshopRoute extends StatefulWidget {
  const _WorkshopRoute({
    required this.jobId,
    required this.technicianId,
    required this.ready,
  });

  final String jobId;
  final String technicianId;
  final bool ready;

  @override
  State<_WorkshopRoute> createState() => _WorkshopRouteState();
}

class _WorkshopRouteState extends State<_WorkshopRoute> {
  // Late, so it is first built inside `_load`'s try: a directory that cannot
  // be reached leaves the card on its fallback text instead of failing.
  late final TechnicianDirectoryService _directory =
      TechnicianDirectoryService();

  TechnicianProfileDetails? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final TechnicianProfileDetails profile = await _directory.profile(
        widget.technicianId,
        // Only the workshop is wanted here.
        reviewLimit: 1,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SugoSkeleton(height: 180, radius: AppSizes.tileRadius);
    }

    final TechnicianProfileDetails? profile = _profile;
    final bool hasShop = profile?.hasShopLocation ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              widget.ready
                  ? Icons.check_circle_rounded
                  : Icons.build_circle_rounded,
              size: 18,
              color: widget.ready ? AppColors.success : AppColors.accent,
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(
                widget.ready
                    ? 'It is ready. Here is where to collect it.'
                    : 'Still being repaired. Here is where to collect it - '
                          'you will see "Ready for collection" when it is done.',
                style: AppTextStyles.caption.copyWith(
                  height: 1.4,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.md),
        if (hasShop)
          RouteMapCard(
            icon: Icons.storefront_rounded,
            jobId: widget.jobId,
            latitude: profile!.shopLatitude!,
            longitude: profile.shopLongitude!,
            title: (profile.shopName?.trim().isNotEmpty ?? false)
                ? profile.shopName!
                : 'Workshop',
            address: profile.technician.displayName,
          )
        else
          Text(
            'The technician has not added a workshop address yet. Message '
            'them to agree a time and the exact place.',
            style: AppTextStyles.caption.copyWith(height: 1.4),
          ),
      ],
    );
  }
}

/// The technician's reminder that the client is collecting: no delivery trip.
///
/// Shared by the job detail and the delivery controls, so both say it the
/// same way.
class ClientPickupBanner extends StatelessWidget {
  const ClientPickupBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.accentSofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.storefront_rounded, size: 20, color: AppColors.accent),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'The client will pick it up',
                  style: AppTextStyles.bodyStrong.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'No delivery trip. When it is fixed, mark it ready for '
                  'collection and they will come to your shop.',
                  style: AppTextStyles.caption.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Client pick-up" - the same fact as [ClientPickupBanner], small enough for
/// a card in the technician's Jobs list.
class ClientPickupChip extends StatelessWidget {
  const ClientPickupChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentSofter,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.storefront_rounded, size: 13, color: AppColors.accent),
          SizedBox(width: 4),
          Text(
            'Client pick-up',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
