import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/device_category.dart';
import 'package:sugo_app/features/rb_cars/models/schedule_preference.dart';
import 'package:sugo_app/features/rb_cars/providers/job_posting_provider.dart';
import 'package:sugo_app/features/rb_cars/screens/device_details_screen.dart';
import 'package:sugo_app/features/rb_cars/screens/job_posting_screen.dart';
import 'package:sugo_app/features/rb_cars/screens/review_and_post_screen.dart';
import 'package:sugo_app/features/rb_cars/screens/symptom_screen.dart';
import 'package:sugo_app/features/rb_cars/screens/where_and_when_screen.dart';

/// Renders the posting flow for design review. Regenerate after intentional
/// changes:
///
///   flutter test --update-goldens
///
/// Four of the five steps, laid out side by side like the mockup they were
/// built from. Step 4 is absent on purpose: it is mostly `LocationPickerMap`,
/// which fetches tiles over the network, and a golden that depends on a tile
/// server is a golden that fails on a train.
///
/// Goldens are platform-specific; regenerate if they fail on another machine.
void main() {
  /// A draft filled in as far as the review step, so every screen renders in
  /// its answered state rather than empty.
  JobPostingProvider filledDraft() {
    final JobPostingProvider posting = JobPostingProvider();
    posting.selectCategory(DeviceCategory.laptop);
    posting.selectSymptom('laptop_wont_power_on');
    posting.setDeviceDetail(deviceDetail: 'laptop', brand: 'Lenovo');
    posting.setModel('IdeaPad 3 14"');
    posting.setDescription(
      'It was fine last night. This morning the power light comes on for a '
      'second and then nothing.',
    );
    posting.setLocation(latitude: 7.0731, longitude: 125.6128);
    posting.setSchedulePreference(SchedulePreference.thisWeek);
    posting.setBudget(min: 850, max: 1200);
    return posting;
  }

  testWidgets('posting flow, steps 1-3 and 5', (WidgetTester tester) async {
    // Four 390x860 phones in a row, at 2x.
    tester.view.physicalSize = const Size(3120, 1720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final JobPostingProvider posting = filledDraft();
    addTearDown(posting.dispose);

    Widget phone(Widget child) {
      return SizedBox(
        width: 390,
        height: 860,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(390, 860)),
          child: child,
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Row(
          children: <Widget>[
            phone(const JobPostingScreen()),
            phone(SymptomScreen(posting: posting)),
            phone(DeviceDetailsScreen(posting: posting)),
            phone(ReviewAndPostScreen(posting: posting)),
          ],
        ),
      ),
    );

    // Step 1 owns its own provider, so it starts empty. Tap a card so the
    // golden shows the selected state the other three are already in.
    await tester.tap(find.text('Laptop / PC').first);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../goldens/posting_flow.png'),
    );
  });

  // Step 4 is kept out of the golden but not out of the tests: it is the only
  // screen with a network dependency, so it gets a render check instead.
  testWidgets('step 4 renders with the map', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(780, 1720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final JobPostingProvider posting = filledDraft();
    addTearDown(posting.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: WhereAndWhenScreen(posting: posting),
      ),
    );
    await tester.pump();

    expect(find.text('Where and when?'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
