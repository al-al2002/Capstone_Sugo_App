import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/time_off.dart';
import '../services/time_off_service.dart';

/// The technician's vacation days, on their Profile tab.
///
/// Shows whether they are away now, lists what is planned, and adds or ends a
/// period. What being away MEANS is said on the card in plain words, because
/// it is not the same as going offline: they still appear in a client's Top 3,
/// labelled "On vacation", but nobody can book them until they are back.
class VacationCard extends StatefulWidget {
  const VacationCard({super.key, this.service, this.clock});

  /// Injected by tests. Defaults to the real service.
  final TimeOffService? service;

  /// Injected by tests so "today" is fixed. Defaults to the device clock.
  final DateTime Function()? clock;

  @override
  State<VacationCard> createState() => _VacationCardState();
}

class _VacationCardState extends State<VacationCard> {
  late final TimeOffService _service = widget.service ?? TimeOffService();

  List<TimeOff> _periods = const <TimeOff>[];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<TimeOff> periods = await _service.upcoming();
      if (!mounted) return;
      setState(() {
        _periods = periods;
        _loading = false;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _loading = false;
      });
    }
  }

  TimeOff? get _current {
    for (final TimeOff period in _periods) {
      if (period.isCurrent(_now)) return period;
    }
    return null;
  }

  List<TimeOff> get _planned =>
      _periods.where((TimeOff p) => p.isUpcoming(_now)).toList(growable: false);

  Future<void> _add() async {
    if (await addVacationFlow(context, service: _service, now: _now)) {
      await _load();
    }
  }

  Future<void> _endNow(TimeOff period) async {
    if (await endVacationFlow(context, service: _service, period: period)) {
      await _load();
    }
  }

  Future<void> _cancel(TimeOff period) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Remove these dates?'),
        content: Text('${period.rangeLabel} will be open for bookings again.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => _service.cancel(period), 'Vacation removed.');
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      UiFeedback.showSuccess(context, success);
      await _load();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SugoSkeleton(height: 132, radius: AppSizes.panelRadius);
    }

    final TimeOff? current = _current;
    final List<TimeOff> planned = _planned;

    return SugoCard(
      pressable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_error != null)
            _ErrorLine(message: _error!, onRetry: _load)
          else if (current != null)
            _AwayNow(period: current, busy: _busy, onEnd: () => _endNow(current))
          else
            const _Working(),

          if (planned.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSizes.lg),
            Text('Planned', style: AppTextStyles.overline),
            const SizedBox(height: AppSizes.sm),
            for (final TimeOff period in planned)
              _PlannedRow(
                period: period,
                busy: _busy,
                onRemove: () => _cancel(period),
              ),
          ],

          const SizedBox(height: AppSizes.lg),
          OutlinedButton.icon(
            onPressed: _busy || _error != null ? null : _add,
            icon: const Icon(Icons.beach_access_rounded, size: 18),
            label: Text(current == null ? 'Add vacation' : 'Plan another vacation'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.2),
              minimumSize: const Size.fromHeight(AppSizes.buttonHeight - 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks dates and confirms a new vacation. True when one was saved.
///
/// Shared by the Profile card and the dashboard's "Set vacation", so both ask
/// the same way and say the same things.
Future<bool> addVacationFlow(
  BuildContext context, {
  required TimeOffService service,
  DateTime? now,
}) async {
  final DateTime today = TimeOff.dayOf(now ?? DateTime.now());
  final DateTimeRange? range = await showDateRangePicker(
    context: context,
    firstDate: today,
    lastDate: today.add(const Duration(days: 365)),
    currentDate: today,
    helpText: 'Select your vacation days',
    saveText: 'Next',
  );
  if (range == null || !context.mounted) return false;

  final DateTime start = TimeOff.dayOf(range.start);
  final DateTime end = TimeOff.dayOf(range.end);

  // Said before the sheet opens, so the technician is not asked to write a
  // note for dates the database will refuse.
  if (end.difference(start).inDays + 1 > TimeOff.maxDays) {
    UiFeedback.showError(
      context,
      'A vacation can be at most ${TimeOff.maxDays} days. '
      'Add a second one for a longer break.',
    );
    return false;
  }

  final bool? saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSizes.sheetRadius),
      ),
    ),
    builder: (_) =>
        _ConfirmVacationSheet(start: start, end: end, service: service),
  );

  if (saved == true && context.mounted) {
    UiFeedback.showSuccess(
      context,
      'Vacation added. Clients will see you are away on those days.',
    );
    return true;
  }
  return false;
}

/// Asks, then ends [period] now. True when it was ended.
Future<bool> endVacationFlow(
  BuildContext context, {
  required TimeOffService service,
  required TimeOff period,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('End your vacation?'),
      content: const Text(
        'Clients will be able to book you again straight away.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Stay on vacation'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('End it now'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    await service.endNow(period);
    if (context.mounted) {
      UiFeedback.showSuccess(context, 'Welcome back. You can be booked again.');
    }
    return true;
  } on RbCarsFailure catch (failure) {
    if (context.mounted) UiFeedback.showError(context, failure.message);
    return false;
  }
}

/// "Edit dates": moves the last day of [period]. True when it was saved.
///
/// Only the end moves. A vacation under way has already started, and a
/// planned one is quicker to remove and add again than to re-pick twice.
Future<bool> editVacationEndFlow(
  BuildContext context, {
  required TimeOffService service,
  required TimeOff period,
  DateTime? now,
}) async {
  final DateTime today = TimeOff.dayOf(now ?? DateTime.now());
  final DateTime first = period.startsOn.isAfter(today) ? period.startsOn : today;
  // The database caps a period at [TimeOff.maxDays], counted from its start.
  final DateTime last = period.startsOn.add(
    const Duration(days: TimeOff.maxDays - 1),
  );
  DateTime initial = period.endsOn;
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;

  final DateTime? picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
    currentDate: today,
    helpText: 'Your last day off',
    confirmText: 'Save',
  );
  if (picked == null || !context.mounted) return false;

  final DateTime endsOn = TimeOff.dayOf(picked);
  if (endsOn == period.endsOn) return false;

  try {
    await service.changeEnd(period, endsOn);
    if (context.mounted) {
      UiFeedback.showSuccess(
        context,
        'Updated. You are back on '
        '${DateFormat('EEE, MMM d').format(endsOn.add(const Duration(days: 1)))}.',
      );
    }
    return true;
  } on RbCarsFailure catch (failure) {
    if (context.mounted) UiFeedback.showError(context, failure.message);
    return false;
  }
}

/// Shown while they are working, i.e. not inside any period.
class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) {
    return const _StatusRow(
      icon: Icons.event_available_rounded,
      tint: AppColors.success,
      background: AppColors.successSoft,
      title: 'You are taking jobs',
      body:
          'Going away? Add your vacation days so clients know. You will still '
          'appear in matching, but nobody can book you on those days.',
    );
  }
}

/// Shown while today is inside a period.
class _AwayNow extends StatelessWidget {
  const _AwayNow({required this.period, required this.busy, required this.onEnd});

  final TimeOff period;
  final bool busy;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final String until = DateFormat('EEE, MMM d').format(period.endsOn);
    final String back = DateFormat('EEE, MMM d').format(period.backOn);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _StatusRow(
          icon: Icons.beach_access_rounded,
          tint: AppColors.accent,
          background: AppColors.accentSofter,
          title: 'On vacation until $until',
          body:
              'Clients still see you in matching, marked "On vacation", but '
              'cannot book you. You are back on $back.',
        ),
        if (period.note != null) ...<Widget>[
          const SizedBox(height: AppSizes.sm),
          _PrivateNote(note: period.note!),
        ],
        const SizedBox(height: AppSizes.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy ? null : onEnd,
            icon: const Icon(Icons.work_outline_rounded, size: 18),
            label: const Text('End vacation now'),
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.tint,
    required this.background,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color tint;
  final Color background;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: AppSizes.iconTile,
          height: AppSizes.iconTile,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          ),
          child: Icon(icon, color: tint, size: 22),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: AppTextStyles.bodyStrong),
              const SizedBox(height: 2),
              Text(body, style: AppTextStyles.caption.copyWith(height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlannedRow extends StatelessWidget {
  const _PlannedRow({
    required this.period,
    required this.busy,
    required this.onRemove,
  });

  final TimeOff period;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      padding: const EdgeInsets.fromLTRB(AppSizes.md, AppSizes.sm, AppSizes.xs, AppSizes.sm),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.event_rounded, size: 20, color: AppColors.primary),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${period.rangeLabel} · ${period.days} '
                  '${period.days == 1 ? 'day' : 'days'}',
                  style: AppTextStyles.bodyStrong,
                ),
                if (period.note != null)
                  Text(
                    period.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption,
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: busy ? null : onRemove,
            icon: const Icon(Icons.close_rounded, size: 20),
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _PrivateNote extends StatelessWidget {
  const _PrivateNote({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.hint),
        const SizedBox(width: AppSizes.xs),
        Expanded(
          child: Text(
            note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
        const SizedBox(width: AppSizes.sm),
        Expanded(child: Text(message, style: AppTextStyles.caption)),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

/// Confirms the chosen dates, says what they mean, and takes a private note.
class _ConfirmVacationSheet extends StatefulWidget {
  const _ConfirmVacationSheet({
    required this.start,
    required this.end,
    required this.service,
  });

  final DateTime start;
  final DateTime end;
  final TimeOffService service;

  @override
  State<_ConfirmVacationSheet> createState() => _ConfirmVacationSheetState();
}

class _ConfirmVacationSheetState extends State<_ConfirmVacationSheet> {
  final TextEditingController _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.add(
        startsOn: widget.start,
        endsOn: widget.end,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final int days = widget.end.difference(widget.start).inDays + 1;
    final String back = DateFormat(
      'EEE, MMM d',
    ).format(widget.end.add(const Duration(days: 1)));

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        0,
        AppSizes.screenPadding,
        MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Confirm your vacation', style: AppTextStyles.title),
            const SizedBox(height: AppSizes.md),
            Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: AppColors.accentSofter,
                borderRadius: BorderRadius.circular(AppSizes.tileRadius),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.beach_access_rounded, color: AppColors.accent),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${TimeOff.formatRange(widget.start, widget.end)} · '
                          '$days ${days == 1 ? 'day' : 'days'}',
                          style: AppTextStyles.bodyStrong,
                        ),
                        Text('Back on $back', style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.md),
            const _Point(
              icon: Icons.visibility_outlined,
              text: 'Clients still see you in matching, marked "On vacation".',
            ),
            const _Point(
              icon: Icons.block_rounded,
              text: 'Nobody can book you on these days.',
            ),
            const _Point(
              icon: Icons.handyman_outlined,
              text: 'Jobs you have already accepted are not affected - '
                  'finish them before you go.',
            ),
            const SizedBox(height: AppSizes.md),
            TextField(
              controller: _note,
              maxLength: TimeOff.maxNoteLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Private note (optional)',
                hintText: 'e.g. Family trip',
                helperText: 'Only you can see this.',
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSizes.sm),
              Text(
                _error!,
                style: AppTextStyles.caption.copyWith(color: AppColors.error),
              ),
            ],
            const SizedBox(height: AppSizes.md),
            PrimaryButton(
              label: 'Save vacation',
              isLoading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSizes.sm),
          Expanded(child: Text(text, style: AppTextStyles.body)),
        ],
      ),
    );
  }
}
