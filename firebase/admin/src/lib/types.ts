import type { Timestamp } from "firebase/firestore";

/**
 * Firestore document shapes, mirroring the iOS `Codable` models so the portal
 * writes exactly the fields the app decodes.
 *
 * Source of truth: `Pickems/Core/Models/DomainModels.swift` and
 * `Pickems/Core/Models/GroupRules.swift`. A field renamed there must be renamed
 * here, or the app silently fails to decode the doc the portal repaired.
 */

export type WeekStatus = "selection" | "picking" | "locked" | "scored";
export const WEEK_STATUSES: WeekStatus[] = ["selection", "picking", "locked", "scored"];

export type GameStatus = "scheduled" | "inProgress" | "final";
export type SelectionMode = "commissioner" | "member";
export type DeadlinePolicy = "firstKickoff" | "custom";
export type TieBreakerPolicy = "commissionerOverride" | "headToHead";
export type MemberRole = "commissioner" | "member";

export interface GroupRules {
  selectionMode: SelectionMode;
  selectionsPerMember: number;
  slateSize: number;
  pickDeadline: DeadlinePolicy;
  tieBreaker: TieBreakerPolicy;
  customDeadlineHour: number;
  customDeadlineMinute: number;
  allowConfidencePick: boolean;
  allowLatePicks: boolean;
  latePickPenaltyWins: number;
}

export const DEFAULT_GROUP_RULES: GroupRules = {
  selectionMode: "member",
  selectionsPerMember: 3,
  slateSize: 12,
  pickDeadline: "firstKickoff",
  tieBreaker: "commissionerOverride",
  customDeadlineHour: 18,
  customDeadlineMinute: 0,
  allowConfidencePick: false,
  allowLatePicks: false,
  latePickPenaltyWins: 1,
};

export interface GroupDoc {
  id: string;
  name: string;
  inviteCode: string;
  commissionerId: string;
  memberIds: string[];
  rules?: Partial<GroupRules>;
  createdAt?: Timestamp | null;
  isPublic?: boolean;
}

export interface MemberDoc {
  id: string;
  displayName: string;
  avatarColorHex?: string;
  role?: MemberRole;
  joinedAt?: Timestamp | null;
  seasonWins?: number;
  seasonLosses?: number;
}

export interface WeekAwards {
  sharpshooterUserId?: string | null;
  heartbreakerUserId?: string | null;
  contrarianUserId?: string | null;
}

export interface WeekDoc {
  id: string;
  seasonYear?: number;
  weekNumber?: number;
  status?: WeekStatus;
  slateSize?: number;
  selectionMode?: SelectionMode;
  selectionsPerMember?: number;
  lockedAt?: Timestamp | null;
  pickDeadline?: Timestamp | null;
  nominationCount?: number;
  awards?: WeekAwards | null;
  deadlineReminderSent?: boolean;
  scoredAt?: Timestamp | null;
}

export interface SlateGameDoc {
  id: string;
  espnEventId: string;
  homeTeamId: string;
  homeTeamName: string;
  homeTeamAbbreviation: string;
  homeTeamLogoURL?: string | null;
  awayTeamId: string;
  awayTeamName: string;
  awayTeamAbbreviation: string;
  awayTeamLogoURL?: string | null;
  spread: number;
  spreadTeamId: string;
  kickoff?: Timestamp | null;
  status?: GameStatus;
  homeScore?: number | null;
  awayScore?: number | null;
  winnerTeamId?: string | null;
}

export interface NominationDoc {
  id: string;
  submittedBy: string;
  submitterName: string;
  espnEventId: string;
  spread: number;
  spreadTeamId: string;
  homeTeamName: string;
  awayTeamName: string;
  homeTeamAbbreviation?: string | null;
  awayTeamAbbreviation?: string | null;
  kickoff?: Timestamp | null;
  createdAt?: Timestamp | null;
}

export interface PickDoc {
  id: string;
  userId: string;
  displayName: string;
  picks: Record<string, string>;
  submittedAt?: Timestamp | null;
  isLocked?: boolean;
  confidenceGameId?: string | null;
}

export interface SubmissionDoc {
  id: string;
  userId: string;
  displayName: string;
  isLocked?: boolean;
  submittedAt?: Timestamp | null;
}

/** One row of an archived season's final standings. Mirrors iOS `SeasonStandingEntry`. */
export interface SeasonStandingEntry {
  id: string;
  displayName: string;
  avatarColorHex: string;
  seasonWins: number;
  seasonLosses: number;
  rank: number;
}

/** `groups/{id}/seasons/{year}` — a closed season. Mirrors iOS `SeasonArchive`. */
export interface SeasonArchiveDoc {
  id: string;
  seasonYear: number;
  groupId: string;
  championUserId?: string | null;
  championDisplayName?: string | null;
  finalStandings: SeasonStandingEntry[];
  weekCount: number;
  closedAt?: Timestamp | null;
}

/**
 * `groups/{id}/career/{userId}` — cumulative dynasty record. `titles` is the
 * "crown" count shown in the app. Mirrors iOS `CareerRecord`.
 */
export interface CareerRecordDoc {
  id: string;
  displayName: string;
  avatarColorHex?: string;
  titles?: number;
  seasonWins?: number;
  seasonLosses?: number;
  seasonsPlayed?: number;
  bestFinish?: number | null;
  updatedAt?: Timestamp | null;
}

export interface UserDoc {
  id: string;
  displayName?: string;
  firstName?: string | null;
  lastName?: string | null;
  avatarColorHex?: string;
  favoriteTeamName?: string | null;
  createdAt?: Timestamp | null;
}

export interface AuditEntryDoc {
  id: string;
  actorUid?: string;
  actorEmail?: string | null;
  action?: string;
  targetPath?: string;
  before?: unknown;
  after?: unknown;
  createdAt?: Timestamp | null;
}

export interface ChatMessageDoc {
  id: string;
  groupId?: string;
  weekId?: string | null;
  userId?: string;
  displayName?: string;
  avatarColorHex?: string;
  text?: string;
  createdAt?: Timestamp | null;
  editedAt?: Timestamp | null;
  isDeleted?: boolean;
  reportCount?: number;
}

export interface MessageReportDoc {
  id: string;
  reporterUid?: string;
  reason?: string | null;
  createdAt?: Timestamp | null;
}

/**
 * `appConfig/live` — remote flags read by every signed-in client at launch.
 * Typed fields get real inputs; anything else is editable as raw JSON so the
 * portal never becomes the reason a new flag can't ship.
 */
export interface AppConfigDoc {
  chatEnabled?: boolean;
  top25FilterEnabled?: boolean;
  minimumBuild?: number;
  announcementTitle?: string;
  announcementBody?: string;
  maintenanceMessage?: string;
  updatedAt?: Timestamp | null;
  [key: string]: unknown;
}

/** Row shape returned by the `adminAuditWeekIds` callable. */
export interface WeekAuditRow {
  groupId: string;
  groupName: string | null;
  weekId: string;
  expectedWeekId: string | null;
  seasonYear: number | null;
  weekNumber: number | null;
  status: string | null;
  nominationCount: number;
  gameCount: number;
  pickCount: number;
  issues: string[];
}
