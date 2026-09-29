import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Where a transported job currently is in its journey.
///
/// Mirrors the `job_tracking.stage` check constraint. Order matters: the
/// timeline on the tracking screen is drawn from [index], so a stage is
/// "reached" when the current stage's index is at least its own.
enum TrackingStage {
  headingToPickup(
    'heading_to_pickup',
    'On the way to you',
    'The technician is travelling to collect your appliance.',
    Icons.directions_car_rounded,
    showsMap: true,
  ),
  collected(
    'collected',
    'Collected',
    'Your appliance has been picked up.',
    Icons.inventory_2_rounded,
    showsMap: true,
  ),
  returningToShop(
    'returning_to_shop',
    'Heading to the shop',
    'Your appliance is on its way to the workshop.',
    Icons.local_shipping_rounded,
    showsMap: true,
  ),
  inRepair(
    'in_repair',
    'Being repaired',
    'Work is underway at the workshop.',
    Icons.build_circle_rounded,
    // No travel, so no map: a stationary pin for hours would look broken.
    showsMap: false,
  ),
  outForDelivery(
    'out_for_delivery',
    'Out for delivery',
    'Repaired and on the way back to you.',
    Icons.delivery_dining_rounded,
    showsMap: true,
  ),
  readyForCollection(
    'ready_for_collection',
    'Ready for collection',
    'Repaired and waiting for you at the workshop.',
    Icons.store_mall_directory_rounded,
    // Nothing is travelling - it is on a shelf. A live map here would show a
    // stationary pin over the shop for hours, which reads as a stalled
    // technician rather than as a finished repair.
    showsMap: false,
  ),
  delivered(
    'delivered',
    'Delivered',
    'Your appliance is back with you.',
    Icons.check_circle_rounded,
    showsMap: false,
  );

  const TrackingStage(
    this.wire,
    this.label,
    this.blurb,
    this.icon, {
    required this.showsMap,
  });

  final String wire;
  final String label;
  final String blurb;
  final IconData icon;

  /// Whether this stage involves travel worth putting on a map.
  final bool showsMap;

  static TrackingStage fromWire(String? value) {
    for (final TrackingStage stage in TrackingStage.values) {
      if (stage.wire == value) return stage;
    }
    return TrackingStage.headingToPickup;
  }

  /// True while the appliance is travelling *towards the shop*.
  bool get isInboundLeg =>
      this == TrackingStage.headingToPickup ||
      this == TrackingStage.collected ||
      this == TrackingStage.returningToShop;

  /// True while it is travelling *back to the client*.
  ///
  /// Deliberately excludes [readyForCollection]: that is the client's own trip,
  /// which SUGO neither tracks nor estimates.
  bool get isOutboundLeg => this == TrackingStage.outForDelivery;

  /// True once the repair is done and the unit is waiting at the shop.
  bool get isAwaitingCollection => this == TrackingStage.readyForCollection;

  /// True at the one stage where the client is asked how they want the unit
  /// back — delivered, or collected from the workshop.
  ///
  /// ## Why only here
  ///
  /// The question used to be asked from the moment a technician took the job,
  /// which is before anyone knows whether there is anything to bring back.
  /// It is a decision about a finished repair, and asking for it while the
  /// van is still on its way to collect the unit invites an answer given
  /// without the one fact that matters.
  ///
  /// Not [readyForCollection] either, which would be the literal reading of
  /// "once the repair is done": by then the unit is on the shop shelf, and
  /// `set_return_method` refuses a switch back to delivery from there. So the
  /// window is the bench - the repair is in hand, the technician has not
  /// moved it anywhere yet, and either answer is still possible.
  bool get asksReturnChoice => this == TrackingStage.inRepair;

  bool get isFinished => this == TrackingStage.delivered;

  /// The stage's colour. It is printed as *text* ("Stage 3 of 5") and as the
  /// icon on a pale wash, so the orange stages use the text orange: the
  /// bright one is 2.1:1 on white.
  Color get color => switch (this) {
    TrackingStage.delivered => AppColors.success,
    TrackingStage.inRepair => AppColors.accentDark,
    TrackingStage.readyForCollection => AppColors.accentDark,
    _ => AppColors.primary,
  };

  /// The stages a technician may move to from here.
  ///
  /// Was `values[index + 1]` - a straight walk through the enum. That stopped
  /// being true when `in_repair` gained a second exit: the client can collect
  /// the unit themselves instead of waiting for it to be delivered. Ordinal
  /// order cannot express a branch, so the transitions are written out.
  ///
  /// Both branches converge on [delivered], so nothing downstream needs to know
  /// which route was taken.
  List<TrackingStage> get nextOptions => switch (this) {
    TrackingStage.headingToPickup => const <TrackingStage>[
      TrackingStage.collected,
    ],
    TrackingStage.collected => const <TrackingStage>[
      TrackingStage.returningToShop,
    ],
    TrackingStage.returningToShop => const <TrackingStage>[
      TrackingStage.inRepair,
    ],
    // The branch: deliver it, or hold it for the client.
    TrackingStage.inRepair => const <TrackingStage>[
      TrackingStage.outForDelivery,
      TrackingStage.readyForCollection,
    ],
    TrackingStage.outForDelivery => const <TrackingStage>[
      TrackingStage.delivered,
    ],
    TrackingStage.readyForCollection => const <TrackingStage>[
      TrackingStage.delivered,
    ],
    TrackingStage.delivered => const <TrackingStage>[],
  };

  /// The single next stage, or null when there is none - or when there is a
  /// choice to make. A caller that gets null here must check [nextOptions]
  /// before concluding the journey is over.
  TrackingStage? get next =>
      nextOptions.length == 1 ? nextOptions.single : null;

  /// The stages to draw on the timeline for a journey ending this way.
  ///
  /// The two branches are the same length, so the timeline does not change
  /// shape when the choice is made. Before it is made the delivery route is
  /// shown, because that is what happens unless someone says otherwise.
  static List<TrackingStage> timelineFor(TrackingStage current) {
    return <TrackingStage>[
      TrackingStage.headingToPickup,
      TrackingStage.collected,
      TrackingStage.returningToShop,
      TrackingStage.inRepair,
      current == TrackingStage.readyForCollection
          ? TrackingStage.readyForCollection
          : TrackingStage.outForDelivery,
      TrackingStage.delivered,
    ];
  }
}

/// One `job_tracking` row: where the job is right now.
class JobTracking {
  const JobTracking({
    required this.id,
    required this.jobId,
    required this.technicianId,
    required this.stage,
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.heading,
    this.note,
    this.startedAt,
    this.updatedAt,
    this.expectedArrivalAt,
    this.projectedArrivalAt,
    this.delayMinutes,
    this.delayReason,
    this.etaSampledAt,
  });

  factory JobTracking.fromJson(Map<String, dynamic> json) {
    double? asDouble(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    DateTime? asDate(Object? v) =>
        v is String ? DateTime.tryParse(v)?.toLocal() : null;

    return JobTracking(
      id: json['id'] as String,
      jobId: json['job_id'] as String,
      technicianId: json['technician_id'] as String,
      stage: TrackingStage.fromWire(json['stage'] as String?),
      latitude: asDouble(json['latitude']),
      longitude: asDouble(json['longitude']),
      accuracyM: asDouble(json['accuracy_m']),
      heading: asDouble(json['heading']),
      note: json['note'] as String?,
      startedAt: asDate(json['started_at']),
      updatedAt: asDate(json['updated_at']),
      expectedArrivalAt: asDate(json['expected_arrival_at']),
      projectedArrivalAt: asDate(json['projected_arrival_at']),
      delayMinutes: asDouble(json['delay_minutes']),
      delayReason: json['delay_reason'] as String?,
      etaSampledAt: asDate(json['eta_sampled_at']),
    );
  }

  final String id;
  final String jobId;
  final String technicianId;
  final TrackingStage stage;
  final double? latitude;
  final double? longitude;
  final double? accuracyM;
  final double? heading;
  final String? note;
  final DateTime? startedAt;
  final DateTime? updatedAt;

  /// The promise: arrival as first estimated when this leg began. Frozen, so
  /// lateness stays measurable - see the `tracking-eta` function.
  final DateTime? expectedArrivalAt;

  /// Arrival as currently estimated.
  final DateTime? projectedArrivalAt;

  /// Minutes behind the promise. Zero or negative means on time or early.
  final double? delayMinutes;

  /// `traffic` | `weather` | `both`, or null when the delay could not be
  /// attributed. Null is meaningful: the technician may simply be running
  /// behind, and blaming traffic without evidence invents an excuse for them.
  final String? delayReason;

  final DateTime? etaSampledAt;

  bool get hasPosition => latitude != null && longitude != null;

  /// Mirrors `DELAY_THRESHOLD_MINUTES` in the `tracking-eta` edge function.
  ///
  /// The server decides what counts as late - this copy exists so the UI can
  /// filter without a round trip. Change one and change the other.
  static const double delayThresholdMinutes = 10;

  bool get isDelayed => (delayMinutes ?? 0) >= delayThresholdMinutes;

  /// e.g. `about 15 minutes behind`. Rounded to 5 minutes, because the estimate
  /// is straight-line distance over a sampled speed and printing "17 minutes"
  /// would claim a precision the method does not have.
  String? get delayLabel {
    final double? minutes = delayMinutes;
    if (minutes == null || !isDelayed) return null;
    final int rounded = ((minutes / 5).round() * 5).clamp(5, 999).toInt();
    return 'about $rounded minutes behind';
  }

  /// Plain-language cause, or null when none was established.
  String? get delayReasonLabel => switch (delayReason) {
    'traffic' => 'heavy traffic',
    'weather' => 'bad weather',
    'both' => 'traffic and weather',
    _ => null,
  };

  /// How stale the last fix is. A position from twenty minutes ago should not
  /// be presented as "live", so the UI degrades the wording instead of quietly
  /// showing an old dot.
  Duration? get age {
    final DateTime? at = updatedAt;
    return at == null ? null : DateTime.now().difference(at);
  }

  bool get isLive {
    final Duration? since = age;
    return since != null && since.inSeconds < 90;
  }

  String get freshnessLabel {
    final Duration? since = age;
    if (since == null) return 'No position yet';
    if (since.inSeconds < 90) return 'Live';
    if (since.inMinutes < 60) return 'Updated ${since.inMinutes} min ago';
    if (since.inHours < 24) return 'Updated ${since.inHours} h ago';
    return 'Position is out of date';
  }
}

/// How the client wants a repaired pickup job back.
///
/// Mirrors `job_return_preferences.method` (20260922000005). No row means
/// [delivery], the default: the technician brings it back unless the client
/// says they will come for it.
enum ReturnMethod {
  delivery('delivery'),
  clientPickup('client_pickup');

  const ReturnMethod(this.wire);

  final String wire;

  static ReturnMethod fromWire(String? value) =>
      value == clientPickup.wire ? clientPickup : delivery;
}
