import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/tracking/models/job_tracking.dart';
import 'package:sugo_app/features/tracking/services/tracking_service.dart';
import 'package:sugo_app/features/tracking/widgets/return_method_card.dart';

/// "How do you want it back?" on a workshop repair.
///
/// The rules themselves are the database's (`set_return_method()`, checked
/// against the live project); this pins what the client sees: both choices,
/// the save, the route appearing once they collect, and the one switch the
/// card refuses before asking the server.
void main() {
  Widget host(ReturnMethodCard card) => MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(320, 900),
        textScaler: TextScaler.linear(1.3),
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: card,
        ),
      ),
    ),
  );

  testWidgets('choosing to collect saves it and opens the way to the shop', (
    WidgetTester tester,
  ) async {
    final _FakeTracking service = _FakeTracking(ReturnMethod.delivery);

    await tester.pumpWidget(
      host(
        ReturnMethodCard(
          jobId: 'job-1',
          technicianId: 'tech-1',
          stage: TrackingStage.inRepair,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How do you want it back?'), findsOneWidget);
    expect(find.text('Deliver it to me'), findsOneWidget);
    expect(find.text("I'll pick it up"), findsOneWidget);

    await tester.tap(find.text("I'll pick it up"));
    await tester.pumpAndSettle();

    expect(service.saved, <ReturnMethod>[ReturnMethod.clientPickup]);
    // Still at the bench, so the card says so above the route. With no
    // workshop on record (none in a test) it falls back to "message them".
    expect(find.textContaining('Still being repaired'), findsOneWidget);
    expect(find.textContaining('has not added a workshop address'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('once it waits at the shop, delivery is refused before asking', (
    WidgetTester tester,
  ) async {
    final _FakeTracking service = _FakeTracking(ReturnMethod.clientPickup);

    await tester.pumpWidget(
      host(
        ReturnMethodCard(
          jobId: 'job-1',
          technicianId: 'tech-1',
          stage: TrackingStage.readyForCollection,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('It is ready'), findsOneWidget);

    await tester.tap(find.text('Deliver it to me'));
    await tester.pump();

    expect(service.saved, isEmpty);
    expect(find.textContaining('already waiting at the shop'), findsOneWidget);
  });

  test('an unknown wire value reads as delivery, the default', () {
    expect(ReturnMethod.fromWire(null), ReturnMethod.delivery);
    expect(ReturnMethod.fromWire('client_pickup'), ReturnMethod.clientPickup);
    expect(ReturnMethod.fromWire('teleport'), ReturnMethod.delivery);
  });
}

class _FakeTracking implements TrackingService {
  _FakeTracking(this.current);

  ReturnMethod current;
  final List<ReturnMethod> saved = <ReturnMethod>[];

  @override
  Future<ReturnMethod> returnMethod(String jobId) async => current;

  @override
  Future<ReturnMethod> setReturnMethod(String jobId, ReturnMethod method) async {
    saved.add(method);
    current = method;
    return method;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
