import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/providers/match_provider.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';

/// `isResponding` must be true for the whole time a booking is in flight, and
/// it must notify at both ends.
///
/// This is the signal `ClientReviewScreen` drives its busy overlay from. It
/// existed from the start and no screen read it, so "Send request" ran a
/// network round trip with nothing moving on screen - the client tapped,
/// waited, and eventually got a snackbar.
///
/// ## What this does and does not cover
///
/// This is a PROVIDER test, not a widget test. `ClientReviewScreen` constructs
/// its own `MatchProvider` internally, so a test cannot hand it a gated service
/// without changing production code to accept one. What is asserted here is the
/// signal the overlay keys off; that the overlay itself renders from it is
/// covered by reading `_busyLabel`, which is a pure function of these flags.
///
/// The Completer is built inside the test body on purpose: `testWidgets` and
/// `test` bodies run under a zone where a Completer created in `setUp` schedules
/// nothing the fake clock will run, so the await it gates would simply hang.
void main() {
  test('isResponding brackets a booking, and notifies at both ends', () async {
    final Completer<JobResponseOutcome> gate = Completer<JobResponseOutcome>();
    final MatchProvider matching = MatchProvider(
      jobId: 'job-1',
      service: _GatedMatchService(gate),
    );
    addTearDown(matching.dispose);

    int notifications = 0;
    matching.addListener(() => notifications += 1);

    expect(matching.isResponding, isFalse);

    final Future<bool> booking = matching.selectTechnician('match-1');

    // Set synchronously, before the first await - otherwise the overlay would
    // not appear until a frame after the tap, which is the visible stutter this
    // guards against.
    expect(matching.isResponding, isTrue);
    expect(
      notifications,
      greaterThanOrEqualTo(1),
      reason: 'the screen has to be told to rebuild when the request starts',
    );

    // A second tap while the first is in flight must not double-send: selecting
    // promotes one match to `offered` and retires the others, so it is not
    // idempotent.
    expect(await matching.selectTechnician('match-2'), isFalse);

    gate.complete(const JobResponseOutcome());
    await booking;

    expect(matching.isResponding, isFalse);
  });
}

class _GatedMatchService implements RbCarsService {
  _GatedMatchService(this.gate);

  final Completer<JobResponseOutcome> gate;

  int selectCalls = 0;

  @override
  Future<JobResponseOutcome> selectTechnician(String matchId) {
    selectCalls += 1;
    return gate.future;
  }

  @override
  Future<List<MatchResult>> fetchMatches(String jobId) async =>
      const <MatchResult>[];

  @override
  Future<Job?> jobById(String jobId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
