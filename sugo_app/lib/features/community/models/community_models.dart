import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../rb_cars/models/job_enums.dart';

/// What a question is about.
///
/// A fixed set rather than free tags, matching the `topic` check constraint in
/// migration 20260921000001. Free tags on a feed this size fragment into
/// "laptop", "Laptop" and "laptops" within a week, and the filter row then has
/// thirty entries and sorts nothing.
enum CommunityTopic {
  general('general', 'General', Icons.forum_rounded),
  laptop('laptop', 'Laptops', Icons.laptop_mac_rounded),
  phone('phone', 'Phones', Icons.smartphone_rounded),
  appliance('appliance', 'Appliances', Icons.kitchen_rounded),
  network('network', 'Network', Icons.router_rounded),
  buying('buying', 'Buying advice', Icons.shopping_bag_rounded);

  const CommunityTopic(this.wire, this.label, this.icon);

  final String wire;
  final String label;
  final IconData icon;

  static CommunityTopic fromWire(String? value) {
    for (final CommunityTopic topic in CommunityTopic.values) {
      if (topic.wire == value) return topic;
    }
    return CommunityTopic.general;
  }
}

/// How the feed is ordered.
///
/// Two options only. A sort control with five entries is one nobody touches,
/// and these are the only two questions a reader actually has: "what is new?"
/// and "what is worth reading?".
enum CommunitySort {
  recent('Recent', Icons.schedule_rounded),
  mostHelpful('Most Helpful', Icons.trending_up_rounded);

  const CommunitySort(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The person behind a post or an answer, as resolved by `community_author()`.
///
/// Deliberately a thin projection: name, picture, role and standing. The
/// database function returns exactly these fields, and it must stay that way -
/// everything here is rendered publicly beside an answer.
class CommunityAuthor {
  const CommunityAuthor({
    required this.id,
    this.fullName,
    this.avatarUrl,
    this.role = 'client',
    this.tier = TechnicianTier.standard,
    this.badge,
    this.isVerified = false,
    this.rating = 0,
    this.points = 0,
    this.answers = 0,
  });

  factory CommunityAuthor.fromJson(Map<String, dynamic> json) {
    return CommunityAuthor(
      id: json['id'] as String? ?? '',
      fullName: json['full_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String? ?? 'client',
      tier: TechnicianTier.fromWire(json['tier'] as String?),
      badge: json['badge'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      points: (json['points'] as num?)?.toInt() ?? 0,
      answers: (json['answers'] as num?)?.toInt() ?? 0,
    );
  }

  /// Stands in for an author the view could not resolve - a deleted profile,
  /// or a row read before the join landed. Never an error: one missing name
  /// must not blank out a whole feed.
  static const CommunityAuthor unknown = CommunityAuthor(id: '');

  final String id;
  final String? fullName;
  final String? avatarUrl;
  final String role;
  final TechnicianTier tier;
  final String? badge;
  final bool isVerified;
  final double rating;

  /// Community standing. Display only - see the migration for why this can
  /// never reach the matcher.
  final int points;
  final int answers;

  bool get isTechnician => role == 'technician';

  String get displayName {
    final String? name = fullName?.trim();
    return (name == null || name.isEmpty) ? 'SUGO user' : name;
  }

  /// What the pill beside the name reads. Falls back to the tier when the
  /// technician has no explicit badge, which is the common case.
  String get badgeLabel {
    final String? explicit = badge?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return tier.label;
  }

  /// Tint and ink for the tier pill. Existing palette tokens only.
  (Color, Color) get tierColors => switch (tier) {
    // The ink is the text orange: the bright one is 2.1:1 on its wash.
    TechnicianTier.elite => (AppColors.accentSoft, AppColors.accentDark),
    TechnicianTier.pro => (AppColors.primarySoft, AppColors.primaryDark),
    TechnicianTier.standard => (AppColors.divider, AppColors.textSecondary),
  };
}

/// One question on the feed: a row of `community_feed`.
class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.title,
    required this.body,
    required this.topic,
    required this.author,
    this.commentCount = 0,
    this.helpfulTotal = 0,
    this.isMine = false,
    this.imagePath,
    required this.createdAt,
    required this.lastActivityAt,
  });

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? author =
        json['author'] as Map<String, dynamic>?;

    return CommunityPost(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      topic: CommunityTopic.fromWire(json['topic'] as String?),
      author: author == null
          ? CommunityAuthor.unknown
          : CommunityAuthor.fromJson(author),
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      helpfulTotal: (json['helpful_total'] as num?)?.toInt() ?? 0,
      isMine: json['is_mine'] as bool? ?? false,
      // Read defensively: a build newer than the database simply sees every
      // question as photoless rather than failing to parse the feed.
      imagePath: json['image_path'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      lastActivityAt:
          DateTime.tryParse(
            json['last_activity_at'] as String? ?? '',
          )?.toLocal() ??
          DateTime.now(),
    );
  }

  final String id;
  final String title;
  final String body;
  final CommunityTopic topic;
  final CommunityAuthor author;
  final int commentCount;
  final int helpfulTotal;
  final bool isMine;

  /// Object path in the public `community-photos` bucket, or null. Resolve it
  /// to a URL with `CommunityService.photoUrl`.
  final String? imagePath;

  final DateTime createdAt;
  final DateTime lastActivityAt;

  bool get hasPhoto => (imagePath ?? '').isNotEmpty;

  /// Drives the "Answered" chip. The most useful signal on the feed: an
  /// unanswered question is the one a technician should open.
  bool get isAnswered => commentCount > 0;

  String get answerLabel => switch (commentCount) {
    0 => 'No answers yet',
    1 => '1 answer',
    _ => '$commentCount answers',
  };
}

/// One answer in a thread: a row of `community_thread`.
class CommunityAnswer {
  const CommunityAnswer({
    required this.id,
    required this.postId,
    required this.body,
    required this.author,
    this.authorRole = 'technician',
    this.helpfulCount = 0,
    this.hasVoted = false,
    this.canVote = false,
    this.isMine = false,
    required this.createdAt,
  });

  factory CommunityAnswer.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? author =
        json['author'] as Map<String, dynamic>?;

    return CommunityAnswer(
      id: json['id'] as String,
      postId: json['post_id'] as String? ?? '',
      body: json['body'] as String? ?? '',
      author: author == null
          ? CommunityAuthor.unknown
          : CommunityAuthor.fromJson(author),
      authorRole: json['author_role'] as String? ?? 'technician',
      helpfulCount: (json['helpful_count'] as num?)?.toInt() ?? 0,
      hasVoted: json['has_voted'] as bool? ?? false,
      // Mirrors the insert policy, so the UI hides the control rather than
      // offering a button that fails.
      canVote: json['can_vote'] as bool? ?? false,
      isMine: json['is_mine'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  final String id;
  final String postId;
  final String body;
  final CommunityAuthor author;
  final String authorRole;
  final int helpfulCount;
  final bool hasVoted;
  final bool canVote;
  final bool isMine;
  final DateTime createdAt;

  bool get isFromTechnician => authorRole == 'technician';

  /// Optimistic local flip, so the vote button responds on tap rather than
  /// after the round trip. Replaced by the server row on the next read.
  CommunityAnswer toggledVote() => CommunityAnswer(
    id: id,
    postId: postId,
    body: body,
    author: author,
    authorRole: authorRole,
    helpfulCount: hasVoted
        // Never below zero, in case a stale row and a fresh tap disagree.
        ? (helpfulCount > 0 ? helpfulCount - 1 : 0)
        : helpfulCount + 1,
    hasVoted: !hasVoted,
    canVote: canVote,
    isMine: isMine,
    createdAt: createdAt,
  );
}

/// Short relative time - "2h", "3d" - for a feed row.
///
/// Feed timestamps are read as "how stale is this?", not as dates, so the
/// shortest form that answers that is the right one. Anything older than a
/// week gets a real date, because "63d" is not a thing anyone parses.
String communityTimeAgo(DateTime moment) {
  final Duration gap = DateTime.now().difference(moment);

  if (gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes}m ago';
  if (gap.inHours < 24) return '${gap.inHours}h ago';
  if (gap.inDays < 7) return '${gap.inDays}d ago';

  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[moment.month - 1]} ${moment.day}';
}
