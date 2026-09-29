import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_env.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../screens/in_app_route_screen.dart';
import '../../../core/widgets/sugo_map.dart';

/// A destination on a map, with a way to actually get there.
///
/// Used by both sides of a job, for the same reason each time - somebody has to
/// travel and needs to know where to:
///
///   * the TECHNICIAN heading to a home-service address, and
///   * the CLIENT collecting a repaired unit from the workshop.
///
/// ## Why it is not `TrackingMap`
///
/// `TrackingMap` follows something that is moving, and everything about it -
/// the live pin, the staleness halo, the recentre button, the traffic overlay -
/// exists to answer "where are they now". This answers "where am I going",
/// which is a static question. Sharing one widget between them would mean a
/// pile of flags switching half of it off.
///
/// ## Why routing stays in the app
///
/// This card used to hand the coordinates to Google Maps. The brief is that
/// the journey stays inside SUGO, so the button now opens `InAppRouteScreen`,
/// which draws the road route from the user's position. The destination is
/// resolved by the server from [jobId], never taken from this widget's
/// coordinates - those are only used to draw the preview pin.
class RouteMapCard extends StatelessWidget {
  const RouteMapCard({
    super.key,
    required this.jobId,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.address,
    this.height = 180,
    this.icon = Icons.home_rounded,
  });

  /// The pin's icon: a house for a client's address (the default), a shop
  /// for the workshop.
  final IconData icon;

  /// The job whose destination this is. Routing is resolved from it.
  final String jobId;

  final double latitude;
  final double longitude;

  /// What sits at this point - "Workshop", "Client address".
  final String title;

  /// Printed under the title when known. The coordinates are never shown as a
  /// fallback: a client reading "7.07438, 125.61452" learns nothing, and the
  /// map is already showing them the place.
  final String? address;

  final double height;

  LatLng get _point => LatLng(latitude, longitude);

  void _openRoute(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InAppRouteScreen(
          jobId: jobId,
          title: title,
          subtitle: address,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          child: SizedBox(
            height: height,
            child: AppEnv.hasMapTilerKey
                ? _map()
                : _noMapFallback(),
          ),
        ),
        const SizedBox(height: AppSizes.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.place_rounded, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (address != null && address!.trim().isNotEmpty)
                    Text(
                      address!,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        SizedBox(
          height: 42,
          child: FilledButton.icon(
            onPressed: () => _openRoute(context),
            icon: const Icon(Icons.directions_rounded, size: 18),
            label: const Text('Show route'),
          ),
        ),
      ],
    );
  }

  Widget _map() {
    return FlutterMap(
      options: MapOptions(
        initialCenter: _point,
        initialZoom: 15,
        // Static by design: this is a destination, not something to explore.
        // Letting it pan invites a user to drag it somewhere and then wonder
        // why the pin left the screen.
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
      ),
      children: <Widget>[
        const SugoMapTiles(),
        MarkerLayer(
          markers: <Marker>[
            Marker(
              point: _point,
              width: SugoMapPin.markerWidth,
              height: SugoMapPin.markerHeight(labelled: false),
              alignment: Alignment.topCenter,
              child: SugoMapPin(icon: icon, color: AppColors.accentDark),
            ),
          ],
        ),
      ],
    );
  }

  /// Without a MapTiler key there are no tiles to draw on. A grey box that says
  /// so beats a blank one that looks broken.
  Widget _noMapFallback() {
    return Container(
      color: AppColors.primarySofter,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.map_outlined, size: 26, color: AppColors.hint),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Map preview unavailable in this build.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
