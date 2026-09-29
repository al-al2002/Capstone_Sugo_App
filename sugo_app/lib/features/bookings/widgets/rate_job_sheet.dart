import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../rb_cars/models/technician_profile_details.dart';
import '../../rb_cars/services/rb_cars_service.dart';

/// Stars and an optional comment for a completed job.
///
/// ## Why this matters more than it looks
///
/// Until this sheet existed nothing in the app recorded a rating, and every
/// technician on the platform was rated 0.00. That value is the recommended
/// row's primary sort key and one of the matcher's scoring factors, so both
/// were ranking on nothing. A review written here is mirrored into the scoring
/// tables by a database trigger - see 20260917000001_reviews_drive_rating.sql.
///
/// ## Why the comment is optional
///
/// Forcing text produces "good" far more often than it produces anything worth
/// reading, and a client who is made to write before they can rate may simply
/// not rate. The stars are the signal the ranking needs; the words are a bonus.
///
/// ## Both directions
///
/// The same sheet rates a client, from the technician's side, when opened with
/// [RateJobSheet.showForClient]. One widget rather than two, so the two kinds
/// of rating feel identical - same stars, same meanings, same optional
/// comment - and cannot drift apart as either one is changed.
class RateJobSheet extends StatefulWidget {
  const RateJobSheet({
    super.key,
    required this.jobId,
    required this.technicianId,
    required this.technicianName,
    this.existing,
  }) : clientId = null;

  /// A technician rating the client on a completed job.
  const RateJobSheet.client({
    super.key,
    required this.jobId,
    required String this.clientId,
    required String clientName,
    this.existing,
  }) : technicianId = '',
       technicianName = clientName;

  final String jobId;
  final String technicianId;

  /// Who is being rated. Named for its original use; for a client rating it
  /// holds the client's name.
  final String technicianName;

  /// Set when a technician is rating a client. Decides which table the rating
  /// is written to and how the sheet is worded.
  final String? clientId;

  /// The current rating, when editing rather than writing.
  final TechnicianReview? existing;

  bool get _ratesClient => clientId != null;

  /// Shows the sheet. Resolves to true when a review was saved.
  static Future<bool> show(
    BuildContext context, {
    required String jobId,
    required String technicianId,
    required String technicianName,
    TechnicianReview? existing,
  }) async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.panelRadius),
        ),
      ),
      builder: (_) => RateJobSheet(
        jobId: jobId,
        technicianId: technicianId,
        technicianName: technicianName,
        existing: existing,
      ),
    );
    return saved ?? false;
  }

  /// Opens the sheet for a technician to rate a client. Resolves to true
  /// when a rating was saved.
  static Future<bool> showForClient(
    BuildContext context, {
    required String jobId,
    required String clientId,
    required String clientName,
    TechnicianReview? existing,
  }) async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.panelRadius),
        ),
      ),
      builder: (_) => RateJobSheet.client(
        jobId: jobId,
        clientId: clientId,
        clientName: clientName,
        existing: existing,
      ),
    );
    return saved ?? false;
  }

  @override
  State<RateJobSheet> createState() => _RateJobSheetState();
}

class _RateJobSheetState extends State<RateJobSheet> {
  /// Late, so the sheet can be built without a live Supabase client - it is
  /// only needed at the moment a review is actually saved.
  late final RbCarsService _service = RbCarsService();
  late final TextEditingController _comment = TextEditingController(
    text: widget.existing?.comment ?? '',
  );

  /// 0 means "not chosen yet". Deliberately not pre-filled with five stars:
  /// a default rating is a rating nobody gave, and the ranking would learn from
  /// it exactly as if they had.
  late int _stars = widget.existing?.stars ?? 0;

  bool _saving = false;
  String? _error;

  static const List<String> _meanings = <String>[
    '',
    'Poor',
    'Below expectations',
    'Okay',
    'Good',
    'Excellent',
  ];

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_stars == 0 || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (widget._ratesClient) {
        await _service.submitClientReview(
          jobId: widget.jobId,
          clientId: widget.clientId!,
          stars: _stars,
          comment: _comment.text,
          existingReviewId: widget.existing?.id,
        );
      } else {
        await _service.submitReview(
          jobId: widget.jobId,
          technicianId: widget.technicianId,
          stars: _stars,
          comment: _comment.text,
          existingReviewId: widget.existing?.id,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save your review. Please try again.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool editing = widget.existing != null;

    return Padding(
      // Lifts the sheet above the keyboard when the comment field is focused.
      padding: EdgeInsets.only(
        left: AppSizes.screenPadding,
        right: AppSizes.screenPadding,
        top: AppSizes.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSizes.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              ),
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Text(
            editing ? 'Edit your review' : 'How did it go?',
            textAlign: TextAlign.center,
            style: AppTextStyles.headline,
          ),
          const SizedBox(height: 4),
          Text(
            widget._ratesClient
                // Different reason, stated honestly: a client rating does not
                // move any ranking. It is a heads-up for the next technician.
                ? 'Rate ${widget.technicianName}. Other technicians see this '
                      'before they accept a job from them.'
                : 'Rate ${widget.technicianName}. Your rating helps other '
                      'clients choose, and decides how they are ranked.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: AppSizes.lg),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (int i = 1; i <= 5; i++)
                IconButton(
                  onPressed: _saving ? null : () => setState(() => _stars = i),
                  iconSize: 38,
                  tooltip: '$i star${i == 1 ? '' : 's'}',
                  icon: Icon(
                    i <= _stars
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: i <= _stars ? AppColors.accent : AppColors.hint,
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 18,
            child: Text(
              _meanings[_stars],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSizes.md),

          TextField(
            controller: _comment,
            enabled: !_saving,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: widget._ratesClient
                  ? 'Anything other technicians should know? (optional)'
                  : 'Anything other clients should know? (optional)',
            ),
          ),

          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSizes.sm),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ],

          const SizedBox(height: AppSizes.md),
          SizedBox(
            height: AppSizes.buttonHeight,
            child: FilledButton(
              // Disabled until a star is chosen, so a review can never be saved
              // with a rating the client did not give.
              onPressed: _stars == 0 || _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(editing ? 'Save changes' : 'Submit review'),
            ),
          ),
        ],
      ),
    );
  }
}
