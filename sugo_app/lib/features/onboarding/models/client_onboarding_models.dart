/// A place the map step is working with: a pin, a search hit, or a saved row.
///
/// One type for all three because they are the same three facts - a coordinate
/// pair and the text a human reads. Separate types for "Nominatim result" and
/// "saved address" would mean a conversion at every hand-off between the search
/// bar, the map and the save call.
enum EmailVerificationState {
  /// Ready to send. Nothing to collect - the address came from signup.
  entry,

  /// Code mailed, waiting for the six digits.
  awaitingCode,

  /// The code checked out. Held in the flow, not in a column - see
  /// `EmailOtpService`.
  verified,
}

class GeoPlace {
  const GeoPlace({
    required this.latitude,
    required this.longitude,
    required this.addressText,
    this.shortLabel,
  });

  /// Builds one from a Nominatim search or reverse-geocode result.
  factory GeoPlace.fromNominatim(Map<String, dynamic> json) {
    // Nominatim returns lat/lon as strings, not numbers.
    final double? lat = double.tryParse(json['lat']?.toString() ?? '');
    final double? lon = double.tryParse(json['lon']?.toString() ?? '');
    final String display = json['display_name'] as String? ?? '';

    return GeoPlace(
      latitude: lat ?? 0,
      longitude: lon ?? 0,
      addressText: display,
      // The first comma-separated component is the specific bit - a building
      // or street name - and is what a list row should lead with. The full
      // display_name is often eight components long and unreadable in a list.
      shortLabel: display.split(',').first.trim(),
    );
  }

  final double latitude;
  final double longitude;
  final String addressText;
  final String? shortLabel;

  /// True when the coordinates are usable. Nominatim occasionally returns a
  /// row whose lat/lon fail to parse, and a silent (0, 0) puts the pin in the
  /// Gulf of Guinea rather than failing visibly.
  bool get hasCoordinates => latitude != 0 || longitude != 0;

  String get coordinateLabel =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  /// What to show when reverse geocoding found nothing - a dropped pin in a
  /// place with no mapped address is still a valid location.
  String get displayText =>
      addressText.trim().isEmpty ? coordinateLabel : addressText;
}

/// A row of `client_saved_addresses`.
class SavedAddress {
  const SavedAddress({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.addressText,
    this.id,
    this.notes,
    this.isDefault = true,
  });

  factory SavedAddress.fromJson(Map<String, dynamic> json) {
    return SavedAddress(
      id: json['id'] as String?,
      label: json['label'] as String? ?? 'Home',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      addressText: json['address_text'] as String? ?? '',
      notes: json['notes'] as String?,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  final String? id;

  /// "Home", "Office", or whatever the client typed.
  final String label;

  final double latitude;
  final double longitude;
  final String addressText;

  /// Landmarks the map cannot know: "green gate", "ask for Ate Beth".
  final String? notes;

  final bool isDefault;

  GeoPlace get place => GeoPlace(
    latitude: latitude,
    longitude: longitude,
    addressText: addressText,
  );

  Map<String, dynamic> toInsertJson(String clientId) {
    return <String, dynamic>{
      'client_id': clientId,
      'label': label,
      'latitude': latitude,
      'longitude': longitude,
      'address_text': addressText,
      if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
      'is_default': isDefault,
    };
  }

  SavedAddress copyWith({
    String? label,
    double? latitude,
    double? longitude,
    String? addressText,
    String? notes,
  }) {
    return SavedAddress(
      id: id,
      label: label ?? this.label,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      addressText: addressText ?? this.addressText,
      notes: notes ?? this.notes,
      isDefault: isDefault,
    );
  }

  /// Labels offered as one-tap chips. Free text is still accepted - these are
  /// a shortcut, not a constraint.
  static const List<String> suggestedLabels = <String>[
    'Home',
    'Office',
    'Shop',
    'Parents',
  ];
}

/// Mirrors `client_verification_status.trust_level`.
enum TrustLevel {
  isNew('new', 'New', 'Just joined. Identity review pending.'),
  verified('verified', 'Verified', 'Government ID approved by SUGO.'),
  trusted('trusted', 'Trusted', 'Verified, with a strong booking history.');

  const TrustLevel(this.wire, this.label, this.blurb);

  final String wire;
  final String label;
  final String blurb;

  static TrustLevel fromWire(String? value) {
    for (final TrustLevel t in TrustLevel.values) {
      if (t.wire == value) return t;
    }
    return TrustLevel.isNew;
  }
}

/// What a technician is shown about a client before accepting a job.
class ClientTrustProfile {
  const ClientTrustProfile({
    required this.clientId,
    required this.trustLevel,
    this.noShowCount = 0,
    this.avgRatingFromTechnicians,
  });

  factory ClientTrustProfile.fromJson(Map<String, dynamic> json) {
    return ClientTrustProfile(
      clientId: json['client_id'] as String,
      trustLevel: TrustLevel.fromWire(json['trust_level'] as String?),
      noShowCount: json['no_show_count'] as int? ?? 0,
      avgRatingFromTechnicians: (json['avg_rating_from_technicians'] as num?)
          ?.toDouble(),
    );
  }

  final String clientId;
  final TrustLevel trustLevel;
  final int noShowCount;

  /// Null until enough technicians have rated them.
  ///
  /// Null and 0 are not the same and must not be collapsed: "not yet rated" is
  /// neutral, whereas a displayed 0 reads as unanimously terrible and would
  /// freeze out every new client.
  final double? avgRatingFromTechnicians;

  bool get hasRating => avgRatingFromTechnicians != null;

  String get ratingLabel => hasRating
      ? avgRatingFromTechnicians!.toStringAsFixed(1)
      : 'Not yet rated';
}
