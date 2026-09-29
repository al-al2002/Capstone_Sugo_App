import 'package:flutter/material.dart';

/// SUGO brand palette.
///
/// ## The 2026-09 redesign: navy leads, blue points, orange marks
///
/// The palette used to be one saturated blue (`#1877F2`) doing every job - the
/// brand, the buttons, the links, the focus rings, the selected tabs. When one
/// colour means everything it means nothing, and that blue is also the most
/// recognisable colour of a social network, which undercut SUGO's own identity.
///
/// Each colour now has one job:
///
/// * **Deep navy ([primary])** is the brand and the primary action. Dark enough
///   to read as trustworthy - this is an app that sends a stranger into your
///   home - and it carries white text at better than 12:1, so a navy button is
///   legible in direct sunlight on a cheap screen.
/// * **Modern blue ([secondary])** is for *pointing*: links, focus, selection,
///   progress, the route line on a map, "information" states. It stays out of
///   large fills, which is what keeps it meaningful.
/// * **Orange ([accent])** marks the few things that deserve a glance - an
///   unread badge, a rating star, the live-booking pulse. Never text on white:
///   orange on white fails contrast, so text in that family uses [accentDark].
///
/// ## 2026-09-27: the matching brief's palette
///
/// The context-aware matching brief set exact values. They are used exactly
/// wherever a colour is a fill, an icon, a line or a brand surface:
///
/// | Brief                   | Token                              |
/// |-------------------------|------------------------------------|
/// | Deep Navy `#062B5C`     | [primary]                          |
/// | SUGO Blue `#087FEA`     | [secondary]                        |
/// | Cyan Accent `#11C5E8`   | [cyan]                             |
/// | Soft Blue `#EAF5FF`     | [secondarySoft], [infoSoft]        |
/// | Dark Text `#10233F`     | [textPrimary]                      |
/// | Warning/Orange `#F59E0B`| [accent]                           |
///
/// Five of the brief's values are too light to be read as *text* on white,
/// and this app prints every one of those colours as text somewhere - a link,
/// "Confirmed" in green, an error under a field. Measured on white:
///
/// | Brief                | Contrast | Text token, same hue, darkened   |
/// |----------------------|----------|----------------------------------|
/// | SUGO Blue `#087FEA`  | 4.0:1    | [secondaryDark] `#0663C4` 5.8:1  |
/// | Gray Text `#6B7A90`  | 4.4:1    | [textSecondary] `#5F6E84` 5.2:1  |
/// | Success `#20B26B`    | 2.8:1    | [success] `#157F4B` 5.0:1        |
/// | Error `#E5484D`      | 3.9:1    | [error] `#CE2C31` 5.2:1          |
/// | Orange `#F59E0B`     | 2.1:1    | [warning], [accentDark] `#B45309`|
///
/// WCAG AA asks 4.5:1 for body text. On the page ground ([background]) every
/// brief value above does worse still. So the rule this file has always had
/// - a bright colour for marks, a darker one of the same family for words -
/// now applies to every hue in the brief, not only orange. The difference is
/// a step in shade; side by side it is the same colour.
///
/// ## Why every old token name survives
///
/// These names are referenced across the whole app. Keeping them and changing
/// their *values* re-skins every screen at once and leaves nothing half-migrated
/// - a screen nobody has touched still picks up the new palette correctly,
/// because `AppColors.primary` now *means* navy everywhere.
///
/// ## 2026-09-29: the "Dispatch" redesign
///
/// The brand colours did not change. What changed is how surfaces separate:
/// flat white on a Paper ground ([background]) with a Hairline edge
/// ([border]), instead of a shadow under every card. Both values moved by one
/// shade so the hairline reads on the ground at arm's length. Text on the
/// orange marks uses [onAccent] - white on `#F59E0B` is 2.1:1.
class AppColors {
  const AppColors._();

  // --------------------------------------------------------------- brand

  /// Deep navy (brief `#062B5C`). The brand, primary buttons, selected states.
  static const Color primary = Color(0xFF062B5C);

  /// Pressed navy, and the dark end of hero gradients.
  static const Color primaryDark = Color(0xFF04224B);

  /// The light end of a navy gradient, and a disabled primary fill.
  static const Color primaryLight = Color(0xFF2D5B97);

  /// Darkest brand ink: hero backgrounds, the splash, dark text on light tint.
  static const Color navy = Color(0xFF031F44);

  /// Navy lifted towards blue - the far end of the hero gradient and of the
  /// logo mark's tile. One token so the two can never drift apart.
  static const Color navyLift = Color(0xFF0C4C9C);

  /// SUGO blue (brief `#087FEA`): focus rings, progress, selection, map
  /// routes, the verified tick. Marks, not words - see [secondaryDark].
  static const Color secondary = Color(0xFF087FEA);

  /// SUGO blue as text: links, text buttons, "View profile". Pressed blue.
  /// 5.8:1 on white, AA on [secondarySoft].
  static const Color secondaryDark = Color(0xFF0663C4);

  /// Orange (brief `#F59E0B`): badges, stars, urgency, the live pulse. Not
  /// for text on white.
  static const Color accent = Color(0xFFF59E0B);

  /// Orange that passes contrast as text - use this, not [accent], for words.
  static const Color accentDark = Color(0xFFB45309);

  /// Words and numerals printed *on* an [accent] fill - a count badge, an
  /// "Urgent" tag. Ink rather than white: ink on orange is 7.3:1, white 2.1:1.
  static const Color onAccent = Color(0xFF10233F);

  /// Cyan: recommendation and match highlights only - score bars, the
  /// "Recommended" mark. The roof and swoosh in the app icon are this colour, and
  /// the 2026-09-27 matching brief reserves it for exactly this. Never text on
  /// white (about 2:1); use [cyanDark] for words.
  static const Color cyan = Color(0xFF11C5E8);

  /// Cyan that reads as text on white and on [cyanSoft].
  static const Color cyanDark = Color(0xFF0B7A93);

  /// The wash behind a recommendation highlight.
  static const Color cyanSoft = Color(0xFFE3F8FD);

  // ------------------------------------------------------------ surfaces

  /// Paper: the page ground. A cool off-white, so a white card with a hairline
  /// edge separates from it with no shadow at all.
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Color(0xFFFFFFFF);

  /// A field at rest. A shade under the page so an empty input reads as a slot
  /// to fill; it lifts to [surface] on focus.
  static const Color fieldFill = Color(0xFFF7F9FC);

  /// The two ends of the illustrated backdrop behind the auth header.
  static const Color skyTop = Color(0xFFEAF0FA);
  static const Color skyBottom = Color(0xFFDDE6F5);

  // ---------------------------------------------------------------- text

  /// Body ink. Near-black with a navy cast, so text belongs to the palette
  /// instead of sitting on it as neutral grey.
  static const Color textPrimary = Color(0xFF10233F);

  /// The brief's gray `#6B7A90`, one step darker so a caption clears 4.5:1 on
  /// white and on [background]. Same hue.
  static const Color textSecondary = Color(0xFF5F6E84);

  /// Placeholders and disabled labels. Kept above 3:1 on white so a hint is
  /// faint, never invisible.
  static const Color hint = Color(0xFF8C95A8);

  // -------------------------------------------------------- lines & states

  /// Hairline: the edge of every card, field and tile. In the Dispatch design
  /// this does the job a drop shadow used to do.
  static const Color border = Color(0xFFE3E8EF);
  static const Color divider = Color(0xFFEDF0F5);

  // State colours are the dark shades of the brief's hues, not the brief's
  // bright values. This app prints them as *text* - "Confirmed" in green,
  // "Waiting 3h" in amber - and the bright values sit between 2:1 and 4:1 on
  // white, which fails WCAG AA for body text. These three all clear 4.5:1.
  /// Green, from the brief's `#20B26B`.
  static const Color success = Color(0xFF157F4B);

  /// Amber, from the brief's `#F59E0B` - the same family as [accent].
  static const Color warning = Color(0xFFB45309);

  /// Red, from the brief's `#E5484D`. Also the destructive button fill: white
  /// on it is 5.2:1.
  static const Color error = Color(0xFFCE2C31);

  /// Neutral information. The same blue as [secondary], named for intent so
  /// an info banner does not read as a link.
  static const Color info = secondary;

  // --------------------------------------------------------- soft tints
  //
  // 6-12% washes of the colours above, for chip fills, icon tiles and
  // selected states. Precomputed rather than `withValues(alpha:)` so they
  // render identically over any surface.

  /// Navy-blue wash for icon tiles and selected rows. Leans blue rather than
  /// grey: a navy-derived wash on its own reads as dirty white.
  static const Color primarySoft = Color(0xFFE6EDF9);
  static const Color primarySofter = Color(0xFFF1F5FC);

  /// The brief's Soft Blue.
  static const Color secondarySoft = Color(0xFFEAF5FF);

  static const Color accentSoft = Color(0xFFFEF1D6);
  static const Color accentSofter = Color(0xFFFFF8EA);

  static const Color successSoft = Color(0xFFE5F6ED);
  static const Color warningSoft = Color(0xFFFEF3E0);
  static const Color errorSoft = Color(0xFFFDEBEC);
  static const Color infoSoft = secondarySoft;

  // ------------------------------------------------------ match scores

  // Score bands on a match card's ring.
  static const Color scoreStrong = success;
  static const Color scoreFair = warning;
  static const Color scoreWeak = hint;

  // -------------------------------------------------------------- social

  static const Color facebook = Color(0xFF1877F2);

  // ----------------------------------------------------------- gradients

  /// The one hero gradient: navy lifting towards blue at the top-right, as if
  /// lit from the same corner every shadow in the app assumes.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: <Color>[navy, primary, navyLift],
    stops: <double>[0, 0.55, 1],
  );
}
