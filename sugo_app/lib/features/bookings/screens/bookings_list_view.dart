import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_loading.dart';
import '../../../core/widgets/sugo_status_badge.dart';
import '../../chat/screens/chat_thread_screen.dart';
import '../../client/widgets/home_sections.dart';
import '../../rb_cars/models/job.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../profile/profile_navigation.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/models/job_party.dart';
import '../../rb_cars/models/technician_profile_details.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../rb_cars/widgets/review_card.dart';
import '../../technician/services/technician_service.dart';
import '../widgets/rate_job_sheet.dart';
import 'job_detail_screen.dart';
import '../../tracking/models/job_tracking.dart';
import '../../tracking/services/tracking_service.dart';
import '../../tracking/widgets/return_method_card.dart';

/// The Bookings tab for a client and the Jobs tab for a technician.
///
/// One widget for both, because the list is the same list seen from opposite
/// ends: the same `jobs` rows, the same statuses, the same actions. What
/// differs is which rows the caller can see, and RLS already decides that -
/// `jobs_client_select_own` for one side, `jobs_technician_select_assigned`
/// for the other. Two screens would mean two copies of the status chips, the
/// filters and the empty states, drifting apart on every change.
///
/// The [role] only changes wording and which service loads the rows.
enum BookingsRole { client, technician }

class BookingsListView extends StatefulWidget {
  const BookingsListView({super.key, required this.role, this.onPostJob});

  final BookingsRole role;

  /// Client only: the empty state offers to start a booking.
  final VoidCallback? onPostJob;

  @override
  State<BookingsListView> createState() => _BookingsListViewState();
}

/// Which slice of the list is showing.
///
/// "Active" is everything still in play, not a single status - a client
/// thinking about their booking does not care whether it is `matched` or
/// `in_progress`, only whether it is still happening.
enum BookingFilter {
  active('Active'),
  completed('Completed'),
  cancelled('Cancelled');

  const BookingFilter(this.label);

  final String label;

  bool matches(JobStatus status) => switch (this) {
    BookingFilter.active =>
      status != JobStatus.completed && status != JobStatus.cancelled,
    BookingFilter.completed => status == JobStatus.completed,
    BookingFilter.cancelled => status == JobStatus.cancelled,
  };
}

class _BookingsListViewState extends State<BookingsListView> {
  final RbCarsService _clientService = RbCarsService();
  final TechnicianService _technicianService = TechnicianService();

  List<Job> _jobs = const <Job>[];

  /// Who is on each job, and the caller's own rating of the other person.
  /// Loaded beside the jobs in one request for the whole list.
  Map<String, JobParty> _parties = const <String, JobParty>{};

  /// Technician only: the workshop jobs whose client is collecting the unit
  /// themselves, so the card can say "Client pick-up" before it is opened.
  Map<String, ReturnMethod> _returnMethods = const <String, ReturnMethod>{};

  BookingFilter _filter = BookingFilter.active;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // `assignedJobs`, not `activeJobs`, for a technician. `activeJobs` only
      // returns confirmed and in-progress work, so the Completed and
      // Cancelled tabs of this very list could never show anything.
      final (List<Job> jobs, Map<String, JobParty> parties) = await (
        widget.role == BookingsRole.client
            ? _clientService.myJobs()
            : _technicianService.assignedJobs(),
        // Never fatal - an empty map just means no names this time.
        _clientService.jobParties(),
      ).wait;

      // Never throws - a failed lookup just means no chips this time.
      final Map<String, ReturnMethod> methods =
          widget.role == BookingsRole.technician
          ? await TrackingService().returnMethods(<String>[
              for (final Job job in jobs)
                if (job.servicePath == ServicePath.pickup &&
                    job.status != JobStatus.completed &&
                    job.status != JobStatus.cancelled)
                  job.id,
            ])
          : const <String, ReturnMethod>{};

      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _parties = parties;
        _returnMethods = methods;
        _isLoading = false;
        _error = null;
      });
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load your jobs.';
      });
    }
  }

  /// Rates the other person on a completed job, straight from the list.
  ///
  /// Looks up any existing rating first, so tapping the stars of a job
  /// already rated opens the sheet to *edit* that rating rather than trying
  /// to write a second one the unique constraint would refuse.
  Future<void> _rate(Job job) async {
    final JobParty? party = _parties[job.id];
    final bool isClient = widget.role == BookingsRole.client;

    final bool saved;
    if (isClient) {
      final String? technicianId = job.assignedTechnicianId;
      if (technicianId == null) return;
      final TechnicianReview? existing = await _clientService.myReview(job.id);
      if (!mounted) return;
      saved = await RateJobSheet.show(
        context,
        jobId: job.id,
        technicianId: technicianId,
        technicianName: party?.technicianLabel ?? 'your technician',
        existing: existing,
      );
    } else {
      final TechnicianReview? existing = await _clientService.myClientReview(
        job.id,
      );
      if (!mounted) return;
      saved = await RateJobSheet.showForClient(
        context,
        jobId: job.id,
        clientId: job.clientId,
        clientName: party?.clientLabel ?? 'this client',
        existing: existing,
      );
    }

    if (saved) await _load();
  }

  List<Job> get _visible =>
      _jobs.where((Job job) => _filter.matches(job.status)).toList();

  /// How many jobs sit under each tab, so the counts are on the control
  /// itself rather than discovered by tapping through.
  Map<BookingFilter, int> get _counts => <BookingFilter, int>{
    for (final BookingFilter f in BookingFilter.values)
      f: _jobs.where((Job job) => f.matches(job.status)).length,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        BookingsTitle(
          title: widget.role == BookingsRole.client ? 'Bookings' : 'Jobs',
          subtitle: widget.role == BookingsRole.client
              ? 'Everything you have booked with SUGO'
              : 'Work you have accepted',
        ),
        BookingFilterTabs(
          selected: _filter,
          counts: _isLoading ? null : _counts,
          onChanged: (BookingFilter filter) => setState(() => _filter = filter),
        ),
        const SizedBox(height: AppSizes.md),
        Expanded(child: _content()),
      ],
    );
  }

  Widget _content() {
    if (_isLoading) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
        children: const <Widget>[SugoSkeletonCards.bookings(count: 3)],
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSizes.screenPadding),
        children: <Widget>[
          SugoEmptyState.error(
            title: 'Unable to load your bookings',
            message: '$_error Check your connection, then try again.',
            onAction: () {
              setState(() => _isLoading = true);
              _load();
            },
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: _visible.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(AppSizes.screenPadding),
              children: <Widget>[
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.06),
                _emptyState(),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.screenPadding,
                0,
                AppSizes.screenPadding,
                AppSizes.xxl + AppSizes.xl,
              ),
              itemCount: _visible.length,
              itemBuilder: (BuildContext context, int index) => BookingCard(
                key: ValueKey<String>(_visible[index].id),
                job: _visible[index],
                role: widget.role,
                party: _parties[_visible[index].id],
                clientCollects:
                    _returnMethods[_visible[index].id] ==
                    ReturnMethod.clientPickup,
                onReturn: _load,
                onRate: () => _rate(_visible[index]),
              ),
            ),
    );
  }

  Widget _emptyState() {
    final bool isClient = widget.role == BookingsRole.client;

    return SugoEmptyState(
      icon: switch (_filter) {
        BookingFilter.active => Icons.event_note_outlined,
        BookingFilter.completed => Icons.verified_outlined,
        BookingFilter.cancelled => Icons.cancel_outlined,
      },
      title: switch (_filter) {
        BookingFilter.active =>
          isClient ? 'No active bookings' : 'No active jobs',
        BookingFilter.completed => 'Nothing completed yet',
        BookingFilter.cancelled => 'Nothing cancelled',
      },
      message: switch (_filter) {
        BookingFilter.active =>
          isClient
              ? 'Post a repair and we will rank the three best technicians '
                    'near you.'
              : 'Accepted jobs appear here. New requests arrive on your '
                    'dashboard.',
        BookingFilter.completed =>
          isClient
              ? 'Finished repairs are kept here with their receipts and '
                    'ratings.'
              : 'Jobs you finish will be listed here.',
        BookingFilter.cancelled => 'Cancelled bookings are kept for reference.',
      },
      actionLabel: isClient && _filter == BookingFilter.active
          ? 'Book a repair'
          : null,
      onAction: isClient && _filter == BookingFilter.active
          ? widget.onPostJob
          : null,
    );
  }
}

/// The screen's name, with the accent rule beside it.
///
/// Public, like [JobStatusChip] and the two below it, so the golden in
/// `test/features/bookings` can pose the list without a Supabase round trip -
/// [BookingsListView] loads in `initState`, so the assembled screen is not
/// renderable offline.
class BookingsTitle extends StatelessWidget {
  const BookingsTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.lg,
        AppSizes.screenPadding,
        AppSizes.lg,
      ),
      // A plain heading since the Dispatch redesign. The navy bar that used
      // to stand to its left said nothing the heading did not - an accent
      // rail beside a title is template chrome, not information.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.headline,
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption,
            ),
          ],
        ],
      ),
    );
  }
}

/// The three filters as one segmented control.
///
/// Three fixed options in a fixed track say "these are all your choices" - a
/// scrolling row of pills implies there might be more to the right, and there
/// never was. Each carries its count, so the shape of someone's history is
/// readable without tapping through the tabs.
class BookingFilterTabs extends StatelessWidget {
  const BookingFilterTabs({
    super.key,
    required this.selected,
    required this.onChanged,
    this.counts,
  });

  final BookingFilter selected;
  final ValueChanged<BookingFilter> onChanged;

  /// Null while loading, which hides the numbers rather than showing zeros.
  final Map<BookingFilter, int>? counts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.fieldRadius),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: BookingFilter.values
              .map((BookingFilter filter) {
                final bool active = filter == selected;
                final int? count = counts?[filter];

                return Expanded(
                  child: Semantics(
                    button: true,
                    selected: active,
                    label: count == null
                        ? filter.label
                        : '${filter.label}, $count',
                    excludeSemantics: true,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onChanged(filter),
                        borderRadius: BorderRadius.circular(AppSizes.sm + 2),
                        child: AnimatedContainer(
                          duration: AppMotion.base,
                          curve: AppMotion.standard,
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSizes.sm + 2,
                            horizontal: AppSizes.xs,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              AppSizes.sm + 2,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  filter.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: active
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: active
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              if (count != null && count > 0) ...<Widget>[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? Colors.white.withValues(alpha: 0.22)
                                        : AppColors.divider,
                                    borderRadius: BorderRadius.circular(
                                      AppSizes.pillRadius,
                                    ),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: active
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
        ),
      ),
    );
  }
}

/// One booking in the list.
///
/// ## What the redesign changed
///
/// The card used to be four labelled rows - Status, Schedule, Service
/// provider - each with a grey caption under a bold value. That is a form,
/// not a card: every row had the same weight, so nothing was findable at a
/// glance.
///
/// Now it leads with the thing being repaired and its reference, carries the
/// status as a badge with an icon, puts the facts on one compact line, and
/// ends with the person and the actions. The price is on the card because
/// "what is this going to cost" is the second question anybody asks about a
/// booking, and it used to be a tap away.
class BookingCard extends StatelessWidget {
  const BookingCard({
    super.key,
    required this.job,
    required this.role,
    required this.onReturn,
    this.party,
    this.onRate,
    this.clientCollects = false,
  });

  final Job job;
  final BookingsRole role;

  /// The client is collecting the unit at the workshop - shown to the
  /// technician as "Client pick-up", so there is no delivery trip planned.
  final bool clientCollects;

  /// Who is on the job. Null when the lookup has not returned or failed - the
  /// card then falls back to the unnamed labels it always had.
  final JobParty? party;

  /// Opens the rating sheet for the other person. Offered on completed jobs.
  final VoidCallback? onRate;

  /// Re-reads the list when the detail screen comes back, because a stage
  /// change made over there can move this row into another filter tab.
  final Future<void> Function() onReturn;

  /// Chat opens only once somebody is assigned - matching the RLS rule, so the
  /// button is never offered for a thread the database would refuse.
  bool get _canChat => job.assignedTechnicianId != null;

  bool get _isClient => role == BookingsRole.client;

  /// Opens the full booking. The card shows what is worth scanning;
  /// everything else - the timeline, the photos, the live delivery leg -
  /// lives one tap in.
  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JobDetailScreen(job: job, role: role),
      ),
    );
    await onReturn();
  }

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      onTap: () => _open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _header(),
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: jobStatusBadge(job.status),
                ),
              ),
              if (clientCollects) ...<Widget>[
                const SizedBox(width: AppSizes.sm),
                const ClientPickupChip(),
              ],
            ],
          ),
          // No divider under the status since the Dispatch redesign: the
          // card's own edge already frames it, and a rule across the middle
          // of a card makes it read as two boxes.
          const SizedBox(height: AppSizes.lg),
          _facts(),
          const SizedBox(height: AppSizes.md),
          _providerRow(context),

          // Completed work carries its rating on the card itself, so the
          // Completed tab reads as a record - what was done, with whom, and
          // how it went - rather than a list of closed tickets.
          if (job.status == JobStatus.completed &&
              (role == BookingsRole.technician ||
                  job.assignedTechnicianId != null)) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            _ratingRow(),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: <Widget>[
        // The same hairline device tile as the matching screen's summary.
        Container(
          width: AppSizes.iconTile,
          height: AppSizes.iconTile,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radius),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(job.deviceType.icon, size: 22, color: AppColors.primary),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                job.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                job.reference,
                // Secondary ink, not hint: hint is 3:1 on white, for
                // placeholders only.
                style: AppTextStyles.micro.copyWith(
                  color: AppColors.textSecondary,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Schedule and price on one line, because they answer the two questions a
  /// booking list is scanned for: when, and how much.
  Widget _facts() {
    final DateTime? when = job.preferredSchedule;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: _Fact(
            icon: Icons.calendar_today_rounded,
            label: 'Schedule',
            // No deadline is a real answer, not a gap: it is what "Flexible"
            // on the posting flow writes, and saying so beats an empty line.
            value: when == null ? 'Flexible' : Fmt.shortDateTime(when),
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: _Fact(
            icon: Icons.payments_rounded,
            label: 'Budget',
            value: job.budgetLabel,
          ),
        ),
      ],
    );
  }

  Widget _providerRow(BuildContext context) {
    final JobParty? who = party;

    // The other person, by name, now that `job_parties` can resolve it. This
    // row used to print "Technician assigned" because a `jobs` row has ids
    // and nothing else, and `profiles` is readable only by its owner.
    final String? name = who == null
        ? null
        : _isClient
        ? (who.hasTechnician ? who.technicianLabel : null)
        : who.clientLabel;
    final String? avatar = who == null
        ? null
        : _isClient
        ? who.technicianAvatarUrl
        : who.clientAvatarUrl;
    final String? personId = who == null
        ? null
        : _isClient
        ? who.technicianId
        : who.clientId;
    final bool isRequest = _isClient && (who?.technicianIsRequest ?? false);

    if (name == null) {
      return Row(
        children: <Widget>[
          const Icon(
            Icons.person_search_rounded,
            size: 18,
            color: AppColors.hint,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(_unassignedLabel(), style: AppTextStyles.caption),
          ),
          SugoButton(
            label: 'View',
            variant: SugoButtonVariant.tonal,
            size: SugoButtonSize.small,
            expand: false,
            onPressed: () => _open(context),
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(AppSizes.tileRadius),
          onTap: personId == null
              ? null
              : () => openPersonProfile(
                  context,
                  userId: personId,
                  role: _isClient ? 'technician' : 'client',
                  name: name,
                  avatarUrl: avatar,
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: <Widget>[
                SugoAvatar(name: name, imageUrl: avatar, size: 38),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.titleSmall,
                      ),
                      const SizedBox(height: 1),
                      // A request is labelled as one. Naming the person the
                      // client is waiting on is the point; calling it a
                      // booking before they accept would not be true.
                      Text(
                        isRequest
                            ? 'Requested — waiting for them to accept'
                            : _isClient
                            ? 'Your technician'
                            : 'Your client',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.micro.copyWith(
                          color: isRequest
                              ? AppColors.warning
                              : AppColors.textSecondary,
                          fontWeight: isRequest
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.hint,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSizes.md),
        Row(
          children: <Widget>[
            if (_canChat) ...<Widget>[
              Expanded(
                child: SugoButton(
                  label: 'Message',
                  icon: Icons.chat_bubble_outline_rounded,
                  variant: SugoButtonVariant.tonal,
                  size: SugoButtonSize.small,
                  onPressed: () => openChatThread(
                    context,
                    jobId: job.id,
                    title: name,
                    avatarUrl: avatar,
                    subtitle: jobThreadSubtitle(
                      job.deviceType.wire,
                      job.problemSymptom,
                      job.status,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.md),
            ],
            Expanded(
              child: SugoButton(
                label: 'View details',
                variant: SugoButtonVariant.outlined,
                size: SugoButtonSize.small,
                onPressed: () => _open(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The caller's rating of the other person, or a prompt to give one.
  Widget _ratingRow() {
    final int? stars = party?.myRating;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm + 2,
      ),
      decoration: BoxDecoration(
        color: stars == null ? AppColors.accentSofter : AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(
          color: stars == null ? AppColors.accentSoft : AppColors.border,
        ),
      ),
      child: Row(
        children: <Widget>[
          if (stars != null) ...<Widget>[
            StarRow(rating: stars.toDouble(), size: 18),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(
                'You rated $stars/5',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.micro.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ] else ...<Widget>[
            const Icon(
              Icons.star_outline_rounded,
              size: 18,
              color: AppColors.accent,
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Text(
                _isClient ? 'How did the repair go?' : 'How was this client?',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.micro.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
          if (onRate != null)
            TextButton(
              onPressed: onRate,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentDark,
              ),
              child: Text(
                stars == null ? 'Rate' : 'Edit',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }

  String _unassignedLabel() => switch (job.status) {
    JobStatus.pending => 'Finding your technician',
    JobStatus.matched => 'Choose from your matches',
    JobStatus.cancelled => 'Nobody was assigned',
    _ => 'Not assigned yet',
  };
}

/// A small icon, a caption and the value under it.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: AppColors.hint),
        ),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(label, style: AppTextStyles.micro),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyStrong.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The status pill, shared by the bookings list and the detail screen.
///
/// Kept as a named widget because two screens and a golden test use it; it is
/// now a thin wrapper over [SugoStatusBadge], so status colours and icons are
/// decided in exactly one place ([jobStatusBadge]).
class JobStatusChip extends StatelessWidget {
  const JobStatusChip({super.key, required this.status, this.dense = false});

  final JobStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) => jobStatusBadge(status, dense: dense);
}
