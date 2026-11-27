import { describe, expect, it } from "vitest";
import {
  groupShouldSkipAutoClose,
  isBowlWeekDocumentId,
  isOpenBowlWeek,
  seasonYearToArchive,
  espnPostseasonWouldMintRegularWeekOne,
} from "./autoCloseSeasonsLogic";

describe("autoCloseSeasonsLogic", () => {
  it("detects ESPN postseason week 1 collision risk", () => {
    expect(espnPostseasonWouldMintRegularWeekOne(2026, 1, 3)).toBe(true);
    expect(espnPostseasonWouldMintRegularWeekOne(2026, 1, 2)).toBe(false);
    expect(espnPostseasonWouldMintRegularWeekOne(2026, 2, 3)).toBe(false);
  });

  it("recognizes bowl week document ids", () => {
    expect(isBowlWeekDocumentId("2026-BOWL1")).toBe(true);
    expect(isBowlWeekDocumentId("2026-BOWL2")).toBe(true);
    expect(isBowlWeekDocumentId("2026-BOWL")).toBe(true);
    expect(isBowlWeekDocumentId("2026-W15")).toBe(false);
  });

  it("treats unscored bowl weeks as open", () => {
    expect(isOpenBowlWeek("2026-BOWL1", { status: "selection" })).toBe(true);
    expect(isOpenBowlWeek("2026-BOWL1", { status: "picking", seasonType: 3 })).toBe(true);
    expect(isOpenBowlWeek("2026-BOWL1", { status: "scored", seasonType: 3 })).toBe(false);
    expect(isOpenBowlWeek("2026-W15", { status: "picking" })).toBe(false);
  });

  it("skips season close when a bowl week is still open", () => {
    expect(
      groupShouldSkipAutoClose([
        { id: "2026-W15", data: { status: "scored" } },
        { id: "2026-BOWL1", data: { status: "picking", seasonType: 3 } },
      ])
    ).toBe(true);
    expect(
      groupShouldSkipAutoClose([
        { id: "2026-W15", data: { status: "scored" } },
        { id: "2026-BOWL1", data: { status: "scored", seasonType: 3 } },
      ])
    ).toBe(false);
  });

  it("archives 2026 when the job runs Feb 1 2027 Eastern", () => {
    const runAt = new Date("2027-02-01T17:00:00.000Z"); // noon ET
    expect(seasonYearToArchive(runAt)).toBe(2026);
  });
});