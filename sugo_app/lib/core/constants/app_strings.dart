/// User-facing copy, kept in one place so it is easy to review or localise.
///
/// Sentence case throughout since the Dispatch redesign ("Email address",
/// not "Email Address"), like every other label in the app. The two legal
/// documents keep their capitals because they are names.
class AppStrings {
  const AppStrings._();

  static const String appName = 'SUGO';
  static const String tagline = 'Fix. Technology. Appliances.';

  // Service chips under the tagline.
  static const String chipDiagnose = 'Diagnose';
  static const String chipRepair = 'Repair';
  static const String chipDone = 'Done';

  // Login
  static const String loginTitle = 'Welcome back';
  static const String loginSubtitle = 'Log in to your SUGO account';
  static const String loginCta = 'Log in';
  static const String forgotPassword = 'Forgot password?';
  static const String noAccount = "Don't have an account? ";
  static const String switchToRegister = 'Register';
  static const String register = 'Register';

  // Register
  static const String registerTitle = 'Create an account';
  static const String registerSubtitle =
      'Sign up with SUGO and get things done';
  static const String registerCta = 'Create account';
  static const String hasAccount = 'Already have an account? ';
  static const String login = 'Log in';

  // Fields
  static const String fullName = 'Full name';
  static const String fullNameHint = 'Enter your full name';
  static const String email = 'Email address';
  static const String emailHint = 'Enter your email';
  static const String phone = 'Phone number';
  static const String phoneHint = '09XXXXXXXXX';
  static const String password = 'Password';
  static const String passwordHint = 'Enter your password';
  static const String createPasswordHint = 'Create a password';
  static const String confirmPassword = 'Confirm password';
  static const String confirmPasswordHint = 'Confirm your password';

  // Terms
  static const String agreePrefix = 'I agree to the ';
  static const String terms = 'Terms of Service';
  static const String agreeMiddle = ' and ';
  static const String privacy = 'Privacy Policy';

  // Feedback
  static const String verifyEmailSent =
      'Account created. Check your email to verify your account before logging in.';
  static const String mustAcceptTerms =
      'Please accept the Terms of Service and Privacy Policy to continue.';
}
