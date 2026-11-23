import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sugo_delete_animation.dart';
import '../../../core/widgets/sugo_dialog.dart';
import '../../../core/widgets/staggered_entrance.dart';
import '../../../core/widgets/sugo_app_bar.dart';
import '../../../core/widgets/sugo_motion.dart';
import '../../../core/widgets/sugo_route_line.dart';
import '../../../core/widgets/sugo_skeleton.dart';
import '../../bookings/models/booking_route.dart';
import '../models/job.dart';
import '../models/job_enums.dart';
import '../models/job_price.dart';
import '../models/labor_price_catalog.dart';
import '../models/match_result.dart';
import '../models/score_breakdown.dart';
import '../models/schedule_preference.dart';
import '../models/technician_preferences.dart';
import '../providers/job_posting_provider.dart';
import '../providers/match_provider.dart';
import '../services/rb_cars_service.dart';
import '../widgets/booking_pause.dart';
import '../widgets/booking_request_sheet.dart';
import '../widgets/context_summary.dart';
import '../widgets/delivery_option_selector.dart';
import '../widgets/match_score_card.dart';
import '../widgets/more_technicians_section.dart';
import '../widgets/recommendation_reasons_sheet.dart';
import '../widgets/relax_preferences_panel.dart';
import '../widgets/request_send_intro.dart';
import '../widgets/send_request_animation.dart';
import '../widgets/technician_matching_loader.dart';
import 'matching_walkthrough_screen.dart';
import '../../tracking/screens/job_tracking_screen.dart';
import '../../client/screens/client_dashboard_screen.dart';
import '../../community/screens/community_post_screen.dart';
import '../../community/models/community_models.dart';
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
  bool _isSwitchingToService = false;

  /// True from the first frame when there is a draft to post, so the back
  /// gesture is already blocked before [_post] has begun.
  late bool _isPosting = widget.jobId == null;

  /// One matching run's clock, shared by the posting loader and the review's
  /// loader so the animation carries straight on when the job is saved.
  MatchingSession _session = MatchingSession();

  /// The last post failed because of the connection (2026-11-23): the
  /// pop-up says "Connection problem" rather than a generic failure.
  bool _postOffline = false;

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
      // A retry starts the analysis screen afresh: a new clock, so it does
      // not open already "taking longer than usual" with the bar at 90%.
      if (_postError != null) _session = MatchingSession();
      _postError = null;
      _isPosting = true;
    });

    final JobPostingProvider draft = widget.draft!;
    final Job? job = await draft.submit();

    if (!mounted) return;

    if (job == null) {
      setState(() {
        _postError = draft.error ?? 'Could not post this job.';
        _postOffline = draft.connectionProblem;
        _isPosting = false;
        // Retry goes straight back to the analysis screen; the letter has
        // been sent once already.
        _sendIntro = false;
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

  /// The "letter to the technicians" opening (2026-11-23): plays first when
  /// arriving from Find technician / Save & find technicians, while the save
  /// runs underneath, then fades into the analysis screen. Not for a
  /// community post, which has its own screen; cut short by a failed post,
  /// whose retry matters more than the rest of the letter.
  late bool _sendIntro =
      widget.draft != null &&
      widget.draft!.draft.servicePath != ServicePath.itCommunity;

  @override
  Widget build(BuildContext context) {
    final bool intro = _sendIntro && _postError == null;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: intro
          ? KeyedSubtree(
              key: const ValueKey<String>('send-intro'),
              child: _buildSendIntro(),
            )
          : KeyedSubtree(
              key: const ValueKey<String>('main'),
              child: _buildMain(context),
            ),
    );
  }

  Widget _buildSendIntro() {
    final JobPostingProvider posting = widget.draft!;
    final JobDraft draft = posting.draft;
    final LaborPrice? labor =
        draft.deviceType == null || draft.problemSymptom == null
        ? null
        : LaborPriceCatalog.forJob(
            deviceType: draft.deviceType!,
            symptomCode: draft.problemSymptom!,
          );
    final String detail = <String?>[
      posting.deviceCategory?.label,
      labor?.fee,
    ].whereType<String>().join(' · ');

    // Back is refused: the job is still being saved underneath.
    return PopScope(
      canPop: false,
      child: MatchingLoaderScaffold(
        canGoBack: false,
        loader: RequestSendIntro(
          title: labor?.symptom ?? 'Your repair request',
          detail: detail.isEmpty ? null : detail,
          editing: posting.isEditing,
          onDone: () {
            if (mounted) setState(() => _sendIntro = false);
          },
        ),
      ),
    );
  }

  Widget _buildMain(BuildContext context) {
    final String? jobId = _jobId;

    if (jobId == null) {
      // Leaving mid-insert would strand a job nobody is looking at, so the
      // back gesture is refused until the post settles one way or the other.
      // Offline, too slow, or refused (2026-11-23): the animation goes, and a
      // pop-up offers Retry - which brings the analysis screen straight back.
      if (_postError != null) {
        return PopScope(
          canPop: !_isPosting,
          child: MatchingLoaderScaffold(
            canGoBack: !_isPosting,
            loader: _PostFailed(
              message: _postError!,
              offline: _postOffline,
              onRetry: _post,
              onBack: () => Navigator.of(context).maybePop(),
            ),
          ),
        );
      }

      // The analysis screen, following the post as it really goes: the first
      // tick waits for the job to be saved, the rest for the match result.
      final JobPostingProvider draft = widget.draft!;
      if (draft.draft.servicePath == ServicePath.itCommunity) {
        return PopScope(
          canPop: !_isPosting,
          child: Scaffold(
            appBar: SugoAppBar(
              title: 'Posting to technician community',
              automaticallyImplyLeading: !_isPosting,
            ),
            body: Center(
              child: _isPosting
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CircularProgressIndicator(),
                        SizedBox(height: AppSizes.lg),
                        Text('Posting your question...'),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        );
      }

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

    if (_isSwitchingToService) {
      return const Scaffold(
        appBar: SugoAppBar(title: 'Finding a technician'),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: AppSizes.lg),
              Text('Updating your request...'),
            ],
          ),
        ),
      );
    }

    if (widget.draft?.postedToTechnicianCommunity ?? false) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? _) {
          if (!didPop) {
            Navigator.of(
              context,
            ).popUntil((Route<dynamic> route) => route.isFirst);
          }
        },
        child: _TechnicianCommunityPostedView(
          communityPost: widget.draft!.communityPost,
          onChooseService: _chooseService,
        ),
      );
    }

    final Widget review = ChangeNotifierProvider<MatchProvider>(
      create: (_) => MatchProvider(
        jobId: jobId,
        service: widget.service,
        initialNotice: widget.draft?.matchingNotice,
        // Null when opened from the dashboard - "not known yet", which
        // `load()` resolves from the job itself.
        initialPreferencesBlocked: widget.draft?.preferencesBlocked,
        initialRelaxHints: widget.draft?.relaxHints ?? const [],
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

  Future<void> _chooseService(ServicePath path) async {
    final JobPostingProvider posting = widget.draft!;
    setState(() => _isSwitchingToService = true);
    posting.chooseServicePath(path);

    final Job? job = await posting.submit();
    if (!mounted) return;

    if (job == null) {
      setState(() => _isSwitchingToService = false);
      UiFeedback.showError(
        context,
        posting.error ?? 'Could not change this request to a service.',
      );
      return;
    }

    posting.leaveTechnicianCommunity();
    setState(() {
      _jobId = job.id;
      _isSwitchingToService = false;
    });
  }
}

class _TechnicianCommunityPostedView extends StatelessWidget {
  const _TechnicianCommunityPostedView({
    required this.communityPost,
    required this.onChooseService,
  });

  final CommunityPost? communityPost;
  final Future<void> Function(ServicePath path) onChooseService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SugoAppBar(title: 'Technician community'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.screenPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(
                Icons.groups_rounded,
                size: 56,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSizes.lg),
              const Text(
                'Your question is now in the technician community',
                textAlign: TextAlign.center,
                style: AppTextStyles.headline,
              ),
              const SizedBox(height: AppSizes.sm),
              const Text(
                'Technicians can comment with steps to try. If you cannot do '
                'the fix yourself, you can then choose Home Service or Shop '
                'Repair.',
                textAlign: TextAlign.center,
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: AppSizes.xl),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Need someone to do it for you?',
                  style: AppTextStyles.subtitle,
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              OutlinedButton.icon(
                onPressed: () => onChooseService(ServicePath.homeService),
                icon: const Icon(Icons.home_repair_service_rounded),
                label: const Text('Book Home Service'),
              ),
              const SizedBox(height: AppSizes.sm),
              OutlinedButton.icon(
                onPressed: () => onChooseService(ServicePath.pickup),
                icon: const Icon(Icons.local_shipping_rounded),
                label: const Text('Book Shop Repair'),
              ),
              const SizedBox(height: AppSizes.lg),
              PrimaryButton(
                label: 'Open technician community',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) {
                      final CommunityPost? post = communityPost;
                      if (post == null) {
                        return const ClientDashboardScreen(
                          initialTab: ClientTab.community,
                        );
                      }
                      return CommunityPostScreen(
                        post: post,
                        isClient: true,
                        onChooseService: (ServicePath path) async {
                          await onChooseService(path);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).popUntil((Route<dynamic> route) => route.isFirst),
                child: const Text('Back to home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The decoration clock for the failure pop-up's backdrop: held still.
final ValueNotifier<Duration> _stillBackdrop = ValueNotifier<Duration>(
  const Duration(milliseconds: 1600),
);

/// The post did not go through: offline, too slow, or refused.
///
/// Redesigned 2026-11-23 at the user's request ("if the connection is slow or
/// the internet is lost, make the animation disappear and pop up a retry
/// button"): a card pops up over the analysis screen's navy, says what went
/// wrong, and offers **Retry**, which brings the animation straight back.
/// The draft is still in memory on the provider below this route, so a retry
/// re-sends it rather than asking for the form again - and
/// [JobDraft.requestId] makes sure a post whose reply was lost is never
/// saved twice.
class _PostFailed extends StatelessWidget {
  const _PostFailed({
    required this.message,
    required this.offline,
    required this.onRetry,
    required this.onBack,
  });

  final String message;

  /// The connection was the problem, not a refusal.
  final bool offline;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final bool reduced = AppMotion.reduced(context);

    final Widget card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Material(
        color: AppColors.surface,
        elevation: 8,
        shadowColor: AppColors.navy.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppSizes.sheetRadius + 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.xl,
            AppSizes.xl,
            AppSizes.xl,
            AppSizes.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: _ProblemIcon(offline: offline, reduced: reduced),
              ),
              const SizedBox(height: AppSizes.lg),
              Text(
                offline ? 'Connection problem' : "Couldn't finish that",
                textAlign: TextAlign.center,
                style: AppTextStyles.title,
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (offline) ...<Widget>[
                const SizedBox(height: AppSizes.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.md,
                    vertical: AppSizes.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppSizes.tileRadius),
                  ),
                  child: const Row(
                    children: <Widget>[
                      Icon(
                        Icons.verified_user_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: AppSizes.sm),
                      Expanded(
                        child: Text(
                          "Retrying is safe - your job won't be posted twice.",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSizes.lg),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              TextButton(
                onPressed: onBack,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  minimumSize: const Size.fromHeight(AppSizes.touchTarget),
                ),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );

    return Stack(
      children: <Widget>[
        Positioned.fill(child: MatchingBackdrop(clock: _stillBackdrop)),
        // Dimmed, like the ground behind any pop-up.
        Positioned.fill(
          child: ColoredBox(color: AppColors.navy.withValues(alpha: 0.35)),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.xl),
              // Pops in: a small spring, the same as SUGO's other pop-ups.
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                builder: (BuildContext _, double v, Widget? child) => Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Transform.scale(scale: 0.86 + 0.14 * v, child: child),
                ),
                child: card,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// No signal (offline) or a warning (anything else), on a soft disc, with
/// one shake as it lands.
class _ProblemIcon extends StatelessWidget {
  const _ProblemIcon({required this.offline, required this.reduced});

  final bool offline;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final Widget disc = Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: offline ? AppColors.primarySoft : AppColors.warningSoft,
        border: Border.all(
          color: (offline ? AppColors.secondary : AppColors.warning).withValues(
            alpha: 0.35,
          ),
          width: 2,
        ),
      ),
      child: Icon(
        offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
        size: 38,
        color: offline ? AppColors.primary : AppColors.warning,
      ),
    );
    return reduced
        ? disc
        : SugoWiggle(angle: 0.16, alignment: Alignment.center, child: disc);
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
      //
      // "Delete request" sits beside it (2026-09-29): a client who has not
      // booked anyone can drop the whole thing from here, rather than having
      // to find the job again under Bookings.
      bottomNavigationBar: job != null && _canEdit(job, matching)
          ? _EditPostBar(
              enabled: !matching.isLoading && !matching.isResponding,
              onEdit: () => _editPost(context, job, matching),
              onDelete: job.canBeDeletedByClient
                  ? () => _deletePost(context, matching)
                  : null,
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
    if (matching.isCheckingTechnician) return 'Checking their schedule...';
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

    // The client's own preferences left nobody (the engine's
    // `no_match_relax_preferences`). Offer to relax them, one chip each,
    // rather than an empty list - the brief's impossible-combination case.
    if (matching.showRelaxPreferences && job != null) {
      return _Centered(
        child: RelaxPreferencesPanel(
          preferences: job.preferences,
          hints: matching.relaxHints,
          message: matching.notice,
          onRelax: matching.relaxPreferences,
          onSearchAgain: matching.rematch,
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
        // Book-and-cancel cooldown (2026-11-17): first thing on screen, so
        // the wait is explained before a Book button is tapped.
        if (matching.bookingPausedUntil != null) ...<Widget>[
          BookingPauseBanner(
            until: matching.bookingPausedUntil!,
            onDone: matching.clearBookingPause,
          ),
          const SizedBox(height: AppSizes.md),
        ],
        if (job != null)
          _JobSummary(
            job: job,
            matches: matching.matches,
            offerPending: matching.matches.any(
              (MatchResult m) => m.isAwaitingTechnician,
            ),
            // Long-press the conditions for the ranking walkthrough, for a
            // demo; debug builds also show a link.
            onWalkthrough: () => _openWalkthrough(context, matching),
          ),
        // The client's own must-haves, read back where they take effect: the
        // list below is already filtered by them (2026-11-17).
        if (job != null && job.preferences.hasAny) ...<Widget>[
          const SizedBox(height: AppSizes.md),
          _MustHaves(
            preferences: job.preferences,
            onEdit: _canEdit(job, matching)
                ? () => _editPost(context, job, matching)
                : null,
          ),
        ],
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
            // How many, as a gradient badge - the number a client wants
            // first (2026-11-23).
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[AppColors.secondary, AppColors.cyan],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                '${matching.matches.length}',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              // The app bar already says "Choose a technician"; this line
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

        if (matching.notice != null) ...<Widget>[
          _Notice(message: matching.notice!, onDismiss: matching.clearNotice),
          const SizedBox(height: AppSizes.lg),
        ],

        // Nobody within the client's distance limit: the matcher showed the
        // nearest who meet everything else, and says so (2026-11-17).
        if (_fallbackOf(matching.matches)
            case final PreferenceFallback fb) ...<Widget>[
          _DistanceFallbackBanner(fallback: fb),
          const SizedBox(height: AppSizes.lg),
        ],

        // Cards rise in one after another - a short, quiet entrance that
        // reads as "here are your three" rather than a list popping in.
        StaggeredEntrance(
          children: <Widget>[
            for (final MatchResult match in matching.matches)
              MatchScoreCard(
                match: match,
                preferences: job?.preferences,
                highlighted: match.technicianId == preselectedTechnicianId,
                onTap: () => _openDetail(context, match),
                onWhyTap: () => RecommendationReasonsSheet.show(context, match),
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
            'The whole pool that passed the hard gates, in the order SUGO '
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

  /// Deletes a job nobody has booked yet, under the bin animation, then goes
  /// home - there is nothing left on this screen to look at.
  Future<void> _deletePost(BuildContext context, MatchProvider matching) async {
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
    if (!confirmed || !context.mounted) return;

    try {
      // The bin says "Request deleted" itself, so no snackbar.
      await runWithDeleteAnimation(context, matching.deleteJob());
      if (!context.mounted) return;
      Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    } on RbCarsFailure catch (failure) {
      if (context.mounted) UiFeedback.showError(context, failure.message);
    }
  }

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
          waitingOn.technician?.displayName.split(' ').first ??
          'the technician';
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

    // Book-and-cancel cooldown (2026-11-17). The banner above already shows
    // the countdown; this stops the booking sheet opening for a request the
    // server would refuse.
    final DateTime? paused = matching.bookingPausedUntil;
    if (paused != null) {
      UiFeedback.showInfo(
        context,
        'You can book again in '
        '${bookingPauseLabel(paused.difference(DateTime.now()))}.',
      );
      return;
    }

    // The card hides its button for a technician on vacation; this covers any
    // other route here. The server refuses the request regardless.
    final String? away = match.technician?.awayLabel;
    if (away != null) {
      UiFeedback.showInfo(context, '$away and cannot be booked.');
      return;
    }

    final String name =
        match.technician?.displayName.split(' ').first ?? 'this technician';
    final Job? priceJob = matching.job;
    final LaborPrice? labor = priceJob == null
        ? null
        : LaborPriceCatalog.forJob(
            deviceType: priceJob.deviceType,
            symptomCode: priceJob.problemSymptom,
          );
    final double? distanceKm = priceJob?.servicePath == ServicePath.homeService
        ? match.breakdown.context.distanceKm ?? match.technician?.distanceKm
        : null;
    final int? travelFee = LaborPriceCatalog.travelFee(distanceKm);

    // On another job? Asked live, because the card's label is from when the
    // job was matched (2026-09-29). They can still be requested: the client
    // is told, and chooses to wait or to pick someone else. The technician
    // cannot accept until their current job is done - the server holds that.
    //
    // The same call brings the distance to this technician's shop for a shop
    // repair (2026-11-16), so the delivery fee is on screen before Send.
    final TechnicianStatus status = await matching.technicianStatus(match.id);
    final bool busy = status.busy;
    if (!context.mounted) return;

    // Shop repair: "bring it myself" or "shop pickup/delivery". Asked HERE
    // only - the posting flow stopped asking on 2026-11-17 - starting from
    // delivery (or what an earlier booking saved), switchable, with the fee
    // updating as they switch. Sent with the request; the server saves it
    // with the fee it works out from the same distance.
    final bool isShopRepair = priceJob?.servicePath == ServicePath.pickup;
    DeliveryOption deliveryOption =
        priceJob?.deliveryOption ?? DeliveryOption.delivery;

    Widget content(StateSetter setDialogState, {bool busy = false}) =>
        _BookingPriceContent(
          technicianName: name,
          labor: labor,
          distanceKm: distanceKm,
          travelFee: travelFee,
          urgent: priceJob?.urgency == Urgency.needToday,
          busy: busy,
          deliveryChooser: isShopRepair
              ? DeliveryOptionSelector(
                  value: deliveryOption,
                  distanceKm: status.shopDistanceKm,
                  onChanged: (DeliveryOption option) =>
                      setDialogState(() => deliveryOption = option),
                )
              : null,
        );

    // The send-request moment is a sheet about the technician, not a system
    // dialog - see `showBookingRequestSheet`.
    final bool? confirmed = await showBookingRequestSheet(
      context: context,
      technician: match.technician,
      name: name,
      busy: busy,
      contentBuilder: (StateSetter setSheetState) =>
          content(setSheetState, busy: busy),
    );

    if (confirmed != true || !context.mounted) return;

    // The request flies away to them while it is really being sent
    // (2026-11-23); the tick only lands once the server has accepted it.
    final bool ok = await runWithSendAnimation(
      context,
      matching.selectTechnician(
        match.id,
        deliveryOption: isShopRepair ? deliveryOption : null,
      ),
      name: name,
      technician: match.technician,
    );
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
      // In place of the whole flow, not just this screen - see
      // `BookingSuccessScreen.show`. This screen's own `PopScope` sent Back
      // home, but it leaves with the screen it wraps.
      final Job? job = matching.job;
      if (job == null) {
        UiFeedback.showSuccess(context, 'Request sent to $name.');
        Navigator.of(context).popUntil((Route<void> route) => route.isFirst);
        return;
      }
      BookingSuccessScreen.show(
        context,
        job: job,
        technician: match.technician,
        match: match,
      );
    } else if (matching.bookingPausedUntil != null) {
      // Refused by the cooldown (a pause started on another phone, say): the
      // banner has appeared with the countdown, so a short pointer is enough.
      UiFeedback.showInfo(
        context,
        'Booking is paused for a moment. See the timer at the top.',
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
/// The decoration clock for the header's backdrop: held still.
final ValueNotifier<Duration> _stillHeader = ValueNotifier<Duration>(
  const Duration(milliseconds: 1600),
);

/// The header of "Choose a technician": the request, where it is, and what
/// SUGO saw when it ranked - on SUGO navy.
///
/// ## Renovated 2026-11-23
///
/// At the user's request ("renovate that UI/UX, make it cool and suitable
/// for SUGO"). It was a white card with the conditions chips in a separate
/// block under it. It is now one navy card on the analysis screen's own
/// twinkling ground (`MatchingBackdrop`), so the results open on the look
/// the matching screens just played in: the device in a frosted tile, the
/// route line in white and cyan, frosted pills, and "Based on your current
/// situation" inside it - long-press it for the ranking walkthrough.
class _JobSummary extends StatelessWidget {
  const _JobSummary({
    required this.job,
    required this.matches,
    this.offerPending = false,
    this.onWalkthrough,
  });

  final Job job;
  final List<MatchResult> matches;

  /// A technician has been asked and has not answered.
  final bool offerPending;

  /// Opens the ranking walkthrough (a long press on the conditions; debug
  /// builds also show a link).
  final VoidCallback? onWalkthrough;

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
    final Color soft = Colors.white.withValues(alpha: 0.72);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.sheetRadius + 4),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: MatchingBackdrop(clock: _stillHeader)),
          Padding(
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
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppSizes.radius),
                        border: Border.all(
                          color: AppColors.cyan.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Icon(job.deviceType.icon, color: AppColors.cyan),
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
                            style: AppTextStyles.sectionTitle.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            <String>[
                              job.deviceType.label,
                              if (brand != null && brand.isNotEmpty) brand,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(color: soft),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(
                          AppSizes.pillRadius,
                        ),
                      ),
                      child: Text(
                        job.reference,
                        style: AppTextStyles.micro.copyWith(
                          color: soft,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (position != null) ...<Widget>[
                  const SizedBox(height: AppSizes.lg),
                  SugoRouteLine(
                    stops: BookingRoute.stops,
                    position: position,
                    onDark: true,
                  ),
                ],
                const SizedBox(height: AppSizes.lg),
                Wrap(
                  spacing: AppSizes.sm,
                  runSpacing: AppSizes.sm,
                  children: <Widget>[
                    if (path != null)
                      _MetaPill(
                        icon: path.icon,
                        label: path.label,
                        onDark: true,
                      ),
                    _MetaPill(
                      icon: Icons.schedule_rounded,
                      label: schedule.label,
                      onDark: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.md),
                Row(
                  children: <Widget>[
                    Icon(Icons.place_rounded, size: 15, color: soft),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        job.locationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(color: soft),
                      ),
                    ),
                  ],
                ),
                if (matches.isNotEmpty) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
                    child: Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  // The context-aware part, made visible: what the engine
                  // saw, and the matching rules it re-weighted for.
                  ContextSummary(
                    matches: matches,
                    job: job,
                    onLongPress: onWalkthrough,
                    onDark: true,
                  ),
                  if (kDebugMode && onWalkthrough != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onWalkthrough,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.cyan,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        icon: const Icon(Icons.account_tree_outlined, size: 16),
                        label: const Text('How this was ranked (demo)'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Your must-haves" - the preferences the client set while posting, shown
/// above the matches they filtered. Tapping Edit reopens the post.
class _MustHaves extends StatelessWidget {
  const _MustHaves({required this.preferences, required this.onEdit});

  final TechnicianPreferences preferences;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.xs,
        AppSizes.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySofter,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.tune_rounded,
                size: 16,
                color: AppColors.primaryDark,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Your must-haves',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              if (onEdit != null)
                TextButton(onPressed: onEdit, child: const Text('Edit')),
            ],
          ),
          Wrap(
            spacing: AppSizes.xs,
            runSpacing: AppSizes.xs,
            children: <Widget>[
              for (final PreferenceField field in preferences.active)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    preferences.labelFor(field),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            'Only technicians who meet all of these are shown.',
            style: AppTextStyles.micro,
          ),
        ],
      ),
    );
  }
}

class _BookingPriceContent extends StatelessWidget {
  const _BookingPriceContent({
    required this.technicianName,
    required this.labor,
    required this.distanceKm,
    required this.travelFee,
    this.urgent = false,
    this.busy = false,
    this.deliveryChooser,
  });

  final String technicianName;
  final LaborPrice? labor;
  final double? distanceKm;
  final int? travelFee;

  /// Posted as Urgent: 20% of the labor on top (2026-11-17).
  final bool urgent;
  final bool busy;

  /// Shop repairs: the bring-it-myself / delivery choice with its live fee.
  final Widget? deliveryChooser;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      if (labor != null) ...<Widget>[
        // The problem as a normal line of text. It used to be a label/value
        // row, where a long symptom squeezed the label into "Sy / mpt / om".
        const Text(
          'Problem',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          labor!.symptom,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const Divider(height: AppSizes.lg),
        const Text('Price', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: AppSizes.sm),
        _PriceLine(label: 'Labor fee', value: labor!.fee),
        if (urgent)
          _PriceLine(
            label: JobPrice.urgentFeeLabel,
            value: LaborPriceCatalog.urgentFee(labor!) == null
                ? '+20% of labor'
                : '₱${LaborPriceCatalog.urgentFee(labor!)}',
          ),
        if (travelFee != null) ...<Widget>[
          _PriceLine(
            label: 'Travel fee (${distanceKm!.toStringAsFixed(1)} km)',
            value: '₱$travelFee',
          ),
          const Divider(height: AppSizes.lg),
          _PriceLine(
            label: 'Estimated total',
            value: LaborPriceCatalog.estimatedTotal(
              labor: labor!,
              travelFee: travelFee!,
              urgentFee: urgent ? LaborPriceCatalog.urgentFee(labor!) ?? 0 : 0,
            ),
            bold: true,
          ),
        ],
        const SizedBox(height: AppSizes.md),
      ],
      if (deliveryChooser != null) ...<Widget>[
        const Text(
          'Getting it to the shop',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSizes.sm),
        deliveryChooser!,
        const SizedBox(height: AppSizes.md),
      ],
      Text(
        busy
            ? '$technicianName is finishing a repair for someone else, so '
                  'they can only accept yours once that one is done. You can '
                  'send the request now and wait, or choose someone else.'
            : 'We will send your job to $technicianName and let the other '
                  'options go. They still need to accept before it is '
                  'confirmed.',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.xs),
      // Both sides may wrap. A fixed value used to take all the width it
      // wanted and crush the label into a column of syllables.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 3, child: Text(label)),
          const SizedBox(width: AppSizes.sm),
          Flexible(
            flex: 2,
            child: Text(value, style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    this.onDark = false,
  });

  final IconData icon;
  final String label;

  /// Frosted, for the navy header.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.09)
            : AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
        border: Border.all(
          color: onDark
              ? Colors.white.withValues(alpha: 0.16)
              : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 14,
            color: onDark ? AppColors.cyan : AppColors.primary,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.micro.copyWith(
                fontWeight: FontWeight.w700,
                color: onDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "SUGO" beside the section title: who did the ranking.
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
            'SUGO',
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

/// The sticky bar under the matches: "Edit post", and "Delete request" while
/// nobody has taken the job.
class _EditPostBar extends StatelessWidget {
  const _EditPostBar({
    required this.onEdit,
    required this.enabled,
    this.onDelete,
  });

  final VoidCallback onEdit;
  final bool enabled;

  /// Null when the job can no longer be deleted.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    // A floating tray (2026-11-23): rounded, lifted off the page, rather than
    // a full-width strip ruled off at the top.
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppSizes.screenPadding,
          0,
          AppSizes.screenPadding,
          AppSizes.sm,
        ),
        padding: const EdgeInsets.all(AppSizes.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.sheetRadius),
          border: Border.all(color: AppColors.border),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.14),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Expanded(child: _edit()),
            if (onDelete != null) ...<Widget>[
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: SizedBox(
                  height: AppSizes.buttonHeight,
                  child: OutlinedButton.icon(
                    onPressed: enabled ? onDelete : null,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete request'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(
                        color: enabled ? AppColors.error : AppColors.border,
                        width: 1.4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSizes.buttonRadius,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.sm,
                      ),
                      textStyle: AppTextStyles.button,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _edit() {
    return SizedBox(
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
    );
  }
}

/// The distance fallback the shortlist was built with, if any. Read from the
/// first match that carries it - the engine writes it on every row of a run.
PreferenceFallback? _fallbackOf(List<MatchResult> matches) {
  for (final MatchResult m in matches) {
    if (m.breakdown.preferenceFallback != null) {
      return m.breakdown.preferenceFallback;
    }
  }
  return null;
}

/// "No technician within 5 km - the nearest is 12 km away."
class _DistanceFallbackBanner extends StatelessWidget {
  const _DistanceFallbackBanner({required this.fallback});

  final PreferenceFallback fallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppSizes.tileRadius),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.near_me_disabled_rounded,
            size: 20,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSizes.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  fallback.message,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'These are the closest technicians who meet your other '
                  'preferences. Their travel fee is for the longer distance.',
                  style: AppTextStyles.micro.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ],
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
