/// Tolerant converters shared by every RB-CARS model.
///
/// PostgREST returns `numeric` columns as strings, `integer` as int and
/// `double precision` as double, and any nullable column as null. Rather than
/// repeat that defensiveness in four `fromJson` bodies, every model funnels
/// through these.
library;

/// Non-null double, defaulting to 0.
double asDouble(Object? value) => asNullableDouble(value) ?? 0;

double? asNullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

int? asNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// Parses a Postgres timestamptz into local time.
DateTime? asDate(Object? value) {
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

/// Parses a `text[]` column, dropping any non-string entries.
List<String> asStringList(Object? value) {
  if (value is List) return value.whereType<String>().toList(growable: false);
  return const <String>[];
}
