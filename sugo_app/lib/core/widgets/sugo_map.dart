import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_env.dart';
import '../constants/app_colors.dart';
import '../theme/app_elevation.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';

// The pieces every SUGO map is drawn from, so the tracking map, the route
// screen, the route preview and the location pickers look like one product
// (2026-09-29, "mas pa gwapohon ang mga mapa").
//
// ## What changed, and why it looked worse before
//
// * **Sharp tiles.** The maps asked for 256-pixel tiles and stretched them on
//   phones with two or three pixels per point, which is every current phone
//   - hence the soft, smeared streets. [SugoMapTiles] asks MapTiler for the
//   `@2x` tiles on a high-density screen instead.
// * **A calmer base.** `dataviz` in place of `streets-v2`: pale land, soft
//   blue water, and street names at readable sizes. The busy default fought
//   with the navy route and orange pins drawn over it; a quiet base lets the
//   things that matter - where they are, where they are going - stand out.
// * **One pin, one line, one moving dot**, shared below, instead of a
//   slightly different drawing on each screen.

/// A tight shadow for things standing on the map. The app's card shadows
/// throw a wide, low cloud that, under a small disc, reads as a grey blob
/// beneath it rather than as lift.
const List<BoxShadow> _onMapShadow = <BoxShadow>[
  BoxShadow(color: Color(0x400B2B5C), blurRadius: 6, offset: Offset(0, 2)),
];

/// The base map.
class SugoMapTiles extends StatelessWidget {
  const SugoMapTiles({super.key});

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: AppEnv.mapTilerTileUrl,
      userAgentPackageName: 'com.example.sugo_app',
      // Fills `{r}` in the template with "@2x" on a high-density screen.
      retinaMode: RetinaMode.isHighDensity(context),
      maxZoom: 19,
    );
  }
}

/// A road route: a soft navy halo, a white casing, then the line, so it reads
/// on any tile - over a white street as well as a grey block.
List<Polyline<Object>> sugoRouteLines(
  List<LatLng> points, {
  Color color = AppColors.primary,
}) {
  return <Polyline<Object>>[
    Polyline<Object>(
      points: points,
      color: AppColors.navy.withValues(alpha: 0.18),
      strokeWidth: 13,
    ),
    Polyline<Object>(points: points, color: Colors.white, strokeWidth: 9),
    Polyline<Object>(points: points, color: color, strokeWidth: 5.5),
  ];
}

/// Metres from [at] to the nearest point of [route]. Road routes from TomTom
/// have points a few tens of metres apart in a city, so the nearest vertex is
/// close enough to decide "has this person left the route?".
double distanceToRoute(LatLng at, List<LatLng> route) {
  const Distance distance = Distance();
  double best = double.infinity;
  for (final LatLng p in route) {
    final double d = distance.as(LengthUnit.Meter, at, p);
    if (d < best) best = d;
  }
  return best;
}

/// The part of [route] still ahead of [from], starting at [from] itself - so
/// a route line shrinks behind a moving marker without a new request.
List<LatLng> routeAhead(LatLng from, List<LatLng> route) {
  if (route.isEmpty) return <LatLng>[from];
  const Distance distance = Distance();
  int nearest = 0;
  double best = double.infinity;
  for (int i = 0; i < route.length; i++) {
    final double d = distance.as(LengthUnit.Meter, from, route[i]);
    if (d < best) {
      best = d;
      nearest = i;
    }
  }
  return <LatLng>[from, ...route.sublist(nearest)];
}

/// Where someone is going: a coloured disc with an icon, on a short stem to
/// the exact spot, and an optional name above it.
///
/// Place it with `alignment: Alignment.topCenter` in its [Marker], so the tip
/// of the stem - not the middle of the disc - sits on the coordinate. Size the
/// marker with [markerWidth] and [markerHeight].
class SugoMapPin extends StatelessWidget {
  const SugoMapPin({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
    this.label,
  });

  final IconData icon;
  final Color color;

  /// "Your address", "Workshop". Null draws the pin alone.
  final String? label;

  static const double markerWidth = 150;
  static double markerHeight({required bool labelled}) => labelled ? 90 : 56;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (label != null) ...<Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: AppElevation.sm,
              ),
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.micro.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: _onMapShadow,
            ),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
          // The point of the pin: a stem to the exact spot, so the disc does
          // not hide the doorway it is marking.
          Container(
            width: 3,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Whoever is travelling: a disc with their icon, and a soft ring pulsing out
/// of it while their position is live.
///
/// The pulse is the one piece of motion on a tracking map, and it means
/// something: "this is live". A position that has gone stale stops pulsing
/// and turns grey, so an old dot never looks like a moving one. Still under
/// reduced motion.
class SugoTravellerMarker extends StatefulWidget {
  const SugoTravellerMarker({
    super.key,
    required this.icon,
    required this.color,
    required this.isLive,
  });

  final IconData icon;
  final Color color;
  final bool isLive;

  /// The [Marker] size that leaves room for the pulse.
  static const double size = 72;

  @override
  State<SugoTravellerMarker> createState() => _SugoTravellerMarkerState();
}

class _SugoTravellerMarkerState extends State<SugoTravellerMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SugoTravellerMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final bool animate = widget.isLive && !AppMotion.reduced(context);
    if (animate && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!animate && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color fill = widget.isLive ? widget.color : AppColors.hint;

    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        if (widget.isLive)
          AnimatedBuilder(
            animation: _pulse,
            builder: (BuildContext context, Widget? _) {
              final double t = _pulse.value;
              return Container(
                width: 42 + 30 * t,
                height: 42 + 30 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill.withValues(alpha: 0.28 * (1 - t)),
                ),
              );
            },
          ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: _onMapShadow,
          ),
          child: Icon(widget.icon, size: 20, color: Colors.white),
        ),
      ],
    );
  }
}
