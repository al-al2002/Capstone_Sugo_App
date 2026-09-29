import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/rb_cars/models/device_category.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/schedule_preference.dart';
import 'package:sugo_app/features/rb_cars/providers/job_posting_provider.dart';

/// The two mappings the five-screen flow added on top of the frozen schema,
/// plus the gate each step opens.
void main() {
  group('SchedulePreference maps three buttons onto two columns', () {
    // A fixed clock, so "7 days out" is an assertion rather than a race.
    final DateTime now = DateTime(2026, 9, 15, 10, 30);

    test('Flexible asks for nothing', () {
      expect(SchedulePreference.flexible.urgency, Urgency.canWait);
      expect(SchedulePreference.flexible.deadlineFrom(now), isNull);
    });

    test('This week is can_wait with a seven-day deadline', () {
      expect(SchedulePreference.thisWeek.urgency, Urgency.canWait);
      expect(
        SchedulePreference.thisWeek.deadlineFrom(now),
        DateTime(2026, 9, 22, 23, 59),
      );
    });

    test('Urgent is need_today, due end of today', () {
      expect(SchedulePreference.urgent.urgency, Urgency.needToday);
      expect(
        SchedulePreference.urgent.deadlineFrom(now),
        DateTime(2026, 9, 15, 23, 59),
      );
    });

    test('every choice writes an urgency the check constraint allows', () {
      const Set<String> storable = <String>{'need_today', 'can_wait'};
      for (final SchedulePreference choice in SchedulePreference.values) {
        expect(storable, contains(choice.urgency.wire));
      }
    });

    test('each choice reads back as itself', () {
      for (final SchedulePreference choice in SchedulePreference.values) {
        expect(
          SchedulePreference.fromJob(
            urgency: choice.urgency,
            preferredSchedule: choice.deadlineFrom(now),
          ),
          choice,
          reason:
              '${choice.name} did not survive the round trip through the two '
              'columns, so the review screen would show the wrong schedule.',
        );
      }
    });
  });

  group('three text answers become one description column', () {
    test('an untouched draft writes null, not an empty string', () {
      expect(JobDraft().composedDescription, isNull);
    });

    test('each answer is labelled and separated', () {
      final JobDraft draft = JobDraft()
        ..model = 'IdeaPad 3 14"'
        ..description = 'Will not power on.'
        ..notes = 'Available after 5pm.';

      expect(
        draft.composedDescription,
        'Model: IdeaPad 3 14"\n\n'
        'Will not power on.\n\n'
        'Notes: Available after 5pm.',
      );
    });

    test('a skipped field contributes no empty label', () {
      final JobDraft draft = JobDraft()..description = 'Screen flickers.';
      expect(draft.composedDescription, 'Screen flickers.');
    });

    test('whitespace-only answers count as skipped', () {
      final JobDraft draft = JobDraft()
        ..model = '   '
        ..description = 'Screen flickers.'
        ..notes = '\n';
      expect(draft.composedDescription, 'Screen flickers.');
    });
  });

  group('each step opens only its own gate', () {
    test('the flow unlocks one step at a time', () {
      final JobPostingProvider posting = JobPostingProvider();
      addTearDown(posting.dispose);

      expect(posting.canLeaveDevice, isFalse);

      posting.selectCategory(DeviceCategory.laptop);
      expect(posting.canLeaveDevice, isTrue);
      expect(
        posting.canLeaveSymptom,
        isFalse,
        reason: 'Step 2 should still be shut - no symptom has been chosen.',
      );

      posting.selectSymptom('laptop_wont_power_on');
      expect(
        posting.canLeaveSymptom,
        isTrue,
        reason:
            'Choosing a symptom must classify immediately, because the path '
            'cards on the same screen render from the result.',
      );
      expect(posting.draft.classification, isNotNull);

      expect(posting.canLeaveDeviceDetails, isTrue, reason: 'All optional.');
      expect(posting.canLeaveWhereAndWhen, isFalse);

      posting.setLocation(latitude: 7.0731, longitude: 125.6128);
      expect(posting.canLeaveWhereAndWhen, isTrue);
      expect(posting.canSubmit, isTrue);
    });

    test('the CCTV card pre-fills the device the detail step asks for', () {
      final JobPostingProvider posting = JobPostingProvider();
      addTearDown(posting.dispose);

      posting.selectCategory(DeviceCategory.cctv);
      expect(posting.draft.deviceDetail, 'cctv');
      expect(posting.draft.deviceType, DeviceType.network);
    });

    test(
      'switching category clears the answers that belonged to the old one',
      () {
        final JobPostingProvider posting = JobPostingProvider();
        addTearDown(posting.dispose);

        posting.selectCategory(DeviceCategory.laptop);
        posting.selectSymptom('laptop_wont_power_on');
        posting.setDeviceDetail(deviceDetail: 'laptop', brand: 'Lenovo');

        posting.selectCategory(DeviceCategory.appliance);

        expect(posting.draft.problemSymptom, isNull);
        expect(posting.draft.brand, isNull);
        expect(posting.draft.classification, isNull);
        expect(posting.canLeaveSymptom, isFalse);
      },
    );

    test('toggling damage re-runs the rules rather than clearing them', () {
      final JobPostingProvider posting = JobPostingProvider();
      addTearDown(posting.dispose);

      posting.selectCategory(DeviceCategory.laptop);
      posting.selectSymptom('laptop_wont_power_on');

      posting.setPhysicalDamage(true);

      expect(
        posting.draft.classification,
        isNotNull,
        reason:
            'Clearing the classification emptied the path cards the client '
            'was looking at when they answered.',
      );
      expect(posting.draft.hasPhysicalDamage, isTrue);
    });
  });
}
