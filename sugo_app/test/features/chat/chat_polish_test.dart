import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/chat/models/chat_models.dart';
import 'package:sugo_app/features/chat/screens/chat_thread_screen.dart';
import 'package:sugo_app/features/chat/screens/conversation_list_view.dart';
import 'package:sugo_app/features/chat/services/chat_service.dart';
import 'package:sugo_app/features/rb_cars/models/job_enums.dart';

/// The chat thread and the inbox, on a small phone with large text.
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

  ChatMessage message(String id, String sender, String body, DateTime at) =>
      ChatMessage(
        id: id,
        jobId: 'job-1',
        senderId: sender,
        body: body,
        createdAt: at,
      );

  testWidgets('a conversation renders, grouped, without overflowing', (
    WidgetTester tester,
  ) async {
    // Anchored to the start of today, not "30 minutes ago": between midnight
    // and 00:30 that was yesterday, the separator read "Yesterday", and this
    // test failed every night for half an hour.
    final DateTime now = DateTime.now();
    final DateTime t = DateTime(now.year, now.month, now.day, 0, 1);
    final _FakeChat chat = _FakeChat(<ChatMessage>[
      message('1', 'them', 'Good morning! I can come at 2pm.', t),
      message('2', 'them', 'Is the gate open?', t.add(const Duration(minutes: 1))),
      message('3', 'me', 'Yes, see you then. The unit is in the kitchen.', t.add(const Duration(minutes: 3))),
    ]);

    await tester.pumpWidget(
      host(
        ChatThreadScreen(
          jobId: 'job-1',
          title: 'Lance Dela Cruz',
          subtitle: 'Laptop / PC · Confirmed',
          service: chat,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lance Dela Cruz'), findsOneWidget);
    expect(find.text('Is the gate open?'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty thread offers starters that fill the box', (
    WidgetTester tester,
  ) async {
    final _FakeChat chat = _FakeChat(const <ChatMessage>[]);

    await tester.pumpWidget(
      host(ChatThreadScreen(jobId: 'job-1', title: 'Lance Dela Cruz', service: chat)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Say hello to Lance'), findsOneWidget);
    await tester.tap(find.text('What time works for you?'));
    await tester.pump();

    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'What time works for you?');
    // Filled, not sent: the first message stays the user's to edit.
    expect(chat.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the inbox counts unread threads and fits a two-digit badge', (
    WidgetTester tester,
  ) async {
    final _FakeChat chat = _FakeChat(const <ChatMessage>[], rows: <Conversation>[
      Conversation.fromJson(<String, dynamic>{
        'job_id': 'job-1',
        'counterpart': <String, dynamic>{'id': 't1', 'full_name': 'Lance Dela Cruz'},
        'job_status': JobStatus.confirmed.wire,
        'device_type': 'laptop',
        'problem_symptom': 'laptop_wont_power_on',
        'last_message': 'On my way now, about fifteen minutes out.',
        'last_message_at': DateTime.now().toIso8601String(),
        'unread_count': 12,
      }),
      Conversation.fromJson(<String, dynamic>{
        'job_id': 'job-2',
        'counterpart': <String, dynamic>{'id': 't2', 'full_name': 'Vance'},
        'job_status': JobStatus.completed.wire,
        'device_type': 'appliance',
        'problem_symptom': 'x',
        'unread_count': 0,
      }),
    ]);

    await tester.pumpWidget(host(Scaffold(body: ConversationListView(service: chat))));
    await tester.pumpAndSettle();

    expect(find.textContaining('unread conversation'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    // The device reads as a label, not a wire value.
    expect(find.text('Laptop / PC · Confirmed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeChat implements ChatService {
  _FakeChat(this.thread, {this.rows = const <Conversation>[]});

  /// What the thread stream delivers.
  final List<ChatMessage> thread;

  /// What the inbox lists.
  final List<Conversation> rows;

  final List<String> sent = <String>[];

  @override
  String? get currentUserId => 'me';

  @override
  Stream<List<ChatMessage>> watch(String jobId) =>
      Stream<List<ChatMessage>>.value(thread);

  @override
  Future<void> markRead(String jobId) async {}

  @override
  Future<List<Conversation>> conversations() async => rows;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
