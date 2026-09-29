import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/theme/app_theme.dart';
import 'package:sugo_app/core/widgets/sugo_bottom_nav.dart';
import 'package:sugo_app/features/community/screens/community_feed_view.dart';

/// The Community tab inside the shell it actually lives in.
///
/// The earlier feed test pumped `CommunityFeedView` into a bare `Scaffold`,
/// which is not what the app does: the real screen has a `SugoBottomNav` in
/// the `bottomNavigationBar` slot, a compose button inside it, and a modal
/// sheet that opens over the whole thing while the keyboard pushes everything
/// up. Every one of those is a layout constraint the bare harness never
/// applied, so a whole class of render failure could not show up there.
void main() {
  Widget shell({required bool isClient}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: _Shell(isClient: isClient),
    );
  }

  Future<void> pumpShell(WidgetTester tester, {bool isClient = true}) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(shell(isClient: isClient));
    await tester.pumpAndSettle();
  }

  testWidgets('feed + bottom nav lay out together', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Community'), findsWidgets);
  });

  testWidgets('composer over the feed, with the nav behind it', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    expect(find.text('Ask the community'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composer with the keyboard up, nav squeezed behind', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    // A soft keyboard over a 640dp screen leaves very little for the shell
    // behind the sheet. This is the state the bug was reported in.
    tester.view.viewInsets = const FakeViewPadding(bottom: 340 * 3);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // And typing into it, which is when the report says it goes wrong.
    await tester.enterText(
      find.byType(TextField).first,
      'What laptop should a student on a budget buy?',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Then dismissing, which tears the sheet down over the live shell. The
    // back arrow replaced the Cancel button, and because there is a draft it
    // asks before throwing it away.
    tester.view.viewInsets = const FakeViewPadding(bottom: 0);
    await tester.tap(find.byTooltip('Back to the community'));
    await tester.pumpAndSettle();

    expect(find.text('Discard this question?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Ask the community'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('backing out of an empty composer does not ask twice', (
    WidgetTester tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    // Nothing typed, so there is nothing to lose and nothing to confirm.
    await tester.tap(find.byTooltip('Back to the community'));
    await tester.pumpAndSettle();

    expect(find.text('Discard this question?'), findsNothing);
    expect(find.text('Ask the community'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a very short viewport does not break the shell', (
    WidgetTester tester,
  ) async {
    // Small phone, keyboard up: about the harshest real layout there is.
    tester.view.physicalSize = const Size(320 * 3, 480 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(shell(isClient: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

/// Mirrors the client dashboard's shell: feed body, nav bar with a compose
/// button, tab switching. Built here rather than pumping the real dashboard,
/// which needs a live Supabase session to construct at all.
class _Shell extends StatefulWidget {
  const _Shell({required this.isClient});

  final bool isClient;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _tab = 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CommunityFeedView(isClient: widget.isClient),
      ),
      bottomNavigationBar: SugoBottomNav(
        items: const <SugoNavItem>[
          SugoNavItem(
            label: 'Home',
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
          ),
          SugoNavItem(
            label: 'Bookings',
            icon: Icons.event_note_outlined,
            activeIcon: Icons.event_note_rounded,
          ),
          SugoNavItem(
            label: 'Community',
            icon: Icons.forum_outlined,
            activeIcon: Icons.forum_rounded,
            showBadge: true,
          ),
          SugoNavItem(
            label: 'Profile',
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
          ),
        ],
        currentIndex: _tab,
        composeAction: widget.isClient
            ? SugoComposeAction(onTap: () {})
            : null,
        onChanged: (int index) => setState(() => _tab = index),
      ),
    );
  }
}
