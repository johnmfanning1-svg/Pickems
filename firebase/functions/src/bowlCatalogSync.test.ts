import { describe, expect, it } from "vitest";
import type { EspnEvent } from "./espn";
import { isBowlFullSlateWeek } from "./bowlWeek";

describe("bowlCatalogSync guards", () => {
  it("full slate requires 2026-BOWL week id", () => {
    expect(
      isBowlFullSlateWeek({ bowlFullSlate: true, slateSource: "bowlCatalog" }, "2026-BOWL")
    ).toBe(true);
    expect(
      isBowlFullSlateWeek({ bowlFullSlate: true, slateSource: "bowlCatalog" }, "2026-BOWL1")
    ).toBe(false);
  });

  it("espn events carry kickoff for mirror merge", () => {
    const event: EspnEvent = {
      id: "cfp-natty",
      date: "2027-01-25T01:30:00.000Z",
      competitions: [
        {
          competitors: [
            {
              id: "1",
              homeAway: "home",
              team: { id: "h", displayName: "Home", abbreviation: "HOM" },
            },
            {
              id: "2",
              homeAway: "away",
              team: { id: "a", displayName: "Away", abbreviation: "AWY" },
            },
          ],
        },
      ],
    };
    expect(event.date).toBeTruthy();
    expect(event.competitions?.[0]?.competitors?.length).toBe(2);
  });
});