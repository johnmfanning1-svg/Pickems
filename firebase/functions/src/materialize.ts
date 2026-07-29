import * as admin from "firebase-admin";

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
const SCORING_OWNED_FIELDS = ["status", "homeScore", "awayScore", "winnerTeamId"] as const;

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
  options: { force?: boolean } = {}
): Promise<MaterializeResult> {
  const db = admin.firestore();
  const weekRef = db.collection("groups").doc(groupId).collection("weeks").doc(weekId);
  const noms = await weekRef.collection("nominations").get();
  const games = await weekRef.collection("games").get();

  if (!games.empty && options.force !== true) {
    return { created: 0, updated: 0, total: games.size, skipped: true };
  }

  const existingIds = new Set(games.docs.map((d) => d.id));
  let created = 0;
  let updated = 0;
  const batch = db.batch();

  for (const doc of noms.docs) {
    const n = doc.data();
    const espnEventId = n.espnEventId as string;
    if (!espnEventId) continue;

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
      spread: Math.abs(Number(n.spread ?? 0)),
      spreadTeamId: n.spreadTeamId ?? n.homeTeamId ?? "home",
      kickoff: n.kickoff,
      status: "scheduled",
      homeScore: null,
      awayScore: null,
      winnerTeamId: null,
    };

    const gameRef = weekRef.collection("games").doc(espnEventId);
    if (existingIds.has(espnEventId)) {
      for (const field of SCORING_OWNED_FIELDS) delete payload[field];
      batch.set(gameRef, payload, { merge: true });
      updated += 1;
    } else {
      batch.set(gameRef, payload);
      created += 1;
      existingIds.add(espnEventId);
    }
  }

  if (created > 0 || updated > 0) await batch.commit();
  return { created, updated, total: existingIds.size, skipped: false };
}
