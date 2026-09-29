import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_env.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../models/job_tracking.dart';
import '../models/route_result.dart';
import '../services/tracking_service.dart';
import '../../../core/widgets/sugo_map.dart';

/// The live map: whoever is travelling, where they are going, and the road
/// between them.
///
/// ## The route (2026-09-29)
///
/// It used to be a straight dotted line, because a directions call per GPS
/// fix would empty the free tier within one delivery. It is now the road
/// route (`job-route`, live mode), fetched sparingly:
///
/// * once when the map opens, and again when the stage changes (the
///   destination flips);
/// * again only when the traveller has drifted more than [_offRouteMetres]
///   from the drawn route, and never more than once per [_minRouteInterval] -
///   a wrong turn, or a road the route did not expect;
/// * between fetches the line is trimmed to start at the moving marker, so it
///   shrinks as they drive without another request.
///
/// If no route can be had - no key, no road between the points, the provider
/// down - the old dotted straight line comes back, which is still honest about
/// which way and roughly how far.
///
/// ## Honesty about staleness
///
/// A position that has stopped updating is drawn hollow with a dashed halo
/// rather than as a confident dot, and the freshness label says how old it is.
/// A tracking screen that shows a stale fix as live is worse than one that
/// admits it has lost contact.
class TrackingMap extends StatefulWidget {
  const TrackingMap({
    super.key,
    required this.tracking,
    required this.destination,
    this.destinationLabel = 'Destination',
    this.height = 300,
    this.rounded = true,
    this.bottomInset = 0,
    this.travellerIcon,
    this.destinationIcon = Icons.place_rounded,
    this.showRoute = true,
    this.service,
  });

  /// The destination pin's icon: a house for the client, a shop for the
  /// workshop.
  final IconData destinationIcon;

  /// Draw the road route. Off only where a route would be noise.
  final bool showRoute;

  /// Tests pass a fake; the app uses the real service.
  final TrackingService? service;

  final JobTracking tracking;

  /// The moving pin's icon. Defaults to the stage's (a van, a car); the
  /// client's trip to the workshop passes a person instead.
  final IconData? travellerIcon;

  /// Where this leg is heading: the shop on the way in, the client on the way
  /// back. Null when we do not know, in which case only the van is drawn.
  final LatLng? destination;

  final String destinationLabel;
  final double height;

  /// False when the map is full-bleed behind a sheet, where rounded corners
  /// would show the page ground through them.
  final bool rounded;

  /// How much of the map's bottom is covered by something else - the tracking
  /// sheet. Controls and attribution are lifted above it, so the recentre
  /// button is not hidden under the sheet the moment the screen opens.
  final double bottomInset;

  @override
  State<TrackingMap> createState() => _TrackingMapState();
}

class _TrackingMapState extends State<TrackingMap>
    with SingleTickerProviderStateMixin {
  final MapController _controller = MapController();
  bool _followTechnician = true;

  /// Slides the van between fixes instead of teleporting it.
  ///
  /// Positions arrive every few seconds at best, and on a poor connection far
  /// less often. Snapping the marker to each one makes a technician look like
  /// they are jumping between streets; easing between them over
  /// [AppMotion.slow] reads as a vehicle moving, which is what is actually
  /// happening between the two samples.
  ///
  /// This is interpolation for legibility, not invented precision: the marker
  /// only ever travels between two *real* reported positions, and the
  /// freshness chip still states how old the latest one is.
  late final AnimationController _move;
  LatLng? _from;
  LatLng? _to;

  /// False until a `FlutterMap` has actually been built with this controller.
  ///
  /// `MapController.camera` throws if the controller was never attached, and
  /// this widget legitimately renders without a map - when there is no MapTiler
  /// key, or before the first position arrives. Without this guard the first
  /// tracking update in those states crashed on `_controller.camera.zoom`.
  bool _mapAttached = false;

  /// Traffic overlay, off by default.
  ///
  /// Every traffic tile is an edge-function invocation - see
  /// `AppEnv.trafficTileUrl` for why it is proxied rather than fetched straight
  /// from TomTom - so leaving it on for every tracking session would spend
  /// quota on an overlay most clients are not reading. Off until asked for.
  bool _showTraffic = false;

  // ---------------------------------------------------------------- route

  /// Never ask for a route more often than this.
  static const Duration _minRouteInterval = Duration(seconds: 60);

  /// How far off the drawn route counts as "took another road".
  static const double _offRouteMetres = 200;

  late final TrackingService _routes = widget.service ?? TrackingService();

  /// The road route for the current leg, or null for the dotted fallback.
  List<LatLng>? _route;
  DateTime? _routeAt;
  TrackingStage? _routeStage;
  bool _routing = false;

  /// Asks for a route when the rules in the class note say it is worth it.
  void _maybeRoute() {
    if (!widget.showRoute || _routing || !AppEnv.hasMapTilerKey) return;
    final LatLng? at = _technicianPoint;
    if (at == null || widget.destination == null) return;

    final bool newLeg = _routeStage != widget.tracking.stage;
    final DateTime? last = _routeAt;
    final bool due =
        last == null || DateTime.now().difference(last) >= _minRouteInterval;
    final List<LatLng>? route = _route;
    final bool offRoute =
        route == null || distanceToRoute(at, route) > _offRouteMetres;

    if (newLeg || (offRoute && due)) _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    _routing = true;
    final TrackingStage stage = widget.tracking.stage;
    try {
      final RouteResult result = await _routes.liveRoute(widget.tracking.jobId);
      if (!mounted) return;
      setState(() {
        _route = result.available ? result.points : null;
        _routeAt = DateTime.now();
        _routeStage = stage;
      });
    } finally {
      _routing = false;
    }
  }


  /// Auth headers for the tile proxy, built once per toggle.
  ///
  /// `traffic-tile` requires a signed-in caller, so the session token rides on
  /// each tile request. Built on demand rather than in `initState` because a
  /// token refreshed mid-session would otherwise be stale here; a session that
  /// expires while the overlay is open simply stops returning tiles, which
  /// degrades to the plain base map.
  Map<String, String> _tileHeaders() {
    final String? token =
        SupabaseService.auth.currentSession?.accessToken;
    return <String, String>{
      'apikey': AppEnv.supabaseAnonKey,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// The latest reported position.
  LatLng? get _technicianPoint {
    final JobTracking t = widget.tracking;
    if (!t.hasPosition) return null;
    return LatLng(t.latitude!, t.longitude!);
  }

  /// Where to draw the van this frame: somewhere between the last two fixes.
  LatLng? get _displayPoint {
    final LatLng? to = _to ?? _technicianPoint;
    final LatLng? from = _from;
    if (to == null) return null;
    if (from == null || !_move.isAnimating) return to;
    final double t = Curves.easeInOut.transform(_move.value);
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  @override
  void initState() {
    super.initState();
    _move = AnimationController(vsync: this, duration: AppMotion.slow);
    _to = _technicianPoint;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeRoute();
    });
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    final LatLng? next = _technicianPoint;
    final LatLng? previous = _to;
    if (next != null &&
        (previous == null ||
            previous.latitude != next.latitude ||
            previous.longitude != next.longitude)) {
      _from = _displayPoint ?? previous;
      _to = next;
      if (_from == null || MediaQuery.disableAnimationsOf(context)) {
        _move.value = 1;
      } else {
        _move.forward(from: 0);
      }
    }

    _maybeRoute();

    // Recentre only while following, so a client who has panned to look at the
    // route is not yanked back every time a fix arrives. Skipped entirely when
    // no map has been built, because the controller has no camera to read.
    if (!_mapAttached) return;

    if (_followTechnician && next != null) {
      _controller.move(next, _controller.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LatLng? technician = _technicianPoint;
    final LatLng? destination = widget.destination;

    if (!AppEnv.hasMapTilerKey) {
      _mapAttached = false;
      return _MapUnavailable(height: widget.height, tracking: widget.tracking);
    }

    if (technician == null && destination == null) {
      _mapAttached = false;
      return _AwaitingFix(height: widget.height);
    }

    _mapAttached = true;

    final LatLng centre =
        technician ??
        destination ??
        const LatLng(AppEnv.defaultLatitude, AppEnv.defaultLongitude);

    return ClipRRect(
      borderRadius: BorderRadius.circular(
        widget.rounded ? AppSizes.tileRadius : 0,
      ),
      child: SizedBox(
        height: widget.height.isFinite ? widget.height : null,
        child: Stack(
          children: <Widget>[
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: centre,
                initialZoom: 14,
                minZoom: 5,
                maxZoom: 18,
                // Any manual gesture means the client is exploring, so stop
                // fighting them for control of the camera.
                onPositionChanged: (MapCamera _, bool hasGesture) {
                  if (hasGesture && _followTechnician) {
                    setState(() => _followTechnician = false);
                  }
                },
              ),
              children: <Widget>[
                const SugoMapTiles(),

                // Traffic sits directly on the base map, under the route line
                // and the pins - congestion is context for the journey, and it
                // must never obscure where the technician actually is.
                if (_showTraffic)
                  TileLayer(
                    urlTemplate: AppEnv.trafficTileUrl,
                    userAgentPackageName: 'com.example.sugo_app',
                    maxZoom: 18,
                    // A tile that fails is left blank rather than retried into
                    // a broken-image box: the overlay is optional, and the base
                    // map underneath is still correct without it.
                    tileProvider: NetworkTileProvider(
                      headers: _tileHeaders(),
                      silenceExceptions: true,
                    ),
                  ),
                // Only the two layers that move are rebuilt per frame; the
                // tiles underneath are not touched by the marker animation.
                AnimatedBuilder(
                  animation: _move,
                  builder: (BuildContext context, Widget? _) {
                    final LatLng? van = _displayPoint;
                    final List<LatLng>? route = _route;
                    return Stack(
                      children: <Widget>[
                        if (van != null && route != null && route.length >= 2)
                          PolylineLayer<Object>(
                            polylines: sugoRouteLines(routeAhead(van, route)),
                          )
                        else if (van != null && destination != null)
                          PolylineLayer<Object>(
                            polylines: <Polyline<Object>>[
                              Polyline<Object>(
                                points: <LatLng>[van, destination],
                                color: AppColors.secondary.withValues(
                                  alpha: 0.7,
                                ),
                                strokeWidth: 3,
                                // Dashed, so it never reads as a driven route.
                                pattern: const StrokePattern.dotted(),
                              ),
                            ],
                          ),
                        MarkerLayer(
                          markers: <Marker>[
                            if (destination != null)
                              Marker(
                                point: destination,
                                width: SugoMapPin.markerWidth,
                                height: SugoMapPin.markerHeight(
                                  labelled: true,
                                ),
                                alignment: Alignment.topCenter,
                                child: SugoMapPin(
                                  icon: widget.destinationIcon,
                                  color: AppColors.accentDark,
                                  label: widget.destinationLabel,
                                ),
                              ),
                            if (van != null)
                              Marker(
                                point: van,
                                width: SugoTravellerMarker.size,
                                height: SugoTravellerMarker.size,
                                child: SugoTravellerMarker(
                                  // A truck on every technician leg; the
                                  // client's own trip passes a person.
                                  icon:
                                      widget.travellerIcon ??
                                      Icons.local_shipping_rounded,
                                  color: AppColors.primary,
                                  isLive: widget.tracking.isLive,
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),

            // Below the back button when the map is full-bleed, so the two do
            // not sit on top of each other.
            Positioned(
              left: AppSizes.sm,
              top: widget.rounded ? AppSizes.sm : 74,
              child: _FreshnessChip(tracking: widget.tracking),
            ),

            Positioned(
              right: 0,
              left: 0,
              // Lifted clear of the tracking sheet. Attribution is a licence
              // condition of the tiles, so it has to stay visible.
              bottom: widget.bottomInset,
              child: Container(
                color: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  AppEnv.mapAttribution,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),

            // Traffic toggle. Top-right, clear of the recentre button and the
            // attribution bar.
            Positioned(
              right: AppSizes.sm,
              top: widget.rounded ? AppSizes.sm : 74,
              child: _TrafficToggle(
                active: _showTraffic,
                onTap: () => setState(() => _showTraffic = !_showTraffic),
              ),
            ),

            if (!_followTechnician && technician != null)
              Positioned(
                right: AppSizes.sm,
                bottom: widget.bottomInset + AppSizes.lg,
                child: FloatingActionButton.small(
                  heroTag: 'recentre_tracking',
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  onPressed: () {
                    setState(() => _followTechnician = true);
                    _controller.move(technician, 15);
                  },
                  child: const Icon(Icons.my_location_rounded, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FreshnessChip extends StatelessWidget {
  const _FreshnessChip({required this.tracking});

  final JobTracking tracking;

  @override
  Widget build(BuildContext context) {
    final bool live = tracking.isLive;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x1A0B2B5C), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: live ? AppColors.success : AppColors.hint,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            tracking.freshnessLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: live ? AppColors.success : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AwaitingFix extends StatelessWidget {
  const _AwaitingFix({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          SizedBox(height: AppSizes.md),
          Text(
            'Waiting for the technician to share their position',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'The map appears as soon as they set off.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Shown when no MapTiler key was supplied at build time, so the flow still
/// works without a map instead of rendering a grey void.
class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable({required this.height, required this.tracking});

  final double height;
  final JobTracking tracking;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.map_outlined, size: 28, color: AppColors.primary),
          const SizedBox(height: AppSizes.sm),
          const Text(
            'Map preview unavailable',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'No MapTiler key is configured for this build.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (tracking.hasPosition) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Text(
              '${tracking.latitude!.toStringAsFixed(4)}, '
              '${tracking.longitude!.toStringAsFixed(4)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
            Text(
              tracking.freshnessLabel,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small pill that turns the traffic overlay on and off.
///
/// A toggle rather than an always-on layer for two reasons: every tile is an
/// edge-function call, and congestion colour over a base map is visual noise
/// for a client who only wants to see where their technician is.
class _TrafficToggle extends StatelessWidget {
  const _TrafficToggle({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.primary : Colors.white,
      borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.traffic_rounded,
                size: 14,
                color: active ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                'Traffic',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
