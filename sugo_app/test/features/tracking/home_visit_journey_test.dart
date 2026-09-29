import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/tracking/models/job_tracking.dart';

/// Home visits share the tracking table with workshop pickups (2026-09-29).
///
/// These pin the two things that make sharing safe: a home visit gets its own
/// short route and its own words, and a workshop pickup gets exactly what it
/// had before.
void main() {
  group('which journey a job is on', () {
    test('home service is a home visit; a pickup is the workshop', () {
      expect(
        TrackingJourney.of(ServicePath.homeService),
        TrackingJourney.homeVisit,
      );
      expect(TrackingJourney.of(ServicePath.pickup), TrackingJourney.workshop);
    });

    test('a community diagnosis has no trip to follow', () {
      expect(TrackingJourney.tracks(ServicePath.homeService), isTrue);
      expect(TrackingJourney.tracks(ServicePath.pickup), isTrue);
      expect(TrackingJourney.tracks(ServicePath.itCommunity), isFalse);
      expect(TrackingJourney.tracks(null), isFalse);
    });
  });

  group('where the map pin goes', () {
    test('the technician on the way heads to the client, not the shop', () {
      // The bug this replaced: "On the way to you" pinned the workshop.
      expect(TrackingStage.headingToPickup.headsToClient, isTrue);
      expect(TrackingStage.outForDelivery.headsToClient, isTrue);
    });

    test('the legs towards the shop, and the stationary ones, do not', () {
      for (final TrackingStage stage in <TrackingStage>[
        TrackingStage.collected,
        TrackingStage.returningToShop,
        TrackingStage.inRepair,
        TrackingStage.readyForCollection,
        TrackingStage.delivered,
      ]) {
        expect(stage.headsToClient, isFalse, reason: stage.wire);
      }
    });
  });

  group('a home visit', () {
    const TrackingJourney home = TrackingJourney.homeVisit;

    test('is two stages long: on the way, then repairing', () {
      expect(
        TrackingStage.timelineFor(TrackingStage.headingToPickup, journey: home),
        <TrackingStage>[TrackingStage.headingToPickup, TrackingStage.inRepair],
      );
    });

    test('has one move, arriving, and nothing after it', () {
      expect(TrackingStage.headingToPickup.nextOptionsOn(home), <TrackingStage>[
        TrackingStage.inRepair,
      ]);
      expect(TrackingStage.inRepair.nextOptionsOn(home), isEmpty);
    });

    test('says "your home", not "the workshop" or "collect"', () {
      expect(TrackingStage.inRepair.labelOn(home), 'Repairing at your home');
      expect(
        TrackingStage.headingToPickup.blurbOn(home),
        isNot(contains('collect')),
      );
      expect(TrackingStage.inRepair.blurbOn(home), isNot(contains('workshop')));
    });

    test('never asks how the unit should come back', () {
      expect(TrackingStage.inRepair.asksReturnChoiceOn(home), isFalse);
    });
  });

  group('a workshop pickup is unchanged', () {
    const TrackingJourney shop = TrackingJourney.workshop;

    test('same route, same moves, same words', () {
      for (final TrackingStage stage in TrackingStage.values) {
        expect(
          TrackingStage.timelineFor(stage, journey: shop),
          TrackingStage.timelineFor(stage),
          reason: stage.wire,
        );
        expect(
          stage.nextOptionsOn(shop),
          stage.nextOptions,
          reason: stage.wire,
        );
        expect(stage.labelOn(shop), stage.label, reason: stage.wire);
        expect(stage.blurbOn(shop), stage.blurb, reason: stage.wire);
        expect(
          stage.asksReturnChoiceOn(shop),
          stage.asksReturnChoice,
          reason: stage.wire,
        );
      }
    });
  });
}
