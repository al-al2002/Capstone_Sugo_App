import 'package:flutter/material.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/widgets/sugo_pill.dart';

/// The four home filters. Values are the enum, labels come from it, so the row
/// and the screen can never drift apart.
enum HomeFilter {
  all('All', Icons.apps_rounded),
  booked('Booked', Icons.event_available_rounded),
  technicians('Technicians', Icons.engineering_rounded),
  history('History', Icons.history_rounded);

  const HomeFilter(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Horizontal pill tabs under the search bar.
///
/// Active tab is filled with the primary blue; the rest are outlined and muted,
/// which is the same treatment [SugoPill] gives selected chips elsewhere.
class HomeFilterTabs extends StatelessWidget {
  const HomeFilterTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final HomeFilter selected;
  final ValueChanged<HomeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.filterTabHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
        itemCount: HomeFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSizes.sm),
        itemBuilder: (BuildContext context, int index) {
          final HomeFilter filter = HomeFilter.values[index];
          return SugoPill(
            label: filter.label,
            icon: filter.icon,
            selected: filter == selected,
            onTap: () => onChanged(filter),
          );
        },
      ),
    );
  }
}
