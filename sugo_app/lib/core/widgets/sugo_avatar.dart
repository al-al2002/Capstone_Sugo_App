import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_elevation.dart';

/// A person's picture, with a dependable fallback.
///
/// ## Why initials and not a default silhouette
///
/// Most rows in SUGO have no photo. `profiles.avatar_url` is optional at every
/// step of registration, so the grey-person placeholder was the most-rendered
/// image in the app - and a list of identical grey silhouettes is genuinely
/// harder to scan than a list of coloured initials, because nothing
/// distinguishes one row from the next.
///
/// Initials sit on a tint chosen deterministically from the name, so the same
/// person is the same colour everywhere in the app and a conversation list
/// becomes scannable by colour before it is read. The tints are existing
/// palette washes - no new colours enter the app through this widget.
class SugoAvatar extends StatelessWidget {
  const SugoAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = AppSizes.avatarMd,
    this.verified = false,
    this.ringColor,
    this.onTap,
    this.elevated = false,
  });

  final String? name;
  final String? imageUrl;
  final double size;

  /// Draws the verification tick. Only ever set from a server-backed flag -
  /// this is a trust signal and must never be decorative.
  final bool verified;

  /// Optional accent ring, e.g. a tier colour on a profile hero.
  final Color? ringColor;

  final VoidCallback? onTap;
  final bool elevated;

  /// The soft washes an initials avatar can land on. All existing tokens.
  ///
  /// The orange pair uses the *text* orange: initials are words, and the
  /// bright orange on its own wash was about 2:1.
  static const List<(Color, Color)> _tints = <(Color, Color)>[
    (AppColors.primarySoft, AppColors.primaryDark),
    (AppColors.accentSoft, AppColors.accentDark),
    (AppColors.successSoft, AppColors.success),
    (AppColors.warningSoft, AppColors.warning),
    (AppColors.primarySofter, AppColors.primary),
  ];

  String get _initials {
    final String trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return '?';
    final List<String> parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  /// Stable per name, so one person keeps one colour across every screen.
  (Color, Color) get _tint {
    final String key = (name ?? '').trim();
    if (key.isEmpty) return (AppColors.divider, AppColors.textSecondary);
    final int hash = key.codeUnits.fold<int>(0, (int a, int b) => a + b);
    return _tints[hash % _tints.length];
  }

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = _tint;
    final String? url = imageUrl?.trim();

    final Widget initials = Text(
      _initials,
      style: TextStyle(
        // Scales with the avatar so a 96px profile hero and a 36px list row
        // are the same design rather than two.
        fontSize: size * 0.36,
        fontWeight: FontWeight.w700,
        color: foreground,
        letterSpacing: -0.2,
      ),
    );

    final bool hasPhoto = url != null && url.isNotEmpty;

    Widget face = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        boxShadow: elevated ? AppElevation.sm : null,
      ),
      alignment: Alignment.center,
      // ClipOval rather than a `DecorationImage` on the box above.
      //
      // A decoration image has no error or loading callback that can put
      // something else in its place - `onError` only reports. So a photo that
      // 404s, or one on a phone that is briefly offline, used to leave a blank
      // tinted circle: no picture *and* no initials, which is worse than never
      // having tried to load it.
      //
      // `Image.network` can fall back, and both of its fallbacks below are the
      // initials. That makes the avatar degrade to the state it would have had
      // anyway, instead of to nothing.
      child: hasPhoto
          ? ClipOval(
              child: Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                    initials,
                // Initials while the bytes are in flight, so the circle is
                // never empty and nothing reflows when the photo lands.
                loadingBuilder:
                    (
                      BuildContext _,
                      Widget child,
                      ImageChunkEvent? progress,
                    ) => progress == null ? child : initials,
              ),
            )
          : initials,
    );

    if (ringColor != null) {
      face = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ringColor!, width: 2),
        ),
        child: face,
      );
    }

    if (verified) {
      face = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          face,
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.verified_rounded,
                size: size * 0.30,
                // Blue: the colour this app uses for confirmed information,
                // and the convention people already read a verified tick in.
                color: AppColors.secondary,
              ),
            ),
          ),
        ],
      );
    }

    if (onTap == null) return face;

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: face),
    );
  }
}
