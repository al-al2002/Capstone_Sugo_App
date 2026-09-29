import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/features/community/models/community_models.dart';
import 'package:sugo_app/features/community/widgets/community_post_card.dart';

/// The feed row, rendered the way the feed renders it: inside a `ListView`.
///
/// Every earlier community test reached the *error* state, because a widget
/// test has no Supabase - so no post card was ever built. The one widget that
/// only appears once the feed has content was therefore the one widget with no
/// coverage at all, which is exactly where the reported crash was.
void main() {
  CommunityPost post({int answers = 0}) => CommunityPost(
    id: 'p1',
    title: 'What laptop should a student on a budget buy?',
    body: 'Budget is around 30k pesos, mostly for schoolwork and some light '
        'photo editing. Is a refurbished ThinkPad a good idea?',
    topic: CommunityTopic.laptop,
    author: const CommunityAuthor(id: 'a1', fullName: 'Maria Santos'),
    commentCount: answers,
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    lastActivityAt: DateTime.now().subtract(const Duration(hours: 1)),
  );

  Widget inList(List<Widget> children) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SafeArea(
        // A vertically scrolling list gives its children UNBOUNDED height.
        // That is the constraint the real feed applies and the one that
        // matters here.
        child: ListView(children: children),
      ),
    ),
  );

  testWidgets('renders inside a ListView without a render error', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      inList(<Widget>[CommunityPostCard(post: post(), onTap: () {})]),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('What laptop'), findsOneWidget);
  });

  testWidgets('answered and unanswered both render', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      inList(<Widget>[
        CommunityPostCard(post: post(), onTap: () {}),
        CommunityPostCard(post: post(answers: 3), onTap: () {}),
      ]),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Unanswered'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('the owner gets a delete affordance and it still lays out', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 480 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      inList(<Widget>[
        CommunityPostCard(post: post(), onTap: () {}, onDelete: () {}),
      ]),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
