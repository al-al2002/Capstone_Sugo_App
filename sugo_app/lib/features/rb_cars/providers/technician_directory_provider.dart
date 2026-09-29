import 'package:flutter/foundation.dart';

import '../models/technician.dart';
import '../services/rb_cars_service.dart';
import '../services/technician_directory_service.dart';

/// Backs the home screen's "Recommended technicians" row.
///
/// Kept deliberately small: one list, one loading flag, one error. The home
/// screen must still render if the directory is unreachable, so a failure here
/// leaves the rest of the screen untouched and shows a retry inside the row.
class TechnicianDirectoryProvider extends ChangeNotifier {
  TechnicianDirectoryProvider({TechnicianDirectoryService? service})
    : _service = service ?? TechnicianDirectoryService();

  final TechnicianDirectoryService _service;

  List<Technician> _technicians = <Technician>[];
  bool _isLoading = false;
  String? _error;

  List<Technician> get technicians => _technicians;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get isEmpty => !_isLoading && _error == null && _technicians.isEmpty;

  /// Where the client is, remembered so [refresh] keeps the distances.
  double? _originLat;
  double? _originLon;

  /// True once an origin has been supplied. Callers use it to avoid replacing
  /// a live GPS fix with a weaker fallback that resolved later.
  bool get hasOrigin => _originLat != null && _originLon != null;

  /// True once [load] has been called, whether or not it has come back yet.
  ///
  /// This, and not "are there technicians in the list", is what decides whether
  /// [setOrigin] needs to re-fetch. The distinction is the whole bug: the
  /// directory is an edge-function round trip and the origin is a single
  /// indexed query, so the origin nearly always lands while the first load is
  /// still in flight. Testing the list for emptiness at that moment says "not
  /// loaded yet" and skips the refetch - and the request already on the wire
  /// went out with no origin, so no card ever gets a distance.
  bool _loadRequested = false;

  /// Tells the row where the client is, so the cards can carry a distance.
  ///
  /// Separate from [load] because the origin and the list arrive from different
  /// places at different times - the home screen resolves a position from the
  /// client's saved address, their last GPS fix or their most recent job, and
  /// any of those can resolve before, during or after the first load.
  Future<void> setOrigin({double? latitude, double? longitude}) async {
    if (_originLat == latitude && _originLon == longitude) return;
    _originLat = latitude;
    _originLon = longitude;
    if (_loadRequested) await refresh();
  }

  /// Loads the recommended row.
  ///
  /// There is no device-type parameter: this row is the general "best
  /// performers" list and is never filtered by specialisation. The
  /// specialisation-aware list is task matching, which is keyed on a posted job
  /// and lives behind `TechnicianDirectoryService.forJob`.
  Future<void> load({int limit = 10}) async {
    _loadRequested = true;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _technicians = await _service.recommended(
        limit: limit,
        latitude: _originLat,
        longitude: _originLon,
      );
    } on RbCarsFailure catch (failure) {
      _error = failure.message;
      _technicians = <Technician>[];
    } catch (_) {
      _error = 'Could not load technicians.';
      _technicians = <Technician>[];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();
}
