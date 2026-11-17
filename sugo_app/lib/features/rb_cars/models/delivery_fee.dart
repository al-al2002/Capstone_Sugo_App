import 'package:flutter/foundation.dart';

/// The shop pickup/delivery fee, worked out step by step (2026-11-16).
///
///   billed km = distance rounded UP to the next whole km
///   one trip, up to 3 km: PHP 50
///   one trip, beyond:     PHP 50 + PHP 15 for each km after the third
///   pickup and delivery:  2 trips (2026-11-17)
///
/// ## Why two trips
///
/// "Shop pickup/delivery" is two drives for the technician: to the client to
/// collect the unit, and back to them with it repaired. Until 2026-11-17 it
/// was charged as one, the same as a home visit; the user set it to twice
/// the trip fee. [oneWay] is one trip - what a home visit's travel fee still
/// is ([LaborPriceCatalog.travelFee]) - and [total] is the two.
///
/// THE ONE PLACE THE APP KNOWS THE RATES. Change them here, and in the
/// server's copy, `supabase/functions/_shared/delivery_fee.ts` - the server
/// calculates the fee actually saved on a job (from the technician's shop
/// location, which the app never sees before booking), and both are tested
/// on the same distances, so a mismatch fails a test.
@immutable
class DeliveryFee {
  const DeliveryFee._({
    required this.distanceKm,
    required this.billedKm,
    required this.extraKm,
  });

  /// Everything up to this many km costs [baseFee].
  static const int baseKm = 3;
  static const int baseFee = 50;
  static const int perKmFee = 15;

  /// Pickup and delivery: collecting the unit, and bringing it back.
  static const int trips = 2;

  /// The breakdown for [distanceKm]. "Bring it myself" is free and never
  /// needs this.
  factory DeliveryFee.calculate(double distanceKm) {
    final int billed = distanceKm <= 0 ? 0 : distanceKm.ceil();
    return DeliveryFee._(
      distanceKm: distanceKm,
      billedKm: billed,
      extraKm: billed > baseKm ? billed - baseKm : 0,
    );
  }

  /// The straight-line distance it was worked out from.
  final double distanceKm;

  /// Whole km charged: 3.2 km is 4 km.
  final int billedKm;

  /// Km beyond the first [baseKm], each charged [perKmFee].
  final int extraKm;

  int get extraFee => extraKm * perKmFee;

  /// One trip, in whole pesos. A home visit's travel fee.
  int get oneWay => baseFee + extraFee;

  /// Pickup and delivery, in whole pesos: [trips] of [oneWay]. The fee a
  /// shop repair with "Shop pickup/delivery" is charged.
  int get total => oneWay * trips;

  /// One trip's rate, e.g. "₱50 first 3 km + ₱15 × 2 km".
  String get breakdownLabel => extraKm == 0
      ? '₱$baseFee for up to $baseKm km'
      : '₱$baseFee first $baseKm km + ₱$perKmFee × $extraKm km';

  /// The two trips, e.g. "₱80 × 2 trips (pickup + return)".
  String get tripsLabel => '₱$oneWay × $trips trips (pickup + return)';

  /// The lowest pickup-and-delivery fee: two trips inside the base distance.
  static const int minimumTotal = baseFee * trips;

  /// The rule in words, for before a distance is known.
  static const String ruleLabel =
      '₱$baseFee up to $baseKm km, then ₱$perKmFee per km - per trip, '
      '$trips trips';
}
