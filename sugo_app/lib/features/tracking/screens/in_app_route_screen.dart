import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_env.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/route_result.dart';
import '../services/tracking_service.dart';

/// Routes the user to a job's destination without leaving SUGO.
///
/// Opened from a `RouteMapCard`: by the technician heading to a home-service
/// address, or by the client collecting a repaired unit from the workshop. The
/// server decides which destination applies - this screen only supplies where
/// the user is.
///
/// ## What it does, and what it deliberately does not
///
/// It draws the road route, shows the user moving along it, gives distance and
/// a traffic-aware ETA, recalculates when they leave the route, and says so
/// when they arrive.
///
/// It does NOT give spoken, turn-by-turn instructions. That is a navigation
/// product in its own right - lane guidance, voice, rerouting mid-junction - and
/// claiming it from a line on a map would be overselling. The route is drawn
/// honestly; the turns are the driver's to read.
///
/// ## When it spends API calls
///
/// Moving along the route costs nothing: position updates only move a marker.
/// A TomTom call happens when the screen opens, when the user taps
/// Recalculate, and when they are more than [_offRouteMeters] from the line -
/// at most once per [_rerouteCooldown], so a wrong turn is one call, not one
/// per fix while they find their way back.
class InAppRouteScreen extends StatefulWidget {
  const InAppRouteScreen({
    super.key,
    required this.jobId,
    required this.title,
    this.subtitle,
  });

  final String jobId;

  /// What sits at the destination - "Client address", "Workshop".
  final String title;

  final String? subtitle;

  @override
  State<InAppRouteScreen> createState() => _InAppRouteScreenState();
}

class _InAppRouteScreenState extends State<InAppRouteScreen> {
  final TrackingService _service = TrackingService();
  final MapController _map = MapController();

  StreamSubscription<Position>? _positions;

  RouteResult? _route;
  LatLng? _me;
  bool _loading = true;
  bool _following = false;
  bool _mapReady = false;
  DateTime? _lastRouteAt;

  /// Beyond this, the drawn line no longer describes the journey.
  ///
  /// 60 m, against a GPS fix that is typically good to 5-15 m in a city: well
  /// clear of ordinary jitter, and less than a short block, so a genuine wrong
  /// turn is noticed before the driver is far down the wrong street.
  static const double _offRouteMeters = 60;

  /// Minimum gap between automatic recalculations. A driver correcting a wrong
  /// turn stays off route for several fixes; one new route is enough.
  static const Duration _rerouteCooldown = Duration(seconds: 60);

  /// Close enough to say "you have arrived". Larger than GPS error, smaller
  /// than the gap between neighbouring buildings on most streets.
  static const double _arrivedMeters = 40;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _positions?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final LocationReadiness readiness = await _service.prepareLocation();
    if (!mounted) return;

    if (!readiness.isReady) {
      setState(() {
        _route = const RouteResult.unavailable('no_location');
        _loading = false;
      });
      return;
    }

    final Position? fix = await _service.currentPosition();
    if (!mounted) return;

    if (fix == null) {
      setState(() {
        _route = const RouteResult.unavailable('no_location');
        _loading = false;
      });
      return;
    }

    _me = LatLng(fix.latitude, fix.longitude);
    await _calculate();

    // Live position only moves the marker - no network involved.
    _positions = _service.positionStream().listen(_onPosition);
  }

  Future<void> _calculate() async {
    final LatLng? origin = _me;
    if (origin == null) return;

    setState(() => _loading = true);
    _lastRouteAt = DateTime.now();

    final RouteResult route = await _service.routeFor(
      widget.jobId,
      originLatitude: origin.latitude,
      originLongitude: origin.longitude,
    );
    if (!mounted) return;

    setState(() {
      _route = route;
      _loading = false;
    });

    if (route.available && _mapReady) _fitWholeRoute();
  }

  void _onPosition(Position position) {
    final LatLng here = LatLng(position.latitude, position.longitude);
    setState(() => _me = here);

    if (_following && _mapReady) {
      _map.move(here, _map.camera.zoom < 15 ? 16 : _map.camera.zoom);
    }

    final RouteResult? route = _route;
    if (route == null || !route.available || _loading) return;
    if (_hasArrived) return;

    final double off = RouteGeometry.distanceToPolylineMeters(
      here,
      route.points,
    );
    final DateTime? last = _lastRouteAt;
    final bool cooledDown =
        last == null || DateTime.now().difference(last) >= _rerouteCooldown;

    if (off > _offRouteMeters && cooledDown) _calculate();
  }

  bool get _hasArrived {
    final LatLng? me = _me;
    final LatLng? dest = _route?.destination;
    if (me == null || dest == null) return false;
    return const Distance().as(LengthUnit.Meter, me, dest) <= _arrivedMeters;
  }

  void _fitWholeRoute() {
    final RouteResult? route = _route;
    if (route == null || !route.available) return;

    final List<LatLng> frame = <LatLng>[...route.points, if (_me != null) _me!];

    setState(() => _following = false);
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(frame),
        padding: const EdgeInsets.fromLTRB(40, 120, 40, 200),
      ),
    );
  }

  void _toggleFollow() {
    final LatLng? me = _me;
    if (me == null) return;
    setState(() => _following = !_following);
    if (_following) _map.move(me, 16);
  }

  // ---------------------------------------------------------------------------
  // Presentation
  //
  // Redesigned around one idea: the map IS the screen. The AppBar is gone, so
  // the route runs edge to edge the way it does in every navigation app a
  // technician already knows, and the controls float over it - a slim bar at
  // the top for where you are going, a panel at the bottom for how long it
  // will take. Everything below this line is layout; the routing logic above
  // is unchanged.
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final RouteResult? route = _route;
    final double top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: AppEnv.hasMapTilerKey ? _mapView(route) : _noTiles(),
          ),

          // Where you are going, floating over the map.
          Positioned(
            top: top + AppSizes.sm,
            left: AppSizes.md,
            right: AppSizes.md,
            child: _FloatingBar(
              title: widget.title,
              onBack: () => Navigator.of(context).maybePop(),
              onRecalculate: _loading || _me == null ? null : _calculate,
            ),
          ),

          if (_loading)
            Positioned(
              top: top + 72,
              left: 0,
              right: 0,
              child: const Center(child: _LoadingPill()),
            ),

          // How long, how far, when - pinned to the bottom.
          Positioned(
            left: AppSizes.md,
            right: AppSizes.md,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.md),
                child: AnimatedSwitcher(
                  duration: AppMotion.base,
                  switchInCurve: AppMotion.standard,
                  child: KeyedSubtree(
                    // Re-keyed on the three states that change the panel's
                    // shape, so it cross-fades instead of snapping.
                    key: ValueKey<String>(
                      route == null
                          ? 'locating'
                          : !route.available
                          ? 'unavailable'
                          : _hasArrived
                          ? 'arrived'
                          : 'driving',
                    ),
                    child: _summary(route),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapView(RouteResult? route) {
    final LatLng? me = _me;
    final LatLng? dest = route?.destination;
    final LatLng start =
        me ??
        dest ??
        const LatLng(AppEnv.defaultLatitude, AppEnv.defaultLongitude);
    final double top = MediaQuery.paddingOf(context).top;

    return Stack(
      children: <Widget>[
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: start,
            initialZoom: 14,
            minZoom: 5,
            maxZoom: 18,
            onMapReady: () {
              _mapReady = true;
              if (_route?.available ?? false) _fitWholeRoute();
            },
            // Any manual pan means the user is looking around; stop yanking
            // the camera back to them on every fix.
            onPositionChanged: (MapCamera _, bool hasGesture) {
              if (hasGesture && _following) setState(() => _following = false);
            },
          ),
          children: <Widget>[
            TileLayer(
              urlTemplate: AppEnv.mapTilerTileUrl,
              userAgentPackageName: 'com.example.sugo_app',
              maxZoom: 18,
            ),
            if (route != null && route.available)
              PolylineLayer<Object>(
                polylines: <Polyline<Object>>[
                  // Three strokes, widest first: a soft navy halo, a white
                  // casing, then the brand line. The casing is what keeps the
                  // route legible over busy streets; the halo gives it depth
                  // against a light basemap, where a flat line looks printed.
                  Polyline<Object>(
                    points: route.points,
                    color: AppColors.navy.withValues(alpha: 0.18),
                    strokeWidth: 13,
                  ),
                  Polyline<Object>(
                    points: route.points,
                    color: Colors.white,
                    strokeWidth: 9,
                  ),
                  Polyline<Object>(
                    points: route.points,
                    color: AppColors.primary,
                    strokeWidth: 5.5,
                  ),
                ],
              ),
            MarkerLayer(
              markers: <Marker>[
                if (dest != null)
                  Marker(
                    point: dest,
                    width: 48,
                    height: 58,
                    alignment: Alignment.topCenter,
                    child: _DestinationPin(arrived: _hasArrived),
                  ),
                if (me != null)
                  Marker(
                    point: me,
                    width: 56,
                    height: 56,
                    child: const _PulsingDot(),
                  ),
              ],
            ),
          ],
        ),

        // Map controls, right edge, clear of the floating bar.
        Positioned(
          top: top + 76,
          right: AppSizes.md,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _MapButton(
                icon: _following
                    ? Icons.navigation_rounded
                    : Icons.my_location_rounded,
                active: _following,
                tooltip: _following ? 'Stop following' : 'Follow me',
                onTap: _me == null ? null : _toggleFollow,
              ),
              const SizedBox(height: AppSizes.sm),
              _MapButton(
                icon: Icons.zoom_out_map_rounded,
                tooltip: 'Show whole route',
                onTap: route?.available ?? false ? _fitWholeRoute : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summary(RouteResult? route) {
    final bool arrived = route != null && route.available && _hasArrived;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.lg,
        AppSizes.lg,
        AppSizes.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.sheetRadius),
        boxShadow: AppElevation.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // --------------------------------------------------- destination
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: arrived ? AppColors.successSoft : AppColors.errorSoft,
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                ),
                child: Icon(
                  arrived ? Icons.check_circle_rounded : Icons.flag_rounded,
                  size: 22,
                  color: arrived ? AppColors.success : AppColors.error,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      arrived ? 'You have arrived' : widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(fontSize: 15),
                    ),
                    if (widget.subtitle != null &&
                        widget.subtitle!.trim().isNotEmpty)
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.micro,
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSizes.md),
          const Divider(height: 1),
          const SizedBox(height: AppSizes.md),

          // ------------------------------------------------------ the state
          if (route == null)
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSizes.sm + 2),
                Text('Finding your location...', style: AppTextStyles.body),
              ],
            )
          else if (!route.available) ...<Widget>[
            Text(
              route.unavailableMessage,
              style: AppTextStyles.body.copyWith(height: 1.4),
            ),
            const SizedBox(height: AppSizes.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _loading ? null : _retry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ),
          ] else if (arrived)
            Text(
              'The destination is within a few metres. Park up and let the '
              'client know you are here.',
              style: AppTextStyles.body.copyWith(height: 1.4),
            )
          else
            _TripFigures(route: route),

          // Attribution lives in the panel now. It used to sit in the map's
          // bottom-left corner, which this panel covers - and the tile and
          // routing licences require it to stay visible.
          const SizedBox(height: AppSizes.md),
          Text(
            '${AppEnv.mapAttribution} · Routing TomTom',
            textAlign: TextAlign.center,
            style: AppTextStyles.micro,
          ),
        ],
      ),
    );
  }

  /// A failure before any fix - location off, permission declined - has no
  /// origin to recalculate from, so it restarts from the permission step.
  Future<void> _retry() async {
    if (_me == null) {
      setState(() {
        _loading = true;
        _route = null;
      });
      await _positions?.cancel();
      _positions = null;
      await _start();
    } else {
      await _calculate();
    }
  }

  Widget _noTiles() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Text(
          'The map is unavailable in this build, so the route cannot be drawn.',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption,
        ),
      ),
    );
  }
}

/// The slim bar floating over the top of the map.
class _FloatingBar extends StatelessWidget {
  const _FloatingBar({
    required this.title,
    required this.onBack,
    required this.onRecalculate,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback? onRecalculate;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        boxShadow: AppElevation.md,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.textPrimary,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Route to', style: AppTextStyles.overline),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Recalculate route',
            onPressed: onRecalculate,
            icon: const Icon(Icons.refresh_rounded),
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

/// Minutes, distance, and the clock time you will get there.
///
/// ## Why the arrival time
///
/// "18 min" is what the router computes; "arrive 10:42" is what a technician
/// actually tells a client on the phone. Showing both saves the arithmetic,
/// and the clock time is the one that stays meaningful when the phone is
/// glanced at a few minutes later.
class _TripFigures extends StatelessWidget {
  const _TripFigures({required this.route});

  final RouteResult route;

  @override
  Widget build(BuildContext context) {
    final double? seconds = route.travelSeconds;
    final String? arrival = seconds == null
        ? null
        : DateFormat(
            'h:mm a',
          ).format(DateTime.now().add(Duration(seconds: seconds.round())));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            // The ETA is the hero: it is the one number a driver reads.
            Expanded(
              flex: 5,
              child: _Figure(
                value: route.etaLabel ?? '—',
                label: 'Travel time',
                big: true,
                color: AppColors.success,
              ),
            ),
            Expanded(
              flex: 4,
              child: _Figure(
                value: route.distanceLabel ?? '—',
                label: 'Distance',
              ),
            ),
            Expanded(
              flex: 4,
              child: _Figure(value: arrival ?? '—', label: 'Arrive by'),
            ),
          ],
        ),
        if (route.hasMeaningfulTrafficDelay) ...<Widget>[
          const SizedBox(height: AppSizes.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md,
              vertical: AppSizes.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: BorderRadius.circular(AppSizes.tileRadius),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.traffic_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    route.trafficDelayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.micro.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.label,
    this.big = false,
    this.color = AppColors.textPrimary,
  });

  final String value;
  final String label;
  final bool big;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Scaled down rather than wrapped: a long "1 hr 12 min" in the
        // narrowest column must not push the panel taller.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: (big ? AppTextStyles.display : AppTextStyles.title).copyWith(
              fontSize: big ? 26 : 16,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, style: AppTextStyles.statLabel),
      ],
    );
  }
}

/// The destination: a branded pin rather than a stock map marker.
class _DestinationPin extends StatelessWidget {
  const _DestinationPin({required this.arrived});

  final bool arrived;

  @override
  Widget build(BuildContext context) {
    final Color tone = arrived ? AppColors.success : AppColors.error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: tone,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: AppElevation.lg,
          ),
          child: Icon(
            arrived ? Icons.check_rounded : Icons.home_repair_service_rounded,
            size: 19,
            color: Colors.white,
          ),
        ),
        // The point of the pin: a short stem to the exact spot, so the marker
        // does not hide the doorway it is marking.
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: tone,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

/// The user's position, with a slow pulse around it.
///
/// A static dot on a moving map is easy to lose; the pulse is what the eye
/// finds first. Slow (1.8s) on purpose - a fast pulse reads as an alert.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  // Created in initState, never lazily - see the note on `_GlyphState` in
  // `sugo_empty_state.dart` for what a lazy controller does on dispose.
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (BuildContext context, Widget? child) {
        final double t = _pulse.value;
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Container(
              width: 22 + 30 * t,
              height: 22 + 30 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.28 * (1 - t)),
              ),
            ),
            child!,
          ],
        );
      },
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: AppElevation.md,
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.standard,
      decoration: BoxDecoration(
        color: active ? AppColors.primary : AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: AppElevation.md,
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(
          icon,
          size: 20,
          color: active ? Colors.white : AppColors.primary,
        ),
      ),
    );
  }
}

class _LoadingPill extends StatelessWidget {
  const _LoadingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        boxShadow: AppElevation.md,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Calculating route...',
            style: AppTextStyles.micro.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
