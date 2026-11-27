import type { Firestore } from "firebase-admin/firestore";
import { bowlCountsTowardSeason, isBowlWeekId } from "./bowlWeek";

export const COUNTS_TOWARD_SEASON_AT_SCORE = "countsTowardSeasonStandingsAtScore";

type RulesLike = { bowlSeason?: { countsTowardSeasonStandings?: boolean } | null };

export function countsTowardSeasonAtScoreFromRules(rules: RulesLike): boolean {
  return bowlCountsTowardSeason(rules);
}

/** Prefer the week stamp once scored; live group rules cannot change scoring semantics. */
export function bowlWeekCountsTowardSeason(
  rules: RulesLike,
  week: { countsTowardSeasonStandingsAtScore?: boolean } | undefined
): boolean {
  const stamped = week?.countsTowardSeasonStandingsAtScore;
  if (typeof stamped === "boolean") return stamped;
  return bowlCountsTowardSeason(rules);
}

export async function stampedBowlStandingsValue(
  db: Firestore,
  groupId: string
): Promise<boolean | null> {
  const weeks = await db.collection("groups").doc(groupId).collection("weeks").get();
  for (const doc of weeks.docs) {
    if (!isBowlWeekId(doc.id)) continue;
    const data = doc.data();
    if (data.status !== "scored") continue;
    const stamp = data[COUNTS_TOWARD_SEASON_AT_SCORE];
    if (typeof stamp === "boolean") return stamp;
  }
  return null;
}

/** Backfill legacy scored bowl weeks so guard reverts target a stable stamp. */
export async function ensureScoredBowlStandingsStamps(
  db: Firestore,
  groupId: string,
  stampValue: boolean
): Promise<void> {
  const weeksRef = db.collection("groups").doc(groupId).collection("weeks");
  const weeks = await weeksRef.get();
  const batch = db.batch();
  let writes = 0;
  for (const doc of weeks.docs) {
    if (!isBowlWeekId(doc.id)) continue;
    const data = doc.data();
    if (data.status !== "scored") continue;
    if (typeof data[COUNTS_TOWARD_SEASON_AT_SCORE] === "boolean") continue;
    batch.update(doc.ref, { [COUNTS_TOWARD_SEASON_AT_SCORE]: stampValue });
    writes += 1;
  }
  if (writes > 0) await batch.commit();
}

export async function resolveLockedBowlStandingsStamp(
  db: Firestore,
  groupId: string,
  rulesBeforeFlip: unknown
): Promise<boolean | null> {
  const existing = await stampedBowlStandingsValue(db, groupId);
  if (existing !== null) return existing;
  const weeks = await db.collection("groups").doc(groupId).collection("weeks");
  const snap = await weeks.get();
  const hasScoredBowl = snap.docs.some(
    (d) => isBowlWeekId(d.id) && d.data().status === "scored"
  );
  if (!hasScoredBowl) return null;
  const fallback = countsTowardSeasonAtScoreFromRules(
    (rulesBeforeFlip as RulesLike | undefined) ?? {}
  );
  await ensureScoredBowlStandingsStamps(db, groupId, fallback);
  return fallback;
}