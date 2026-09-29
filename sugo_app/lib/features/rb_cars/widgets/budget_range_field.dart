import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_sizes.dart';
import '../theme/posting_text.dart';
import '../../../core/constants/app_colors.dart';

/// Two peso amounts that become `jobs.budget_min` and `jobs.budget_max`.
///
/// The ceiling is what Stage 2 actually scores against: a technician's tier
/// rate times a typical job length is compared to `budget_max`, and quotes over
/// it lose points on a linear slope. Both stay optional - leaving the range
/// untouched scores every technician at a neutral 0.7 rather than excluding
/// anyone.
///
/// ## Why a slider replaced the two number fields
///
/// The pair of text boxes could express a backwards range, so the widget
/// carried a validator and an error line for `min > max`. A `RangeSlider`
/// cannot produce that state at all, which removes the error rather than
/// reporting it. It also stops a client typing 50 into a field whose realistic
/// floor is [_floor].
///
/// The trade is precision, and it is a cheap one: budget feeds a linear score,
/// not a filter, so PHP 1,150 and PHP 1,200 rank identically anyway.
class BudgetRangeField extends StatelessWidget {
  const BudgetRangeField({
    super.key,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double? min;
  final double? max;
  final void Function(double? min, double? max) onChanged;

  /// Below this nobody is being paid for a call-out, so the track starts here.
  static const double _floor = 300;

  /// The top of the track. Anything above it is "3,000+" - a ceiling the
  /// scorer treats as "budget is not the constraint".
  static const double _ceiling = 3000;

  static const double _step = 50;

  /// Where an untouched slider sits. Deliberately not written to the draft:
  /// the handles have to show *somewhere*, but until the client moves one,
  /// `budget_min` and `budget_max` stay null and budget stays out of the
  /// ranking entirely.
  static const RangeValues _resting = RangeValues(850, 1200);

  bool get _isSet => min != null || max != null;

  @override
  Widget build(BuildContext context) {
    final RangeValues values = _isSet
        ? RangeValues(
            (min ?? _floor).clamp(_floor, _ceiling),
            (max ?? _ceiling).clamp(_floor, _ceiling),
          )
        : _resting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(_peso(_floor), style: PostingText.caption),
            Flexible(
              child: Text(
                _isSet
                    ? '${_peso(values.start)} - ${_peso(values.end)}'
                    : 'Any budget',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _isSet
                      ? AppColors.primaryDark
                      : AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('${_peso(_ceiling)}+', style: PostingText.caption),
          ],
        ),
        // Greyed until the client actually sets a range.
        //
        // The handles have to sit somewhere, so an untouched slider shows them
        // at [_resting] - and that looked exactly like a range the client had
        // chosen. People reasonably believed they had set a budget, posted the
        // job, and found "No budget set" on the booking.
        //
        // Colour is what carries the state now, rather than the word "Any
        // budget" and a paragraph of small print underneath. The first drag
        // calls onChanged, `_isSet` flips, and the control comes alive - so
        // "inactive" is visible at a glance instead of being something you have
        // to read.
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _isSet ? AppColors.primary : AppColors.divider,
            inactiveTrackColor: AppColors.divider,
            thumbColor: _isSet ? AppColors.primary : AppColors.hint,
            overlayColor: (_isSet ? AppColors.primary : AppColors.hint)
                .withValues(alpha: 0.12),
            valueIndicatorColor: _isSet
                ? AppColors.primary
                : AppColors.textSecondary,
            rangeThumbShape: const RoundRangeSliderThumbShape(
              // Slightly smaller while inactive, so it reads as dormant rather
              // than as a control someone has already positioned.
              enabledThumbRadius: 9,
            ),
          ),
          child: RangeSlider(
            values: values,
            min: _floor,
            max: _ceiling,
            divisions: ((_ceiling - _floor) / _step).round(),
            labels: RangeLabels(_peso(values.start), _peso(values.end)),
            onChanged: (RangeValues next) => onChanged(next.start, next.end),
          ),
        ),
        if (_isSet)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => onChanged(null, null),
              child: const Text('Clear budget'),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(top: AppSizes.xs),
            child: Text(
              'Optional - no budget set. Drag either handle to choose a '
              'range. Leaving it alone rules nobody out; it just keeps budget '
              'out of the ranking.',
              style: PostingText.caption,
            ),
          ),
      ],
    );
  }

  static String _peso(double value) =>
      NumberFormat.currency(symbol: '₱', decimalDigits: 0).format(value);
}
