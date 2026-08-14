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

const SELECTION_DEADLINE_TYPES: DeadlinePushType[] = [
  "set_selection_deadline",
  "selection_deadline_passed",
  "selection_deadline_reminder",
];

const PICKEMS_DEADLINE_TYPES: DeadlinePushType[] = [
  "deadline_reminder",
  "deadline_locked",
  "deadline_passed",
  "pickems_open",
];

/** Missing prefs default to on so existing users keep receiving deadline alerts. */
export function shouldSendDeadlinePush(
  data: { notifySelectionDeadlines?: boolean; notifyPickemsDeadlines?: boolean } | undefined,
  type: string
): boolean {
  if (SELECTION_DEADLINE_TYPES.includes(type as DeadlinePushType)) {
    return data?.notifySelectionDeadlines !== false;
  }
  if (PICKEMS_DEADLINE_TYPES.includes(type as DeadlinePushType)) {
    return data?.notifyPickemsDeadlines !== false;
  }
  return true;
}
