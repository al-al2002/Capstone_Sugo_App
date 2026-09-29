import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// The app's shadow scale.
///
/// ## Why two layers per step
///
/// A single soft shadow is what most Flutter code reaches for, and it is also
/// what makes a card read as a flat rectangle with a grey smudge under it.
/// Real depth has two parts, and the eye reads both:
///
/// * a **contact shadow** - tight, barely offset, slightly denser. This is the
///   dark line where an object meets the surface it rests on, and it is what
///   tells you the object is *touching* rather than floating.
/// * an **ambient shadow** - wide, soft, far more transparent. This is the
///   general occlusion of light around a raised object, and it is what gives
///   the sense of height.
///
/// Drop either one and the effect collapses: contact alone looks stamped on,
/// ambient alone looks like fog. Together they cost one extra `BoxShadow` and
/// are the single largest reason the renovated UI reads as more premium than
/// the old one.
///
/// ## Why navy and not black
///
/// Every shadow here is [AppColors.navy] at low alpha, never `Colors.black`.
/// The app's ground is [AppColors.background] - a cool blue-tinted white - and
/// a neutral black shadow over a tinted surface desaturates to a dead grey
/// that fights the palette. Tinting the shadow with the brand's own darkest
/// blue keeps it in the same colour family as everything it falls on.
///
/// This is not a new colour: it is an existing token at a new alpha, which is
/// exactly the constraint the renovation works under.
///
/// ## 2026-09-29: the "Dispatch" redesign keeps shadows for floating things
///
/// Cards no longer cast a shadow. A white card on the Paper ground is
/// separated by a hairline edge (`AppColors.border`), which [SugoCard] now
/// draws itself. A shadow under every card was the "SaaS card kit" look - the
/// same grey smudge under everything, so nothing reads as more raised than
/// anything else - and it costs a blur per card on a cheap phone.
///
/// Shadows remain where something genuinely floats over other content:
/// [xl] for sheets, dialogs and sticky footers, [navBar] for the bottom bar,
/// [lg] for a card lifted over a map. [glow] is no longer used by the shared
/// buttons; a flat navy button on a flat page does not need lighting.
class AppElevation {
  const AppElevation._();

  /// Level 0 - flush with the ground. Used for nested surfaces, where a second
  /// shadow inside an already-raised card reads as muddy rather than layered.
  static const List<BoxShadow> flat = <BoxShadow>[];

  /// Level 1 - resting on the surface. Chips, small tiles, input fields and
  /// anything that should separate from the ground without claiming to float.
  static const List<BoxShadow> sm = <BoxShadow>[
    BoxShadow(color: Color(0x0A0B2B5C), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F0B2B5C), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// Level 2 - the standard content card. This is the default for [SugoCard]
  /// and therefore the most common depth in the app.
  static const List<BoxShadow> md = <BoxShadow>[
    BoxShadow(color: Color(0x0D0B2B5C), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x140B2B5C), blurRadius: 18, offset: Offset(0, 6)),
  ];

  /// Level 3 - lifted. A card under the finger, a selected option, the tile
  /// the user is about to commit to. Pairs with a small upward translation.
  static const List<BoxShadow> lg = <BoxShadow>[
    BoxShadow(color: Color(0x0F0B2B5C), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x1C0B2B5C), blurRadius: 28, offset: Offset(0, 12)),
  ];

  /// Level 4 - floating above everything. Bottom sheets, dialogs, the posting
  /// flow's sticky footer and the client's compose button.
  static const List<BoxShadow> xl = <BoxShadow>[
    BoxShadow(color: Color(0x120B2B5C), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x240B2B5C), blurRadius: 40, offset: Offset(0, 18)),
  ];

  /// The bottom navigation bar, which casts *upward* onto the page it covers.
  /// Offsets are negated rather than being a separate design.
  static const List<BoxShadow> navBar = <BoxShadow>[
    BoxShadow(color: Color(0x0D0B2B5C), blurRadius: 3, offset: Offset(0, -1)),
    BoxShadow(color: Color(0x160B2B5C), blurRadius: 24, offset: Offset(0, -8)),
  ];

  /// A coloured glow for primary actions, so the main button on a screen sits
  /// visually above the neutral cards around it.
  ///
  /// Takes the button's own colour so an accent-coloured action glows orange
  /// and a brand-blue one glows blue - a neutral shadow under a saturated
  /// button is the thing that makes it look pasted on.
  static List<BoxShadow> glow(Color color, {double opacity = 0.32}) {
    return <BoxShadow>[
      BoxShadow(
        color: color.withValues(alpha: opacity * 0.5),
        blurRadius: 6,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];
  }
}
