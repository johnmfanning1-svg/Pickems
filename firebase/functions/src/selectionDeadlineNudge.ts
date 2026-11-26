/** Commissioner push when a selection week opens without a deadline. */
export function shouldSendSelectionDeadlineNudge(week: {
  selectionDeadline?: unknown;
  selectionDeadlineNudgeSent?: boolean;
}): boolean {
  if (week.selectionDeadline) return false;
  if (week.selectionDeadlineNudgeSent) return false;
  return true;
}
