import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/utils/network_errors.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';

/// Telling a dead connection from a refusal, and the phone-made job id that
/// keeps a retried post from being saved twice (2026-11-23).
void main() {
  group('looksLikeNetworkError', () {
    test('timeouts and the usual network failures count', () {
      expect(looksLikeNetworkError(TimeoutException('slow')), isTrue);
      expect(
        looksLikeNetworkError(Exception('ClientException: Failed to fetch')),
        isTrue,
      );
      expect(
        looksLikeNetworkError(
          Exception('SocketException: Failed host lookup: x.supabase.co'),
        ),
        isTrue,
      );
      expect(
        looksLikeNetworkError(Exception('XMLHttpRequest error.')),
        isTrue,
      );
    });

    test('a refusal does not', () {
      expect(looksLikeNetworkError(Exception('permission denied')), isFalse);
      expect(looksLikeNetworkError(StateError('bad state')), isFalse);
    });
  });

  group('newUuidV4', () {
    final RegExp v4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test('is a well-formed version 4 UUID', () {
      for (int seed = 0; seed < 50; seed++) {
        expect(newUuidV4(math.Random(seed)), matches(v4));
      }
      expect(newUuidV4(), matches(v4));
    });

    test('differs every time', () {
      final Set<String> ids = <String>{
        for (int i = 0; i < 200; i++) newUuidV4(),
      };
      expect(ids.length, 200);
    });
  });

  group('JobDraft.requestId', () {
    test('goes into the insert only when set', () {
      // A classified draft: the insert needs a device and a symptom.
      final JobDraft draft = JobDraft()
        ..deviceType = DeviceType.laptop
        ..problemSymptom = 'laptop_overheating';
      expect(draft.toInsert(clientId: 'c').containsKey('id'), isFalse);

      draft.requestId = 'job-id-1';
      expect(draft.toInsert(clientId: 'c')['id'], 'job-id-1');
      // An edit never changes a job's id.
      expect(draft.toUpdate().containsKey('id'), isFalse);
    });
  });
}
