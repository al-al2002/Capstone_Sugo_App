import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/widgets/sugo_avatar.dart';

/// The avatar's job is to always show *something*.
///
/// It renders in the dashboard header, the profile hero and beside every
/// community answer, and most accounts have no photo - so the fallback is the
/// common path, not the edge case. An earlier version painted the photo with a
/// `DecorationImage` and set the initials child to null whenever a URL was
/// present, which meant a 404, a slow connection or an offline phone produced
/// a blank tinted circle: no picture and no initials.
///
/// `flutter_test` blocks real HTTP, so every `Image.network` here fails to
/// load. That is precisely the condition being tested.
void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  group('SugoAvatar', () {
    testWidgets('shows initials when there is no photo', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(const SugoAvatar(name: 'Juan Dela Cruz')));
      // First word + last word: given name and surname.
      expect(find.text('JC'), findsOneWidget);
    });

    testWidgets('falls back to initials when the photo cannot load', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SugoAvatar(
            name: 'Juan Dela Cruz',
            imageUrl: 'https://example.invalid/missing.jpg',
          ),
        ),
      );
      // Let the failed load settle so errorBuilder runs.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('JC'),
        findsOneWidget,
        reason: 'a broken photo URL must not leave an empty circle',
      );
    });

    testWidgets('a single name still yields one initial', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(const SugoAvatar(name: 'Cher')));
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('an empty name degrades to a placeholder, not a crash', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(const SugoAvatar(name: '   ')));
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('the same name always gets the same tint', (
      WidgetTester tester,
    ) async {
      // One person is one colour everywhere in the app - that is what makes a
      // list scannable by colour before it is read.
      Color tintOf(WidgetTester t) {
        final Container box = t.widget<Container>(
          find
              .descendant(
                of: find.byType(SugoAvatar),
                matching: find.byType(Container),
              )
              .first,
        );
        return (box.decoration! as BoxDecoration).color!;
      }

      await tester.pumpWidget(host(const SugoAvatar(name: 'Maria Santos')));
      final Color first = tintOf(tester);

      await tester.pumpWidget(host(const SizedBox()));
      await tester.pumpWidget(host(const SugoAvatar(name: 'Maria Santos')));

      expect(tintOf(tester), first);
    });
  });
}
