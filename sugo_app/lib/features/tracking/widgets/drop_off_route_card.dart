import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_env.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/contact_launcher.dart';
import '../../../core/widgets/sugo_map.dart';
import '../../../core/widgets/sugo_motion.dart';
import '../../rb_cars/models/technician_profile_details.dart';
import '../../rb_cars/services/technician_directory_service.dart';
import '../models/job_tracking.dart';
import '../models/route_result.dart';
import '../models/trip_conditions.dart';
import '../screens/in_app_route_screen.dart';
import '../services/tracking_service.dart';
import 'collection_trip_panel.dart';
import 'trip_conditions_card.dart';

/// "Bring it to the shop": the client's road route to the technician's shop,
/// on a Shop Repair they chose to drop off themselves (2026-11-17).
///
/// ## When it shows
///
/// From the moment the technician accepts until they mark the unit received.
/// Nothing is tracked in that window - on a drop-off the client is the one
/// travelling - so before this card the client's job page said "Tracking
/// opens once your technician sets off to collect the unit", which never
/// happens on this kind of job, and the shop was a pin behind a "Track"
/// button.
///
/// ## Where the shop comes from
///
/// Two reads, both behind the booking gate, neither from the job row (a
/// client cannot read `technicians`):
///
/// * `technician_profile` releases the shop's name and pin once the client
///   has a confirmed booking with this technician - enough to draw the map
///   straight away, without asking for the client's location.
/// * `job-route` draws the road from the client's position to the same shop.
///   The app sends only the origin; the server resolves the destination from
///   the job, so the route cannot be pointed anywhere else.
///
/// ## Location is not asked for on arrival
///
/// The route is drawn at once only when SUGO may already read the position.
/// Otherwise the card shows the shop and a "Show my route" button, and the
/// permission prompt comes from that tap - a job page that opened with a
/// system dialog would be asking before the client knew why.
///
/// One TomTom call per card, then none: the live, recalculating route is
/// [InAppRouteScreen], behind "Start route".
///
/// ## The trip itself (2026-11-17)
///
/// Under the route: the technician's number with a Call button, for when the
/// client is at the door; "I'm on my way" / "I've arrived"
/// ([CollectionTripPanel] - the first tap creates the `dropping_off` row,
/// 20261117000006), which lets the technician follow them with an arrival
/// time; and, once they are moving, the trip-conditions card - "Weather is
/// good and traffic is light", the countdown, and why if they run late.
class DropOffRouteCard extends StatefulWidget {
  const DropOffRouteCard({
    super.key,
    required this.jobId,
    required this.technicianId,
    this.trip,
    this.directory,
    this.tracking,
  });

  final String jobId;
  final String technicianId;

  /// The live tracking row once the client has set off (`dropping_off`);
  /// null before. The host watches it and rebuilds this card.
  final JobTracking? trip;

  /// The host screen's services, so a test's fakes answer here too. Null
  /// builds the real ones.
  final TechnicianDirectoryService? directory;
  final TrackingService? tracking;

  @override
  State<DropOffRouteCard> createState() => _DropOffRouteCardState();
}

class _DropOffRouteCardState extends State<DropOffRouteCard>
    with AutomaticKeepAliveClientMixin<DropOffRouteCard> {
  /// Kept alive in a scrolling page: the trip panel inside shares the
  /// client's position only while it exists, so scrolling the card out of
  /// view must not quietly stop the technician's map.
  @override
  bool get wantKeepAlive => true;

  late final TechnicianDirectoryService _directory =
      widget.directory ?? TechnicianDirectoryService();
  late final TrackingService _tracking = widget.tracking ?? TrackingService();

  TechnicianProfileDetails? _profile;
  bool _profileLoaded = false;

  RouteResult? _route;
  LatLng? _origin;
  bool _routing = false;

  /// Why the route could not start on the device side, when it could not.
  LocationReadiness? _blocked;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _routeIfAllowed();
  }

  Future<void> _loadProfile() async {
    try {
      final TechnicianProfileDetails profile = await _directory.profile(
        widget.technicianId,
        // Only the shop is wanted here.
        reviewLimit: 1,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _profileLoaded = true;
      });
    } catch (_) {
      // The route may still find the shop, and the copy says what to do.
      if (mounted) setState(() => _profileLoaded = true);
    }
  }

  Future<void> _routeIfAllowed() async {
    bool allowed = false;
    try {
      allowed = await _tracking.locationAllowed();
    } catch (_) {
      allowed = false;
    }
    if (allowed && mounted) await _drawRoute(ask: false);
  }

  /// [ask] is true only from the button: that tap is the client agreeing to
  /// share where they are.
  Future<void> _drawRoute({required bool ask}) async {
    if (_routing) return;
    setState(() {
      _routing = true;
      _blocked = null;
    });

    try {
      if (ask) {
        final LocationReadiness readiness = await _tracking.prepareLocation();
        if (!mounted) return;
        if (!readiness.isReady) {
          setState(() {
            _blocked = readiness;
            _routing = false;
          });
          return;
        }
      }

      final Position? fix = await _tracking.currentPosition();
      if (!mounted) return;
      if (fix == null) {
        setState(() {
          _route = const RouteResult.unavailable('no_location');
          _routing = false;
        });
        return;
      }

      final LatLng origin = LatLng(fix.latitude, fix.longitude);
      final RouteResult route = await _tracking.routeFor(
        widget.jobId,
        originLatitude: origin.latitude,
        originLongitude: origin.longitude,
      );
      if (!mounted) return;
      setState(() {
        _origin = origin;
        _route = route;
        _routing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _route = const RouteResult.unavailable('provider_unavailable');
        _routing = false;
      });
    }
  }

  // ----------------------------------------------------------- derived

  /// The shop's pin: the profile's, else the end of the drawn route.
  LatLng? get _shop {
    final TechnicianProfileDetails? p = _profile;
    if (p != null && p.hasShopLocation) {
      return LatLng(p.shopLatitude!, p.shopLongitude!);
    }
    final RouteResult? route = _route;
    if (route != null && route.available) {
      return route.destination ?? route.points.last;
    }
    return null;
  }

  String get _shopName {
    final String? name = _profile?.shopName?.trim();
    return name != null && name.isNotEmpty ? name : "Technician's shop";
  }

  String? get _technicianName => _profile?.technician.displayName;

  /// The technician's number, released by `technician_profile` once the
  /// booking is confirmed - the same gate as the shop.
  String? get _phone {
    final TechnicianProfileDetails? p = _profile;
    final String? phone = p?.phone?.trim();
    if (p == null || !p.contactUnlocked || phone == null || phone.isEmpty) {
      return null;
    }
    return phone;
  }

  bool get _hasRoute => _route?.available ?? false;

  void _startRoute() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InAppRouteScreen(
          jobId: widget.jobId,
          title: _shopName,
          subtitle: _technicianName,
        ),
      ),
    );
  }

  void _openInMaps(LatLng shop) {
    ContactLauncher.directions(
      context,
      latitude: shop.latitude,
      longitude: shop.longitude,
      label: _shopName,
    );
  }

  // ----------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final LatLng? shop = _shop;
    final JobTracking? trip = widget.trip;
    final bool moving = trip?.clientOnTheWay ?? false;
    final String? phone = _phone;

    return Semantics(
      container: true,
      label: 'Bring it to the shop',
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius + 4),
          border: Border.all(color: AppColors.border),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _band(),
            if (shop != null || _hasRoute)
              _DropOffMap(shop: shop, origin: _origin, route: _route)
            else if (!_profileLoaded)
              const _MapPlaceholder(loading: true)
            else
              const _MapPlaceholder(loading: false),
            Padding(
              padding: const EdgeInsets.all(AppSizes.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _shopRow(shop),
                  if (phone != null) ...<Widget>[
                    const SizedBox(height: AppSizes.md),
                    _CallTechnician(
                      name: _technicianName ?? 'Your technician',
                      phone: phone,
                      onCall: () => ContactLauncher.call(context, phone),
                    ),
                  ],
                  const SizedBox(height: AppSizes.md),
                  _routeStatus(),
                  const SizedBox(height: AppSizes.md),
                  _buttons(shop),
                  const SizedBox(height: AppSizes.lg),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: AppSizes.lg),
                  CollectionTripPanel(
                    jobId: widget.jobId,
                    tracking: trip,
                    dropOff: true,
                    // The conditions card below says it, with more.
                    showsArrival: !moving,
                    service: _tracking,
                  ),
                  if (moving && trip != null) ...<Widget>[
                    const SizedBox(height: AppSizes.md),
                    TripConditionsCard(
                      tracking: trip,
                      viewer: TripViewer.client,
                    ),
                  ],
                  const SizedBox(height: AppSizes.lg),
                  const _DropOffSteps(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _band() {
    final RouteResult? route = _route;
    return SugoHeroBand(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppSizes.cardRadius + 4),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.lg,
        AppSizes.lg,
        AppSizes.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SugoRiseIn(
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppSizes.radius + 2),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: SugoRiseIn(
                  delay: AppMotion.staggerStep,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Bring it to the shop',
                        style: AppTextStyles.titleSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your technician accepted. Drop the unit off at their '
                        'shop - no delivery fee.',
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Distance and time arrive with the route, never before: a number
          // the road has not confirmed would be a guess.
          // Reduced motion: no AnimatedSize at all - at zero duration it
          // trips a layout assertion, and there is nothing to animate.
          if (AppMotion.reduced(context))
            _pills(route)
          else
            AnimatedSize(
              duration: AppMotion.base,
              curve: AppMotion.standard,
              alignment: Alignment.topLeft,
              child: _pills(route),
            ),
        ],
      ),
    );
  }

  /// Distance, time and traffic on the band - or nothing yet.
  Widget _pills(RouteResult? route) {
    return route == null || !route.available
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.only(top: AppSizes.md),
            child: Wrap(
              spacing: AppSizes.sm,
              runSpacing: AppSizes.xs,
              children: <Widget>[
                if (route.distanceLabel != null)
                  _GlassPill(
                    icon: Icons.route_rounded,
                    label: route.distanceLabel!,
                  ),
                if (route.etaLabel != null)
                  _GlassPill(
                    icon: Icons.schedule_rounded,
                    label: '${route.etaLabel!} away',
                  ),
                if (route.hasMeaningfulTrafficDelay)
                  _GlassPill(
                    icon: Icons.traffic_rounded,
                    label: route.trafficDelayLabel,
                  ),
              ],
            ),
          );
  }

  Widget _shopRow(LatLng? shop) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.accentSofter,
            borderRadius: BorderRadius.circular(AppSizes.sm + 2),
          ),
          child: const Icon(
            Icons.place_rounded,
            size: 19,
            color: AppColors.accentDark,
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _shopName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              if (_technicianName != null)
                Text(_technicianName!, style: AppTextStyles.caption),
              if (shop == null && _profileLoaded)
                Text(
                  'The shop has no pin on the map yet. Message your '
                  'technician to agree a time and get the address.',
                  style: AppTextStyles.caption,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// One line under the map: drawing, drawn, or why not.
  Widget _routeStatus() {
    final Widget child;
    if (_routing) {
      child = const _StatusLine(
        key: ValueKey<String>('routing'),
        icon: Icons.alt_route_rounded,
        text: 'Finding the best road from where you are...',
        busy: true,
      );
    } else if (_blocked != null) {
      child = Column(
        key: const ValueKey<String>('blocked'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _StatusLine(
            icon: Icons.location_off_rounded,
            text: _blocked!.reason ?? 'Location is not available.',
            tone: AppColors.warning,
          ),
          if (_blocked!.fix != LocationFix.none)
            TextButton(
              onPressed: () => _blocked!.openFix(),
              child: const Text('Open settings'),
            ),
        ],
      );
    } else if (_hasRoute) {
      child = const _StatusLine(
        key: ValueKey<String>('drawn'),
        icon: Icons.check_circle_rounded,
        text: 'Route drawn from where you are now.',
        tone: AppColors.success,
      );
    } else if (_route != null) {
      child = _StatusLine(
        key: const ValueKey<String>('unavailable'),
        icon: Icons.info_outline_rounded,
        text: _route!.unavailableMessage,
        tone: AppColors.textSecondary,
      );
    } else {
      child = const _StatusLine(
        key: ValueKey<String>('ask'),
        icon: Icons.my_location_rounded,
        text: 'See the road from where you are to the shop.',
      );
    }

    return AnimatedSwitcher(
      duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.base,
      child: child,
    );
  }

  Widget _buttons(LatLng? shop) {
    final bool needsRoute = !_hasRoute;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
          child: needsRoute
              ? FilledButton.icon(
                  onPressed: _routing ? null : () => _drawRoute(ask: true),
                  icon: const Icon(Icons.alt_route_rounded, size: 18),
                  label: const Text('Show my route'),
                )
              : FilledButton.icon(
                  onPressed: _startRoute,
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('Start route'),
                ),
        ),
        if (shop != null) ...<Widget>[
          const SizedBox(height: AppSizes.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSizes.touchTarget),
            child: OutlinedButton.icon(
              onPressed: () => _openInMaps(shop),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Open in maps'),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Call Ryan · 0917 123 4567" - for when the client is at the shop door, or
/// lost on the way.
class _CallTechnician extends StatelessWidget {
  const _CallTechnician({
    required this.name,
    required this.phone,
    required this.onCall,
  });

  final String name;
  final String phone;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.sm + 2),
            ),
            child: const Icon(
              Icons.phone_rounded,
              size: 18,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Call $name when you arrive',
                  style: AppTextStyles.micro.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                SelectableText(
                  phone,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          FilledButton.icon(
            onPressed: onCall,
            icon: const Icon(Icons.call_rounded, size: 18),
            label: const Text('Call'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              minimumSize: const Size(0, AppSizes.touchTarget),
            ),
          ),
        ],
      ),
    );
  }
}

/// The map: the shop, and once drawn, the road to it from the client.
///
/// Static on purpose, like `RouteMapPreview`: this answers "where am I
/// going", and the live, pannable route is one tap away. The road draws
/// itself in once - a line that grows from the client to the shop says
/// "from here to there" faster than a legend would. Reduced motion shows it
/// whole.
class _DropOffMap extends StatelessWidget {
  const _DropOffMap({required this.shop, this.origin, this.route});

  final LatLng? shop;
  final LatLng? origin;
  final RouteResult? route;

  static const double height = 200;

  @override
  Widget build(BuildContext context) {
    if (!AppEnv.hasMapTilerKey) return const _MapPlaceholder(loading: false);

    final RouteResult? r = route;
    final bool drawn = r != null && r.available;
    final LatLng? pin = shop ?? (drawn ? r.points.last : null);
    if (pin == null) return const _MapPlaceholder(loading: false);

    final List<LatLng> frame = <LatLng>[
      if (drawn) ...r.points,
      pin,
      if (origin != null) origin!,
    ];
    final bool fits = frame.length >= 2;

    return SizedBox(
      height: height,
      child: FlutterMap(
        // A new route is a new camera.
        key: ValueKey<int>(drawn ? r.points.length : 0),
        options: MapOptions(
          initialCenter: pin,
          initialZoom: 15,
          initialCameraFit: fits
              ? CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(frame),
                  padding: const EdgeInsets.fromLTRB(36, 48, 36, 28),
                  maxZoom: 16,
                )
              : null,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: <Widget>[
          const SugoMapTiles(),
          if (drawn)
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: AppMotion.reduced(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 1100),
              curve: AppMotion.emphasized,
              builder: (BuildContext context, double t, Widget? _) {
                final List<LatLng> shown = _grown(r.points, t);
                return PolylineLayer<Object>(
                  polylines: <Polyline<Object>>[
                    // The route screen's three strokes, so the two read as
                    // the same road.
                    Polyline<Object>(
                      points: shown,
                      color: AppColors.navy.withValues(alpha: 0.18),
                      strokeWidth: 12,
                    ),
                    Polyline<Object>(
                      points: shown,
                      color: Colors.white,
                      strokeWidth: 8,
                    ),
                    Polyline<Object>(
                      points: shown,
                      color: AppColors.primary,
                      strokeWidth: 5,
                    ),
                  ],
                );
              },
            ),
          MarkerLayer(
            markers: <Marker>[
              if (origin != null)
                Marker(
                  point: origin!,
                  width: 26,
                  height: 26,
                  child: const _YouDot(),
                ),
              Marker(
                point: pin,
                width: SugoMapPin.markerWidth,
                height: SugoMapPin.markerHeight(labelled: true),
                alignment: Alignment.topCenter,
                child: const SugoMapPin(
                  icon: Icons.storefront_rounded,
                  color: AppColors.accentDark,
                  label: 'Shop',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The first [t] of [points], at least two so the layer always has a line.
  static List<LatLng> _grown(List<LatLng> points, double t) {
    if (t >= 1 || points.length <= 2) return points;
    final int n = math.max(2, (points.length * t).ceil());
    return points.sublist(0, math.min(n, points.length));
  }
}

/// Where the client is: a plain dot with a white ring. Not the pulsing
/// traveller marker - nothing is being tracked, and a loop would never
/// settle.
class _YouDot extends StatelessWidget {
  const _YouDot();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'You',
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.secondary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.35),
              blurRadius: 10,
            ),
          ],
        ),
      ),
    );
  }
}

/// The map's footprint while the shop loads, or when there is no map to
/// draw (no shop pin, or a build without a MapTiler key).
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      // A floor, not a height: the "no map" words wrap at large text.
      constraints: BoxConstraints(
        minHeight: loading ? _DropOffMap.height : 120,
      ),
      color: AppColors.primarySofter,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSizes.lg),
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.map_outlined, size: 26, color: AppColors.hint),
                const SizedBox(height: AppSizes.sm),
                Text(
                  AppEnv.hasMapTilerKey
                      ? 'No map yet - the shop has not been pinned.'
                      : 'Map preview unavailable in this build.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    super.key,
    required this.icon,
    required this.text,
    this.tone = AppColors.secondaryDark,
    this.busy = false,
  });

  final IconData icon;
  final String text;
  final Color tone;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 18,
          height: 18,
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(2),
                  child: CircularProgressIndicator(strokeWidth: 2, color: tone),
                )
              : Icon(icon, size: 18, color: tone),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textPrimary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// What happens next, in three steps, so "drop it off" is not the end of
/// the story: the technician confirms receipt (tracking starts there), and
/// the client collects it when it is ready.
class _DropOffSteps extends StatelessWidget {
  const _DropOffSteps();

  static const List<({IconData icon, String label})> _steps =
      <({IconData icon, String label})>[
        (icon: Icons.directions_walk_rounded, label: 'Bring it in'),
        (icon: Icons.inventory_2_rounded, label: 'Technician confirms receipt'),
        (icon: Icons.storefront_rounded, label: 'Collect it when ready'),
      ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < _steps.length; i++)
          Expanded(
            child: SugoRiseIn(
              delay: AppMotion.staggerDelay(i + 2),
              child: Column(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? AppColors.primary
                          : AppColors.primarySofter,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _steps[i].icon,
                      size: 17,
                      color: i == 0 ? Colors.white : AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _steps[i].label,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.micro.copyWith(
                      fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
                      color: i == 0
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A frosted pill on the navy band: distance, time, traffic.
class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
