/// Named route constants, so route strings are never typed by hand.
class AppRoutes {
  const AppRoutes._();

  static const String root = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String home = '/home';

  /// RB-CARS entry point. The rest of the matching flow is pushed directly
  /// rather than named, because those screens need a job id or a match and a
  /// named route can only carry loosely-typed arguments.
  static const String postJob = '/post-job';
}
