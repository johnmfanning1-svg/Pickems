import { describe, expect, it } from "vitest";
import {
  assertConfidenceChangeAllowed,
  assertLockTransitionAllowed,
  validateConfidenceGameId,
} from "./bowlMemberPickLogic";

describe("bowlMemberPickLogic", () => {
  const slate = new Set(["g1", "g2"]);

  it("rejects empty and off-slate confidence ids", () => {
    expect(() => validateConfidenceGameId("", slate, true)).toThrow(/cannot be empty/);
    expect(() => validateConfidenceGameId("  ", slate, true)).toThrow(/cannot be empty/);
    expect(() => validateConfidenceGameId("nope", slate, true)).toThrow(/not on the bowl slate/);
    expect(validateConfidenceGameId("g1", slate, true)).toBe("g1");
    expect(validateConfidenceGameId(null, slate, true)).toBeNull();
  });

  it("blocks moving confidence off a kicked-off game", () => {
    const past = Date.now() - 60_000;
    expect(() =>
      assertConfidenceChangeAllowed({
        beforeConfidence: "g1",
        afterConfidence: "g2",
        games: [{ id: "g1", kickoff: past, status: "scheduled" }],
        week: { pickLockMode: "rolling", gameKickoffs: { g1: past } },
        now: Date.now(),
      })
    ).toThrow(/Cannot change confidence off/);
  });

  it("rejects unlock after submit", () => {
    expect(() => assertLockTransitionAllowed(true, false)).toThrow(/cannot be unlocked/);
    expect(assertLockTransitionAllowed(true, true)).toBe(true);
    expect(assertLockTransitionAllowed(false, false)).toBe(false);
  });
});