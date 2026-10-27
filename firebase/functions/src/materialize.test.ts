import { describe, expect, it } from "vitest";
import { Timestamp } from "firebase-admin/firestore";
import {
  lineForMaterializedGame,
  preservedLinesForStartedGames,
} from "./materialize";

const past = Timestamp.fromMillis(1_000);
const future = Timestamp.fromMillis(9_000_000_000_000);
const now = 5_000;

describe("lineForMaterializedGame", () => {
  it("takes the nomination line while the game has not started", () => {
    expect(
      lineForMaterializedGame({
        started: false,
        nominationSpread: 14,
        nominationSpreadTeamId: "away",
        existing: { spread: 3, spreadTeamId: "home", lockedSpread: 3, lockedSpreadTeamId: "home" },
      })
    ).toEqual({
      spread: 14,
      spreadTeamId: "away",
      clearLockedSpread: true,
    });
  });

  it("keeps an existing lockedSpread when the game has started", () => {
    expect(
      lineForMaterializedGame({
        started: true,
        nominationSpread: 14,
        nominationSpreadTeamId: "away",
        existing: { spread: 3.5, spreadTeamId: "home", lockedSpread: 3, lockedSpreadTeamId: "home" },
      })
    ).toEqual({
      spread: 3.5,
      spreadTeamId: "home",
      lockedSpread: 3,
      lockedSpreadTeamId: "home",
      clearLockedSpread: false,
    });
  });

  it("stamps the stored spread, not the nomination, when a started game has no lockedSpread yet", () => {
    expect(
      lineForMaterializedGame({
        started: true,
        nominationSpread: 14,
        nominationSpreadTeamId: "away",
        existing: { spread: 3.5, spreadTeamId: "home" },
      })
    ).toEqual({
      spread: 3.5,
      spreadTeamId: "home",
      lockedSpread: 3.5,
      lockedSpreadTeamId: "home",
      clearLockedSpread: false,
    });
  });

  it("captures the nomination the first time a started game is created", () => {
    expect(
      lineForMaterializedGame({
        started: true,
        nominationSpread: -6.5,
        nominationSpreadTeamId: "away",
      })
    ).toEqual({
      spread: 6.5,
      spreadTeamId: "away",
      lockedSpread: 6.5,
      lockedSpreadTeamId: "away",
      clearLockedSpread: false,
    });
  });
});

describe("preservedLinesForStartedGames", () => {
  it("keeps started games and drops ones that have not kicked off", () => {
    const week = { status: "selection" };
    const started = {
      kickoff: past,
      status: "scheduled",
      spread: 3,
      spreadTeamId: "home",
      lockedSpread: 3,
      lockedSpreadTeamId: "home",
    };
    const open = { kickoff: future, status: "scheduled", spread: 7, spreadTeamId: "away" };
    const preserved = preservedLinesForStartedGames(
      week,
      [
        { id: "started", data: started },
        { id: "open", data: open },
      ],
      now
    );
    expect(preserved.get("started")).toEqual(started);
    expect(preserved.has("open")).toBe(false);
  });
});
