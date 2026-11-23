import 'dart:async';
import 'dart:math' as math;

/// Whether [error] is the network failing - offline, a dropped connection, a
/// request that took too long - rather than the server refusing something.
///
/// Checked by message rather than by type so this file stays usable on web,
/// where dart:io (and therefore SocketException) is unavailable. The same
/// words as `AuthFailure._looksLikeNetworkError`, plus timeouts.
bool looksLikeNetworkError(Object error) {
  if (error is TimeoutException) return true;
  final String raw = error.toString().toLowerCase();
  return raw.contains('socketexception') ||
      raw.contains('clientexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('connection refused') ||
      raw.contains('connection closed') ||
      raw.contains('connection reset') ||
      raw.contains('network is unreachable') ||
      raw.contains('xmlhttprequest error') ||
      raw.contains('failed to fetch') ||
      raw.contains('timed out');
}

/// A random (version 4) UUID, from a secure source.
///
/// Used to give a new job its id on the phone before it is saved
/// (2026-11-23), so that retrying a post whose reply was lost finds the job
/// already saved instead of saving it twice.
String newUuidV4([math.Random? random]) {
  final math.Random source = random ?? math.Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final String hex = bytes
      .map((int b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
