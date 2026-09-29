import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/bookings/widgets/rate_job_sheet.dart';
import 'package:sugo_app/features/rb_cars/models/technician_profile_details.dart';

/// A rating the client did not give must never be saved.
///
/// Reviews now set `technicians.rating`, which ranks the recommended row and
/// feeds the matcher. So a sheet that opened on a default of five stars - or
/// that let "Submit" through with no stars chosen - would quietly write
/// ratings into the ranking that no client actually gave. This pins the rule.
void main() {
  Future<void> pumpSheet(WidgetTester tester, {TechnicianReview? existing}) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: RateJobSheet(
            jobId: 'job-1',
            technicianId: 'tech-1',
            technicianName: 'your technician',
            existing: existing,
          ),
        ),
      ),
    );
  }

  FilledButton submit(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('opens with no stars and cannot be submitted', (
    WidgetTester tester,
  ) async {
    await pumpSheet(tester);

    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.byIcon(Icons.star_border_rounded), findsNWidgets(5));
    expect(
      submit(tester).onPressed,
      isNull,
      reason: 'no star chosen means nothing to save',
    );
  });

  testWidgets('choosing a star enables submit and labels the rating', (
    WidgetTester tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.byTooltip('4 stars'));
    await tester.pump();

    expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
    expect(find.text('Good'), findsOneWidget);
    expect(submit(tester).onPressed, isNotNull);
  });

  testWidgets('editing opens on the stars the client actually gave', (
    WidgetTester tester,
  ) async {
    await pumpSheet(
      tester,
      existing: const TechnicianReview(id: 'r1', stars: 2, comment: 'Late'),
    );

    expect(find.text('Edit your review'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));
    expect(find.text('Below expectations'), findsOneWidget);
    expect(find.text('Late'), findsOneWidget);
  });
}
