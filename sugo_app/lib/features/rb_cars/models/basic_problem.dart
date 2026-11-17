import 'package:flutter/foundation.dart';

import '../config/basic_problems.dart';
import 'issue_catalog.dart';

/// Why a problem was judged basic: the issue category, or the words matched.
@immutable
class BasicProblemMatch {
  const BasicProblemMatch({this.issueCode, this.keyword});

  /// Set when the picked issue is on the basic list.
  final String? issueCode;

  /// Set when a keyword matched the issue label or the description.
  final String? keyword;
}

/// Decides whether a problem looks basic enough to try the Technician
/// Community first (2026-11-16).
///
/// Rule-based and free: the issue code against `basicProblemIssueCodes`, then
/// each phrase in `basicProblemKeywords` against the picked issue's label and
/// the client's own description. Both lists live in
/// `lib/features/rb_cars/config/basic_problems.dart`, the only file to edit.
///
/// Whole words only, so "hang" does not fire on "change" and "slow" does not
/// fire on "slowdown"... but a phrase can sit anywhere in the text.
class BasicProblemDetector {
  const BasicProblemDetector._();

  static BasicProblemMatch? check({String? issueCode, String? description}) {
    if (issueCode != null && basicProblemIssueCodes.contains(issueCode)) {
      return BasicProblemMatch(issueCode: issueCode);
    }

    final String text = _normalise(
      '${IssueCatalog.byCode(issueCode)?.label ?? ''} ${description ?? ''}',
    );
    if (text.trim().isEmpty) return null;

    for (final String keyword in basicProblemKeywords) {
      final String phrase = _normalise(keyword).trim();
      if (phrase.isEmpty) continue;
      if (_wholePhrase(phrase).hasMatch(text)) {
        return BasicProblemMatch(keyword: keyword);
      }
    }
    return null;
  }

  /// Lower case, curly apostrophes made straight, runs of space collapsed.
  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll('‘', "'")
      .replaceAll(RegExp(r'\s+'), ' ');

  /// The phrase with no letter or digit touching either end.
  static RegExp _wholePhrase(String phrase) =>
      RegExp('(?<![a-z0-9])${RegExp.escape(phrase)}(?![a-z0-9])');
}
