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

  it("honors game, standings, season, and chat opt-outs", () => {
    expect(shouldSendDeadlinePush({ notifyGameFinals: false }, "game_final")).toBe(false);
    expect(shouldSendDeadlinePush({ notifyTookTheLead: false }, "took_the_lead")).toBe(false);
    expect(shouldSendDeadlinePush({ notifyWeekScored: false }, "week_scored")).toBe(false);
    expect(shouldSendDeadlinePush({ notifySeasonClosed: false }, "season_closed")).toBe(false);
    expect(shouldSendDeadlinePush({ notifyChatMessages: false }, "chat_message")).toBe(false);
    expect(shouldSendDeadlinePush({ notifyGameFinals: false }, "week_scored")).toBe(true);
  });
});
