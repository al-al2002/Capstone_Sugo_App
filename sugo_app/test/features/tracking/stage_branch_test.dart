import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/tracking/models/job_tracking.dart';

/// The tracking flow forks after the repair, and ordinal order cannot say so.
///
/// `next` used to be `values[index + 1]` and the timeline walked
/// `TrackingStage.values`. Both assume the stages are a straight line. Adding
/// `readyForCollection` broke that assumption in a way that fails silently
/// rather than loudly: the enum still compiles, the screens still render, and
/// the client is simply shown the wrong journey.
void main() {
  group('the post-repair branch', () {
    test('in_repair offers both endings, and nothing else does', () {
      expect(TrackingStage.inRepair.nextOptions, <TrackingStage>[
        TrackingStage.outForDelivery,
        TrackingStage.readyForCollection,
      ]);

      // Every other stage has exactly one way forward, except the last.
      for (final TrackingStage stage in TrackingStage.values) {
        if (stage == TrackingStage.inRepair) continue;
        expect(
          stage.nextOptions.length,
          stage == TrackingStage.delivered ? 0 : 1,
          reason: '${stage.wire} should not branch',
        );
      }
    });

    test('next is null at the fork, so a caller cannot pick silently', () {
      // The delivery screen used to read `next` and show one button. If that
      // still returned a stage here it would quietly choose delivery on the
      // technician's behalf, and a client expecting to collect their own
      // laptop would be told it was on its way to them.
      expect(TrackingStage.inRepair.next, isNull);
      expect(TrackingStage.collected.next, TrackingStage.returningToShop);
      expect(TrackingStage.delivered.next, isNull);
    });

    test('both routes converge on delivered', () {
      expect(TrackingStage.outForDelivery.nextOptions, <TrackingStage>[
        TrackingStage.delivered,
      ]);
      expect(TrackingStage.readyForCollection.nextOptions, <TrackingStage>[
        TrackingStage.delivered,
      ]);
    });
  });

  group('the timeline', () {
    test('shows one ending, never both', () {
      for (final TrackingStage stage in TrackingStage.values) {
        final List<TrackingStage> steps = TrackingStage.timelineFor(stage);
        expect(steps.length, 6, reason: 'both routes are the same length');
        expect(
          steps.contains(TrackingStage.outForDelivery) &&
              steps.contains(TrackingStage.readyForCollection),
          isFalse,
          reason: 'drawing both would promise a trip that is not happening',
        );
      }
    });

    test('a collection journey never shows a delivery step', () {
      final List<TrackingStage> steps = TrackingStage.timelineFor(
        TrackingStage.readyForCollection,
      );
      expect(steps.contains(TrackingStage.readyForCollection), isTrue);
      expect(steps.contains(TrackingStage.outForDelivery), isFalse);
    });

    test('progress is measured by position in the route, not enum index', () {
      // The trap: `readyForCollection` sits AFTER `outForDelivery` in the enum,
      // so comparing enum indices would mark "Out for delivery" as already
      // completed on a job that is sitting on a shelf waiting to be collected.
      final List<TrackingStage> steps = TrackingStage.timelineFor(
        TrackingStage.readyForCollection,
      );
      expect(
        steps.indexOf(TrackingStage.readyForCollection),
        4,
        reason: 'it is the fifth step of its own route',
      );
      expect(
        TrackingStage.readyForCollection.index,
        greaterThan(TrackingStage.outForDelivery.index),
        reason: 'which is exactly why enum index must not be used',
      );
    });
  });

  group('who chooses the ending', () {
    test('the client is asked exactly once, on the bench', () {
      // The fork belongs to the client, and the window is `in_repair`: before
      // it there is nothing to bring back, and after it the unit has been
      // moved - `set_return_method()` refuses a switch to delivery once it is
      // `ready_for_collection`. Widening this would put the question where
      // the server would reject the answer.
      final List<TrackingStage> asking = TrackingStage.values
          .where((TrackingStage s) => s.asksReturnChoice)
          .toList();

      expect(asking, <TrackingStage>[TrackingStage.inRepair]);
    });

    test('the stage that asks is the stage that branches', () {
      // These two must move together. If a future stage gained a second exit
      // without also asking the client, the technician's screen would be back
      // to picking the ending on their behalf.
      for (final TrackingStage stage in TrackingStage.values) {
        expect(
          stage.nextOptions.length > 1,
          stage.asksReturnChoice,
          reason: '${stage.wire}: a fork must be the client\'s to resolve',
        );
      }
    });
  });

  test('a waiting unit is not travelling', () {
    // `showsMap` gates live location sharing. If this flipped, the technician
    // would be asked to broadcast their position for as long as the appliance
    // sat on a shelf.
    expect(TrackingStage.readyForCollection.showsMap, isFalse);
    expect(TrackingStage.readyForCollection.isOutboundLeg, isFalse);
    expect(TrackingStage.readyForCollection.isAwaitingCollection, isTrue);
  });
}
