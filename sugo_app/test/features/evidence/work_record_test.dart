import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/evidence/models/job_evidence.dart';
import 'package:sugo_app/features/evidence/widgets/evidence_capture_sheet.dart';
import 'package:sugo_app/features/evidence/widgets/work_record_section.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';
import 'package:sugo_app/features/technician/widgets/technician_job_actions.dart';

/// In-task documentation, the work record (2026-11-22, migration
/// 20261122000002): the step names, the location stamp, the technician's
/// checklist, the client's timeline, the camera sheet, and "Mark as complete"
/// waiting on the required photos.
void main() {
  // A real 1x1 PNG, so the preview decodes like a camera photo would.
  final Uint8List png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );

  Map<String, dynamic> row({
    String milestone = 'intake',
    double? lat = 7.0731,
    double? lng = 125.6128,
    String? note,
  }) => <String, dynamic>{
    'id': 'e-$milestone',
    'job_id': 'job-1',
    'technician_id': 'tech-1',
    'milestone': milestone,
    'photo_paths': <String>['job-1/1.jpg'],
    'note': note,
    'latitude': lat,
    'longitude': lng,
    'captured_at': '2026-11-22T07:41:00Z',
  };

  group('the steps', () {
    test('the unit-as-found step is named for how the job travels', () {
      expect(EvidenceMilestone.intake.labelFor(ServicePath.homeService), 'Before');
      expect(EvidenceMilestone.intake.labelFor(ServicePath.pickup), 'Collected');
      expect(
        EvidenceMilestone.intake.labelFor(ServicePath.pickup, selfDropOff: true),
        'Unit received',
      );
      expect(EvidenceMilestone.after.labelFor(ServicePath.homeService), 'After');
      expect(EvidenceMilestone.after.labelFor(ServicePath.pickup), 'After repair');
    });

    test('only Before and After are required; a home visit has no handover', () {
      expect(
        EvidenceMilestone.values.where((EvidenceMilestone m) => m.required),
        <EvidenceMilestone>[EvidenceMilestone.intake, EvidenceMilestone.after],
      );
      expect(
        EvidenceMilestone.stepsFor(ServicePath.homeService),
        isNot(contains(EvidenceMilestone.handover)),
      );
      expect(
        EvidenceMilestone.stepsFor(ServicePath.pickup),
        contains(EvidenceMilestone.handover),
      );
    });

    test('missingRequired mirrors the server', () {
      expect(missingRequired(const <JobEvidence>[]), <EvidenceMilestone>[
        EvidenceMilestone.intake,
        EvidenceMilestone.after,
      ]);
      expect(missingRequired(<JobEvidence>[JobEvidence.fromJson(row())]), <EvidenceMilestone>[
        EvidenceMilestone.after,
      ]);
    });
  });

  group('the location stamp', () {
    test('at the address, some km away, or not recorded', () {
      final JobEvidence here = JobEvidence.fromJson(row());
      expect(here.locationStamp(7.0731, 125.6128), 'At the job address');
      // ~2.2 km north.
      expect(here.locationStamp(7.0931, 125.6128), '2.2 km from the job address');
      expect(
        JobEvidence.fromJson(row(lat: null, lng: null)).locationStamp(7.07, 125.61),
        'Location not recorded',
      );
    });

    test('the time is the server time, shown in local time', () {
      final JobEvidence e = JobEvidence.fromJson(row());
      expect(e.capturedAt.isUtc, isFalse);
      expect(e.capturedAt.toUtc(), DateTime.utc(2026, 11, 22, 7, 41));
    });
  });

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
    ),
  );
  Future<String> url(String path) async => 'https://example.invalid/$path';

  group('the technician checklist', () {
    testWidgets('Before and After are required, and After waits for Before', (
      WidgetTester tester,
    ) async {
      EvidenceMilestone? asked;
      await tester.pumpWidget(
        host(
          WorkRecordSection(
            evidence: const <JobEvidence>[],
            servicePath: ServicePath.homeService,
            missing: const <EvidenceMilestone>[
              EvidenceMilestone.intake,
              EvidenceMilestone.after,
            ],
            canAdd: true,
            onAdd: (EvidenceMilestone m) => asked = m,
            photoUrl: url,
          ),
        ),
      );

      expect(find.text('Work record'), findsOneWidget);
      expect(find.text('Before'), findsOneWidget);
      expect(find.text('Required'), findsNWidgets(2));
      expect(find.text('Add the Before photos first.'), findsOneWidget);

      final TextButton after = tester.widget<TextButton>(
        find.byKey(const ValueKey<String>('evidence-add-after')),
      );
      expect(after.onPressed, isNull, reason: 'After is locked until Before');

      await tester.tap(find.byKey(const ValueKey<String>('evidence-add-intake')));
      expect(asked, EvidenceMilestone.intake);
    });

    testWidgets('a saved step shows its time instead of "Required"', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          WorkRecordSection(
            evidence: <JobEvidence>[JobEvidence.fromJson(row())],
            servicePath: ServicePath.homeService,
            missing: const <EvidenceMilestone>[EvidenceMilestone.after],
            canAdd: true,
            onAdd: (_) {},
            photoUrl: url,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Required'), findsOneWidget, reason: 'only After now');
      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('a job posted before the record existed shows nothing required', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          WorkRecordSection(
            evidence: const <JobEvidence>[],
            servicePath: ServicePath.pickup,
            missing: const <EvidenceMilestone>[],
            canAdd: true,
            onAdd: (_) {},
            photoUrl: url,
          ),
        ),
      );
      expect(find.text('Required'), findsNothing);
      expect(find.text('Collected'), findsOneWidget);
      expect(find.text('Handover'), findsOneWidget);
    });
  });

  group('the client timeline', () {
    testWidgets('opens folded to one line, like the other sections', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          WorkRecordSection(
            evidence: <JobEvidence>[
              JobEvidence.fromJson(row()),
              JobEvidence.fromJson(row(milestone: 'after')),
            ],
            servicePath: ServicePath.homeService,
            forClient: true,
            photoUrl: url,
          ),
        ),
      );
      expect(find.text('Work record'), findsOneWidget);
      expect(find.text('Before · After'), findsOneWidget);
      expect(find.text('At the job address'), findsNothing, reason: 'folded');
    });

    testWidgets('shows each step with its stamp and note', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          WorkRecordSection(
            evidence: <JobEvidence>[
              JobEvidence.fromJson(row(note: 'Screen already cracked')),
            ],
            servicePath: ServicePath.homeService,
            jobLatitude: 7.0731,
            jobLongitude: 125.6128,
            forClient: true,
            photoUrl: url,
          ),
        ),
      );
      await tester.tap(find.text('Work record'));
      await tester.pumpAndSettle();
      // The step's own heading; the folded summary line says "Before" too.
      expect(find.text('Before'), findsWidgets);
      expect(find.text('At the job address'), findsOneWidget);
      expect(find.text('Screen already cracked'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('evidence-add-intake')), findsNothing);
    });

    testWidgets('says what to expect before any photo', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          WorkRecordSection(
            evidence: const <JobEvidence>[],
            servicePath: ServicePath.homeService,
            forClient: true,
            photoUrl: url,
          ),
        ),
      );
      expect(find.text('No photos yet'), findsOneWidget, reason: 'folded line');
      await tester.tap(find.text('Work record'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Before when they start'), findsOneWidget);
    });
  });

  group('the camera sheet', () {
    testWidgets('takes a photo, then saves it with the note', (
      WidgetTester tester,
    ) async {
      List<XFile>? saved;
      String? savedNote;
      await tester.pumpWidget(
        host(
          EvidenceCaptureSheet(
            pickPhoto: () async => XFile.fromData(png, name: 'shot.png'),
            onSave: (List<XFile> photos, String? note) async {
              saved = photos;
              savedNote = note;
            },
          ),
        ),
      );

      expect(find.text('Take at least one photo'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('evidence-take')));
      await tester.pump();
      expect(find.text('Save 1 photo to the work record'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('evidence-note')),
        'Battery swollen',
      );
      await tester.tap(find.byKey(const ValueKey<String>('evidence-save')));
      await tester.pump();
      expect(saved, hasLength(1));
      expect(savedNote, 'Battery swollen');
    });

    testWidgets('shows the server refusal word for word', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          EvidenceCaptureSheet(
            pickPhoto: () async => XFile.fromData(png, name: 'a.png'),
            onSave: (_, _) async => throw const RbCarsFailure(
              'Photos can be added only while the job is under way.',
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('evidence-take')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('evidence-save')));
      await tester.pump();
      expect(
        find.text('Photos can be added only while the job is under way.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('"Mark as complete" waits for the required photos', (
    WidgetTester tester,
  ) async {
    int completes = 0;
    await tester.pumpWidget(
      host(
        TechnicianJobActions(
          job: const Job(
            id: 'job-1',
            clientId: 'client-1',
            deviceType: DeviceType.laptop,
            problemSymptom: 'laptop_wont_power_on',
            hasPhysicalDamage: false,
            status: JobStatus.confirmed,
            assignedTechnicianId: 'tech-1',
            servicePath: ServicePath.homeService,
          ),
          onTrip: () {},
          onComplete: () => completes++,
          onNeedsShop: () {},
          completeBlockedReason: 'Add the Before and After photos first',
        ),
      ),
    );
    expect(find.text('Add the Before and After photos first'), findsOneWidget);
    await tester.tap(find.text('Mark as complete'));
    expect(completes, 0);
  });
}
