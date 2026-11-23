import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/onboarding/controllers/technician_registration_controller.dart';
import 'package:sugo_app/features/onboarding/models/client_onboarding_models.dart';
import 'package:sugo_app/features/onboarding/models/registration_status.dart';
import 'package:sugo_app/features/onboarding/models/travel_conditions.dart';
import 'package:sugo_app/features/onboarding/services/geocoding_service.dart';
import 'package:sugo_app/features/rb_cars/services/rb_cars_service.dart';
import 'package:sugo_app/features/onboarding/services/identity_verification_service.dart';
import 'package:sugo_app/features/onboarding/services/technician_registration_service.dart';
import 'package:sugo_app/features/onboarding/widgets/location_pin_step.dart';
import 'package:sugo_app/features/onboarding/widgets/work_type_step.dart';

/// The technician's work type at registration (2026-11-17): Home Service,
/// Shop Repair or both, what each involves, and the shop's pin when Shop
/// Repair is chosen. Matching only offers a technician jobs of a kind they
/// take (migration 20261117000007).
void main() {
  const GeoPlace shop = GeoPlace(
    latitude: 7.0731,
    longitude: 125.6128,
    addressText: 'Matina, Davao City',
  );

  group('the flow', () {
    test('the step sits after the documents and before the location', () {
      const List<OnboardingStepId> flow = OnboardingStepId.technicianFlow;
      final int at = flow.indexOf(OnboardingStepId.workType);
      expect(at, greaterThan(flow.indexOf(OnboardingStepId.documents)));
      expect(at, lessThan(flow.indexOf(OnboardingStepId.location)));
      expect(
        OnboardingStepId.clientFlow,
        isNot(contains(OnboardingStepId.workType)),
      );
      expect(OnboardingStepId.fromWire('work_type'), OnboardingStepId.workType);
    });
  });

  group('the controller', () {
    TechnicianRegistrationController controller() =>
        TechnicianRegistrationController(
          service: _FakeService(),
          identityService: _FakeIdentity(),
        );

    test('nothing is chosen until the technician chooses', () {
      final TechnicianRegistrationController c = controller();
      addTearDown(c.dispose);
      expect(c.homeService, isFalse);
      expect(c.shopRepair, isFalse);
      expect(c.hasWorkType, isFalse);
      expect(c.workTypeLabel, 'Not chosen');
    });

    test('Home Service alone is enough', () {
      final TechnicianRegistrationController c = controller()
        ..setHomeService(true);
      addTearDown(c.dispose);
      expect(c.hasWorkType, isTrue);
      expect(c.workTypeLabel, 'Home Service');
    });

    test('Shop Repair needs the shop pinned', () {
      final TechnicianRegistrationController c = controller()
        ..setShopRepair(true);
      addTearDown(c.dispose);
      expect(c.hasWorkType, isFalse, reason: 'no shop yet');
      c.setShopPlace(shop);
      expect(c.hasWorkType, isTrue);
      expect(c.workTypeLabel, 'Shop Repair');
    });

    test('both is allowed, and still needs the shop', () {
      final TechnicianRegistrationController c = controller()
        ..setHomeService(true)
        ..setShopRepair(true);
      addTearDown(c.dispose);
      expect(c.hasWorkType, isFalse);
      c.setShopPlace(shop);
      expect(c.hasWorkType, isTrue);
      expect(c.workTypeLabel, 'Home Service and Shop Repair');
    });

    test('Continue also needs both travel answers (rain and traffic)', () {
      final TechnicianRegistrationController c = controller()
        ..setHomeService(true);
      addTearDown(c.dispose);
      expect(c.hasWorkType, isTrue);
      expect(c.canLeaveWorkTypeStep, isFalse, reason: 'nothing answered');
      expect(c.travelConditionsLabel, 'Rain and traffic not answered');

      c.setRainTravel(RainTravel.any);
      expect(c.canLeaveWorkTypeStep, isFalse, reason: 'traffic unanswered');

      c.setTrafficTravel(TrafficTravel.avoids);
      expect(c.canLeaveWorkTypeStep, isTrue);
      expect(
        c.travelConditionsLabel,
        'Even in heavy rain · Avoids heavy traffic',
      );
    });

    test('the answers map to the database values the matcher reads', () {
      expect(RainTravel.any.wire, 'any');
      expect(RainTravel.notHeavy.wire, 'not_heavy');
      expect(RainTravel.never.wire, 'never');
      expect(RainTravel.fromWire('not_heavy'), RainTravel.notHeavy);
      expect(RainTravel.fromWire(null), isNull, reason: 'not answered');
      expect(TrafficTravel.fromWire(true), TrafficTravel.goes);
      expect(TrafficTravel.fromWire(false), TrafficTravel.avoids);
      expect(TrafficTravel.fromWire(null), isNull, reason: 'not answered');
    });
  });

  group('the step', () {
    Future<void> show(
      WidgetTester tester, {
      bool home = false,
      bool shopRepair = false,
      Size size = const Size(400, 2200),
      double scale = 1,
      ValueChanged<bool>? onHome,
      ValueChanged<bool>? onShop,
      RainTravel? rain,
      TrafficTravel? traffic,
      ValueChanged<RainTravel>? onRain,
      ValueChanged<TrafficTravel>? onTraffic,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: WorkTypeStep(
                  homeService: home,
                  shopRepair: shopRepair,
                  onHomeServiceChanged: onHome ?? (_) {},
                  onShopRepairChanged: onShop ?? (_) {},
                  shopPlace: null,
                  onShopPlaceChanged: (_) {},
                  shopName: '',
                  onShopNameChanged: (_) {},
                  rainTravel: rain,
                  trafficTravel: traffic,
                  onRainTravelChanged: onRain ?? (_) {},
                  onTrafficTravelChanged: onTraffic ?? (_) {},
                  autoLocate: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says what each kind of work involves', (
      WidgetTester tester,
    ) async {
      await show(tester);
      expect(find.text('What work do you take?'), findsOneWidget);
      expect(find.text('Home Service'), findsOneWidget);
      expect(find.text('You go to the client'), findsOneWidget);
      expect(
        find.text("Repair, clean or install at the client's home or office."),
        findsOneWidget,
      );
      expect(find.text('Shop Repair'), findsOneWidget);
      expect(find.text('The unit comes to your shop'), findsOneWidget);
      expect(
        find.text('Clients drop it off, or you collect it and bring it back.'),
        findsOneWidget,
      );
      expect(find.text('Choose at least one to continue.'), findsOneWidget);
      // No shop map until Shop Repair is chosen.
      expect(find.byType(LocationPinStep), findsNothing);
    });

    testWidgets('tapping a card toggles it, and both can be on', (
      WidgetTester tester,
    ) async {
      bool? home;
      bool? shopRepair;
      await show(
        tester,
        onHome: (bool v) => home = v,
        onShop: (bool v) => shopRepair = v,
      );
      await tester.tap(find.text('Home Service'));
      await tester.tap(find.text('Shop Repair'));
      expect(home, isTrue);
      expect(shopRepair, isTrue);
    });

    testWidgets('Shop Repair opens the shop name and its map', (
      WidgetTester tester,
    ) async {
      await show(tester, home: true, shopRepair: true);
      expect(
        find.text('You will be offered both kinds of job.'),
        findsOneWidget,
      );
      expect(find.text('Shop name (optional)'), findsOneWidget);
      expect(find.byType(LocationPinStep), findsOneWidget);
      expect(find.text('Pin your shop'), findsOneWidget);
      expect(find.text('Search for an address or landmark'), findsOneWidget);
      expect(find.text('Use my current location'), findsOneWidget);
    });

    testWidgets('asks about rain and heavy traffic, nothing preselected', (
      WidgetTester tester,
    ) async {
      RainTravel? rain;
      TrafficTravel? traffic;
      await show(
        tester,
        home: true,
        onRain: (RainTravel v) => rain = v,
        onTraffic: (TrafficTravel v) => traffic = v,
      );
      expect(find.text('Travelling to clients'), findsOneWidget);
      expect(
        find.text('Will you still go to a client when it is raining?'),
        findsOneWidget,
      );
      expect(find.text('Yes, even in heavy rain or a storm'), findsOneWidget);
      expect(find.text('Yes, but not in heavy rain or a storm'), findsOneWidget);
      expect(find.text('No, I do not travel in the rain'), findsOneWidget);
      expect(find.text('Will you still go when traffic is heavy?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('rain-not_heavy')));
      await tester.tap(find.byKey(const ValueKey<String>('traffic-true')));
      expect(rain, RainTravel.notHeavy);
      expect(traffic, TrafficTravel.goes);
    });

    testWidgets('fits a small phone at large text, map open', (
      WidgetTester tester,
    ) async {
      await show(
        tester,
        shopRepair: true,
        size: const Size(320, 3000),
        scale: 1.3,
      );
      expect(
        find.text('You will be offered Shop Repair jobs only.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the map', _autoLocateGroup);
}

/// The map finds the user on its own (2026-11-17). In a test there is no
/// location at all, which is exactly the case to prove: the automatic try
/// fails quietly - no error, no crash - and search and the button remain.
void _autoLocateGroup() {
  Future<void> open(
    WidgetTester tester,
    _FakeGeocoding geocoding,
    ValueChanged<GeoPlace> onPlaced,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: LocationPinStep(
              place: null,
              onPlaceChanged: onPlaced,
              geocoding: geocoding,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('opening with nothing pinned finds the user on its own', (
    WidgetTester tester,
  ) async {
    GeoPlace? placed;
    final _FakeGeocoding geocoding = _FakeGeocoding(
      found: const GeoPlace(
        latitude: 7.0652,
        longitude: 125.6081,
        addressText: 'Bajada, Davao City',
      ),
    );
    await open(tester, geocoding, (GeoPlace p) => placed = p);
    expect(geocoding.asked, 1, reason: 'asked once, without a tap');
    expect(placed?.addressText, 'Bajada, Davao City');
  });

  testWidgets('an automatic fix that cannot happen fails quietly', (
    WidgetTester tester,
  ) async {
    GeoPlace? placed;
    final _FakeGeocoding geocoding = _FakeGeocoding();
    await open(tester, geocoding, (GeoPlace p) => placed = p);
    expect(geocoding.asked, 1);
    expect(placed, isNull);
    // Not the user's doing, so not shown as an error...
    expect(find.byType(SnackBar), findsNothing);
    // ...and the other two ways are still there.
    expect(find.text('Use my current location'), findsOneWidget);
    expect(find.text('Search for an address or landmark'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeGeocoding implements GeocodingService {
  _FakeGeocoding({this.found});

  final GeoPlace? found;
  int asked = 0;

  @override
  Future<GeoPlace> currentLocation() async {
    asked++;
    final GeoPlace? place = found;
    if (place == null) {
      throw const RbCarsFailure('Location access was declined.');
    }
    return place;
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeService implements TechnicianRegistrationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIdentity implements IdentityVerificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
