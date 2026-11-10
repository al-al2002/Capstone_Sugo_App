import 'package:flutter/material.dart';
import '../../../core/constants/app_sizes.dart';
import '../models/job.dart';
import '../models/job_enums.dart';
import '../providers/job_posting_provider.dart';
import '../theme/posting_text.dart';
import '../widgets/photo_picker_row.dart';
import '../widgets/posting_field.dart';
import '../widgets/posting_scaffold.dart';
import 'client_review_screen.dart';
import '../../../core/constants/app_colors.dart';
import '../models/labor_price_catalog.dart';

/// Step 5 of 5: the last look before the job goes out to technicians.
///
/// Photos and notes are collected here rather than earlier because both are
/// afterthoughts by nature - a client knows what else to mention once they can
/// see everything else they have said. The summary above the button is the
/// same four facts a technician will judge the job on.
class ReviewAndPostScreen extends StatefulWidget {
  const ReviewAndPostScreen({super.key, required this.posting});

  final JobPostingProvider posting;

  @override
  State<ReviewAndPostScreen> createState() => _ReviewAndPostScreenState();
}

class _ReviewAndPostScreenState extends State<ReviewAndPostScreen> {
  late final TextEditingController _notes = TextEditingController(
    text: widget.posting.draft.notes ?? '',
  );

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// Hands the draft to the matching screen and leaves immediately.
  ///
  /// This used to `await posting.submit()` here, which meant the photo upload,
  /// the insert and the matcher all ran behind a spinner *inside the button* -
  /// a dead screen for several seconds - and the matching animation then got
  /// perhaps a frame of screen time, because by the time it appeared the work
  /// it illustrates had already finished.
  ///
  /// Now the navigation is synchronous and the work happens under the loader,
  /// so the animation covers the wait it was built for.
  void _submit() {
    widget.posting.setNotes(_notes.text);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ClientReviewScreen.postDraft(draft: widget.posting),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.posting,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final JobPostingProvider posting = widget.posting;

    final bool editing = posting.isEditing;

    return PostingScaffold(
      step: 5,
      title: editing ? 'Review your changes' : 'Review & post',
      subtitle: editing
          ? 'Saving updates your post and finds a fresh top 3 for it.'
          : 'Last look before we rank the three best technicians near you.',
      stepName: 'Review',
      ctaLabel: posting.draft.servicePath == ServicePath.itCommunity
          ? 'Post'
          : editing
          ? 'Save & find technicians'
          : 'Find technician',
      ctaHint: 'Set a location on the map to post this job.',
      onCta: posting.canSubmit ? _submit : null,
      children: <Widget>[
        const PostingLabel('Photos (optional)'),
        const SizedBox(height: AppSizes.xs),
        // Says what the photos are *for*. People skip an optional field unless
        // they can see the benefit, and a technician who can see the fault
        // before they set off brings the right part with them.
        const Text(
          'Photos help technicians understand the problem before they '
          'arrive — and get you a more accurate price.',
          style: PostingText.subtitle,
        ),
        const SizedBox(height: AppSizes.md),
        PhotoPickerRow(
          photos: posting.photos,
          existingUrls: posting.keptPhotoUrls,
          onRemoveExisting: posting.removeKeptPhoto,
          onAdd: posting.addPhoto,
          onRemove: posting.removePhoto,
          maxPhotos: JobPostingProvider.maxPhotos,
        ),

        const SizedBox(height: AppSizes.xl),
        const PostingLabel('Additional notes (optional)'),
        const SizedBox(height: AppSizes.sm),
        TextField(
          controller: _notes,
          maxLines: 3,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Anything else the technician should know...',
            counterText: '',
          ),
        ),

        const SizedBox(height: AppSizes.lg),
        _MatchPromise(
          editing: editing,
          isTechnicianCommunity:
              posting.draft.servicePath == ServicePath.itCommunity,
        ),

        const SizedBox(height: AppSizes.lg),
        _Summary(posting: posting),
      ],
    );
  }
}

/// What happens the moment the button is pressed.
///
/// A soft navy wash, not a button colour: this is a reassurance, and the
/// flow's filled colours are reserved for things the client chose or is about
/// to press.
class _MatchPromise extends StatelessWidget {
  const _MatchPromise({
    required this.editing,
    required this.isTechnicianCommunity,
  });

  final bool editing;
  final bool isTechnicianCommunity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.auto_awesome_rounded,
            size: 15,
            color: AppColors.primaryDark,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              editing
                  ? 'Your current matches will be replaced with a fresh top 3'
                  : isTechnicianCommunity
                  ? 'Your question will be posted to the technician community'
                  : 'RB-CARS will match you with top 3 technicians',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three facts relevant to routing and scheduling, read back before it is sent.
class _Summary extends StatelessWidget {
  const _Summary({required this.posting});

  final JobPostingProvider posting;

  @override
  Widget build(BuildContext context) {
    final JobDraft draft = posting.draft;

    final String device = <String?>[
      posting.deviceCategory?.label,
      draft.brand,
    ].whereType<String>().join(' - ');
    final LaborPrice? labor =
        draft.deviceType == null || draft.problemSymptom == null
        ? null
        : LaborPriceCatalog.forJob(
            deviceType: draft.deviceType!,
            symptomCode: draft.problemSymptom!,
          );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: <Widget>[
          _Row(label: 'Device', value: device.isEmpty ? 'Not set' : device),
          _Row(
            label: 'Symptom',
            value:
                labor?.symptom ??
                (draft.problemSymptom == null
                    ? 'Not set'
                    : draft.problemSymptom!),
          ),
          _Row(label: 'Price', value: labor?.fee ?? 'Price to be confirmed'),
          _Row(label: 'Service', value: draft.servicePath?.label ?? 'Not set'),
          _Row(
            label: 'Schedule',
            value: posting.schedulePreference.label,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.lg,
        vertical: AppSizes.md,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSizes.lg),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
