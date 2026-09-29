import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/constants/app_colors.dart';
import 'package:sugo_app/core/constants/app_sizes.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/widgets/budget_range_field.dart';

/// The two states of the budget slider, for design review. Regenerate after
/// intentional changes:
///
///   flutter test --update-goldens
///
/// The distinction is the whole point of this widget. An untouched slider still
/// has to draw its handles somewhere, and while they were drawn in the brand
/// blue an unset range was indistinguishable from a chosen one - clients
/// believed they had set a budget, posted the job, and found "No budget set"
/// on the booking.
///
/// So the top control is unset and must read as dormant: grey track, grey
/// thumbs, "Any budget". The bottom one is set and must read as live: blue
/// track, blue thumbs, the range spelled out, and a Clear action.
///
/// Goldens are platform-specific; regenerate if they fail on another machine.
void main() {
  testWidgets('budget slider, unset versus set', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSizes.screenPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  BudgetRangeField(
                    min: null,
                    max: null,
                    onChanged: (_, __) {},
                  ),
                  const SizedBox(height: AppSizes.xxl),
                  BudgetRangeField(
                    min: 800,
                    max: 1650,
                    onChanged: (_, __) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Any budget'), findsOneWidget);
    expect(find.text('Clear budget'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../goldens/budget_range_field.png'),
    );
  });
}
