import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/rb_cars/models/delivery_fee.dart';
import 'package:sugo_app/features/rb_cars/models/labor_price_catalog.dart';

/// The shop pickup/delivery fee (2026-11-16).
///
///   billed km = distance rounded up to a whole km
///   one trip: up to 3 km ₱50;  beyond: ₱50 + ₱15 per km after the third
///   pickup and delivery: two trips (2026-11-17)
///
/// The server's copy (`supabase/functions/_shared/delivery_fee.ts`) is pinned
/// on the same cases by `delivery_fee.test.ts`, so the fee a client is shown
/// is the fee saved on their job.
void main() {
  group('one trip: the five distances from the brief', () {
    final Map<double, int> cases = <double, int>{
      1: 50,
      3: 50,
      4: 65,
      5: 80,
      8: 125,
    };

    cases.forEach((double km, int fee) {
      test('${km.toInt()} km costs ₱$fee a trip', () {
        expect(DeliveryFee.calculate(km).oneWay, fee);
      });
    });
  });

  // 2026-11-17: pickup and delivery is two trips - collect, then return.
  group('pickup and delivery: two trips', () {
    final Map<double, int> cases = <double, int>{
      1: 100,
      3: 100,
      4: 130,
      5: 160,
      8: 250,
    };

    cases.forEach((double km, int fee) {
      test('${km.toInt()} km costs ₱$fee', () {
        expect(DeliveryFee.calculate(km).total, fee);
        expect(
          DeliveryFee.calculate(km).total,
          2 * DeliveryFee.calculate(km).oneWay,
        );
      });
    });

    test('the breakdown names both trips', () {
      expect(
        DeliveryFee.calculate(5).tripsLabel,
        '₱80 × 2 trips (pickup + return)',
      );
      expect(DeliveryFee.minimumTotal, 100);
    });
  });

  group('rounding up to the next whole km', () {
    test('0.4 km is billed as 1 km', () {
      expect(DeliveryFee.calculate(0.4).billedKm, 1);
      expect(DeliveryFee.calculate(0.4).oneWay, 50);
    });

    test('exactly 3 km stays inside the base fee', () {
      expect(DeliveryFee.calculate(3.0).oneWay, 50);
    });

    test('3.01 km is billed as 4 km', () {
      final DeliveryFee fee = DeliveryFee.calculate(3.01);
      expect(fee.billedKm, 4);
      expect(fee.extraKm, 1);
      expect(fee.oneWay, 65);
    });

    test('7.2 km is billed as 8 km', () {
      expect(DeliveryFee.calculate(7.2).oneWay, 125);
    });
  });

  group('the breakdown the client reads', () {
    test('inside the base distance names the flat fee', () {
      expect(DeliveryFee.calculate(2).breakdownLabel, '₱50 for up to 3 km');
    });

    test('beyond it shows base plus the extra km', () {
      final DeliveryFee fee = DeliveryFee.calculate(5);
      expect(fee.breakdownLabel, '₱50 first 3 km + ₱15 × 2 km');
      expect(fee.extraFee, 30);
    });
  });

  test('a home visit\'s travel fee is ONE trip of the same rule', () {
    for (final double km in <double>[1, 3, 3.5, 4, 5, 8, 12.3]) {
      expect(
        LaborPriceCatalog.travelFee(km),
        DeliveryFee.calculate(km).oneWay,
        reason: 'travelFee($km) drifted from DeliveryFee',
      );
    }
    expect(LaborPriceCatalog.travelFee(null), isNull);
  });
}
