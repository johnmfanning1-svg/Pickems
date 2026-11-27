/** Merge ESPN postseason catalog into a Mode B week — late CFP games included. */

import { FieldValue, Timestamp, type DocumentReference } from "firebase-admin/firestore";
import type { EspnEvent } from "./espn";
import { liveSpreadFromEvent, parseEventScores, resolveSpreadTeamId } from "./espn";
import {
  BOWL_CATALOG_SLATE_SOURCE,
  isBowlFullSlateWeek,
} from "./bowlWeek";
import { kickoffMillis, lockSnapshotFromGames } from "./pickLock";

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

export type BowlCatalogSyncResult = { created: number; updated: number; slateSize: number };

/** Idempotently add catalog events (incl. newly scheduled CFP) to the week slate. */
export async function syncBowlCatalogSlate(
  weekRef: DocumentReference,
  weekData: Record<string, unknown>,
  catalogEvents: EspnEvent[]
): Promise<BowlCatalogSyncResult | null> {
  if (!isBowlFullSlateWeek(weekData)) return null;
  const gamesRef = weekRef.collection("games");
  const existing = await gamesRef.get();
  const existingById = new Map(existing.docs.map((doc) => [doc.id, doc]));
  const batch = weekRef.firestore.batch();
  let created = 0;
  let updated = 0;

  const kickoffs: Array<{ id: string; kickoff: unknown }> = [];

  for (const event of catalogEvents) {
    const payload = slatePayloadFromEspn(event);
    if (!payload) continue;
    const id = event.id;
    kickoffs.push({ id, kickoff: payload.kickoff });
    const gameRef = gamesRef.doc(id);
    const stored = existingById.get(id);
    if (!stored) {
      batch.set(gameRef, payload);
      created += 1;
    } else {
      const data = stored.data();
      const parsed = parseEventScores(event);
      const patch: Record<string, unknown> = {};
      if (typeof data.kickoff === "undefined" || data.kickoff == null) {
        patch.kickoff = payload.kickoff;
      }
      if (parsed) {
        if (data.homeScore !== parsed.homeScore) patch.homeScore = parsed.homeScore;
        if (data.awayScore !== parsed.awayScore) patch.awayScore = parsed.awayScore;
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