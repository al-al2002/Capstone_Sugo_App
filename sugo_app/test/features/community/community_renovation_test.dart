import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/community/models/community_models.dart';
import 'package:sugo_app/features/community/screens/community_feed_view.dart';
import 'package:sugo_app/features/community/screens/community_post_screen.dart';
import 'package:sugo_app/features/community/services/community_service.dart';

/// The renovated Community (2026-11-17), with questions in it.
///
/// The older tests can only reach the offline error state, because the feed
/// built its own service. With the service injectable, these render the feed
/// and the thread as people actually see them - on a small phone at large
/// text, settling at full motion (which also proves nothing loops forever).
void main() {
  const CommunityAuthor asker = CommunityAuthor(
    id: 'c1',
    fullName: 'Ana Reyes',
  );
  const CommunityAuthor tech = CommunityAuthor(
    id: 't1',
    fullName: 'Ryan Santos',
    role: 'technician',
    isVerified: true,
  );

  CommunityPost post(String id, String title, {int answers = 0}) =>
      CommunityPost(
        id: id,
        title: title,
        body: 'It shuts off after a few minutes and the fan is very loud.',
        topic: CommunityTopic.laptop,
        author: asker,
        commentCount: answers,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        lastActivityAt: DateTime.now().subtract(const Duration(minutes: 30)),
      );

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(320, 900),
        textScaler: TextScaler.linear(1.3),
      ),
      child: child,
    ),
  );

  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.reset);
  }

  final List<CommunityPost> posts = <CommunityPost>[
    post('p1', 'Laptop overheats when gaming'),
    post('p2', 'Which charger is safe for my phone?', answers: 2),
    post('p3', 'Aircon drips water inside'),
  ];

  testWidgets('a client\'s feed: the band, one Ask, the questions', (
    WidgetTester tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      host(
        Scaffold(
          body: CommunityFeedView(isClient: true, service: _Fake(posts)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
    expect(find.text('Laptop overheats when gaming'), findsOneWidget);
    expect(find.text('Unanswered'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a technician\'s band counts the questions waiting', (
    WidgetTester tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      host(
        Scaffold(
          body: CommunityFeedView(isClient: false, service: _Fake(posts)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 questions waiting for an answer'), findsOneWidget);
    expect(find.text('to answer'), findsOneWidget);
    expect(find.text('Ask'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unanswered thread says so, top and bottom', (
    WidgetTester tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      host(CommunityPostScreen(post: posts.first, service: _Fake(posts))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Laptop overheats when gaming'), findsOneWidget);
    expect(find.text('Waiting for an answer'), findsOneWidget);
    expect(find.text('No answers yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an answered thread shows the count and the answers', (
    WidgetTester tester,
  ) async {
    phone(tester);
    final List<CommunityAnswer> answers = <CommunityAnswer>[
      CommunityAnswer(
        id: 'a1',
        postId: 'p2',
        body: 'Use the original charger, or one with the same rating.',
        author: tech,
        helpfulCount: 3,
        createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
      ),
      CommunityAnswer(
        id: 'a2',
        postId: 'p2',
        body: 'Avoid the cheap ones without a certification mark.',
        author: tech,
        createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
      ),
    ];
    await tester.pumpWidget(
      host(
        CommunityPostScreen(
          post: posts[1],
          service: _Fake(posts, answers: answers),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Answered · 2'), findsOneWidget);
    expect(
      find.text('Use the original charger, or one with the same rating.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _Fake implements CommunityService {
  _Fake(this.posts, {List<CommunityAnswer> answers = const <CommunityAnswer>[]})
    : answerRows = answers;

  final List<CommunityPost> posts;

  /// Not called `answers`: that is the service method being faked.
  final List<CommunityAnswer> answerRows;

  @override
  Future<List<CommunityPost>> feed({
    CommunitySort sort = CommunitySort.recent,
    CommunityTopic? topic,
    int limit = 50,
  }) async => posts;

  @override
  Future<CommunityPost?> post(String postId) async =>
      posts.where((CommunityPost p) => p.id == postId).firstOrNull;

  @override
  Future<List<CommunityAnswer>> answers(
    String postId, {
    CommunitySort sort = CommunitySort.mostHelpful,
  }) async => answerRows;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
