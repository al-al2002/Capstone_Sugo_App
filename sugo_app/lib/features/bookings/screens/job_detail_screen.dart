import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_dialog.dart';
import '../../../core/widgets/sugo_delete_animation.dart';
import '../../../core/widgets/sugo_image_viewer.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../../../core/widgets/sugo_timeline.dart';
import '../../chat/screens/chat_thread_screen.dart';
import '../../client/widgets/home_sections.dart';
import '../models/booking_route.dart';
import '../../disputes/models/job_dispute.dart';
import '../../disputes/services/dispute_service.dart';
import '../../disputes/widgets/dispute_section.dart';
import '../../disputes/widgets/report_problem_sheet.dart';
import '../../rb_cars/models/device_category.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/screens/client_review_screen.dart';
import '../../rb_cars/screens/job_posting_screen.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../tracking/models/job_tracking.dart';
import '../../tracking/screens/job_tracking_screen.dart';
import '../../tracking/screens/technician_delivery_screen.dart';
import '../../tracking/services/tracking_service.dart';
import '../../tracking/widgets/return_method_card.dart';
import 'bookings_list_view.dart';
import '../../rb_cars/models/technician_profile_details.dart';
import '../../rb_cars/models/job_party.dart';
import '../../rb_cars/widgets/review_card.dart';
import '../../profile/profile_navigation.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_route_line.dart';
import '../widgets/rate_job_sheet.dart';

/// Everything about one booking, from either end.
///
/// ## Why one screen for both roles
///
/// The same reason [BookingsListView] is one widget: this is the same `jobs`
/// row seen from opposite ends, and RLS - not the UI - decides who may read
/// it. `jobs_client_select_own` opens it for the client,
/// `jobs_technician_select_assigned` for the assigned technician. Two screens
/// would mean two copies of the status timeline and the detail rows, drifting
/// apart on every change.
///
/// The [role] changes wording and which follow-on screen the tracking button
/// opens. It grants nothing: a technician reaching a job they are not assigned
/// to gets an empty read from the database, not a hidden button.
///
/// ## What the redesign added
///
/// * **A hero that answers "where is this up to"** before any detail: the
///   status, what it means, and the one action that matters right now.
/// * **A real timeline** ([SugoTimeline]) that folds the delivery stages of a
///   pickup job into the booking's own lifecycle, instead of two separate
///   progress lists that had to be read together.
/// * **Photos that open**, full-screen and zoomable. They were thumbnails
///   that did nothing, which is the one thing a photo of a broken screen
///   must not be.
/// * **A price section that says who gets paid.** SUGO records a budget, not
///   a transaction - money changes hands between the client and the
///   technician - and the card says so rather than implying an invoice
///   exists.
class JobDetailScreen extends StatefulWidget {
  const JobDetailScreen({super.key, required this.job, required this.role});

  /// The row as the list already had it. Used to paint immediately, then
  /// replaced by a fresh read - a list can be minutes old, and a status is the
  /// one thing here nobody should be reading stale.
  final Job job;

  final BookingsRole role;

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  final RbCarsService _service = RbCarsService();
  final TrackingService _tracking = TrackingService();

  /// Built once, never in `build`.
  ///
  /// Every `watch` call opens its own realtime channel and its own polling
  /// timer, so rebuilding this stream on each `setState` would stack a new
  /// subscription on top of the last one. The job id cannot change while
  /// this screen is alive, so one stream is all it ever needs.
  late final Stream<JobTracking?> _trackingStream = _tracking.watch(
    widget.job.id,
  );

  late Job _job = widget.job;
  String? _error;
  bool _busy = false;

  bool get _isClient => widget.role == BookingsRole.client;

  /// The caller's own rating of the other person on this job.
  TechnicianReview? _myReview;

  /// Both people on the job, resolved by `job_parties`. Null until loaded.
  JobParty? _party;

  final DisputeService _disputeService = DisputeService();

  /// Problems reported on this booking, by either side. Newest first.
  List<JobDispute> _disputes = const <JobDispute>[];

  /// Once a technician has taken the job - the same rule
  /// `open_job_dispute()` checks, so the button is never offered for a report
  /// the server would refuse. (The 7-day limit after completion is left to
  /// the server, whose message says so.)
  bool get _canReportProblem =>
      _job.assignedTechnicianId != null &&
      (_job.status == JobStatus.confirmed ||
          _job.status == JobStatus.inProgress ||
          _job.status == JobStatus.completed);

  /// Only once the work is finished, and only when there is somebody to rate.
  /// The same facts the `job_reviews` insert policy checks, so the card is
  /// never offered for a write the server would refuse.
  bool get _canReview =>
      _job.status == JobStatus.completed && _job.assignedTechnicianId != null;

  /// A pickup job travels twice and has something to track. An on-site repair
  /// never leaves the client's home, so there is no journey to show.
  bool get _needsTracking => _job.servicePath == ServicePath.pickup;

  /// Chat opens once there is somebody on the other end - which since
  /// `20260923000003_negotiation_chat.sql` includes a technician the client
  /// has requested but who has not answered yet.
  ///
  /// That window is exactly when a client most needs to talk: the technician
  /// is deciding, and "I can stretch to ₱2,500 if you can do it today" is the
  /// message that turns a decline into a booking. Mirrors the RLS rule, so
  /// the button is never offered for a write the server would refuse.
  bool get _canChat =>
      _job.assignedTechnicianId != null ||
      ((_party?.technicianIsRequest ?? false) && _party?.technicianId != null);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Re-reads the row. `jobById` filters on nothing but the id - RLS decides
  /// what comes back - so the one method serves both roles.
  Future<void> _refresh() async {
    try {
      final Job? fresh = await _service.jobById(_job.id);
      if (!mounted) return;
      setState(() {
        // Null means the row is no longer readable, not that it is empty.
        // Keeping what we have beats blanking the screen.
        if (fresh != null) _job = fresh;
        _error = null;
      });
      // Who is on the job, so both sides see a name instead of "your
      // technician". Never fatal.
      final Map<String, JobParty> parties = await _service.jobParties();
      if (mounted) setState(() => _party = parties[_job.id]);

      if (_canReview) {
        final TechnicianReview? mine = _isClient
            ? await _service.myReview(_job.id)
            : await _service.myClientReview(_job.id);
        if (mounted) setState(() => _myReview = mine);
      }

      // Never fatal: a failed read just shows no reports.
      if (_job.assignedTechnicianId != null) {
        final List<JobDispute> disputes = await _disputeService.forJob(_job.id);
        if (mounted) setState(() => _disputes = disputes);
      }
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not refresh this booking.');
    }
  }

  // ------------------------------------------------------------- actions

  String? get _counterpartName {
    final JobParty? party = _party;
    if (party == null) return null;
    if (_isClient) return party.hasTechnician ? party.technicianLabel : null;
    return party.clientLabel;
  }

  String? get _counterpartAvatar =>
      _isClient ? _party?.technicianAvatarUrl : _party?.clientAvatarUrl;

  Future<void> _openChat() => openChatThread(
    context,
    jobId: _job.id,
    title: _counterpartName ?? (_isClient ? 'Your technician' : 'Your client'),
    avatarUrl: _counterpartAvatar,
    subtitle: jobThreadSubtitle(
      _job.deviceType.wire,
      _job.problemSymptom,
      _job.status,
    ),
  );

  /// Each role gets the screen built for it: the client watches, the
  /// technician drives. Handing either one the other's screen would offer
  /// controls the database would refuse, or a map with nothing to change.
  Future<void> _openTracking() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _isClient
            ? JobTrackingScreen(job: _job)
            : TechnicianDeliveryScreen(job: _job),
      ),
    );
    if (!mounted) return;
    // A stage change over there can move the job's own status, so the detail
    // has to catch up on the way back.
    await _refresh();
  }

  Future<void> _openReview() async {
    final String name =
        _counterpartName ?? (_isClient ? 'your technician' : 'this client');
    final Future<bool> sheet = _isClient
        ? RateJobSheet.show(
            context,
            jobId: _job.id,
            technicianId: _job.assignedTechnicianId!,
            technicianName: name,
            existing: _myReview,
          )
        : RateJobSheet.showForClient(
            context,
            jobId: _job.id,
            clientId: _job.clientId,
            clientName: name,
            existing: _myReview,
          );
    final bool saved = await sheet;
    if (!saved || !mounted) return;
    UiFeedback.showSuccess(
      context,
      _myReview == null ? 'Thanks for your review.' : 'Review updated.',
    );
    await _refresh();
    if (!mounted) return;

    // One or two stars is when somebody has just realised something went
    // wrong - so that is the moment to offer the report, not a screen later.
    final int stars = _myReview?.stars ?? 5;
    final bool reportedAlready = _disputes.any(
      (JobDispute d) => d.isOpen && d.raisedByClient == _isClient,
    );
    if (stars <= 2 && _canReportProblem && !reportedAlready) {
      final bool report = await showSugoConfirmDialog(
        context: context,
        icon: Icons.report_problem_outlined,
        title: 'Sorry it went badly',
        message:
            'Do you want to report the problem? A SUGO admin will look into '
            'it and reply on this booking.',
        confirmLabel: 'Report it',
        cancelLabel: 'Not now',
      );
      if (report && mounted) {
        await _reportProblem(reason: _isClient ? DisputeReason.notFixed : null);
      }
    }
  }

  /// Opens "Report a problem" and, when sent, shows the new report here.
  Future<void> _reportProblem({DisputeReason? reason}) async {
    final JobDispute? sent = await ReportProblemSheet.show(
      context,
      jobId: _job.id,
      isClient: _isClient,
      service: _disputeService,
      initialReason: reason,
    );
    if (sent == null || !mounted) return;
    setState(() => _disputes = <JobDispute>[sent, ..._disputes]);
    UiFeedback.showSuccess(
      context,
      'Report sent. A SUGO admin will review it and reply here.',
    );
  }

  void _bookAgain() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JobPostingScreen(
          initialCategory: DeviceCategory.forJob(
            deviceType: _job.deviceType,
            deviceDetail: _job.deviceDetail,
            symptomCode: _job.problemSymptom,
          ),
          initialSymptomCode: _job.problemSymptom,
        ),
      ),
    );
  }

  /// Deletes a job nobody has taken yet. The server refuses once a technician
  /// is on it, so the action is only offered while `canBeDeletedByClient`.
  Future<void> _delete() async {
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

    setState(() => _busy = true);
    try {
      // The bin animation says "Request deleted" itself, so no snackbar.
      await runWithDeleteAnimation(context, _service.deleteJob(_job.id));
      if (!mounted) return;
      Navigator.of(context).pop();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() => _busy = false);
      UiFeedback.showError(context, failure.message);
    }
  }

  /// Takes back a request the technician has not answered yet.
  Future<void> _withdraw() async {
    final String name = _counterpartName ?? 'this technician';
    final bool confirmed = await showSugoConfirmDialog(
      context: context,
      icon: Icons.undo_rounded,
      title: 'Cancel your request to $name?',
      message:
          'They have not answered yet, so nothing is lost — and this is not '
          'recorded against them. Your other matches stay ready.',
      confirmLabel: 'Cancel request',
      cancelLabel: 'Keep waiting',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await _service.withdrawTechnician(_job.id);
      if (!mounted) return;
      setState(() => _busy = false);
      UiFeedback.showSuccess(
        context,
        'Request cancelled. Pick another technician.',
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ClientReviewScreen(jobId: _job.id),
        ),
      );
      if (mounted) await _refresh();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() => _busy = false);
      UiFeedback.showError(context, failure.message);
      await _refresh();
    }
  }

  /// The booking summary, which is as close to a receipt as SUGO can honestly
  /// produce - see [_priceCard].
  void _openSummary() {
    showSugoBottomSheet<void>(
      context: context,
      title: 'Booking summary',
      subtitle: _job.reference,
      builder: (BuildContext sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _SummaryRow(label: 'Service', value: _job.title),
          _SummaryRow(label: 'Route', value: _job.servicePath?.label ?? '—'),
          if (_counterpartName != null)
            _SummaryRow(
              label: _isClient ? 'Technician' : 'Client',
              value: _counterpartName!,
            ),
          if (_job.createdAt != null)
            _SummaryRow(label: 'Booked', value: Fmt.dateTime(_job.createdAt!)),
          if (_job.preferredSchedule != null)
            _SummaryRow(
              label: 'Scheduled',
              value: Fmt.dateTime(_job.preferredSchedule!),
            ),
          _SummaryRow(label: 'Budget', value: _job.budgetLabel),
          _SummaryRow(
            label: 'Location',
            value: _job.hasLocation ? _job.locationLabel : 'Not pinned',
          ),
          const SizedBox(height: AppSizes.md),
          Container(
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: AppColors.primarySofter,
              borderRadius: BorderRadius.circular(AppSizes.tileRadius),
            ),
            child: Text(
              'SUGO does not process payment. The final amount is agreed with '
              'your technician and paid directly to them, so this summary is '
              'a record of the booking rather than a receipt.',
              style: AppTextStyles.micro,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final bool canDelete = _isClient && _job.canBeDeletedByClient;
    final bool canWithdraw =
        _isClient && (_party?.technicianIsRequest ?? false);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: SugoAppBar(
        title: _job.title,
        subtitle: _job.reference,
        actions: <Widget>[
          if (canDelete || canWithdraw)
            PopupMenuButton<String>(
              tooltip: 'More actions',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (String value) {
                if (value == 'delete') _delete();
                if (value == 'withdraw') _withdraw();
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                if (canWithdraw)
                  const PopupMenuItem<String>(
                    value: 'withdraw',
                    child: Text('Cancel request'),
                  ),
                if (canDelete)
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Delete request'),
                  ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: StreamBuilder<JobTracking?>(
          stream: _trackingStream,
          builder:
              (BuildContext context, AsyncSnapshot<JobTracking?> snapshot) {
                final JobTracking? tracking = snapshot.data;

                // A tracking row appearing on a job this screen still thinks
                // is an on-site repair means the technician rerouted it while
                // we were looking. Re-read so everything catches up; deferred
                // to the next frame because this runs inside a build.
                if (tracking != null && !_needsTracking) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_needsTracking) _refresh();
                  });
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSizes.screenPadding,
                    AppSizes.md,
                    AppSizes.screenPadding,
                    AppSizes.xxl,
                  ),
                  children: <Widget>[
                    if (_error != null) ...<Widget>[
                      _ErrorNote(message: _error!),
                      const SizedBox(height: AppSizes.md),
                    ],
                    _statusHero(tracking),
                    const SizedBox(height: AppSizes.md),
                    if (_party != null && _counterpartName != null) ...<Widget>[
                      _counterpartCard(),
                      const SizedBox(height: AppSizes.md),
                    ],
                    if (_canReview) ...<Widget>[
                      _reviewCard(),
                      const SizedBox(height: AppSizes.md),
                    ],
                    _timelineCard(tracking),
                    const SizedBox(height: AppSizes.md),
                    ..._trackingSection(tracking),
                    _priceCard(),
                    const SizedBox(height: AppSizes.md),
                    _detailsCard(),
                    if (_job.photoUrls.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSizes.md),
                      _photosCard(),
                    ],
                    // Last, and quiet: most bookings never need it.
                    if (_disputes.isNotEmpty || _canReportProblem) ...<Widget>[
                      const SizedBox(height: AppSizes.xl),
                      DisputeSection(
                        disputes: _disputes,
                        isClient: _isClient,
                        canReport: _canReportProblem,
                        onReport: _reportProblem,
                      ),
                    ],
                  ],
                );
              },
        ),
      ),
    );
  }

  // ------------------------------------------------------------- the hero

  /// Status, what it means for the reader, and the action it calls for.
  Widget _statusHero(JobTracking? tracking) {
    final bool travelling =
        tracking != null &&
        tracking.stage.showsMap &&
        !tracking.stage.isFinished;

    final String headline = travelling
        ? tracking.stage.label
        : switch (_job.status) {
            JobStatus.pending => 'Finding your technician',
            JobStatus.matched =>
              _party?.technicianIsRequest ?? false
                  ? 'Waiting for acceptance'
                  : 'Your matches are ready',
            JobStatus.confirmed => 'Booking confirmed',
            JobStatus.inProgress => 'Repair in progress',
            JobStatus.completed => 'Service completed',
            JobStatus.cancelled => 'Booking cancelled',
          };

    final String blurb = travelling
        ? tracking.stage.blurb
        : switch (_job.status) {
            JobStatus.pending =>
              _isClient
                  ? 'RB-CARS is ranking the three best technicians for this job.'
                  : 'This job has not been matched yet.',
            JobStatus.matched =>
              _isClient
                  ? (_party?.technicianIsRequest ?? false
                        ? 'They have been asked and have not answered yet. You '
                              'can message them in the meantime — about the '
                              'price, or anything they need to know.'
                        : 'Choose who you would like to book.')
                  : 'You have been offered this job.',
            JobStatus.confirmed =>
              _isClient
                  ? 'Your technician has accepted. Message them any time.'
                  : 'You accepted this job. The client is expecting you.',
            JobStatus.inProgress => 'Work is underway.',
            JobStatus.completed =>
              _isClient
                  ? 'The repair is finished. Rate your technician below.'
                  : 'Closed, and the outcome fed back to RB-CARS.',
            JobStatus.cancelled =>
              'This booking was cancelled. It is kept for reference and does '
                  'not count against anyone.',
          };

    return SugoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: jobStatusBadge(_job.status),
                ),
              ),
              if (tracking != null && !tracking.stage.isFinished)
                Text(
                  tracking.freshnessLabel,
                  style: AppTextStyles.micro.copyWith(
                    color: tracking.isLive
                        ? AppColors.success
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Text(headline, style: AppTextStyles.title),
          const SizedBox(height: AppSizes.xs),
          Text(blurb, style: AppTextStyles.subtitle),
          // The booking as a trip, the same drawing the home card and the
          // "Request sent" screen use. Placed from `jobs.status` - refined to
          // "under way" while a tracking row is live - and absent for a
          // cancelled booking, which is not on its way anywhere.
          if (_routePosition(travelling)
              case final SugoRoutePosition at) ...<Widget>[
            const SizedBox(height: AppSizes.lg),
            SugoRouteLine(stops: BookingRoute.stops, position: at),
          ],
          const SizedBox(height: AppSizes.lg),
          _actions(travelling),
        ],
      ),
    );
  }

  /// Where this booking sits on its route, or null when it has none.
  SugoRoutePosition? _routePosition(bool travelling) {
    if (travelling) return BookingRoute.underway;
    return BookingRoute.forStatus(
      _job.status,
      offerPending: _party?.technicianIsRequest ?? false,
    );
  }

  /// The two or three things worth doing from here, in priority order.
  Widget _actions(bool travelling) {
    final List<Widget> buttons = <Widget>[];

    if (_needsTracking &&
        (travelling ||
            _job.status == JobStatus.confirmed ||
            _job.status == JobStatus.inProgress)) {
      buttons.add(
        SugoButton(
          label: _isClient ? 'Track' : 'Delivery controls',
          icon: _isClient ? Icons.near_me_rounded : Icons.navigation_rounded,
          size: SugoButtonSize.small,
          variant: travelling
              ? SugoButtonVariant.accent
              : SugoButtonVariant.primary,
          onPressed: _openTracking,
        ),
      );
    }

    if (_isClient &&
        (_job.status == JobStatus.pending ||
            _job.status == JobStatus.matched) &&
        !(_party?.technicianIsRequest ?? false)) {
      buttons.add(
        SugoButton(
          label: 'Choose technician',
          icon: Icons.groups_rounded,
          size: SugoButtonSize.small,
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ClientReviewScreen(jobId: _job.id),
              ),
            );
            if (mounted) await _refresh();
          },
        ),
      );
    }

    if (_canChat) {
      buttons.add(
        SugoButton(
          label: 'Message',
          icon: Icons.chat_bubble_outline_rounded,
          size: SugoButtonSize.small,
          variant: buttons.isEmpty
              ? SugoButtonVariant.primary
              : SugoButtonVariant.tonal,
          onPressed: _openChat,
        ),
      );
    }

    if (_isClient && _job.status == JobStatus.completed) {
      buttons.add(
        SugoButton(
          label: 'Book again',
          icon: Icons.replay_rounded,
          size: SugoButtonSize.small,
          variant: SugoButtonVariant.outlined,
          onPressed: _bookAgain,
        ),
      );
    }

    if (buttons.isEmpty) {
      buttons.add(
        SugoButton(
          label: 'Booking summary',
          icon: Icons.receipt_long_rounded,
          size: SugoButtonSize.small,
          variant: SugoButtonVariant.outlined,
          onPressed: _openSummary,
        ),
      );
    }

    return Opacity(
      opacity: _busy ? 0.5 : 1,
      child: IgnorePointer(
        ignoring: _busy,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < buttons.length && i < 2; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: AppSizes.md),
              Expanded(child: buttons[i]),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ timeline

  /// The booking's lifecycle, with the delivery stages folded in where they
  /// belong rather than shown as a second, separate progress list.
  Widget _timelineCard(JobTracking? tracking) {
    return SugoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Progress'),
          const SizedBox(height: AppSizes.lg),
          SugoTimeline(steps: _steps(tracking), compact: true),
        ],
      ),
    );
  }

  List<SugoTimelineStep> _steps(JobTracking? tracking) {
    if (_job.status == JobStatus.cancelled) {
      return <SugoTimelineStep>[
        SugoTimelineStep(
          title: 'Request submitted',
          state: SugoStepState.done,
          subtitle: _job.createdAt == null
              ? null
              : Fmt.dateTime(_job.createdAt!),
        ),
        const SugoTimelineStep(
          title: 'Cancelled',
          state: SugoStepState.current,
          icon: Icons.cancel_rounded,
          subtitle: 'This booking is closed.',
        ),
      ];
    }

    const List<JobStatus> lifecycle = <JobStatus>[
      JobStatus.pending,
      JobStatus.matched,
      JobStatus.confirmed,
      JobStatus.inProgress,
      JobStatus.completed,
    ];
    final int current = lifecycle.indexOf(_job.status);

    SugoStepState stateFor(int index) => index < current
        ? SugoStepState.done
        : index == current
        ? SugoStepState.current
        : SugoStepState.upcoming;

    final List<SugoTimelineStep> steps = <SugoTimelineStep>[
      SugoTimelineStep(
        title: 'Request submitted',
        state: stateFor(0),
        icon: Icons.send_rounded,
        subtitle: _job.createdAt == null
            ? 'Posted to RB-CARS.'
            : Fmt.dateTime(_job.createdAt!),
      ),
      SugoTimelineStep(
        title: _isClient ? 'Technician chosen' : 'Offered to you',
        state: stateFor(1),
        icon: Icons.workspace_premium_rounded,
        subtitle: _isClient
            ? 'Three technicians were scored; you pick one.'
            : 'Ranked against two others.',
      ),
      SugoTimelineStep(
        title: 'Booking accepted',
        state: stateFor(2),
        icon: Icons.check_circle_rounded,
        subtitle: _isClient
            ? 'Your technician confirmed the job.'
            : 'You accepted the job.',
      ),
    ];

    // The delivery legs of a pickup job sit between "accepted" and
    // "completed", which is exactly where they happen.
    if (_needsTracking && tracking != null) {
      final List<TrackingStage> route = TrackingStage.timelineFor(
        tracking.stage,
      );
      final int stageIndex = route.indexOf(tracking.stage);
      for (int i = 0; i < route.length; i++) {
        final TrackingStage stage = route[i];
        if (stage == TrackingStage.delivered) continue;
        steps.add(
          SugoTimelineStep(
            title: stage.label,
            state: _job.status == JobStatus.completed
                ? SugoStepState.done
                : i < stageIndex
                ? SugoStepState.done
                : i == stageIndex
                ? SugoStepState.current
                : SugoStepState.upcoming,
            icon: stage.icon,
            subtitle: stage.blurb,
          ),
        );
      }
    } else {
      steps.add(
        SugoTimelineStep(
          title: 'Work in progress',
          state: stateFor(3),
          icon: Icons.build_rounded,
          subtitle: 'The repair is under way.',
        ),
      );
    }

    steps.add(
      SugoTimelineStep(
        title: 'Service completed',
        state: stateFor(4),
        icon: Icons.verified_rounded,
        subtitle: _isClient
            ? 'Rate your technician when it is done.'
            : 'Closed, and fed back to RB-CARS.',
      ),
    );

    return steps;
  }

  // ------------------------------------------------------------ tracking

  /// The live leg of a pickup job, and the client's "how do you want it back?"
  List<Widget> _trackingSection(JobTracking? tracking) {
    if (tracking == null && !_needsTracking) return const <Widget>[];

    final TrackingStage? stage = tracking?.stage;
    final String? technicianId = _job.assignedTechnicianId;

    // Only while the unit is on the bench - see `asksReturnChoice`. Before
    // that there is nothing to bring back yet; after it, the unit has already
    // been moved and the server will not accept a change of mind.
    final bool canChooseReturn =
        _isClient &&
        technicianId != null &&
        (_job.status == JobStatus.confirmed ||
            _job.status == JobStatus.inProgress) &&
        (stage?.asksReturnChoice ?? false);

    return <Widget>[
      SugoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(title: 'Delivery'),
            const SizedBox(height: AppSizes.md),
            if (stage == null)
              Text(
                _isClient
                    ? 'Tracking opens once your technician sets off to collect '
                          'the unit.'
                    : 'Start tracking when you set off, so the client can '
                          'follow the trip.',
                style: AppTextStyles.subtitle,
              )
            else
              Row(
                children: <Widget>[
                  Container(
                    width: AppSizes.iconTile,
                    height: AppSizes.iconTile,
                    decoration: BoxDecoration(
                      color: stage.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSizes.radius),
                    ),
                    child: Icon(stage.icon, size: 20, color: stage.color),
                  ),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(stage.label, style: AppTextStyles.titleSmall),
                        const SizedBox(height: 2),
                        Text(stage.blurb, style: AppTextStyles.micro),
                      ],
                    ),
                  ),
                ],
              ),
            // The technician is told, on the job itself, when there is no
            // delivery trip to make.
            if (!_isClient) _ClientCollectsNote(jobId: _job.id),
            const SizedBox(height: AppSizes.lg),
            SugoButton(
              label: _isClient ? 'Track your appliance' : 'Delivery controls',
              icon: _isClient
                  ? Icons.location_on_outlined
                  : Icons.navigation_outlined,
              size: SugoButtonSize.medium,
              onPressed: _openTracking,
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSizes.md),
      if (canChooseReturn) ...<Widget>[
        ReturnMethodCard(
          jobId: _job.id,
          technicianId: technicianId,
          stage: stage,
        ),
        const SizedBox(height: AppSizes.md),
      ],
    ];
  }

  // ------------------------------------------------------- who and review

  /// Who is on the other side of this job, with a way to their profile.
  Widget _counterpartCard() {
    final JobParty party = _party!;
    final String name = _counterpartName!;
    final String? personId = _isClient ? party.technicianId : party.clientId;

    return SugoCard(
      onTap: personId == null
          ? null
          : () => openPersonProfile(
              context,
              userId: personId,
              role: _isClient ? 'technician' : 'client',
              name: name,
              avatarUrl: _counterpartAvatar,
            ),
      child: Row(
        children: <Widget>[
          SugoAvatar(name: name, imageUrl: _counterpartAvatar, size: 46),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _isClient
                      ? (party.technicianIsRequest
                            ? 'Requested technician'
                            : 'Your technician')
                      : 'Your client',
                  style: AppTextStyles.overline,
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Text(
            'View profile',
            style: AppTextStyles.micro.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryDark,
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppColors.secondaryDark,
          ),
        ],
      ),
    );
  }

  /// The caller's rating of the other person, or the prompt to give one.
  Widget _reviewCard() {
    final TechnicianReview? mine = _myReview;
    final String who = _isClient ? 'technician' : 'client';

    return SugoCard(
      background: mine == null ? AppColors.accentSofter : AppColors.surface,
      borderColor: mine == null ? AppColors.accentSoft : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                ),
                child: Icon(
                  mine == null
                      ? Icons.star_outline_rounded
                      : Icons.star_rounded,
                  size: 20,
                  color: AppColors.accentDark,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      mine == null
                          ? 'Rate this $who'
                          : 'Your rating of this $who',
                      style: AppTextStyles.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    if (mine == null)
                      Text(
                        _isClient
                            ? 'It takes a few seconds and helps other clients '
                                  'choose.'
                            : 'Other technicians see this before they accept '
                                  'a job from them.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.micro,
                      )
                    else
                      Row(
                        children: <Widget>[
                          StarRow(rating: mine.stars.toDouble(), size: 18),
                          const SizedBox(width: AppSizes.sm),
                          Text(
                            '${mine.stars}/5',
                            style: AppTextStyles.micro.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _openReview,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accentDark,
                ),
                child: Text(
                  mine == null ? 'Rate' : 'Edit',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (mine != null && mine.hasComment) ...<Widget>[
            const SizedBox(height: AppSizes.md),
            Text(
              '"${mine.comment!.trim()}"',
              style: AppTextStyles.body.copyWith(
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------- price

  /// What this costs, and who is paid.
  ///
  /// SUGO records a *budget range* the client set when posting, and nothing
  /// else: there is no payments table, no invoice and no platform fee,
  /// because money changes hands directly between the two people. The card
  /// therefore shows the budget as a budget, states the payment arrangement
  /// plainly, and does not invent a "service fee" line to look complete.
  Widget _priceCard() {
    return SugoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Price'),
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Your budget',
                  style: AppTextStyles.subtitle.copyWith(fontSize: 13),
                ),
              ),
              Text(_job.budgetLabel, style: AppTextStyles.price),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Container(
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppSizes.tileRadius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 17,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    'Paid directly to your technician. SUGO does not take '
                    'payment or charge a service fee, so the final amount is '
                    'whatever the two of you agree after diagnosis.',
                    style: AppTextStyles.micro,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          SugoButton(
            label: 'View booking summary',
            icon: Icons.receipt_long_rounded,
            variant: SugoButtonVariant.outlined,
            size: SugoButtonSize.small,
            onPressed: _openSummary,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- details

  Widget _detailsCard() {
    final Job job = _job;

    return SugoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(title: 'Details'),
          const SizedBox(height: AppSizes.md),
          _DetailRow(label: 'Device', value: job.deviceType.label),
          _DetailRow(label: 'Problem', value: job.symptomLabel),
          _DetailRow(
            label: 'Physical damage',
            value: job.hasPhysicalDamage ? 'Yes' : 'No',
          ),
          if (job.servicePath != null)
            _DetailRow(label: 'Service', value: job.servicePath!.label),
          _DetailRow(label: 'Urgency', value: job.urgency.label),
          if (job.preferredSchedule != null)
            _DetailRow(
              label: 'Preferred',
              value: Fmt.dateTime(job.preferredSchedule!),
            ),
          if (job.createdAt != null)
            _DetailRow(label: 'Booked', value: Fmt.dateTime(job.createdAt!)),
          _DetailRow(
            label: 'Location',
            // `locationLabel` prefers the address captured when the client
            // set the pin, and falls back to the coordinate pair.
            value: job.hasLocation ? job.locationLabel : 'Not pinned',
          ),
          if ((job.description ?? '').trim().isNotEmpty) ...<Widget>[
            const Divider(height: AppSizes.xl),
            Text(
              _isClient ? 'What you described' : 'What the client described',
              style: AppTextStyles.label,
            ),
            const SizedBox(height: AppSizes.sm),
            Text(job.description!.trim(), style: AppTextStyles.body),
          ],
        ],
      ),
    );
  }

  Widget _photosCard() {
    return SugoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: 'Photos',
            subtitle: '${_job.photoUrls.length} attached · tap to enlarge',
          ),
          const SizedBox(height: AppSizes.md),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _job.photoUrls.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(width: AppSizes.sm),
              itemBuilder: (BuildContext context, int index) {
                final String url = _job.photoUrls[index];
                return GestureDetector(
                  onTap: () => openSugoImageViewer(
                    context,
                    urls: _job.photoUrls,
                    initialIndex: index,
                    heroTag: 'job-photo-$index-$url',
                  ),
                  child: Hero(
                    tag: 'job-photo-$index-$url',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSizes.tileRadius),
                      child: Image.network(
                        url,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        // A dead photo URL must not paint a broken-image glyph
                        // over an otherwise fine booking.
                        errorBuilder:
                            (
                              BuildContext context,
                              Object error,
                              StackTrace? trace,
                            ) {
                              return Container(
                                width: 96,
                                height: 96,
                                color: AppColors.divider,
                                child: const Icon(
                                  Icons.image_not_supported_outlined,
                                  size: 18,
                                  color: AppColors.hint,
                                ),
                              );
                            },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(label, style: AppTextStyles.caption),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyStrong.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(label, style: AppTextStyles.caption)),
          const SizedBox(width: AppSizes.md),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodyStrong.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.wifi_off_rounded,
            size: 17,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              '$message Showing the last known details.',
              style: AppTextStyles.caption,
            ),
          ),
        ],
      ),
    );
  }
}

/// "The client will pick it up at your shop" - on the technician's copy of a
/// workshop job, when the client has chosen to collect. Renders nothing
/// otherwise, including while it loads: the default is delivery, and a note
/// that flickered in and out would be worse than one that simply appears.
class _ClientCollectsNote extends StatelessWidget {
  const _ClientCollectsNote({required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ReturnMethod>(
      future: TrackingService().returnMethod(jobId),
      builder: (BuildContext context, AsyncSnapshot<ReturnMethod> snapshot) {
        if (snapshot.data != ReturnMethod.clientPickup) {
          return const SizedBox.shrink();
        }
        return const Padding(
          padding: EdgeInsets.only(top: AppSizes.md),
          child: ClientPickupBanner(),
        );
      },
    );
  }
}
