import 'package:flutter/foundation.dart';

import 'delivery_fee.dart';
import 'job.dart';
import 'job_enums.dart';
import 'labor_price_catalog.dart';

/// What a booking costs, as the booking screens show it (2026-11-17).
///
/// Replaced "Any budget" on the bookings list, the booking detail and its
/// summary. The budget range was the client's own guess at posting; this is
/// the price they were actually quoted:
///
/// * **labor fee** - from `LaborPriceCatalog`, for the symptom;
/// * **distance fee** - for a shop repair, the delivery fee the server saved
///   when the request was sent (₱0 when they bring it themselves); for a home
///   visit, the travel fee for the distance the matcher measured, the same
///   number the client saw before sending;
/// * **urgent fee** - since 2026-11-17, 20% of the labor when the job is
///   Urgent (the user's rule: ₱600 labor -> ₱120 urgent fee). Worked out here
///   like the labor fee, from the job's own `urgency`, so nothing new is
///   stored and the client and the technician always see the same figure;
/// * **estimated total** - labor, urgent fee and distance fee together, when
///   all are known.
///
/// One helper for every screen, so the list and the detail never disagree.
@immutable
class JobPrice {
  const JobPrice._({
    required this.labor,
    required this.feeLabel,
    required this.distanceKm,
    required this.distanceFee,
    this.isUrgent = false,
    this.pickupAndDelivery = false,
  });

  /// [homeDistanceKm] is the matcher's distance to the technician for a home
  /// visit, from the accepted match. Shop repairs ignore it - their distance
  /// is saved on the job.
  factory JobPrice.forJob(Job job, {double? homeDistanceKm}) => JobPrice.of(
    deviceType: job.deviceType,
    symptomCode: job.problemSymptom,
    servicePath: job.servicePath,
    deliveryOption: job.deliveryOption,
    homeDistanceKm: homeDistanceKm,
    shopDistanceKm: job.distanceKm,
    savedDeliveryFee: job.deliveryFee,
    urgency: job.urgency,
  );

  /// The same price for a technician's OFFER, before they can read the job
  /// (2026-11-17). [distanceKm] is the matcher's distance to them. A shop
  /// repair uses the fee the server put on the offer when the client sent
  /// it, and falls back to working it out from [distanceKm] for an offer
  /// sent before that existed.
  factory JobPrice.forSnapshot(JobSnapshot job, {double? distanceKm}) =>
      JobPrice.of(
        deviceType: job.deviceType,
        symptomCode: job.problemSymptom,
        servicePath: job.servicePath,
        deliveryOption: job.deliveryOption,
        homeDistanceKm: distanceKm,
        shopDistanceKm: job.distanceKm ?? distanceKm,
        savedDeliveryFee:
            job.deliveryFee ??
            (job.deliveryOption == DeliveryOption.delivery && distanceKm != null
                // Two trips, like the server's saved fee (2026-11-17).
                ? DeliveryFee.calculate(distanceKm).total
                : null),
        urgency: job.urgency,
      );

  factory JobPrice.of({
    required DeviceType deviceType,
    required String symptomCode,
    required ServicePath? servicePath,
    DeliveryOption? deliveryOption,
    double? homeDistanceKm,
    double? shopDistanceKm,
    int? savedDeliveryFee,
    Urgency urgency = Urgency.canWait,
  }) {
    final LaborPrice? labor = LaborPriceCatalog.forJob(
      deviceType: deviceType,
      symptomCode: symptomCode,
    );
    final bool urgent = urgency == Urgency.needToday;

    return switch (servicePath) {
      ServicePath.pickup => JobPrice._(
        labor: labor,
        feeLabel: deliveryOption == DeliveryOption.self
            ? 'Delivery fee - bring it myself'
            : 'Pickup and delivery fee',
        distanceKm: shopDistanceKm,
        // Saved by the server on select; null on shop jobs booked before it.
        distanceFee:
            savedDeliveryFee ??
            (deliveryOption == DeliveryOption.self ? 0 : null),
        isUrgent: urgent,
        pickupAndDelivery: deliveryOption == DeliveryOption.delivery,
      ),
      ServicePath.homeService => JobPrice._(
        labor: labor,
        feeLabel: 'Travel fee',
        distanceKm: homeDistanceKm,
        distanceFee: LaborPriceCatalog.travelFee(homeDistanceKm),
        isUrgent: urgent,
      ),
      _ => JobPrice._(
        labor: labor,
        feeLabel: null,
        distanceKm: null,
        distanceFee: null,
        isUrgent: urgent,
      ),
    };
  }

  /// Null when the symptom has no catalogue price ("I am not sure").
  final LaborPrice? labor;

  /// "Travel fee", "Pickup and delivery fee", ... or null when there is none.
  final String? feeLabel;
  final double? distanceKm;
  final int? distanceFee;

  /// The job was posted as Urgent: the urgent fee applies.
  final bool isUrgent;

  /// A shop repair the technician collects and brings back: two trips.
  final bool pickupAndDelivery;

  /// The distance fee as the lines to print (2026-11-17) - see [feeLines].
  /// Null when there is no fee yet.
  List<({String label, int amount})>? get distanceFeeLines {
    final String? label = feeLabel;
    final int? fee = distanceFee;
    if (label == null || fee == null) return null;
    return feeLines(
      label: label,
      km: distanceKm,
      fee: fee,
      pickupAndDelivery: pickupAndDelivery,
    );
  }

  /// [fee] as the lines a price card prints.
  ///
  /// A pickup and delivery is two trips, so it prints as two - the user's own
  /// example, "pickup ₱260 and delivery ₱260":
  ///
  ///     Pickup trip (16.2 km)   ₱260
  ///     Delivery trip           ₱260
  ///
  /// Everything else is one line, "Travel fee (16.2 km) ₱260". A job booked
  /// before the two-trip rule was charged one trip: its fee is not twice the
  /// trip fee, so it stays one line rather than being split into two halves
  /// that nobody was charged.
  static List<({String label, int amount})> feeLines({
    required String label,
    required double? km,
    required int fee,
    required bool pickupAndDelivery,
  }) {
    final String kmText = km == null ? '' : ' (${km.toStringAsFixed(1)} km)';
    if (pickupAndDelivery && km != null) {
      final int trip = DeliveryFee.calculate(km).oneWay;
      if (fee == trip * DeliveryFee.trips) {
        return <({String label, int amount})>[
          (label: 'Pickup trip$kmText', amount: trip),
          (label: 'Delivery trip', amount: trip),
        ];
      }
    }
    return <({String label, int amount})>[
      (label: '$label$kmText', amount: fee),
    ];
  }

  /// One phrase for a summary line: "pickup ₱260 + delivery ₱260", or the
  /// fee's own name, e.g. "travel fee ₱260". Null when there is no fee.
  String? get distanceFeePhrase {
    final List<({String label, int amount})>? lines = distanceFeeLines;
    if (lines == null) return null;
    if (lines.length == 2) {
      return 'pickup ₱${lines[0].amount} + delivery ₱${lines[1].amount}';
    }
    return '${feeLabel!.split(' - ').first.toLowerCase()} ₱${lines.single.amount}';
  }

  bool get hasDistanceFee => feeLabel != null && distanceFee != null;

  /// 20% of the labor in pesos, for an urgent job with a flat labor fee.
  int? get urgentFee =>
      isUrgent && labor != null ? LaborPriceCatalog.urgentFee(labor!) : null;

  /// Whether to show an urgent-fee line at all.
  bool get hasUrgentFee => isUrgent && labor != null;

  /// "₱120", or "+20% of labor" when the labor is per unit.
  String? get urgentFeeText => !hasUrgentFee
      ? null
      : urgentFee == null
      ? '+20% of labor'
      : '₱$urgentFee';

  /// The line's label, with the rule in it so nobody wonders where it came
  /// from: "Urgent fee (20%)".
  static const String urgentFeeLabel = 'Urgent fee (20%)';

  /// "Travel fee (16.2 km)".
  String? get distanceFeeLabel => feeLabel == null
      ? null
      : distanceKm == null
      ? feeLabel
      : '$feeLabel (${distanceKm!.toStringAsFixed(1)} km)';

  /// Labor, the urgent fee and the distance fee, or null until all are known.
  String? get total => labor == null || distanceFee == null
      ? null
      : LaborPriceCatalog.estimatedTotal(
          labor: labor!,
          travelFee: distanceFee!,
          urgentFee: urgentFee ?? 0,
        );

  /// Labor with the urgent fee on top when it applies: "₱720".
  String? get laborWithUrgent {
    if (labor == null) return null;
    final int? amount = LaborPriceCatalog.laborAmount(labor!);
    final int? urgent = urgentFee;
    if (amount == null || urgent == null) return labor!.fee;
    return '₱${amount + urgent}';
  }

  /// The one figure for a list card: the total when known, else the labor
  /// fee (with any urgent fee), else an honest "to be confirmed".
  String get headline => total ?? laborWithUrgent ?? 'Price to be confirmed';
}
