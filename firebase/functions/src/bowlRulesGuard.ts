import type { DocumentReference, Firestore } from "firebase-admin/firestore";
import { resolveLockedBowlStandingsStamp } from "./bowlStandingsStamp";

type BowlRules = { bowlSeason?: { countsTowardSeasonStandings?: boolean } | null };

function countsTowardSeasonFlag(rules: unknown): boolean | undefined {
  const bowl = (rules as BowlRules | undefined)?.bowlSeason;
  return bowl?.countsTowardSeasonStandings;
}

/**
 * Revert a commissioner flip of `countsTowardSeasonStandings` once any bowl week is scored.
 * No-op when the doc already matches the stamped value (including after our own revert write).
 */
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

  const stamped = await resolveLockedBowlStandingsStamp(db, groupId, before.rules);
  if (stamped === null) return false;
  if (afterFlag === stamped) return false;

  await groupRef.update({
    "rules.bowlSeason.countsTowardSeasonStandings": stamped,
  });
  return true;
}