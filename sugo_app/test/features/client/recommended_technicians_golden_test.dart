import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/constants/app_colors.dart';
import 'package:sugo_app/core/constants/app_sizes.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/client/widgets/recommended_technicians.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/models/technician.dart';
import 'package:sugo_app/features/rb_cars/models/technician_specialization.dart';
import 'package:sugo_app/features/rb_cars/providers/technician_directory_provider.dart';
import 'package:sugo_app/features/rb_cars/services/technician_directory_service.dart';

/// Renders the recommended row for design review. Regenerate after intentional
/// changes:
///
///   flutter test --update-goldens
///
/// The four cards are the four states the row has to survive:
///
/// 1. Everything known - a registered specialisation from
///    `technician_specializations`, a distance and a job count.
/// 2. Nothing registered and no location: the specialisation line falls back
///    through the coarse columns, and the distance line is dropped rather than
///    left blank or guessed at.
/// 3. An assessment-track wire (`network_surveillance`), which used to render
///    raw, underscores and all.
/// 4. A brand-new technician: no jobs, no rating. This is the one the card has
///    to handle without saying "0.0" or "0 jobs" - it shows the New badge, a
///    New rating pill and "No jobs yet".
///
/// Goldens are platform-specific; regenerate if they fail on another machine.
void main() {
  testWidgets('recommended technicians, three known-data states', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(820, 560);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final TechnicianDirectoryProvider provider = TechnicianDirectoryProvider(
      service: _StubDirectory(),
    );
    addTearDown(provider.dispose);
    await provider.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                RecommendedTechnicians(provider: provider, onSelect: (_) {}),
                const SizedBox(height: AppSizes.lg),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../goldens/recommended_technicians.png'),
    );
  });
}

/// Returns fixed rows, so the golden does not depend on a backend or a clock.
class _StubDirectory implements TechnicianDirectoryService {
  @override
  Future<List<Technician>> recommended({
    int limit = 10,
    double? latitude,
    double? longitude,
  }) async {
    return <Technician>[
      Technician(
        id: 't1',
        fullName: 'Lance D.',
        specialization: const <String>['refrigeration'],
        skillTags: const <String>['aircon', 'washing_machine', 'refrigerator'],
        tier: TechnicianTier.pro,
        isVerified: true,
        rating: 4.9,
        reviewCount: 18,
        totalJobs: 24,
        distanceKm: 3.4,
        memberSince: DateTime(2024, 3, 14),
        // What the RPC sends: the specific registered row, so the card says
        // "Aircon Repair" rather than falling back to a coarse label.
        primaryDeviceType: 'aircon',
        primaryBrand: 'Samsung',
        registeredSpecializations: const <TechnicianSpecialization>[
          TechnicianSpecialization(
            deviceType: 'aircon',
            brand: 'Samsung',
            skillLevel: 'expert',
            verified: true,
          ),
        ],
      ),
      // The barest account the directory can return: verified, but nothing
      // declared and no location to measure from. Exactly the state the real
      // `vance` account is in, and the one the card has to degrade into
      // without a blank slot or a guessed number.
      Technician(
        id: 't2',
        fullName: 'Vance R.',
        isVerified: true,
        rating: 4.8,
        totalJobs: 16,
        memberSince: DateTime(2026, 8, 2),
      ),
      const Technician(
        id: 't3',
        fullName: 'Jomar S.',
        specialization: <String>['network_surveillance'],
        skillTags: <String>['router', 'cctv'],
        tier: TechnicianTier.elite,
        isVerified: true,
        rating: 4.7,
        reviewCount: 41,
        totalJobs: 32,
        distanceKm: 0.65,
      ),
      // Verified, qualified, and nothing completed yet. Ranked last by the RPC
      // because the ordering is rating then job count, but still listed.
      const Technician(
        id: 't4',
        fullName: 'Rhea M.',
        isVerified: true,
        totalJobs: 0,
        distanceKm: 2.1,
        primaryDeviceType: 'laptop',
        primaryBrand: 'Lenovo',
        registeredSpecializations: <TechnicianSpecialization>[
          TechnicianSpecialization(
            deviceType: 'laptop',
            brand: 'Lenovo',
            verified: true,
          ),
        ],
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
