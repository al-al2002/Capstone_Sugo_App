import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import '../models/device_category.dart';
import '../models/job.dart';
import '../models/match_result.dart';
import '../models/issue_catalog.dart';
import '../models/job_enums.dart';
import '../models/schedule_preference.dart';
import '../services/rb_cars_service.dart';

/// Drives the three-screen job posting flow.
///
/// Held by the flow, not by the app: created when the client starts posting and
/// disposed when they leave, so a half-finished draft never leaks into the next
/// booking. The screens read [draft] and call the mutators; nothing writes to
/// the draft directly.
class JobPostingProvider extends ChangeNotifier {
  JobPostingProvider({RbCarsService? service, this.preselectedTechnicianId})
    : _service = service ?? RbCarsService(),
      editingJob = null;

  /// "Edit post": the same five steps, opened on an existing job with every
  /// answer already filled in. Saving updates that job instead of posting a
  /// new one, and matching runs again for the changed details.
  JobPostingProvider.editing(Job job, {RbCarsService? service})
    : _service = service ?? RbCarsService(),
      preselectedTechnicianId = null,
      editingJob = job {
    _prefill(job);
  }

  final RbCarsService _service;

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
  int _photosFailed = 0;

  bool get isSubmitting => _isSubmitting;

  /// True once the current [submit] has saved the job and moved on to the
  /// matcher. The matching screen's first tick waits for this.
  bool get requestSaved => _requestSaved;
  String? get error => _error;
  Job? get postedJob => _postedJob;

  /// The engine's explanation when the first matching run found nobody.
  ///
  /// Null when it found someone, or when nothing has run yet.
  String? _matchingNotice;
  String? get matchingNotice => _matchingNotice;

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
    _error = null;
    notifyListeners();
  }

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

  /// The "Flexible / This week / Urgent" control, which writes both
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

  /// Step 2 - a symptom is chosen, so the rule base has something to run on.
  bool get canLeaveSymptom =>
      draft.problemSymptom != null && draft.servicePath != null;

  /// Step 3 - nothing is required. Brand, model and description are all
  /// optional: the matcher degrades to device-category matching without them,
  /// and blocking the flow on a model number nobody can find is worse than a
  /// slightly weaker match.
  bool get canLeaveDeviceDetails => true;

  /// Step 4 - the map has a pin. Proximity, traffic and weather all key off it,
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
    notifyListeners();

    try {
      final List<String> uploaded = _photos.isEmpty
          ? const <String>[]
          : await _service.uploadPhotos(_photos);
      _photosFailed = _photos.length - uploaded.length;
      draft.photoUrls = <String>[..._keptPhotoUrls, ...uploaded];

      final Job? existing = _postedJob ?? editingJob;
      final Job job = existing == null
          ? await _service.postJob(draft)
          : await _service.updateJob(existing.id, draft);
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

      // Matching runs immediately: the client should land on the review screen
      // with a Top 3 already waiting, not on an empty list.
      final MatchingRun run = await _service.runMatching(job.id);

      // When it found nobody, the engine says which gate emptied the pool -
      // "1 was outside their own service radius" rather than a shrug. Kept
      // here because the review screen reads `job_matches` from the database
      // on arrival, and a reason that exists only in this response would
      // otherwise be thrown away at the one moment it is most useful.
      _matchingNotice = run.matches.isEmpty ? run.message : null;

      return job;
    } on RbCarsFailure catch (failure) {
      _error = failure.message;
      return null;
    } catch (error) {
      _error = 'Could not post this job. Please try again.';
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
