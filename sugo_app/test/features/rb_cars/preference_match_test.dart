import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/match_result.dart';
import 'package:sugo_app/features/rb_cars/models/preference_match.dart';
import 'package:sugo_app/features/rb_cars/models/technician_preferences.dart';
import 'package:sugo_app/features/rb_cars/widgets/match_score_card.dart';

/// "Meets your must-haves" on a match card (2026-11-17): the client's
/// pre-filter preferences, each shown with the technician's own value.
void main() {
  group('checkPreferences', () {
    test('every set preference is checked with the real value', () {
      final List<PreferenceCheck> checks = checkPreferences(
        const TechnicianPreferences(
          maxDistance: MaxDistance.km5,
          minRating: MinRating.r45,
          minTrust: TrustBadge.skillVerified,
          availability: AvailabilityPreference.now,
        ),
        distanceKm: 3.24,
        rating: 4.8,
        trustForJob: TrustBadge.communityTrusted,
      );

      expect(checks.map((PreferenceCheck c) => c.passed), everyElement(true));
      expect(checks.map((PreferenceCheck c) => c.detail), <String?>[
        '3.2 km',
        '4.8★',
        'free now',
        'Community Trusted',
      ]);
    });

    test('nothing set, nothing shown', () {
      expect(checkPreferences(TechnicianPreferences.none), isEmpty);
    });

    test('a change since matching is shown, not hidden', () {
      final List<PreferenceCheck> checks = checkPreferences(
        const TechnicianPreferences(availability: AvailabilityPreference.now),
        away: true,
      );
      expect(checks.single.passed, isFalse);
      expect(checks.single.detail, 'on leave');
    });

    test('what the card cannot see counts as passed by the server', () {
      final PreferenceCheck check = checkPreferences(
        const TechnicianPreferences(
          specialization: PreferredSpecialization.phoneTablet,
        ),
      ).single;
      expect(check.met, isNull);
      expect(check.passed, isTrue);
    });
  });

  testWidgets('the card shows the preferences as bars', (
    WidgetTester tester,
  ) async {
    final MatchResult match = MatchResult.fromJson(<String, dynamic>{
      'id': 'm1',
      'job_id': 'j1',
      'technician_id': 't1',
      'rank': 1,
      'status': 'shortlisted',
      'score_breakdown': <String, dynamic>{
        'context': <String, dynamic>{'distance_km': 3.2},
        'technician': <String, dynamic>{
          'id': 't1',
          'full_name': 'Vance Reyes',
          'rating': 4.6,
          'total_jobs': 26,
          'trust_badge_for_job': 'skill_verified',
        },
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: MatchScoreCard(
              match: match,
              preferences: const TechnicianPreferences(
                maxDistance: MaxDistance.km5,
                minRating: MinRating.r45,
                minTrust: TrustBadge.skillVerified,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Bars since 2026-11-17, one per preference the client set.
    expect(find.text('Your preferences'), findsOneWidget);
    expect(find.text('Meets all'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('3.2 km · within 5 km'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(find.text('4.6★ · min 4.5'), findsOneWidget);
    expect(find.text('Trust badge'), findsOneWidget);
    // On the trust bar, and on the technician's own badge pill.
    expect(find.text('Skill verified'), findsWidgets);
  });
}
