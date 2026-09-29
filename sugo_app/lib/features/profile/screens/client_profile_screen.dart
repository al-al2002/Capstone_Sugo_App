import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../../core/widgets/sugo_stat_tile.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../rb_cars/models/job_party.dart';
import '../../rb_cars/models/technician_profile_details.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../rb_cars/widgets/review_card.dart';

/// A client's public profile.
///
/// ## Who this is for
///
/// Mostly a technician deciding whether to accept - or looking back at - a job
/// at somebody's home. Before this screen existed they had no signal at all
/// about who they were about to visit, while the client could read three
/// screens about them. A two-sided marketplace with one-sided trust is one
/// where the careful technicians leave.
///
/// It is also where a client's name leads from a Community answer, so a
/// question can be traced to a real, rated person.
///
/// ## What it shows, and what it must never show
///
/// Everything here comes from `client_profile()`, which returns a deliberate
/// subset: name, picture, whether their ID was verified, job counts, and the
/// ratings technicians gave them. Never a phone number, an email, or any job's
/// location. See migration 20260921000010.
class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({
    super.key,
    required this.clientId,
    this.initialName,
    this.initialAvatarUrl,
  });

  final String clientId;

  /// Optional seed, so the header paints before the network call returns.
  final String? initialName;
  final String? initialAvatarUrl;

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final RbCarsService _service = RbCarsService();

  ClientProfileDetails? _details;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ClientProfileDetails details = await _service.clientProfile(
        widget.clientId,
      );
      if (!mounted) return;
      setState(() {
        _details = details;
        _loading = false;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const SugoAppBar(title: 'Client profile'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.screenPadding,
            AppSizes.sm,
            AppSizes.screenPadding,
            AppSizes.xxl,
          ),
          children: _body(),
        ),
      ),
    );
  }

  List<Widget> _body() {
    final ClientProfileDetails? d = _details;

    if (d == null && _loading) {
      return <Widget>[
        _Hero(
          name: widget.initialName ?? 'Client',
          avatarUrl: widget.initialAvatarUrl,
          idVerified: false,
          memberSince: null,
        ),
        const SizedBox(height: AppSizes.lg),
        const SugoSkeletonList(count: 3, showAvatar: false),
      ];
    }

    if (d == null) {
      return <Widget>[
        const SizedBox(height: AppSizes.xxl),
        SugoEmptyState.error(
          message: _error ?? 'Could not load this profile.',
          onAction: _load,
        ),
      ];
    }

    final int? completion = d.completionRate;

    return <Widget>[
      _Hero(
        name: d.displayName,
        avatarUrl: d.avatarUrl,
        idVerified: d.idVerified,
        memberSince: d.memberSince,
      ),
      const SizedBox(height: AppSizes.md),

      SugoStatRow(
        tiles: <Widget>[
          SugoStatTile(
            icon: Icons.star_rounded,
            value: d.ratingCount == 0 ? '—' : d.rating.toStringAsFixed(1),
            animate: false,
            label: d.ratingCount == 0
                ? 'Not rated yet'
                : '${d.ratingCount} '
                      '${d.ratingCount == 1 ? 'rating' : 'ratings'}',
            tint: AppColors.warningSoft,
            foreground: AppColors.warning,
          ),
          SugoStatTile(
            icon: Icons.task_alt_rounded,
            value: '${d.jobsCompleted}',
            numericValue: d.jobsCompleted,
            label: 'Jobs completed',
            tint: AppColors.successSoft,
            foreground: AppColors.success,
          ),
          SugoStatTile(
            icon: Icons.verified_outlined,
            // A rate, not a count - so it is not animated from zero.
            value: completion == null ? '—' : '$completion%',
            animate: false,
            label: 'Follow-through',
          ),
        ],
      ),

      if (d.ratingCount > 0) ...<Widget>[
        const SizedBox(height: AppSizes.lg),
        _Breakdown(details: d),
      ],

      const SizedBox(height: AppSizes.xl),
      const SectionHeader(
        title: 'What technicians said',
        icon: Icons.engineering_outlined,
      ),
      const SizedBox(height: AppSizes.md),

      if (d.reviews.isEmpty)
        const SugoEmptyState(
          icon: Icons.rate_review_outlined,
          title: 'No ratings yet',
          message:
              'Technicians can rate a client once a job with them is '
              'completed. Nobody has yet.',
          compact: true,
        )
      else
        for (final TechnicianReview review in d.reviews)
          ReviewCard(key: ValueKey<String>(review.id), review: review),

      if (d.communityQuestions > 0) ...<Widget>[
        const SizedBox(height: AppSizes.md),
        Row(
          children: <Widget>[
            const Icon(
              Icons.forum_outlined,
              size: 15,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Has asked ${d.communityQuestions} '
                '${d.communityQuestions == 1 ? 'question' : 'questions'} '
                'in Community',
                style: AppTextStyles.micro,
              ),
            ),
          ],
        ),
      ],

      const SizedBox(height: AppSizes.lg),
      const _PrivacyNote(),
    ];
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.name,
    required this.avatarUrl,
    required this.idVerified,
    required this.memberSince,
  });

  final String name;
  final String? avatarUrl;
  final bool idVerified;
  final DateTime? memberSince;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      padding: const EdgeInsets.all(AppSizes.xl),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[AppColors.primary, AppColors.navy],
      ),
      elevation: SugoElevation.lg,
      child: Column(
        children: <Widget>[
          SugoAvatar(
            name: name,
            imageUrl: avatarUrl,
            size: 84,
            ringColor: Colors.white.withValues(alpha: 0.35),
            verified: idVerified,
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTextStyles.display.copyWith(
              color: Colors.white,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSizes.sm,
            runSpacing: AppSizes.xs,
            children: <Widget>[
              const _HeroChip(icon: Icons.person_rounded, label: 'Client'),
              if (idVerified)
                const _HeroChip(
                  icon: Icons.verified_rounded,
                  label: 'ID verified',
                ),
              if (memberSince != null)
                _HeroChip(
                  icon: Icons.calendar_month_rounded,
                  label: 'Since ${DateFormat('MMM yyyy').format(memberSince!)}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Five bars, one per star value, scaled to the busiest.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.details});

  final ClientProfileDetails details;

  @override
  Widget build(BuildContext context) {
    final int largest = details.starBreakdown.values.fold<int>(
      1,
      (int a, int b) => b > a ? b : a,
    );

    return SugoCard(
      elevation: SugoElevation.sm,
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        children: <Widget>[
          for (int star = 5; star >= 1; star--)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 26,
                    child: Text('$star', style: AppTextStyles.micro),
                  ),
                  const Icon(
                    Icons.star_rounded,
                    size: 13,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                      child: LinearProgressIndicator(
                        value: (details.starBreakdown[star] ?? 0) / largest,
                        minHeight: 7,
                        backgroundColor: AppColors.divider,
                        // The text orange: a bar carries the count, and the
                        // bright orange is under 3:1 against its track.
                        color: AppColors.accentDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${details.starBreakdown[star] ?? 0}',
                      textAlign: TextAlign.right,
                      style: AppTextStyles.micro.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md + 2),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.primary),
          SizedBox(width: AppSizes.sm + 2),
          Expanded(
            child: Text(
              'A client’s phone number, email and address are never shown '
              'here. They reach a technician only through a confirmed booking.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
