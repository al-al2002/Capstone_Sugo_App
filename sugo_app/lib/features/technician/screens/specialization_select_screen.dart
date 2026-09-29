import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_button.dart';
import '../models/assessment.dart';

/// What do you repair?
///
/// The choice selects which question bank the quiz pulls from, and is written
/// to `technicians.specialization` at the end - where Stage 1 of the matcher
/// scores it at 25% weight. Picking appliance repair means appliance jobs rank
/// you higher and laptop jobs rank you lower.
///
/// Only `appliance_repair` has a seeded bank so far. The rest are shown greyed
/// out rather than hidden, so a technician can see the platform is broader than
/// what they can sit today.
///
/// Controlled and write-free: the selection is reported up and held in memory
/// until registration is committed.
class SpecializationSelectScreen extends StatefulWidget {
  const SpecializationSelectScreen({
    super.key,
    required this.onChosen,
    this.selected,
  });

  final void Function(Specialization specialization) onChosen;
  final Specialization? selected;

  @override
  State<SpecializationSelectScreen> createState() =>
      _SpecializationSelectScreenState();
}

class _SpecializationSelectScreenState
    extends State<SpecializationSelectScreen> {
  Specialization? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selected;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.lg,
        AppSizes.screenPadding,
        AppSizes.xxl,
      ),
      children: <Widget>[
        Text('What do you repair?', style: AppTextStyles.headline),
        const SizedBox(height: AppSizes.xs),
        Text(
          'Your assessment is drawn from this area, and it is what the '
          'matching engine scores you on when jobs come in.',
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.xl),

        ...Specialization.values.map(
          (Specialization option) => _SpecializationTile(
            option: option,
            selected: option == _selected,
            onTap: option.available
                ? () => setState(() => _selected = option)
                : null,
          ),
        ),

        const SizedBox(height: AppSizes.lg),
        PrimaryButton(
          label: 'Continue to assessment',
          onPressed: _selected == null
              ? null
              : () => widget.onChosen(_selected!),
        ),
        const SizedBox(height: AppSizes.sm),
        Text(
          'You can qualify in more areas later by taking another assessment.',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(fontSize: 12),
        ),
      ],
    );
  }
}

class _SpecializationTile extends StatelessWidget {
  const _SpecializationTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final Specialization option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onTap == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(AppSizes.lg),
              decoration: BoxDecoration(
                color: selected ? AppColors.primarySofter : AppColors.surface,
                borderRadius: BorderRadius.circular(AppSizes.tileRadius),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary
                          : AppColors.primarySofter,
                      borderRadius: BorderRadius.circular(AppSizes.radius),
                    ),
                    child: Icon(
                      option.icon,
                      size: 21,
                      color: selected ? Colors.white : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                option.label,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (!option.available) ...<Widget>[
                              const SizedBox(width: AppSizes.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.divider,
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.pillRadius,
                                  ),
                                ),
                                child: const Text(
                                  'Coming soon',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          option.blurb,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (option.available)
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 19,
                      color: selected ? AppColors.primary : AppColors.border,
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
