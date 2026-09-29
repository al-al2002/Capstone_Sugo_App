import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/technician_profile_details.dart';
import 'package:sugo_app/features/rb_cars/widgets/review_card.dart';

/// Reviews with the repair they were about, and the past-work summary.
///
/// Rendered inside a `ListView` on purpose. Both profile screens put these in
/// vertically scrolling lists, which hand their children unbounded height -
/// the constraint that broke the Community feed card, and the one a bare
/// `Scaffold` harness never applies.
void main() {
  Widget inList(List<Widget> children) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: ListView(children: children)),
  );

  Future<void> small(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  // Shaped exactly like a row from `technician_profile` after migration
  // 20260921000009.
  Map<String, dynamic> reviewJson({
    String? device = 'phone',
    String? brand = 'Samsung',
    String? symptom = 'Will not power on',
    String? path = 'home_service',
    String? comment = 'Fast, tidy work and explained the fix clearly.',
  }) => <String, dynamic>{
    'id': 'r1',
    'stars': 5,
    'comment': comment,
    'created_at': '2026-09-16T14:11:46Z',
    'reviewer_name': 'Maria Santos',
    'reviewer_avatar': null,
    'job_device_type': device,
    'job_brand': brand,
    'job_symptom': symptom,
    'job_service_path': path,
  };

  group('TechnicianReview parsing', () {
    test('reads the repair fields', () {
      final TechnicianReview r = TechnicianReview.fromJson(reviewJson());
      expect(r.jobDeviceType, DeviceType.phone);
      expect(r.jobServicePath, ServicePath.homeService);
      expect(r.jobDeviceLabel, 'Phone / Tablet · Samsung');
      expect(r.hasJob, isTrue);
    });

    test('a payload without job fields still parses - older or orphaned', () {
      final TechnicianReview r = TechnicianReview.fromJson(
        reviewJson(device: null, brand: null, symptom: null, path: null),
      );
      expect(r.hasJob, isFalse);
      expect(r.jobDeviceLabel, isNull);
      expect(r.stars, 5);
    });

    test('no brand shows the device alone', () {
      final TechnicianReview r = TechnicianReview.fromJson(
        reviewJson(brand: null),
      );
      expect(r.jobDeviceLabel, 'Phone / Tablet');
    });
  });

  group('TechnicianProfileDetails', () {
    Map<String, dynamic> profile() => <String, dynamic>{
      'id': 't1',
      'full_name': 'Lance',
      'rating': 4.6,
      'review_count': 20,
      'total_jobs': 21,
      'reviews': <dynamic>[reviewJson()],
      'work_history': <dynamic>[
        <String, dynamic>{'device_type': 'laptop', 'jobs': 6},
        <String, dynamic>{'device_type': 'phone', 'jobs': 5},
        <String, dynamic>{'device_type': 'network', 'jobs': 0},
      ],
    };

    test('parses work history and drops empty buckets', () {
      final TechnicianProfileDetails d = TechnicianProfileDetails.fromJson(
        profile(),
      );
      expect(d.workHistory, hasLength(2));
      expect(d.workHistory.first.deviceType, DeviceType.laptop);
      expect(d.workHistory.first.jobs, 6);
    });

    test('paging keeps the work history', () {
      // `withMoreReviews` rebuilds the object field by field. Forgetting one
      // blanks it the moment a second page loads - the same trap the class
      // already documents for the workshop location.
      final TechnicianProfileDetails d = TechnicianProfileDetails.fromJson(
        profile(),
      );
      final TechnicianProfileDetails paged = d.withMoreReviews(
        <TechnicianReview>[TechnicianReview.fromJson(reviewJson())],
      );
      expect(paged.reviews, hasLength(2));
      expect(paged.workHistory, hasLength(2));
    });
  });

  group('ReviewCard', () {
    testWidgets('shows the repair above the verdict, in a list', (
      WidgetTester tester,
    ) async {
      await small(tester);
      await tester.pumpWidget(
        inList(<Widget>[
          ReviewCard(review: TechnicianReview.fromJson(reviewJson())),
        ]),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Will not power on'), findsOneWidget);
      expect(find.text('Phone / Tablet · Samsung'), findsOneWidget);
      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.textContaining('Fast, tidy work'), findsOneWidget);

      // Order matters: the repair must read before the verdict.
      final double jobY = tester.getTopLeft(find.text('Will not power on')).dy;
      final double nameY = tester.getTopLeft(find.text('Maria Santos')).dy;
      expect(jobY, lessThan(nameY));
    });

    testWidgets('a review with no job still renders cleanly', (
      WidgetTester tester,
    ) async {
      await small(tester);
      await tester.pumpWidget(
        inList(<Widget>[
          ReviewCard(
            review: TechnicianReview.fromJson(
              reviewJson(device: null, brand: null, symptom: null, path: null),
            ),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Maria Santos'), findsOneWidget);
    });

    testWidgets('a rating without words says so', (WidgetTester tester) async {
      await small(tester);
      await tester.pumpWidget(
        inList(<Widget>[
          ReviewCard(review: TechnicianReview.fromJson(reviewJson(comment: ''))),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rated without a written review.'), findsOneWidget);
    });
  });

  group('PastWorkSummary', () {
    testWidgets('totals every device and lays out in a list', (
      WidgetTester tester,
    ) async {
      await small(tester);
      await tester.pumpWidget(
        inList(<Widget>[
          const PastWorkSummary(
            entries: <WorkHistoryEntry>[
              WorkHistoryEntry(deviceType: DeviceType.laptop, jobs: 6),
              WorkHistoryEntry(deviceType: DeviceType.appliance, jobs: 5),
              WorkHistoryEntry(deviceType: DeviceType.network, jobs: 5),
              WorkHistoryEntry(deviceType: DeviceType.phone, jobs: 5),
            ],
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('21 completed jobs'), findsOneWidget);
      expect(find.text('Laptop / PC'), findsOneWidget);
      expect(find.text('Network / CCTV'), findsOneWidget);
    });

    testWidgets('survives a narrow phone with large accessibility text', (
      WidgetTester tester,
    ) async {
      // The real screen: a 320dp phone, the 20px page gutters both profile
      // screens use, and the system text scaled up - the combination that
      // turns "fits in testing" into an overflow stripe for real users.
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: <Widget>[
                  const PastWorkSummary(
                    entries: <WorkHistoryEntry>[
                      WorkHistoryEntry(deviceType: DeviceType.network, jobs: 112),
                      WorkHistoryEntry(deviceType: DeviceType.laptop, jobs: 9),
                    ],
                  ),
                  ReviewCard(
                    review: TechnicianReview.fromJson(
                      reviewJson(
                        brand: 'Samsung Galaxy',
                        path: 'it_community',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders nothing when there is no work', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        inList(<Widget>[const PastWorkSummary(entries: <WorkHistoryEntry>[])]),
      );
      expect(find.text('Past work'), findsNothing);
    });
  });
}
