export type DeadlinePushType =
  | "week_scored"
  | "deadline_reminder"
  | "deadline_locked"
  | "deadline_passed"
  | "set_selection_deadline"
  | "selection_deadline_passed"
  | "selection_deadline_reminder"
  | "pickems_open"
  | "game_final"
  | "took_the_lead"
  | "season_closed"
  | "chat_message";

export type PushPrefFields = {
  notifySelectionDeadlines?: boolean;
  notifyPickemsDeadlines?: boolean;
  notifyGameFinals?: boolean;
  notifyTookTheLead?: boolean;
  notifyWeekScored?: boolean;
  notifySeasonClosed?: boolean;
  notifyChatMessages?: boolean;
};

const PREF_FOR_TYPE: Record<DeadlinePushType, keyof PushPrefFields> = {
  set_selection_deadline: "notifySelectionDeadlines",
  selection_deadline_passed: "notifySelectionDeadlines",
  selection_deadline_reminder: "notifySelectionDeadlines",
  deadline_reminder: "notifyPickemsDeadlines",
  deadline_locked: "notifyPickemsDeadlines",
  deadline_passed: "notifyPickemsDeadlines",
  pickems_open: "notifyPickemsDeadlines",
  game_final: "notifyGameFinals",
  took_the_lead: "notifyTookTheLead",
  week_scored: "notifyWeekScored",
  season_closed: "notifySeasonClosed",
  chat_message: "notifyChatMessages",
};

/** Missing prefs default to on so existing users keep receiving alerts. */
export function shouldSendDeadlinePush(
  data: PushPrefFields | undefined,
  type: string
): boolean {
  const key = PREF_FOR_TYPE[type as DeadlinePushType];
  if (!key) return true;
  return data?.[key] !== false;
}
