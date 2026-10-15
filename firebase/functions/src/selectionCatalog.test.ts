import { describe, expect, it } from "vitest";
import { kickoffsMillisByEspnEventId } from "./selectionCatalog";

describe("kickoffsMillisByEspnEventId", () => {
  it("keys each ESPN event by id using the scoreboard date", () => {
    const thursday = "2026-10-15T23:30:00.000Z";
    const saturday = "2026-10-17T16:00:00.000Z";
    expect(
      kickoffsMillisByEspnEventId([
        { id: "401", date: saturday },
        { id: " 402 ", date: thursday },
        { id: "405", date: "2026-08-29T16:00Z" },
        { id: "", date: saturday },
        { id: "403" },
        { id: "404", date: "not-a-date" },
      ])
    ).toEqual({
      "401": Date.parse(saturday),
      "402": Date.parse(thursday),
      "405": Date.parse("2026-08-29T16:00:00Z"),
    });
  });
});