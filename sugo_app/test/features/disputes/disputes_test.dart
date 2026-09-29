import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/core/widgets/sugo_button.dart';
import 'package:sugo_app/features/disputes/models/job_dispute.dart';
import 'package:sugo_app/features/disputes/services/dispute_service.dart';
import 'package:sugo_app/features/disputes/widgets/dispute_section.dart';
import 'package:sugo_app/features/disputes/widgets/report_problem_sheet.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';

/// "Report a problem with this booking": the model, the sheet, and the
/// section on the booking screen.
void main() {
  Map<String, dynamic> row({
    String role = 'client',
    String status = 'open',
    String? note,
  }) => <String, dynamic>{
    'id': 'd1',
    'job_id': 'j1',
    'raised_by': 'u1',
    'raised_by_role': role,
    'reason': 'not_fixed',
    'details': 'The laptop still does not turn on after the repair.',
    'photo_paths': <String>['j1/1.jpg'],
    'status': status,
    'resolution_note': note,
    'resolved_at': note == null ? null : '2026-09-28T12:00:00Z',
    'created_at': '2026-09-28T10:00:00Z',
  };

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );

  group('model', () {
    test('reads a row, and an unknown reason falls back to "other"', () {
      final JobDispute d = JobDispute.fromJson(row());
      expect(d.reason, DisputeReason.notFixed);
      expect(d.raisedByClient, isTrue);
      expect(d.isOpen, isTrue);
      expect(d.photoPaths, <String>['j1/1.jpg']);

      expect(
        DisputeReason.fromWire('something_new'),
        DisputeReason.other,
      );
    });

    test('each side is offered only the reasons that fit it', () {
      final List<DisputeReason> client = DisputeReason.forRole(isClient: true);
      final List<DisputeReason> tech = DisputeReason.forRole(isClient: false);

      expect(client, contains(DisputeReason.notFixed));
      expect(client, isNot(contains(DisputeReason.payment)));
      expect(tech, contains(DisputeReason.payment));
      expect(tech, isNot(contains(DisputeReason.notFixed)));
    });
  });

  group('report sheet', () {
    testWidgets('send stays off until a reason and a real description', (
      WidgetTester tester,
    ) async {
      final _FakeDisputes service = _FakeDisputes();
      await tester.pumpWidget(
        host(
          ReportProblemSheet(jobId: 'j1', isClient: true, service: service),
        ),
      );

      bool sendEnabled() =>
          tester.widget<SugoButton>(find.byType(SugoButton)).onPressed != null;

      expect(sendEnabled(), isFalse);

      await tester.tap(find.text('The problem was not fixed'));
      await tester.enterText(find.byType(TextField), 'too short');
      await tester.pump();
      expect(sendEnabled(), isFalse, reason: 'under ten characters');

      await tester.enterText(
        find.byType(TextField),
        'Still does not turn on after the repair.',
      );
      await tester.pump();
      expect(sendEnabled(), isTrue);

      await tester.ensureVisible(find.text('Send report'));
      await tester.tap(find.text('Send report'));
      await tester.pump();
      expect(service.sent?.reason, DisputeReason.notFixed);
      expect(service.sent?.details, 'Still does not turn on after the repair.');
    });

    testWidgets('a technician is not offered "not fixed"', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          ReportProblemSheet(
            jobId: 'j1',
            isClient: false,
            service: _FakeDisputes(),
          ),
        ),
      );
      expect(find.text('The problem was not fixed'), findsNothing);
      expect(find.text('I was not paid'), findsOneWidget);
    });

    testWidgets("the server's refusal is shown in its own words", (
      WidgetTester tester,
    ) async {
      final _FakeDisputes service = _FakeDisputes(
        refuse: 'Reports close 7 days after a booking is completed. Contact '
            'SUGO support instead.',
      );
      await tester.pumpWidget(
        host(
          ReportProblemSheet(
            jobId: 'j1',
            isClient: true,
            service: service,
            initialReason: DisputeReason.notFixed,
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextField),
        'Still does not turn on after the repair.',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Send report'));
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Reports close 7 days'), findsOneWidget);
    });
  });

  group('section on the booking', () {
    testWidgets('offers the report when there is none of mine open', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          DisputeSection(
            disputes: const <JobDispute>[],
            isClient: true,
            canReport: true,
            onReport: () {},
          ),
        ),
      );
      expect(find.text('Report a problem with this booking'), findsOneWidget);
    });

    testWidgets('an open report of mine replaces the button with its status', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          DisputeSection(
            disputes: <JobDispute>[JobDispute.fromJson(row())],
            isClient: true,
            canReport: true,
            onReport: () {},
          ),
        ),
      );
      expect(find.text('Report a problem with this booking'), findsNothing);
      expect(find.text('Under review'), findsOneWidget);
      expect(find.textContaining('You reported'), findsOneWidget);
    });

    testWidgets('the other side sees the report and the decision', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          DisputeSection(
            disputes: <JobDispute>[
              JobDispute.fromJson(
                row(
                  status: 'resolved',
                  note: 'The technician will return on Friday at no charge.',
                ),
              ),
            ],
            isClient: false,
            canReport: true,
            onReport: () {},
          ),
        ),
      );
      expect(find.textContaining('The client reported'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
      expect(
        find.text('The technician will return on Friday at no charge.'),
        findsOneWidget,
      );
      // The technician has no report of their own open, so may still file one.
      expect(find.text('Report a problem with this booking'), findsOneWidget);
    });
  });
}

class _Sent {
  _Sent(this.reason, this.details);
  final DisputeReason reason;
  final String details;
}

class _FakeDisputes implements DisputeService {
  _FakeDisputes({this.refuse});

  final String? refuse;
  _Sent? sent;

  @override
  Future<JobDispute> open({
    required String jobId,
    required DisputeReason reason,
    required String details,
    List<XFile> photos = const <XFile>[],
  }) async {
    final String? message = refuse;
    if (message != null) throw RbCarsFailure(message);
    sent = _Sent(reason, details.trim());
    return JobDispute(
      id: 'new',
      jobId: jobId,
      raisedBy: 'me',
      raisedByClient: true,
      reason: reason,
      details: details,
      status: DisputeStatus.open,
    );
  }

  @override
  Future<List<JobDispute>> forJob(String jobId) async => const <JobDispute>[];

  @override
  Future<String> photoUrl(String path) async => path;
}
