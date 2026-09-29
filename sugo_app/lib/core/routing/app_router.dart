import 'package:flutter/material.dart';

import '../../features/auth/presentation/screens/auth_gate.dart';
import '../../features/auth/presentation/screens/auth_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/widgets/auth_tab.dart';
import '../../features/rb_cars/screens/job_posting_screen.dart';
import 'app_routes.dart';

/// Maps named routes onto screens.
class AppRouter {
  const AppRouter._();

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.root:
        return _page(const AuthGate(), settings);
      case AppRoutes.login:
        return _page(const AuthScreen(), settings);
      case AppRoutes.register:
        // Same screen, opened with the register tab already selected.
        return _page(const AuthScreen(initialTab: AuthTab.register), settings);
      case AppRoutes.forgotPassword:
        return _page(const ForgotPasswordScreen(), settings);
      // `home` deliberately resolves through the gate rather than naming a
      // dashboard. Which dashboard is a role decision, and that decision lives
      // in exactly one place - `SessionController` via `AuthGate`.
      case AppRoutes.home:
        return _page(const AuthGate(), settings);
      case AppRoutes.postJob:
        return _page(const JobPostingScreen(), settings);
      default:
        return _page(const AuthGate(), settings);
    }
  }

  static MaterialPageRoute<dynamic> _page(
    Widget child,
    RouteSettings settings,
  ) {
    return MaterialPageRoute<dynamic>(
      builder: (BuildContext context) => child,
      settings: settings,
    );
  }
}
