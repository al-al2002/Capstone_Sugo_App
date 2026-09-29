import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../models/device_category.dart';
import '../models/issue_catalog.dart';
import '../models/job_enums.dart';
import '../models/problem_catalog.dart';
import '../providers/job_posting_provider.dart';
import '../theme/posting_text.dart';
import '../widgets/posting_field.dart';
import '../widgets/posting_scaffold.dart';
import '../widgets/service_path_card.dart';
import 'device_details_screen.dart';
import '../../../core/constants/app_colors.dart';

/// Step 2 of 5: what is it doing, and where should that send it?
///
/// This screen is the visible half of the classification rule base in
/// `ProblemCatalog`. The suggested path, the confidence and the sentence
/// explaining the decision all come from `ClassificationResult.evaluate` -
/// nothing here is hard-coded copy.
///
/// Symptom and suggestion sit on one screen deliberately. They used to be two,
/// and the client had to press Continue to find out what their answer implied;
/// now the three path cards re-rank the moment the dropdown changes, so the
/// rules are visibly reacting to the answer rather than grading it afterwards.
class SymptomScreen extends StatelessWidget {
  const SymptomScreen({super.key, required this.posting});

  final JobPostingProvider posting;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: posting,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final DeviceCategory? category = posting.deviceCategory;

    if (category == null) {
      // Reached only if someone deep-links here without choosing a device.
      return const Scaffold(
        body: Center(child: Text('Start from the job posting screen.')),
      );
    }

    final ClassificationResult? result = posting.draft.classification;
    final ServicePath? selected = posting.draft.servicePath;

    return PostingScaffold(
      step: 2,
      title: "Tell us what's wrong",
      subtitle: 'Closest match is fine — a technician confirms on arrival.',
      stepName: 'Symptom',
      ctaLabel: selected == null
          ? 'Continue'
          : 'Continue with ${selected.label}',
      ctaHint: 'Pick the closest symptom to continue.',
      onCta: posting.canLeaveSymptom
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DeviceDetailsScreen(posting: posting),
              ),
            )
          : null,
      children: <Widget>[
        const PostingLabel('Symptom'),
        const SizedBox(height: AppSizes.sm),
        _SymptomDropdown(
          category: category,
          selected: posting.draft.problemSymptom,
          onSelect: posting.selectSymptom,
        ),

        if (posting.draft.problemSymptom != null) ...<Widget>[
          const SizedBox(height: AppSizes.xl),
          const PostingLabel('Is there visible physical damage?'),
          const SizedBox(height: AppSizes.xs),
          const Text(
            'Cracks, dents, burn marks, or anything spilled on it. This one '
            'answer can move the job from your kitchen table to the shop '
            'bench, which is why we ask it here.',
            style: PostingText.caption,
          ),
          const SizedBox(height: AppSizes.md),
          _DamageToggle(
            value: posting.draft.hasPhysicalDamage,
            onChanged: posting.setPhysicalDamage,
          ),
        ],

        if (result != null && selected != null) ...<Widget>[
          const SizedBox(height: AppSizes.xl),
          const Text(
            "Based on your answer, here's what we suggest:",
            style: PostingText.subtitle,
          ),
          const SizedBox(height: AppSizes.md),
          ServicePathSuggestion(
            result: result,
            selected: selected,
            onChanged: posting.overrideServicePath,
          ),
        ],
      ],
    );
  }
}

class _SymptomDropdown extends StatelessWidget {
  const _SymptomDropdown({
    required this.category,
    required this.selected,
    required this.onSelect,
  });

  final DeviceCategory category;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    // Rebuilt per card, from data. Adding an issue is a row in `IssueCatalog`,
    // never a branch in here - including a camera symptom, which lands under
    // CCTV rather than Wi-Fi by virtue of its `cctv_` code.
    final List<IssueOption> issues = category.issues;
    final IssueOption? picked = IssueCatalog.byCode(selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        DropdownButtonFormField<String>(
          key: ValueKey<DeviceCategory>(category),
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(
            hintText: 'Pick the closest description',
          ),
          items: <DropdownMenuItem<String>>[
            ...issues.map(
              (IssueOption issue) => DropdownMenuItem<String>(
                value: issue.code,
                child: Text(
                  issue.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ),
            // The escape hatch. Choosing this routes the job to the IT
            // community with low confidence, instead of guessing a path.
            const DropdownMenuItem<String>(
              value: ProblemCatalog.notSureCode,
              child: Text(
                'I am not sure',
                style: TextStyle(
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
          onChanged: (String? value) {
            if (value != null) onSelect(value);
          },
        ),

        if (picked?.impliesPhysicalDamage ?? false) ...<Widget>[
          const SizedBox(height: AppSizes.sm),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.check_circle_outline_rounded,
                size: 13,
                color: AppColors.primaryDark,
              ),
              SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Counted as physical damage - the next question is already '
                  'answered.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
        ] else if (selected == ProblemCatalog.notSureCode) ...<Widget>[
          const SizedBox(height: AppSizes.sm),
          const _NotSureNote(),
        ],
      ],
    );
  }
}

class _NotSureNote extends StatelessWidget {
  const _NotSureNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.groups_rounded, size: 15, color: AppColors.primaryDark),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'No problem. The IT community narrows it down before anyone is '
              'dispatched, so you are not charged for a guess.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DamageToggle extends StatelessWidget {
  const _DamageToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _DamageOption(
            label: 'No visible damage',
            selected: !value,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: _DamageOption(
            label: 'Yes, it is damaged',
            selected: value,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _DamageOption extends StatelessWidget {
  const _DamageOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
            decoration: BoxDecoration(
              color: selected ? AppColors.primarySofter : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primaryDark : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
