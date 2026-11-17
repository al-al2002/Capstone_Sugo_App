import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/core/widgets/sugo_status_badge.dart';
import 'package:sugo_app/features/notifications/models/app_notification.dart';
import 'package:sugo_app/features/notifications/screens/notifications_screen.dart';
import 'package:sugo_app/features/notifications/services/notification_feed_service.dart';

/// The renovated notification centre (2026-11-17), on a small phone with
/// large text. Every test settles with `pumpAndSettle` at full motion, which
/// also proves nothing on the screen loops forever.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(320, 700),
        textScaler: TextScaler.linear(1.3),
      ),
      child: child,
    ),
  );

  AppNotification item(
    String id, {
    bool unread = false,
    NotificationCategory category = NotificationCategory.booking,
  }) => AppNotification(
    id: id,
    category: category,
    title: 'Booking update $id',
    body: 'Your technician accepted the job and is on the way.',
    at: DateTime.now().subtract(const Duration(minutes: 5)),
    icon: Icons.event_note_rounded,
    tone: SugoTone.brand,
    action: NotificationAction.openJob,
    unread: unread,
  );

  testWidgets('the band counts what is new; rows render without overflow', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        NotificationsScreen(
          service: _FakeFeed(<AppNotification>[
            item('1', unread: true),
            item('2', unread: true, category: NotificationCategory.tracking),
            item('3'),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 new updates'), findsOneWidget);
    expect(find.text('Booking update 1'), findsOneWidget);
    expect(find.text('Booking update 3'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing at all: "Nothing new" and the all-caught-up state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(NotificationsScreen(service: _FakeFeed(const <AppNotification>[]))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing new'), findsOneWidget);
    expect(find.text("You're all caught up"), findsOneWidget);
    expect(find.text('Mark all read'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a technician\'s band speaks of requests', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        NotificationsScreen(
          audience: NotificationAudience.technician,
          service: _FakeFeed(<AppNotification>[item('1', unread: true)]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 new update'), findsOneWidget);
    expect(find.textContaining('Requests, messages'), findsOneWidget);
  });
}

class _FakeFeed implements NotificationFeedService {
  _FakeFeed(this.items);

  final List<AppNotification> items;

  @override
  Future<List<AppNotification>> load() async => items;

  @override
  Future<void> markSeen(Iterable<AppNotification> items) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
