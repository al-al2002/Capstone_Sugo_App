import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../rb_cars/widgets/photo_picker_row.dart';
import '../models/job_dispute.dart';
import '../services/dispute_service.dart';

/// "Report a problem with this booking": what went wrong, in the person's own
/// words, with photos if they have them.
///
/// Returns the new report, or null if the sheet was closed without sending.
///
/// ## Three questions, no more
///
/// A reason from a short list (so the admin queue can be sorted), a
/// description (at least a sentence - "bad" is not something anyone can act
/// on), and optional photos (a cracked casing says more than a paragraph).
/// Anything else the admin needs is already on the booking: the chat, the
/// job photos, the timeline and the price.
class ReportProblemSheet extends StatefulWidget {
  const ReportProblemSheet({
    super.key,
    required this.jobId,
    required this.isClient,
    this.service,
    this.initialReason,
  });

  final String jobId;
  final bool isClient;
  final DisputeService? service;

  /// Preselected - a 1-star rating arrives with "not fixed" chosen.
  final DisputeReason? initialReason;

  static Future<JobDispute?> show(
    BuildContext context, {
    required String jobId,
    required bool isClient,
    DisputeService? service,
    DisputeReason? initialReason,
  }) {
    return showSugoBottomSheet<JobDispute>(
      context: context,
      title: 'Report a problem',
      subtitle: 'A SUGO admin reviews every report and replies here.',
      builder: (_) => ReportProblemSheet(
        jobId: jobId,
        isClient: isClient,
        service: service,
        initialReason: initialReason,
      ),
    );
  }

  @override
  State<ReportProblemSheet> createState() => _ReportProblemSheetState();
}

class _ReportProblemSheetState extends State<ReportProblemSheet> {
  static const int _minDetails = 10;

  late final DisputeService _service = widget.service ?? DisputeService();
  final TextEditingController _details = TextEditingController();
  final List<XFile> _photos = <XFile>[];

  late DisputeReason? _reason = widget.initialReason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  bool get _ready =>
      _reason != null && _details.text.trim().length >= _minDetails;

  Future<void> _send() async {
    if (!_ready || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final JobDispute dispute = await _service.open(
        jobId: widget.jobId,
        reason: _reason!,
        details: _details.text,
        photos: _photos,
      );
      if (mounted) Navigator.of(context).pop(dispute);
    } on RbCarsFailure catch (failure) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = failure.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<DisputeReason> reasons = DisputeReason.forRole(
      isClient: widget.isClient,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('What went wrong?', style: AppTextStyles.titleSmall),
        const SizedBox(height: AppSizes.sm),
        Wrap(
          spacing: AppSizes.sm,
          runSpacing: AppSizes.sm,
          children: <Widget>[
            for (final DisputeReason reason in reasons)
              ChoiceChip(
                avatar: Icon(reason.icon, size: 17),
                label: Text(reason.label),
                selected: _reason == reason,
                onSelected: _sending
                    ? null
                    : (_) => setState(() => _reason = reason),
              ),
          ],
        ),
        const SizedBox(height: AppSizes.lg),
        Text('Tell us what happened', style: AppTextStyles.titleSmall),
        const SizedBox(height: AppSizes.sm),
        TextField(
          controller: _details,
          enabled: !_sending,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText:
                'What was agreed, what happened instead, and when. The more '
                'specific, the faster this is sorted out.',
          ),
        ),
        const SizedBox(height: AppSizes.sm),
        Text('Photos (optional)', style: AppTextStyles.titleSmall),
        const SizedBox(height: AppSizes.sm),
        PhotoPickerRow(
          photos: _photos,
          onAdd: (XFile file) => setState(() => _photos.add(file)),
          onRemove: (XFile file) => setState(() => _photos.remove(file)),
        ),
        const SizedBox(height: AppSizes.lg),
        Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            color: AppColors.primarySofter,
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          ),
          child: Text(
            'The other person on this booking can read your report, and the '
            'admin reads your chat with them too. Keep to what happened.',
            style: AppTextStyles.caption,
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: AppSizes.md),
          Text(
            _error!,
            style: AppTextStyles.caption.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: AppSizes.lg),
        SugoButton(
          label: 'Send report',
          icon: Icons.send_rounded,
          isLoading: _sending,
          onPressed: _ready && !_sending ? _send : null,
        ),
      ],
    );
  }
}
