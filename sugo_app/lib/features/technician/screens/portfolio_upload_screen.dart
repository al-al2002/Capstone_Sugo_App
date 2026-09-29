import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/primary_button.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../services/onboarding_service.dart';

/// Optional final step: show off past work.
///
/// Deliberately skippable and never a gate. Verification is already granted by
/// this point - the assessment set `is_verified` - so blocking the dashboard on
/// a marketing nicety would be hostile. Both buttons lead to the same place.
///
/// Photos go to the public `job-photos` bucket rather than the private
/// `technician-ids` one, because portfolio work is meant to be seen by clients.
class PortfolioUploadScreen extends StatefulWidget {
  const PortfolioUploadScreen({super.key, required this.onDone});

  /// Called on both Save and Skip.
  final VoidCallback onDone;

  @override
  State<PortfolioUploadScreen> createState() => _PortfolioUploadScreenState();
}

class _PortfolioUploadScreenState extends State<PortfolioUploadScreen> {
  final OnboardingService _service = OnboardingService();
  final TextEditingController _description = TextEditingController();

  XFile? _photo;
  bool _isSaving = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final XFile? file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (file == null) return;
      setState(() => _photo = file);
    } catch (_) {
      if (!mounted) return;
      UiFeedback.showError(context, 'Could not open the gallery.');
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final String description = _description.text.trim();
    if (_photo == null && description.isEmpty) {
      widget.onDone();
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _service.addPortfolioItem(
        photo: _photo,
        description: description.isEmpty ? null : description,
      );
      if (!mounted) return;
      widget.onDone();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
        Text('Show your work', style: AppTextStyles.headline),
        const SizedBox(height: AppSizes.xs),
        Text(
          'Optional. A photo of a repair you are proud of helps clients pick '
          'you, but it does not affect your ranking or your tier.',
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.xl),

        InkWell(
          onTap: _pick,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              color: AppColors.primarySofter,
              borderRadius: BorderRadius.circular(AppSizes.tileRadius),
              border: Border.all(color: AppColors.primarySoft, width: 1.4),
            ),
            clipBehavior: Clip.antiAlias,
            child: _photo == null
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 30,
                        color: AppColors.primary,
                      ),
                      SizedBox(height: AppSizes.sm),
                      Text(
                        'Add a photo of your work',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  )
                : _PhotoPreview(file: _photo!),
          ),
        ),

        const SizedBox(height: AppSizes.lg),
        TextField(
          controller: _description,
          maxLines: 3,
          maxLength: 240,
          decoration: const InputDecoration(
            hintText:
                'What was the job? e.g. Replaced a compressor on a '
                'split-type aircon.',
          ),
        ),

        const SizedBox(height: AppSizes.md),
        PrimaryButton(
          label: 'Save and finish',
          isLoading: _isSaving,
          onPressed: _save,
        ),
        const SizedBox(height: AppSizes.sm),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _isSaving ? null : widget.onDone,
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: const Text('Skip for now'),
          ),
        ),
      ],
    );
  }
}

/// Renders a picked photo from bytes.
///
/// `Image.file` needs a filesystem, which web does not have. Reading bytes and
/// using `Image.memory` is the one approach that works on every platform.
class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          );
        }
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
  }
}
