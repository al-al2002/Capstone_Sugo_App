/**
 * Shared types for the matching engine.
 *
 * `ScoreBreakdown` here and `lib/features/rb_cars/models/score_breakdown.dart`
 * are two halves of one contract - the jsonb written into
 * `job_matches.score_breakdown`. Change one, change the other.
 */

export type DeviceType = "laptop" | "phone" | "appliance" | "network";
export type ServicePath = "home_service" | "pickup" | "it_community";
export type Urgency = "need_today" | "can_wait";
export type Tier = "standard" | "pro" | "elite";

/** Mirrors `technicians.verification_tier`. How much paperwork SUGO checked. */
export type VerificationTier = "basic" | "verified" | "certified_pro";

/** Mirrors `technician_specializations.skill_level`. */
export type SkillLevel = "beginner" | "intermediate" | "expert";

/** Mirrors `client_verification_status.trust_level`. */
export type TrustLevel = "new" | "verified" | "trusted";

/** One declared (device, brand) pair, as `matching_candidates` returns it. */
export interface SpecializationRow {
  device_type: string;
  brand: string;
  skill_level: SkillLevel | null;
  verified: boolean;
  track: string | null;
}

/** What the engine knows about the client who posted the job. */
export interface ClientTrust {
  trustLevel: TrustLevel;
  noShowCount: number;
  averageRating: number | null;
}

/** A row of `jobs`, as far as scoring cares. */
export interface JobRow {
  id: string;
  client_id: string;
  device_type: DeviceType;
  problem_symptom: string;
  has_physical_damage: boolean;
  classification_confidence: "high" | "low" | null;
  service_path: ServicePath | null;
  urgency: Urgency;
  latitude: number | null;
  longitude: number | null;
  budget_min: number | null;
  budget_max: number | null;
  preferred_schedule: string | null;
  description: string | null;
  photo_urls: string[] | null;
  status: string;
  assigned_technician_id: string | null;

  /**
   * Brand of the device, added in 20260907000010. Null or "Others" means the
   * client did not say, and Stage 1 falls back to device-only matching rather
   * than excluding everybody.
   */
  brand: string | null;

  /**
   * Precise device type from the specialisation vocabulary. Null on older
   * jobs, where `device_type` is mapped instead - see
   * `job_device_candidates()`.
   */
  device_detail: string | null;
}

/**
 * A candidate technician, as `matching_candidates` returns them.
 *
 * That view pre-joins the profile, the identity verdict and the declared
 * specialisations, so the engine still makes one query for the whole pool.
 */
export interface TechnicianRow {
  id: string;
  skill_tags: string[];
  tier: Tier;
  specialization: string[];
  is_verified: boolean;
  /**
   * The retired online/offline switch. Still selected by the view (the table
   * is frozen) but read by nothing: availability is `away_until` now.
   */
  is_available?: boolean;
  badge: string | null;
  rating: number | null;
  total_jobs: number | null;
  current_workload: number | null;

  /** Live position while working. May be null and may be stale. */
  latitude: number | null;
  longitude: number | null;

  /**
   * Where they actually work from, captured during registration. Distance and
   * the service-radius gate are measured from here, not from `latitude` -
   * which is a working position that is null for anyone not currently on a
   * job.
   */
  base_latitude: number | null;
  base_longitude: number | null;

  /** How far they said they will travel, in km. */
  service_radius_km: number | null;

  verification_tier: VerificationTier | null;

  /** True when an admin approved their ID + selfie. A hard gate in Stage 1. */
  identity_approved: boolean;

  /** Every (device, brand) pair they declared. */
  specializations: SpecializationRow[];

  created_at: string | null;

  /**
   * Last day of the time off covering today (`YYYY-MM-DD`), or null when they
   * are working. From `technician_away_until()` via `matching_candidates`.
   * Not a gate: a technician on vacation is still ranked and shown, scored
   * lowest on availability, and `job-response` refuses to let them be booked.
   */
  away_until?: string | null;

  full_name?: string | null;
  avatar_url?: string | null;
  phone?: string | null;

  /** Kept for the older embed shape, still read by `snapshot()` as a fallback. */
  profiles?: {
    full_name: string | null;
    avatar_url: string | null;
    phone: string | null;
  } | null;
}

/** What the feedback loop knows about one technician on one job type. */
export interface AccuracyStats {
  /** Outcomes on this exact device type + symptom. */
  similarRepairs: number;
  /** Outcomes on the same device type, any symptom. */
  sameDeviceRepairs: number;
  /** Smoothed 0..1 accuracy, already discounted for reroutes. */
  signal: number;
  /** Raw share of those jobs that were rerouted mid-job. */
  rerouteRate: number;
  /** Average client rating across the matching outcomes, or null. */
  averageRating: number | null;
}

/** Live traffic at the job site. */
export interface TrafficContext {
  available: boolean;
  currentSpeed: number | null;
  freeFlowSpeed: number | null;
  /** 0 = free flowing, 1 = stopped. */
  congestion: number | null;
  roadClosure: boolean;
  label: string | null;
}

/** Live weather at the job site. */
export interface WeatherContext {
  available: boolean;
  condition: string | null;
  description: string | null;
  tempC: number | null;
  /** 0 = clear, 1 = severe. */
  severity: number | null;
  label: string | null;
}

/**
 * A condition the matching rules can be written against.
 *
 * Each is a yes/no fact derived once per job from data the engine actually
 * has. A signal whose source is unavailable - TomTom down, no weather - is
 * simply absent, so any rule needing it does not fire and the base weights
 * stand. That is the fallback the brief asks for, with no special case.
 */
export type ContextSignal =
  | "urgent"
  | "rain"
  | "heavy_traffic"
  | "on_site"
  | "appliance"
  | "technology";

/** Which score a rule re-weights. */
export type RuleStage = "suitability" | "acceptance" | "recommendation";

/** Factor key -> multiplier on its base weight. */
export type WeightMultipliers = Record<string, number>;

/**
 * One matching rule: IF every signal in `when` holds, THEN multiply these
 * factor weights. Rules are data (see `rules.ts`), not branches in the scorer.
 */
export interface MatchingRule {
  id: string;
  /** Short, for the context chips and the demo view. */
  label: string;
  /** Why this rule exists - printed in the demo view, defended at the panel. */
  rationale: string;
  when: ContextSignal[];
  adjust: Partial<Record<RuleStage, WeightMultipliers>>;
}

/** A rule that fired for this job, with what it actually changed. */
export interface AppliedRule {
  id: string;
  label: string;
  rationale: string;
  when: ContextSignal[];
  effects: { stage: RuleStage; factor: string; multiplier: number }[];
}

/** The outcome of rule selection for one job, shared by every candidate. */
export interface RuleSelection {
  signals: ContextSignal[];
  applied: AppliedRule[];
  /** Composed and capped. A factor missing here keeps its base weight. */
  multipliers: Record<RuleStage, WeightMultipliers>;
}

/** This client's past jobs with one technician. */
export interface ClientTechnicianHistory {
  jobs: number;
  completed: number;
  /** Stars from their most recent review of this technician, if any. */
  stars: number | null;
}

/**
 * What this client's own history says, for Stage 3.
 *
 * `pastJobs` of 0 is the cold-start case: the client-preference factor is then
 * null and dropped, so nobody is ranked on preferences the client never showed.
 */
export interface ClientHistory {
  pastJobs: number;
  byTechnician: Map<string, ClientTechnicianHistory>;
}

/** How a technician has answered the offers they were sent. */
export interface TrackRecord {
  accepted: number;
  declined: number;
}

/** A client-facing reason, derived from a recorded number - never copywriting. */
export interface RecommendationReason {
  code: string;
  text: string;
  /** `positive` supports the recommendation; `caveat` is something to know. */
  kind: "positive" | "caveat";
}

/** Everything fetched once per job and reused for every candidate. */
export interface JobContext {
  traffic: TrafficContext;
  weather: WeatherContext;
  servicePath: ServicePath;
  travelExposure: number;

  /**
   * Who is asking. Feeds the Stage 2 client-trust factor: a technician is
   * measurably less willing to cross the city for a client with a no-show
   * history. Soft only - a new client must still be bookable.
   */
  clientTrust: ClientTrust;

  /**
   * Device types that can serve this job, from `job_device_candidates()`.
   * Bridges the coarse `jobs.device_type` vocabulary and the fine
   * specialisation one.
   */
  deviceCandidates: string[];

  /** The conditions that held and the rules they selected. */
  rules: RuleSelection;

  /** This client's past bookings, for the Stage 3 preference factor. */
  clientHistory: ClientHistory;
}

/** One weighted input to a stage score. */
export interface ScoreFactor {
  key: string;
  label: string;
  /** Normalised 0..1 for this factor alone. */
  value: number;
  /** Weight actually applied, after rules and any renormalisation. */
  weight: number;
  /**
   * The weight before any matching rule touched it (still renormalised over
   * the factors that were available). Present only when a rule changed it,
   * so the demo view can print "Distance 18% -> 27%".
   */
  base_weight?: number;
  /** `value * weight`. */
  contribution: number;
  note?: string;
}

export interface StageResult {
  score: number;
  factors: ScoreFactor[];
}

/**
 * One technician the engine scored, offered or not.
 *
 * `job_matches` can only hold three rows per job - `rank` is checked between 1
 * and 3 - so everyone past third place exists only here, in the function's
 * response. Nothing about this is persisted.
 */
export interface ConsideredCandidate {
  technician_id: string;
  full_name: string | null;
  avatar_url: string | null;
  /** Position in the full ranking, 1-based. Not the same as `job_matches.rank`. */
  rank: number;
  /** True for the first three: the ones actually written as offers. */
  offered: boolean;
  distance_km: number | null;
  eta_minutes: number | null;
  /** False while they are on vacation. Shown, never filtered on. */
  available: boolean;
  suitability: number;
  acceptance: number;
  /** Stage 3. The same number as `final_score`, named for what it is. */
  recommendation: number;
  final_score: number;
  explainability: string[];
}

/** Stage 3 as stored: its own factors plus the rules and reasons behind it. */
export interface RecommendationBlock extends StageResult {
  signals: ContextSignal[];
  rules: AppliedRule[];
  reasons: RecommendationReason[];
}

/**
 * The jsonb document written to `job_matches.score_breakdown`.
 *
 * Version 2 (2026-09-27) added `recommendation`. Everything version 1 had is
 * still written, unchanged in meaning, so installed app builds keep working;
 * `final_score` is now the recommendation score.
 */
export interface ScoreBreakdown {
  version: number;
  stage1: StageResult;
  stage2: StageResult;
  recommendation: RecommendationBlock;
  final_score: number;
  context: Record<string, unknown>;
  explainability: string[];
  technician: TechnicianSnapshot;
  job: JobSnapshot;
}

/**
 * Job details copied into the breakdown so the *technician* can read them.
 *
 * `jobs_technician_select_assigned` only lets a technician read a job they are
 * already assigned to. Before they accept, they are not assigned - so without
 * this snapshot an incoming offer would show a score and nothing to judge it
 * by. They can read their own `job_matches` row, so the details ride along in
 * the jsonb.
 *
 * Deliberately withheld: `client_id`, `latitude` and `longitude`. A technician
 * who has merely been *offered* a job has not earned the client's identity or
 * their doorstep. Distance is already in `context.distance_km`, which is what
 * they actually need to decide, and the exact address becomes available
 * through `jobs` the moment they accept and are assigned.
 */
export interface JobSnapshot {
  id: string;
  device_type: DeviceType;
  brand: string | null;
  device_detail: string | null;
  problem_symptom: string;
  has_physical_damage: boolean;
  classification_confidence: "high" | "low" | null;
  service_path: ServicePath;
  urgency: Urgency;
  budget_min: number | null;
  budget_max: number | null;
  preferred_schedule: string | null;
  description: string | null;
  photo_urls: string[];
}

/**
 * Technician details copied into the breakdown at match time.
 *
 * RLS on `technicians` is `id = auth.uid()`, so a client cannot read another
 * person's technician row. Embedding a snapshot in the jsonb - which the
 * client *can* read through its own `job_matches` row - is what lets the review
 * screen show a name, photo and rating without weakening the policy.
 */
export interface TechnicianSnapshot {
  id: string;
  full_name: string | null;
  avatar_url: string | null;
  tier: Tier;
  badge: string | null;
  is_verified: boolean;

  /**
   * True unless they are on vacation. The name is from the retired online
   * switch, kept because installed app builds still read it.
   */
  is_available: boolean;

  rating: number;
  total_jobs: number;
  current_workload: number;
  specialization: string[];
  skill_tags: string[];
  member_since: string | null;
  latitude: number | null;
  longitude: number | null;

  /** basic | verified | certified_pro - what SUGO actually checked. */
  verification_tier: VerificationTier;

  /** The declared brands relevant to this job, for the review screen. */
  matched_specializations: string[];

  /**
   * Last day of their current time off, or null. The card shows
   * "On vacation until ..." and disables booking. A snapshot, so it can go
   * stale if a vacation starts after matching ran - which is why the booking
   * gate in `job-response` re-checks it live rather than trusting this.
   */
  away_until: string | null;
}

/** A fully scored candidate, before ranking. */
export interface ScoredCandidate {
  technician: TechnicianRow;
  suitability: StageResult;
  acceptance: StageResult;
  recommendation: RecommendationBlock;
  /** The recommendation score. What the ranking sorts on. */
  finalScore: number;
  distanceKm: number | null;
  accuracy: AccuracyStats;
  breakdown: ScoreBreakdown;
}
