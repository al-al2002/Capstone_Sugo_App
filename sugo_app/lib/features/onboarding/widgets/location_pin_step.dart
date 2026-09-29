import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_env.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../models/client_onboarding_models.dart';
import '../services/geocoding_service.dart';
import '../../../core/widgets/sugo_map.dart';

/// Map-based location picker with address search and a current-location button.
///
/// Shared by both flows: the technician pins a base of operations and picks a
/// service radius, the client pins a default address and labels it. The map,
/// the search bar and the geolocation button are identical work, so the only
/// difference is which extras the host asks for.
///
/// ## Three ways to set the pin, on purpose
///
/// Each covers where the others fail:
///
///   * **Tap the map** - always works, needs no permission and no network
///     beyond tiles. The fallback everything else degrades to.
///   * **Use current location** - fastest when the user is standing at the
///     place, but needs a permission that can be permanently denied.
///   * **Search an address** - the only option when pinning somewhere you are
///     not, but needs a network and Nominatim's rate limit to cooperate.
///
/// A single method would strand a real user in each of those cases.
class LocationPinStep extends StatefulWidget {
  const LocationPinStep({
    super.key,
    required this.place,
    required this.onPlaceChanged,
    this.radiusKm,
    this.onRadiusChanged,
    this.radiusOptions = const <double>[5, 10, 15, 20],
    this.title = 'Pin your location',
    this.subtitle,
    this.mapHeight = 260,
  });

  /// The current pin. Null opens the map at the default view.
  final GeoPlace? place;

  final ValueChanged<GeoPlace> onPlaceChanged;

  /// Non-null turns on the service-radius selector. The client flow leaves it
  /// null; only a technician has a travel radius.
  final double? radiusKm;
  final ValueChanged<double>? onRadiusChanged;
  final List<double> radiusOptions;

  final String title;
  final String? subtitle;
  final double mapHeight;

  @override
  State<LocationPinStep> createState() => _LocationPinStepState();
}

class _LocationPinStepState extends State<LocationPinStep> {
  final GeocodingService _geocoding = GeocodingService();
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();

  Timer? _debounce;
  List<GeoPlace> _results = const <GeoPlace>[];
  bool _isSearching = false;
  bool _isLocating = false;
  bool _isReverseGeocoding = false;

  /// Nominatim allows about one request per second. Typing "Matina Crossing"
  /// is fifteen keystrokes; without a debounce that is fifteen requests and an
  /// IP block. 450 ms is below the threshold at which a search field starts to
  /// feel unresponsive while cutting that to one or two requests.
  static const Duration _debounceDelay = Duration(milliseconds: 450);

  LatLng get _point => LatLng(
    widget.place?.latitude ?? AppEnv.defaultLatitude,
    widget.place?.longitude ?? AppEnv.defaultLongitude,
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _geocoding.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- searching

  void _onQueryChanged(String value) {
    _debounce?.cancel();

    if (value.trim().length < 3) {
      setState(() => _results = const <GeoPlace>[]);
      return;
    }

    _debounce = Timer(_debounceDelay, () => _runSearch(value));
  }

  Future<void> _runSearch(String query) async {
    setState(() => _isSearching = true);

    try {
      final List<GeoPlace> found = await _geocoding.search(query);
      if (!mounted) return;
      setState(() => _results = found);
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() => _results = const <GeoPlace>[]);
      UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _choose(GeoPlace place) {
    _searchController.clear();
    setState(() => _results = const <GeoPlace>[]);
    FocusScope.of(context).unfocus();

    widget.onPlaceChanged(place);
    _mapController.move(LatLng(place.latitude, place.longitude), 16);
  }

  // ------------------------------------------------------------- current fix

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);

    try {
      final GeoPlace place = await _geocoding.currentLocation();
      if (!mounted) return;
      _choose(place);
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  // ------------------------------------------------------------ tap the map

  /// Places the pin, then fills in the address behind it.
  ///
  /// The coordinates are committed immediately and the reverse lookup runs
  /// after. Waiting for Nominatim before moving the marker would make every
  /// tap feel laggy, and the pin is the part the user is actually aiming.
  Future<void> _placePin(LatLng point) async {
    widget.onPlaceChanged(
      GeoPlace(
        latitude: point.latitude,
        longitude: point.longitude,
        addressText: widget.place?.addressText ?? '',
      ),
    );

    setState(() => _isReverseGeocoding = true);

    final GeoPlace? resolved = await _geocoding.reverse(
      point.latitude,
      point.longitude,
    );

    if (!mounted) return;
    setState(() => _isReverseGeocoding = false);

    // Null means the lookup failed or the spot has no mapped address. The
    // coordinates already landed, so the step stays completable either way.
    if (resolved != null) widget.onPlaceChanged(resolved);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(widget.title, style: AppTextStyles.headline),
        if (widget.subtitle != null) ...<Widget>[
          const SizedBox(height: AppSizes.sm),
          Text(widget.subtitle!, style: AppTextStyles.subtitle),
        ],
        const SizedBox(height: AppSizes.lg),

        _searchField(),
        if (_results.isNotEmpty) _resultsList(),

        const SizedBox(height: AppSizes.md),
        _currentLocationButton(),
        const SizedBox(height: AppSizes.md),

        _map(),
        const SizedBox(height: AppSizes.md),
        _addressCard(),

        if (widget.radiusKm != null &&
            widget.onRadiusChanged != null) ...<Widget>[
          const SizedBox(height: AppSizes.xl),
          _radiusSelector(),
        ],
      ],
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      onChanged: _onQueryChanged,
      textInputAction: TextInputAction.search,
      onSubmitted: _runSearch,
      decoration: InputDecoration(
        hintText: 'Search for an address or landmark',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _isSearching
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : (_searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _results = const <GeoPlace>[]);
                      },
                    )
                  : null),
      ),
    );
  }

  Widget _resultsList() {
    return Container(
      margin: const EdgeInsets.only(top: AppSizes.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: _results
            .map((GeoPlace place) {
              return ListTile(
                dense: true,
                leading: const Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                title: Text(
                  place.shortLabel ?? place.addressText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  place.addressText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption,
                ),
                onTap: () => _choose(place),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  Widget _currentLocationButton() {
    return OutlinedButton.icon(
      onPressed: _isLocating ? null : _useCurrentLocation,
      icon: _isLocating
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.my_location_rounded, size: 17),
      label: Text(_isLocating ? 'Finding you...' : 'Use my current location'),
    );
  }

  Widget _map() {
    if (!AppEnv.hasMapTilerKey) return _mapFallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      child: SizedBox(
        height: widget.mapHeight,
        child: Stack(
          children: <Widget>[
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _point,
                initialZoom: 15,
                minZoom: 5,
                maxZoom: 18,
                onTap: (TapPosition _, LatLng point) => _placePin(point),
              ),
              children: <Widget>[
                const SugoMapTiles(),

                // The service-radius ring, drawn under the marker so the pin
                // stays legible on top of it. Only present for a technician.
                if (widget.radiusKm != null)
                  CircleLayer<Object>(
                    circles: <CircleMarker<Object>>[
                      CircleMarker<Object>(
                        point: _point,
                        // flutter_map measures a CircleMarker radius in metres
                        // when `useRadiusInMeter` is set; without it the ring
                        // is a fixed pixel size and does not track zoom.
                        radius: widget.radiusKm! * 1000,
                        useRadiusInMeter: true,
                        color: AppColors.primary.withValues(alpha: 0.10),
                        borderColor: AppColors.primary.withValues(alpha: 0.45),
                        borderStrokeWidth: 1.5,
                      ),
                    ],
                  ),

                MarkerLayer(
                  markers: <Marker>[
                    Marker(
                      point: _point,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_on_rounded,
                        size: 40,
                        color: AppColors.accent,
                        shadows: <Shadow>[
                          Shadow(
                            color: Color(0x40000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
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
                  'Tap the map to move the pin',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when no MapTiler key is configured.
  ///
  /// Mirrors the fallback in `LocationPickerMap`: rather than a grey void or a
  /// crash on a 403 tile, the coordinates stay editable so the step still
  /// completes and the missing key is stated instead of looking like a bug.
  Widget _mapFallback() {
    return Container(
      height: widget.mapHeight,
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
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
            'No MapTiler key is configured for this build. Search for an '
            'address above, or use your current location.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }

  Widget _addressCard() {
    final GeoPlace? place = widget.place;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: place == null ? AppColors.warningSoft : AppColors.successSoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            place == null
                ? Icons.location_searching_rounded
                : Icons.check_circle_rounded,
            size: 17,
            color: place == null ? AppColors.warning : AppColors.success,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  place == null ? 'No location set yet' : 'Location set',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                if (_isReverseGeocoding)
                  const Text(
                    'Looking up the address...',
                    style: AppTextStyles.caption,
                  )
                else
                  Text(
                    place?.displayText ??
                        'Tap the map, search, or use your current location.',
                    style: AppTextStyles.caption,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _radiusSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'How far will you travel?',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Jobs outside this radius will not be offered to you.',
          style: AppTextStyles.caption,
        ),
        const SizedBox(height: AppSizes.md),
        Row(
          children: widget.radiusOptions
              .map((double km) {
                final bool selected = widget.radiusKm == km;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSizes.sm),
                    child: InkWell(
                      onTap: () => widget.onRadiusChanged!(km),
                      borderRadius: BorderRadius.circular(AppSizes.tileRadius),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSizes.md,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(
                            AppSizes.tileRadius,
                          ),
                          border: Border.all(
                            color: selected
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${km.toStringAsFixed(0)} km',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }
}
