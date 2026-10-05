import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/repositories/auth_repository.dart';
import '../controllers/login_controller.dart';
import '../controllers/register_controller.dart';
import '../widgets/auth_footer_prompt.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_tab.dart';
import '../widgets/login_form.dart';
import '../widgets/register_form.dart';

/// Single entry point for signing in and signing up.
///
/// ## Layout (the 2026-09-28 reference design)
///
/// The SUGO lockup large on navy at the top ([AuthHeader]), and a white sheet
/// with rounded top corners riding up over its bottom edge, holding one form.
/// Email and password only - no Google or Facebook.
///
/// There is no tab switcher any more. The reference moves between the two
/// forms with the line under each one - "Don't have an account? Register",
/// "Already have an account? Log in" - which is also where people look for it.
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key, this.initialTab = AuthTab.login});

  final AuthTab initialTab;

  @override
  Widget build(BuildContext context) {
    final AuthRepository repository = context.read<AuthRepository>();

    // Both controllers live above the forms, so a half-typed form survives a
    // switch to the other one and back.
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<LoginController>(
          create: (_) => LoginController(repository),
        ),
        ChangeNotifierProvider<RegisterController>(
          create: (_) => RegisterController(repository),
        ),
      ],
      child: _AuthView(initialTab: initialTab),
    );
  }
}

class _AuthView extends StatefulWidget {
  const _AuthView({required this.initialTab});

  final AuthTab initialTab;

  @override
  State<_AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<_AuthView>
    with SingleTickerProviderStateMixin {
  static const Duration _switchDuration = Duration(milliseconds: 280);

  /// The entrance (2026-09-29): the SUGO lockup settles in and the white
  /// sheet pops up from below with a small overshoot, like a sheet being
  /// handed to you - the answer to "Get started" on the splash, rather than a
  /// plain cross-fade into a form.
  ///
  /// Plays once each time sign-in appears: after the splash, and after a
  /// sign-out. Not on switching between log in and register - that has its
  /// own sideways transition. A still frame under reduced motion.
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enter.isAnimating || _enter.isCompleted) return;
    if (AppMotion.reduced(context)) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  late AuthTab _tab = widget.initialTab;

  /// Which way the forms travel: register arrives from the right, login from
  /// the left.
  bool _towardsRegister = true;

  void _switchTo(AuthTab tab) {
    if (_tab == tab) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _towardsRegister = tab == AuthTab.register;
      _tab = tab;
    });
  }

  /// Sizes the transition box to the incoming child rather than the larger of
  /// the two, so the sheet eases between form heights instead of snapping.
  static Widget _stackToCurrent(
    Widget? currentChild,
    List<Widget> previousChildren,
  ) {
    return Stack(
      alignment: Alignment.topCenter,
      children: <Widget>[
        for (final Widget child in previousChildren)
          Positioned(top: 0, left: 0, right: 0, child: child),
        if (currentChild != null) currentChild,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Requests in flight lock the switch so a pending sign-in cannot have its
    // form swapped out from under it.
    final bool isBusy =
        context.watch<LoginController>().isBusy ||
        context.watch<RegisterController>().isSubmitting;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status-bar icons over the navy header.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              // Keeps the layout readable on tablet and desktop.
              constraints: const BoxConstraints(maxWidth: 480),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints box) {
                  final double headerHeight = AuthHeader.heightFor(
                    box.maxWidth,
                  );
                  return AnimatedBuilder(
                    animation: _enter,
                    // Built once and moved, not rebuilt on every frame.
                    child: _sheet(isBusy),
                    builder: (BuildContext context, Widget? sheet) {
                      final double t = _enter.value;
                      // The lockup takes the first half; the sheet rises over
                      // the whole, overshooting a touch at the top.
                      final double header = AppMotion.standard.transform(
                        (t / 0.55).clamp(0.0, 1.0),
                      );
                      final double rise = AppMotion.playful.transform(t);
                      final double drop =
                          (1 - rise) * MediaQuery.sizeOf(context).height * 0.45;
                      return Stack(
                        children: <Widget>[
                          // Navy behind the sheet, seen only while it is on
                          // its way up: once it lands, the header and the
                          // sheet cover every pixel of it. Without it the
                          // white sheet would rise over a white page and the
                          // entrance would be invisible.
                          const Positioned.fill(
                            child: ColoredBox(color: AppColors.navy),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Opacity(
                              opacity: header,
                              child: Transform.scale(
                                scale: 0.94 + 0.06 * header,
                                child: AuthHeader(height: headerHeight),
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.only(
                              top: headerHeight - AuthHeader.sheetOverlap,
                            ),
                            child: Transform.translate(
                              offset: Offset(0, drop),
                              child: Opacity(
                                opacity: (t / 0.3).clamp(0.0, 1.0),
                                child: sheet,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheet(bool isBusy) {
    final bool login = _tab == AuthTab.login;

    return Container(
      // At least the rest of the screen, so the white runs to the bottom
      // edge even under a short form.
      constraints: BoxConstraints(
        minHeight:
            MediaQuery.sizeOf(context).height -
            AuthHeader.heightFor(MediaQuery.sizeOf(context).width) +
            AuthHeader.sheetOverlap,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.cardRadius + 4),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSizes.screenPadding + AppSizes.xs,
        AppSizes.xl,
        AppSizes.screenPadding + AppSizes.xs,
        AppSizes.lg + MediaQuery.paddingOf(context).bottom,
      ),
      child: AnimatedSize(
        duration: _switchDuration,
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: _switchDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: _stackToCurrent,
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: animation.drive(
                  Tween<Offset>(
                    begin: Offset(_towardsRegister ? 0.06 : -0.06, 0),
                    end: Offset.zero,
                  ),
                ),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<AuthTab>(_tab),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  login ? 'Welcome back' : 'Create your account',
                  style: AppTextStyles.headline,
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  login
                      ? 'Log in to book a trusted technician.'
                      : 'Join SUGO and get matched with verified technicians.',
                  style: AppTextStyles.subtitle,
                ),
                const SizedBox(height: AppSizes.xl),
                if (login)
                  LoginForm(
                    key: const ValueKey<String>('login-form'),
                    onSwitchTab: _switchTo,
                  )
                else
                  RegisterForm(
                    key: const ValueKey<String>('register-form'),
                    onSwitchTab: _switchTo,
                  ),
                const SizedBox(height: AppSizes.lg),
                AuthFooterPrompt(
                  message: login ? AppStrings.noAccount : AppStrings.hasAccount,
                  actionLabel: login
                      ? AppStrings.switchToRegister
                      : AppStrings.loginCta,
                  onAction: isBusy
                      ? null
                      : () => _switchTo(
                          login ? AuthTab.register : AuthTab.login,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
