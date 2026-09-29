import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_pill.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../models/device_category.dart';

/// How the directory is ordered.
enum TechnicianSort {
  recommended('Recommended'),
  nearest('Nearest first'),
  rating('Highest rated'),
  jobs('Most jobs done'),
  price('Lowest price');

  const TechnicianSort(this.label);

  final String label;
}

/// The directory's filter state.
///
/// Immutable, so "Apply" is a single value the screen can adopt and "Reset" is
/// a constructor call. A mutable settings object shared with the sheet is how
/// filters end up applying themselves while the user is still choosing.
class TechnicianFilters {
  const TechnicianFilters({
    this.categories = const <DeviceCategory>{},
    this.maxDistanceKm,
    this.minRating = 0,
    this.maxHourlyFee,
    this.availableOnly = false,
    this.favoritesOnly = false,
  });

  final Set<DeviceCategory> categories;
  final double? maxDistanceKm;
  final double minRating;
  final int? maxHourlyFee;

  /// Hide technicians who are on vacation and cannot be booked.
  final bool availableOnly;

  final bool favoritesOnly;

  int get activeCount =>
      (categories.isEmpty ? 0 : 1) +
      (maxDistanceKm == null ? 0 : 1) +
      (minRating > 0 ? 1 : 0) +
      (maxHourlyFee == null ? 0 : 1) +
      (availableOnly ? 1 : 0) +
      (favoritesOnly ? 1 : 0);

  TechnicianFilters copyWith({
    Set<DeviceCategory>? categories,
    double? maxDistanceKm,
    double? minRating,
    int? maxHourlyFee,
    bool? availableOnly,
    bool? favoritesOnly,
    bool clearDistance = false,
    bool clearFee = false,
  }) {
    return TechnicianFilters(
      categories: categories ?? this.categories,
      maxDistanceKm: clearDistance ? null : (maxDistanceKm ?? this.maxDistanceKm),
      minRating: minRating ?? this.minRating,
      maxHourlyFee: clearFee ? null : (maxHourlyFee ?? this.maxHourlyFee),
      availableOnly: availableOnly ?? this.availableOnly,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    );
  }
}

/// Opens the filter sheet. Returns the filters to apply, or null if dismissed.
///
/// ## Why a sheet and not a screen
///
/// Filtering is an adjustment to a list you are already looking at. A sheet
/// keeps that list half-visible behind it, so the change reads as tuning
/// rather than as going somewhere - and dismissing it is a swipe rather than a
/// back navigation that might lose your place.
///
/// Sorting lives in the same sheet, at the top. It is a different kind of
/// control, so it is separated by a divider rather than given a screen of its
/// own for one row of chips.
Future<TechnicianFilters?> showTechnicianFilterSheet(
  BuildContext context, {
  required TechnicianFilters current,
  required TechnicianSort sort,
  required bool canSortByDistance,
  required ValueChanged<TechnicianSort> onSortChanged,
}) {
  return showSugoBottomSheet<TechnicianFilters>(
    context: context,
    title: 'Filter & sort',
    subtitle: 'Narrow the list to the technicians you would actually book.',
    builder: (BuildContext sheetContext) => _FilterBody(
      initial: current,
      sort: sort,
      canSortByDistance: canSortByDistance,
      onSortChanged: onSortChanged,
    ),
  );
}

class _FilterBody extends StatefulWidget {
  const _FilterBody({
    required this.initial,
    required this.sort,
    required this.canSortByDistance,
    required this.onSortChanged,
  });

  final TechnicianFilters initial;
  final TechnicianSort sort;
  final bool canSortByDistance;
  final ValueChanged<TechnicianSort> onSortChanged;

  @override
  State<_FilterBody> createState() => _FilterBodyState();
}

class _FilterBodyState extends State<_FilterBody> {
  late TechnicianFilters _draft = widget.initial;
  late TechnicianSort _sort = widget.sort;

  static const List<(String, double?)> _distances = <(String, double?)>[
    ('Any', null),
    ('Within 2 km', 2),
    ('Within 5 km', 5),
    ('Within 10 km', 10),
    ('Within 20 km', 20),
  ];

  static const List<(String, double)> _ratings = <(String, double)>[
    ('Any', 0),
    ('3.5+', 3.5),
    ('4.0+', 4.0),
    ('4.5+', 4.5),
  ];

  /// Bands from the published tier rates: standard ₱350, pro ₱550, elite ₱800.
  static const List<(String, int?)> _prices = <(String, int?)>[
    ('Any', null),
    ('Up to ₱400/hr', 400),
    ('Up to ₱600/hr', 600),
    ('Up to ₱800/hr', 800),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _Label('Sort by'),
        Wrap(
          spacing: AppSizes.sm,
          runSpacing: AppSizes.sm,
          children: <Widget>[
            for (final TechnicianSort option in TechnicianSort.values)
              if (option != TechnicianSort.nearest || widget.canSortByDistance)
                SugoPill(
                  label: option.label,
                  selected: _sort == option,
                  onTap: () => setState(() => _sort = option),
                ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSizes.lg),
          child: Divider(height: 1),
        ),
        const _Label('Service type'),
        Wrap(
          spacing: AppSizes.sm,
          runSpacing: AppSizes.sm,
          children: <Widget>[
            for (final DeviceCategory c in DeviceCategory.values)
              SugoPill(
                label: c.label,
                selected: _draft.categories.contains(c),
                onTap: () => setState(() {
                  final Set<DeviceCategory> next = Set<DeviceCategory>.of(
                    _draft.categories,
                  );
                  if (!next.remove(c)) next.add(c);
                  _draft = _draft.copyWith(categories: next);
                }),
              ),
          ],
        ),
        if (widget.canSortByDistance) ...<Widget>[
          const _Label('Distance'),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.sm,
            children: <Widget>[
              for (final (String label, double? km) in _distances)
                SugoPill(
                  label: label,
                  selected: _draft.maxDistanceKm == km,
                  onTap: () => setState(
                    () => _draft = km == null
                        ? _draft.copyWith(clearDistance: true)
                        : _draft.copyWith(maxDistanceKm: km),
                  ),
                ),
            ],
          ),
        ],
        const _Label('Minimum rating'),
        Wrap(
          spacing: AppSizes.sm,
          runSpacing: AppSizes.sm,
          children: <Widget>[
            for (final (String label, double value) in _ratings)
              SugoPill(
                label: label,
                icon: value == 0 ? null : Icons.star_rounded,
                selected: _draft.minRating == value,
                onTap: () => setState(
                  () => _draft = _draft.copyWith(minRating: value),
                ),
              ),
          ],
        ),
        const _Label('Starting price'),
        Wrap(
          spacing: AppSizes.sm,
          runSpacing: AppSizes.sm,
          children: <Widget>[
            for (final (String label, int? fee) in _prices)
              SugoPill(
                label: label,
                selected: _draft.maxHourlyFee == fee,
                onTap: () => setState(
                  () => _draft = fee == null
                      ? _draft.copyWith(clearFee: true)
                      : _draft.copyWith(maxHourlyFee: fee),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSizes.xs),
          child: Text(
            'Published hourly rates by tier — ${Fmt.peso(350)}, '
            '${Fmt.peso(550)} and ${Fmt.peso(800)}. The final price is agreed '
            'with your technician after they diagnose the problem.',
            style: AppTextStyles.micro,
          ),
        ),
        const _Label('Availability'),
        Column(
          children: <Widget>[
            _Toggle(
              label: 'Available to book now',
              hint: 'Hides technicians who are on vacation',
              value: _draft.availableOnly,
              onChanged: (bool v) =>
                  setState(() => _draft = _draft.copyWith(availableOnly: v)),
            ),
            _Toggle(
              label: 'Favourites only',
              hint: 'Technicians you saved on this phone',
              value: _draft.favoritesOnly,
              onChanged: (bool v) =>
                  setState(() => _draft = _draft.copyWith(favoritesOnly: v)),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.xl),
        Row(
          children: <Widget>[
            Expanded(
              child: SugoButton(
                label: 'Reset',
                variant: SugoButtonVariant.outlined,
                onPressed: () => setState(() {
                  _draft = const TechnicianFilters();
                  _sort = TechnicianSort.recommended;
                }),
              ),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              flex: 2,
              child: SugoButton(
                label: _draft.activeCount == 0
                    ? 'Apply'
                    : 'Apply ${_draft.activeCount} filter'
                          '${_draft.activeCount == 1 ? '' : 's'}',
                onPressed: () {
                  widget.onSortChanged(_sort);
                  Navigator.of(context).pop(_draft);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.lg, bottom: AppSizes.sm),
      child: Text(text, style: AppTextStyles.overline),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(AppSizes.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: AppTextStyles.bodyStrong.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 1),
                  Text(hint, style: AppTextStyles.micro),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
