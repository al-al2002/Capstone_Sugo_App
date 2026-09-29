import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_env.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_colors.dart';
import '../../onboarding/models/client_onboarding_models.dart';
import '../../onboarding/services/geocoding_service.dart';
import '../services/rb_cars_service.dart';

/// Tap-to-place location picker backed by MapTiler tiles.
///
/// ## The no-key path
///
/// `MAPTILER_KEY` has a baked-in default, so plain `flutter run` shows the map.
/// This fallback covers the case where it is deliberately overridden with an
/// empty value, or the key is later removed: rather than render a grey void or
/// crash on a 403 tile, it falls back to a coordinate card seeded at Davao City
/// with nudge controls. The flow still completes, the job still gets a latitude
/// and longitude, and the missing key is stated plainly instead of looking like
/// a bug.
class LocationPickerMap extends StatefulWidget {
  const LocationPickerMap({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.onChanged,
    this.height = 240,
  });

  final double? latitude;
  final double? longitude;
  /// Fires with the coordinates, and with an address once one is known.
  ///
  /// Called TWICE for a map tap: immediately with a null address so the pin and
  /// the Continue button respond on the same frame, then again when the reverse
  /// geocode resolves. Waiting for Nominatim before moving the pin would make
  /// every tap feel broken on a slow connection.
  final void Function(double latitude, double longitude, String? address)
  onChanged;
  final double height;

  @override
  State<LocationPickerMap> createState() => _LocationPickerMapState();
}

class _LocationPickerMapState extends State<LocationPickerMap> {
  late final MapController _controller = MapController();
  final GeocodingService _geocoding = GeocodingService();
  final TextEditingController _search = TextEditingController();

  bool _locating = false;
  bool _searching = false;
  List<GeoPlace> _results = const <GeoPlace>[];

  /// Nominatim allows one request per second and blocks by IP for abuse, so a
  /// keystroke must never be a request. 450ms is long enough that a normal
  /// typist sends one query per word, not per letter.
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  LatLng get _point => LatLng(
    widget.latitude ?? AppEnv.defaultLatitude,
    widget.longitude ?? AppEnv.defaultLongitude,
  );

  /// Most recent placement, so a slow reverse geocode for a pin the user has
  /// already moved away from is discarded instead of overwriting the new one.
  int _placementSeq = 0;

  void _place(LatLng point, {bool recentre = false, String? address}) {
    widget.onChanged(point.latitude, point.longitude, address);
    if (recentre) _controller.move(point, 16);
  }

  /// Places the pin now, then fills in the address when Nominatim answers.
  Future<void> _placeAndResolve(LatLng point) async {
    final int seq = ++_placementSeq;
    _place(point);

    try {
      final GeoPlace? resolved = await _geocoding.reverse(
        point.latitude,
        point.longitude,
      );
      // Superseded by a later tap, or the widget is gone.
      if (!mounted || seq != _placementSeq || resolved == null) return;
      _place(point, address: resolved.addressText);
    } catch (_) {
      // Best effort. The coordinates are already set and the job is postable;
      // the label simply stays as the numbers.
    }
  }

  /// Finds the device and SETS the job location with it.
  ///
  /// This button used to only recentre the camera on whatever point was already
  /// chosen - it never asked for GPS and never called [LocationPickerMap.onChanged].
  /// So pressing the one control labelled with a location icon left
  /// `draft.latitude` null, Continue stayed disabled, and the only way forward
  /// was to tap the map by hand. It now does what its icon promises.
  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);

    try {
      final GeoPlace place = await _geocoding.currentLocation();
      if (!mounted) return;
      _placementSeq++;
      _place(
        LatLng(place.latitude, place.longitude),
        recentre: true,
        address: place.addressText,
      );
      // Clearing the search keeps the field from contradicting the pin.
      _search.clear();
      setState(() => _results = const <GeoPlace>[]);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is RbCarsFailure
                ? error.message
                : 'Could not find your location. Tap the map instead.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final String query = value.trim();

    if (query.length < 3) {
      setState(() {
        _results = const <GeoPlace>[];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 450), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    try {
      final List<GeoPlace> found = await _geocoding.search(query);
      if (!mounted) return;
      setState(() {
        _results = found;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      // A failed lookup leaves the map fully usable, so it stays quiet rather
      // than interrupting with an error the user cannot act on.
      setState(() {
        _results = const <GeoPlace>[];
        _searching = false;
      });
    }
  }

  void _choose(GeoPlace place) {
    FocusScope.of(context).unfocus();
    _placementSeq++;
    _place(
      LatLng(place.latitude, place.longitude),
      recentre: true,
      address: place.addressText,
    );
    _search.text = place.shortLabel ?? place.addressText;
    setState(() => _results = const <GeoPlace>[]);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      child: SizedBox(
        height: widget.height,
        child: AppEnv.hasMapTilerKey ? _buildMap() : _buildFallback(),
      ),
    );
  }

  Widget _buildMap() {
    return Stack(
      children: <Widget>[
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: _point,
            initialZoom: 14,
            minZoom: 5,
            maxZoom: 18,
            onTap: (TapPosition _, LatLng point) => _placeAndResolve(point),
          ),
          children: <Widget>[
            TileLayer(
              urlTemplate: AppEnv.mapTilerTileUrl,
              userAgentPackageName: 'com.example.sugo_app',
              maxZoom: 18,
            ),
            MarkerLayer(
              markers: <Marker>[
                Marker(
                  point: _point,
                  width: 44,
                  height: 44,
                  alignment: Alignment.topCenter,
                  child: const _Pin(),
                ),
              ],
            ),
          ],
        ),

        // MapTiler and OpenStreetMap both require visible attribution.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
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

        Positioned(
          top: AppSizes.sm,
          left: AppSizes.sm,
          right: AppSizes.sm,
          child: _SearchBar(
            controller: _search,
            searching: _searching,
            results: _results,
            onChanged: _onQueryChanged,
            onSelected: _choose,
          ),
        ),

        Positioned(
          bottom: AppSizes.lg,
          left: AppSizes.sm,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x1A0B2B5C), blurRadius: 8),
              ],
            ),
            child: const Text(
              'Tap the map to set the pin',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),

        Positioned(
          right: AppSizes.sm,
          bottom: AppSizes.lg,
          child: FloatingActionButton.small(
            heroTag: 'use_my_location',
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
            elevation: 2,
            onPressed: _locating ? null : _useCurrentLocation,
            child: _locating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.my_location_rounded, size: 18),
          ),
        ),
      ],
    );
  }

  /// Shown when no MapTiler key was supplied at build time.
  Widget _buildFallback() {
    return Container(
      color: AppColors.primarySofter,
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.map_outlined, size: 30, color: AppColors.primary),
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
            'No MapTiler key is configured for this build. You can still '
            'set the location below.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.lg,
              vertical: AppSizes.sm,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              '${_point.latitude.toStringAsFixed(4)}, '
              '${_point.longitude.toStringAsFixed(4)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                color: AppColors.primaryDark,
              ),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _Nudge(icon: Icons.north_rounded, onTap: () => _nudge(0.005, 0)),
              _Nudge(icon: Icons.south_rounded, onTap: () => _nudge(-0.005, 0)),
              _Nudge(icon: Icons.west_rounded, onTap: () => _nudge(0, -0.005)),
              _Nudge(icon: Icons.east_rounded, onTap: () => _nudge(0, 0.005)),
            ],
          ),
        ],
      ),
    );
  }

  void _nudge(double dLat, double dLon) {
    widget.onChanged(_point.latitude + dLat, _point.longitude + dLon, null);
  }
}

class _Nudge extends StatelessWidget {
  const _Nudge({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.location_on_rounded,
      size: 40,
      color: AppColors.primary,
      shadows: <Shadow>[
        Shadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2)),
      ],
    );
  }
}

/// Address search over the map.
///
/// Sits on top of the map rather than above it so the picker keeps its fixed
/// height: this widget is embedded in a scrolling step, and growing the card
/// every time a result list appeared would shift everything below it.
///
/// Results are capped at four. Nominatim happily returns more, but a taller
/// list would cover the pin the user is trying to place.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.searching,
    required this.results,
    required this.onChanged,
    required this.onSelected,
  });

  final TextEditingController controller;
  final bool searching;
  final List<GeoPlace> results;
  final ValueChanged<String> onChanged;
  final void Function(GeoPlace place) onSelected;

  static const int _maxResults = 4;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x1A0B2B5C), blurRadius: 8),
            ],
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search an address or landmark',
              hintStyle: const TextStyle(fontSize: 13, color: AppColors.hint),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 18,
                color: AppColors.hint,
              ),
              suffixIcon: searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16),
                            color: AppColors.hint,
                            onPressed: () {
                              controller.clear();
                              onChanged('');
                            },
                          )),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        if (results.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSizes.md),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x1A0B2B5C), blurRadius: 8),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: results
                  .take(_maxResults)
                  .map(
                    (GeoPlace place) => InkWell(
                      onTap: () => onSelected(place),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.md,
                          vertical: AppSizes.sm,
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(
                              Icons.place_outlined,
                              size: 14,
                              color: AppColors.hint,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                place.shortLabel ?? place.addressText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ],
    );
  }
}
