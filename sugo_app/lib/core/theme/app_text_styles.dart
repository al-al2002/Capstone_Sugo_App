import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Typography used across the app.
///
/// ## The typeface
///
/// Plus Jakarta Sans, bundled in `assets/fonts`. Chosen over the platform
/// default (Roboto on Android) for three reasons that matter on a phone:
///
/// * a tall x-height, so 14px body copy reads like 15px Roboto - the brief
///   asked for no tiny text, and this buys legibility without larger sizes
///   pushing every card taller;
/// * open, distinct numerals, which is most of what a booking screen shows -
///   prices, times, reference codes, ratings;
/// * enough character in the heavy weights that a heading looks designed
///   rather than defaulted, which is most of the "premium" in a UI.
///
/// [AppTheme] sets it as the theme's `fontFamily`, so every `Text` inherits it
/// through `DefaultTextStyle` even when it was styled inline. The styles below
/// name it too, so a style used outside a themed subtree (a `TextPainter` on a
/// map marker) still renders in the brand face.
///
/// ## The scale (2026-09-29, "Dispatch")
///
/// Six sizes, and nothing in between:
///
/// | Size | Styles | For |
/// |---|---|---|
/// | 28 | [display], [displayLarge] | A screen's opening line - one per screen at most |
/// | 20 | [title], [headline], [stat], [price] | Screen titles, a headline figure |
/// | 16 | [sectionTitle] | Section and card headings |
/// | 15 | [body], [bodyStrong], [subtitle], [titleSmall], [button], [field] | Running text, a row's title, a button |
/// | 13 | [caption], [label], [link] | Supporting text, field labels, links |
/// | 12 | [micro], [overline], [statLabel] | Metadata: a time, a distance |
///
/// **Nothing is smaller than 12.** The audit that started the redesign found
/// 370 hand-typed font sizes in 25 different values, 21 of them 9-10px. A
/// scale that is short enough to remember is one that gets used.
///
/// **No all-caps eyebrows.** [overline] used to be 11px capitals with wide
/// tracking. It is now 12px sentence case: capitals are slower to read, and a
/// capitalised label above every heading is template chrome, not information.
///
/// Body text moved from 14 to 15, the size the brief's "no tiny text" asked
/// for; Plus Jakarta's tall x-height makes 15 read like 16 elsewhere.
class AppTextStyles {
  const AppTextStyles._();

  /// The bundled family name, as declared in `pubspec.yaml`.
  static const String fontFamily = 'PlusJakartaSans';

  static const TextStyle headline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
    height: 1.25,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle field = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const TextStyle hint = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.hint,
  );

  /// Button labels. Sentence case with near-zero tracking: the old wide-spaced
  /// style was built for ALL-CAPS labels, which the redesign retired because
  /// capitals are slower to read and shout on a screen full of them.
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 0.1,
  );

  static const TextStyle socialButton = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// Inline links. Blue, because blue is the colour that points - the text
  /// shade of it, since the brief's SUGO blue is 4.0:1 on white.
  static const TextStyle link = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.secondaryDark,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // ------------------------------------------------------------ type scale
  //
  // Two rules run through all of it, and they are the difference between text
  // that is merely legible and text that looks typeset:
  //
  // 1. **Letter-spacing tightens as size grows.** Type designed at body size
  //    has tracking built in for readability at that size. Scaled up to 28px
  //    that same tracking reads as loose and amateurish, so large sizes pull
  //    it back. Small sizes get slightly positive tracking, because at 11px
  //    the opposite problem appears - letters start to touch.
  //
  // 2. **Line-height loosens as size shrinks.** A headline is one or two
  //    lines and wants a tight 1.15 so it reads as a single block. Body copy
  //    runs to several lines and wants 1.5, because the eye needs a clear
  //    channel to find the start of the next line.

  /// Once-per-flow moments: "Booking confirmed". Since the Dispatch scale it
  /// is the same size as [display] - 28 is the top of the scale - and differs
  /// only in its tighter line, for one- or two-word arrivals.
  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.8,
    height: 1.1,
  );

  /// Largest text in an ordinary screen: a dashboard greeting, a flow's
  /// opening question. One per screen at most - a second one competing with
  /// it is what makes a layout feel like it has no hierarchy at all.
  static const TextStyle display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.7,
    height: 1.15,
  );

  /// Screen titles below [display], and the headline of a major card.
  static const TextStyle title = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
    height: 1.25,
  );

  /// Section and card headings - "Services", "Top-rated technicians".
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
    height: 1.3,
  );

  /// The title line of a list row or a compact card.
  static const TextStyle titleSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.15,
    height: 1.3,
  );

  /// Running text in the app's primary ink. Distinct from [subtitle], which is
  /// the same size in the muted tone - use this when the words are the point
  /// and that one when they are supporting.
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  /// Body copy that carries weight: a selected option's description, the
  /// answer to the question a card is asking.
  static const TextStyle bodyStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.45,
  );

  /// Metadata under a row: a timestamp, a distance, a category.
  static const TextStyle micro = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 0.05,
    height: 1.35,
  );

  /// A small label above a group - "Your booking", "Recommended". Sentence
  /// case at 12px since the Dispatch redesign; it used to be 11px capitals.
  static const TextStyle overline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    letterSpacing: 0.1,
    height: 1.25,
  );

  /// A headline figure on a stat tile: an earnings total, a job count.
  ///
  /// Heavier and tighter than [title] at the same size, because a number
  /// has no descenders or word shapes to give it presence - weight is the only
  /// tool available to make it read as the important thing on the tile.
  static const TextStyle stat = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.1,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  /// The label under a [stat] figure.
  static const TextStyle statLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.1,
    height: 1.25,
  );

  /// A money figure that the screen exists to show: a booking total, a
  /// starting price. Tabular figures so a column of prices lines up.
  static const TextStyle price = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
    height: 1.15,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}
