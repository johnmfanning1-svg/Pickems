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
  notifyCommissionerDeadlines?: boolean;
};

export type MemberPushPrefFields = PushPrefFields & {
  chatMuted?: boolean;
};

const PREF_FOR_TYPE: Record<DeadlinePushType, keyof PushPrefFields> = {
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
  set_selection_deadline: "notifyCommissionerDeadlines",
  selection_deadline_passed: "notifyCommissionerDeadlines",
};

function storedBool(
  data: PushPrefFields | undefined,
  key: keyof PushPrefFields
): boolean | undefined {
  const value = data?.[key];
  return typeof value === "boolean" ? value : undefined;
}

/**
 * League member override if present, else account default, else on.
 * `chatMuted` on the member doc always suppresses chat.
 * Unset commissioner prefs fall back to the legacy Selection-deadlines account pref.
 */
export function shouldSendDeadlinePush(
  user: PushPrefFields | undefined,
  type: string,
  member?: MemberPushPrefFields
): boolean {
  const key = PREF_FOR_TYPE[type as DeadlinePushType];
  if (!key) return true;

  if (key === "notifyChatMessages" && member?.chatMuted === true) {
    return false;
  }

  const memberValue = storedBool(member, key);
  if (memberValue !== undefined) return memberValue;

  const userValue = storedBool(user, key);
  if (userValue !== undefined) return userValue;

  if (key === "notifyCommissionerDeadlines") {
    return user?.notifySelectionDeadlines !== false;
  }

  return true;
}
