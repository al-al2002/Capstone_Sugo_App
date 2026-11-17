import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/community/models/community_models.dart';
import 'package:sugo_app/features/rb_cars/models/technician.dart';
import 'package:sugo_app/features/rb_cars/models/technician_preferences.dart';
import 'package:sugo_app/features/rb_cars/models/trust_badge.dart';
import 'package:sugo_app/features/technician/widgets/trust_badge_progress_card.dart';

/// The Progressive Trust Badge, app side (2026-11-15).
///
/// The rules themselves live in SQL (`trust_badge_level()`) and are pinned by
/// running the migration in PGlite; the engine's per-job rung is pinned in
/// `preferences.test.ts`. This half is what the app does with the result:
/// read it, never print the wire value, and show the technician the same
/// numbers the evaluator used.
void main() {
  Map<String, dynamic> metrics({
    String? level = 'skill_verified',
    int completed = 38,
    double? rating = 4.6,
    double? response = 0.92,
    int disputes = 0,
    List<String> skills = const <String>['phone_tablet'],
  }) => <String, dynamic>{
    'level': level,
    'identity_approved': true,
    'email_confirmed': true,
    'skill_verified_specializations': skills,
    'completed_jobs': completed,
    'avg_rating': rating,
    'response_rate': response,
    'offers_counted': 25,
    'offers_answered_in_time': 23,
    'disputes_open_or_lost': disputes,
    'accepted_jobs': 40,
    'cancellation_rate': 0,
    'thresholds': <String, dynamic>{
      'completed_jobs': 50,
      'avg_rating': 4.5,
      'response_rate': 0.9,
      'max_disputes': 0,
      'max_cancellation_rate': 0.1,
      'response_window_hours': 24,
    },
  };

  group('TrustBadge', () {
    test('reads the three wire values and nothing else', () {
      expect(TrustBadge.fromWire('id_verified'), TrustBadge.idVerified);
      expect(TrustBadge.fromWire('skill_verified'), TrustBadge.skillVerified);
      expect(
        TrustBadge.fromWire('community_trusted'),
        TrustBadge.communityTrusted,
      );
      expect(TrustBadge.fromWire('certified_pro'), isNull);
      expect(TrustBadge.fromWire('Top Rated'), isNull);
    });

    test('rungs compare in order, never by equality', () {
      expect(
        TrustBadge.communityTrusted.atLeast(TrustBadge.skillVerified),
        isTrue,
      );
      expect(
        TrustBadge.skillVerified.atLeast(TrustBadge.skillVerified),
        isTrue,
      );
      expect(TrustBadge.idVerified.atLeast(TrustBadge.skillVerified), isFalse);
      expect(TrustBadge.idVerified.next, TrustBadge.skillVerified);
      expect(TrustBadge.communityTrusted.next, isNull);
    });
  });

  group('the badge is named, never printed raw', () {
    test('a technician card reads the label', () {
      final Technician t = Technician.fromJson(<String, dynamic>{
        'id': 't1',
        'badge': 'skill_verified',
      });
      expect(t.trustBadge, TrustBadge.skillVerified);
      expect(t.badgeLabel, 'Skill verified');
    });

    test('a community author reads the label', () {
      const CommunityAuthor author = CommunityAuthor(
        id: 'a',
        role: 'technician',
        badge: 'community_trusted',
      );
      expect(author.badgeLabel, 'Community Trusted');
    });

    test('the match snapshot carries the badge for that one job', () {
      final Technician t = Technician.fromJson(<String, dynamic>{
        'id': 't1',
        'badge': 'community_trusted',
        'trust_badge_for_job': 'id_verified',
      });
      expect(t.trustBadge, TrustBadge.communityTrusted);
      expect(t.trustBadgeForJob, TrustBadge.idVerified);
    });

    test('verified specialisations come from the verified rows only', () {
      final Technician t = Technician.fromJson(<String, dynamic>{
        'id': 't1',
        'specializations': <Map<String, dynamic>>[
          <String, dynamic>{
            'device_type': 'desktop',
            'brand': 'MSI',
            'verified': true,
          },
          <String, dynamic>{
            'device_type': 'smartphone',
            'brand': 'Apple',
            'verified': false,
          },
        ],
      });
      expect(t.skillVerifiedSpecializations, <PreferredSpecialization>[
        PreferredSpecialization.computer,
        PreferredSpecialization.pcBuilding,
      ]);
    });
  });

  group('TrustBadgeProgress', () {
    test('reads my_trust_badge() and says the brief\'s one-line summary', () {
      final TrustBadgeProgress p = TrustBadgeProgress.fromJson(metrics());
      expect(p.level, TrustBadge.skillVerified);
      expect(p.skillVerified, <PreferredSpecialization>[
        PreferredSpecialization.phoneTablet,
      ]);
      expect(p.summary, '38 / 50 jobs, rating 4.6, response 92%');
      expect(p.jobsMet, isFalse);
      expect(p.ratingMet, isTrue);
      expect(p.responseMet, isTrue);
    });

    test('no ratings or offers yet reads as a dash, not zero', () {
      final TrustBadgeProgress p = TrustBadgeProgress.fromJson(
        metrics(rating: null, response: null),
      );
      expect(p.summary, '38 / 50 jobs, rating —, response —');
    });
  });

  group('the progress card', () {
    Future<void> pump(WidgetTester tester, Map<String, dynamic> json) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: TrustBadgeProgressCard(
                progress: TrustBadgeProgress.fromJson(json),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('skill verified shows the path to Community Trusted', (
      WidgetTester tester,
    ) async {
      await pump(tester, metrics());
      expect(find.text('Skill verified'), findsOneWidget);
      expect(find.text('Next: Community Trusted'), findsOneWidget);
      expect(
        find.text('38 / 50 jobs, rating 4.6, response 92%'),
        findsOneWidget,
      );
      expect(find.text('38 / 50'), findsOneWidget);
      expect(find.text('Phone/Tablet'), findsOneWidget);
    });

    testWidgets('community trusted frames the same numbers as what keeps it', (
      WidgetTester tester,
    ) async {
      await pump(tester, metrics(level: 'community_trusted', completed: 52));
      expect(find.text('Community Trusted'), findsOneWidget);
      expect(find.textContaining('Keep all five'), findsOneWidget);
      expect(find.textContaining('Next:'), findsNothing);
    });

    testWidgets('below the baseline lists what identity still needs', (
      WidgetTester tester,
    ) async {
      await pump(tester, <String, dynamic>{
        ...metrics(level: null, skills: const <String>[]),
        'email_confirmed': false,
      });
      expect(find.text('No badge yet'), findsOneWidget);
      expect(find.text('Email confirmed'), findsOneWidget);
      expect(find.text('Not confirmed yet'), findsOneWidget);
    });

    testWidgets('fits a small phone at large text', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(320, 640) * 3;
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
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: TrustBadgeProgressCard(
                    progress: TrustBadgeProgress.fromJson(metrics()),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
