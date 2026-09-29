import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../theme/app_elevation.dart';
import '../theme/app_motion.dart';
import '../theme/app_text_styles.dart';

/// One destination in a bottom navigation bar.
///
/// The client and the technician have entirely separate dashboards with
/// different tabs, so the *bar* is shared but the *items* are not. Each feature
/// declares its own enum and maps it to these, which is why this is a plain
/// data class in core rather than an enum with a fixed set of tabs.
class SugoNavItem {
  const SugoNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.showBadge = false,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// Draws the unread dot. A dot rather than a count on purpose: the number of
  /// unread threads is not a number anyone acts on, and a growing "17" reads as
  /// a debt. What matters is whether there is anything new at all.
  final bool showBadge;
}

/// The compose action in the middle of the bar.
///
/// Client-side only. A technician has nothing to post - they answer jobs and
/// community questions rather than creating them - so their bar simply omits
/// this and spreads four tabs evenly. Passing it as an optional parameter
/// rather than branching on a role keeps the bar ignorant of who is using it.
class SugoComposeAction {
  const SugoComposeAction({
    required this.onTap,
    this.icon = Icons.add_rounded,
    this.tooltip = 'Post a repair job',
  });

  final VoidCallback onTap;
  final IconData icon;
  final String tooltip;
}

/// Bottom navigation bar: a white bar along the bottom edge.
///
/// Built by hand rather than with `NavigationBar` so the label weight, the
/// icon swap and the colours follow the same tokens as the rest of the app.
///
/// ## The Dispatch bar (2026-09-29)
///
/// **It sits on the edge again.** The previous design floated the bar as a
/// rounded pill on a heavy shadow. In the flat Dispatch design only things
/// that genuinely float over content get a shadow, and a tab bar is the
/// floor of the screen, not something above it. It is a white bar with a
/// hairline along its top and the faint upward [AppElevation.navBar] shadow,
/// so content scrolling underneath still reads as going *under* it.
///
/// **One indicator that travels.** A single soft pill sits behind the active
/// icon and slides to the new tab on a switch. The motion *is* the
/// information: it shows where you came from and where you went. It sits
/// behind the icon only - the Material 3 pattern - rather than the whole tab,
/// so the label stays on plain white and reads at full contrast.
///
/// No bounce or elastic curve. A navigation bar is pressed dozens of times a
/// session, and overshoot that is charming once is tiring by the tenth tap.
/// Under "remove animations" the pill jumps instead of sliding.
///
/// ## Why the compose button sits inside the bar
///
/// A button that overflows its parent depends on no ancestor ever clipping
/// it, and a bottom bar sits inside a `Scaffold` slot, above a gesture inset,
/// on devices whose safe areas differ. It earns its prominence from its navy
/// fill instead - the only filled shape in the bar.
class SugoBottomNav extends StatelessWidget {
  const SugoBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onChanged,
    this.composeAction,
  });

  final List<SugoNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  /// When set, drops a compose button into the middle of the row. The tabs
  /// keep their own indices - the button is not a destination and never
  /// changes [currentIndex].
  final SugoComposeAction? composeAction;

  /// Width the compose slot takes out of the row: the button plus its gutter.
  static const double _composeSlot = AppSizes.composeButton + AppSizes.lg * 2;

  static const double _barHeight = 64;

  /// The pill behind the active icon.
  static const Size _indicator = Size(56, 30);

  @override
  Widget build(BuildContext context) {
    // Split point for the compose button: as close to the centre as the item
    // count allows. Four tabs give a clean two-and-two.
    final int splitAt = (items.length / 2).ceil();
    final bool hasCompose = composeAction != null;
    final bool still = AppMotion.reduced(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppElevation.navBar,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _barHeight,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double reserved = hasCompose ? _composeSlot : 0;
              final double tab =
                  (constraints.maxWidth - reserved) / items.length;

              double leftOf(int index) =>
                  index * tab + (hasCompose && index >= splitAt ? reserved : 0);

              final List<Widget> slots = <Widget>[];
              for (int i = 0; i < items.length; i++) {
                if (hasCompose && i == splitAt) {
                  slots.add(_ComposeButton(action: composeAction!));
                }
                slots.add(
                  SizedBox(
                    width: tab,
                    child: _NavItem(
                      item: items[i],
                      active: i == currentIndex,
                      onTap: () => onChanged(i),
                    ),
                  ),
                );
              }
              // Odd item counts would otherwise never reach the split point.
              if (hasCompose && splitAt >= items.length) {
                slots.add(_ComposeButton(action: composeAction!));
              }

              final bool validIndex =
                  currentIndex >= 0 && currentIndex < items.length;

              return Stack(
                children: <Widget>[
                  // The travelling indicator, under the active icon.
                  if (validIndex)
                    AnimatedPositioned(
                      duration: still ? Duration.zero : AppMotion.slow,
                      curve: AppMotion.emphasized,
                      left:
                          leftOf(currentIndex) + (tab - _indicator.width) / 2,
                      width: _indicator.width,
                      top: _NavItem.topPad,
                      height: _indicator.height,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(
                            AppSizes.pillRadius,
                          ),
                        ),
                      ),
                    ),
                  Row(children: slots),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The client's compose button: a navy square with the page corner, the only
/// filled shape in the bar.
class _ComposeButton extends StatefulWidget {
  const _ComposeButton({required this.action});

  final SugoComposeAction action;

  @override
  State<_ComposeButton> createState() => _ComposeButtonState();
}

class _ComposeButtonState extends State<_ComposeButton> {
  bool _held = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: SugoBottomNav._composeSlot,
      child: Center(
        child: Semantics(
          button: true,
          label: widget.action.tooltip,
          excludeSemantics: true,
          child: Tooltip(
            message: widget.action.tooltip,
            child: GestureDetector(
              onTapDown: (_) => setState(() => _held = true),
              onTapUp: (_) => setState(() => _held = false),
              onTapCancel: () => setState(() => _held = false),
              onTap: widget.action.onTap,
              child: AnimatedScale(
                scale: _held ? 0.94 : 1,
                duration: AppMotion.fast,
                curve: AppMotion.standard,
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  width: AppSizes.composeButton,
                  height: AppSizes.composeButton,
                  decoration: BoxDecoration(
                    color: _held ? AppColors.primaryDark : AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSizes.radius),
                  ),
                  child: Icon(
                    widget.action.icon,
                    size: 26,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final SugoNavItem item;
  final bool active;
  final VoidCallback onTap;

  /// Space above the icon's pill; shared with the travelling indicator so the
  /// two line up exactly.
  static const double topPad = 8;

  static const Color _inactive = AppColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: active ? 1 : 0),
          duration: AppMotion.base,
          curve: AppMotion.standard,
          builder: (BuildContext context, double t, Widget? _) {
            final Color color = Color.lerp(_inactive, AppColors.primary, t)!;

            return Padding(
              padding: const EdgeInsets.only(top: topPad),
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: SugoBottomNav._indicator.height,
                    child: Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          Icon(
                            active ? item.activeIcon : item.icon,
                            size: 22,
                            color: color,
                          ),
                          if (item.showBadge)
                            const Positioned(
                              top: -2,
                              right: -4,
                              child: _Badge(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.micro.copyWith(
                      // Lerped rather than switched, so the weight change
                      // lands with the colour instead of a frame before it.
                      fontWeight: FontWeight.lerp(
                        FontWeight.w500,
                        FontWeight.w800,
                        t,
                      ),
                      color: color,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The unread dot.
///
/// Ringed in the bar's own white so it stays legible over the indicator pill.
class _Badge extends StatelessWidget {
  const _Badge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 2),
      ),
    );
  }
}
