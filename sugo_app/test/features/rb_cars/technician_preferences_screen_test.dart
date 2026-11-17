import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/device_category.dart';
import 'package:sugo_app/features/rb_cars/models/technician_preferences.dart';
import 'package:sugo_app/features/rb_cars/providers/job_posting_provider.dart';
import 'package:sugo_app/features/rb_cars/screens/technician_preferences_screen.dart';
import 'package:sugo_app/features/rb_cars/widgets/relax_preferences_panel.dart';

/// The two screens a client touches: the step that sets the preferences, and
/// the panel that relaxes them when they leave nobody.
void main() {
  Widget host(Widget child, {double textScale = 1}) => MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (BuildContext context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child,
      ),
    ),
  );

  /// Sets the real test surface. Overriding `MediaQuery.size` alone does not:
  /// layout still happens on the 800x600 default, so scrolling and overflow
  /// would be tested on the wrong screen.
  void phone(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = size * 3;
    addTearDown(tester.view.reset);
  }

  group('the "Your technician" step', () {
    late JobPostingProvider posting;

    setUp(() {
      posting = JobPostingProvider()..selectCategory(DeviceCategory.phone);
    });
    tearDown(() => posting.dispose());

    testWidgets('opens with everything on No preference, and says so on the '
        'button', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(TechnicianPreferencesScreen(posting: posting)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Any must-haves?'), findsOneWidget);
      expect(find.text('Continue without preferences'), findsOneWidget);
      expect(find.text('Reset all'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking a rating counts on the button and can be reset', (
      WidgetTester tester,
    ) async {
      phone(tester, const Size(390, 1400));
      await tester.pumpWidget(
        host(TechnicianPreferencesScreen(posting: posting)),
      );
      await tester.pumpAndSettle();

      // The rating field is the third dropdown; open it by its hint row.
      final Finder ratingField = find.byWidgetPredicate(
        (Widget w) => w is DropdownButtonFormField<MinRating?>,
      );
      await tester.ensureVisible(ratingField);
      await tester.tap(ratingField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('4.5+').last);
      await tester.pumpAndSettle();

      expect(posting.preferences.minRating, MinRating.r45);
      expect(find.text('Continue with 1 preference'), findsOneWidget);

      await tester.tap(find.text('Reset all'));
      await tester.pumpAndSettle();

      expect(posting.preferences.hasAny, isFalse);
      expect(find.text('Continue without preferences'), findsOneWidget);
    });

    testWidgets('a phone job is only offered the phone specialisation', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(TechnicianPreferencesScreen(posting: posting)),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byWidgetPredicate(
          (Widget w) => w is DropdownButtonFormField<PreferredSpecialization?>,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Phone/Tablet'), findsWidgets);
      expect(find.text('Appliance Service'), findsNothing);
      expect(find.text('Computer/Laptop'), findsNothing);
    });

    // Removed at the user's request (2026-11-17), and the app's own name
    // replaces "RB-CARS" in what the client reads.
    testWidgets('has no Availability question, and names SUGO', (
      WidgetTester tester,
    ) async {
      phone(tester, const Size(390, 1400));
      await tester.pumpWidget(
        host(TechnicianPreferencesScreen(posting: posting)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Availability'), findsNothing);
      expect(find.text('Available now'), findsNothing);
      expect(find.text('Pick a date'), findsNothing);
      expect(
        find.text('All optional. Skip this and SUGO ranks everyone nearby.'),
        findsOneWidget,
      );
      expect(find.textContaining('RB-CARS'), findsNothing);
    });

    testWidgets('fits a small phone at large text without overflow', (
      WidgetTester tester,
    ) async {
      posting.setPreferences(
        const TechnicianPreferences(
          specialization: PreferredSpecialization.phoneTablet,
          maxDistance: MaxDistance.km10,
          minRating: MinRating.r45,
          minTrust: TrustBadge.communityTrusted,
        ),
      );
      phone(tester, const Size(320, 640));
      await tester.pumpWidget(
        host(TechnicianPreferencesScreen(posting: posting), textScale: 1.3),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Continue with 4 preferences'), findsOneWidget);
    });
  });

  group('the relax panel', () {
    const TechnicianPreferences prefs = TechnicianPreferences(
      maxDistance: MaxDistance.km3,
      minRating: MinRating.r45,
    );

    testWidgets('shows one chip per preference with what removing it brings '
        'back', (WidgetTester tester) async {
      TechnicianPreferences? relaxedTo;
      await tester.pumpWidget(
        host(
          Scaffold(
            body: SingleChildScrollView(
              child: RelaxPreferencesPanel(
                preferences: prefs,
                hints: const <RelaxHint>[
                  RelaxHint(field: PreferenceField.maxDistance, wouldMatch: 2),
                  RelaxHint(field: PreferenceField.minRating, wouldMatch: 0),
                ],
                onRelax: (TechnicianPreferences next) => relaxedTo = next,
                onSearchAgain: () {},
              ),
            ),
          ),
        ),
      );

      expect(
        find.text('No technician matches your preferences'),
        findsOneWidget,
      );
      expect(find.text('Within 3 km'), findsOneWidget);
      expect(find.text('4.5+ rating'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);

      await tester.tap(find.text('Within 3 km'));
      expect(relaxedTo?.maxDistance, isNull);
      expect(relaxedTo?.minRating, MinRating.r45);

      await tester.tap(find.text('Clear all and search again'));
      expect(relaxedTo, TechnicianPreferences.none);
    });
  });
}
