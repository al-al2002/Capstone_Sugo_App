import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/rb_cars/models/technician.dart';
import 'package:sugo_app/features/technician/models/time_off.dart';
import 'package:sugo_app/features/technician/widgets/technician_home_header.dart';

/// The technician home's header console (2026-11-16): who and what's new,
/// whether clients can book them, and the week's figures - one panel.
void main() {
  const Technician maria = Technician(
    id: 't',
    fullName: 'Maria Santos',
    rating: 4.8,
    totalJobs: 42,
    isVerified: true,
  );

  Widget host(Widget child, {double width = 390, double scale = 1}) =>
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: ListView(padding: EdgeInsets.zero, children: <Widget>[child]),
          ),
        ),
      );

  TechnicianHomeHeader header({
    TimeOff? vacation,
    VoidCallback? onSetVacation,
    VoidCallback? onEndVacation,
    VoidCallback? onOpenInbox,
  }) => TechnicianHomeHeader(
    technician: maria,
    vacation: vacation,
    unreadMessages: 2,
    unreadNotifications: 0,
    onOpenInbox: onOpenInbox ?? () {},
    onOpenNotifications: () {},
    onSetVacation: onSetVacation ?? () {},
    onEndVacation: onEndVacation ?? () {},
    onEditDates: () {},
    earningsToday: 1250,
    jobsThisWeek: 6,
    now: DateTime(2026, 11, 16, 9),
  );

  testWidgets('taking jobs: the name, the status, the week, one action', (
    WidgetTester tester,
  ) async {
    int set = 0;
    int inbox = 0;
    await tester.pumpWidget(
      host(header(onSetVacation: () => set++, onOpenInbox: () => inbox++)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Good morning,'), findsOneWidget);
    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('Taking jobs'), findsOneWidget);
    expect(find.text('₱1,250'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('End vacation'), findsNothing);

    await tester.tap(find.text('Set vacation'));
    expect(set, 1);
    await tester.tap(find.byTooltip('Messages'));
    expect(inbox, 1);
  });

  testWidgets('on vacation: days left, the day back, and how to end it', (
    WidgetTester tester,
  ) async {
    int ended = 0;
    await tester.pumpWidget(
      host(
        header(
          vacation: TimeOff(
            id: 'v',
            startsOn: DateTime(2026, 11, 15),
            endsOn: DateTime(2026, 11, 18),
          ),
          onEndVacation: () => ended++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The 16th to the 18th, counting today: three days, back on the 19th.
    expect(find.text('3 days left · back Thu, Nov 19'), findsOneWidget);
    expect(find.text('Set vacation'), findsNothing);
    expect(find.text('Edit dates'), findsOneWidget);

    await tester.tap(find.text('End vacation'));
    expect(ended, 1);
  });

  testWidgets('fits a small phone with large text', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(header(), width: 320, scale: 1.3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
