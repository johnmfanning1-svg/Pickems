/** Merge ESPN postseason catalog into a Mode B week — late CFP games included. */

import { Timestamp, type DocumentReference } from "firebase-admin/firestore";
import type { EspnEvent } from "./espn";
import { liveSpreadFromEvent, resolveSpreadTeamId } from "./espn";
import {
  BOWL_CATALOG_SLATE_SOURCE,
  isBowlFullSlateWeek,
} from "./bowlWeek";
import { kickoffMillis, lockSnapshotFromGames } from "./pickLock";
import { kickoffsMillisByEspnEventId } from "./selectionCatalog";
import { gameEffectivelyLocked } from "./spreadLock";

function slatePayloadFromEspn(event: EspnEvent): Record<string, unknown> | null {
  const competition = event.competitions?.[0];
  const competitors = competition?.competitors ?? [];
  if (competitors.length < 2) return null;
  const home = competitors.find((c) => c.homeAway === "home");
  const away = competitors.find((c) => c.homeAway === "away");
  if (!home?.team?.id || !away?.team?.id) return null;
  if (!event.date) return null;
  const kickoffMs = Date.parse(event.date);
  if (!Number.isFinite(kickoffMs)) return null;

  const odds = competition?.odds?.[0];
  const spread =
    typeof odds?.spread === "number" && Number.isFinite(odds.spread) ? Math.abs(odds.spread) : 0;
  const spreadTeamId = resolveSpreadTeamId({
    homeTeamId: home.team.id,
    awayTeamId: away.team.id,
    spread: odds?.spread,
    homeFavorite: odds?.homeTeamOdds?.favorite,
    awayFavorite: odds?.awayTeamOdds?.favorite,
  });
  const live = liveSpreadFromEvent(event, home.team.id, away.team.id);

  return {
    id: event.id,
    espnEventId: event.id,
    homeTeamId: home.team.id,
    homeTeamName: home.team.displayName,
    homeTeamAbbreviation: home.team.abbreviation,
    homeTeamLogoURL: home.team.logo ?? null,
    awayTeamId: away.team.id,
    awayTeamName: away.team.displayName,
    awayTeamAbbreviation: away.team.abbreviation,
    awayTeamLogoURL: away.team.logo ?? null,
    spread,
    spreadTeamId,
    liveSpread: live?.liveSpread ?? null,
    liveSpreadTeamId: live?.liveSpreadTeamId ?? null,
    kickoff: Timestamp.fromMillis(kickoffMs),
    status: "scheduled",
    homeScore: null,
    awayScore: null,
    winnerTeamId: null,
  };
}

/**
 * Full-catalog kickoffs + `liveIds` for Mode B rolling locks.
 * Written by `syncBowlCatalogSlate` and `publishSelectionKickoffCatalog` (lockAndScoreWeeks).
 */
export async function publishBowlGameLockMirror(
  weekRef: DocumentReference,
  catalogEvents: EspnEvent[]
): Promise<void> {
  const millisById = kickoffsMillisByEspnEventId(catalogEvents);
  const ids = Object.keys(millisById);
  if (ids.length === 0) return;
  const kickoffs: Record<string, Timestamp> = {};
  const phases: Record<string, string> = {};
  for (const id of ids) {
    kickoffs[id] = Timestamp.fromMillis(millisById[id]);
    phases[id] = "pre";
  }
  await weekRef.collection("gameLock").doc("current").set(
    { kickoffs, phases, liveIds: [], updatedAt: Timestamp.now() },
    { merge: true }
  );
}

export type BowlCatalogSyncResult = { created: number; updated: number; slateSize: number };

/** Idempotently add catalog events (incl. newly scheduled CFP) to the week slate. */
export async function syncBowlCatalogSlate(
  weekRef: DocumentReference,
  weekId: string,
  weekData: Record<string, unknown>,
  catalogEvents: EspnEvent[]
): Promise<BowlCatalogSyncResult | null> {
  if (!isBowlFullSlateWeek(weekData, weekId)) return null;
  const now = Date.now();
  const gamesRef = weekRef.collection("games");
  const existing = await gamesRef.get();
  const existingById = new Map(existing.docs.map((doc) => [doc.id, doc]));
  const batch = weekRef.firestore.batch();
  let created = 0;
  let updated = 0;

  for (const event of catalogEvents) {
    const payload = slatePayloadFromEspn(event);
    if (!payload) continue;
    const id = event.id;
    const gameRef = gamesRef.doc(id);
    const stored = existingById.get(id);
    if (!stored) {
      batch.set(gameRef, payload);
      created += 1;
    } else {
      const data = stored.data();
      const patch: Record<string, unknown> = {};
      const newKickoffMs = kickoffMillis(payload.kickoff);
      const oldKickoffMs = kickoffMillis(data.kickoff);
      const openForKickoffUpdate = !gameEffectivelyLocked(weekData, {
        id,
        kickoff: data.kickoff,
        status: data.status,
      }, now);
      if (
        openForKickoffUpdate &&
        newKickoffMs != null &&
        oldKickoffMs != null &&
        newKickoffMs !== oldKickoffMs
      ) {
        patch.kickoff = payload.kickoff;
      } else if (openForKickoffUpdate && oldKickoffMs == null && newKickoffMs != null) {
        patch.kickoff = payload.kickoff;
      }
      if (data.status !== "final" && data.status !== "inProgress") {
        if (typeof payload.liveSpread === "number") {
          patch.liveSpread = payload.liveSpread;
          patch.liveSpreadTeamId = payload.liveSpreadTeamId;
        }
      }
      if (Object.keys(patch).length > 0) {
        batch.update(gameRef, patch);
        updated += 1;
      }
    }
  }

  if (created + updated > 0) {
    await batch.commit();
  }

  await publishBowlGameLockMirror(weekRef, catalogEvents);

  const allGames = await gamesRef.get();
  const slateSize = allGames.size;
  const lockGames = allGames.docs.map((doc) => ({
    id: doc.id,
    kickoff: doc.data().kickoff,
  }));

  const weekPatch: Record<string, unknown> = {
    slateSize,
    slateSource: BOWL_CATALOG_SLATE_SOURCE,
    bowlFullSlate: true,
    ...lockSnapshotFromGames(lockGames, "rolling", { bowlFullSlate: true }),
  };

  if (weekData.status === "selection") {
    const first = lockGames
      .map((g) => kickoffMillis(g.kickoff))
      .filter((ms): ms is number => ms != null);
    const future = first.filter((ms) => ms > Date.now());
    if (future.length > 0) {
      weekPatch.status = "picking";
    }
  }

  await weekRef.set(weekPatch, { merge: true });

  return { created, updated, slateSize };
}