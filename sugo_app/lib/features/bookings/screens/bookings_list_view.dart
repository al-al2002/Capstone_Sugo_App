import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_delete_animation.dart';
import '../../../core/widgets/sugo_dialog.dart';
import '../../../core/widgets/sugo_empty_state.dart';
import '../../../core/widgets/sugo_loading.dart';
import '../../../core/widgets/sugo_motion.dart';
import '../../../core/widgets/sugo_route_line.dart';
import '../../../core/widgets/sugo_status_badge.dart';
import '../../chat/screens/chat_thread_screen.dart';
import '../../client/widgets/home_sections.dart';
import '../../rb_cars/models/job.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../profile/profile_navigation.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/models/job_price.dart';
import '../../rb_cars/models/job_party.dart';
import '../../rb_cars/models/technician_profile_details.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../rb_cars/widgets/review_card.dart';
import '../../technician/services/technician_service.dart';
import '../models/booking_route.dart';
import '../widgets/rate_job_sheet.dart';
import 'job_detail_screen.dart';
import '../../tracking/models/job_tracking.dart';
import '../../tracking/services/tracking_service.dart';
import '../../tracking/widgets/return_method_card.dart';
import '../../rb_cars/widgets/booking_pause.dart';

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
///
/// Renovated 2026-11-17 ("Dispatch, levelled up"): a summary band with the
/// active count, the sliding segmented filter, cards that deal in (again on
/// every filter change, for the cards that are new to the view), a stage
/// strip on each card, and animated empty states. What each card says is
/// unchanged.
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

  /// Cards deal in when the list first appears and when the filter changes;
  /// a card already on screen keeps its place rather than replaying.
  bool _entrancePlayed = false;

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

      // A technician-community question is not a booking until the client
      // chooses a service route. Keep it in the jobs table so it can be
      // converted later, but do not present it in the client's booking list.
      final List<Job> visibleJobs = widget.role == BookingsRole.client
          ? jobs
                .where((Job job) => job.servicePath != ServicePath.itCommunity)
                .toList(growable: false)
          : jobs;

      // Never throws - a failed lookup just means no chips this time.
      final Map<String, ReturnMethod> methods =
          widget.role == BookingsRole.technician
          ? await TrackingService().returnMethods(<String>[
              for (final Job job in visibleJobs)
                if (job.servicePath == ServicePath.pickup &&
                    job.status != JobStatus.completed &&
                    job.status != JobStatus.cancelled)
                  job.id,
            ])
          : const <String, ReturnMethod>{};

      if (!mounted) return;
      setState(() {
        _jobs = visibleJobs;
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
  /// Deletes a request nobody has taken yet, from the list itself
  /// (2026-09-29), under the same bin animation as everywhere else.
  Future<void> _delete(Job job) async {
    final bool confirmed = await showSugoConfirmDialog(
      context: context,
      icon: Icons.delete_outline_rounded,
      iconColor: AppColors.textPrimary,
      iconTint: AppColors.divider,
      title: 'Delete this request?',
      message:
          'Nobody has taken it yet, so it will be removed along with the '
          'matches we found. This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    try {
      // The bin says "Request deleted" itself, so no snackbar.
      final DateTime? paused = (await runWithDeleteAnimation(
        context,
        _clientService.deleteJob(job.id),
      )).bookingPausedUntil;
      if (!mounted) return;
      // Deleting while a technician was booked counts as a cancel.
      if (paused != null) showBookingPausedNotice(context, paused);
      await _load();
    } on RbCarsFailure catch (failure) {
      if (mounted) UiFeedback.showError(context, failure.message);
    }
  }

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
    final Map<BookingFilter, int>? counts = _isLoading ? null : _counts;
    return Column(
      children: <Widget>[
        BookingsTitle(
          title: widget.role == BookingsRole.client ? 'Bookings' : 'Jobs',
          subtitle: widget.role == BookingsRole.client
              ? 'Everything you have booked with SUGO'
              : 'Work you have accepted',
          activeCount: counts?[BookingFilter.active],
          doneCount: counts?[BookingFilter.completed],
        ),
        BookingFilterTabs(
          selected: _filter,
          counts: counts,
          onChanged: (BookingFilter filter) => setState(() {
            if (filter != _filter) _entrancePlayed = false;
            _filter = filter;
          }),
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

    final bool animate = !_entrancePlayed;
    if (animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _entrancePlayed = true;
      });
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
              itemBuilder: (BuildContext context, int index) {
                final Job job = _visible[index];
                return SugoRiseIn(
                  key: ValueKey<String>('rise-${job.id}'),
                  enabled: animate,
                  delay: AppMotion.staggerDelay(index),
                  child: BookingCard(
                    key: ValueKey<String>(job.id),
                    job: job,
                    role: widget.role,
                    party: _parties[job.id],
                    clientCollects:
                        _returnMethods[job.id] == ReturnMethod.clientPickup,
                    onReturn: _load,
                    onRate: () => _rate(job),
                    onDelete:
                        widget.role == BookingsRole.client &&
                            job.canBeDeletedByClient
                        ? () => _delete(job)
                        : null,
                  ),
                );
              },
            ),
    );
  }

  Widget _emptyState() {
    final bool isClient = widget.role == BookingsRole.client;

    return _EmptyBookings(
      key: ValueKey<BookingFilter>(_filter),
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

/// The screen's name on the brand band, with the active count beside it.
///
/// Public, like [JobStatusChip] and the two below it, so the golden in
/// `test/features/bookings` can pose the list without a Supabase round trip -
/// [BookingsListView] loads in `initState`, so the assembled screen is not
/// renderable offline.
///
/// Since 2026-11-17 a navy band rather than a plain heading: the same summary
/// band as the inbox and the notifications, so every list in the app opens
/// the same way. The counts are null while loading, which hides the bubble
/// rather than showing zeros.
class BookingsTitle extends StatelessWidget {
  const BookingsTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.activeCount,
    this.doneCount,
  });

  final String title;
  final String? subtitle;

  /// Bookings still in play, and finished ones.
  final int? activeCount;
  final int? doneCount;

  @override
  Widget build(BuildContext context) {
    final int? active = activeCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.md,
        AppSizes.screenPadding,
        AppSizes.md,
      ),
      child: SugoRiseIn(
        child: SugoHeroBand(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 24,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.micro.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                    if (doneCount != null && doneCount! > 0) ...<Widget>[
                      const SizedBox(height: AppSizes.sm),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: AppColors.cyan,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$doneCount completed',
                            style: AppTextStyles.micro.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (active != null) ...<Widget>[
                const SizedBox(width: AppSizes.md),
                Container(
                  width: 70,
                  padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppSizes.radius + 4),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SugoCountUp(
                        value: active,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 24,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'active',
                        style: AppTextStyles.micro.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
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
///
/// Since 2026-11-17 the shared [SugoSegmentedFilter], whose highlight slides
/// to the chosen tab - the same control as the inbox's.
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
      child: SugoSegmentedFilter<BookingFilter>(
        selected: selected,
        onChanged: onChanged,
        segments: <SugoSegment<BookingFilter>>[
          for (final BookingFilter filter in BookingFilter.values)
            SugoSegment<BookingFilter>(
              value: filter,
              label: filter.label,
              count: counts?[filter],
            ),
        ],
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
    this.onDelete,
    this.clientCollects = false,
  });

  /// Deletes the request. Non-null only for a client's job nobody has taken.
  final VoidCallback? onDelete;

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
          // Where the booking is on its route (2026-11-17): the same four
          // stops as the detail screen's route line, from `jobs.status`
          // alone. A cancelled booking is going nowhere, so it has none.
          if (BookingRoute.forStatus(
                job.status,
                offerPending: party?.technicianIsRequest ?? false,
              )
              case final SugoRoutePosition at) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            _StageStrip(position: at),
          ],
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
        // The device on a gradient tile in the booking's own colour
        // (2026-11-17): brand while live, green when fixed, grey when
        // cancelled - the state reads before a word does.
        Container(
          width: AppSizes.iconTile,
          height: AppSizes.iconTile,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSizes.radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _tileColors(job.status),
            ),
          ),
          child: Icon(job.deviceType.icon, size: 22, color: Colors.white),
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
          // The quoted price, not the budget range (2026-11-17): the total
          // when the distance fee is known - a shop repair saves it - else
          // the labor fee for the symptom.
          child: Builder(
            builder: (BuildContext context) {
              final JobPrice price = JobPrice.forJob(job);
              return _Fact(
                icon: Icons.payments_rounded,
                label: price.total != null ? 'Est. total' : 'Labor fee',
                value: price.headline,
              );
            },
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
          if (onDelete != null) ...<Widget>[
            _DeleteButton(onPressed: onDelete!),
            const SizedBox(width: AppSizes.sm),
          ],
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
            // A request still waiting on the technician can be dropped here.
            if (onDelete != null) ...<Widget>[
              const SizedBox(width: AppSizes.sm),
              _DeleteButton(onPressed: onDelete!),
            ],
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

  static List<Color> _tileColors(JobStatus status) => switch (status) {
    JobStatus.completed => const <Color>[AppColors.success, Color(0xFF34C77B)],
    JobStatus.cancelled => const <Color>[
      AppColors.hint,
      AppColors.textSecondary,
    ],
    _ => const <Color>[AppColors.primary, AppColors.secondary],
  };

  String _unassignedLabel() => switch (job.status) {
    JobStatus.pending => 'Finding your technician',
    JobStatus.matched => 'Choose from your matches',
    JobStatus.cancelled => 'Nobody was assigned',
    _ => 'Not assigned yet',
  };
}

/// A booking's place on its route, as four stops joined by a track that
/// fills to the current position once, when the card appears (2026-11-17).
///
/// The stops are [BookingRoute.stops] - Posted, Matched, Booked, Fixed - and
/// the position comes from `jobs.status` through [BookingRoute.forStatus], so
/// the strip never shows progress the database has not recorded. Between two
/// stops it fills half way, exactly as the route line does.
class _StageStrip extends StatelessWidget {
  const _StageStrip({required this.position});

  final SugoRoutePosition position;

  /// Short enough to finish inside the list golden's fixed 700 ms frame.
  static const Duration _fill = Duration(milliseconds: 650);

  @override
  Widget build(BuildContext context) {
    final int last = BookingRoute.stops.length - 1;
    final String here = BookingRoute.stops[position.stop];
    final bool reduced = AppMotion.reduced(context);

    return Semantics(
      label: 'Step ${position.stop + 1} of ${last + 1}: $here',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: position.progress / last),
              duration: reduced ? Duration.zero : _fill,
              curve: AppMotion.emphasized,
              builder: (BuildContext context, double fill, Widget? _) {
                return SizedBox(
                  height: 14,
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints box) {
                      final double w = box.maxWidth;
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: <Widget>[
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.divider,
                              borderRadius: BorderRadius.circular(
                                AppSizes.pillRadius,
                              ),
                            ),
                          ),
                          Container(
                            width: w * fill,
                            height: 4,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: <Color>[
                                  AppColors.primary,
                                  AppColors.cyan,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(
                                AppSizes.pillRadius,
                              ),
                            ),
                          ),
                          for (int i = 0; i <= last; i++)
                            Positioned(
                              left: (w - 12) * i / last,
                              child: _StopDot(
                                reached: fill * last >= i - 0.001,
                                current: i == position.stop && !position.moving,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Text(
            '${position.stop + 1}/${last + 1} · $here',
            style: AppTextStyles.micro.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StopDot extends StatelessWidget {
  const _StopDot({required this.reached, required this.current});

  final bool reached;
  final bool current;

  @override
  Widget build(BuildContext context) {
    // Not animated itself: it lights the moment the fill reaches it, which
    // is the motion. Its own fade would lag a beat behind the fill.
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: reached ? AppColors.primary : AppColors.surface,
        border: Border.all(
          color: reached ? AppColors.primary : AppColors.border,
          width: 2,
        ),
        boxShadow: current
            ? <BoxShadow>[
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.45),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
    );
  }
}

/// An empty tab: its icon swinging once on a gradient disc, then the words,
/// then the action when there is one. Replays when the tab changes, because
/// the key does.
class _EmptyBookings extends StatelessWidget {
  const _EmptyBookings({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SugoRiseIn(
          child: Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.primarySoft, AppColors.cyanSoft],
              ),
            ),
            child: SugoWiggle(
              swings: 2,
              angle: 0.22,
              alignment: Alignment.bottomCenter,
              child: Icon(icon, size: 42, color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        SugoRiseIn(
          delay: AppMotion.staggerDelay(2),
          child: Column(
            children: <Widget>[
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.title,
              ),
              const SizedBox(height: AppSizes.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.subtitle,
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null) ...<Widget>[
          const SizedBox(height: AppSizes.xl),
          SugoRiseIn(
            delay: AppMotion.staggerDelay(4),
            child: SugoButton(
              label: actionLabel!,
              icon: Icons.add_rounded,
              expand: false,
              onPressed: onAction,
            ),
          ),
        ],
      ],
    );
  }
}

/// The bin on a booking card: an icon button, red, with its name for screen
/// readers and a long press. Small, because on a card it sits beside the main
/// action and must not compete with it.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Delete request',
      onPressed: onPressed,
      icon: const Icon(Icons.delete_outline_rounded),
      color: AppColors.error,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.errorSoft,
        minimumSize: const Size.square(AppSizes.compactButtonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
      ),
    );
  }
}

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
