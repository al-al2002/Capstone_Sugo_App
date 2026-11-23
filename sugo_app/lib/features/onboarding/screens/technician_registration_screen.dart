import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../controllers/technician_registration_controller.dart';
import '../models/registration_status.dart';
import '../models/specialization_catalog.dart';
import '../services/technician_registration_service.dart';
import '../widgets/id_verification_step.dart';
import '../widgets/location_pin_step.dart';
import '../widgets/onboarding_scaffold.dart';
import '../widgets/specialization_picker.dart';
import '../widgets/work_type_step.dart';
import 'assessment_screen.dart';
import 'verification_documents_step.dart';
import '../../../core/widgets/sugo_staggered_column.dart';
import '../widgets/onboarding_step_intro.dart';

/// The seven-step technician registration flow.
///
/// account -> ID + selfie -> specialisation -> assessment -> documents ->
/// location -> review
///
/// The screen owns navigation and step bodies only. Every rule about what is
/// required lives in [TechnicianRegistrationController], so the same rule
/// governs the button, the progress rail and the final submit.
class TechnicianRegistrationScreen extends StatelessWidget {
  const TechnicianRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TechnicianRegistrationController>(
      create: (_) => TechnicianRegistrationController()..load(),
      child: const _TechnicianRegistrationView(),
    );
  }
}

class _TechnicianRegistrationView extends StatelessWidget {
  const _TechnicianRegistrationView();

  @override
  Widget build(BuildContext context) {
    final TechnicianRegistrationController controller = context
        .watch<TechnicianRegistrationController>();

    if (controller.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Already filed. There is nothing to edit until a reviewer rules.
    if (controller.status == RegistrationStatus.pendingReview) {
      return const PendingReviewScreen(
        status: RegistrationStatus.pendingReview,
      );
    }

    return OnboardingScaffold(
      controller: controller,
      onSaveAndExit: () async {
        await controller.saveAndExit();
        if (!context.mounted) return;
        Navigator.of(context).maybePop();
      },
      continueLabel: _continueLabel(controller),
      onContinue: () => _onContinue(context, controller),
      child: _body(context, controller),
    );
  }

  // The footer used to be hidden on the identity step once a submission was
  // queued, on the reasoning that there was nothing to press. That was wrong:
  // the panel tells the user they can carry on while the ID is reviewed, and
  // hiding the only way forward stranded them on the screen. Review runs in
  // parallel with the remaining steps by design - see
  // 20260907000005_review_during_flow.sql, which makes the database agree.

  String? _continueLabel(TechnicianRegistrationController controller) {
    return switch (controller.currentStep) {
      OnboardingStepId.identity when !controller.hasSubmittedIdentity =>
        'Submit ID for verification',
      // Already filed: this is an ordinary "move on to the next step".
      OnboardingStepId.identity => 'Continue',
      OnboardingStepId.documents => 'Continue',
      OnboardingStepId.review => 'Submit for review',
      _ => null,
    };
  }

  Future<void> _onContinue(
    BuildContext context,
    TechnicianRegistrationController controller,
  ) async {
    // The identity step submits rather than advancing, because the upload has
    // to succeed before the step counts as passed.
    if (controller.currentStep == OnboardingStepId.identity &&
        !controller.hasSubmittedIdentity) {
      final bool ok = await controller.submitIdentity();
      if (!context.mounted) return;
      if (ok) {
        UiFeedback.showSuccess(
          context,
          'ID submitted. You can carry on while we review it.',
        );
      }
      return;
    }

    if (controller.isLastStep) {
      final bool ok = await controller.submitForReview();
      if (!context.mounted) return;
      if (ok) {
        UiFeedback.showSuccess(context, 'Registration submitted for review.');
      }
      return;
    }

    await controller.next();
  }

  Widget _body(
    BuildContext context,
    TechnicianRegistrationController controller,
  ) {
    return switch (controller.currentStep) {
      OnboardingStepId.account => const _AccountRecap(),

      OnboardingStepId.identity => IdVerificationStep(
        capture: controller.capture,
        validation: controller.validation,
        onIdPicked: controller.pickIdDocument,
        onSelfiePicked: controller.pickSelfie,
        isUploading: controller.isBusy,
        rejection: controller.rejection,
        // Any filed attempt that is not a rejection - pending or approved.
        submitted: controller.filedSubmission,
      ),

      OnboardingStepId.specialization => SpecializationPicker(
        selected: controller.selected,
        onChanged: controller.setSelection,
      ),

      OnboardingStepId.assessment => _AssessmentList(controller: controller),

      OnboardingStepId.documents => VerificationDocumentsStep(
        documents: controller.documents,
        service: controller.service,
        onChanged: controller.refreshDocuments,
      ),

      OnboardingStepId.workType => WorkTypeStep(
        homeService: controller.homeService,
        shopRepair: controller.shopRepair,
        onHomeServiceChanged: controller.setHomeService,
        onShopRepairChanged: controller.setShopRepair,
        shopPlace: controller.shopPlace,
        onShopPlaceChanged: controller.setShopPlace,
        shopName: controller.shopName,
        onShopNameChanged: controller.setShopName,
        rainTravel: controller.rainTravel,
        trafficTravel: controller.trafficTravel,
        onRainTravelChanged: controller.setRainTravel,
        onTrafficTravelChanged: controller.setTrafficTravel,
      ),

      OnboardingStepId.location => LocationPinStep(
        place: controller.basePlace,
        onPlaceChanged: controller.setBasePlace,
        radiusKm: controller.radiusKm,
        onRadiusChanged: controller.setRadius,
        radiusOptions: TechnicianRegistrationService.radiusOptions,
        // Worded for the work chosen on the step before (2026-11-17).
        title: controller.homeService
            ? 'Where do you start from?'
            : 'Your service area',
        subtitle: controller.homeService
            ? 'Pin your home base or shop. Home Service jobs are matched by '
                  'distance from this point, within your travel radius.'
            : 'It starts at your shop. Clients within this distance are '
                  'matched with you.',
      ),

      OnboardingStepId.review => _TechnicianReview(controller: controller),

      // Not part of the technician flow.
      OnboardingStepId.email => const SizedBox.shrink(),
    };
  }
}

/// Step 1. The account already exists - sign-up created it - so this is a
/// confirmation rather than a form.
///
/// It is kept as a visible step rather than skipped because the stepper
/// promises seven steps and silently starting on step 2 reads as a bug. It
/// also gives the flow somewhere to explain what is coming.
class _AccountRecap extends StatelessWidget {
  const _AccountRecap();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const OnboardingStepIntro(
          icon: Icons.engineering_rounded,
          title: 'Become a SUGO technician',
          subtitle:
              'Your account is created. Here is what is left before you can '
              'take jobs.',
        ),
        const SizedBox(height: AppSizes.xl),
        SugoStaggeredColumn(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ...<({String title, String blurb, IconData icon, bool required})>[
              (
                title: 'Verify your identity',
                blurb: 'A government ID and a selfie holding it. Required.',
                icon: Icons.badge_outlined,
                required: true,
              ),
              (
                title: 'Choose your specialisations',
                blurb: 'The devices and brands you repair. Required.',
                icon: Icons.build_outlined,
                required: true,
              ),
              (
                title: 'Pass a skill assessment',
                blurb: 'A short quiz for each specialisation. Required.',
                icon: Icons.quiz_outlined,
                required: true,
              ),
              // Was "Certificates, NBI clearance, portfolio. Optional.": the
              // clearance has been required since 20260922000001 - the documents
              // step blocks without it and the reviewer treats it as mandatory.
              // Corrected 2026-11-17.
              (
                title: 'Upload your clearance',
                blurb:
                    'An NBI or police clearance. Required. Certificates and '
                    'portfolio photos are optional.',
                icon: Icons.workspace_premium_outlined,
                required: true,
              ),
              (
                title: 'Set your service area',
                blurb: 'Where you are based and how far you travel. Required.',
                icon: Icons.map_outlined,
                required: true,
              ),
            ].map(
              (
                ({String title, String blurb, IconData icon, bool required})
                item,
              ) => Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: item.required
                              ? const <Color>[
                                  AppColors.primarySoft,
                                  AppColors.cyanSoft,
                                ]
                              : const <Color>[
                                  AppColors.accentSofter,
                                  AppColors.accentSoft,
                                ],
                        ),
                        borderRadius: BorderRadius.circular(AppSizes.sm),
                      ),
                      child: Icon(
                        item.icon,
                        size: 18,
                        color: item.required
                            ? AppColors.primary
                            : AppColors.accentDark,
                      ),
                    ),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(item.blurb, style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.md),
        Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            color: AppColors.primarySofter,
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.bookmark_outline_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  'You can stop after the ID check and pick up where you left '
                  'off later.',
                  style: AppTextStyles.caption,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Step 4. One card per specialisation, each leading to its own quiz.
class _AssessmentList extends StatelessWidget {
  const _AssessmentList({required this.controller});

  final TechnicianRegistrationController controller;

  @override
  Widget build(BuildContext context) {
    final List<PendingAssessment> items = controller.assessments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const OnboardingStepIntro(
          icon: Icons.quiz_rounded,
          title: 'Prove your skills',
          subtitle:
              'One short assessment per skill, not per brand. Passing it '
              'qualifies you for every brand you picked in that group. Score '
              '70% to qualify, 90% to be listed as an expert.',
        ),
        const SizedBox(height: AppSizes.lg),

        // The requirement, said out loud: every card must be cleared before
        // the button unlocks, and how far along they are.
        Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            color: controller.hasPassedAllAssessments
                ? AppColors.successSoft
                : AppColors.warningSoft,
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                controller.hasPassedAllAssessments
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
                size: 17,
                color: controller.hasPassedAllAssessments
                    ? AppColors.success
                    : AppColors.warning,
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                // Every skill must be proven since 2026-11-22 - one pass
                // used to be enough. A failed one can be retaken after 24
                // hours, or removed from its card below.
                child: Text(
                  controller.hasPassedAllAssessments
                      ? 'All ${items.length} passed. Every skill you listed '
                            'is verified, so you can continue.'
                      : items.length == 1
                      ? 'Pass this assessment to continue.'
                      : 'Pass all ${items.length} to continue - '
                            '${controller.passedAssessments.length} of '
                            '${items.length} done. Failed one? Retake it after '
                            '24 hours, or remove that skill.',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),

        ...items.map(
          (PendingAssessment item) =>
              _AssessmentCard(item: item, controller: controller),
        ),
      ],
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({required this.item, required this.controller});

  final PendingAssessment item;
  final TechnicianRegistrationController controller;

  @override
  Widget build(BuildContext context) {
    final bool locked = item.isCoolingDown;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(
          color: item.isPassed ? AppColors.success : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: item.isPassed
                      ? AppColors.successSoft
                      : AppColors.primarySofter,
                  borderRadius: BorderRadius.circular(AppSizes.sm),
                ),
                child: Icon(
                  item.track.icon,
                  size: 19,
                  color: item.isPassed ? AppColors.success : AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.track.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(_statusLine(), style: AppTextStyles.caption),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              if (item.isPassed)
                const Icon(
                  Icons.verified_rounded,
                  size: 20,
                  color: AppColors.success,
                )
              else
                TextButton(
                  onPressed: locked || controller.isBusy
                      ? null
                      : () => _startQuiz(context),
                  child: Text(item.hasAttempted ? 'Retake' : 'Start'),
                ),
            ],
          ),

          // What this one sitting covers. Showing it is the whole reason the
          // grouping is worth having - otherwise a technician sees "one
          // assessment" and assumes their other brands still need work.
          if (item.specializationCount > 1) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.md,
                vertical: AppSizes.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.primarySofter,
                borderRadius: BorderRadius.circular(AppSizes.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.done_all_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${item.coverageLabel} — '
                      '${_coveredLabels().join(', ')}',
                      style: AppTextStyles.caption,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Failed it, and not the only skill: offer to drop it rather than
          // wait 24 hours (2026-11-22, when every assessment became
          // required). Never offered before a first attempt - removing a
          // skill should be a decision after trying, not a way round it.
          if (!item.isPassed &&
              item.hasAttempted &&
              !controller.isOnlyTrack(item.track)) ...<Widget>[
            const SizedBox(height: AppSizes.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey<String>('remove-track-${item.track.wire}'),
                onPressed: controller.isBusy ? null : () => _remove(context),
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                label: const Text('Remove this skill'),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context) async {
    final int brands = _coveredLabels().length;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Remove ${item.track.label}?'),
        content: Text(
          'The $brands ${brands == 1 ? 'brand' : 'brands'} you picked under '
          'it come off your profile, and you will not be matched for these '
          'jobs. Skills can only be added during registration.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.removeTrack(item.track);
  }

  /// The declared (device, brand) pairs this track qualifies.
  List<String> _coveredLabels() {
    return controller.selected
        .where((TechnicianSpecialization s) => s.track == item.track)
        .map((TechnicianSpecialization s) => s.displayLabel)
        .toList(growable: false);
  }

  String _statusLine() {
    if (item.isPassed) {
      final String level = item.skillLevel?.label ?? 'Qualified';
      final String score = item.lastScore == null
          ? ''
          : ' · ${item.lastScore!.round()}%';
      return '$level$score';
    }
    if (item.isCoolingDown) {
      return '${item.cooldownLabel} · scored ${item.lastScore?.round() ?? 0}%';
    }
    if (item.hasAttempted) {
      return 'Last attempt ${item.lastScore?.round() ?? 0}% · ready to retake';
    }
    return 'Not started · 70% to pass';
  }

  Future<void> _startQuiz(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AssessmentScreen(assessment: item, controller: controller),
      ),
    );
  }
}

/// Step 7. Everything about to be submitted, in one place.
class _TechnicianReview extends StatelessWidget {
  const _TechnicianReview({required this.controller});

  final TechnicianRegistrationController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const OnboardingStepIntro(
          icon: Icons.fact_check_rounded,
          title: 'Check and submit',
          subtitle:
              'A SUGO reviewer checks your ID before your account goes live. '
              'This usually takes under a day.',
        ),
        const SizedBox(height: AppSizes.xl),

        _ReviewSection(
          title: 'Identity',
          icon: Icons.badge_outlined,
          rows: <String>[
            controller.hasSubmittedIdentity
                ? 'ID and selfie submitted'
                : 'Not submitted',
          ],
          isComplete: controller.hasSubmittedIdentity,
        ),

        _ReviewSection(
          title: 'Specialisations',
          icon: Icons.build_outlined,
          rows: controller.selected
              .map(
                (TechnicianSpecialization s) =>
                    '${s.displayLabel}'
                    '${s.verified ? ' · ${s.skillLevel?.label ?? 'Verified'}' : ' · not yet assessed'}',
              )
              .toList(),
          isComplete: controller.selected.isNotEmpty,
        ),

        _ReviewSection(
          title: 'Assessments',
          icon: Icons.quiz_outlined,
          rows: <String>[
            '${controller.passedAssessments.length} of '
                '${controller.assessments.length} skill '
                '${controller.assessments.length == 1 ? 'assessment' : 'assessments'} passed',
            ...controller.passedAssessments.map(
              (PendingAssessment a) =>
                  '${a.track.label} · ${a.skillLevel?.label ?? 'Qualified'}',
            ),
            if (controller.outstandingAssessments.isNotEmpty)
              'Pass the rest, or remove those skills, to submit',
          ],
          isComplete: controller.hasPassedAllAssessments,
        ),

        _ReviewSection(
          title: 'Credentials',
          icon: Icons.workspace_premium_outlined,
          rows: controller.documents.isEmpty
              ? <String>['NBI or police clearance not uploaded']
              : controller.documents
                    .map(
                      (dynamic d) => '${d.docType.label} · ${d.status.label}',
                    )
                    .toList()
                    .cast<String>(),
          // The clearance gates the step, so the recap has to show a missing
          // one as missing. The other two documents stay optional, which is
          // why the section is not flagged wholesale.
          isComplete: controller.hasNbiClearance,
          isOptional: false,
        ),

        _ReviewSection(
          title: 'Work type',
          icon: Icons.work_outline_rounded,
          rows: <String>[
            controller.workTypeLabel,
            if (controller.shopRepair)
              controller.shopPlace == null
                  ? 'Shop not pinned'
                  : (controller.shopName.trim().isEmpty
                        ? 'Shop pinned on the map'
                        : '${controller.shopName.trim()} · pinned on the map'),
            controller.travelConditionsLabel,
          ],
          isComplete: controller.canLeaveWorkTypeStep,
        ),

        _ReviewSection(
          title: 'Service area',
          icon: Icons.map_outlined,
          rows: <String>[
            if (controller.basePlace != null)
              controller.basePlace!.displayText
            else
              'Not set',
            '${controller.radiusKm.toStringAsFixed(0)} km radius',
          ],
          isComplete: controller.hasBaseLocation,
        ),

        const SizedBox(height: AppSizes.lg),
        Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            color: AppColors.primarySofter,
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  'Submitting locks your ID photos for review. You will be '
                  'notified once a reviewer has checked them.',
                  style: AppTextStyles.caption,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.title,
    required this.icon,
    required this.rows,
    required this.isComplete,
    this.isOptional = false,
  });

  final String title;
  final IconData icon;
  final List<String> rows;
  final bool isComplete;
  final bool isOptional;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 17, color: AppColors.primary),
              const SizedBox(width: AppSizes.sm),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (isOptional)
                const Text('Optional', style: AppTextStyles.caption)
              else
                Icon(
                  isComplete
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
                  size: 16,
                  color: isComplete ? AppColors.success : AppColors.error,
                ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          ...rows.map(
            (String row) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $row', style: AppTextStyles.caption),
            ),
          ),
        ],
      ),
    );
  }
}
