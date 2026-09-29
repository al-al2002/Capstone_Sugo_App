import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_sizes.dart';
import '../../core/services/local_prefs.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/sugo_avatar.dart';
import '../../core/widgets/sugo_card.dart';
import '../../core/widgets/sugo_empty_state.dart';
import '../../core/widgets/sugo_loading.dart';
import '../../core/widgets/sugo_search_field.dart';
import '../../core/widgets/sugo_skeleton.dart';
import '../client/widgets/service_category_row.dart';
import '../rb_cars/models/device_category.dart';
import '../rb_cars/models/issue_catalog.dart';
import '../rb_cars/models/technician.dart';
import '../rb_cars/services/technician_directory_service.dart';

/// Global search across services, problems and technicians.
///
/// ## Why a screen rather than a field on the home page
///
/// Typing on the dashboard would push the dashboard around: results appear,
/// the keyboard covers half the screen, and the greeting and active booking
/// scroll away. A dedicated screen keeps the home screen calm and gives
/// results the whole display. The home bar is a button styled exactly like
/// this screen's field, so the transition reads as the same control gaining
/// focus.
///
/// ## What it searches, and where each answer goes
///
/// | Match | Opens |
/// |---|---|
/// | A service category ("aircon") | The posting flow, that category chosen |
/// | A specific problem ("not cooling") | The posting flow, that problem chosen |
/// | A technician's name or skill | Their profile |
///
/// Categories and problems come from the catalogs already in the app, so
/// search needs no index and works offline. Technicians come from the
/// directory function, fetched once when the first query is typed - not on
/// open, because a search screen that spends a round trip before anyone has
/// typed is a slow search screen.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.onCategory,
    this.onIssue,
    this.onTechnician,
    this.directory,
    this.latitude,
    this.longitude,
  });

  /// Start the posting flow for a category.
  final void Function(DeviceCategory category)? onCategory;

  /// Start the posting flow for a specific problem.
  final void Function(DeviceCategory category, IssueOption issue)? onIssue;

  final void Function(Technician technician)? onTechnician;

  /// Tests only.
  final TechnicianDirectoryService? directory;

  /// The client's position, so technician results can carry a distance.
  final double? latitude;
  final double? longitude;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TechnicianDirectoryService _directory =
      widget.directory ?? TechnicianDirectoryService();
  final TextEditingController _input = TextEditingController();
  final LocalPrefs _prefs = LocalPrefs.instance;

  List<String> _recent = const <String>[];
  List<Technician> _technicians = const <Technician>[];
  bool _loadingTechnicians = false;
  bool _technicianLoadFailed = false;
  String _query = '';

  /// The searches offered before anyone types. Written as problems people
  /// actually have, not as category names, because that is what they type.
  static const List<String> _popular = <String>[
    'Aircon not cooling',
    'Laptop will not turn on',
    'Cracked phone screen',
    'Slow Wi-Fi',
    'CCTV installation',
    'Washing machine repair',
  ];

  String? get _uid => SupabaseService.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    final String? uid = _uid;
    if (uid != null) {
      _prefs.recentSearches(uid).then((List<String> saved) {
        if (mounted) setState(() => _recent = saved);
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadTechnicians() async {
    if (_loadingTechnicians || _technicians.isNotEmpty) return;
    setState(() => _loadingTechnicians = true);
    try {
      final List<Technician> found = await _directory.browse(
        latitude: widget.latitude,
        longitude: widget.longitude,
      );
      if (!mounted) return;
      setState(() {
        _technicians = found;
        _loadingTechnicians = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingTechnicians = false;
        _technicianLoadFailed = true;
      });
    }
  }

  void _onChanged(String value) {
    setState(() => _query = value.trim());
    if (_query.length >= 2) _loadTechnicians();
  }

  void _run(String query) {
    _input.text = query;
    _input.selection = TextSelection.collapsed(offset: query.length);
    _onChanged(query);
    _remember(query);
  }

  void _remember(String query) {
    final String? uid = _uid;
    if (uid == null) return;
    _prefs.addRecentSearch(uid, query).then((_) async {
      final List<String> saved = await _prefs.recentSearches(uid);
      if (mounted) setState(() => _recent = saved);
    });
  }

  // ------------------------------------------------------------- matching

  bool _matches(String haystack, String needle) =>
      haystack.toLowerCase().contains(needle);

  List<HomeServiceCategory> get _categoryHits {
    final String q = _query.toLowerCase();
    if (q.isEmpty) return const <HomeServiceCategory>[];
    return HomeServiceCategory.values
        .where(
          (HomeServiceCategory c) =>
              _matches(c.label, q) ||
              c.keywords.any((String k) => k.contains(q) || q.contains(k)),
        )
        .toList(growable: false);
  }

  List<IssueOption> get _issueHits {
    final String q = _query.toLowerCase();
    if (q.length < 2) return const <IssueOption>[];
    return IssueCatalog.all
        .where(
          (IssueOption i) =>
              _matches(i.label, q) || _matches(i.hintText, q),
        )
        .take(8)
        .toList(growable: false);
  }

  List<Technician> get _technicianHits {
    final String q = _query.toLowerCase();
    if (q.length < 2) return const <Technician>[];
    return _technicians
        .where(
          (Technician t) =>
              _matches(t.displayName, q) ||
              _matches(t.specializationLabel, q) ||
              t.skillTags.any((String s) => s.toLowerCase().contains(q)),
        )
        .take(8)
        .toList(growable: false);
  }

  bool get _noResults =>
      _query.length >= 2 &&
      _categoryHits.isEmpty &&
      _issueHits.isEmpty &&
      _technicianHits.isEmpty &&
      !_loadingTechnicians;

  // --------------------------------------------------------------- render

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.sm,
                AppSizes.sm,
                AppSizes.screenPadding,
                AppSizes.md,
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  ),
                  Expanded(
                    child: SugoSearchField(
                      controller: _input,
                      autofocus: true,
                      hint: 'Search services or technicians',
                      onChanged: _onChanged,
                      onSubmitted: (String value) {
                        if (value.trim().length >= 2) _remember(value.trim());
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _query.isEmpty ? _idle() : _results(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _idle() {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        0,
        AppSizes.screenPadding,
        AppSizes.xxl,
      ),
      children: <Widget>[
        if (_recent.isNotEmpty) ...<Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text('Recent searches', style: AppTextStyles.sectionTitle),
              ),
              TextButton(
                onPressed: () async {
                  final String? uid = _uid;
                  if (uid == null) return;
                  await _prefs.clearRecentSearches(uid);
                  if (mounted) setState(() => _recent = const <String>[]);
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.sm,
            children: <Widget>[
              for (final String query in _recent)
                _Chip(
                  label: query,
                  icon: Icons.history_rounded,
                  onTap: () => _run(query),
                ),
            ],
          ),
          const SizedBox(height: AppSizes.xl),
        ],
        const Text('Popular right now', style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSizes.sm),
        Wrap(
          spacing: AppSizes.sm,
          runSpacing: AppSizes.sm,
          children: <Widget>[
            for (final String query in _popular)
              _Chip(
                label: query,
                icon: Icons.trending_up_rounded,
                onTap: () => _run(query),
              ),
          ],
        ),
        const SizedBox(height: AppSizes.xl),
        const Text('Browse services', style: AppTextStyles.sectionTitle),
        const SizedBox(height: AppSizes.md),
        ServiceCategoryGrid(
          onSelect: (HomeServiceCategory category) => resolveHomeCategory(
            context,
            category,
            onResolved: (DeviceCategory? device) {
              _remember(category.label);
              if (device != null) widget.onCategory?.call(device);
            },
          ),
        ),
      ],
    );
  }

  Widget _results() {
    if (_noResults) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: <Widget>[
          SugoEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matches for "$_query"',
            message:
                'Try a simpler word like "aircon", "laptop" or "Wi-Fi" — or '
                'just describe the problem and we will classify it for you.',
            actionLabel: 'Describe my problem',
            onAction: () => widget.onCategory?.call(DeviceCategory.laptop),
          ),
        ],
      );
    }

    final List<HomeServiceCategory> categories = _categoryHits;
    final List<IssueOption> issues = _issueHits;
    final List<Technician> technicians = _technicianHits;

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        0,
        AppSizes.screenPadding,
        AppSizes.xxl,
      ),
      children: <Widget>[
        if (categories.isNotEmpty) ...<Widget>[
          const _ResultHeading(label: 'Services'),
          for (final HomeServiceCategory c in categories)
            _ResultRow(
              icon: c.icon,
              title: c.label,
              subtitle: 'Book a ${c.label.toLowerCase()} job',
              onTap: () => resolveHomeCategory(
                context,
                c,
                onResolved: (DeviceCategory? device) {
                  _remember(_query);
                  if (device != null) widget.onCategory?.call(device);
                },
              ),
            ),
          const SizedBox(height: AppSizes.lg),
        ],
        if (issues.isNotEmpty) ...<Widget>[
          const _ResultHeading(label: 'Problems'),
          for (final IssueOption issue in issues)
            _ResultRow(
              icon: issue.deviceType.icon,
              title: issue.label,
              subtitle: issue.hintText,
              onTap: () {
                _remember(issue.label);
                final DeviceCategory category = DeviceCategory.forJob(
                  deviceType: issue.deviceType,
                  symptomCode: issue.code,
                );
                widget.onIssue?.call(category, issue);
              },
            ),
          const SizedBox(height: AppSizes.lg),
        ],
        const _ResultHeading(label: 'Technicians'),
        if (_loadingTechnicians)
          const SugoSkeletonList(count: 2)
        else if (_technicianLoadFailed)
          SugoCard(
            elevation: SugoElevation.sm,
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 18,
                  color: AppColors.hint,
                ),
                const SizedBox(width: AppSizes.md),
                const Expanded(
                  child: Text(
                    'Technicians could not be loaded.',
                    style: AppTextStyles.caption,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _technicianLoadFailed = false);
                    _loadTechnicians();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        else if (technicians.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.sm),
            child: Text(
              'No technician matches "$_query".',
              style: AppTextStyles.caption,
            ),
          )
        else
          for (final Technician t in technicians)
            _TechnicianRow(
              technician: t,
              onTap: () {
                _remember(t.displayName);
                widget.onTechnician?.call(t);
              },
            ),
      ],
    );
  }
}

class _ResultHeading extends StatelessWidget {
  const _ResultHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSizes.sm,
        bottom: AppSizes.sm,
        left: AppSizes.xs,
      ),
      child: Text(label, style: AppTextStyles.overline),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      padding: const EdgeInsets.all(AppSizes.md),
      elevation: SugoElevation.sm,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppSizes.radius),
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.micro,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_outward_rounded,
            size: 17,
            color: AppColors.hint,
          ),
        ],
      ),
    );
  }
}

class _TechnicianRow extends StatelessWidget {
  const _TechnicianRow({required this.technician, required this.onTap});

  final Technician technician;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      padding: const EdgeInsets.all(AppSizes.md),
      elevation: SugoElevation.sm,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          SugoAvatar(
            name: technician.displayName,
            imageUrl: technician.avatarUrl,
            size: 42,
            verified: technician.isVerified,
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  technician.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  technician.specializationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.micro.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          SugoRatingLabel(
            rating: technician.rating,
            reviewCount: technician.reviewCount,
            size: 12,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md + 2,
            vertical: AppSizes.sm + 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.pillRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 14, color: AppColors.hint),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
