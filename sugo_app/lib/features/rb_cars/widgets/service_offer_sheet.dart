import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../config/service_offers.dart';
import '../models/issue_catalog.dart';

/// "What needs maintenance?" / "What needs installing?", with Davao prices.
///
/// One sheet for both doors into it - the home screen's category tiles and
/// step 1 of posting - so the two can never offer different services or
/// different prices. Returns the chosen offer, or null when dismissed.
Future<ServiceOffer?> showServiceOfferSheet(
  BuildContext context,
  IssueKind kind,
) {
  return showSugoBottomSheet<ServiceOffer>(
    context: context,
    title: kind == IssueKind.installation
        ? 'What needs installing?'
        : 'What needs maintenance?',
    subtitle: 'We will match you with technicians who do exactly this.',
    builder: (BuildContext sheetContext) => _OfferList(
      offers: ServiceOffers.of(kind),
      onPick: (ServiceOffer offer) => Navigator.of(sheetContext).pop(offer),
    ),
  );
}

class _OfferList extends StatefulWidget {
  const _OfferList({required this.offers, required this.onPick});

  final List<ServiceOffer> offers;
  final ValueChanged<ServiceOffer> onPick;

  @override
  State<_OfferList> createState() => _OfferListState();
}

/// The rows arrive one after another, a few frames apart - enough to read as
/// a list being dealt out, not enough to make anyone wait for it.
class _OfferListState extends State<_OfferList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: AppMotion.slow + AppMotion.staggerStep * widget.offers.length,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entrance.isDismissed) {
      AppMotion.reduced(context) ? _entrance.value = 1 : _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int count = widget.offers.length;
    final double total = _entrance.duration!.inMilliseconds.toDouble();
    final double step = AppMotion.staggerStep.inMilliseconds / total;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < count; i++)
          _Rise(
            animation: CurveTween(
              curve: Interval(
                (step * i).clamp(0, 1),
                (step * i + AppMotion.slow.inMilliseconds / total).clamp(0, 1),
                curve: AppMotion.emphasized,
              ),
            ).animate(_entrance),
            child: _OfferRow(
              offer: widget.offers[i],
              onTap: () => widget.onPick(widget.offers[i]),
            ),
          ),
      ],
    );
  }
}

/// Fades in while rising a few pixels.
class _Rise extends StatelessWidget {
  const _Rise({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({required this.offer, required this.onTap});

  final ServiceOffer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String? price = offer.priceLabel;

    return Semantics(
      button: true,
      label: <String>[offer.label, offer.hint, ?price].join(', '),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSizes.md,
              horizontal: AppSizes.xs,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: AppSizes.iconTile,
                  height: AppSizes.iconTile,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppSizes.md),
                  ),
                  child: Icon(offer.icon, size: 21, color: AppColors.primary),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(offer.label, style: AppTextStyles.titleSmall),
                      const SizedBox(height: 2),
                      Text(offer.hint, style: AppTextStyles.micro),
                    ],
                  ),
                ),
                if (price != null) ...<Widget>[
                  const SizedBox(width: AppSizes.sm),
                  _PricePill(price),
                ],
                const SizedBox(width: AppSizes.xs),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.hint,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  const _PricePill(this.price);

  final String price;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.sm,
        vertical: AppSizes.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Text(
        price,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.success,
        ),
      ),
    );
  }
}
