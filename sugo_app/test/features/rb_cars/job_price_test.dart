import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_price.dart';

/// The price the booking screens show instead of "Any budget" (2026-11-17):
/// labor fee for the symptom, plus the travel or delivery fee.
void main() {
  Job job(Map<String, dynamic> extra) => Job.fromJson(<String, dynamic>{
    'id': 'j',
    'client_id': 'c',
    'device_type': 'laptop',
    'problem_symptom': 'laptop_input_dead',
    'status': 'confirmed',
    ...extra,
  });

  test('home visit: labor + travel fee for the quoted distance', () {
    final JobPrice price = JobPrice.forJob(
      job(<String, dynamic>{'service_path': 'home_service'}),
      homeDistanceKm: 16.2,
    );
    expect(price.labor, isNotNull);
    // 16.2 km bills as 17 km: ₱50 + ₱15 × 14 = ₱260.
    expect(price.distanceFee, 260);
    expect(price.distanceFeeLabel, 'Travel fee (16.2 km)');
    expect(price.total, isNotNull);
    expect(price.headline, price.total);
  });

  test('home visit without the distance yet: the labor fee alone', () {
    final JobPrice price = JobPrice.forJob(
      job(<String, dynamic>{'service_path': 'home_service'}),
    );
    expect(price.distanceFee, isNull);
    expect(price.total, isNull);
    expect(price.headline, price.labor!.fee);
  });

  test('shop delivery: the fee the server saved', () {
    final JobPrice price = JobPrice.forJob(
      job(<String, dynamic>{
        'service_path': 'pickup',
        'delivery_option': 'delivery',
        'distance_km': 4.2,
        'delivery_fee': 80,
      }),
    );
    expect(price.distanceFee, 80);
    expect(price.distanceFeeLabel, 'Pickup and delivery fee (4.2 km)');
    // Booked before the two-trip rule: one trip was charged, so it stays one
    // line - not split into two halves nobody paid.
    expect(price.distanceFeeLines, hasLength(1));
  });

  // The user's own example (2026-11-17): 16.2 km bills as 17 km, so one trip
  // is ₱50 + ₱15 × 14 = ₱260 - pickup ₱260 and delivery ₱260, ₱520 in all.
  test('pickup and delivery prints as its two trips', () {
    final JobPrice price = JobPrice.forJob(
      job(<String, dynamic>{
        'service_path': 'pickup',
        'delivery_option': 'delivery',
        'distance_km': 16.2,
        'delivery_fee': 520,
      }),
    );
    expect(price.distanceFee, 520);
    final List<({String label, int amount})> lines = price.distanceFeeLines!;
    expect(lines, hasLength(2));
    expect(lines[0].label, 'Pickup trip (16.2 km)');
    expect(lines[0].amount, 260);
    expect(lines[1].label, 'Delivery trip');
    expect(lines[1].amount, 260);
    expect(price.distanceFeePhrase, 'pickup ₱260 + delivery ₱260');
  });

  test('a home visit is one trip, one line', () {
    final List<({String label, int amount})> lines = JobPrice.feeLines(
      label: 'Travel fee',
      km: 16.2,
      fee: 260,
      pickupAndDelivery: false,
    );
    expect(lines.single.label, 'Travel fee (16.2 km)');
    expect(lines.single.amount, 260);
  });

  test('bring it myself: delivery is ₱0', () {
    final JobPrice price = JobPrice.forJob(
      job(<String, dynamic>{
        'service_path': 'pickup',
        'delivery_option': 'self',
      }),
    );
    expect(price.distanceFee, 0);
    expect(price.feeLabel, 'Delivery fee - bring it myself');
  });

  test('no catalogue price: an honest "to be confirmed"', () {
    final JobPrice price = JobPrice.forJob(
      job(<String, dynamic>{
        'problem_symptom': 'not_sure',
        'service_path': 'it_community',
      }),
    );
    expect(price.headline, 'Price to be confirmed');
  });
}
