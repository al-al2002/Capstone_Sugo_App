import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../rb_cars/models/technician.dart';
import '../../rb_cars/providers/technician_directory_provider.dart';
import '../../rb_cars/widgets/technician_card.dart';

/// Horizontally scrolling technician cards: the dashboard's "best performers".
///
/// Loads from the `recommended_technicians` RPC, so it can fail independently
/// of the rest of the home screen. A failure shows a retry inside this row and
/// leaves everything above and below it working.
///
/// Ranking is rating then completed jobs, decided in SQL. Distance appears on
/// the cards but does not order them - see the RPC's header comment for why
/// this row and task matching deliberately sort differently.
///
/// Tall enough for the avatar row, the name, the specialisation and the two
/// fact lines without clipping any of them.
/// 182, not the old 172: the redesign's type scale raised the row title from
/// 13.5 to 15 and the fact lines from 10.5 to 12, and the vacation variant -
/// the tallest of them - overflowed the old height by a pixel. Legibility is
/// worth ten pixels of row.
const double _cardHeight = 182;

class RecommendedTechnicians extends StatelessWidget {
  const RecommendedTechnicians({
    super.key,
    required this.provider,
    required this.onSelect,
  });

  final TechnicianDirectoryProvider provider;
  final void Function(Technician technician) onSelect;

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading) {
      return const SizedBox(
        height: _cardHeight,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }

    if (provider.error != null) {
      return _RowMessage(
        icon: Icons.cloud_off_rounded,
        message: provider.error!,
        actionLabel: 'Retry',
        onAction: provider.refresh,
      );
    }

    if (provider.isEmpty) {
      // States the entry rule rather than apologising for an empty row.
      //
      // Since migration 20260921000007 this row is a shortlist, not a
      // directory: a technician needs 20 completed jobs and a 4.0+ review
      // average before SUGO will vouch for them. An empty row therefore does
      // not mean "nothing loaded" - it means nobody has earned the spot yet,
      // and saying so turns a screen that looks broken into one that explains
      // the standard being applied.
      //
      // It also points at the surface that *does* list everyone, so the row
      // is never a dead end.
      return const _RowMessage(
        icon: Icons.workspace_premium_outlined,
        message:
            'Nobody has earned a spot here yet. Technicians appear once they '
            'have completed 20 jobs with good reviews.\n\n'
            'Post a job and we will still rank the best matches for you.',
      );
    }

    return SizedBox(
      height: _cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
        itemCount: provider.technicians.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSizes.md),
        itemBuilder: (BuildContext context, int index) {
          final Technician technician = provider.technicians[index];
          return TechnicianCard.compact(
            technician: technician,
            onTap: () => onSelect(technician),
          );
        },
      ),
    );
  }
}

class _RowMessage extends StatelessWidget {
  const _RowMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 22, color: AppColors.hint),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption.copyWith(fontSize: 12, height: 1.35),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
