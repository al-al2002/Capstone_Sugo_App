/// The basic-problem list: what counts as "probably fixable with advice".
///
/// EDIT THIS FILE to tune the suggestion. Nothing else needs to change.
///
/// When the picked issue matches anything here, the posting flow suggests the
/// Technician Community - the "Suggested" badge moves there - and shows:
///
///   "This looks like a basic problem. Try the Technician Community first:
///    it's free, and you can still book a technician."
///
/// It is only a suggestion. The client still chooses between the Technician
/// Community, Home Service and Shop Repair.
///
/// Two kinds of issue are never suggested the community, even when they
/// match (see `ClassificationResult._fromIssue`):
///
/// * one whose route is Shop pickup, or with visible damage - it needs the
///   bench, so Shop Repair stays the suggestion;
/// * one that "needs diagnosis" (e.g. "Will not turn on") - those are matched
///   with a technician, because clients reporting a dead laptop were getting
///   advice instead of a technician (fixed 2026-11-15).
///
/// The client's own words ("needs a restart") can still bring the card up on
/// the details step, as a nudge.
///
/// Matching is plain and free: lower-case text containment, on the issue the
/// client picked and on whatever they typed in "What happened?". No AI
/// service is called. (Ask before adding a paid one.)
library;

/// Phrases that suggest a basic fix. Lower case; matched anywhere in the
/// picked issue's label and the client's own description. Taglish is fine -
/// add whatever clients actually type.
const List<String> basicProblemKeywords = <String>[
  // From the brief.
  'not charging',
  'loose cable',
  'needs restart',
  'restart',
  'dusty',
  'slow',
  'not turning on',
  'not turn on',
  'will not turn on',
  "won't turn on",
  // Common variants.
  'freezing',
  'freeze',
  'hang',
  'nag-hang',
  'loose',
  'maluwag',
  'reboot',
  'mabagal',
  'ayaw mag-on',
  'ayaw mag on',
  'ayaw mag-charge',
  'hindi nagcha-charge',
  'maalikabok',
  'alikabok',
  'dust',
];

/// Issue codes from `IssueCatalog` that are basic whatever the client types.
/// A code here is a category - "this kind of problem is usually basic".
const Set<String> basicProblemIssueCodes = <String>{
  'laptop_slow_or_freezing',
  'laptop_battery_not_charging',
  'phone_software_stuck',
  'phone_battery_drain',
  'network_no_internet',
  'network_device_wont_connect',
};

/// The suggestion card's words, in one place with the list. English since
/// 2026-11-17, like the rest of the app; it read "Mukhang basic lang ito.
/// Subukan muna sa Technician Community para makatipid."
const String basicProblemTitle = 'This looks like a basic problem.';
const String basicProblemMessage =
    "Try the Technician Community first: it's free, and you can still book "
    'a technician if the tips do not fix it.';
