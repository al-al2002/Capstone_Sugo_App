import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/core/widgets/sugo_button.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/technician/widgets/complete_job_sheet.dart';

/// The wrap-up sheet behind "Mark as complete" (2026-11-16): no diagnosis
/// question and no reroute switch, but "What did you fix?" still yields the
/// RB-CARS `diagnosis_correct` signal.
void main() {
  Job job({String symptom = 'laptop_wont_power_on'}) => Job(
    id: 'a3f2b1c4-0000-0000-0000-000000000000',
    clientId: 'client-1',
    deviceType: DeviceType.laptop,
    problemSymptom: symptom,
    hasPhysicalDamage: false,
    status: JobStatus.inProgress,
    assignedTechnicianId: 'tech-1',
    servicePath: ServicePath.homeService,
  );

  /// Opens the sheet and hands back whatever it returns.
  Future<List<CompletionAnswers?>> open(WidgetTester tester, Job on) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1400);
    addTearDown(tester.view.reset);

    final List<CompletionAnswers?> results = <CompletionAnswers?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async =>
                  results.add(await CompleteJobSheet.show(context, on)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  SugoButton completeButton(WidgetTester tester) => tester.widget<SugoButton>(
    find.widgetWithText(SugoButton, 'Complete job'),
  );

  Future<void> tickBothChecks(WidgetTester tester) async {
    await tester.tap(find.text('It works, and the client has seen it'));
    await tester.tap(find.text('Payment is settled'));
    await tester.pumpAndSettle();
  }

  testWidgets('asks what was fixed, not "was the diagnosis correct"', (
    WidgetTester tester,
  ) async {
    await open(tester, job());

    expect(find.text('Wrap up this job'), findsOneWidget);
    expect(find.text('What did you fix?'), findsOneWidget);
    expect(find.textContaining('diagnosis'), findsNothing);
    expect(find.textContaining('Rerouted'), findsNothing);
    // Nothing is preselected, so nothing is assumed.
    expect(completeButton(tester).onPressed, isNull);
    expect(find.textContaining('Still to do: what you fixed'), findsOneWidget);
  });

  testWidgets('"what the client reported" means the diagnosis was right', (
    WidgetTester tester,
  ) async {
    final List<CompletionAnswers?> results = await open(tester, job());

    await tester.tap(find.text('Will not turn on'));
    await tester.pumpAndSettle();
    expect(completeButton(tester).onPressed, isNull, reason: 'checks first');

    await tickBothChecks(tester);
    expect(find.text('The client will be asked to rate you.'), findsOneWidget);
    await tester.tap(find.text('Complete job'));
    await tester.pumpAndSettle();

    final CompletionAnswers answers = results.single!;
    expect(answers.diagnosisCorrect, isTrue);
    expect(answers.fixedLabel, 'Will not turn on');
    expect(answers.wrapUpMessage, isNull, reason: 'no note, no message');
  });

  testWidgets('"something else" records it as wrong, with the real fault', (
    WidgetTester tester,
  ) async {
    final List<CompletionAnswers?> results = await open(tester, job());

    expect(find.text('Very slow or freezing'), findsNothing);
    await tester.tap(find.text('Something else'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Very slow or freezing'));
    await tickBothChecks(tester);
    await tester.enterText(find.byType(TextField), 'Keep the vents clear.');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Complete job'));
    await tester.tap(find.text('Complete job'));
    await tester.pumpAndSettle();

    final CompletionAnswers answers = results.single!;
    expect(answers.diagnosisCorrect, isFalse);
    expect(answers.fixedLabel, 'Very slow or freezing');
    expect(
      answers.wrapUpMessage,
      'Job done. What I fixed: Very slow or freezing.\n\nKeep the vents clear.',
    );
  });

  testWidgets('a "not sure" job has nothing to judge: no verdict', (
    WidgetTester tester,
  ) async {
    final List<CompletionAnswers?> results = await open(
      tester,
      job(symptom: 'not_sure'),
    );

    expect(find.text('Something else'), findsNothing);
    expect(find.textContaining('was not sure'), findsOneWidget);
    await tester.tap(find.text('Not on the list'));
    await tickBothChecks(tester);
    await tester.tap(find.text('Complete job'));
    await tester.pumpAndSettle();

    expect(results.single!.diagnosisCorrect, isNull);
    expect(results.single!.fixedLabel, isNull);
  });

  testWidgets('fits a small phone with large text', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: Scaffold(
              body: Builder(
                builder: (BuildContext inner) => TextButton(
                  onPressed: () => CompleteJobSheet.show(inner, job()),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Something else'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
