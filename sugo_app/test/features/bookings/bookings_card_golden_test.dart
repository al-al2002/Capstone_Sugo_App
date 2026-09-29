import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/constants/app_colors.dart';
import 'package:sugo_app/core/constants/app_sizes.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/bookings/screens/bookings_list_view.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/job_party.dart';

/// Renders the bookings list for design review. Regenerate after intentional
/// changes:
///
///   flutter test --update-goldens
///
/// `BookingsListView` loads from Supabase in `initState`, so the golden poses
/// the pieces it is built from - the title, the segmented filter and the cards
/// in their three interesting states - rather than the whole screen. The states
/// are what matter here: a confirmed booking with a named technician, a
/// pending one with nobody yet, and a completed one showing the stars the
/// client gave - real filled stars, not the grey characters it used to be.
///
/// Goldens are platform-specific; regenerate if they fail on another machine.
void main() {
  testWidgets('bookings list, three card states', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(820, 1740);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const BookingsTitle(title: 'Bookings'),
                const BookingFilterTabs(
                  selected: BookingFilter.active,
                  onChanged: _ignore,
                ),
                const SizedBox(height: AppSizes.md),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.screenPadding,
                    ),
                    children: <Widget>[
                      BookingCard(
                        job: _confirmed,
                        role: BookingsRole.client,
                        party: _confirmedParty,
                        onReturn: _noop,
                      ),
                      BookingCard(
                        job: _pending,
                        role: BookingsRole.client,
                        onReturn: _noop,
                      ),
                      BookingCard(
                        job: _done,
                        role: BookingsRole.client,
                        party: _doneParty,
                        onReturn: _noop,
                        onRate: () {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // A fixed frame rather than `pumpAndSettle`. Since the 2026-09 redesign a
    // booking that is still live carries a pulsing status dot, and an
    // animation that repeats for ever never settles - `pumpAndSettle` times
    // out. Animations are deterministic in tests, so pumping a set duration
    // captures the same frame every run.
    await tester.pump(const Duration(milliseconds: 700));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../goldens/bookings_list.png'),
    );
  });
}

void _ignore(BookingFilter _) {}

Future<void> _noop() async {}

final Job _confirmed = Job(
  id: 'a3f2b1c4-0000-0000-0000-000000000001',
  clientId: 'client-1',
  deviceType: DeviceType.appliance,
  problemSymptom: 'appliance_aircon_not_cooling',
  hasPhysicalDamage: false,
  status: JobStatus.confirmed,
  assignedTechnicianId: 'tech-1',
  preferredSchedule: DateTime(2026, 12, 9, 8),
);

const Job _pending = Job(
  id: 'd571224a-0000-0000-0000-000000000002',
  clientId: 'client-1',
  deviceType: DeviceType.laptop,
  problemSymptom: 'laptop_wont_power_on',
  hasPhysicalDamage: false,
  status: JobStatus.pending,
);

final Job _done = Job(
  id: 'bb90f31e-0000-0000-0000-000000000003',
  clientId: 'client-1',
  deviceType: DeviceType.network,
  problemSymptom: 'cctv_no_video',
  hasPhysicalDamage: false,
  status: JobStatus.completed,
  assignedTechnicianId: 'tech-2',
  preferredSchedule: DateTime(2026, 11, 28, 14, 30),
);

const JobParty _confirmedParty = JobParty(
  jobId: 'a3f2b1c4-0000-0000-0000-000000000001',
  clientId: 'client-1',
  clientName: 'Maria Santos',
  technicianId: 'tech-1',
  technicianName: 'Lance Villanueva',
);

const JobParty _doneParty = JobParty(
  jobId: 'bb90f31e-0000-0000-0000-000000000003',
  clientId: 'client-1',
  clientName: 'Maria Santos',
  technicianId: 'tech-2',
  technicianName: 'Lyra Dizon',
  myRating: 4,
);
