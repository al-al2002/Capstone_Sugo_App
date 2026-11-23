import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/contact_launcher.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_button.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_motion.dart';
import '../../../core/widgets/sugo_dialog.dart';
import '../../../core/widgets/sugo_delete_animation.dart';
import '../../../core/widgets/sugo_image_viewer.dart';
import '../../../core/widgets/sugo_sheet.dart';
import '../../../core/widgets/sugo_timeline.dart';
import '../../chat/screens/chat_thread_screen.dart';
import '../../chat/services/chat_service.dart';
import '../../client/widgets/home_sections.dart';
import '../models/booking_route.dart';
import '../../disputes/models/job_dispute.dart';
import '../../disputes/services/dispute_service.dart';
import '../../disputes/widgets/dispute_section.dart';
import '../../disputes/widgets/report_problem_sheet.dart';
import '../../evidence/models/job_evidence.dart';
import '../../evidence/services/job_evidence_service.dart';
import '../../evidence/widgets/evidence_capture_sheet.dart';
import '../../evidence/widgets/work_record_section.dart';
import '../../rb_cars/models/device_category.dart';
import '../../rb_cars/models/job.dart';
import '../../rb_cars/models/job_enums.dart';
import '../../rb_cars/models/job_price.dart';
import '../../rb_cars/models/match_result.dart';
import '../../rb_cars/screens/client_review_screen.dart';
import '../../rb_cars/screens/job_posting_screen.dart';
import '../../rb_cars/services/rb_cars_service.dart';
import '../../rb_cars/services/technician_directory_service.dart';
import '../../tracking/models/job_tracking.dart';
import '../../tracking/screens/home_visit_trip_screen.dart';
import '../../tracking/screens/job_tracking_screen.dart';
import '../../tracking/screens/technician_delivery_screen.dart';
import '../../technician/widgets/complete_job_sheet.dart';
import '../../technician/widgets/technician_job_actions.dart';
import '../../tracking/services/tracking_service.dart';
import '../../tracking/widgets/drop_off_route_card.dart';
import '../../tracking/widgets/return_method_card.dart';
import 'bookings_list_view.dart';
import '../../rb_cars/models/technician_profile_details.dart';
import '../../rb_cars/models/job_party.dart';
import '../../rb_cars/widgets/review_card.dart';
import '../../profile/profile_navigation.dart';
import '../../../core/widgets/sugo_avatar.dart';
import '../../../core/widgets/sugo_route_line.dart';
import '../../../core/widgets/sugo_fold_card.dart';
import '../widgets/rate_job_sheet.dart';
import '../../rb_cars/widgets/booking_pause.dart';

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
  const JobDetailScreen({
    super.key,
    required this.job,
    required this.role,
    @visibleForTesting this.service,
    @visibleForTesting this.tracking,
    @visibleForTesting this.disputes,
    @visibleForTesting this.chat,
    @visibleForTesting this.directory,
    @visibleForTesting this.evidence,
  });

  /// Tests only (2026-11-17): fakes for the services the screen talks to, so
  /// it can be rendered offline. The app passes none and gets the real ones.
  final RbCarsService? service;
  final TrackingService? tracking;
  final DisputeService? disputes;
  final ChatService? chat;

  /// The work record (2026-11-22).
  final JobEvidenceService? evidence;

  /// The drop-off card's read of the technician's shop.
  final TechnicianDirectoryService? directory;

  /// The row as the list already had it. Used to paint immediately, then
  /// replaced by a fresh read - a list can be minutes old, and a status is the
  /// one thing here nobody should be reading stale.
  final Job job;

  final BookingsRole role;

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  late final RbCarsService _service = widget.service ?? RbCarsService();
  late final TrackingService _tracking = widget.tracking ?? TrackingService();

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

  /// "Mark as complete" / "take to shop" in flight, for their spinners.
  bool _completing = false;
  bool _movingToShop = false;

  bool get _isClient => widget.role == BookingsRole.client;

  /// The caller's own rating of the other person on this job.
  TechnicianReview? _myReview;

  /// Both people on the job, resolved by `job_parties`. Null until loaded.
  JobParty? _party;

  /// The client's phone, on the technician's copy of an active job
  /// (2026-11-17). Released by `job_client_phone` only to the assigned
  /// technician while the job is confirmed or in progress.
  String? _clientPhone;

  /// A home visit's distance to the technician, from the accepted match -
  /// the number the client's travel fee was quoted on before they sent the
  /// request. Shop repairs carry theirs on the job itself.
  double? _homeDistanceKm;

  JobPrice get _price => JobPrice.forJob(_job, homeDistanceKm: _homeDistanceKm);

  late final DisputeService _disputeService =
      widget.disputes ?? DisputeService();

  /// Problems reported on this booking, by either side. Newest first.
  List<JobDispute> _disputes = const <JobDispute>[];

  late final JobEvidenceService _evidenceService =
      widget.evidence ?? JobEvidenceService();

  /// The work record: checkpoint photos the technician took (2026-11-22).
  List<JobEvidence> _evidence = const <JobEvidence>[];

  /// Required steps still missing, for the technician on the job. Null until
  /// checked, or when the check failed - the server checks again anyway.
  List<EvidenceMilestone>? _missingEvidence;

  /// A visit (home or shop) that a technician has taken: the jobs that keep a
  /// work record. A Technician Community question has none.
  bool get _hasWorkRecord =>
      TrackingJourney.tracks(_job.servicePath) &&
      _job.assignedTechnicianId != null &&
      (_job.status == JobStatus.confirmed ||
          _job.status == JobStatus.inProgress ||
          _job.status == JobStatus.completed);

  String _evidenceLabel(EvidenceMilestone m) =>
      m.labelFor(_job.servicePath, selfDropOff: _job.isSelfDropOff);

  /// "Add the Before and After photos first", while the work record lacks a
  /// required step. Null when the technician may complete.
  String? get _completeBlockedReason {
    final List<EvidenceMilestone>? missing = _missingEvidence;
    if (!_isWorking || missing == null || missing.isEmpty) return null;
    final List<String> names = missing.map(_evidenceLabel).toList();
    final String list = names.length == 1
        ? names.single
        : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    return 'Add the $list photo${names.length == 1 ? '' : 's'} first';
  }

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

  /// A pickup job travels twice; a home visit once, the technician driving to
  /// the client (2026-09-29). Both have a trip to follow. A community
  /// diagnosis has none.
  bool get _needsTracking => TrackingJourney.tracks(_job.servicePath);

  /// The client's way to the shop, on a drop-off the technician has accepted
  /// but not yet received (2026-11-17). Nothing is tracked in that window -
  /// the client is the one travelling - so the "Delivery" card's "tracking
  /// opens once your technician sets off" would promise a trip that never
  /// happens on this job. The route card takes its place, high on the page.
  bool _showsDropOffRoute(JobTracking? tracking) =>
      _isClient &&
      _job.isSelfDropOff &&
      // No row yet, or the client's own trip in (2026-11-17).
      (tracking == null || tracking.stage == TrackingStage.droppingOff) &&
      _job.assignedTechnicianId != null &&
      (_job.status == JobStatus.confirmed ||
          _job.status == JobStatus.inProgress);

  TrackingJourney get _journey => TrackingJourney.of(_job.servicePath);

  bool get _isHomeVisit => _journey == TrackingJourney.homeVisit;

  /// The last tracking stage this screen saw. See the stream builder.
  TrackingStage? _seenStage;

  /// The sections deal in once, on the first build (2026-11-17).
  bool _entrancePlayed = false;

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
  /// The technician on this job while it is under way: the one who can
  /// complete it or take it to the shop.
  bool get _isWorking =>
      !_isClient &&
      _job.assignedTechnicianId != null &&
      (_job.status == JobStatus.confirmed ||
          _job.status == JobStatus.inProgress);

  /// Closes the job. The two RB-CARS questions come first - they are the only
  /// signals Stage 1 learns from, so they are asked, never defaulted - and the
  /// client is rated straight after, while the job is fresh.
  Future<void> _complete() async {
    if (_completing || _movingToShop) return;
    // The work record first (2026-11-22). The server refuses too; saying so
    // here saves answering the questions for nothing.
    final String? blocked = _completeBlockedReason;
    if (blocked != null) {
      UiFeedback.showError(context, '$blocked, in the work record below.');
      return;
    }
    final CompletionAnswers? answers = await CompleteJobSheet.show(
      context,
      _job,
      homeDistanceKm: _homeDistanceKm,
    );
    if (answers == null || !mounted) return;

    setState(() => _completing = true);
    try {
      await _service.completeJob(
        _job.id,
        diagnosisCorrect: answers.diagnosisCorrect,
      );
      // The aftercare note goes to the chat only once the job really is
      // closed, so a failed completion never leaves the client reading
      // "Job done". A failed send does not undo the completion.
      final String? wrapUp = answers.wrapUpMessage;
      bool noteSent = false;
      if (wrapUp != null) {
        try {
          await (widget.chat ?? ChatService()).send(_job.id, wrapUp);
          noteSent = true;
        } catch (_) {
          // Reported below; the job is closed either way.
        }
      }
      if (!mounted) return;
      if (wrapUp != null && !noteSent) {
        UiFeedback.showWarning(
          context,
          'Job completed, but the note could not be sent. Message the '
          'client from the chat.',
        );
      } else {
        UiFeedback.showSuccess(
          context,
          noteSent
              ? 'Job completed. Your note is in the chat.'
              : 'Job completed. The client can now rate it.',
        );
      }
      await _refresh();
      if (mounted && _canReview && _myReview == null) await _openReview();
    } on RbCarsFailure catch (failure) {
      if (mounted) UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  /// Switches an on-site job to a shop pickup. Confirmed first: the client
  /// sees it at once - "someone is coming to fix it" becomes "someone is
  /// taking it away" - which is not something to trigger on a stray tap.
  Future<void> _takeToShop() async {
    if (_completing || _movingToShop) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Take it to the shop?'),
        content: const Text(
          'This tells the client the repair cannot be finished at their home '
          'and that you are collecting the unit. They will see a live map of '
          'the pickup. You cannot switch it back.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep on site'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Collect it'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _movingToShop = true);
    try {
      await _service.markNeedsShop(_job.id);
      if (!mounted) return;
      UiFeedback.showSuccess(
        context,
        'Switched to shop pickup. The client can now track their appliance.',
      );
      await _refresh();
    } on RbCarsFailure catch (failure) {
      if (mounted) UiFeedback.showError(context, failure.message);
    } finally {
      if (mounted) setState(() => _movingToShop = false);
    }
  }

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

      // The client's number, for the technician on this job. Never fatal.
      if (!_isClient && _job.assignedTechnicianId != null) {
        final String? phone = await _service.clientPhone(_job.id);
        if (mounted) setState(() => _clientPhone = phone);
      }

      // The travel fee's distance, for a home visit with a technician on it.
      // Read from their match: RLS lets both the client and that technician
      // see it. Never fatal - the card shows the labor fee without it.
      if (_job.servicePath == ServicePath.homeService &&
          _job.assignedTechnicianId != null) {
        try {
          final List<MatchResult> matches = await _service.fetchMatches(
            _job.id,
          );
          double? km;
          for (final MatchResult match in matches) {
            if (match.technicianId == _job.assignedTechnicianId) {
              km = match.breakdown.context.distanceKm;
              break;
            }
          }
          if (mounted) setState(() => _homeDistanceKm = km);
        } catch (_) {
          // Leave the distance unknown.
        }
      }

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

      await _loadEvidence();
    } on RbCarsFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not refresh this booking.');
    }
  }

  /// The work record, and - for the technician on the job - what is still
  /// required. Never fatal: both reads fall back quietly.
  Future<void> _loadEvidence() async {
    if (!_hasWorkRecord) return;
    final List<JobEvidence> evidence = await _evidenceService.forJob(_job.id);
    final List<EvidenceMilestone>? missing = _isWorking
        ? await _evidenceService.missing(_job.id)
        : null;
    if (!mounted) return;
    setState(() {
      _evidence = evidence;
      _missingEvidence = missing;
    });
  }

  /// Opens the camera sheet for one step, then reloads the record.
  Future<void> _addEvidence(EvidenceMilestone milestone) async {
    final bool? saved = await EvidenceCaptureSheet.show(
      context,
      label: _evidenceLabel(milestone),
      blurb: milestone.blurbFor(
        _job.servicePath,
        selfDropOff: _job.isSelfDropOff,
      ),
      onSave: (photos, note) => _evidenceService.add(
        jobId: _job.id,
        milestone: milestone,
        photos: photos,
        note: note,
      ),
    );
    if (saved != true || !mounted) return;
    UiFeedback.showSuccess(context, 'Saved to the work record.');
    await _loadEvidence();
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
            : _isHomeVisit
            ? HomeVisitTripScreen(job: _job)
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
      final DateTime? paused = (await runWithDeleteAnimation(
        context,
        _service.deleteJob(_job.id),
      )).bookingPausedUntil;
      if (!mounted) return;
      // Deleting while a technician was booked counts as a cancel.
      if (paused != null) showBookingPausedNotice(context, paused);
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
          'recorded against them. Your other matches stay ready. Cancelling '
          '2 requests within an hour pauses booking for 2 minutes.',
      confirmLabel: 'Cancel request',
      cancelLabel: 'Keep waiting',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      final DateTime? paused = await _service.withdrawTechnician(_job.id);
      if (!mounted) return;
      setState(() => _busy = false);
      if (paused != null) {
        showBookingPausedNotice(context, paused);
      } else {
        UiFeedback.showSuccess(
          context,
          'Request cancelled. Pick another technician.',
        );
      }
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
          _SummaryRow(label: 'Price', value: _price.headline),
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

                // The trip moving on can mean the job did too: arriving, or a
                // home visit rerouted to the workshop while we were looking,
                // which rewrites `service_path`. A tracking row on a job with
                // no trip at all means the same. Re-read so everything catches
                // up; deferred to the next frame because this runs inside a
                // build, and a stage change is rare enough to be cheap.
                final TrackingStage? stage = tracking?.stage;
                final bool moved =
                    _seenStage != null && stage != null && stage != _seenStage;
                if (stage != null) _seenStage = stage;
                if (tracking != null && (!_needsTracking || moved)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _refresh();
                  });
                }

                // The sections deal in top to bottom the first time the screen
                // opens (2026-11-17). After that - every tracking update
                // rebuilds this list - they simply stay put.
                final bool animate = !_entrancePlayed;
                if (animate) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _entrancePlayed = true;
                  });
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSizes.screenPadding,
                    AppSizes.md,
                    AppSizes.screenPadding,
                    AppSizes.xxl,
                  ),
                  children: _dealtIn(animate, <Widget>[
                    if (_error != null) ...<Widget>[
                      _ErrorNote(message: _error!),
                      const SizedBox(height: AppSizes.md),
                    ],
                    _statusHero(tracking),
                    const SizedBox(height: AppSizes.md),
                    if (_showsDropOffRoute(tracking)) ...<Widget>[
                      DropOffRouteCard(
                        jobId: _job.id,
                        technicianId: _job.assignedTechnicianId!,
                        trip: tracking,
                        directory: widget.directory,
                        tracking: _tracking,
                      ),
                      const SizedBox(height: AppSizes.md),
                    ],
                    // The technician's actions on a job they are on - moved
                    // here from the dashboard card on 2026-09-29.
                    if (_isWorking) ...<Widget>[
                      TechnicianJobActions(
                        job: _job,
                        onTrip: _openTracking,
                        onComplete: _complete,
                        onNeedsShop: _takeToShop,
                        isCompleting: _completing,
                        isMovingToShop: _movingToShop,
                        distanceKm: _homeDistanceKm,
                        completeBlockedReason: _completeBlockedReason,
                      ),
                      const SizedBox(height: AppSizes.md),
                      // Right under the actions: the photos are part of
                      // doing the job, and "Mark as complete" waits on them.
                      if (_hasWorkRecord) ...<Widget>[
                        _workRecord(canAdd: true),
                        const SizedBox(height: AppSizes.md),
                      ],
                    ],
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
                    // The client's view of the work record, and the
                    // technician's once the job is closed. A finished job
                    // with no photos (posted before the record existed)
                    // shows nothing rather than an empty card.
                    if (!_isWorking &&
                        _hasWorkRecord &&
                        (_evidence.isNotEmpty ||
                            _job.status != JobStatus.completed)) ...<Widget>[
                      _workRecord(canAdd: false),
                      const SizedBox(height: AppSizes.md),
                    ],
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
                  ]),
                );
              },
        ),
      ),
    );
  }

  Widget _workRecord({required bool canAdd}) => WorkRecordSection(
    evidence: _evidence,
    servicePath: _job.servicePath,
    selfDropOff: _job.isSelfDropOff,
    missing: _missingEvidence,
    canAdd: canAdd,
    onAdd: canAdd ? _addEvidence : null,
    jobLatitude: _job.latitude,
    jobLongitude: _job.longitude,
    forClient: _isClient,
    photoUrl: _evidenceService.photoUrl,
  );

  /// [children], each rising in after the one before it when [animate].
  /// Spacers are dealt in too; they are invisible, so it costs nothing and
  /// keeps the stagger in step with the cards.
  List<Widget> _dealtIn(bool animate, List<Widget> children) => <Widget>[
    for (int i = 0; i < children.length; i++)
      SugoRiseIn(
        enabled: animate,
        delay: AppMotion.staggerDelay(i ~/ 2),
        child: children[i],
      ),
  ];

  // ------------------------------------------------------------- the hero

  /// Status, what it means for the reader, and the action it calls for.
  Widget _statusHero(JobTracking? tracking) {
    final bool travelling =
        tracking != null &&
        tracking.stage.showsMap &&
        !tracking.stage.isFinished;

    // A home visit's technician at the door is news too, even though nothing
    // is moving any more: "Booking confirmed" would hide that they are here.
    final bool arrivedHome =
        tracking != null &&
        _isHomeVisit &&
        tracking.stage == TrackingStage.inRepair &&
        (_job.status == JobStatus.confirmed ||
            _job.status == JobStatus.inProgress);
    final bool showStage = travelling || arrivedHome;

    final String headline = showStage
        ? tracking.stage.labelOn(_journey)
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

    final String blurb = showStage
        ? tracking.stage.blurbOn(_journey)
        : switch (_job.status) {
            JobStatus.pending =>
              _isClient
                  ? 'SUGO is ranking the three best technicians for this job.'
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
                  : 'Closed, and the outcome fed back to SUGO.',
            JobStatus.cancelled =>
              'This booking was cancelled. It is kept for reference and does '
                  'not count against anyone.',
          };

    // Since 2026-11-17 the hero opens on a gradient band in the booking's
    // own colour - brand while it is live, green when it is fixed, slate
    // when it was cancelled - so the state reads before a word does. The
    // words are the same ones the card always carried.
    const Radius corner = Radius.circular(AppSizes.cardRadius);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.all(corner),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SugoHeroBand(
            colors: _heroColors,
            borderRadius: const BorderRadius.vertical(top: corner),
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
                    // Only while someone is moving: once they have arrived,
                    // or the unit is on the bench, the last position is just
                    // old.
                    if (travelling) _FreshnessPill(tracking: tracking),
                  ],
                ),
                const SizedBox(height: AppSizes.md),
                Text(
                  headline,
                  style: AppTextStyles.title.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  blurb,
                  style: AppTextStyles.subtitle.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // The booking as a trip, the same drawing the home card and
                // the "Request sent" screen use. Placed from `jobs.status` -
                // refined to "under way" while a tracking row is live - and
                // absent for a cancelled booking, which is not on its way
                // anywhere.
                if (_routePosition(showStage)
                    case final SugoRoutePosition at) ...<Widget>[
                  SugoRouteLine(stops: BookingRoute.stops, position: at),
                  const SizedBox(height: AppSizes.lg),
                ],
                _actions(travelling, tracking),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The hero band's colours: the booking's state at a glance.
  List<Color> get _heroColors => switch (_job.status) {
    JobStatus.completed => const <Color>[Color(0xFF0F6B3E), AppColors.success],
    JobStatus.cancelled => const <Color>[Color(0xFF475569), Color(0xFF94A3B8)],
    _ => SugoHeroBand.brand,
  };

  /// Where this booking sits on its route, or null when it has none.
  SugoRoutePosition? _routePosition(bool travelling) {
    if (travelling) return BookingRoute.underway;
    return BookingRoute.forStatus(
      _job.status,
      offerPending: _party?.technicianIsRequest ?? false,
    );
  }

  /// The two or three things worth doing from here, in priority order.
  Widget _actions(bool travelling, JobTracking? tracking) {
    final List<Widget> buttons = <Widget>[];

    // The technician's trip button lives in their work card, just below.
    // A drop-off's route card does the same for the client.
    if (_needsTracking &&
        !_isWorking &&
        !_showsDropOffRoute(tracking) &&
        (travelling ||
            _job.status == JobStatus.confirmed ||
            _job.status == JobStatus.inProgress)) {
      buttons.add(
        SugoButton(
          label: _isClient
              ? 'Track'
              : _isHomeVisit
              ? 'Trip'
              : 'Delivery controls',
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

    // Out in the open while nobody has taken the job (2026-09-29). It was only
    // in the overflow menu, where a client looking for "delete" did not find
    // it. Its own line, full width and red, so it never sits beside "Choose
    // technician" at the same weight.
    final bool canDelete = _isClient && _job.canBeDeletedByClient;

    return Opacity(
      opacity: _busy ? 0.5 : 1,
      child: IgnorePointer(
        ignoring: _busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                for (int i = 0; i < buttons.length && i < 2; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: AppSizes.md),
                  Expanded(child: buttons[i]),
                ],
              ],
            ),
            if (canDelete) ...<Widget>[
              const SizedBox(height: AppSizes.sm),
              SugoButton(
                label: 'Delete request',
                icon: Icons.delete_outline_rounded,
                size: SugoButtonSize.small,
                variant: SugoButtonVariant.danger,
                onPressed: _delete,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ timeline

  /// The booking's lifecycle, with the delivery stages folded in where they
  /// belong rather than shown as a second, separate progress list.
  /// Folded to its current step (2026-11-17) - the hero above already says
  /// where the booking is; the full route is one tap away.
  Widget _timelineCard(JobTracking? tracking) {
    final List<SugoTimelineStep> steps = _steps(tracking);
    final SugoTimelineStep? now =
        steps
            .where((SugoTimelineStep s) => s.state == SugoStepState.current)
            .firstOrNull ??
        steps
            .where((SugoTimelineStep s) => s.state == SugoStepState.done)
            .lastOrNull;
    return SugoFoldCard(
      icon: Icons.timeline_rounded,
      title: 'Progress',
      summary: now?.title,
      child: SugoTimeline(steps: steps, compact: true),
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
            ? 'Posted to SUGO.'
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

    // The trip - both legs of a pickup job, or the drive to a home visit -
    // sits between "accepted" and "completed", which is exactly where it
    // happens.
    if (_needsTracking && tracking != null) {
      final List<TrackingStage> route = TrackingStage.timelineFor(
        tracking.stage,
        journey: _journey,
        dropOff: _job.isSelfDropOff,
      );
      final int stageIndex = route.indexOf(tracking.stage);
      for (int i = 0; i < route.length; i++) {
        final TrackingStage stage = route[i];
        if (stage == TrackingStage.delivered) continue;
        steps.add(
          SugoTimelineStep(
            title: stage.labelOn(_journey),
            state: _job.status == JobStatus.completed
                ? SugoStepState.done
                : i < stageIndex
                ? SugoStepState.done
                : i == stageIndex
                ? SugoStepState.current
                : SugoStepState.upcoming,
            icon: stage.icon,
            subtitle: stage.blurbOn(_journey),
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
            : 'Closed, and fed back to SUGO.',
      ),
    );

    return steps;
  }

  // ------------------------------------------------------------ tracking

  /// The live trip, and on a pickup job the client's "how do you want it
  /// back?"
  List<Widget> _trackingSection(JobTracking? tracking) {
    if (tracking == null && !_needsTracking) return const <Widget>[];
    // Shown higher up instead - see `_showsDropOffRoute`.
    if (_showsDropOffRoute(tracking)) return const <Widget>[];
    // A finished home visit's trip ended at "Repairing at your home", which
    // would read as still going. The status card says it is done.
    if (_isHomeVisit &&
        (_job.status == JobStatus.completed ||
            _job.status == JobStatus.cancelled)) {
      return const <Widget>[];
    }

    final TrackingStage? stage = tracking?.stage;
    final String? technicianId = _job.assignedTechnicianId;

    // Only while the unit is on the bench - see `asksReturnChoice`. Before
    // that there is nothing to bring back yet; after it, the unit has already
    // been moved and the server will not accept a change of mind.
    // Never on a drop-off (2026-11-17): the client chose "I'll bring it",
    // which covers the way back too - collection was set when they booked.
    // Asking "deliver it to me?" would offer a trip that is not part of the
    // job and a fee nobody agreed.
    final bool canChooseReturn =
        _isClient &&
        !_job.isSelfDropOff &&
        technicianId != null &&
        (_job.status == JobStatus.confirmed ||
            _job.status == JobStatus.inProgress) &&
        (stage?.asksReturnChoiceOn(_journey) ?? false);

    return <Widget>[
      SugoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              title: _isHomeVisit
                  ? 'Trip'
                  : _job.isSelfDropOff
                  ? 'Drop-off and collection'
                  : 'Delivery',
            ),
            const SizedBox(height: AppSizes.md),
            if (stage == null)
              Text(
                _isClient
                    ? (_isHomeVisit
                          ? 'Tracking opens once your technician sets off to '
                                'your address.'
                          : 'Tracking opens once your technician sets off to '
                                'collect the unit.')
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
                        Text(
                          stage.labelOn(_journey),
                          style: AppTextStyles.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stage.blurbOn(_journey),
                          style: AppTextStyles.micro,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            // The technician is told, on the job itself, when there is no
            // delivery trip to make.
            if (!_isClient && !_isHomeVisit)
              _ClientCollectsNote(jobId: _job.id, tracking: _tracking),
            // A working technician already has this in their work card.
            if (!_isWorking) ...<Widget>[
              const SizedBox(height: AppSizes.lg),
              SugoButton(
                label: _isClient
                    ? (_isHomeVisit
                          ? 'Track your technician'
                          : _job.isSelfDropOff
                          ? (stage == TrackingStage.readyForCollection
                                ? 'Route to the shop'
                                : 'Repair progress')
                          : 'Track your appliance')
                    : (_isHomeVisit
                          ? 'Trip to the client'
                          : _job.isSelfDropOff
                          ? 'Drop-off and collection'
                          : 'Delivery controls'),
                icon: _isClient
                    ? Icons.location_on_outlined
                    : Icons.navigation_outlined,
                size: SugoButtonSize.medium,
                onPressed: _openTracking,
              ),
            ],
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
      // What a drop-off client gets instead of the question: the answer
      // they already gave, said once.
      if (_isClient &&
          _job.isSelfDropOff &&
          stage != null &&
          !stage.isFinished &&
          stage != TrackingStage.readyForCollection &&
          stage != TrackingStage.droppingOff) ...<Widget>[
        const _CollectAtShopNote(),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
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
          // The client's number, on the technician's side (2026-11-17), with
          // a Call button - to say they are running late or to find the house.
          if (!_isClient && _clientPhone != null) ...<Widget>[
            const Divider(height: AppSizes.xl),
            _ClientPhoneRow(
              phone: _clientPhone!,
              onCall: () => ContactLauncher.call(context, _clientPhone),
            ),
          ],
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
  /// The price the client was quoted (2026-11-17): the labor fee for the
  /// symptom, the travel or delivery fee for the distance, and the estimated
  /// total. It replaced the client's own budget range, which was a guess
  /// made before anyone was matched. Money still changes hands directly
  /// between the two people - the note below says so - so there is no
  /// invented "service fee" line.
  /// Folded to the one number (2026-11-17): the estimated total, or the
  /// labor fee until the total is known.
  Widget _priceCard() {
    final JobPrice price = _price;

    return SugoFoldCard(
      icon: Icons.payments_outlined,
      title: 'Price',
      summary: price.total != null
          ? 'Estimated total ${price.total}'
          : price.laborWithUrgent != null
          ? 'Labor fee ${price.laborWithUrgent}'
          : 'To be confirmed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (price.labor == null)
            _PriceRow(label: 'Labor fee', value: 'To be confirmed')
          else ...<Widget>[
            Text(
              price.labor!.symptom,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSizes.sm),
            _PriceRow(label: 'Labor fee', value: price.labor!.fee),
          ],
          // Urgent jobs: 20% of the labor on top (2026-11-17).
          if (price.hasUrgentFee)
            _PriceRow(
              label: JobPrice.urgentFeeLabel,
              value: price.urgentFeeText!,
            ),
          // Pickup and delivery prints as its two trips (2026-11-17).
          if (price.distanceFeeLines
              case final List<({String label, int amount})> lines)
            for (final ({String label, int amount}) line in lines)
              _PriceRow(label: line.label, value: '₱${line.amount}')
          else if (price.feeLabel != null)
            _PriceRow(
              label: price.distanceFeeLabel!,
              value: 'Agreed with the technician',
            ),
          if (price.total != null) ...<Widget>[
            const Divider(height: AppSizes.lg),
            _PriceRow(
              label: 'Estimated total',
              value: price.total!,
              bold: true,
            ),
          ],
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

  /// Folded to the device and the problem (2026-11-17).
  Widget _detailsCard() {
    final Job job = _job;

    return SugoFoldCard(
      icon: Icons.description_outlined,
      title: 'Details',
      summary: '${job.deviceType.label} · ${job.symptomLabel}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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

  /// Folded to how many there are (2026-11-17).
  Widget _photosCard() {
    return SugoFoldCard(
      icon: Icons.photo_library_outlined,
      title: 'Photos',
      summary: '${_job.photoUrls.length} attached · tap to enlarge',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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

/// "Live" or "Updated 4 min ago", as a glass pill on the hero band, with a
/// green dot while the position is fresh.
class _FreshnessPill extends StatelessWidget {
  const _FreshnessPill({required this.tracking});

  final JobTracking tracking;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tracking.isLive
                  ? const Color(0xFF4ADE80)
                  : Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            tracking.freshnessLabel,
            style: AppTextStyles.micro.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
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
  const _ClientCollectsNote({required this.jobId, required this.tracking});

  final String jobId;

  /// The screen's own service, so a test's fake answers here too.
  final TrackingService tracking;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ReturnMethod>(
      future: tracking.returnMethod(jobId),
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

/// "You'll collect it at the shop" - a drop-off client's answer to "how do
/// you want it back?", which they gave when they booked "I'll bring it"
/// (2026-11-17). Replaces the delivery-or-pickup choice on this job.
class _CollectAtShopNote extends StatelessWidget {
  const _CollectAtShopNote();

  @override
  Widget build(BuildContext context) {
    return SugoCard(
      background: AppColors.primarySofter,
      borderColor: AppColors.primarySoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: AppSizes.iconTile,
            height: AppSizes.iconTile,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.radius),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: AppColors.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  "You'll collect it at the shop",
                  style: AppTextStyles.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'You chose to bring it in yourself, so there is no '
                  'delivery and no delivery fee. We will tell you when it is '
                  'ready for collection, and show you the way.',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the price card: label left, amount right, both free to wrap.
class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: AppTextStyles.subtitle.copyWith(fontSize: 13),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: bold
                  ? AppTextStyles.price
                  : const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Phone · 0917 123 4567" with a Call button, under the client's name.
class _ClientPhoneRow extends StatelessWidget {
  const _ClientPhoneRow({required this.phone, required this.onCall});

  final String phone;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.successSoft,
            borderRadius: BorderRadius.circular(AppSizes.sm + 2),
          ),
          child: const Icon(
            Icons.phone_rounded,
            size: 18,
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Phone', style: AppTextStyles.micro),
              SelectableText(
                phone,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        FilledButton.icon(
          onPressed: onCall,
          icon: const Icon(Icons.call_rounded, size: 18),
          label: const Text('Call'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            minimumSize: const Size(0, AppSizes.touchTarget),
          ),
        ),
      ],
    );
  }
}
