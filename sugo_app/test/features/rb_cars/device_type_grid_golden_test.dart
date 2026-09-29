import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/constants/app_sizes.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/device_category.dart';
import 'package:sugo_app/features/rb_cars/widgets/device_type_grid.dart';
import 'package:sugo_app/core/constants/app_colors.dart';

/// Renders the device picker for design review. Regenerate after intentional
/// changes:
///
///   flutter test --update-goldens
///
/// The glyphs are painted, not assets, so this golden is the only thing that
/// notices if a path drifts: a stroke width typo or a mispositioned lens still
/// compiles and still passes every behavioural test.
///
/// Goldens are platform-specific; regenerate if they fail on another machine.
void main() {
  testWidgets('device picker, unselected and with CCTV chosen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(780, 1560);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.screenPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DeviceTypeGrid(selected: null, onSelect: (_) {}),
                const SizedBox(height: AppSizes.xl),
                DeviceTypeGrid(selected: DeviceCategory.cctv, onSelect: (_) {}),
              ],
            ),
          ),
        ),
      ),
    );

    // The glyph tint is tweened, so settle before capturing or the selected
    // card is caught mid-fade.
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../goldens/device_type_grid.png'),
    );
  });
}
