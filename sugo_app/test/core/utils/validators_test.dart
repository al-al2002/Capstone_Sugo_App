import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('accepts a well-formed address', () {
      expect(Validators.email('juan.delacruz@umindanao.edu.ph'), isNull);
    });

    test('rejects empty and malformed addresses', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('juan@'), isNotNull);
      expect(Validators.email('juan@sugo'), isNotNull);
      expect(Validators.email('juan.sugo.com'), isNotNull);
    });
  });

  group('Validators.phone', () {
    test('accepts the local form only', () {
      expect(Validators.phone('09171234567'), isNull);
    });

    test('rejects the international forms it used to accept', () {
      // Deliberate narrowing. One shape on the way in lets the field, the
      // formatter and the error message all describe the same thing;
      // `normalizePhone` still converts to E.164 before storage.
      expect(Validators.phone('639171234567'), isNotNull);
      expect(Validators.phone('+639171234567'), isNotNull);
    });

    test('rejects a wrong length or prefix', () {
      expect(Validators.phone('0917123456'), isNotNull);
      expect(Validators.phone('091712345678'), isNotNull);
      expect(Validators.phone('08171234567'), isNotNull);
    });

    test('the message names the actual fault', () {
      expect(Validators.phone('0917-123-456x'), contains('Numbers only'));
      expect(Validators.phone('08171234567'), contains('starts with 09'));
      expect(Validators.phone('0917123456'), contains('10 digits'));
      expect(Validators.phone(''), contains('required'));
    });
  });

  group('Validators.password', () {
    test('requires length plus a letter and a digit', () {
      expect(Validators.password('sugo1234'), isNull);
      expect(Validators.password('sugo12'), isNotNull);
      expect(Validators.password('sugopassword'), isNotNull);
      expect(Validators.password('12345678'), isNotNull);
    });

    test('login only requires a non-empty value', () {
      expect(Validators.loginPassword('x'), isNull);
      expect(Validators.loginPassword(''), isNotNull);
    });
  });

  group('Validators.confirmPassword', () {
    test('must match the original', () {
      expect(Validators.confirmPassword('sugo1234', 'sugo1234'), isNull);
      expect(Validators.confirmPassword('sugo1234', 'sugo4321'), isNotNull);
    });
  });

  group('Validators.normalizePhone', () {
    test('converts local formats to E.164', () {
      expect(Validators.normalizePhone('09171234567'), '+639171234567');
      expect(Validators.normalizePhone('639171234567'), '+639171234567');
      expect(Validators.normalizePhone('+639171234567'), '+639171234567');
      expect(Validators.normalizePhone('0917 123 4567'), '+639171234567');
    });
  });
}
