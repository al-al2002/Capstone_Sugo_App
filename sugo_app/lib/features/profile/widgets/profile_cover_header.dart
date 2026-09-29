import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_card.dart';

/// A profile's identity panel: a cover, the avatar straddling its lower edge,
/// then the name and a row of badges.
///
/// ## The redesign (2026-09-29)
///
/// The cover used to be the app icon's emblem, stretched wide - house, wrench,
/// swoosh and van - with the avatar placed dead centre on top of it. The
/// portrait landed on the wrench and half the van, so the two pictures fought
/// and neither read; the panel under it was navy too, which made a light
/// avatar look pasted on. ("Mura mn lain tan-awon.")
///
/// Now the cover is drawn, not a picture: the brand gradient, two soft rings,
/// and the dashed route with a van at its end - the same route line the app
/// draws for every booking. It is quiet in the middle, where the avatar sits,
/// so the face is the only thing there. The panel below is white like every
/// other card, the avatar has a white ring, and the badges are tinted pills.
///
/// ## Why the avatar overlaps the cover
///
/// An image above a card is a banner. An image with the portrait cut into its
/// bottom edge is a *cover* - the arrangement every social profile uses, so
/// people read it without being told. The overlap is half the avatar.
class ProfileCoverHeader extends StatelessWidget {
  const ProfileCoverHeader({
    super.key,
    required this.name,
    this.avatarUrl,
    this.verified = false,
    this.badges = const <Widget>[],
  });

  final String name;
  final String? avatarUrl;

  /// Shows the verified tick on the avatar.
  final bool verified;

  /// Small chips under the name - role, tier, ID status.
  final List<Widget> badges;

  /// Height of the cover.
  static const double coverHeight = 128;

  /// The white ring around the avatar, so it reads as cut into the cover.
  static const double _ringWidth = 4;

  static const double _avatarOuter = AppSizes.avatarLg + _ringWidth * 2;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          Stack(
            alignment: Alignment.bottomCenter,
            children: <Widget>[
              // The cover reserves room below itself for the lower half of
              // the avatar, so the Stack is exactly as tall as what it paints
              // and nothing overflows into the name.
              Padding(
                padding: const EdgeInsets.only(bottom: _avatarOuter / 2),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppSizes.radius - 1),
                  ),
                  child: const SizedBox(
                    height: coverHeight,
                    width: double.infinity,
                    child: _Cover(),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(_ringWidth),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  boxShadow: AppElevation.sm,
                ),
                child: SugoAvatar(
                  name: name,
                  imageUrl: avatarUrl,
                  size: AppSizes.avatarLg,
                  verified: verified,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.xl,
              AppSizes.md,
              AppSizes.xl,
              AppSizes.xl,
            ),
            child: Column(
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.title,
                ),
                if (badges.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSizes.sm),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSizes.sm,
                    runSpacing: AppSizes.xs,
                    children: badges,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The drawn cover: gradient, rings, and the route to the van.
class _Cover extends StatelessWidget {
  const _Cover();

  /// Where the van sits, from the top-right corner.
  static const double _vanRight = 22;
  static const double _vanTop = 20;
  static const double _vanSize = 26;

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CustomPaint(painter: _CoverPainter()),
          Positioned(
            right: _vanRight,
            top: _vanTop,
            child: Icon(
              Icons.local_shipping_rounded,
              size: _vanSize,
              color: Color(0xE6FFFFFF),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverPainter extends CustomPainter {
  const _CoverPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect all = Offset.zero & size;

    // The brand gradient, navy to SUGO blue, corner to corner.
    canvas.drawRect(
      all,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: <Color>[AppColors.navy, AppColors.primary, AppColors.secondary],
          stops: <double>[0, 0.55, 1],
        ).createShader(all),
    );

    // Two soft rings for depth, kept to the corners.
    canvas.drawCircle(
      Offset(size.width * 0.92, -size.height * 0.15),
      size.height * 0.95,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..color = Colors.white.withValues(alpha: 0.06),
    );
    canvas.drawCircle(
      Offset(size.width * 0.02, size.height * 1.05),
      size.height * 0.62,
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );

    // The route: from a start dot low on the left, curving up to the van at
    // the top right. It stays high across the middle, clear of the avatar.
    final Offset start = Offset(size.width * 0.07, size.height * 0.72);
    final Offset end = Offset(
      size.width - _Cover._vanRight - _Cover._vanSize - 6,
      _Cover._vanTop + _Cover._vanSize * 0.62,
    );
    final Path route = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.18,
        size.width * 0.58,
        size.height * 0.62,
        end.dx,
        end.dy,
      );

    final Paint dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.45);
    for (final metric in route.computeMetrics()) {
      const double on = 7;
      const double off = 6;
      for (double d = 0; d < metric.length; d += on + off) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + on, metric.length)),
          dash,
        );
      }
    }

    // The stop where the trip began.
    canvas.drawCircle(start, 6, Paint()..color = Colors.white);
    canvas.drawCircle(start, 3, Paint()..color = AppColors.secondary);
  }

  @override
  bool shouldRepaint(covariant _CoverPainter oldDelegate) => false;
}
