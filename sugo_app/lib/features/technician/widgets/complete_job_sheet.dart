import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../../rb_cars/models/issue_catalog.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/models/job_price.dart';
import '../../rb_cars/models/problem_catalog.dart';

/// The technician's wrap-up when they mark a job complete (2026-11-16).
///
/// ## What changed, and why
///
/// This sheet used to ask two RB-CARS questions in the engine's own words:
/// "Was the original diagnosis correct?" and a "Rerouted mid-job" switch. At
/// the user's request both are gone:
///
/// * **Rerouted mid-job** never needed asking. The system itself moves a job
///   to the shop, so `job-response` now works it out from the match snapshot
///   (`_shared/reroute.ts`).
/// * **Diagnosis correct** is still the one signal Stage 1's accuracy factor
///   learns from - dropping it would freeze every technician at the prior.
///   So it is asked the way a technician thinks about a job: **What did you
///   fix?** The problem the client reported is one answer, anything else is
///   the other, and the app compares the two. Nothing is preselected: a
///   default of "as reported" would quietly inflate everyone's accuracy.
///   When the client picked "Not sure yet" there was no diagnosis to judge,
///   so the answer is recorded as no verdict (null) rather than a guess.
///
/// In their place, two things that fit how SUGO actually works:
///
/// * **Before you close** - the unit works and is with the client, and the
///   payment is settled. SUGO does not take payment, so this is the moment
///   to make sure nobody is left out of pocket.
/// * **An aftercare note** (optional), sent to the client in the job chat
///   with what was fixed - the written record a SUGO booking otherwise lacks,
///   since there is no receipt.
class CompleteJobSheet extends StatefulWidget {
  const CompleteJobSheet({super.key, required this.job, this.homeDistanceKm});

  final Job job;

  /// For the booking's estimate in the payment check; see [JobPrice.forJob].
  final double? homeDistanceKm;

  static Future<CompletionAnswers?> show(
    BuildContext context,
    Job job, {
    double? homeDistanceKm,
  }) {
    return showSugoBottomSheet<CompletionAnswers>(
      context: context,
      title: 'Wrap up this job',
      subtitle: '${job.title} · ${job.reference}',
      scrollable: false,
      padding: EdgeInsets.zero,
      builder: (_) =>
          CompleteJobSheet(job: job, homeDistanceKm: homeDistanceKm),
    );
  }

  @override
  State<CompleteJobSheet> createState() => _CompleteJobSheetState();
}

class _CompleteJobSheetState extends State<CompleteJobSheet> {
  /// "Not on the list" in the something-else chips.
  static const String _notListed = '_not_listed';

  static const int _noteLimit = 300;

  /// True: it was what the client reported. False: something else.
  bool? _asReported;

  /// What it actually was, when it was something else.
  String? _actualCode;

  bool _works = false;
  bool _paid = false;
  final TextEditingController _note = TextEditingController();

  Job get _job => widget.job;

  /// False when the client did not know what was wrong.
  bool get _hasReportedProblem {
    final String code = _job.problemSymptom.trim();
    return code.isNotEmpty && code != ProblemCatalog.notSureCode;
  }

  List<IssueOption> get _alternatives => IssueCatalog.all
      .where(
        (IssueOption o) =>
            o.deviceType == _job.deviceType && o.code != _job.problemSymptom,
      )
      .toList(growable: false);

  // Choosing "as reported" clears [_actualCode], so either one answers it.
  bool get _fixAnswered => _asReported == true || _actualCode != null;

  bool get _checksDone => _works && _paid;

  bool get _ready => _fixAnswered && _checksDone;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _chooseReported(bool asReported) {
    setState(() {
      _asReported = asReported;
      if (asReported) _actualCode = null;
    });
  }

  void _submit() {
    final String? fixed = _asReported == true
        ? _job.symptomLabel
        : _actualCode == _notListed
        ? null
        : IssueCatalog.byCode(_actualCode)?.label;
    final String note = _note.text.trim();

    Navigator.of(context).pop(
      CompletionAnswers(
        diagnosisCorrect: _hasReportedProblem ? _asReported == true : null,
        fixedLabel: fixed,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPadding,
              0,
              AppSizes.screenPadding,
              AppSizes.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Step(
                  number: 1,
                  title: 'What did you fix?',
                  done: _fixAnswered,
                  child: _fixStep(),
                ),
                const SizedBox(height: AppSizes.xl),
                _Step(
                  number: 2,
                  title: 'Before you close',
                  done: _checksDone,
                  child: _checksStep(),
                ),
                const SizedBox(height: AppSizes.xl),
                _Step(
                  number: 3,
                  title: 'Aftercare note',
                  trailing: 'Optional',
                  done: _note.text.trim().isNotEmpty,
                  child: _noteStep(),
                ),
              ],
            ),
          ),
        ),
        _footer(),
      ],
    );
  }

  Widget _fixStep() {
    final Widget chips = _FaultGrid(
      options: <_Fault>[
        for (final IssueOption option in _alternatives)
          _Fault(code: option.code, label: option.label),
        const _Fault(
          code: _notListed,
          label: 'Not on the list',
          icon: Icons.more_horiz_rounded,
        ),
      ],
      selected: _actualCode,
      onSelected: (String code) => setState(() => _actualCode = code),
    );

    // The client did not know: just ask what it was.
    if (!_hasReportedProblem) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'The client was not sure what was wrong. Pick what it turned out '
            'to be.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSizes.md),
          chips,
        ],
      );
    }

    final Duration motion = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.base;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ChoiceCard(
          title: _job.symptomLabel,
          subtitle: 'What the client reported',
          icon: Icons.task_alt_rounded,
          selected: _asReported == true,
          onTap: () => _chooseReported(true),
        ),
        const SizedBox(height: AppSizes.sm),
        _ChoiceCard(
          title: 'Something else',
          subtitle: 'The real fault was different',
          icon: Icons.manage_search_rounded,
          selected: _asReported == false,
          onTap: () => _chooseReported(false),
        ),
        AnimatedSize(
          duration: motion,
          curve: AppMotion.standard,
          alignment: Alignment.topCenter,
          child: _asReported == false
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSizes.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text('What was it?', style: AppTextStyles.overline),
                      const SizedBox(height: AppSizes.sm),
                      chips,
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _checksStep() {
    final String price = JobPrice.forJob(
      _job,
      homeDistanceKm: widget.homeDistanceKm,
    ).headline;
    final bool priced = price.startsWith('₱');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CheckRow(
            icon: Icons.handshake_outlined,
            title: _worksTitle,
            subtitle: 'Tested and handed back',
            value: _works,
            onChanged: (bool value) => setState(() => _works = value),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
          _CheckRow(
            icon: Icons.payments_outlined,
            title: 'Payment is settled',
            subtitle: priced
                ? 'Paid to you directly · estimate $price'
                : 'Paid to you directly - SUGO does not take payment',
            value: _paid,
            onChanged: (bool value) => setState(() => _paid = value),
          ),
        ],
      ),
    );
  }

  /// The first check, in the words of this kind of job.
  String get _worksTitle {
    if (_job.servicePath == ServicePath.pickup) {
      return _job.isSelfDropOff
          ? 'The client has collected it, working'
          : 'It is back with the client, working';
    }
    return 'It works, and the client has seen it';
  }

  Widget _noteStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 4,
          maxLength: _noteLimit,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'e.g. Keep the vents clear and charge it fully tonight.',
          ),
        ),
        const SizedBox(height: AppSizes.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSizes.xs + 2),
            Expanded(
              child: Text(
                'Sent to the client in your chat, with what you fixed.',
                style: AppTextStyles.micro,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _footer() {
    final List<String> missing = <String>[
      if (!_fixAnswered) 'what you fixed',
      if (!_works && !_paid)
        'both checks'
      else if (!_works)
        'the hand-back check'
      else if (!_paid)
        'the payment check',
    ];

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPadding,
          AppSizes.md,
          AppSizes.screenPadding,
          AppSizes.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SugoButton(
              label: 'Complete job',
              icon: Icons.check_rounded,
              onPressed: _ready ? _submit : null,
            ),
            const SizedBox(height: AppSizes.sm),
            Text(
              missing.isEmpty
                  ? 'The client will be asked to rate you.'
                  : 'Still to do: ${_joinNaturally(missing)}.',
              textAlign: TextAlign.center,
              style: AppTextStyles.micro,
            ),
          ],
        ),
      ),
    );
  }

  static String _joinNaturally(List<String> items) {
    if (items.length == 1) return items.single;
    return '${items.sublist(0, items.length - 1).join(', ')} and '
        '${items.last}';
  }
}

/// One answer in the "what was it?" grid.
class _Fault {
  const _Fault({required this.code, required this.label, this.icon});

  final String code;
  final String label;
  final IconData? icon;
}

/// The device's other faults as a two-column grid of tiles.
///
/// They were chips first, but the labels are long ("Keyboard or trackpad not
/// working"), so the chips stacked one per line into a tall ragged column.
/// Two even columns halve the height and scan in rows. Each row takes the
/// height of its taller tile, so the grid stays square at large text sizes.
class _FaultGrid extends StatelessWidget {
  const _FaultGrid({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<_Fault> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < options.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: AppSizes.sm));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _tile(options[i])),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: i + 1 < options.length
                    ? _tile(options[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _tile(_Fault fault) {
    final bool isSelected = fault.code == selected;
    return _FaultTile(
      fault: fault,
      selected: isSelected,
      onTap: () => onSelected(fault.code),
    );
  }
}

class _FaultTile extends StatelessWidget {
  const _FaultTile({
    required this.fault,
    required this.selected,
    required this.onTap,
  });

  final _Fault fault;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Duration motion = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.fast;

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.sm + 2),
          child: AnimatedContainer(
            duration: motion,
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.sm + 2,
              vertical: AppSizes.sm,
            ),
            decoration: BoxDecoration(
              color: selected ? AppColors.primarySofter : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.sm + 2),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                if (selected || fault.icon != null) ...<Widget>[
                  Icon(
                    selected ? Icons.check_circle_rounded : fault.icon,
                    size: 16,
                    color: selected ? AppColors.primary : AppColors.hint,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    fault.label,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A numbered section. Its number turns into a tick once it is answered, so
/// the technician can see at a glance what is left.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.done,
    required this.child,
    this.trailing,
  });

  final int number;
  final String title;
  final bool done;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final Duration motion = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.fast;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            AnimatedContainer(
              duration: motion,
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? AppColors.success : AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: done
                  ? const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    )
                  : Text(
                      '$number',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
            ),
            const SizedBox(width: AppSizes.sm + 2),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: AppTextStyles.titleSmall),
              ),
            ),
            if (trailing != null) Text(trailing!, style: AppTextStyles.micro),
          ],
        ),
        const SizedBox(height: AppSizes.md),
        child,
      ],
    );
  }
}

/// One of two answers to "What did you fix?", drawn as a radio card.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Duration motion = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.fast;

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          child: AnimatedContainer(
            duration: motion,
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md,
              vertical: AppSizes.sm + 2,
            ),
            decoration: BoxDecoration(
              color: selected ? AppColors.primarySofter : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.tileRadius),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.hint,
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(title, style: AppTextStyles.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTextStyles.caption.copyWith(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                _RadioDot(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.hint,
          width: selected ? 6.5 : 1.6,
        ),
      ),
    );
  }
}

/// One "Before you close" check: the whole row toggles it.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.md,
              AppSizes.sm,
              AppSizes.xs,
              AppSizes.sm,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 20,
                  color: value ? AppColors.success : AppColors.hint,
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(title, style: AppTextStyles.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTextStyles.caption.copyWith(fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                Checkbox(
                  value: value,
                  onChanged: (bool? next) => onChanged(next ?? false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the wrap-up sheet returns.
class CompletionAnswers {
  const CompletionAnswers({
    required this.diagnosisCorrect,
    this.fixedLabel,
    this.note,
  });

  /// Whether the fault was the one the client reported - the RB-CARS
  /// `diagnosis_correct` signal. Null when the client was not sure, so there
  /// was nothing to judge.
  final bool? diagnosisCorrect;

  /// What was fixed, in words, or null for "Not on the list".
  final String? fixedLabel;

  /// The aftercare note, already trimmed; null when left empty.
  final String? note;

  /// The chat message for the client, or null when there is no note - the
  /// note is what makes a message worth sending.
  String? get wrapUpMessage {
    final String? text = note;
    if (text == null) return null;
    final String opener = fixedLabel == null
        ? 'Job done.'
        : 'Job done. What I fixed: $fixedLabel.';
    return '$opener\n\n$text';
  }
}
