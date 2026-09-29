import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../models/tracking_weather.dart';
import '../services/tracking_service.dart';

/// Conditions at the destination of the current tracking leg.
///
/// ## Why it fetches on a leg change and nothing else
///
/// The tracking screen is driven by a realtime stream that emits on every GPS
/// fix - every few seconds for the length of a delivery. Rebuilding is cheap;
/// refetching a forecast is not. One request per fix would be roughly three
/// orders of magnitude more OpenWeatherMap calls than the matcher makes, and
/// would empty the free tier in a day.
///
/// So this widget requests once when it appears, and again only when
/// [headsToClient] flips - the only moments the destination actually moves,
/// between the client's address and the workshop. Position updates change
/// where the van is, not where it is going.
///
/// ## Why it disappears rather than erroring
///
/// [TrackingService.weatherFor] returns null for every failure - key unset,
/// provider down, no transport leg, no destination coordinate. All of them mean
/// the same thing here: draw nothing. A client watching their appliance travel
/// does not need a forecast error, and the screen's real job is unaffected.
class WeatherChip extends StatefulWidget {
  const WeatherChip({
    super.key,
    required this.jobId,
    required this.headsToClient,
  });

  final String jobId;

  /// True while the leg ends at the client's address rather than the
  /// workshop. The only input that justifies a refetch.
  final bool headsToClient;

  @override
  State<WeatherChip> createState() => _WeatherChipState();
}

class _WeatherChipState extends State<WeatherChip> {
  final TrackingService _service = TrackingService();

  TrackingWeather? _weather;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WeatherChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The destination moved. Note this deliberately does NOT test the job id:
    // a different job is a different screen, not a rebuild of this one.
    if (oldWidget.headsToClient != widget.headsToClient) _load();
  }

  Future<void> _load() async {
    final TrackingWeather? weather = await _service.weatherFor(widget.jobId);
    if (!mounted) return;
    setState(() => _weather = weather);
  }

  @override
  Widget build(BuildContext context) {
    final TrackingWeather? weather = _weather;

    // Also covers the first frame, before the request comes back. A spinner
    // here would draw more attention to the forecast than it deserves.
    if (weather == null) return const SizedBox.shrink();

    final bool adverse = weather.isAdverse;
    final String? temperature = weather.temperatureLabel;

    return Container(
      margin: const EdgeInsets.only(top: AppSizes.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      decoration: BoxDecoration(
        color: adverse ? AppColors.warningSoft : AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(
          color: adverse ? AppColors.warning : AppColors.border,
          width: adverse ? 1.2 : 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            _iconFor(weather),
            size: 16,
            color: adverse ? AppColors.warning : AppColors.primary,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              weather.sentence,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: adverse
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          if (temperature != null) ...<Widget>[
            const SizedBox(width: AppSizes.sm),
            Text(
              temperature,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Chosen from the provider's condition group, falling back to the severity
  /// when the group is missing - so an unrecognised condition still gets a
  /// sensible glyph rather than none.
  IconData _iconFor(TrackingWeather weather) {
    return switch (weather.condition?.toLowerCase()) {
      'thunderstorm' => Icons.thunderstorm_rounded,
      'drizzle' => Icons.grain_rounded,
      'rain' => Icons.water_drop_rounded,
      'snow' => Icons.ac_unit_rounded,
      'clear' => Icons.wb_sunny_rounded,
      'clouds' => Icons.cloud_rounded,
      'mist' || 'haze' || 'fog' || 'smoke' || 'dust' || 'sand' || 'ash' =>
        Icons.foggy,
      _ => weather.isAdverse ? Icons.umbrella_rounded : Icons.wb_cloudy_rounded,
    };
  }
}
