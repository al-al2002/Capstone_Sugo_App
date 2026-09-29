/// Form validation shared by the auth screens.
///
/// Every validator returns `null` when the value is acceptable, which matches
/// the contract Flutter expects from a FormFieldValidator.
class Validators {
  const Validators._();

  static const int minPasswordLength = 8;

  static final RegExp _emailPattern = RegExp(
    r'^[\w.+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$',
  );

  /// Philippine mobile numbers in local form only: 09XXXXXXXXX.
  ///
  /// Exactly eleven digits, no separators, no country code. The international
  /// forms (+639..., 639...) were accepted before and are deliberately not
  /// any more: one shape on the way in means the field, the formatter and the
  /// error message can all describe the same thing, and [normalizePhone] still
  /// converts to E.164 for storage. Nothing downstream sees the difference.
  static final RegExp _phonePattern = RegExp(r'^09\d{9}$');

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$field is required';
    }
    return null;
  }

  static String? fullName(String? value) {
    final String name = value?.trim() ?? '';
    if (name.isEmpty) return 'Full name is required';
    if (name.length < 3) return 'Please enter your full name';
    return null;
  }

  static String? email(String? value) {
    final String email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email address is required';
    if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  static String? phone(String? value) {
    final String phone = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');

    if (phone.isEmpty) return 'Mobile number is required';

    // Separated from the pattern check so the message names the actual fault.
    // "Use 09XXXXXXXXX" is useless to someone who typed 10 digits correctly -
    // they need to be told they are one short.
    if (!RegExp(r'^\d+$').hasMatch(phone)) {
      return 'Numbers only - no spaces, dashes or +63';
    }
    if (!phone.startsWith('09')) {
      return 'A Philippine mobile number starts with 09';
    }
    if (phone.length != 11) {
      return 'That is ${phone.length} digits. A mobile number has 11';
    }
    if (!_phonePattern.hasMatch(phone)) {
      return 'Enter a valid mobile number, like 09171234567';
    }
    return null;
  }

  static String? password(String? value) {
    final String password = value ?? '';
    if (password.isEmpty) return 'Password is required';
    if (password.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters';
    }
    if (!password.contains(RegExp(r'[A-Za-z]')) ||
        !password.contains(RegExp(r'\d'))) {
      return 'Include at least one letter and one number';
    }
    return null;
  }

  /// Login only checks that a password was entered. Strength rules belong to
  /// registration, otherwise older accounts could be locked out of their own
  /// app by a later policy change.
  static String? loginPassword(String? value) {
    if ((value ?? '').isEmpty) return 'Password is required';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Please confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }

  /// Normalises a local mobile number to E.164 before it is stored.
  static String normalizePhone(String value) {
    final String digits = value.replaceAll(RegExp(r'[\s-]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('09')) return '+63${digits.substring(1)}';
    if (digits.startsWith('639')) return '+$digits';
    return digits;
  }
}
