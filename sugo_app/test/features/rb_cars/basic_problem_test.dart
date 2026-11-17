import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/basic_problem.dart';
import 'package:sugo_app/features/rb_cars/models/device_category.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/problem_catalog.dart';
import 'package:sugo_app/features/rb_cars/providers/job_posting_provider.dart';
import 'package:sugo_app/features/rb_cars/screens/symptom_screen.dart';
import 'package:sugo_app/features/rb_cars/widgets/delivery_option_selector.dart';

/// The basic-problem flow (2026-11-16): detection, the suggestion card, the
/// three options, and Shop Repair's delivery choice with its live fee.
void main() {
  group('BasicProblemDetector', () {
    test('an issue on the category list is basic whatever is typed', () {
      final BasicProblemMatch? match = BasicProblemDetector.check(
        issueCode: 'laptop_slow_or_freezing',
      );
      expect(match?.issueCode, 'laptop_slow_or_freezing');
    });

    test('a keyword in the picked issue label is basic', () {
      // "Will not turn on" is not on the category list, but its label
      // contains a keyword from the brief.
      expect(
        BasicProblemDetector.check(issueCode: 'laptop_wont_power_on'),
        isNotNull,
      );
    });

    test('a keyword in the client\'s own words is basic', () {
      expect(
        BasicProblemDetector.check(
          description: 'I think it just needs restart, sobrang mabagal',
        )?.keyword,
        isNotNull,
      );
      expect(
        BasicProblemDetector.check(description: 'Maluwag yung cable'),
        isNotNull,
      );
    });

    test('whole words only: "change" does not match "hang"', () {
      expect(
        BasicProblemDetector.check(description: 'I want to change the screen'),
        isNull,
      );
    });

    test('a cracked screen is not basic', () {
      expect(
        BasicProblemDetector.check(
          issueCode: 'phone_screen_cracked',
          description: 'Dropped it, the glass shattered.',
        ),
        isNull,
      );
    });

    test('nothing to go on is not basic', () {
      expect(BasicProblemDetector.check(), isNull);
    });
  });

  // The suggestion follows the symptom (2026-11-17): basic -> community,
  // needs the bench -> Shop Repair, otherwise the issue's own route.
  group('the suggestion follows the symptom', () {
    ClassificationResult of(String code, {bool damage = false}) =>
        ClassificationResult.evaluate(
          symptomCode: code,
          hasPhysicalDamage: damage,
        );

    test('a basic issue suggests the Technician Community', () {
      for (final String code in <String>[
        'laptop_slow_or_freezing', // on the category list
        'network_weak_signal', // "slow" in its label
        'network_no_internet', // already remote assist
      ]) {
        final ClassificationResult r = of(code);
        expect(r.servicePath, ServicePath.itCommunity, reason: code);
        expect(r.isBasic, isTrue, reason: code);
        expect(r.confidence, ClassificationConfidence.high, reason: code);
      }
    });

    test('visible damage outranks basic: Shop Repair', () {
      final ClassificationResult r = of(
        'laptop_slow_or_freezing',
        damage: true,
      );
      expect(r.servicePath, ServicePath.pickup);
      expect(r.isBasic, isFalse);
    });

    test('a shop issue stays Shop Repair, even on the basic list', () {
      // phone_battery_drain is on the category list; "Will not turn on" has
      // a basic keyword in its label. Both need the bench.
      for (final String code in <String>[
        'phone_battery_drain',
        'phone_wont_power_on',
        'network_router_dead',
      ]) {
        expect(of(code).servicePath, ServicePath.pickup, reason: code);
        expect(of(code).isBasic, isFalse, reason: code);
      }
    });

    test('"needs diagnosis" is still matched with a technician', () {
      // The 2026-11-15 fix: a dead laptop gets a technician, not advice -
      // even though its label sounds basic.
      for (final String code in <String>[
        'laptop_wont_power_on',
        'laptop_battery_not_charging',
        'appliance_no_power',
      ]) {
        expect(of(code).servicePath, ServicePath.homeService, reason: code);
        expect(of(code).isBasic, isFalse, reason: code);
      }
    });

    test('an ordinary home-service issue keeps Home Service', () {
      expect(of('laptop_overheating').servicePath, ServicePath.homeService);
      expect(of('laptop_overheating').isBasic, isFalse);
    });
  });

  group('JobDraft writes the delivery option only for Shop Repair', () {
    JobDraft draft() => JobDraft()
      ..deviceType = DeviceType.laptop
      ..problemSymptom = 'laptop_screen_broken';

    test('Shop Repair sends the choice', () {
      final JobDraft d = draft()
        ..classify()
        ..servicePathOverride = ServicePath.pickup
        ..deliveryOption = DeliveryOption.self;
      expect(d.toInsert(clientId: 'c')['delivery_option'], 'self');
    });

    test('a new Shop Repair post sends no choice - the booking asks', () {
      final JobDraft d = draft()
        ..classify()
        ..servicePathOverride = ServicePath.pickup;
      expect(d.deliveryOption, isNull);
      expect(d.toInsert(clientId: 'c').containsKey('delivery_option'), isFalse);
    });

    test('"Edit post" keeps the choice made when booking', () {
      final JobDraft d = JobDraft.fromJob(
        Job.fromJson(<String, dynamic>{
          'id': 'j',
          'client_id': 'c',
          'device_type': 'laptop',
          'problem_symptom': 'laptop_screen_broken',
          'has_physical_damage': true,
          'status': 'matched',
          'service_path': 'pickup',
          'delivery_option': 'self',
        }),
      );
      expect(d.toUpdate()['delivery_option'], 'self');
    });

    test('any other path sends null, as the database requires', () {
      final JobDraft d = draft()
        ..classify()
        ..servicePathOverride = ServicePath.homeService
        ..deliveryOption = DeliveryOption.self;
      expect(
        d.toInsert(clientId: 'c').containsKey('delivery_option'),
        isFalse,
        reason: 'Left out entirely, so posting works before the migration.',
      );
      expect(d.toUpdate()['delivery_option'], isNull);
      expect(d.toUpdate().containsKey('delivery_option'), isTrue);
    });

    test('the fee and distance are never sent by the app', () {
      final Map<String, dynamic> row =
          (draft()
                ..classify()
                ..servicePathOverride = ServicePath.pickup)
              .toUpdate();
      expect(row.containsKey('delivery_fee'), isFalse);
      expect(row.containsKey('distance_km'), isFalse);
    });

    test('a saved job reads its delivery back', () {
      final Job job = Job.fromJson(<String, dynamic>{
        'id': 'j',
        'client_id': 'c',
        'device_type': 'laptop',
        'problem_symptom': 'laptop_screen_broken',
        'status': 'confirmed',
        'service_path': 'pickup',
        'delivery_option': 'self',
        'distance_km': '4.20',
        'delivery_fee': 0,
      });
      expect(job.isSelfDropOff, isTrue);
      expect(job.distanceKm, 4.2);
      expect(job.deliveryFee, 0);
    });
  });

  group('the delivery choice', () {
    Widget host(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

    testWidgets('the fee updates live when switching', (
      WidgetTester tester,
    ) async {
      DeliveryOption value = DeliveryOption.delivery;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) =>
                DeliveryOptionSelector(
                  value: value,
                  distanceKm: 4.2,
                  onChanged: (DeliveryOption next) =>
                      setState(() => value = next),
                ),
          ),
        ),
      );

      // 4.2 km is billed as 5 km: ₱50 + ₱15 × 2.
      // Two trips since 2026-11-17: ₱80 a trip, collect and return.
      expect(find.text('₱160'), findsWidgets);
      expect(find.text('Pickup trip'), findsOneWidget);
      expect(find.text('Delivery trip'), findsOneWidget);
      expect(find.text('₱80'), findsNWidgets(2));
      expect(find.text('4.2 km → 5 km'), findsOneWidget);

      await tester.tap(find.text("I'll bring it / pick it up myself"));
      await tester.pumpAndSettle();
      expect(value, DeliveryOption.self);
      expect(find.text('4.2 km → 5 km'), findsNothing);
    });

    testWidgets('without a technician yet it shows the rule', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          DeliveryOptionSelector(
            value: DeliveryOption.delivery,
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.text('from ₱100'), findsOneWidget);
      expect(
        find.text('₱50 up to 3 km, then ₱15 per km - per trip, 2 trips'),
        findsOneWidget,
      );
    });

    testWidgets('each option is at least 48 dp tall', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          DeliveryOptionSelector(
            value: DeliveryOption.delivery,
            onChanged: (_) {},
          ),
        ),
      );
      for (final DeliveryOption option in DeliveryOption.values) {
        final Size size = tester.getSize(
          find
              .ancestor(
                of: find.text(option.label),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });
  });

  group('the symptom step', () {
    late JobPostingProvider posting;

    setUp(() {
      posting = JobPostingProvider()..selectCategory(DeviceCategory.laptop);
    });
    tearDown(() => posting.dispose());

    void screen(WidgetTester tester, Size size) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
    }

    testWidgets(
      'a basic problem suggests the community, and the client chooses',
      (WidgetTester tester) async {
        screen(tester, const Size(400, 1800));
        posting.selectSymptom('laptop_slow_or_freezing');
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: SymptomScreen(posting: posting),
          ),
        );
        await tester.pumpAndSettle();

        // In English, and agreeing with the badge: the community is the
        // suggestion and the first selection.
        expect(find.text('This looks like a basic problem.'), findsOneWidget);
        expect(find.text('Mukhang basic lang ito.'), findsNothing);
        expect(posting.draft.servicePath, ServicePath.itCommunity);
        expect(
          find.text('Technician Community selected - free'),
          findsOneWidget,
        );
        expect(find.text('Post to Technician Community'), findsOneWidget);
        expect(find.text('Home Service'), findsOneWidget);
        expect(find.text('Shop Repair'), findsOneWidget);

        // The client can still pick a technician...
        await tester.tap(find.text('Home Service'));
        await tester.pumpAndSettle();
        expect(posting.draft.servicePath, ServicePath.homeService);

        // ...and come back with one tap.
        await tester.tap(find.text('Try the community (free)'));
        await tester.pumpAndSettle();
        expect(posting.draft.servicePath, ServicePath.itCommunity);
      },
    );

    testWidgets('no basic card when a technician is suggested', (
      WidgetTester tester,
    ) async {
      screen(tester, const Size(400, 1800));
      // "Will not turn on" sounds basic, but it needs a diagnosis: Home
      // Service carries the badge, so the card would contradict it.
      posting.selectSymptom('laptop_wont_power_on');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SymptomScreen(posting: posting),
        ),
      );
      await tester.pumpAndSettle();

      expect(posting.draft.servicePath, ServicePath.homeService);
      expect(find.text('This looks like a basic problem.'), findsNothing);
    });

    // 2026-11-17: asked once, in the booking dialog, not while posting.
    testWidgets('Shop Repair no longer asks how the unit travels', (
      WidgetTester tester,
    ) async {
      screen(tester, const Size(400, 1800));
      posting.selectSymptom('laptop_screen_broken');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SymptomScreen(posting: posting),
        ),
      );
      await tester.pumpAndSettle();

      expect(posting.draft.servicePath, ServicePath.pickup);
      expect(find.byType(DeliveryOptionSelector), findsNothing);
      expect(find.text("I'll bring it / pick it up myself"), findsNothing);
      expect(
        find.text(
          "Repaired at the technician's shop. You choose drop-off or pickup "
          'when you book a technician.',
        ),
        findsOneWidget,
      );
      // Nothing chosen, so nothing is saved: the booking decides.
      expect(posting.draft.effectiveDeliveryOption, isNull);
    });

    testWidgets('fits a small phone at large text, card and Shop Repair on', (
      WidgetTester tester,
    ) async {
      screen(tester, const Size(320, 2400));
      posting
        ..selectSymptom('laptop_slow_or_freezing')
        ..overrideServicePath(ServicePath.pickup);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (BuildContext context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: SymptomScreen(posting: posting),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('This looks like a basic problem.'), findsOneWidget);
      expect(find.byType(DeliveryOptionSelector), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out in landscape without overflow', (
      WidgetTester tester,
    ) async {
      screen(tester, const Size(800, 380));
      posting
        ..selectSymptom('laptop_screen_broken')
        ..overrideServicePath(ServicePath.pickup);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SymptomScreen(posting: posting),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
