import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../onboarding/models/travel_conditions.dart';
import '../models/technician_profile_details.dart';

/// "How they work" on a technician's profile (2026-11-23): what they take,
/// and whether they still travel in rain or heavy traffic - their own
/// answers, the same ones matching weighs on a rainy or jammed day.
///
/// Added at the user's request ("view technician profile, show the work on
/// rain or traffic"). Three tiles side by side, each tinted by its answer:
/// green when they go, amber when they do not, grey when not answered - so a
/// client deciding on a stormy afternoon sees it at a glance.
class HowTheyWorkCard extends StatelessWidget {
  const HowTheyWorkCard({super.key, required this.how});

  final HowTheyWork how;

  @override
  Widget build(BuildContext context) {
    final String work = switch ((how.homeService, how.shopRepair)) {
      (true, true) => 'Home & shop',
      (true, false) => 'Home service',
      (false, true) => 'Shop repair',
      (false, false) => 'Not set',
    };

    final (String rain, _Tone rainTone) = switch (how.rain) {
      RainTravel.any => ('Even in heavy rain', _Tone.go),
      RainTravel.notHeavy => ('Rain, not storms', _Tone.partly),
      RainTravel.never => ('Not in the rain', _Tone.stop),
      null => ('Not answered', _Tone.unknown),
    };

    final (String traffic, _Tone trafficTone) = switch (how.traffic) {
      TrafficTravel.goes => ('Goes in heavy traffic', _Tone.go),
      TrafficTravel.avoids => ('Avoids heavy traffic', _Tone.stop),
      null => ('Not answered', _Tone.unknown),
    };

    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[AppColors.secondary, AppColors.cyan],
                  ),
                ),
                child: const Icon(
                  Icons.engineering_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              const Text('How they work', style: AppTextStyles.label),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _Tile(
                    icon: Icons.home_repair_service_rounded,
                    label: 'Takes',
                    value: work,
                    tone: _Tone.brand,
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: _Tile(
                    icon: Icons.thunderstorm_rounded,
                    label: 'In the rain',
                    value: rain,
                    tone: rainTone,
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: _Tile(
                    icon: Icons.traffic_rounded,
                    label: 'Heavy traffic',
                    value: traffic,
                    tone: trafficTone,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Tone {
  brand(AppColors.primary, AppColors.primarySoft),
  go(AppColors.success, Color(0xFFE7F6EE)),
  partly(AppColors.secondaryDark, AppColors.secondarySoft),
  stop(AppColors.warning, AppColors.warningSoft),
  unknown(AppColors.textSecondary, AppColors.background);

  const _Tone(this.ink, this.wash);

  final Color ink;
  final Color wash;
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.sm,
          AppSizes.sm + 2,
          AppSizes.sm,
          AppSizes.sm + 2,
        ),
        decoration: BoxDecoration(
          color: tone.wash,
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          border: Border.all(color: tone.ink.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20, color: tone.ink),
            const SizedBox(height: AppSizes.xs + 2),
            Text(
              label,
              style: AppTextStyles.micro.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w800,
                color: tone.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
