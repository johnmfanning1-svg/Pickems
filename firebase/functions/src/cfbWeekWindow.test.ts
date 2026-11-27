import { describe, expect, it } from "vitest";
import { weekWindowForPickemsWeek } from "./cfbWeekWindow";

describe("weekWindowForPickemsWeek", () => {
  it("returns regular-season week 15 window", () => {
    const window = weekWindowForPickemsWeek("2026-W15", 2026, 15);
    expect(window).not.toBeNull();
    expect(window!.start.getUTCFullYear()).toBe(2026);
    expect(window!.start.getUTCMonth()).toBe(11); // Dec
  });

  it("aligns BOWL2 window with ESPN postseason week 999", () => {
    const window = weekWindowForPickemsWeek("2026-BOWL2", 2026, 2);
    expect(window).not.toBeNull();
    const startParts = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      month: "short",
      day: "numeric",
    }).format(window!.start);
    expect(startParts).toContain("Dec");
    expect(startParts).toContain("18");
    const endYmd = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      year: "numeric",
      month: "numeric",
      day: "numeric",
    }).format(window!.end);
    expect(endYmd).toMatch(/1\/2[89]\/2027/);
  });

  it("returns bowl week window for BOWL1 deadline stamping", () => {
    const window = weekWindowForPickemsWeek("2026-BOWL1", 2026, 1);
    expect(window).not.toBeNull();
    const startParts = new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      month: "short",
      day: "numeric",
    }).format(window!.start);
    expect(startParts).toContain("Dec");
    expect(startParts).toContain("13");
  });
});