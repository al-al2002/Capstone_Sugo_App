import 'package:flutter/material.dart';

/// Enumerations that mirror the `check` constraints in the RB-CARS migration.
///
/// Every enum carries the exact string Postgres stores in [wire], so the models
/// never hand the database a value a constraint would reject.

/// `jobs.device_type`
enum DeviceType {
  laptop('laptop', 'Laptop / PC', Icons.laptop_mac_rounded),
  phone('phone', 'Phone / Tablet', Icons.smartphone_rounded),
  appliance('appliance', 'Appliance', Icons.kitchen_rounded),
  // Labelled for CCTV as well as Wi-Fi: the camera issues live in this
  // category, and nobody looking for them would think to open "Wi-Fi".
  network('network', 'Network / CCTV', Icons.router_rounded);

  const DeviceType(this.wire, this.label, this.icon);

  final String wire;
  final String label;
  final IconData icon;

  static DeviceType? fromWire(String? value) {
    for (final DeviceType type in DeviceType.values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// `jobs.service_path`
enum ServicePath {
  homeService(
    'home_service',
    'Home service',
    'A technician comes to you and fixes it on site.',
    Icons.home_repair_service_rounded,
  ),
  pickup(
    'pickup',
    'Shop pickup',
    'We collect the unit, repair it in the shop, and return it.',
    Icons.local_shipping_rounded,
  ),
  itCommunity(
    'it_community',
    'IT community',
    'Post it to the technician community for a group diagnosis first.',
    Icons.groups_rounded,
  );

  const ServicePath(this.wire, this.label, this.blurb, this.icon);

  final String wire;
  final String label;
  final String blurb;
  final IconData icon;

  static ServicePath? fromWire(String? value) {
    for (final ServicePath path in ServicePath.values) {
      if (path.wire == value) return path;
    }
    return null;
  }
}

/// `jobs.urgency`
enum Urgency {
  needToday('need_today', 'Need it today', 'Push technicians who can come now'),
  canWait('can_wait', 'Can wait', 'Best price and best fit over speed');

  const Urgency(this.wire, this.label, this.blurb);

  final String wire;
  final String label;
  final String blurb;

  static Urgency fromWire(String? value) {
    return value == 'need_today' ? Urgency.needToday : Urgency.canWait;
  }
}

/// `jobs.classification_confidence`
enum ClassificationConfidence {
  high('high'),
  low('low');

  const ClassificationConfidence(this.wire);

  final String wire;

  static ClassificationConfidence? fromWire(String? value) {
    if (value == 'high') return ClassificationConfidence.high;
    if (value == 'low') return ClassificationConfidence.low;
    return null;
  }
}

/// `jobs.status`
enum JobStatus {
  pending('pending', 'Pending'),
  matched('matched', 'Matched'),
  confirmed('confirmed', 'Confirmed'),
  inProgress('in_progress', 'In progress'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const JobStatus(this.wire, this.label);

  final String wire;
  final String label;

  static JobStatus fromWire(String? value) {
    for (final JobStatus status in JobStatus.values) {
      if (status.wire == value) return status;
    }
    return JobStatus.pending;
  }
}

/// `job_matches.status`
enum MatchStatus {
  /// Ranked into the Top 3 by the engine, and shown to the CLIENT so they can
  /// choose. Deliberately invisible to the technician: being ranked is not the
  /// same as being booked, and a technician's dashboard must only show work a
  /// client actually requested from them.
  shortlisted('shortlisted'),

  /// The client picked this technician. This is the only status that reaches a
  /// technician's dashboard, and the only one they may accept or decline.
  offered('offered'),

  declined('declined'),
  accepted('accepted');

  const MatchStatus(this.wire);

  final String wire;

  static MatchStatus fromWire(String? value) {
    for (final MatchStatus status in MatchStatus.values) {
      if (status.wire == value) return status;
    }
    // Falls back to `shortlisted`, not `offered`. An unrecognised value must
    // never be read as "a client booked this technician" - the safe default is
    // the state that shows nothing on a technician's dashboard.
    return MatchStatus.shortlisted;
  }
}

/// `technicians.tier`
enum TechnicianTier {
  standard('standard', 'Standard'),
  pro('pro', 'Pro'),
  elite('elite', 'Elite');

  const TechnicianTier(this.wire, this.label);

  final String wire;
  final String label;

  static TechnicianTier fromWire(String? value) {
    for (final TechnicianTier tier in TechnicianTier.values) {
      if (tier.wire == value) return tier;
    }
    return TechnicianTier.standard;
  }
}
