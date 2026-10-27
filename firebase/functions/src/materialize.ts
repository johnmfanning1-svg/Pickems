import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { gameEffectivelyLocked, hasLockedSpread, type WeekLockInput } from "./spreadLock";

/** Line captured before a started game is rewritten or recreated. */
export interface PreservedGameLine {
  kickoff?: unknown;
  status?: unknown;
  spread?: unknown;
  spreadTeamId?: unknown;
  lockedSpread?: unknown;
  lockedSpreadTeamId?: unknown;
}

export interface MaterializedLine {
  spread: number;
  spreadTeamId: string;
  lockedSpread?: number;
  lockedSpreadTeamId?: string;
  /** Open games drop any graded copy. Started games never do. */
  clearLockedSpread: boolean;
}

function finiteSpread(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? Math.abs(value) : undefined;
}

function teamId(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

/**
 * Graded line for one game while nominations are copied onto the slate.
 * A started game keeps the line already stored on it. The nomination spread
 * is only the first snapshot when that game has no stored line yet.
 */
export function lineForMaterializedGame(input: {
  started: boolean;
  nominationSpread: number;
  nominationSpreadTeamId: string;
  existing?: PreservedGameLine;
}): MaterializedLine {
  const nominationSpread = finiteSpread(input.nominationSpread) ?? 0;
  const nominationSpreadTeamId = teamId(input.nominationSpreadTeamId) ?? "home";
  if (!input.started) {
    return {
      spread: nominationSpread,
      spreadTeamId: nominationSpreadTeamId,
      clearLockedSpread: true,
    };
  }
  const existing = input.existing;
  if (existing && hasLockedSpread(existing)) {
    const lockedSpread = existing.lockedSpread as number;
    const lockedSpreadTeamId = existing.lockedSpreadTeamId as string;
    return {
      spread: finiteSpread(existing.spread) ?? Math.abs(lockedSpread),
      spreadTeamId: teamId(existing.spreadTeamId) ?? lockedSpreadTeamId,
      lockedSpread,
      lockedSpreadTeamId,
      clearLockedSpread: false,
    };
  }
  if (existing && finiteSpread(existing.spread) != null) {
    const spread = finiteSpread(existing.spread) as number;
    const spreadTeamId = teamId(existing.spreadTeamId) ?? nominationSpreadTeamId;
    return {
      spread,
      spreadTeamId,
      lockedSpread: spread,
      lockedSpreadTeamId: spreadTeamId,
      clearLockedSpread: false,
    };
  }
  return {
    spread: nominationSpread,
    spreadTeamId: nominationSpreadTeamId,
    lockedSpread: nominationSpread,
    lockedSpreadTeamId: nominationSpreadTeamId,
    clearLockedSpread: false,
  };
}

/** Started games whose line must survive a later materialize, keyed by game id. */
export function preservedLinesForStartedGames(
  week: WeekLockInput,
  games: Array<{ id: string; data: PreservedGameLine }>,
  now: number
): Map<string, PreservedGameLine> {
  const preserved = new Map<string, PreservedGameLine>();
  for (const game of games) {
    if (
      !gameEffectivelyLocked(
        week,
        { id: game.id, kickoff: game.data.kickoff, status: game.data.status },
        now
      )
    ) {
      continue;
    }
    preserved.set(game.id, game.data);
  }
  return preserved;
}

export interface MaterializeResult {
  /** Game docs written for the first time. */
  created: number;
  /** Existing game docs refreshed from their nomination (scores preserved). */
  updated: number;
  /** Total game docs on the week after the pass. */
  total: number;
  /** True when the week already had games and `force` was not set. */
  skipped: boolean;
}

/** Fields owned by the scoring pass — never clobbered when refreshing a game. */
const SCORING_OWNED_FIELDS = [
  "status",
  "homeScore",
  "awayScore",
  "winnerTeamId",
  "lockedSpread",
  "lockedSpreadTeamId",
  "liveSpread",
  "liveSpreadTeamId",
] as const;

/**
 * Copy a week's nominations into its `games` subcollection, keyed by
 * `espnEventId` so duplicate nominations collapse instead of double-writing.
 *
 * Without `force` this is a no-op once the week has any games — the original
 * trigger behaviour. `force` (admin repair path) re-derives every game from its
 * nomination while leaving live scores and status untouched.
 */
export async function materializeNominations(
  groupId: string,
  weekId: string,
  options: { force?: boolean; preservedLines?: ReadonlyMap<string, PreservedGameLine> } = {}
): Promise<MaterializeResult> {
  const db = getFirestore();
  const weekRef = db.collection("groups").doc(groupId).collection("weeks").doc(weekId);
  const noms = await weekRef.collection("nominations").get();
  const games = await weekRef.collection("games").get();

  if (!games.empty && options.force !== true) {
    return { created: 0, updated: 0, total: games.size, skipped: true };
  }

  const week = (await weekRef.get()).data() ?? {};
  const now = Date.now();
  const existingById = new Map(games.docs.map((d) => [d.id, d.data()]));
  const existingIds = new Set(existingById.keys());
  let created = 0;
  let updated = 0;
  const batch = db.batch();

  for (const doc of noms.docs) {
    const n = doc.data();
    const espnEventId = n.espnEventId as string;
    if (!espnEventId) continue;

    const nominationSpread = Math.abs(Number(n.spread ?? 0));
    const nominationSpreadTeamId = (n.spreadTeamId ?? n.homeTeamId ?? "home") as string;
    const gameRef = weekRef.collection("games").doc(espnEventId);
    const stored = existingById.get(espnEventId);
    const prior = stored ?? options.preservedLines?.get(espnEventId);
    const locked = gameEffectivelyLocked(
      week,
      {
        id: espnEventId,
        kickoff: prior?.kickoff ?? n.kickoff,
        status: prior?.status ?? "scheduled",
      },
      now
    );
    const line = lineForMaterializedGame({
      started: locked,
      nominationSpread,
      nominationSpreadTeamId,
      existing: prior,
    });
    const payload: Record<string, unknown> = {
      id: espnEventId,
      espnEventId,
      homeTeamId: n.homeTeamId ?? "home",
      homeTeamName: n.homeTeamName ?? "Home",
      homeTeamAbbreviation: n.homeTeamAbbreviation ?? "HOME",
      homeTeamLogoURL: n.homeTeamLogoURL ?? null,
      awayTeamId: n.awayTeamId ?? "away",
      awayTeamName: n.awayTeamName ?? "Away",
      awayTeamAbbreviation: n.awayTeamAbbreviation ?? "AWAY",
      awayTeamLogoURL: n.awayTeamLogoURL ?? null,
      spread: line.spread,
      spreadTeamId: line.spreadTeamId,
      kickoff: n.kickoff,
      status: "scheduled",
      homeScore: null,
      awayScore: null,
      winnerTeamId: null,
    };
    if (!line.clearLockedSpread && line.lockedSpread != null && line.lockedSpreadTeamId) {
      payload.lockedSpread = line.lockedSpread;
      payload.lockedSpreadTeamId = line.lockedSpreadTeamId;
    }

    if (stored) {
      for (const field of SCORING_OWNED_FIELDS) delete payload[field];
      if (locked) delete payload.kickoff;
      if (line.clearLockedSpread) {
        payload.lockedSpread = FieldValue.delete();
        payload.lockedSpreadTeamId = FieldValue.delete();
      } else if (hasLockedSpread(stored)) {
        // Already graded. Leave lockedSpread, and the spread it was taken from.
        delete payload.spread;
        delete payload.spreadTeamId;
      } else if (line.lockedSpread != null && line.lockedSpreadTeamId) {
        payload.lockedSpread = line.lockedSpread;
        payload.lockedSpreadTeamId = line.lockedSpreadTeamId;
        delete payload.spread;
        delete payload.spreadTeamId;
      }
      batch.set(gameRef, payload, { merge: true });
      updated += 1;
    } else {
      // A deleted started game comes back with the line from `preservedLines`,
      // not the nomination that may have been edited after kickoff.
      if (prior?.kickoff != null) payload.kickoff = prior.kickoff;
      batch.set(gameRef, payload);
      created += 1;
      existingIds.add(espnEventId);
    }
  }

  if (created > 0 || updated > 0) await batch.commit();
  return { created, updated, total: existingIds.size, skipped: false };
}
