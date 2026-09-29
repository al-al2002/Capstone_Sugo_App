import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/id_document_picker.dart';
import '../models/identity_verification.dart';

/// The mandatory ID + selfie step, shared by both onboarding flows.
///
/// ## Why this is one widget used twice, not two screens
///
/// The brief requires identical verification for technicians and clients. Two
/// copies would drift - a wording change here, a missing validation there -
/// and the drift would be invisible until someone compared them. Building it
/// once means the technician and the client are literally held to the same
/// standard, which is the property that matters.
///
/// The host flow supplies the state and the callbacks; this widget owns only
/// the layout and the copy. It renders the gate but does not enforce it: the
/// controller decides whether "Continue" is live, because the same rule also
/// governs the stepper, the resume logic and the submit call.
///
/// ## What the two parts are for
///
/// The ID alone proves a document exists. The selfie holding it is what ties
/// the document to the person submitting it - without it, a photo of someone
/// else's ID found online would pass. Neither half is useful alone, which is
/// why [IdentityCapture.isComplete] requires both.
class IdVerificationStep extends StatelessWidget {
  const IdVerificationStep({
    super.key,
    required this.capture,
    required this.validation,
    required this.onIdPicked,
    required this.onSelfiePicked,
    this.isUploading = false,
    this.rejection,
    this.submitted,
  });

  /// The two images picked so far.
  final IdentityCapture capture;

  /// Per-image validation errors.
  final IdentityValidation validation;

  final ValueChanged<XFile> onIdPicked;
  final ValueChanged<XFile> onSelfiePicked;

  final bool isUploading;

  /// A previous attempt an admin rejected. When present, the reviewer's note
  /// is shown at the top and the step becomes a retake.
  final IdentityVerification? rejection;

  /// A submission that has been filed and not rejected - pending or already
  /// approved. When present the pickers are replaced by a status panel,
  /// because an attempt under review cannot be edited and an approved one
  /// must not invite a pointless re-upload.
  final IdentityVerification? submitted;

  @override
  Widget build(BuildContext context) {
    if (submitted != null && !submitted!.isRejected) {
      return _SubmissionPanel(submission: submitted!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (rejection != null) ...<Widget>[
          _RejectionNotice(rejection: rejection!),
          const SizedBox(height: AppSizes.xl),
        ],

        Text(
          rejection != null ? 'Retake your photos' : 'Verify your identity',
          style: AppTextStyles.headline,
        ),
        const SizedBox(height: AppSizes.sm),
        const Text(
          'Every SUGO account is verified by a real person before it goes '
          'live. This keeps technicians and clients safe from each other.',
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.lg),

        // How much of this step is done, as a count.
        //
        // The two halves are far apart on a scrolling screen, so somebody who
        // has photographed their ID and scrolled to the selfie has no way to
        // see that the first half is already satisfied. Stating it at the top
        // is what stops the step feeling open-ended.
        _PartProgress(
          done:
              (capture.idDocument != null &&
                      validation.idDocumentError == null
                  ? 1
                  : 0) +
              (capture.selfie != null && validation.selfieError == null
                  ? 1
                  : 0),
        ),
        const SizedBox(height: AppSizes.xl),

        // ------------------------------------------------------- part one
        _PartHeader(
          index: 1,
          title: 'Government ID',
          subtitle: 'Any valid, unexpired government-issued ID.',
          isDone:
              capture.idDocument != null && validation.idDocumentError == null,
        ),
        const SizedBox(height: AppSizes.md),
        IdDocumentPicker(
          file: capture.idDocument,
          onPicked: onIdPicked,
          hasError: validation.idDocumentError != null,
          isUploading: isUploading,
          uploadLabel: 'Uploading your ID...',
          emptyTitle: 'Tap to add your ID photo',
          emptySubtitle: 'Camera or gallery',
        ),
        if (validation.idDocumentError != null)
          _FieldError(message: validation.idDocumentError!),

        const SizedBox(height: AppSizes.sm),
        const _Guidance(
          items: <String>[
            'All four corners visible',
            'Text sharp enough to read',
            'No glare across the photo or details',
          ],
        ),

        const SizedBox(height: AppSizes.xl),

        // ------------------------------------------------------- part two
        _PartHeader(
          index: 2,
          title: 'Selfie holding that ID',
          subtitle: 'Your face and the same ID, together in one photo.',
          isDone: capture.selfie != null && validation.selfieError == null,
        ),
        const SizedBox(height: AppSizes.md),
        IdDocumentPicker(
          file: capture.selfie,
          onPicked: onSelfiePicked,
          hasError: validation.selfieError != null,
          isUploading: isUploading,
          uploadLabel: 'Uploading your selfie...',
          emptyTitle: 'Tap to add your selfie with the ID',
          emptySubtitle: 'Hold the ID beside your face',
        ),
        if (validation.selfieError != null)
          _FieldError(message: validation.selfieError!),

        const SizedBox(height: AppSizes.sm),
        const _Guidance(
          items: <String>[
            'Your whole face in frame, nothing covering it',
            'The ID held beside your face, details facing the camera',
            'The same ID as the photo above',
          ],
        ),

        const SizedBox(height: AppSizes.xl),

        // The reason this step cannot be skipped, said once, plainly. Users
        // hand over a government ID far more readily when told what happens to
        // it than when asked to trust a form.
        const _PrivacyNote(),

        if (capture.isPartial) ...<Widget>[
          const SizedBox(height: AppSizes.lg),
          _MissingBanner(message: capture.missingLabel!),
        ],
      ],
    );
  }
}

/// Numbered heading for each half, with a tick once that half is valid.
class _PartHeader extends StatelessWidget {
  const _PartHeader({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.isDone,
  });

  final int index;
  final String title;
  final String subtitle;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.standard,
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: isDone ? AppColors.success : AppColors.primarySoft,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: isDone
              ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
              : Text(
                  '$index',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: AppTextStyles.caption),
            ],
          ),
        ),
      ],
    );
  }
}

/// The bullet list under each picker.
///
/// Placed *under* rather than above deliberately: it is a checklist for
/// reviewing the photo just taken, and most rejections are for exactly these
/// three faults.
class _Guidance extends StatelessWidget {
  const _Guidance({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSizes.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map(
              (String item) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.check_circle_outline_rounded,
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(item, style: AppTextStyles.caption)),
                  ],
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 15,
            color: AppColors.error,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when exactly one of the two images is present.
///
/// This is the state worth nudging hardest on: it looks like progress but
/// submits to nothing, and a disabled Continue button with no explanation is
/// how a user concludes the app is broken.
class _MissingBanner extends StatelessWidget {
  const _MissingBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              message,
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
    );
  }
}

/// The reviewer's rejection note, verbatim.
///
/// Shown verbatim on purpose. A generic "your ID was rejected" gives the user
/// nothing to change, so they resubmit the same photos and are rejected again -
/// which is how a verification queue fills up with the same person three times.
class _RejectionNotice extends StatelessWidget {
  const _RejectionNotice({required this.rejection});

  final IdentityVerification rejection;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: AppColors.error,
              ),
              const SizedBox(width: AppSizes.sm),
              const Text(
                'We could not verify your ID',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            rejection.rejectionReason,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          const Text(
            'Take both photos again and resubmit. There is no limit on '
            'attempts.',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}

/// Replaces the pickers once a submission is filed.
///
/// Two states, and the difference matters to the user: `pending` means a
/// reviewer has not looked yet, `approved` means identity is settled and only
/// the remaining steps stand between them and a live account.
class _SubmissionPanel extends StatelessWidget {
  const _SubmissionPanel({required this.submission});

  final IdentityVerification submission;

  @override
  Widget build(BuildContext context) {
    final bool approved = submission.isApproved;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSizes.xl),
          decoration: BoxDecoration(
            color: approved ? AppColors.successSoft : AppColors.warningSoft,
            borderRadius: BorderRadius.circular(AppSizes.panelRadius),
          ),
          child: Column(
            children: <Widget>[
              Icon(
                approved ? Icons.verified_rounded : Icons.schedule_rounded,
                size: 34,
                color: approved ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(height: AppSizes.md),
              Text(
                approved
                    ? 'Your ID has been approved'
                    : 'Your ID is being reviewed',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                approved
                    ? 'Identity confirmed. Finish the remaining steps and your '
                          'account goes live straight away.'
                    : 'A member of the SUGO team is checking your documents. '
                          'This usually takes less than a day.',
                textAlign: TextAlign.center,
                style: AppTextStyles.subtitle,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),

        // The point of the whole panel: review runs in parallel, so the flow
        // is not blocked. The Continue button below is live - hiding it while
        // making this promise is what stranded people on this screen.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.arrow_forward_rounded,
              size: 15,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                approved
                    ? 'Tap Continue to carry on with the rest of your '
                          'registration.'
                    : 'You do not have to wait. Tap Continue and carry on with '
                          'the remaining steps while we review.',
                style: AppTextStyles.caption,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// What happens to the images, and where they are kept.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.lock_outline_rounded,
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSizes.sm),
          const Expanded(
            child: Text(
              'Both photos are stored privately and are visible only to the '
              'SUGO reviewer checking your account. They are never shown to '
              'clients or technicians.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "1 of 2 photos added", with a two-segment rail.
///
/// Uses the success tone rather than the brand blue, because both segments
/// filling is the thing that unblocks the flow - and green is what the rest of
/// the app already uses to mean "this requirement is satisfied".
class _PartProgress extends StatelessWidget {
  const _PartProgress({required this.done});

  final int done;

  @override
  Widget build(BuildContext context) {
    final bool complete = done == 2;

    return Row(
      children: <Widget>[
        Expanded(
          child: Row(
            children: List<Widget>.generate(2, (int i) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 1 ? 0 : 6),
                  child: AnimatedContainer(
                    duration: AppMotion.base,
                    curve: AppMotion.standard,
                    height: AppSizes.stepRailHeight,
                    decoration: BoxDecoration(
                      color: i < done ? AppColors.success : AppColors.divider,
                      borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Text(
          complete ? 'Both photos added' : '$done of 2 photos added',
          style: AppTextStyles.micro.copyWith(
            fontWeight: FontWeight.w700,
            color: complete ? AppColors.success : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
