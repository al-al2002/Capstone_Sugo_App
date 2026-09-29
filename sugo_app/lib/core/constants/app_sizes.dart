/// Shared spacing, radius and sizing tokens so screens stay visually in sync.
///
/// ## The spacing scale
///
/// `4 · 8 · 12 · 16 · 20 · 24 · 32 · 40`, and nothing in between:
///
/// | Token | px | Typical use |
/// |---|---|---|
/// | [xs] | 4 | icon-to-label, stacked micro lines |
/// | [sm] | 8 | chips in a row, a label above its field |
/// | [md] | 12 | inside a compact card, between list rows |
/// | [lg] | 16 | inside a standard card |
/// | [screenPadding] | 20 | the left/right gutter of every screen |
/// | [xl] | 24 | between groups inside a section |
/// | [xxl] | 32 | between major sections |
/// | [xxxl] | 40 | above a screen's first heading, hero breathing room |
///
/// A value that is not on the scale is almost always a sign the layout is
/// fighting something - fix the structure rather than adding a 14.
///
/// ## Corners (the 2026-09-29 "Dispatch" redesign)
///
/// Two corner sizes, where there used to be five (28, 20, 16, 14 and a
/// dozen hand-typed values):
///
/// * [radius] - **12**, for everything that sits *on* the page: cards,
///   buttons, fields, tiles, chips that are not pills.
/// * [sheetRadius] - **20**, for things anchored to a screen edge or floating
///   over it: bottom sheets, dialogs, the auth sheet.
///
/// Why so few: a corner size is a signal of *what kind of object* something
/// is. When a card, a tile inside it and the button inside that all have
/// different corners, the eye reads three kinds of object where there is one.
/// The old names ([panelRadius], [tileRadius], [fieldRadius], [buttonRadius],
/// [cardRadius]) are kept as aliases so every existing screen picks up the new
/// corners at once, with nothing half-migrated.
class AppSizes {
  const AppSizes._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const double screenPadding = 20;

  /// The one corner for things on the page. See the class note.
  static const double radius = 12;

  /// The auth screen's white sheet. It is anchored to the bottom edge like a
  /// bottom sheet, so it takes the sheet corner.
  static const double cardRadius = sheetRadius;

  /// Fields and buttons share the page corner so a form reads as one family
  /// of shapes.
  static const double fieldRadius = radius;
  static const double buttonRadius = radius;

  static const double fieldHeight = 54;

  /// Primary buttons. 54 rather than 52 - comfortably over the 48px touch
  /// floor, and it gives the label room at large accessibility text sizes.
  static const double buttonHeight = 54;

  /// Secondary and outlined buttons, one step shorter than primary so the two
  /// never compete when they sit side by side.
  static const double socialButtonHeight = 48;

  /// The *visible* height of a compact button inside a card ("Track",
  /// "Message"). Its touch area is still [touchTarget]: the button pads its
  /// hit region out to 48, the way Material's own compact buttons do.
  static const double compactButtonHeight = 40;

  /// Height of the illustrated header behind the auth card.
  static const double authHeroHeight = 260;

  // ------------------------------------------------------------- RB-CARS UI

  /// Fully rounded chips and filter tabs.
  static const double pillRadius = 999;

  /// Alias of [radius], kept for the screens that name it.
  static const double panelRadius = radius;

  /// Alias of [radius], kept for the screens that name it.
  static const double tileRadius = radius;

  static const double filterTabHeight = 38;
  static const double serviceTileSize = 58;
  static const double technicianCardWidth = 176;
  static const double heroBannerHeight = 168;
  static const double bottomNavHeight = 64;

  /// Header image on the technician detail screen.
  static const double technicianHeroHeight = 300;

  // ------------------------------------------------------- UI renovation
  //
  // Added by the visual overhaul. Everything above is the original set and
  // keeps its meaning; these fill the gaps the renovation kept hitting.

  /// One step above [xxl], for the breathing room between major sections on a
  /// redesigned screen. The old layouts separated everything by [xl], which is
  /// why they read as an undifferentiated stack - when the gap *between*
  /// sections equals the gap *inside* them, there are no sections.
  static const double xxxl = 40;

  /// Bottom sheets, dialogs and anything anchored to a screen edge. Larger
  /// than [radius] because a full-width surface with a 12 corner reads as
  /// timid - and because the difference itself tells you it floats.
  static const double sheetRadius = 20;

  /// Minimum tap target. 48 is Material's (and Android's) floor; SUGO is used
  /// mostly on Android phones. Anything drawn smaller pads its hit area out to
  /// this rather than shrinking the number.
  static const double touchTarget = 48;

  /// Avatars. Three sizes only: a row, a card header, a profile hero.
  static const double avatarSm = 36;
  static const double avatarMd = 48;
  static const double avatarLg = 96;

  /// The client's compose button in the bottom bar. Larger than a nav icon on
  /// purpose - it is the one action the whole client app is built around.
  static const double composeButton = 48;

  /// Height of the progress rail across a multi-step flow.
  static const double stepRailHeight = 4;

  /// Icon tile beside a list row or inside a stat card.
  static const double iconTile = 44;

  /// Readable column width on tablets and landscape phones. Screens that are
  /// a single column of cards cap here and centre, so a line of text never
  /// runs the full width of a 10" screen.
  static const double maxContentWidth = 560;
}
