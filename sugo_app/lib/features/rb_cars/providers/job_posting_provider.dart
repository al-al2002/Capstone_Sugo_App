import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import '../../../core/utils/network_errors.dart';

import '../models/device_category.dart';
import '../models/job.dart';
import '../models/match_result.dart';
import '../models/issue_catalog.dart';
import '../models/job_enums.dart';
import '../models/schedule_preference.dart';
import '../models/technician_preferences.dart';
import '../services/rb_cars_service.dart';
import '../../community/models/community_models.dart';
import '../../community/services/community_service.dart';

/// Drives the three-screen job posting flow.
///
/// Held by the flow, not by the app: created when the client starts posting and
/// disposed when they leave, so a half-finished draft never leaks into the next
/// booking. The screens read [draft] and call the mutators; nothing writes to
/// the draft directly.
class JobPostingProvider extends ChangeNotifier {
  JobPostingProvider({
    RbCarsService? service,
    CommunityService? communityService,
    this.preselectedTechnicianId,
    this.limits = const PostingTimeLimits(),
  }) : _service = service ?? RbCarsService(),
       _communityService = communityService ?? CommunityService(),
       editingJob = null;

  /// "Edit post": the same six steps, opened on an existing job with every
  /// answer already filled in. Saving updates that job instead of posting a
  /// new one, and matching runs again for the changed details.
  JobPostingProvider.editing(
    Job job, {
    RbCarsService? service,
    CommunityService? communityService,
    this.limits = const PostingTimeLimits(),
  }) : _service = service ?? RbCarsService(),
       _communityService = communityService ?? CommunityService(),
       preselectedTechnicianId = null,
       editingJob = job {
    _prefill(job);
  }

  final RbCarsService _service;
  final CommunityService _communityService;

  /// How long each step of [submit] may take before it is given up as a
  /// connection problem.
  final PostingTimeLimits limits;

  /// The job being edited, or null when posting a new one.
  final Job? editingJob;

  bool get isEditing => editingJob != null;

  /// Set when the flow was started from a technician's detail screen. The job
  /// is still matched normally - RB-CARS decides the ranking - but the review
  /// screen surfaces this technician first if they made the Top 3.
  final String? preselectedTechnicianId;

  final JobDraft draft = JobDraft();

  /// Which of the five cards on step 1 is lit.
  ///
  /// Held next to the draft rather than on it, because it is not a column:
  /// `network` and `cctv` both write `jobs.device_type = 'network'`, so the
  /// draft alone cannot say which card the client tapped. See [DeviceCategory].
  DeviceCategory? _deviceCategory;
  DeviceCategory? get deviceCategory => _deviceCategory;

  final List<XFile> _photos = <XFile>[];
  List<XFile> get photos => List<XFile>.unmodifiable(_photos);

  /// Photos already uploaded - the ones on the job being edited, and after a
  /// save, everything that went up with it. Kept by URL so a second save does
  /// not upload the same pictures again.
  List<String> _keptPhotoUrls = <String>[];
  List<String> get keptPhotoUrls => List<String>.unmodifiable(_keptPhotoUrls);

  bool _isSubmitting = false;
  bool _requestSaved = false;
  String? _error;
  Job? _postedJob;
  bool _communityPostCreated = false;
  CommunityPost? _communityPost;
  int _photosFailed = 0;

  bool _connectionProblem = false;

  bool get isSubmitting => _isSubmitting;

  /// True once the current [submit] has saved the job and moved on to the
  /// matcher. The matching screen's first tick waits for this.
  bool get requestSaved => _requestSaved;
  String? get error => _error;

  /// The last [submit] failed because of the connection - offline, dropped,
  /// or a step over its time limit - rather than a refusal. The screen then
  /// shows "Connection problem" with Retry (2026-11-23).
  bool get connectionProblem => _connectionProblem;
  Job? get postedJob => _postedJob;
  bool get postedToTechnicianCommunity => _communityPostCreated;
  CommunityPost? get communityPost => _communityPost;

  /// The engine's explanation when the first matching run found nobody.
  ///
  /// Null when it found someone, or when nothing has run yet.
  String? _matchingNotice;
  String? get matchingNotice => _matchingNotice;

  /// True when the first matching run found nobody *because of the client's
  /// own preferences* - the engine's `no_match_relax_preferences`. The review
  /// screen then opens on "try relaxing them" instead of an empty list.
  bool _preferencesBlocked = false;
  bool get preferencesBlocked => _preferencesBlocked;

  /// How many technicians removing each single preference would bring back.
  List<RelaxHint> _relaxHints = const <RelaxHint>[];
  List<RelaxHint> get relaxHints => _relaxHints;

  /// How many of the new photos did not reach storage on the last save. The
  /// job was still saved; the screen says so.
  int get photosFailed => _photosFailed;

  /// Fills the draft from a saved job, for "Edit post".
  void _prefill(Job job) {
    _deviceCategory = DeviceCategory.forJob(
      deviceType: job.deviceType,
      deviceDetail: job.deviceDetail,
      symptomCode: job.problemSymptom,
    );
    draft
      ..deviceType = job.deviceType
      ..deviceDetail = job.deviceDetail
      ..brand = job.brand
      ..problemSymptom = job.problemSymptom
      ..hasPhysicalDamage = job.hasPhysicalDamage
      ..urgency = job.urgency
      ..latitude = job.latitude
      ..longitude = job.longitude
      ..locationLabel = job.addressText
      ..budgetMin = job.budgetMin
      ..budgetMax = job.budgetMax
      ..preferredSchedule = job.preferredSchedule
      // The Availability question was removed from step 2 (2026-11-17). A job
      // posted before that may still carry it, and the client could neither
      // see nor clear it here, so editing the post drops it.
      ..preferences = job.preferences.without(PreferenceField.availability)
      ..restoreDescription(job.description);

    // Re-derive the suggestion, then put back the path the client actually
    // chose. `classify()` clears any override, so the order matters.
    draft.classify();
    final ServicePath? saved = job.servicePath;
    if (saved != null && saved != draft.classification?.servicePath) {
      draft.servicePathOverride = saved;
    }

    _keptPhotoUrls = List<String>.of(job.photoUrls);
  }

  // ------------------------------------------------------- step 1: classify

  void selectCategory(DeviceCategory category) {
    if (_deviceCategory == category) return;
    _deviceCategory = category;
    draft.deviceType = category.deviceType;
    // The precise device and brand belonged to the previous category. Keeping
    // them would send a "desktop / Apple" detail along with an appliance job.
    // Where the new card already implies the device - a CCTV job is a camera
    // by the time it is tapped - the detail step opens with it chosen instead
    // of asking a question the client has answered.
    draft.deviceDetail = category.deviceDetailWire;
    draft.brand = null;
    // Symptoms are device-specific, so an old selection is now meaningless.
    draft.problemSymptom = null;
    draft.classification = null;
    // So is a specialisation the new device cannot use - "Phone/Tablet"
    // carried onto an aircon job could only ever produce an empty list. The
    // other preferences are about the technician, not the device, and stay.
    final PreferredSpecialization? wanted = draft.preferences.specialization;
    if (wanted != null &&
        !PreferredSpecialization.forCategory(category).contains(wanted)) {
      draft.preferences = draft.preferences.copyWith(
        specialization: () => null,
      );
    }
    _error = null;
    notifyListeners();
  }

  // -------------------------------------------- step 2: your technician

  /// The client's minimum requirements. See [TechnicianPreferences].
  TechnicianPreferences get preferences => draft.preferences;

  /// Replaces the whole set. The step builds the next value with
  /// [TechnicianPreferences.copyWith], so every control goes through one door.
  void setPreferences(TechnicianPreferences next) {
    if (next == draft.preferences) return;
    draft.preferences = next;
    notifyListeners();
  }

  /// Every field back to "No preference".
  void resetPreferences() => setPreferences(TechnicianPreferences.none);

  /// Records the chosen issue, and answers what the issue already implies.
  ///
  /// Two fields move on their own here:
  ///
  /// * **Physical damage.** "Screen cracked" *is* damage - asking the client to
  ///   confirm it on the next question is a question with one answer. The flag
  ///   is only ever set from an issue that implies it, and cleared again when
  ///   they switch to one that does not, so an implied answer never survives
  ///   the choice that implied it. A box the client ticked themselves is left
  ///   alone.
  /// * **Urgency.** A gas leak or a tripping breaker is a safety matter, so it
  ///   defaults to "need today". A default, not a lock: the urgency step later
  ///   in the flow can still be changed.
  void selectSymptom(String symptomCode) {
    final IssueOption? previous = IssueCatalog.byCode(draft.problemSymptom);
    final IssueOption? issue = IssueCatalog.byCode(symptomCode);

    draft.problemSymptom = symptomCode;

    // A cleaning or an install has no damage to report, and the question is
    // not shown for one (2026-11-16) - so a "yes, damaged" left over from a
    // repair picked earlier must not reroute an aircon cleaning to the shop.
    // Cleared before classifying, because damage is a rule-base input.
    if (issue != null && !issue.kind.asksAboutDamage) {
      draft.hasPhysicalDamage = false;
    }

    // Classified here rather than on "Continue", because the suggestion is now
    // shown on the same screen as the symptom. The client picks "Won't turn on"
    // and the three path cards re-rank underneath their finger.
    draft.classify();

    if (issue?.impliesPhysicalDamage ?? false) {
      draft.hasPhysicalDamage = true;
    } else if (previous?.impliesPhysicalDamage ?? false) {
      draft.hasPhysicalDamage = false;
    }

    if (issue?.isUrgent ?? false) draft.urgency = Urgency.needToday;

    notifyListeners();
  }

  /// Records the precise device and its brand.
  ///
  /// Both feed the Stage 1 brand ladder. Either may be null - the client is
  /// not required to know their model, and the matcher falls back to
  /// device-category matching when they do not.
  void setDeviceDetail({String? deviceDetail, String? brand}) {
    draft.deviceDetail = deviceDetail;
    draft.brand = brand;
    notifyListeners();
  }

  void setPhysicalDamage(bool value) {
    draft.hasPhysicalDamage = value;
    // Damage is a rule-base input - "screen cracked" routes to the shop and
    // "screen flickering" does not - so the suggestion is re-run, not cleared.
    // Clearing it emptied the cards the client was looking at.
    if (draft.problemSymptom != null) draft.classify();
    notifyListeners();
  }

  /// The client overriding our suggestion. Their call wins; we keep the
  /// original confidence so the analytics still show what the rules said.
  void overrideServicePath(ServicePath path) {
    draft.servicePathOverride = path;
    notifyListeners();
  }

  /// Whether the picked issue is basic enough that the rule base suggests the
  /// Technician Community (`ClassificationResult.isBasic`). The problem step
  /// shows the basic-problem card exactly when this is true, so the card and
  /// the "Suggested" badge never disagree - before 2026-11-17 the card said
  /// "try the community" while Home Service carried the badge.
  bool get basicProblem => draft.classification?.isBasic ?? false;

  /// Changes a technician-community request into a service request while
  /// keeping the client's device details, location, photos and notes.
  void chooseServicePath(ServicePath path) {
    if (path == ServicePath.itCommunity) return;
    draft.servicePathOverride = path;
    notifyListeners();
  }

  /// Allows the review screen to leave the community result after the same
  /// job has been updated and matched for a service route.
  void leaveTechnicianCommunity() {
    _communityPostCreated = false;
    notifyListeners();
  }

  bool get canClassify =>
      draft.deviceType != null && draft.problemSymptom != null;

  // ---------------------------------------------------------- step 2: detail

  void setLocation({
    required double latitude,
    required double longitude,
    String? label,
  }) {
    draft.latitude = latitude;
    draft.longitude = longitude;
    draft.locationLabel = label;
    notifyListeners();
  }

  void setBudget({double? min, double? max}) {
    draft.budgetMin = min;
    draft.budgetMax = max;
    notifyListeners();
  }

  /// The "Flexible / Urgent" control, which writes both
  /// `jobs.urgency` and `jobs.preferred_schedule`. See [SchedulePreference].
  SchedulePreference get schedulePreference => SchedulePreference.fromJob(
    urgency: draft.urgency,
    preferredSchedule: draft.preferredSchedule,
  );

  void setSchedulePreference(SchedulePreference preference) {
    draft.urgency = preference.urgency;
    draft.preferredSchedule = preference.deadlineFrom(DateTime.now());
    notifyListeners();
  }

  void setModel(String? model) {
    draft.model = _clean(model);
  }

  void setDescription(String? description) {
    draft.description = _clean(description);
  }

  void setNotes(String? notes) {
    draft.notes = _clean(notes);
  }

  /// Blank and whitespace-only answers are stored as null, so an untouched
  /// optional field never reaches `composedDescription` as an empty line.
  static String? _clean(String? value) {
    final String? trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  void addPhoto(XFile file) {
    if (_photos.length + _keptPhotoUrls.length >= maxPhotos) return;
    _photos.add(file);
    notifyListeners();
  }

  /// Drops an already-uploaded photo from the job being edited. The file stays
  /// in storage; the job simply stops pointing at it.
  void removeKeptPhoto(String url) {
    if (_keptPhotoUrls.remove(url)) notifyListeners();
  }

  void removePhoto(XFile file) {
    _photos.remove(file);
    notifyListeners();
  }

  static const int maxPhotos = 4;

  // ---------------------------------------------------------- step gates
  //
  // One getter per step, each naming only what *that* step is responsible for.
  // The CTA on each screen reads its own gate, so a step can never be blocked
  // by a field that lives two screens later.

  /// Step 1 - a device card is lit.
  bool get canLeaveDevice => deviceCategory != null;

  /// Step 2 - nothing is required; every preference is optional. The one way
  /// to be stuck is "Pick a date" without a date, which could not be checked.
  bool get canLeavePreferences => !draft.preferences.isMissingDate;

  /// Step 3 - a symptom is chosen, so the rule base has something to run on.
  bool get canLeaveSymptom =>
      draft.problemSymptom != null && draft.servicePath != null;

  /// Step 4 - nothing is required. Brand, model and description are all
  /// optional: the matcher degrades to device-category matching without them,
  /// and blocking the flow on a model number nobody can find is worse than a
  /// slightly weaker match.
  bool get canLeaveDeviceDetails => true;

  /// Step 5 - the map has a pin. Proximity, traffic and weather all key off it,
  /// so this is the one answer the matcher cannot do without.
  bool get canLeaveWhereAndWhen => draft.latitude != null;

  bool get canSubmit =>
      draft.isClassified && draft.servicePath != null && draft.latitude != null;

  // ------------------------------------------------------------ step 3: post

  /// Uploads photos, saves the job, then runs the matcher.
  ///
  /// Returns the job on success, null on failure with [error] set. A photo
  /// that fails to upload is not fatal - the job saves without it - but a
  /// failed match is, because a job with no offers is a dead end for the client.
  ///
  /// ## Insert or update
  ///
  /// A new job is inserted once. Any later save from the same flow - an edit,
  /// or pressing "Find technician" again after the first post succeeded -
  /// UPDATES that job instead. The second case was a real bug: going back from
  /// the matching screen to the map and pressing the button again posted the
  /// same job twice. The screen no longer lets a client back into the flow
  /// after posting, but the flow itself refusing to duplicate is what makes
  /// that impossible rather than merely unlikely.
  Future<Job?> submit() async {
    if (_isSubmitting) return null;
    if (!canSubmit) {
      _error = 'Add a location before posting this job.';
      notifyListeners();
      return null;
    }

    _isSubmitting = true;
    _requestSaved = false;
    _error = null;
    _connectionProblem = false;
    notifyListeners();

    // Every step has a time limit (2026-11-23). Without one, a request on a
    // bad connection could hang for ever and leave the client watching the
    // analysis screen with nothing happening. Over its limit, a step is a
    // connection problem: the screen offers Retry, and a retry is safe -
    // [JobDraft.requestId] stops a lost-reply post from being saved twice.
    try {
      final List<String> uploaded = _photos.isEmpty
          ? const <String>[]
          : await _service.uploadPhotos(_photos).timeout(limits.photos);
      _photosFailed = _photos.length - uploaded.length;
      draft.photoUrls = <String>[..._keptPhotoUrls, ...uploaded];
      final XFile? communityPhoto = _photos.isEmpty ? null : _photos.first;

      final Job? existing = _postedJob ?? editingJob;
      if (existing == null) draft.requestId ??= newUuidV4();
      final Job job =
          await (existing == null
                  ? _service.postJob(draft)
                  : _service.updateJob(existing.id, draft))
              .timeout(limits.save);
      _postedJob = job;

      // Saved, and about to be matched. Announced because the matching
      // screen ticks "Understanding your request" on exactly this - an event
      // it can observe - rather than on a timer.
      _requestSaved = true;
      notifyListeners();

      // Those photos belong to the job now. Held by URL from here on, so a
      // later save keeps them without uploading them a second time.
      _keptPhotoUrls = List<String>.of(draft.photoUrls);
      _photos.clear();

      // A new post's question, once - including on a retry after the first
      // attempt saved the job but lost the question (2026-11-23: that retry
      // used to skip the question, because the job already existed).
      if (draft.servicePath == ServicePath.itCommunity &&
          editingJob == null &&
          !_communityPostCreated) {
        _communityPost = await _communityService
            .ask(
              title: 'Help with ${draft.deviceType?.label ?? 'my device'}',
              body: _communityQuestionBody(),
              topic: _communityTopic,
              photo: communityPhoto,
              sourceJobId: job.id,
            )
            .timeout(limits.save);
        _communityPostCreated = true;
        _requestSaved = false;
        notifyListeners();
        return job;
      }

      // Matching runs immediately: the client should land on the review screen
      // with a Top 3 already waiting, not on an empty list.
      final MatchingRun run = await _service
          .runMatching(job.id)
          .timeout(limits.matching);

      // When it found nobody, the engine says which gate emptied the pool -
      // "1 was outside their own service radius" rather than a shrug. Kept
      // here because the review screen reads `job_matches` from the database
      // on arrival, and a reason that exists only in this response would
      // otherwise be thrown away at the one moment it is most useful.
      _matchingNotice = run.matches.isEmpty ? run.message : null;
      _preferencesBlocked = run.matches.isEmpty && run.preferencesBlocked;
      _relaxHints = _preferencesBlocked ? run.relaxHints : const <RelaxHint>[];

      return job;
    } on TimeoutException {
      _connectionProblem = true;
      _error = RbCarsFailure.offlineMessage;
      return null;
    } on RbCarsFailure catch (failure) {
      _connectionProblem = failure.offline;
      _error = failure.message;
      return null;
    } catch (error) {
      _connectionProblem = looksLikeNetworkError(error);
      _error = _connectionProblem
          ? RbCarsFailure.offlineMessage
          : 'Could not post this job. Please try again.';
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  CommunityTopic get _communityTopic {
    return switch (draft.deviceType) {
      DeviceType.laptop => CommunityTopic.laptop,
      DeviceType.phone => CommunityTopic.phone,
      DeviceType.appliance => CommunityTopic.appliance,
      DeviceType.network => CommunityTopic.network,
      null => CommunityTopic.general,
    };
  }

  String _communityQuestionBody() {
    final List<String> details = <String>[
      'I need help with ${draft.deviceDetail ?? draft.deviceType?.label ?? 'my device'}.',
      'Symptom: ${draft.problemSymptom ?? 'Not sure yet'}.',
      if (draft.composedDescription case final String description) description,
    ];
    return details.join('\n\n');
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}

/// How long each step of posting may take before it is treated as a
/// connection problem (2026-11-23). Generous for a phone on mobile data, and
/// well past the analysis screen's "taking longer than usual" line at 12 s,
/// so a slow-but-working connection still gets there; a dead one gets
/// "Connection problem" and Retry instead of an endless wait.
@immutable
class PostingTimeLimits {
  const PostingTimeLimits({
    this.photos = const Duration(seconds: 45),
    this.save = const Duration(seconds: 20),
    this.matching = const Duration(seconds: 30),
  });

  /// Uploading the new photos, all together.
  final Duration photos;

  /// Saving the job (insert or edit), or posting the community question.
  final Duration save;

  /// Running the matcher, which waits on live weather and traffic.
  final Duration matching;
}
