import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/verification_document.dart';
import '../services/technician_registration_service.dart';

/// Step 5 of the technician flow: the clearance, plus optional trust-boosters.
///
/// ## One required, two not
///
/// The NBI or police clearance gates the step. The certificate and the
/// portfolio do not, and the screen has to make that split obvious - a
/// technician with no TESDA paper and no photos of past work should never
/// think the platform is closed to them.
///
/// The split is between **safety and skill**. A technician is admitted to
/// somebody's home, and the clearance is what the client is trusting when they
/// open the door. A certificate and a portfolio describe how good the work is,
/// which raises `verification_tier` - a thing clients see - rather than
/// unlocking anything.
class VerificationDocumentsStep extends StatefulWidget {
  const VerificationDocumentsStep({
    super.key,
    required this.documents,
    required this.service,
    required this.onChanged,
  });

  final List<VerificationDocument> documents;
  final TechnicianRegistrationService service;

  /// Called after an upload or delete so the host can refresh its list.
  final Future<void> Function() onChanged;

  @override
  State<VerificationDocumentsStep> createState() =>
      _VerificationDocumentsStepState();
}

class _VerificationDocumentsStepState extends State<VerificationDocumentsStep> {
  VerificationDocType? _uploading;

  List<VerificationDocument> _of(VerificationDocType type) {
    return widget.documents
        .where((VerificationDocument d) => d.docType == type)
        .toList(growable: false);
  }

  Future<void> _pickAndUpload(VerificationDocType type) async {
    final XFile? picked = await _pickImage(type);
    if (picked == null) return;

    String? caption;
    if (type.allowsCaption && mounted) {
      caption = await _askCaption();
    }

    setState(() => _uploading = type);

    try {
      await widget.service.uploadDocument(
        docType: type,
        file: picked,
        caption: caption,
      );
      await widget.onChanged();

      if (!mounted) return;
      UiFeedback.showSuccess(context, '${type.label} uploaded.');
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<XFile?> _pickImage(VerificationDocType type) async {
    try {
      return await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // Portfolio shots are promotional and can be compressed harder than a
        // certificate, whose small print a reviewer has to read.
        maxWidth: type == VerificationDocType.portfolio ? 1600 : 2400,
        imageQuality: type == VerificationDocType.portfolio ? 80 : 90,
      );
    } catch (error) {
      if (kDebugMode) debugPrint('VerificationDocumentsStep pick: $error');
      if (!mounted) return null;
      UiFeedback.showError(context, 'Could not open the picker. Try again.');
      return null;
    }
  }

  Future<String?> _askCaption() async {
    final TextEditingController controller = TextEditingController();

    final String? caption = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Describe this work'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(
            hintText: 'e.g. Aircon compressor replacement',
          ),
        ),
        actions: <Widget>[
          // Skippable: the caption is optional on an already-optional upload,
          // and forcing one would turn a two-tap action into a writing task.
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Skip'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    controller.dispose();
    return caption;
  }

  Future<void> _delete(VerificationDocument doc) async {
    try {
      await widget.service.deleteDocument(doc);
      await widget.onChanged();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Clearance and credentials', style: AppTextStyles.headline),
        const SizedBox(height: AppSizes.sm),
        const Text(
          'An NBI or police clearance is required - clients are letting you '
          'into their home. The other two are optional, and they win you jobs: '
          'clients see those badges when choosing a technician.',
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.lg),

        _tierExplainer(),
        const SizedBox(height: AppSizes.xl),

        ...VerificationDocType.values.map(_section),

        const SizedBox(height: AppSizes.sm),
        Center(
          child: TextButton(
            onPressed: null,
            child: Text(
              'The optional two can be added later from your profile',
              style: AppTextStyles.caption,
            ),
          ),
        ),
      ],
    );
  }

  /// What each tier requires, so the uploads have a visible purpose.
  Widget _tierExplainer() {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: VerificationTier.values
            .map((VerificationTier tier) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      tier == VerificationTier.certifiedPro
                          ? Icons.workspace_premium_rounded
                          : Icons.verified_outlined,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: AppTextStyles.caption,
                          children: <TextSpan>[
                            TextSpan(
                              text: '${tier.label}: ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            TextSpan(text: tier.blurb),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  Widget _section(VerificationDocType type) {
    final List<VerificationDocument> docs = _of(type);
    final bool busy = _uploading == type;
    final bool canAdd = type.allowsMultiple || docs.isEmpty;

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
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accentSofter,
                  borderRadius: BorderRadius.circular(AppSizes.sm),
                ),
                child: Icon(type.icon, size: 17, color: AppColors.accentDark),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          type.label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: AppSizes.sm),
                        // Marked on every section, not just the required one.
                        // Labelling one and leaving the rest bare makes the
                        // others ambiguous rather than optional.
                        _RequirementTag(
                          required: type == VerificationDocType.nbiClearance,
                          satisfied: docs.isNotEmpty,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(type.blurb, style: AppTextStyles.caption),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (canAdd)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 21),
                  color: AppColors.primary,
                  onPressed: () => _pickAndUpload(type),
                ),
            ],
          ),

          if (docs.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            const Divider(),
            ...docs.map(_documentRow),
          ],
        ],
      ),
    );
  }

  Widget _documentRow(VerificationDocument doc) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.sm),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: doc.status.tone,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  doc.caption?.isNotEmpty ?? false
                      ? doc.caption!
                      : doc.docType.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  doc.status.label,
                  style: AppTextStyles.caption.copyWith(color: doc.status.tone),
                ),
              ],
            ),
          ),
          // Only a pending document can be withdrawn. Once a reviewer has
          // ruled, removing it would erase the audit trail - including a
          // rejection for a forged certificate.
          if (doc.canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: AppColors.textSecondary,
              onPressed: () => _delete(doc),
            ),
        ],
      ),
    );
  }
}

/// The "Required" / "Optional" pill on a document section.
///
/// Turns green once a required document is present, so the one blocking item
/// on the step stops shouting the moment it is satisfied.
class _RequirementTag extends StatelessWidget {
  const _RequirementTag({required this.required, required this.satisfied});

  final bool required;
  final bool satisfied;

  @override
  Widget build(BuildContext context) {
    final bool done = required && satisfied;

    final (Color tint, Color ink, String label) = required
        ? done
              ? (AppColors.successSoft, AppColors.success, 'Added')
              : (AppColors.primarySoft, AppColors.primaryDark, 'Required')
        : (AppColors.divider, AppColors.textSecondary, 'Optional');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      ),
    );
  }
}
