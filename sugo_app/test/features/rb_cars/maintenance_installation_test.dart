import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/client/widgets/service_category_row.dart';
import 'package:sugo_app/features/rb_cars/config/service_offers.dart';
import 'package:sugo_app/features/rb_cars/models/device_category.dart';
import 'package:sugo_app/features/rb_cars/models/issue_catalog.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/labor_price_catalog.dart';
import 'package:sugo_app/features/rb_cars/providers/job_posting_provider.dart';
import 'package:sugo_app/features/rb_cars/screens/job_posting_screen.dart';
import 'package:sugo_app/features/rb_cars/screens/symptom_screen.dart';
import 'package:sugo_app/features/rb_cars/screens/technician_preferences_screen.dart';

/// Maintenance and installation in posting, with Davao prices (2026-11-16).
void main() {
  group('the catalogue', () {
    test('every issue has a price and a unique code', () {
      final Set<String> codes = <String>{};
      for (final IssueOption issue in IssueCatalog.all) {
        expect(
          codes.add(issue.code),
          isTrue,
          reason: 'duplicate ${issue.code}',
        );
        expect(
          LaborPriceCatalog.forJob(
            deviceType: issue.deviceType,
            symptomCode: issue.code,
          ),
          isNotNull,
          reason: '${issue.code} has no labor price',
        );
      }
    });

    test('the Davao prices are the researched ones', () {
      String fee(DeviceType device, String code) =>
          LaborPriceCatalog.forJob(deviceType: device, symptomCode: code)!.fee;

      expect(fee(DeviceType.appliance, 'appliance_aircon_cleaning'), '₱800');
      expect(
        fee(DeviceType.appliance, 'appliance_aircon_install_split'),
        '₱3,500',
      );
      expect(
        fee(DeviceType.appliance, 'appliance_aircon_install_window'),
        '₱1,500',
      );
      expect(fee(DeviceType.laptop, 'laptop_cleaning_tune_up'), '₱1,000');
      expect(fee(DeviceType.phone, 'phone_checkup'), '₱300');
    });

    test('a single price adds the travel fee; a per-camera one does not', () {
      final LaborPrice split = LaborPriceCatalog.forJob(
        deviceType: DeviceType.appliance,
        symptomCode: 'appliance_aircon_install_split',
      )!;
      expect(
        LaborPriceCatalog.estimatedTotal(labor: split, travelFee: 65),
        '₱3,565',
      );
    });

    test('maintenance and installation land on the right device card', () {
      expect(
        DeviceCategory.network.issues.map((IssueOption i) => i.code),
        contains('network_checkup'),
      );
      expect(
        DeviceCategory.cctv.issues.map((IssueOption i) => i.code),
        isNot(contains('network_checkup')),
      );
      final List<IssueOption> appliance = DeviceCategory.appliance.issues;
      expect(
        appliance.where((IssueOption i) => i.kind == IssueKind.installation),
        hasLength(4),
      );
    });

    test('only repairs ask about damage', () {
      expect(IssueKind.repair.asksAboutDamage, isTrue);
      expect(IssueKind.maintenance.asksAboutDamage, isFalse);
      expect(IssueKind.installation.asksAboutDamage, isFalse);
    });
  });

  group('the shared offers', () {
    test('every offer lands on real issues of its own kind and device', () {
      for (final ServiceOffer offer in <ServiceOffer>[
        ...ServiceOffers.maintenance,
        ...ServiceOffers.installation,
      ]) {
        expect(offer.issues, isNotEmpty, reason: offer.label);
        for (final IssueOption issue in offer.issues) {
          expect(issue.kind, offer.kind, reason: offer.label);
          expect(offer.category.owns(issue), isTrue, reason: offer.label);
        }
      }
    });

    test('price labels: one price, a shared per-unit price, or "From"', () {
      ServiceOffer named(List<ServiceOffer> list, String label) =>
          list.firstWhere((ServiceOffer o) => o.label == label);

      expect(
        named(ServiceOffers.maintenance, 'Laptop or PC tune-up').priceLabel,
        '₱1,000',
      );
      expect(
        named(ServiceOffers.maintenance, 'Appliance cleaning').priceLabel,
        'From ₱500',
      );
      expect(
        named(ServiceOffers.installation, 'CCTV cameras').priceLabel,
        '₱800/camera',
      );
      expect(ServiceOffers.startingPrice(IssueKind.maintenance), 'From ₱300');
      expect(ServiceOffers.startingPrice(IssueKind.installation), 'From ₱500');
    });
  });

  group('the posting draft', () {
    test('a cleaning drops a damage answer left over from a repair', () {
      final JobPostingProvider posting = JobPostingProvider();
      addTearDown(posting.dispose);
      posting.selectCategory(DeviceCategory.appliance);
      posting.selectSymptom('appliance_not_cooling');
      posting.setPhysicalDamage(true);

      posting.selectSymptom('appliance_aircon_cleaning');

      expect(posting.draft.hasPhysicalDamage, isFalse);
      expect(posting.draft.servicePath, ServicePath.homeService);
    });
  });

  Widget host(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

  void tallPhone(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.reset);
  }

  testWidgets('step 1: Maintenance opens the sheet and goes straight on', (
    WidgetTester tester,
  ) async {
    tallPhone(tester);
    await tester.pumpWidget(host(const JobPostingScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.text('Installation'), findsOneWidget);
    await tester.tap(find.text('Maintenance'));
    await tester.pumpAndSettle();

    expect(find.text('What needs maintenance?'), findsOneWidget);
    expect(find.text('₱1,000'), findsOneWidget);
    await tester.tap(find.text('Laptop or PC tune-up'));
    await tester.pumpAndSettle();

    // On to step 2, with the device and the tune-up already chosen.
    final TechnicianPreferencesScreen step2 = tester.widget(
      find.byType(TechnicianPreferencesScreen),
    );
    expect(step2.posting.deviceCategory, DeviceCategory.laptop);
    expect(step2.posting.draft.problemSymptom, 'laptop_cleaning_tune_up');
  });

  testWidgets('step 3: no damage question for a maintenance job', (
    WidgetTester tester,
  ) async {
    tallPhone(tester);
    final JobPostingProvider posting = JobPostingProvider()
      ..selectCategory(DeviceCategory.appliance)
      ..selectSymptom('appliance_aircon_cleaning');
    addTearDown(posting.dispose);

    await tester.pumpWidget(host(SymptomScreen(posting: posting)));
    await tester.pumpAndSettle();

    expect(find.text('Is there visible physical damage?'), findsNothing);
    expect(find.textContaining('Included'), findsOneWidget);
    expect(find.text('How do you want it done? Choose one:'), findsOneWidget);

    // The list is grouped once it opens.
    await tester.tap(find.text('Aircon cleaning').first);
    await tester.pumpAndSettle();
    expect(find.text('MAINTENANCE'), findsOneWidget);
    expect(find.text('INSTALLATION'), findsOneWidget);
    expect(find.text('TV wall mounting'), findsOneWidget);
  });

  testWidgets('the home screen tile lands on the exact problem too', (
    WidgetTester tester,
  ) async {
    tallPhone(tester);
    final List<(DeviceCategory?, String?)> resolved =
        <(DeviceCategory?, String?)>[];

    await tester.pumpWidget(
      host(
        Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => resolveHomeCategory(
                context,
                HomeServiceCategory.installation,
                onResolved: (DeviceCategory? d, String? code) =>
                    resolved.add((d, code)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wi-Fi or router'));
    await tester.pumpAndSettle();

    expect(resolved.single, (DeviceCategory.network, 'network_new_install'));
  });
}
