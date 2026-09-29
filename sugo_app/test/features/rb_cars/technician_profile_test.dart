import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/rb_cars/models/technician.dart';

/// The three profile facts the technician cards show, and the fabrication that
/// used to sit behind one of them.
void main() {
  Technician tech({
    DateTime? memberSince,
    List<String> specialization = const <String>[],
    List<String> skillTags = const <String>[],
    double? distanceKm,
  }) {
    return Technician(
      id: 't1',
      fullName: 'Lance D.',
      memberSince: memberSince,
      specialization: specialization,
      skillTags: skillTags,
      distanceKm: distanceKm,
    );
  }

  group('tenure states what created_at actually says', () {
    test('an unknown join date claims nothing', () {
      // The getter this replaced returned "1 year" here, so a technician whose
      // created_at never arrived was advertised as a year-long member on the
      // one screen where the client is deciding who to trust.
      expect(tech().memberSinceLabel, isNull);
      expect(tech().tenureLabel, isNull);
    });

    test('a brand-new account is not rounded up to a year', () {
      final Technician fresh = tech(
        memberSince: DateTime.now().subtract(const Duration(days: 3)),
      );
      expect(fresh.tenureLabel, 'New this week');
    });

    test('tenure steps through weeks, months and years', () {
      String? at(int days) => tech(
        memberSince: DateTime.now().subtract(Duration(days: days)),
      ).tenureLabel;

      expect(at(20), '2 weeks');
      expect(at(100), '3 months');
      expect(at(400), '13 months');
      expect(at(800), '2 years');
    });

    test('the join date is rendered as month and year', () {
      final Technician joined = tech(memberSince: DateTime(2026, 3, 14));
      expect(joined.memberSinceLabel, 'Mar 2026');
    });
  });

  group('headline names what they repair', () {
    test('a declared specialization wins', () {
      expect(
        tech(specialization: <String>['laptop']).headline,
        'Laptop / PC specialist',
      );
    });

    test('an assessment-track wire reads as its track name', () {
      // `submit-assessment` writes `specialization: [bank]`, where bank is a
      // track wire. The card was printing these raw, underscores and all -
      // "appliance_repair specialist" was on screen in the running app.
      expect(
        tech(specialization: <String>['computer_repair']).headline,
        'Computer repair specialist',
      );
      expect(
        tech(specialization: <String>['network_surveillance']).headline,
        'Network and CCTV specialist',
      );
    });

    test('a track nobody catalogued is still de-underscored', () {
      expect(
        tech(specialization: <String>['appliance_repair']).headline,
        'Appliance repair specialist',
      );
    });

    test('a catalogue device wire reads as its device name', () {
      expect(
        tech(specialization: <String>['aircon']).headline,
        'Aircon specialist',
      );
    });

    test('skill tags stand in when specialization is empty', () {
      // Previously this said "General repair technician", which is both wrong
      // and the least useful thing the line could say.
      expect(
        tech(skillTags: <String>['washing_machine']).headline,
        'Washing machine specialist',
      );
    });

    test('two areas read as a pair, more than two are summarised', () {
      expect(
        tech(specialization: <String>['laptop', 'phone']).headline,
        'Laptop / PC and Phone / Tablet repair',
      );
      expect(
        tech(specialization: <String>['laptop', 'phone', 'appliance']).headline,
        'Laptop / PC, Phone / Tablet and more',
      );
    });

    test('nothing declared is the only case that says general', () {
      expect(tech().headline, 'General repair technician');
    });
  });

  group('distance is shown only when the server worked one out', () {
    test('no distance means no label, never a zero', () {
      expect(tech().distanceLabel, isNull);
    });

    test('under a kilometre reads in metres, to the nearest ten', () {
      expect(tech(distanceKm: 0.85).distanceLabel, '850 m');
      // The directory rounds to 10 m, so printing 106 would be false
      // precision on a figure that was already rounded upstream.
      expect(tech(distanceKm: 0.106).distanceLabel, '110 m');
    });

    test('closer than the resolution reads as Nearby, not 0 m', () {
      expect(tech(distanceKm: 0.004).distanceLabel, 'Nearby');
      expect(tech(distanceKm: 0).distanceLabel, 'Nearby');
    });

    test('a kilometre or more reads to one decimal', () {
      expect(tech(distanceKm: 1.24).distanceLabel, '1.2 km');
      expect(tech(distanceKm: 12).distanceLabel, '12.0 km');
    });

    test('distance survives copyWith, which the vacation merge uses', () {
      expect(
        tech(distanceKm: 3.4).copyWith(awayUntil: DateTime(2026, 9, 27)).distanceKm,
        3.4,
      );
    });
  });

  group('parsing', () {
    test('distance_km and created_at come off the directory payload', () {
      final Technician parsed = Technician.fromJson(<String, dynamic>{
        'id': 't1',
        'created_at': '2026-03-14T00:00:00Z',
        'distance_km': 1.2,
        'profiles': <String, dynamic>{'full_name': 'Lance D.'},
      });

      expect(parsed.memberSinceLabel, 'Mar 2026');
      expect(parsed.distanceLabel, '1.2 km');
    });

    test('a payload with no distance leaves the field null', () {
      final Technician parsed = Technician.fromJson(<String, dynamic>{
        'id': 't1',
        'profiles': <String, dynamic>{'full_name': 'Lance D.'},
      });

      expect(parsed.distanceKm, isNull);
      expect(parsed.distanceLabel, isNull);
    });
  });
}
