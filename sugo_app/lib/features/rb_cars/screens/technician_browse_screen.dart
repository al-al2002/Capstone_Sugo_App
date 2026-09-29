import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/local_prefs.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_loading.dart';
import '../../../core/widgets/sugo_pill.dart';
import '../../../core/widgets/sugo_search_field.dart';
import '../models/device_category.dart';
import '../models/technician.dart';
import '../services/rb_cars_service.dart';
import '../services/technician_directory_service.dart';
import '../widgets/technician_filter_sheet.dart';
import '../widgets/technician_list_card.dart';
import 'technician_detail_screen.dart';
import 'job_posting_screen.dart';

/// "Find a technician": the directory, with search, filters and sorting.
///
/// ## Why this exists beside the recommended row
///
/// The dashboard's row is a *shortlist* - since migration 20260921000007 a
/// technician needs 20 completed jobs and 4.0+ reviews to appear there, so it
/// answers "who does SUGO vouch for?". This screen answers a different
/// question: "who is there?". It lists every verified technician, newcomers
/// included, and lets the client apply their own standards instead of SUGO's.
///
/// It uses the `list` action of the `technician-directory` edge function,
/// which has existed since that function was written. No backend change was
/// needed to build this screen.
///
/// ## Why filtering happens on the device
///
/// The function returns at most 50 rows for a signed-in caller. Filtering and
/// sorting that in memory is instant and lets a filter change re-render
/// without a round trip - which is what makes the filter sheet feel like a
/// control rather than a form.
class TechnicianBrowseScreen extends StatefulWidget {
  const TechnicianBrowseScreen({
    super.key,
    this.latitude,
    this.longitude,
    this.initialFavoritesOnly = false,
    this.directory,
  });

  /// The client's position, so cards can carry distances and be sorted by
  /// them. Null simply removes the distance line and the "Nearest" sort.
  final double? latitude;
  final double? longitude;

  /// Opened from Profile -> Favourite technicians.
  final bool initialFavoritesOnly;

  /// Tests only.
  final TechnicianDirectoryService? directory;

  @override
  State<TechnicianBrowseScreen> createState() => _TechnicianBrowseScreenState();
}

class _TechnicianBrowseScreenState extends State<TechnicianBrowseScreen> {
  late final TechnicianDirectoryService _directory =
      widget.directory ?? TechnicianDirectoryService();
  final TextEditingController _search = TextEditingController();
  final LocalPrefs _prefs = LocalPrefs.instance;

  List<Technician> _all = const <Technician>[];
  Set<String> _favorites = <String>{};
  bool _loading = true;
  String? _error;
  String _query = '';

  late TechnicianFilters _filters = TechnicianFilters(
    favoritesOnly: widget.initialFavoritesOnly,
  );
  TechnicianSort _sort = TechnicianSort.recommended;

  String? get _uid => SupabaseService.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    final String? uid = _uid;
    if (uid != null) {
      _prefs.favoriteTechnicians(uid).then((Set<String> saved) {
        if (mounted) setState(() => _favorites = saved);
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<Technician> found = await _directory.browse(
        latitude: widget.latitude,
        longitude: widget.longitude,
      );
      if (!mounted) return;
      setState(() {
        _all = found;
        _loading = false;
        _error = null;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'We could not load the technician directory.';
      });
    }
  }

  Future<void> _toggleFavorite(Technician t) async {
    final String? uid = _uid;
    if (uid == null) return;
    final bool nowFavorite = await _prefs.toggleFavorite(uid, t.id);
    if (!mounted) return;
    setState(() {
      if (nowFavorite) {
        _favorites.add(t.id);
      } else {
        _favorites.remove(t.id);
      }
    });
  }

  void _openProfile(Technician t) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TechnicianDetailScreen(technicianId: t.id, initialTechnician: t),
      ),
    );
  }

  void _book(Technician t) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JobPostingScreen(preselectedTechnicianId: t.id),
      ),
    );
  }

  Future<void> _openFilters() async {
    final TechnicianFilters? applied = await showTechnicianFilterSheet(
      context,
      current: _filters,
      sort: _sort,
      canSortByDistance: widget.latitude != null,
      onSortChanged: (TechnicianSort s) => _sort = s,
    );
    if (applied != null && mounted) setState(() => _filters = applied);
  }

  List<Technician> get _visible {
    final String q = _query.trim().toLowerCase();

    final List<Technician> filtered = _all.where((Technician t) {
      if (_filters.favoritesOnly && !_favorites.contains(t.id)) return false;
      if (_filters.availableOnly && t.isAway) return false;
      if (_filters.minRating > 0 && t.rating < _filters.minRating) return false;
      if (_filters.maxDistanceKm != null) {
        final double? d = t.distanceKm;
        // A technician whose distance is unknown is kept: hiding someone
        // because we could not measure them is worse than showing them
        // without a distance line.
        if (d != null && d > _filters.maxDistanceKm!) return false;
      }
      if (_filters.maxHourlyFee != null &&
          t.indicativeHourlyFee > _filters.maxHourlyFee!) {
        return false;
      }
      if (_filters.categories.isNotEmpty) {
        final bool match = _filters.categories.any(
          (DeviceCategory c) => t.specialization.contains(c.deviceType.wire),
        );
        if (!match) return false;
      }
      if (q.isNotEmpty) {
        final bool hit =
            t.displayName.toLowerCase().contains(q) ||
            t.specializationLabel.toLowerCase().contains(q) ||
            t.skillTags.any((String s) => s.toLowerCase().contains(q));
        if (!hit) return false;
      }
      return true;
    }).toList();

    filtered.sort((Technician a, Technician b) => switch (_sort) {
      TechnicianSort.recommended => b.rating.compareTo(a.rating) != 0
          ? b.rating.compareTo(a.rating)
          : b.totalJobs.compareTo(a.totalJobs),
      TechnicianSort.nearest =>
        (a.distanceKm ?? double.infinity).compareTo(
          b.distanceKm ?? double.infinity,
        ),
      TechnicianSort.rating => b.rating.compareTo(a.rating),
      TechnicianSort.jobs => b.totalJobs.compareTo(a.totalJobs),
      TechnicianSort.price =>
        a.indicativeHourlyFee.compareTo(b.indicativeHourlyFee),
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final int activeFilters = _filters.activeCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: SugoAppBar(
        title: _filters.favoritesOnly ? 'Favourite technicians' : 'Find a technician',
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPadding,
              0,
              AppSizes.screenPadding,
              AppSizes.md,
            ),
            child: SugoSearchField(
              controller: _search,
              hint: 'Search by name or skill',
              onChanged: (String value) => setState(() => _query = value),
            ),
          ),
          SizedBox(
            height: AppSizes.filterTabHeight + AppSizes.sm,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.screenPadding,
              ),
              children: <Widget>[
                SugoPill(
                  label: activeFilters == 0
                      ? 'Filters'
                      : 'Filters · $activeFilters',
                  icon: Icons.tune_rounded,
                  selected: activeFilters > 0,
                  onTap: _openFilters,
                ),
                const SizedBox(width: AppSizes.sm),
                SugoPill(
                  label: _sort.label,
                  icon: Icons.swap_vert_rounded,
                  onTap: _openFilters,
                ),
                if (_filters.favoritesOnly) ...<Widget>[
                  const SizedBox(width: AppSizes.sm),
                  SugoPill(
                    label: 'Favourites',
                    icon: Icons.favorite_rounded,
                    selected: true,
                    onTap: () => setState(
                      () => _filters = _filters.copyWith(favoritesOnly: false),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: const <Widget>[SugoSkeletonCards.technicians(count: 4)],
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: <Widget>[
          SugoEmptyState.error(
            title: 'Unable to load technicians',
            message: '$_error Check your connection, then try again.',
            onAction: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            },
          ),
        ],
      );
    }

    final List<Technician> visible = _visible;

    if (visible.isEmpty) {
      final bool filtered = _filters.activeCount > 0 || _query.isNotEmpty;
      return ListView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: <Widget>[
          SugoEmptyState(
            icon: _filters.favoritesOnly
                ? Icons.favorite_border_rounded
                : Icons.person_search_rounded,
            title: _filters.favoritesOnly
                ? 'No favourites yet'
                : filtered
                ? 'Nobody matches those filters'
                : 'No technicians listed yet',
            message: _filters.favoritesOnly
                ? 'Tap the heart on any technician to keep them here for next '
                      'time. Favourites are saved on this phone.'
                : filtered
                ? 'Try widening the distance or lowering the minimum rating.'
                : 'Technicians appear here once they have passed SUGO '
                      'verification.',
            actionLabel: filtered ? 'Reset filters' : null,
            onAction: filtered
                ? () => setState(() {
                    _filters = const TechnicianFilters();
                    _search.clear();
                    _query = '';
                  })
                : null,
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPadding,
          AppSizes.sm,
          AppSizes.screenPadding,
          AppSizes.xxl,
        ),
        itemCount: visible.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.md),
              child: Text(
                '${visible.length} technician${visible.length == 1 ? '' : 's'}'
                '${_filters.activeCount > 0 ? ' match your filters' : ' available'}',
                style: AppTextStyles.micro,
              ),
            );
          }
          final Technician t = visible[index - 1];
          return TechnicianListCard(
            technician: t,
            isFavorite: _favorites.contains(t.id),
            onToggleFavorite: () => _toggleFavorite(t),
            onOpen: () => _openProfile(t),
            onBook: () => _book(t),
          );
        },
      ),
    );
  }
}
