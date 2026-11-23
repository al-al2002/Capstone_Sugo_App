import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_motion.dart';
import '../models/client_onboarding_models.dart';
import '../models/travel_conditions.dart';
import 'location_pin_step.dart';
import 'onboarding_step_intro.dart';
import 'travel_conditions_section.dart';

/// "What work do you take?" - the technician's kind of work (2026-11-17).
///
/// Home Service, Shop Repair, or both. Clients are matched only with
/// technicians who take the kind of service they chose (`match-technician`
/// Stage 1, migration 20261117000007), so this step decides which jobs a
/// technician is ever offered.
///
/// Each option says what the work actually involves, because "home service"
/// and "shop repair" mean different things to different people, and a
/// technician who picks the wrong one is matched to jobs they cannot do.
///
/// Shop Repair needs the shop's location - clients bringing a unit in are
/// routed there, and the delivery fee is measured from it - so picking it
/// opens the shop's name and a map right here.
///
/// Since 2026-11-22 the step also asks whether they still travel in the rain
/// and in heavy traffic ([TravelConditionsSection]). Both are required to
/// continue; matching uses them on rainy or jammed days.
class WorkTypeStep extends StatefulWidget {
  const WorkTypeStep({
    super.key,
    required this.homeService,
    required this.shopRepair,
    required this.onHomeServiceChanged,
    required this.onShopRepairChanged,
    required this.shopPlace,
    required this.onShopPlaceChanged,
    required this.shopName,
    required this.onShopNameChanged,
    required this.rainTravel,
    required this.trafficTravel,
    required this.onRainTravelChanged,
    required this.onTrafficTravelChanged,
    this.autoLocate = true,
  });

  final bool homeService;
  final bool shopRepair;
  final ValueChanged<bool> onHomeServiceChanged;
  final ValueChanged<bool> onShopRepairChanged;

  final RainTravel? rainTravel;
  final TrafficTravel? trafficTravel;
  final ValueChanged<RainTravel> onRainTravelChanged;
  final ValueChanged<TrafficTravel> onTrafficTravelChanged;

  final GeoPlace? shopPlace;
  final ValueChanged<GeoPlace> onShopPlaceChanged;

  final String shopName;
  final ValueChanged<String> onShopNameChanged;

  /// Passed to the shop map: find the technician on opening. Tests pass false.
  final bool autoLocate;

  @override
  State<WorkTypeStep> createState() => _WorkTypeStepState();
}

class _WorkTypeStepState extends State<WorkTypeStep> {
  late final TextEditingController _name = TextEditingController(
    text: widget.shopName,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduced = AppMotion.reduced(context);
    final bool noneChosen = !widget.homeService && !widget.shopRepair;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const OnboardingStepIntro(
          icon: Icons.work_rounded,
          title: 'What work do you take?',
          subtitle:
              'Pick one or both. Clients are matched only with technicians '
              'who do the kind of service they chose.',
        ),
        const SizedBox(height: AppSizes.xl),
        SugoRiseIn(
          delay: AppMotion.staggerDelay(1),
          child: _WorkCard(
            key: const ValueKey<String>('work-home'),
            selected: widget.homeService,
            icon: Icons.home_repair_service_rounded,
            title: 'Home Service',
            tagline: 'You go to the client',
            points: const <String>[
              'Repair, clean or install at the client\'s home or office.',
              'Bring your own tools and diagnose on the spot.',
              'Offered jobs within your travel radius.',
            ],
            onTap: () => widget.onHomeServiceChanged(!widget.homeService),
          ),
        ),
        const SizedBox(height: AppSizes.md),
        SugoRiseIn(
          delay: AppMotion.staggerDelay(2),
          child: _WorkCard(
            key: const ValueKey<String>('work-shop'),
            selected: widget.shopRepair,
            icon: Icons.storefront_rounded,
            title: 'Shop Repair',
            tagline: 'The unit comes to your shop',
            points: const <String>[
              'Clients drop it off, or you collect it and bring it back.',
              'Bench work: board repair, part swaps, data recovery.',
              'Needs your shop\'s location on the map.',
            ],
            onTap: () => widget.onShopRepairChanged(!widget.shopRepair),
          ),
        ),
        const SizedBox(height: AppSizes.md),
        AnimatedSwitcher(
          duration: reduced ? Duration.zero : AppMotion.base,
          child: Text(
            noneChosen
                ? 'Choose at least one to continue.'
                : widget.homeService && widget.shopRepair
                ? 'You will be offered both kinds of job.'
                : widget.homeService
                ? 'You will be offered Home Service jobs only.'
                : 'You will be offered Shop Repair jobs only.',
            key: ValueKey<String>('${widget.homeService}-${widget.shopRepair}'),
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: noneChosen ? AppColors.warning : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // The shop, only when Shop Repair is picked.
        if (widget.shopRepair) ...<Widget>[
          const SizedBox(height: AppSizes.xl),
          SugoRiseIn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _name,
                  onChanged: widget.onShopNameChanged,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Shop name (optional)',
                    hintText: 'e.g. Santos Repair Hub',
                    prefixIcon: Icon(Icons.storefront_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                LocationPinStep(
                  place: widget.shopPlace,
                  onPlaceChanged: widget.onShopPlaceChanged,
                  autoLocate: widget.autoLocate,
                  title: 'Pin your shop',
                  subtitle:
                      'Clients who bring a unit in are routed here, and the '
                      'pickup fee is measured from it.',
                  mapHeight: 220,
                ),
              ],
            ),
          ),
        ],

        // Rain and traffic (2026-11-22): asked of everyone, since a Shop
        // Repair technician who collects and returns units travels too.
        const SizedBox(height: AppSizes.xl),
        SugoRiseIn(
          delay: AppMotion.staggerDelay(3),
          child: TravelConditionsSection(
            rain: widget.rainTravel,
            traffic: widget.trafficTravel,
            onRainChanged: widget.onRainTravelChanged,
            onTrafficChanged: widget.onTrafficTravelChanged,
          ),
        ),
      ],
    );
  }
}

/// One kind of work: what it is, in three plain lines, and a tick when
/// chosen. Tapping toggles it - both may be on.
class _WorkCard extends StatelessWidget {
  const _WorkCard({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.tagline,
    required this.points,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String tagline;
  final List<String> points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Duration swap = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.base;

    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $tagline.',
      excludeSemantics: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          child: AnimatedContainer(
            duration: swap,
            curve: AppMotion.standard,
            padding: const EdgeInsets.all(AppSizes.lg),
            decoration: BoxDecoration(
              color: selected ? AppColors.primarySofter : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.cardRadius),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AnimatedContainer(
                      duration: swap,
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: selected
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: <Color>[
                                  AppColors.primary,
                                  AppColors.secondary,
                                ],
                              )
                            : null,
                        color: selected ? null : AppColors.primarySofter,
                        borderRadius: BorderRadius.circular(AppSizes.radius),
                      ),
                      child: Icon(
                        icon,
                        size: 22,
                        color: selected ? Colors.white : AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(title, style: AppTextStyles.titleSmall),
                          Text(
                            tagline,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.secondaryDark,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    _Tick(selected: selected),
                  ],
                ),
                const SizedBox(height: AppSizes.md),
                for (final String point in points)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            point,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textPrimary,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
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

/// A round check that fills in when the card is chosen.
class _Tick extends StatelessWidget {
  const _Tick({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final Duration swap = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.base;
    return AnimatedContainer(
      duration: swap,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primary : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
          width: 2,
        ),
      ),
      child: AnimatedScale(
        duration: swap,
        curve: AppMotion.playful,
        scale: selected ? 1 : 0,
        child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
      ),
    );
  }
}
