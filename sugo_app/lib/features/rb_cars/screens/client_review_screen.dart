import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_elevation.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/staggered_entrance.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_card.dart';
import '../../../core/widgets/sugo_route_line.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../bookings/models/booking_route.dart';
import '../models/job.dart';
import '../models/job_enums.dart';
import '../models/match_result.dart';
import '../models/schedule_preference.dart';
import '../providers/job_posting_provider.dart';
import '../providers/match_provider.dart';
import '../services/rb_cars_service.dart';
import '../widgets/context_summary.dart';
import '../widgets/match_score_card.dart';
import '../widgets/more_technicians_section.dart';
import '../widgets/recommendation_reasons_sheet.dart';
import '../widgets/technician_matching_loader.dart';
import 'matching_walkthrough_screen.dart';
import '../../tracking/screens/job_tracking_screen.dart';
import 'booking_success_screen.dart';
import 'job_posting_screen.dart';
import 'technician_detail_screen.dart';

/// The Top 3, as the client sees them.
///
/// Reads `job_matches` straight through RLS - the client owns the job, so the
/// `job_matches_client_select` policy lets them see their own offers. Each card
/// carries the score, rating, specialisation, distance, badge and the
/// explainability line built from `score_breakdown`.
class ClientReviewScreen extends StatefulWidget {
  /// Opening a job that already exists - the dashboard's recent list, a
  /// notification, a deep link.
  const ClientReviewScreen({
    super.key,
    required String this.jobId,
    this.preselectedTechnicianId,
    @visibleForTesting this.service,
  }) : draft = null;

  /// Arriving straight off the posting flow, where the job has not been
  /// inserted yet.
  ///
  /// The screen posts the draft itself, under the matching animation, rather
  /// than being handed a finished job id. That is what lets "Find technician"
  /// move to this screen on the same frame it is tapped: the upload, the
  /// insert and the matcher all run while the loader is already on screen,
  /// instead of behind a spinner on the button the client just pressed.
  const ClientReviewScreen.postDraft({
    super.key,
    required JobPostingProvider this.draft,
    this.preselectedTechnicianId,
    @visibleForTesting this.service,
  }) : jobId = null;

  /// Null exactly when [draft] is set.
  final String? jobId;

  /// Null exactly when [jobId] is set. Owned by the posting flow, which is
  /// still mounted underneath this route, so it outlives the submit.
  final JobPostingProvider? draft;

  /// Highlighted if they made the Top 3. RB-CARS still decides the ranking -
  /// arriving from a technician's profile does not buy a top slot.
  final String? preselectedTechnicianId;

  /// Tests only: where the matches are read from. The app always uses the
  /// real service.
  final RbCarsService? service;

  @override
  State<ClientReviewScreen> createState() => _ClientReviewScreenState();
}

class _ClientReviewScreenState extends State<ClientReviewScreen> {
  /// Known from the start when opening an existing job; filled in by [_post]
  /// otherwise. Null means the job does not exist yet.
  String? _jobId;

  String? _postError;

  /// True from the first frame when there is a draft to post, so the back
  /// gesture is already blocked before [_post] has begun.
  late bool _isPosting = widget.jobId == null;

  /// One matching run's clock, shared by the posting loader and the review's
  /// loader so the animation carries straight on when the job is saved.
  final MatchingSession _session = MatchingSession();

  @override
  void initState() {
    super.initState();
    _jobId = widget.jobId;

    if (_jobId == null) {
      // Deferred by one frame, for two reasons. `submit()` notifies its
      // listeners before its first await, and running that inside initState
      // reached the posting screen this route had just replaced - a
      // markNeedsBuild on a defunct element, mid-build. It also guarantees the
      // loader paints before any work starts, which is the whole point of
      // coming straight here.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _post();
      });
    }
  }

  Future<void> _post() async {
    setState(() {
      _postError = null;
      _isPosting = true;
    });

    final JobPostingProvider draft = widget.draft!;
    final Job? job = await draft.submit();

    if (!mounted) return;

    if (job == null) {
      setState(() {
        _postError = draft.error ?? 'Could not post this job.';
        _isPosting = false;
      });
      return;
    }

    if (draft.photosFailed > 0) {
      UiFeedback.showInfo(
        context,
        '${draft.isEditing ? 'Saved' : 'Posted'}, but ${draft.photosFailed} '
        'photo(s) could not be uploaded.',
      );
    }

    setState(() {
      _jobId = job.id;
      _isPosting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? jobId = _jobId;

    if (jobId == null) {
      // Leaving mid-insert would strand a job nobody is looking at, so the
      // back gesture is refused until the post settles one way or the other.
      if (_postError != null) {
        return PopScope(
          canPop: !_isPosting,
          child: Scaffold(
            appBar: SugoAppBar(
              title: 'Finding your technicians',
              automaticallyImplyLeading: !_isPosting,
            ),
            body: SafeArea(
              child: _PostFailed(message: _postError!, onRetry: _post),
            ),
          ),
        );
      }

      // The analysis screen, following the post as it really goes: the first
      // tick waits for the job to be saved, the rest for the match result.
      final JobPostingProvider draft = widget.draft!;
      return PopScope(
        canPop: !_isPosting,
        child: ListenableBuilder(
          listenable: draft,
          builder: (BuildContext context, Widget? _) => MatchingLoaderScaffold(
            canGoBack: !_isPosting,
            loader: TechnicianMatchingLoader(
              session: _session,
              phase: draft.requestSaved
                  ? MatchingPhase.matching
                  : MatchingPhase.saving,
            ),
          ),
        ),
      );
    }

    final Widget review = ChangeNotifierProvider<MatchProvider>(
      create: (_) => MatchProvider(
        jobId: jobId,
        service: widget.service,
        initialNotice: widget.draft?.matchingNotice,
      )..load(),
      child: _ClientReviewView(
        preselectedTechnicianId: widget.preselectedTechnicianId,
        session: _session,
        arrivedFromPost: widget.draft != null,
      ),
    );

    // Opened from the dashboard: back is simply back.
    if (widget.draft == null) return review;

    // Arrived from the posting (or editing) flow, whose steps are still on
    // the stack underneath. Back used to walk into them - the map step, where
    // pressing "Find technician" again posted the same job a second time.
    // Once the job exists there is nothing left to do in that flow, so back
    // (the gesture and the app-bar arrow alike) goes straight home. The root
    // route is `AuthGate`, which resolves the client's dashboard.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
      },
      child: review,
    );
  }
}

/// The job could not be inserted. The draft is still in memory on the provider
/// below this route, so retrying re-posts it rather than asking the client to
/// fill the form in again.
class _PostFailed extends StatelessWidget {
  const _PostFailed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.hint),
          const SizedBox(height: AppSizes.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.subtitle,
          ),
          const SizedBox(height: AppSizes.lg),
          // Blue, matching the posting flow this screen is the end of. It was
          // orange only because the flow was, and a retry is not an exception
          // worth spending the accent on.
          PrimaryButton(label: 'Try again', onPressed: onRetry),
          const SizedBox(height: AppSizes.sm),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Back to my job'),
          ),
        ],
      ),
    );
  }
}

class _ClientReviewView extends StatelessWidget {
  const _ClientReviewView({
    this.preselectedTechnicianId,
    this.session,
    this.arrivedFromPost = false,
  });

  final String? preselectedTechnicianId;

  /// The posting screen's matching clock, carried on.
  final MatchingSession? session;

  /// True when the job was posted and matched on the screen before this one.
  final bool arrivedFromPost;

  @override
  Widget build(BuildContext context) {
    final MatchProvider matching = context.watch<MatchProvider>();

    // The analysis screen covers the whole route while matching runs - see
    // `MatchingHandoff` for exactly when - and hands over to the results
    // once the result is in and its finish has played.
    return MatchingHandoff(
      loading: matching.isLoading && matching.matches.isEmpty,
      matching: matching.isMatching,
      failed: matching.error != null,
      arrivedFromPost: arrivedFromPost,
      session: session,
      results: _results(context, matching),
    );
  }

  Widget _results(BuildContext context, MatchProvider matching) {
    final Job? job = matching.job;

    return Scaffold(
      // "Edit post" took the place of the old "Return to dashboard" link:
      // back already goes home, and changing the post is the thing a client
      // looking at three technicians who do not suit them actually needs.
      bottomNavigationBar: job != null && _canEdit(job, matching)
          ? _EditPostBar(
              enabled: !matching.isLoading && !matching.isResponding,
              onEdit: () => _editPost(context, job, matching),
            )
          : null,
      // Named for what the client does here, and matching the home card's
      // "Choose technician" button that brings them - one action, one name.
      appBar: SugoAppBar(
        title: 'Choose a technician',
        actions: <Widget>[
          IconButton(
            tooltip: 'Run the matcher again',
            onPressed: matching.isLoading ? null : matching.rematch,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: matching.load,
          // The loader and the Top 3 are different subtrees, so the switcher
          // needs a key that changes when one gives way to the other -
          // otherwise it treats them as the same child and skips the
          // transition entirely.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<bool>(
                matching.isLoading && matching.matches.isEmpty,
              ),
              // Stacked, not swapped: during a booking or a re-match the list
              // stays on screen behind the scrim. Replacing it with a spinner
              // would make the client feel they had lost their matches, and
              // a re-match that finds nobody would then leave them staring at
              // an empty screen wondering what they just did.
              child: Stack(
                children: <Widget>[
                  _body(context, matching, job),
                  if (_busyLabel(matching) != null)
                    _BusyOverlay(label: _busyLabel(matching)!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What the overlay should say, or null when nothing is in flight.
  ///
  /// `isResponding` already existed on the provider and was never read by any
  /// screen - so booking a technician ran a network round trip with no feedback
  /// at all. The client tapped "Send request" and nothing moved until a
  /// snackbar appeared.
  ///
  /// The loading case is narrowed to "matches already on screen", because an
  /// empty list is handled by the analysis screen or the skeleton instead.
  /// Both at once would put a spinner on top of a spinner.
  String? _busyLabel(MatchProvider matching) {
    if (matching.isResponding) return 'Sending your request...';
    if (matching.isLoading && matching.matches.isNotEmpty) {
      return 'Finding more technicians...';
    }
    return null;
  }

  Widget _body(BuildContext context, MatchProvider matching, Job? job) {
    if (matching.isLoading && matching.matches.isEmpty) {
      // Reading results that already exist. The analysis screen is for when
      // RB-CARS is actually running (`MatchingHandoff`); a plain read gets a
      // skeleton of the cards it is about to show.
      return const Padding(
        padding: EdgeInsets.all(AppSizes.screenPadding),
        child: SugoSkeletonList(count: 3),
      );
    }

    if (matching.error != null && matching.matches.isEmpty) {
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: AppColors.hint,
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              matching.error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.subtitle,
            ),
            const SizedBox(height: AppSizes.lg),
            OutlinedButton(
              onPressed: matching.load,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    if (matching.isEmpty) {
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.person_search_rounded,
              size: 44,
              color: AppColors.hint,
            ),
            const SizedBox(height: AppSizes.md),
            Text('No technicians matched yet', style: AppTextStyles.headline),
            const SizedBox(height: AppSizes.xs),
            Text(
              // The engine names the gate that emptied the pool. Preferring it
              // over our own guess is the difference between "nobody is
              // available" - which can be flatly untrue - and "one was outside
              // their own service radius", which tells the client whether
              // waiting will help.
              matching.notice ??
                  'Nobody verified is available for this job right now. Your '
                      'job is saved - try again in a little while.',
              textAlign: TextAlign.center,
              style: AppTextStyles.subtitle,
            ),
            const SizedBox(height: AppSizes.lg),
            OutlinedButton(
              onPressed: matching.rematch,
              child: const Text('Search again'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.lg,
        AppSizes.screenPadding,
        AppSizes.xxl,
      ),
      children: <Widget>[
        if (job != null)
          _JobSummary(
            job: job,
            offerPending: matching.matches.any(
              (MatchResult m) => m.isAwaitingTechnician,
            ),
          ),
        const SizedBox(height: AppSizes.xl),

        // A rerouted job travels to the shop and back, so the client gets a
        // live map. An on-site repair has nothing to track.
        if (job != null && _isTrackable(job, matching)) ...<Widget>[
          _TrackBanner(
            onTap: () => _openTracking(context, job, matching.acceptedMatch!),
          ),
          const SizedBox(height: AppSizes.lg),
        ],

        Row(
          children: <Widget>[
            Expanded(
              // The app bar already says "Recommended technicians"; this line
              // says how many, which is the other thing a client wants to know.
              child: Text(
                matching.matches.length == 1
                    ? 'Your top match'
                    : 'Your top ${matching.matches.length}',
                style: AppTextStyles.headline,
              ),
            ),
            const _RankedByPill(),
          ],
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          'Based on your request and current conditions. Tap “Why this '
          'technician?” on any card to see the reasons.',
          style: AppTextStyles.subtitle,
        ),
        const SizedBox(height: AppSizes.lg),

        // The context-aware part, made visible: what the engine saw, and the
        // matching rules it re-weighted for. Long-press opens the ranking
        // walkthrough for a demo; debug builds also show a link.
        ContextSummary(
          matches: matching.matches,
          job: job,
          onLongPress: () => _openWalkthrough(context, matching),
        ),
        if (kDebugMode)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openWalkthrough(context, matching),
              icon: const Icon(Icons.account_tree_outlined, size: 16),
              label: const Text('How this was ranked (demo)'),
            ),
          ),
        const SizedBox(height: AppSizes.lg),

        if (matching.notice != null) ...<Widget>[
          _Notice(message: matching.notice!, onDismiss: matching.clearNotice),
          const SizedBox(height: AppSizes.lg),
        ],

        // Cards rise in one after another - a short, quiet entrance that
        // reads as "here are your three" rather than a list popping in.
        StaggeredEntrance(
          children: <Widget>[
            for (final MatchResult match in matching.matches)
              MatchScoreCard(
                match: match,
                highlighted: match.technicianId == preselectedTechnicianId,
                onTap: () => _openDetail(context, match),
                onWhyTap: () =>
                    RecommendationReasonsSheet.show(context, match),
                onSelect: () => _book(context, match),
                selectLabel: match.isTopPick
                    ? 'Book ${match.technician?.displayName.split(' ').first ?? 'now'}'
                    : 'Book instead',
              ),
          ],
        ),

        const SizedBox(height: AppSizes.xs),
        Center(
          child: OutlinedButton.icon(
            onPressed: matching.isLoading ? null : matching.rematch,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('None of these work? Search again'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              ),
            ),
          ),
        ),

        // ------------------------ the rest of the qualified pool, selectable
        //
        // Ranks 4+ from `match_technicians_for_job`: everyone else whose
        // registered specialisation fits this device, including technicians
        // with few completed jobs. Renders nothing when there are none, and
        // loads independently so a failure here cannot take the Top 3 down.
        MoreTechniciansSection(jobId: matching.jobId),

        // ------------------------------------------- everyone the engine saw
        //
        // Only three offers can exist - `job_matches.rank` is checked between
        // 1 and 3 - so fourth place onward is visible here or nowhere.
        if (matching.considered.isEmpty)
          Center(
            child: TextButton.icon(
              onPressed: matching.isLoading
                  ? null
                  : () => matching.rematch(excludeDeclined: false),
              icon: const Icon(Icons.groups_2_outlined, size: 16),
              label: const Text('Show everyone we considered'),
            ),
          )
        else ...<Widget>[
          const SizedBox(height: AppSizes.lg),
          const Divider(color: AppColors.divider),
          const SizedBox(height: AppSizes.lg),
          Text(
            'Everyone we considered (${matching.considered.length})',
            style: AppTextStyles.headline,
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            'The whole pool that passed the hard gates, in the order RB-CARS '
            'ranked it. Only the top three can be offered the job.',
            style: AppTextStyles.subtitle,
          ),
          const SizedBox(height: AppSizes.md),
          ...matching.considered.map(
            (ConsideredTechnician candidate) =>
                _ConsideredRow(candidate: candidate),
          ),
        ],
      ],
    );
  }

  /// "Edit post" is offered while the server would accept the edit: nobody
  /// has taken the job. Mirrors `handleUpdateJob`, which re-checks it.
  bool _canEdit(Job job, MatchProvider matching) =>
      job.canBeEditedByClient && matching.acceptedMatch == null;

  /// Opens the posting flow on this job, every answer filled in.
  ///
  /// A request already sent to a technician is withdrawn by the edit - they
  /// agreed to look at the old details, not the new ones - so the client is
  /// told that first, in the technician's name.
  Future<void> _editPost(
    BuildContext context,
    Job job,
    MatchProvider matching,
  ) async {
    MatchResult? waitingOn;
    for (final MatchResult match in matching.matches) {
      if (match.isAwaitingTechnician) {
        waitingOn = match;
        break;
      }
    }

    if (waitingOn != null) {
      final String name =
          waitingOn.technician?.displayName.split(' ').first ?? 'the technician';
      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Edit your post?'),
          content: Text(
            'Your request to $name will be withdrawn, and we will find a '
            'fresh top 3 for the updated post.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('Keep $name'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Edit post'),
            ),
          ],
        ),
      );
      if (proceed != true || !context.mounted) return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => JobPostingScreen.edit(job: job)),
    );
  }

  /// True when this job involves transport that is worth putting on a map:
  /// it was rerouted to the shop, a technician has accepted it, and it has not
  /// finished yet.
  bool _isTrackable(Job job, MatchProvider matching) {
    if (matching.acceptedMatch == null) return false;
    if (job.servicePath != ServicePath.pickup) return false;
    return job.status == JobStatus.confirmed ||
        job.status == JobStatus.inProgress;
  }

  void _openDetail(BuildContext context, MatchResult match) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TechnicianDetailScreen(
          technicianId: match.technicianId,
          match: match,
        ),
      ),
    );
  }

  /// The step-by-step ranking view, for a demo or a review.
  void _openWalkthrough(BuildContext context, MatchProvider matching) {
    if (matching.matches.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MatchingWalkthroughScreen(
          matches: matching.matches,
          considered: matching.considered,
          job: matching.job,
        ),
      ),
    );
  }

  /// Books the chosen technician.
  ///
  /// This used to push `TechnicianConfirmationScreen`, which was wrong: that is
  /// the technician's Accept / Needs-shop / Decline screen, and showing it to a
  /// client let them answer on the technician's behalf. A client selects; only
  /// the technician can accept.
  Future<void> _book(BuildContext context, MatchResult match) async {
    final MatchProvider matching = context.read<MatchProvider>();

    // The card hides its button for a technician on vacation; this covers any
    // other route here. The server refuses the request regardless.
    final String? away = match.technician?.awayLabel;
    if (away != null) {
      UiFeedback.showInfo(context, '$away and cannot be booked.');
      return;
    }

    final String name =
        match.technician?.displayName.split(' ').first ?? 'this technician';

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Book $name?'),
        content: Text(
          'We will send your job to $name and let the other two options go. '
          'They still need to accept before it is confirmed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep looking'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final bool ok = await matching.selectTechnician(match.id);
    if (!context.mounted) return;

    if (ok) {
      matching.clearNotice();

      // On to the confirmation screen, which names the reference, repeats
      // what was booked and says what happens next.
      //
      // Staying here was the old behaviour and it was a dead end: the screen
      // is "choose a technician", the choosing is finished, and the three
      // cards it still showed invited a second choice that the server would
      // refuse. Popping straight to the dashboard with a toast was the fix
      // after that, and it under-sold the moment - the one point in the flow
      // where the client has actually committed to somebody.
      //
      // `pushReplacement`, so Back from the confirmation reaches the
      // dashboard rather than the shortlist it replaced.
      final Job? job = matching.job;
      if (job == null) {
        UiFeedback.showSuccess(context, 'Request sent to $name.');
        Navigator.of(context).popUntil((Route<void> route) => route.isFirst);
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => BookingSuccessScreen(
            job: job,
            technician: match.technician,
          ),
        ),
      );
    } else {
      UiFeedback.showError(
        context,
        matching.error ?? 'Could not send that request.',
      );
      matching.clearError();
    }
  }

  void _openTracking(BuildContext context, Job job, MatchResult match) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            JobTrackingScreen(job: job, technician: match.technician),
      ),
    );
  }
}

/// One row of the full ranking: place, name, distance and final score.
///
/// Deliberately plainer than [MatchScoreCard]. This list answers "who else was
/// there and where did they come?", not "should I book this person" - the
/// three that can actually be booked are the cards above.
class _ConsideredRow extends StatelessWidget {
  const _ConsideredRow({required this.candidate});

  final ConsideredTechnician candidate;

  @override
  Widget build(BuildContext context) {
    final bool offered = candidate.offered;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: offered ? AppColors.primarySoft : AppColors.divider,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${candidate.rank}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: offered ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  candidate.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: offered ? FontWeight.w700 : FontWeight.w600,
                    color: offered
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  <String>[
                    candidate.distanceLabel,
                    if (candidate.statusLabel != null) candidate.statusLabel!,
                    if (offered) 'offered',
                  ].join(' · '),
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Text(
            candidate.finalScore.toStringAsFixed(2),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// What is being matched, so the scores have a subject - and, since "Edit
/// post", a read-back of exactly what an edit would change.
///
/// Since the Dispatch redesign it also carries the booking's route, so the
/// client sees they are at "Matched" - their turn to choose - and that
/// "Booked" is the next stop, which is what the Book button does.
class _JobSummary extends StatelessWidget {
  const _JobSummary({required this.job, this.offerPending = false});

  final Job job;

  /// A technician has been asked and has not answered.
  final bool offerPending;

  @override
  Widget build(BuildContext context) {
    final ServicePath? path = job.servicePath;
    final SchedulePreference schedule = SchedulePreference.fromJob(
      urgency: job.urgency,
      preferredSchedule: job.preferredSchedule,
    );
    final String? brand = job.brand?.trim();
    final SugoRoutePosition? position = BookingRoute.forStatus(
      job.status,
      offerPending: offerPending,
    );

    return SugoCard(
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: AppSizes.iconTile,
                height: AppSizes.iconTile,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(job.deviceType.icon, color: AppColors.primary),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      job.symptomLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.sectionTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        job.deviceType.label,
                        if (brand != null && brand.isNotEmpty) brand,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Text(job.reference, style: AppTextStyles.micro),
            ],
          ),
          if (position != null) ...<Widget>[
            const SizedBox(height: AppSizes.lg),
            SugoRouteLine(stops: BookingRoute.stops, position: position),
          ],
          const SizedBox(height: AppSizes.lg),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.sm,
            children: <Widget>[
              if (path != null) _MetaPill(icon: path.icon, label: path.label),
              _MetaPill(icon: Icons.schedule_rounded, label: schedule.label),
              _MetaPill(icon: Icons.payments_outlined, label: job.budgetLabel),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: <Widget>[
              const Icon(Icons.place_rounded, size: 15, color: AppColors.hint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  job.locationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro.copyWith(
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

/// "RB-CARS" beside the section title: who did the ranking.
class _RankedByPill extends StatelessWidget {
  const _RankedByPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.auto_awesome_rounded,
            size: 13,
            color: AppColors.primary,
          ),
          const SizedBox(width: 4),
          Text(
            'RB-CARS',
            style: AppTextStyles.micro.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// The sticky bar under the matches: "Edit post".
class _EditPostBar extends StatelessWidget {
  const _EditPostBar({required this.onEdit, required this.enabled});

  final VoidCallback onEdit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPadding,
        AppSizes.md,
        AppSizes.screenPadding,
        AppSizes.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: AppElevation.navBar,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: AppSizes.buttonHeight,
          child: OutlinedButton.icon(
            onPressed: enabled ? onEdit : null,
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Edit post'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(
                color: enabled ? AppColors.primary : AppColors.border,
                width: 1.4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
              ),
              // A button's textStyle replaces the inherited one, so it must
              // name the family or the label falls back to the phone's font.
              textStyle: AppTextStyles.button,
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.accentSofter,
        borderRadius: BorderRadius.circular(AppSizes.md),
        border: Border.all(color: AppColors.accentSoft),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: AppColors.accentDark,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(
              Icons.close_rounded,
              size: 15,
              color: AppColors.hint,
            ),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSizes.xxl),
      children: <Widget>[
        const SizedBox(height: 80),
        Center(child: child),
      ],
    );
  }
}

/// Entry point to the live map, shown once a pickup job is confirmed.
class _TrackBanner extends StatelessWidget {
  const _TrackBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(AppSizes.tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.lg),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  size: 21,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Track your appliance',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'See where it is on the way to and from the workshop.',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scrim and spinner shown while a booking or a re-match is in flight.
///
/// ## Why it blocks
///
/// `AbsorbPointer` is the point, not the spinner. Selecting a technician is not
/// idempotent - it promotes one match to `offered` and retires the rest - so a
/// second tap while the first is still travelling is a real double-send. The
/// provider guards this too (`if (_isResponding) return false`), but a UI that
/// silently swallows taps feels broken; one that visibly stops accepting them
/// explains itself.
///
/// ## Why it is translucent
///
/// The matches stay readable underneath. The client just chose one of three
/// people and is waiting to hear back - hiding the three of them at that exact
/// moment is the worst time to do it.
class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: AppColors.background.withValues(alpha: 0.72),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.xl,
                vertical: AppSizes.lg,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSizes.tileRadius),
                border: Border.all(color: AppColors.border),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Color(0x1A0B2B5C), blurRadius: 16),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  ),
                  const SizedBox(height: AppSizes.md),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
