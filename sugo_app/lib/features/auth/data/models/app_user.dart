import 'package:supabase_flutter/supabase_flutter.dart';

/// Domain view of the signed-in account.
///
/// Supabase keeps the sign-up extras (name, phone) in `user_metadata`; this
/// model flattens them so the UI does not read raw maps.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.fullName,
    this.phone,
    this.avatarUrl,
    this.emailConfirmedAt,
  });

  factory AppUser.fromSupabase(User user) {
    final Map<String, dynamic> meta = user.userMetadata ?? <String, dynamic>{};
    return AppUser(
      id: user.id,
      email: user.email ?? '',
      // OAuth providers use `name`/`full_name` inconsistently.
      fullName: (meta['full_name'] ?? meta['name']) as String?,
      phone: (meta['phone'] ?? user.phone) as String?,
      avatarUrl: (meta['avatar_url'] ?? meta['picture']) as String?,
      emailConfirmedAt: user.emailConfirmedAt,
    );
  }

  final String id;
  final String email;
  final String? fullName;
  final String? phone;
  final String? avatarUrl;
  final String? emailConfirmedAt;

  bool get isEmailVerified => emailConfirmedAt != null;

  /// First name if we have one, otherwise the email handle.
  String get displayName {
    final String? name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name.split(' ').first;
    if (email.contains('@')) return email.split('@').first;
    return 'there';
  }

  String get initials {
    final String? name = fullName?.trim();
    if (name == null || name.isEmpty) {
      return email.isEmpty ? '?' : email.substring(0, 1).toUpperCase();
    }
    final List<String> parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
