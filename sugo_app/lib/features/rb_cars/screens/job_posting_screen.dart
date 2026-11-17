import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../config/service_offers.dart';
import '../models/device_category.dart';
import '../models/issue_catalog.dart';
import '../models/job.dart';
import '../models/job_enums.dart';
import '../providers/job_posting_provider.dart';
import '../theme/posting_text.dart';
import '../widgets/device_type_grid.dart';
import '../widgets/posting_scaffold.dart';
import '../widgets/service_kind_card.dart';
import '../widgets/service_offer_sheet.dart';
import 'technician_preferences_screen.dart';

/// Step 1 of 6: a repair, a tune-up or a new install?
///
/// Two ways in since 2026-11-16 (the user's request): the five device cards
/// for a repair, and **Maintenance** / **Installation**, the same two doors
/// the home screen has. Those open the shared [showServiceOfferSheet]; an
/// answer picks the device and - when it names one - the exact problem, then
/// moves straight on, because the client has already said everything this
/// step asks.
///
/// Owns the [JobPostingProvider] for the whole flow. Later screens take it
/// through their constructors, so the draft survives navigation but is disposed
/// the moment the client backs out of posting.
///
/// ## Why the later screens are not re-provided
///
/// A pushed route is a **sibling** of its opener in the Navigator's overlay,
/// not a descendant. Wrapping each screen in its own
/// `ChangeNotifierProvider.value` therefore produced several `InheritedProvider`
/// elements exposing one notifier across unrelated subtrees, and unwinding the
/// flow could deactivate one while widgets still depended on it - the
/// `_dependents.isEmpty is not true` assertion in `framework.dart`.
///
/// Passing the instance down the constructor and listening with
/// `ListenableBuilder` keeps exactly one provider and removes the whole class
/// of bug.
class JobPostingScreen extends StatelessWidget {
  const JobPostingScreen({
    super.key,
    this.preselectedTechnicianId,
    this.initialPath,
    this.initialCategory,
    this.initialSymptomCode,
  }) : editing = null;

  /// "Edit post": the same flow, opened on [job] with every answer filled in.
  /// Saving on the last step updates the job and matches it again.
  const JobPostingScreen.edit({super.key, required Job job})
    : editing = job,
      preselectedTechnicianId = null,
      initialPath = null,
      initialCategory = null,
      initialSymptomCode = null;

  /// The job being edited, or null when posting a new one.
  final Job? editing;

  /// Set when the flow was opened from a technician's detail screen.
  final String? preselectedTechnicianId;

  /// Set when the flow was opened from a home-screen service tile, e.g.
  /// tapping "Pickup" pre-selects the pickup path on the symptom step.
  final ServicePath? initialPath;

  /// Set when the flow was opened from a home-screen category tile or a
  /// search result. The device is chosen for the client and the flow opens on
  /// the next step - "Your technician" since 2026-11-15 - with the device step
  /// still underneath, so Back lands on it with the choice intact rather than
  /// leaving the flow.
  final DeviceCategory? initialCategory;

  /// Set when a search result was a specific problem ("Not cooling"). Picked
  /// on the problem step for the client; they can still change it. Only read
  /// together with [initialCategory].
  final String? initialSymptomCode;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<JobPostingProvider>(
      create: (_) => editing == null
          ? JobPostingProvider(preselectedTechnicianId: preselectedTechnicianId)
          : JobPostingProvider.editing(editing!),
      child: _DeviceStep(
        initialPath: initialPath,
        initialCategory: initialCategory,
        initialSymptomCode: initialSymptomCode,
      ),
    );
  }
}

class _DeviceStep extends StatefulWidget {
  const _DeviceStep({
    this.initialPath,
    this.initialCategory,
    this.initialSymptomCode,
  });

  final ServicePath? initialPath;
  final DeviceCategory? initialCategory;
  final String? initialSymptomCode;

  @override
  State<_DeviceStep> createState() => _DeviceStepState();
}

class _DeviceStepState extends State<_DeviceStep> {
  ServicePath? get initialPath => widget.initialPath;

  @override
  void initState() {
    super.initState();
    final DeviceCategory? category = widget.initialCategory;
    if (category == null) return;
    // After the first frame, so the provider above is readable and the push
    // happens from a route that has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final JobPostingProvider posting = context.read<JobPostingProvider>();
      posting.selectCategory(category);
      final String? symptom = widget.initialSymptomCode;
      if (symptom != null && category.issues.any((i) => i.code == symptom)) {
        posting.selectSymptom(symptom);
      }
      _continue(context, posting);
    });
  }

  @override
  Widget build(BuildContext context) {
    final JobPostingProvider posting = context.watch<JobPostingProvider>();

    return PostingScaffold(
      step: 1,
      title: posting.isEditing ? 'Edit your post' : 'What do you need?',
      subtitle: posting.isEditing
          ? 'Your answers are filled in. Change what you need, then save on '
                'the last step.'
          : 'A repair, a tune-up or a new install. Start here.',
      stepName: 'Service',
      ctaLabel: 'Continue',
      ctaHint: 'Pick a device, or choose maintenance or installation.',
      onCta: posting.canLeaveDevice ? () => _continue(context, posting) : null,
      children: <Widget>[
        const _SectionHeading(
          overline: 'Repair',
          title: 'Something broken?',
          caption: 'Pick the device so we can narrow the right specialists.',
        ),
        const SizedBox(height: AppSizes.md),
        DeviceTypeGrid(
          selected: posting.deviceCategory,
          onSelect: posting.selectCategory,
        ),
        const SizedBox(height: AppSizes.xl),
        const _SectionHeading(
          overline: 'Care and set-up',
          title: 'Maintenance or a new install?',
          caption: 'Pick one and we take you to it.',
        ),
        const SizedBox(height: AppSizes.md),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: ServiceKindCard(
                  kind: IssueKind.maintenance,
                  onTap: () => _pickService(IssueKind.maintenance),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: ServiceKindCard(
                  kind: IssueKind.installation,
                  onTap: () => _pickService(IssueKind.installation),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Maintenance or Installation: the shared sheet, then straight on.
  Future<void> _pickService(IssueKind kind) async {
    final JobPostingProvider posting = context.read<JobPostingProvider>();
    final ServiceOffer? offer = await showServiceOfferSheet(context, kind);
    if (offer == null || !mounted) return;

    posting.selectCategory(offer.category);
    final String? code = offer.issueCode;
    if (code != null) posting.selectSymptom(code);
    _continue(context, posting);
  }

  void _continue(BuildContext context, JobPostingProvider posting) {
    if (initialPath != null) posting.overrideServicePath(initialPath!);

    // Step 2 is the client's preferences for their technician, asked before
    // the problem is described (the pre-filter brief, 2026-11-15). It pushes
    // the symptom step itself.
    Navigator.of(context).push(
      PostingRoute<void>(
        builder: (_) => TechnicianPreferencesScreen(posting: posting),
      ),
    );
  }
}

/// A small label, a title and one line - the two halves of step 1.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.overline,
    required this.title,
    required this.caption,
  });

  final String overline;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          overline.toUpperCase(),
          style: AppTextStyles.overline.copyWith(
            color: AppColors.secondaryDark,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Semantics(
          header: true,
          child: Text(title, style: AppTextStyles.sectionTitle),
        ),
        const SizedBox(height: 2),
        Text(caption, style: PostingText.subtitle),
      ],
    );
  }
}
