import type { DocumentReference, Firestore } from "firebase-admin/firestore";
import { isBowlWeekId } from "./bowlWeek";

type BowlRules = { bowlSeason?: { countsTowardSeasonStandings?: boolean } | null };

function countsTowardSeasonFlag(rules: unknown): boolean | undefined {
  const bowl = (rules as BowlRules | undefined)?.bowlSeason;
  return bowl?.countsTowardSeasonStandings;
}

/** Revert a commissioner flip of `countsTowardSeasonStandings` once any bowl week is scored. */
export async function revertBowlStandingsToggleIfLocked(
  db: Firestore,
  groupId: string,
  before: Record<string, unknown>,
  after: Record<string, unknown>,
  groupRef: DocumentReference
): Promise<boolean> {
  const beforeFlag = countsTowardSeasonFlag(before.rules);
  const afterFlag = countsTowardSeasonFlag(after.rules);
  if (beforeFlag === afterFlag) return false;
  const weeks = await db.collection("groups").doc(groupId).collection("weeks").get();
  const locked = weeks.docs.some((d) => isBowlWeekId(d.id) && d.data().status === "scored");
  if (!locked) return false;
  await groupRef.update({
    "rules.bowlSeason.countsTowardSeasonStandings": beforeFlag === true,
  });
  return true;
}