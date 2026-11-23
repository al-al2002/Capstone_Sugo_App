import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/travel_conditions.dart';

/// "Travelling to clients" - will you still go in the rain, or in heavy
/// traffic? (2026-11-22.)
///
/// Two single-choice questions. Used on the registration "What work do you
/// take?" step and in Edit profile, so the question reads the same in both.
///
/// The intro says plainly what the answer does, because a technician deciding
/// how to answer should know: saying yes puts them ahead when it is raining or
/// jammed, saying no keeps them from being sent jobs they would decline.
/// Nothing is preselected - an answer the technician did not choose would be
/// a claim on their behalf.
class TravelConditionsSection extends StatelessWidget {
  const TravelConditionsSection({
    super.key,
    required this.rain,
    required this.traffic,
    required this.onRainChanged,
    required this.onTrafficChanged,
    this.enabled = true,
  });

  final RainTravel? rain;
  final TrafficTravel? traffic;
  final ValueChanged<RainTravel> onRainChanged;
  final ValueChanged<TrafficTravel> onTrafficChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(
              Icons.two_wheeler_rounded,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(
                'Travelling to clients',
                style: AppTextStyles.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'When it rains or the roads are jammed, clients are matched first '
          'with technicians who said they will still come. Answer honestly: '
          'a "no" means you are not sent jobs you would turn down.',
          style: AppTextStyles.caption.copyWith(height: 1.4),
        ),
        const SizedBox(height: AppSizes.lg),
        _Question(
          icon: Icons.water_drop_rounded,
          question: 'Will you still go to a client when it is raining?',
          children: <Widget>[
            for (final RainTravel option in RainTravel.values)
              _OptionTile(
                key: ValueKey<String>('rain-${option.wire}'),
                label: option.label,
                selected: rain == option,
                onTap: enabled ? () => onRainChanged(option) : null,
              ),
          ],
        ),
        const SizedBox(height: AppSizes.lg),
        _Question(
          icon: Icons.traffic_rounded,
          question: 'Will you still go when traffic is heavy?',
          children: <Widget>[
            for (final TrafficTravel option in TrafficTravel.values)
              _OptionTile(
                key: ValueKey<String>('traffic-${option.wire}'),
                label: option.label,
                selected: traffic == option,
                onTap: enabled ? () => onTrafficChanged(option) : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({
    required this.icon,
    required this.question,
    required this.children,
  });

  final IconData icon;
  final String question;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: AppColors.secondaryDark),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                question,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        ...children,
      ],
    );
  }
}

/// One answer: a radio dot and the words, the whole row tappable.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Duration swap = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.base;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSizes.radius),
            child: AnimatedContainer(
              duration: swap,
              curve: AppMotion.standard,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.md,
                vertical: AppSizes.md,
              ),
              decoration: BoxDecoration(
                color: selected ? AppColors.primarySofter : AppColors.surface,
                borderRadius: BorderRadius.circular(AppSizes.radius),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: <Widget>[
                  AnimatedContainer(
                    duration: swap,
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? AppColors.primary : AppColors.border,
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: AnimatedScale(
                      duration: swap,
                      scale: selected ? 1 : 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
