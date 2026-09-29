import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/id_document_picker.dart';
import '../../../core/widgets/primary_button.dart';

/// The identity step, shared by both roles.
///
/// ## Why both roles land here
///
/// A client hands a stranger their home address and lets them into the house.
/// Verifying both sides is what makes that exchange reasonable. The gate is
/// lighter for a client - upload and finish - while a technician continues to
/// the specialisation and assessment steps afterwards.
///
/// ## Controlled, and it uploads nothing
///
/// The picked file is handed up through [onPicked] and held in memory by
/// `RegistrationController`. The actual upload happens once, at the very end,
/// alongside the single transactional write that creates the account. Abandon
/// here and neither a database row nor a stored file exists.
class ClientIdVerificationScreen extends StatelessWidget {
  const ClientIdVerificationScreen({
    super.key,
    required this.file,
    required this.onPicked,
    required this.onContinue,
    this.validationError,
    this.isSubmitting = false,
    this.isTechnician = false,
  });

  final XFile? file;
  final ValueChanged<XFile> onPicked;
  final VoidCallback onContinue;
  final String? validationError;
  final bool isSubmitting;

  /// Changes the button label only: a technician has further steps to go,
  /// a client is finishing their registration with this tap.
  final bool isTechnician;

  bool get _canContinue =>
      file != null && validationError == null && !isSubmitting;

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
        Text('Verify your identity', style: AppTextStyles.headline),
        const SizedBox(height: AppSizes.xs),
        Text(
          isTechnician
              ? 'Upload a clear photo of a valid government ID. Clients see a '
                    'verified badge on technicians who complete this.'
              : 'Upload a valid government ID. Technicians come to your home, '
                    'so we verify both sides before anyone is dispatched.',
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.xl),

        IdDocumentPicker(
          file: file,
          hasError: validationError != null,
          isUploading: isSubmitting,
          onPicked: onPicked,
          uploadLabel: 'Finishing your registration...',
        ),

        if (validationError != null) ...<Widget>[
          const SizedBox(height: AppSizes.md),
          _ErrorPanel(message: validationError!),
        ],

        const SizedBox(height: AppSizes.xl),
        const _PrivacyPanel(),

        const SizedBox(height: AppSizes.xl),
        PrimaryButton(
          label: isTechnician ? 'Continue' : 'Submit and finish',
          isLoading: isSubmitting,
          onPressed: _canContinue ? onContinue : null,
        ),
        const SizedBox(height: AppSizes.sm),
        Text(
          file == null
              ? 'Pick an image to continue.'
              : validationError != null
              ? 'Fix the problem above to continue.'
              : 'Your ID is stored privately and is never shown to anyone '
                    'you book with.',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(fontSize: 12),
        ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.md),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 17,
            color: AppColors.error,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
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

class _PrivacyPanel extends StatelessWidget {
  const _PrivacyPanel();

  @override
  Widget build(BuildContext context) {
    const List<String> points = <String>[
      'JPG or PNG, under 5 MB',
      'Stored in a private bucket, not a public link',
      'Never visible to technicians or other clients',
    ];

    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
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
              const Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSizes.sm),
              Text('How we handle it', style: AppTextStyles.label),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          ...points.map(
            (String point) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Text(
                      point,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
