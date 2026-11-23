import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_fold_card.dart';
import '../../../core/widgets/sugo_image_viewer.dart';
import '../../rb_cars/models/job_enums.dart';
import '../models/job_evidence.dart';

/// The work record on a booking (in-task documentation, 2026-11-22).
///
/// Two faces of the same `job_evidence` rows:
///
/// * **The technician on a job under way** ([canAdd]) sees a checklist: each
///   step, what to photograph, whether it is required, and a camera button.
///   "After" waits for the unit-as-found step, as the server does.
/// * **Everyone else** - the client, or the technician once the job is
///   closed - sees a timeline: each step's photos, the time, the location
///   stamp and the note.
///
/// Photos are private (`job-evidence` bucket); each thumbnail asks for a
/// signed URL once and keeps it, because this card rebuilds on every
/// tracking update.
class WorkRecordSection extends StatelessWidget {
  const WorkRecordSection({
    super.key,
    required this.evidence,
    required this.servicePath,
    required this.photoUrl,
    this.selfDropOff = false,
    this.missing,
    this.canAdd = false,
    this.onAdd,
    this.jobLatitude,
    this.jobLongitude,
    this.forClient = false,
  });

  final List<JobEvidence> evidence;
  final ServicePath? servicePath;
  final bool selfDropOff;

  /// Required steps still missing, from the server. Null when unknown.
  final List<EvidenceMilestone>? missing;

  final bool canAdd;
  final ValueChanged<EvidenceMilestone>? onAdd;

  final double? jobLatitude;
  final double? jobLongitude;

  /// Words the empty state and subtitle for the client.
  final bool forClient;

  final Future<String> Function(String path) photoUrl;

  String _label(EvidenceMilestone m) =>
      m.labelFor(servicePath, selfDropOff: selfDropOff);

  /// "Before · After", or "No photos yet" - the folded card's one line.
  String get _summary {
    if (evidence.isEmpty) return 'No photos yet';
    final List<String> steps = <String>[];
    for (final JobEvidence e in evidence) {
      final String label = _label(e.milestone);
      if (!steps.contains(label)) steps.add(label);
    }
    return steps.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final String intake = _label(EvidenceMilestone.intake);
    final String after = _label(EvidenceMilestone.after);

    // The reader's copy is a secondary section of the booking page, so it
    // opens folded to one line like Progress, Price and Details (the page's
    // rule since 2026-11-17). The technician's checklist on a live job stays
    // open: it is part of doing the job, and "Mark as complete" waits on it.
    if (!canAdd) {
      return SugoFoldCard(
        icon: Icons.fact_check_rounded,
        title: 'Work record',
        summary: _summary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              forClient
                  ? 'Photos your technician took during the job, with the '
                        'time and place.'
                  : 'The photos you took during the job.',
              style: AppTextStyles.micro,
            ),
            const SizedBox(height: AppSizes.md),
            if (evidence.isEmpty)
              Text(
                forClient
                    ? 'No photos yet. Your technician adds them during the '
                          'job: $intake when they start, and $after once it '
                          'is fixed.'
                    : 'No photos were added to this job.',
                style: AppTextStyles.caption.copyWith(fontSize: 13),
              )
            else
              for (int i = 0; i < evidence.length; i++) ...<Widget>[
                if (i > 0)
                  const Divider(height: AppSizes.lg, color: AppColors.divider),
                _Entry(
                  evidence: evidence[i],
                  label: _label(evidence[i].milestone),
                  stamp: evidence[i].locationStamp(jobLatitude, jobLongitude),
                  photoUrl: photoUrl,
                ),
              ],
          ],
        ),
      );
    }

    return SugoCard(
      pressable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: AppSizes.iconTile,
                height: AppSizes.iconTile,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                ),
                child: const Icon(
                  Icons.fact_check_rounded,
                  size: 22,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Work record', style: AppTextStyles.sectionTitle),
                    const SizedBox(height: 2),
                    Text(
                      'Photos at each step. $intake and $after are needed '
                      'to finish the job.',
                      style: AppTextStyles.micro,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          ..._checklist(),
        ],
      ),
    );
  }

  List<Widget> _checklist() {
    final bool hasIntake = evidence.any(
      (JobEvidence e) => e.milestone == EvidenceMilestone.intake,
    );
    final List<EvidenceMilestone> steps = EvidenceMilestone.stepsFor(servicePath);

    return <Widget>[
      for (int i = 0; i < steps.length; i++) ...<Widget>[
        if (i > 0) const Divider(height: AppSizes.lg, color: AppColors.divider),
        _Step(
          key: ValueKey<String>('evidence-step-${steps[i].wire}'),
          milestone: steps[i],
          label: _label(steps[i]),
          blurb: steps[i] == EvidenceMilestone.after && !hasIntake
              ? 'Add the ${_label(EvidenceMilestone.intake)} photos first.'
              : steps[i].blurbFor(servicePath, selfDropOff: selfDropOff),
          entries: <JobEvidence>[
            for (final JobEvidence e in evidence)
              if (e.milestone == steps[i]) e,
          ],
          // "Required" only while the server says it is still owed: a job
          // posted before the requirement shows every step as optional.
          stillRequired: missing?.contains(steps[i]) ?? steps[i].required,
          locked: steps[i] == EvidenceMilestone.after && !hasIntake,
          onAdd: onAdd == null ? null : () => onAdd!(steps[i]),
          photoUrl: photoUrl,
        ),
      ],
    ];
  }
}

/// One step of the technician's checklist.
class _Step extends StatelessWidget {
  const _Step({
    super.key,
    required this.milestone,
    required this.label,
    required this.blurb,
    required this.entries,
    required this.stillRequired,
    required this.locked,
    required this.onAdd,
    required this.photoUrl,
  });

  final EvidenceMilestone milestone;
  final String label;
  final String blurb;
  final List<JobEvidence> entries;
  final bool stillRequired;
  final bool locked;
  final VoidCallback? onAdd;
  final Future<String> Function(String path) photoUrl;

  @override
  Widget build(BuildContext context) {
    final bool done = entries.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.successSoft : AppColors.primarySofter,
              ),
              child: Icon(
                done ? Icons.check_rounded : milestone.icon,
                size: 18,
                color: done ? AppColors.success : AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: AppSizes.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(label, style: AppTextStyles.bodyStrong),
                      if (stillRequired && !done)
                        const _Tag(text: 'Required', warn: true)
                      else if (done)
                        _Tag(
                          text: Fmt.time(entries.last.capturedAt),
                          warn: false,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(blurb, style: AppTextStyles.caption.copyWith(fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            TextButton.icon(
              key: ValueKey<String>('evidence-add-${milestone.wire}'),
              onPressed: locked ? null : onAdd,
              icon: const Icon(Icons.photo_camera_rounded, size: 18),
              label: Text(done ? 'More' : 'Add'),
            ),
          ],
        ),
        if (done) ...<Widget>[
          const SizedBox(height: AppSizes.sm),
          Padding(
            padding: const EdgeInsets.only(left: 32 + AppSizes.md),
            child: _Thumbnails(
              paths: <String>[for (final JobEvidence e in entries) ...e.photoPaths],
              photoUrl: photoUrl,
            ),
          ),
        ],
      ],
    );
  }
}

/// One saved step, for the timeline.
class _Entry extends StatelessWidget {
  const _Entry({
    required this.evidence,
    required this.label,
    required this.stamp,
    required this.photoUrl,
  });

  final JobEvidence evidence;
  final String label;
  final String stamp;
  final Future<String> Function(String path) photoUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(evidence.milestone.icon, size: 18, color: AppColors.primary),
            const SizedBox(width: AppSizes.sm),
            Expanded(child: Text(label, style: AppTextStyles.bodyStrong)),
            Text(
              Fmt.shortDateTime(evidence.capturedAt),
              style: AppTextStyles.micro,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            Icon(
              evidence.hasLocation ? Icons.place_outlined : Icons.location_off_outlined,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(stamp, style: AppTextStyles.micro),
            ),
          ],
        ),
        if (evidence.note != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(evidence.note!, style: AppTextStyles.caption.copyWith(fontSize: 13)),
        ],
        const SizedBox(height: AppSizes.sm),
        _Thumbnails(paths: evidence.photoPaths, photoUrl: photoUrl),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.warn});

  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: warn ? AppColors.warningSoft : AppColors.successSoft,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: warn ? AppColors.warning : AppColors.success,
        ),
      ),
    );
  }
}

/// A row of photos that open full-screen.
class _Thumbnails extends StatelessWidget {
  const _Thumbnails({required this.paths, required this.photoUrl});

  final List<String> paths;
  final Future<String> Function(String path) photoUrl;

  Future<void> _open(BuildContext context, int index) async {
    try {
      final List<String> urls = await Future.wait(paths.map(photoUrl));
      if (!context.mounted) return;
      await openSugoImageViewer(context, urls: urls, initialIndex: index);
    } catch (_) {
      // A photo that cannot be signed just does not open.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSizes.sm,
      runSpacing: AppSizes.sm,
      children: <Widget>[
        for (int i = 0; i < paths.length; i++)
          _EvidencePhoto(
            key: ValueKey<String>(paths[i]),
            path: paths[i],
            photoUrl: photoUrl,
            onTap: () => _open(context, i),
          ),
      ],
    );
  }
}

/// One private photo: the signed URL is asked for once, then kept.
class _EvidencePhoto extends StatefulWidget {
  const _EvidencePhoto({
    super.key,
    required this.path,
    required this.photoUrl,
    required this.onTap,
  });

  final String path;
  final Future<String> Function(String path) photoUrl;
  final VoidCallback onTap;

  @override
  State<_EvidencePhoto> createState() => _EvidencePhotoState();
}

class _EvidencePhotoState extends State<_EvidencePhoto> {
  late final Future<String> _url = widget.photoUrl(widget.path);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open photo',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.sm),
          child: SizedBox(
            width: 64,
            height: 64,
            child: FutureBuilder<String>(
              future: _url,
              builder: (BuildContext context, AsyncSnapshot<String> s) {
                if (!s.hasData) {
                  return const ColoredBox(color: AppColors.primarySofter);
                }
                return Image.network(
                  s.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: AppColors.primarySofter,
                    child: Icon(Icons.broken_image_outlined, color: AppColors.hint),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
