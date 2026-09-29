import 'package:flutter/material.dart';

/// Durations and curves for every animation in the app.
///
/// ## Why this file exists
///
/// Before the renovation, timings were written inline at each call site -
/// `220ms` here, `300ms` there, `Curves.easeOut` in one widget and
/// `easeOutCubic` in the next. Individually all reasonable; together they are
/// the reason an interface feels assembled rather than designed. Motion is a
/// brand property in the same way colour is, and it deserves the same single
/// source of truth that [AppColors] gives the palette.
///
/// ## The scale
///
/// Four durations, chosen so the *difference* between them is perceptible.
/// Steps closer than about 80ms apart are not distinguishable in use, so a
/// finer scale would be false precision.
///
/// ## On curves
///
/// Almost everything here decelerates: fast at the start, settling at the end.
/// That is the curve of a real object being released, and it is why
/// [standard] rather than `Curves.linear` or a symmetric `easeInOut` is the
/// default. Symmetric easing reads as sluggish on entry because the motion
/// starts slowly, which delays the moment the user learns their tap landed.
///
/// Nothing in the navigation or the forms overshoots. Elastic and bounce
/// curves are charming the first time and tiring by the tenth, and a control
/// pressed dozens of times a session must never be tiring. [playful] exists
/// for the handful of once-per-flow moments that earn it - a success check
/// mark, a newly awarded badge - and is used sparingly on purpose.
class AppMotion {
  const AppMotion._();

  // ----------------------------------------------------------- durations

  /// Immediate feedback: a press state, a ripple, a colour change under the
  /// finger. Fast enough to feel like a property of the touch itself.
  static const Duration fast = Duration(milliseconds: 140);

  /// The default. Tab switches, chip selection, expanding a row, most state
  /// changes. Long enough to be followed, short enough never to be waited on.
  static const Duration base = Duration(milliseconds: 240);

  /// Larger moves: a sheet rising, a card expanding, a step transition in the
  /// posting flow. More distance travelled needs more time, or the motion
  /// reads as a jump-cut.
  static const Duration slow = Duration(milliseconds: 360);

  /// Full-screen route transitions and deliberate, one-off reveals.
  static const Duration page = Duration(milliseconds: 420);

  /// Gap between children in a staggered list entrance.
  ///
  /// Deliberately small. The purpose of a stagger is to suggest the items
  /// arrived in an order, not to make the last one wait: at 55ms a six-item
  /// list finishes its cascade in 275ms, while a more theatrical 150ms step
  /// would leave the final card arriving nearly a second after the screen.
  static const Duration staggerStep = Duration(milliseconds: 55);

  /// Ceiling on a staggered entrance, so a long list does not animate its
  /// twentieth row three seconds late. Past this index every child shares the
  /// same delay and simply arrives together.
  static const int maxStaggerIndex = 8;

  // -------------------------------------------------------------- curves

  /// The workhorse. Decelerating, no overshoot.
  static const Curve standard = Curves.easeOutCubic;

  /// A sharper deceleration for motion that covers real distance - a sheet
  /// coming up from off-screen, a step sliding in. The long tail lets a big
  /// move settle instead of stopping dead.
  static const Curve emphasized = Curves.easeOutQuint;

  /// For things leaving. Accelerating out is the mirror of decelerating in,
  /// and using [standard] for an exit makes the element seem reluctant.
  static const Curve exit = Curves.easeInCubic;

  /// The one curve permitted to overshoot, for rare moments of reward: a
  /// verification check mark, a tier badge being awarded, a posted job
  /// confirming. Never on a control that repeats.
  static const Curve playful = Curves.easeOutBack;

  /// Whether the person has asked the phone to remove animations ("Remove
  /// animations" on Android, "Reduce motion" on iOS).
  ///
  /// Every looping or decorative animation checks this and holds still when
  /// it is on: a shimmer, a pulse, the matching emblem, the delete bin. For
  /// some people movement on screen causes real nausea, and the setting is how
  /// they tell every app. Motion that *answers* a tap - a button dip, a sheet
  /// opening - may stay, shortened, because it carries information.
  ///
  /// The redesign audit found this honoured in only six places.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Delay for the child at [index] in a staggered entrance, clamped by
  /// [maxStaggerIndex].
  static Duration staggerDelay(int index) {
    final int clamped = index < 0
        ? 0
        : (index > maxStaggerIndex ? maxStaggerIndex : index);
    return staggerStep * clamped;
  }
}
