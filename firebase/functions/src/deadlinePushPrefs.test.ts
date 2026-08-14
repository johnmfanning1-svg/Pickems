import { describe, it, expect } from "vitest";
import { shouldSendDeadlinePush } from "./deadlinePushPrefs";

describe("deadline notification prefs", () => {
  it("defaults to sending when prefs are missing", () => {
    expect(shouldSendDeadlinePush(undefined, "deadline_reminder")).toBe(true);
    expect(shouldSendDeadlinePush({}, "selection_deadline_reminder")).toBe(true);
    expect(shouldSendDeadlinePush({}, "week_scored")).toBe(true);
  });

  it("skips Selection deadline pushes when opted out", () => {
    const data = { notifySelectionDeadlines: false };
    expect(shouldSendDeadlinePush(data, "selection_deadline_reminder")).toBe(false);
    expect(shouldSendDeadlinePush(data, "deadline_reminder")).toBe(true);
  });

  it("skips Pickems deadline pushes when opted out", () => {
    const data = { notifyPickemsDeadlines: false };
    expect(shouldSendDeadlinePush(data, "deadline_reminder")).toBe(false);
    expect(shouldSendDeadlinePush(data, "pickems_open")).toBe(false);
    expect(shouldSendDeadlinePush(data, "selection_deadline_reminder")).toBe(true);
  });
});
