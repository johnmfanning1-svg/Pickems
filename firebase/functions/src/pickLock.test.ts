import { describe, it, expect } from "vitest";
import { Timestamp } from "firebase-admin/firestore";
import {
  resolvedPickLockMode,
  isRollingLock,
  lockSnapshotFromGames,
  effectiveWeekLockMillis,
  gameIsLocked,
  lastKickoffMillis,
  revealedPicksForGame,
} from "./pickLock";

describe("pickLock helpers", () => {
  it("treats missing and custom as firstKickoff", () => {
    expect(resolvedPickLockMode(undefined)).toBe("firstKickoff");
    expect(resolvedPickLockMode("custom")).toBe("firstKickoff");
    expect(resolvedPickLockMode("rolling")).toBe("rolling");
    expect(isRollingLock("rolling")).toBe(true);
    expect(isRollingLock("firstKickoff")).toBe(false);
  });

  it("snapshots first kickoff as both deadlines in firstKickoff mode", () => {
    const first = new Date("2026-09-05T19:00:00Z");
    const last = new Date("2026-09-07T19:00:00Z");
    const snap = lockSnapshotFromGames(
      [
        { id: "thu", kickoff: first },
        { id: "sun", kickoff: last },
      ],
      "firstKickoff"
    );
    expect(snap.pickLockMode).toBe("firstKickoff");
    expect((snap.pickDeadline as Timestamp).toMillis()).toBe(first.getTime());
    expect((snap.weekLockAt as Timestamp).toMillis()).toBe(first.getTime());
    expect(snap.gameIds).toEqual(["thu", "sun"]);
  });

  it("snapshots last kickoff as weekLockAt in rolling mode", () => {
    const first = new Date("2026-09-05T19:00:00Z");
    const last = new Date("2026-09-07T19:00:00Z");
    const snap = lockSnapshotFromGames(
      [
        { id: "thu", kickoff: first },
        { id: "sun", kickoff: last },
      ],
      "rolling"
    );
    expect(snap.pickLockMode).toBe("rolling");
    expect((snap.pickDeadline as Timestamp).toMillis()).toBe(first.getTime());
    expect((snap.weekLockAt as Timestamp).toMillis()).toBe(last.getTime());
  });

  it("uses remainingLockAt to pull the week lock forward", () => {
    expect(
      effectiveWeekLockMillis({
        pickLockMode: "rolling",
        weekLockAt: 2_000,
        remainingLockAt: 1_500,
      })
    ).toBe(1_500);
  });

  it("locks rolling games at kickoff and firstKickoff games at pickDeadline", () => {
    const week = {
      pickLockMode: "rolling",
      gameKickoffs: { thu: 1_000, sun: 3_000 },
    };
    expect(gameIsLocked(week, "thu", 1_000, 1_000)).toBe(true);
    expect(gameIsLocked(week, "sun", 3_000, 1_000)).toBe(false);

    const slate = { pickLockMode: "firstKickoff", pickDeadline: 1_000 };
    expect(gameIsLocked(slate, "sun", 3_000, 1_500)).toBe(true);
    expect(gameIsLocked(slate, "sun", 3_000, 500)).toBe(false);
  });

  it("returns the latest kickoff among games", () => {
    expect(
      lastKickoffMillis([{ kickoff: 1_000 }, { kickoff: 4_000 }, { kickoff: 2_000 }])
    ).toBe(4_000);
  });

  it("copies only the locked game's picks into the public projection", () => {
    const payload = revealedPicksForGame("thu", [
      { id: "alice", picks: { thu: "home", sun: "away" }, confidenceGameId: "thu" },
      { id: "bob", picks: { thu: "away", sun: "home" } },
      { id: "carol", picks: { sun: "home" } },
    ]);
    expect(payload.picks).toEqual({ alice: "home", bob: "away" });
    expect(payload.confidenceUserIds).toEqual(["alice"]);
  });

  it("does not lock a firstKickoff week at the last kickoff", () => {
    expect(
      effectiveWeekLockMillis({
        pickLockMode: "firstKickoff",
        pickDeadline: 1_000,
        weekLockAt: 1_000,
      })
    ).toBe(1_000);
    expect(
      effectiveWeekLockMillis({
        pickLockMode: "rolling",
        weekLockAt: 4_000,
      })
    ).toBe(4_000);
  });
});
