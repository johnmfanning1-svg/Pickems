import { describe, expect, it } from "vitest";
import { shouldSendSelectionDeadlineNudge } from "./selectionDeadlineNudge";

describe("selectionDeadlineNudge", () => {
  it("skips when a selection deadline already exists", () => {
    expect(shouldSendSelectionDeadlineNudge({ selectionDeadline: new Date() })).toBe(false);
  });

  it("skips when nudge was already sent", () => {
    expect(
      shouldSendSelectionDeadlineNudge({ selectionDeadlineNudgeSent: true })
    ).toBe(false);
  });

  it("nudges when no deadline and no prior nudge", () => {
    expect(shouldSendSelectionDeadlineNudge({})).toBe(true);
  });

  it("skips after default stamp lost race to manual deadline", () => {
    expect(
      shouldSendSelectionDeadlineNudge({
        selectionDeadline: { toDate: () => new Date() },
      })
    ).toBe(false);
  });
});