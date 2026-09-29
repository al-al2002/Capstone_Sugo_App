import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/job.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';
import 'package:sugo_app/features/rb_cars/screens/booking_success_screen.dart';

/// Back after booking goes home, not into "post a task" (reported 2026-09-29).
///
/// A new post leaves its four steps on the stack under the shortlist. The
/// confirmation used to replace only the shortlist, so Back from it - or from
/// "View booking", which replaces the confirmation - landed on step 4 of a
/// post that had already been sent.
void main() {
  const Job job = Job(
    id: 'a3f2b1c4-0000-0000-0000-000000000001',
    clientId: 'client-1',
    deviceType: DeviceType.laptop,
    problemSymptom: 'laptop_wont_power_on',
    hasPhysicalDamage: false,
    status: JobStatus.matched,
    servicePath: ServicePath.homeService,
  );

  Widget page(String name, {VoidCallback? onNext, String next = 'Next'}) =>
      Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(name),
              if (onNext != null)
                TextButton(onPressed: onNext, child: Text(next)),
            ],
          ),
        ),
      );

  testWidgets('the posting steps are gone once the request is sent', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (BuildContext home) => page(
            'Home',
            onNext: () => Navigator.of(home).push(
              MaterialPageRoute<void>(
                builder: (BuildContext post) => page(
                  'Post a task',
                  onNext: () => Navigator.of(post).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext shortlist) => page(
                        'Choose a technician',
                        next: 'Book',
                        onNext: () =>
                            BookingSuccessScreen.show(shortlist, job: job),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();

    expect(find.text('Request sent'), findsWidgets);

    // Back - the system gesture, since the confirmation has no arrow.
    final NavigatorState navigator = tester.state<NavigatorState>(
      find.byType(Navigator),
    );
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Post a task'), findsNothing);
    expect(find.text('Choose a technician'), findsNothing);
    expect(navigator.canPop(), isFalse, reason: 'home is all that is left');
  });
}
