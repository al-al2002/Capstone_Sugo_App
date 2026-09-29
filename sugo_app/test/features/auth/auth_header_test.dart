import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugo_app/core/constants/app_assets.dart';
import 'package:sugo_app/core/widgets/sugo_logo.dart';
import 'package:sugo_app/features/auth/presentation/widgets/auth_header.dart';

/// The login header must never be an empty navy block.
///
/// Reported 2026-09-28: the running app's asset bundle did not contain
/// `brand_header.jpg` (added while `flutter run` was up; hot restart does not
/// pick up new asset files), and the header's error handler returned nothing.
/// This reproduces the missing file and requires the drawn logo instead.
void main() {
  testWidgets('a missing header image falls back to the drawn logo', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: _WithoutHeader(rootBundle),
          child: const Scaffold(body: AuthHeader(height: 390)),
        ),
      ),
    );

    // The asset load fails asynchronously; let it, then rebuild.
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 50),
        ));
    await tester.pump();

    expect(find.byType(SugoLogoMark), findsOneWidget);
    expect(find.byType(SugoLogo), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// The real bundle, minus the header artwork.
class _WithoutHeader extends CachingAssetBundle {
  _WithoutHeader(this._inner);

  final AssetBundle _inner;

  @override
  Future<ByteData> load(String key) {
    if (key == AppAssets.brandHeader) {
      throw FlutterError('Unable to load asset: "$key".');
    }
    return _inner.load(key);
  }
}
