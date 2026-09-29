import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../models/technician.dart';

/// Technician photo, falling back to their initials on a brand-tinted circle.
///
/// `profiles.avatar_url` is nullable and most seeded accounts will not have
/// one, so the fallback is the common case rather than an edge case.
class TechnicianAvatar extends StatelessWidget {
  const TechnicianAvatar({
    super.key,
    required this.technician,
    this.size = 48,
    this.borderColor,
  });

  final Technician technician;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final String? url = technician.avatarUrl;

    final Widget inner = url == null || url.isEmpty
        ? _Initials(technician: technician, size: size)
        : ClipOval(
            child: Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  _Initials(technician: technician, size: size),
              loadingBuilder:
                  (BuildContext context, Widget child, ImageChunkEvent? chunk) {
                    if (chunk == null) return child;
                    return _Initials(technician: technician, size: size);
                  },
            ),
          );

    if (borderColor == null) return inner;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor!, width: 2),
      ),
      child: inner,
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.technician, required this.size});

  final Technician technician;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.primaryLight, AppColors.primary],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        technician.initials,
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
