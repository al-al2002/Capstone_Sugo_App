import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/technician.dart';
import '../screens/technician_profile_screen.dart';
import '../services/rb_cars_service.dart';
import '../services/technician_directory_service.dart';
import 'technician_card.dart';

/// The wider specialisation list that sits under the Top 3 on a posted job.
///
/// ## What this is, and what it is not
///
/// The Top 3 above it come from `job_matches` - the RB-CARS engine's
/// authoritative offer set, capped at three by `job_matches.rank`. This section
/// is everyone ELSE whose registered specialisation can service the job,
/// straight from `match_technicians_for_job` at ranks 4+.
///
/// Crucially it does NOT filter on completed jobs. A technician with two jobs
/// behind them appears here ranked lower, rather than being hidden - which is
/// the whole point of the section. Being new is a reason to rank below someone
/// proven, not a reason to be invisible.
///
/// It is also distinct from the "Everyone we considered" block further down.
/// That one explains the engine's reasoning and is read-only; this one is a
/// list the client can actually tap into and choose from.
///
/// ## Why it loads itself
///
/// It is supplementary. If this query fails the Top 3 must still be usable, so
/// it owns its own request and shows its own retry rather than being folded
/// into `MatchProvider` where a failure would take the screen down with it.
class MoreTechniciansSection extends StatefulWidget {
  const MoreTechniciansSection({super.key, required this.jobId});

  final String jobId;

  @override
  State<MoreTechniciansSection> createState() => _MoreTechniciansSectionState();
}

class _MoreTechniciansSectionState extends State<MoreTechniciansSection> {
  final TechnicianDirectoryService _service = TechnicianDirectoryService();

  List<Technician> _others = <Technician>[];
  bool _loading = true;
  String? _error;

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
      final List<Technician> all = await _service.forJob(widget.jobId);
      if (!mounted) return;
      setState(() {
        // Ranks 4+. The first three are already on screen above as full match
        // cards with scores and a booking button; repeating them here would
        // read as six technicians rather than three plus alternatives.
        _others = all
            .where((Technician t) => !t.isTopMatch)
            .toList(growable: false);
        _loading = false;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the other technicians.';
        _loading = false;
      });
    }
  }

  void _openProfile(Technician technician) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TechnicianProfileScreen.fromCard(technician: technician),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to add to the screen: stay silent rather than showing an empty
    // heading. Three matches and no alternatives is a normal, complete result.
    if (_loading || (_others.isEmpty && _error == null)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: AppSizes.lg),
        const Divider(color: AppColors.divider),
        const SizedBox(height: AppSizes.lg),
        Text(
          'More technicians who can fix this',
          style: AppTextStyles.headline,
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          _error == null
              ? 'Also qualified for this device, ranked by distance then '
                    'rating. Newer technicians are included here rather than '
                    'hidden. Tap anyone to see their work and reviews.'
              : _error!,
          style: AppTextStyles.subtitle,
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: AppSizes.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _load, child: const Text('Retry')),
          ),
        ] else ...<Widget>[
          const SizedBox(height: AppSizes.md),
          ..._others.map(
            (Technician technician) => Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: TechnicianCard.row(
                technician: technician,
                onTap: () => _openProfile(technician),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
