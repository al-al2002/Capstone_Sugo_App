import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/session/session_state.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../client/screens/client_dashboard_screen.dart';
import '../../../onboarding/models/registration_status.dart';
import '../../../onboarding/screens/registration_entry_screen.dart';
import '../../../onboarding/widgets/onboarding_scaffold.dart';
import '../../../technician/screens/technician_dashboard_screen.dart';
import '../../../technician/screens/technician_onboarding_screen.dart';
import '../controllers/auth_controller.dart';
import 'auth_screen.dart';
import 'registration_flow_screen.dart';
import 'splash_view.dart';
import '../../../profile/screens/profile_setup_screen.dart';

/// The one place that decides where a signed-in user lands.
///
/// ## Why the role check lives here and nowhere else
///
/// Client and technician have completely separate dashboards, so something has
/// to choose between them. Putting that choice in each screen's `initState`, or
/// re-querying the role wherever it is needed, is how apps end up with three
/// slightly different answers to "is this person a technician?".
///
/// Instead the rule lives in `SessionProfile.destination`, the data behind it
/// in `SessionController`, and the rendering of the result here. Every other
/// screen simply trusts that it was routed correctly and never re-checks.
///
/// The gate rebuilds whenever either controller notifies, so a sign-out, a
/// sign-in, or a verification that clears mid-session all move the user without
/// any screen coordinating it.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Whether the launch animation has finished having its say.
  ///
  /// Seeded from `SplashView.hasPlayed` so a hot restart mid-session, or any
  /// later rebuild of the gate, does not replay the overture.
  late bool _splashDone = SplashView.hasPlayed;

  void _onSplashFinished() {
    if (mounted && !_splashDone) setState(() => _splashDone = true);
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final SessionController session = context.watch<SessionController>();

    // Hold the splash until it says it is done. It waits for Supabase to
    // restore (or reject) the persisted session - without that a signed-in
    // user would see the login screen flash before their dashboard - and for
    // its short loading animation, then either lets a signed-in user straight
    // through or offers a signed-out one "Get started". `SplashView` explains
    // the timing and its cost.
    final Widget destination = _destinationFor(auth, session);

    return AnimatedSwitcher(
      duration: AppMotion.page,
      switchInCurve: AppMotion.emphasized,
      switchOutCurve: AppMotion.standard,
      // The splash does not slide away - it settles, brightens and the next
      // screen comes up through it. A push transition here would make the
      // launch feel like a navigation the user performed.
      transitionBuilder: (Widget child, Animation<double> animation) {
        final bool leaving = child.key == const ValueKey<String>('splash');
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(
              // Outgoing, the artwork eases *towards* the viewer; incoming,
              // the next screen rises to meet it.
              begin: leaving ? 1.06 : 0.99,
              end: 1,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: destination,
    );
  }

  Widget _destinationFor(AuthController auth, SessionController session) {
    if (!auth.isInitialized || !_splashDone) {
      return SplashView(
        key: const ValueKey<String>('splash'),
        ready: auth.isInitialized,
        signedIn: auth.isAuthenticated,
        onFinished: _onSplashFinished,
      );
    }
    if (!auth.isAuthenticated) {
      return const _SignedOut(key: ValueKey<String>('signed-out'));
    }

    return KeyedSubtree(
      key: ValueKey<String>('dest:${session.destination.name}'),
      child: _landing(session),
    );
  }

  Widget _landing(SessionController session) {
    return switch (session.destination) {
      LandingDestination.loading => const SplashView(),
      LandingDestination.auth => const _SignedOut(),
      LandingDestination.registration => const RegistrationFlowScreen(),

      // All three unfinished states resolve through the same entry screen: it
      // settles the role if that is still open, then hands off to that role's
      // stepper, which resumes at the saved step.
      LandingDestination.roleSelection ||
      LandingDestination.technicianRegistration ||
      LandingDestination.clientRegistration => const RegistrationEntryScreen(),

      // Nothing for the user to do until an admin rules.
      LandingDestination.pendingReview => const PendingReviewScreen(
        status: RegistrationStatus.pendingReview,
      ),

      // Once, after approval. Saving or skipping stamps the account and the
      // next refresh routes past this to the dashboard.
      LandingDestination.profileSetup => const ProfileSetupScreen.firstRun(),
      LandingDestination.clientDashboard => const ClientDashboardScreen(),
      LandingDestination.technicianOnboarding =>
        const TechnicianOnboardingScreen(),
      LandingDestination.technicianDashboard =>
        const TechnicianDashboardScreen(),
    };
  }
}

/// Where a signed-out user lands: sign-in.
///
/// There used to be a four-slide intro carousel here on first launch. It was
/// removed (2026-09-27): the splash poster already introduces the brand and
/// its "Get started" leads here, and a second screen of explanation before
/// sign-in only delayed people who had already decided to install the app.
class _SignedOut extends StatelessWidget {
  const _SignedOut({super.key});

  @override
  Widget build(BuildContext context) => const AuthScreen();
}
