import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/rb_cars/models/technician.dart';
import 'package:sugo_app/features/rb_cars/providers/technician_directory_provider.dart';
import 'package:sugo_app/features/rb_cars/services/technician_directory_service.dart';

/// When the client's location reaches the directory, relative to the first
/// load, decides whether any card ever shows a distance.
///
/// The home screen fires `load()` and resolves an origin at the same time. The
/// directory is an edge-function round trip; the origin is one indexed query or
/// a cached GPS fix. So the origin nearly always arrives *while the first load
/// is still in flight* - which is the case that was broken, and the case a
/// casual test would never hit.
void main() {
  late _RecordingDirectory service;

  setUp(() => service = _RecordingDirectory());

  TechnicianDirectoryProvider provider() =>
      TechnicianDirectoryProvider(service: service);

  test('an origin that arrives mid-flight still reaches the server', () async {
    final TechnicianDirectoryProvider directory = provider();
    addTearDown(directory.dispose);

    // Load starts and hangs, exactly as a slow function call would.
    final Future<void> loading = directory.load();
    expect(service.calls, hasLength(1));
    expect(service.calls.single.latitude, isNull);

    // The origin resolves before the first response comes back. The list is
    // still empty at this instant - which is what the old guard tested, and
    // why it wrongly concluded there was nothing to refresh.
    final Future<void> origined = directory.setOrigin(
      latitude: 7.1845,
      longitude: 125.4596,
    );

    service.release();
    await loading;
    await origined;

    expect(
      service.calls,
      hasLength(2),
      reason:
          'The origin must trigger a second fetch; the first went out '
          'without one and can never carry a distance.',
    );
    expect(service.calls.last.latitude, 7.1845);
    expect(service.calls.last.longitude, 125.4596);
  });

  test('an origin known before the first load is sent with it', () async {
    final TechnicianDirectoryProvider directory = provider();
    addTearDown(directory.dispose);

    await directory.setOrigin(latitude: 7.1845, longitude: 125.4596);
    expect(
      service.calls,
      isEmpty,
      reason:
          'Nothing has asked for the list yet, so there is nothing to '
          'refresh - setting an origin must not fetch on its own.',
    );

    service.release();
    await directory.load();

    expect(service.calls, hasLength(1));
    expect(service.calls.single.latitude, 7.1845);
  });

  test('an origin that arrives after the list does re-fetches', () async {
    final TechnicianDirectoryProvider directory = provider();
    addTearDown(directory.dispose);

    service.release();
    await directory.load();
    expect(service.calls.single.latitude, isNull);

    await directory.setOrigin(latitude: 7.1845, longitude: 125.4596);

    expect(service.calls, hasLength(2));
    expect(service.calls.last.latitude, 7.1845);
  });

  test('the same origin twice does not re-fetch', () async {
    final TechnicianDirectoryProvider directory = provider();
    addTearDown(directory.dispose);

    service.release();
    await directory.load();
    await directory.setOrigin(latitude: 7.1845, longitude: 125.4596);
    await directory.setOrigin(latitude: 7.1845, longitude: 125.4596);

    expect(service.calls, hasLength(2));
  });

  test('hasOrigin lets a weaker fallback stand aside', () async {
    final TechnicianDirectoryProvider directory = provider();
    addTearDown(directory.dispose);

    expect(directory.hasOrigin, isFalse);
    service.release();
    await directory.setOrigin(latitude: 7.1845, longitude: 125.4596);
    expect(directory.hasOrigin, isTrue);
  });
}

/// Records what each call was given, and can hold the first one open.
class _RecordingDirectory implements TechnicianDirectoryService {
  final List<({double? latitude, double? longitude})> calls =
      <({double? latitude, double? longitude})>[];

  Completer<void> _gate = Completer<void>();

  /// Lets any pending and future call return.
  void release() {
    if (!_gate.isCompleted) _gate.complete();
    _gate = Completer<void>()..complete();
  }

  @override
  Future<List<Technician>> recommended({
    int limit = 10,
    double? latitude,
    double? longitude,
  }) async {
    calls.add((latitude: latitude, longitude: longitude));
    await _gate.future;
    return const <Technician>[
      Technician(id: 't1', fullName: 'Lance D.', isVerified: true),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
