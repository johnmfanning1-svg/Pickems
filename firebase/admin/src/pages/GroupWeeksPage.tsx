import { deleteDoc, doc } from "firebase/firestore";
import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { Badge, WeekStatusBadge } from "@/components/Badge";
import { Banner, ErrorBanner } from "@/components/Banner";
import { Button } from "@/components/Button";
import { Card, EmptyState, PageHeader } from "@/components/Card";
import { Field, Select, TextInput } from "@/components/Fields";
import { GroupTabs } from "@/components/GroupTabs";
import { WeekSlateEditor } from "@/components/WeekSlateEditor";
import { useConfirm } from "@/components/useConfirm";
import { useGroup, useWeeks } from "@/hooks/queries";
import { useAction } from "@/hooks/useAction";
import type { WithId } from "@/hooks/useFirestore";
import { writeAudit } from "@/lib/audit";
import { adminRematerializeNominations, adminSetWeekStatus } from "@/lib/callables";
import { db } from "@/lib/firebase";
import {
  formatTimestamp,
  fromDateTimeLocalValue,
  toDateTimeLocalValue,
} from "@/lib/format";
import { WEEK_STATUSES, type WeekDoc, type WeekStatus } from "@/lib/types";

export function GroupWeeksPage() {
  const { id: groupId } = useParams<{ id: string }>();
  const { data: group } = useGroup(groupId);
  const weeks = useWeeks(groupId);
  const action = useAction();
  const { confirm, dialog } = useConfirm();

  const [expanded, setExpanded] = useState<string | null>(null);
  const [statusDraft, setStatusDraft] = useState<Record<string, WeekStatus>>({});
  const [deadlineDraft, setDeadlineDraft] = useState<Record<string, string>>({});

  if (!groupId) return <Banner tone="error" title="Missing group id" />;
  const groupName = group?.name ?? groupId;

  function draftStatus(week: WithId<WeekDoc>): WeekStatus {
    return statusDraft[week.id] ?? week.status ?? "selection";
  }

  function draftDeadline(week: WithId<WeekDoc>): string {
    return deadlineDraft[week.id] ?? toDateTimeLocalValue(week.pickDeadline);
  }

  async function applyWeek(week: WithId<WeekDoc>) {
    const status = draftStatus(week);
    const deadlineLocal = draftDeadline(week);
    const deadlineIso = fromDateTimeLocalValue(deadlineLocal);
    const currentIso = week.pickDeadline ? week.pickDeadline.toDate().toISOString() : null;
    const deadlineChanged = fromDateTimeLocalValue(toDateTimeLocalValue(week.pickDeadline)) !== deadlineIso;

    const goingBackwards =
      WEEK_STATUSES.indexOf(status) < WEEK_STATUSES.indexOf((week.status ?? "selection") as WeekStatus);

    if (!(await confirm({
      title: "Force this week's state?",
      body: (
        <>
          <p>
            <strong>{groupName}</strong> · week <code className="font-mono">{week.id}</code>:{" "}
            <code className="font-mono">{week.status ?? "none"}</code> →{" "}
            <code className="font-mono">{status}</code>
            {deadlineChanged ? (
              <>
                , deadline {currentIso ? formatTimestamp(week.pickDeadline) : "none"} →{" "}
                {deadlineIso ? formatTimestamp(new Date(deadlineIso)) : "cleared"}
              </>
            ) : null}
            .
          </p>
          {status === "picking" && week.status === "selection" ? (
            <p className="mt-2 text-sky-300">
              This also materializes nominations into the slate, exactly as the{" "}
              <code className="font-mono">onWeekStatusChange</code> trigger would.
            </p>
          ) : null}
          {goingBackwards ? (
            <p className="mt-2 text-amber-300">
              Re-opening a week lets members change picks that were already scored. Rescore the week
              afterwards or standings will disagree with the picks.
            </p>
          ) : null}
        </>
      ),
      tone: goingBackwards ? "danger" : "primary",
      confirmLabel: "Apply",
    }))) {
      return;
    }

    await action.run(`status:${week.id}`, async () => {
      const result = await adminSetWeekStatus({
        groupId: groupId!,
        weekId: week.id,
        status,
        ...(deadlineChanged ? { pickDeadline: deadlineIso } : {}),
      });
      setStatusDraft((previous) => {
        const next = { ...previous };
        delete next[week.id];
        return next;
      });
      setDeadlineDraft((previous) => {
        const next = { ...previous };
        delete next[week.id];
        return next;
      });
      return result.materialized
        ? `Week ${week.id} is ${status} and the slate was materialized.`
        : `Week ${week.id} is ${status}.`;
    });
  }

  async function rematerialize(week: WithId<WeekDoc>) {
    if (!(await confirm({
      title: "Re-materialize the slate?",
      body: (
        <>
          Rebuilds <code className="font-mono">games</code> for week{" "}
          <code className="font-mono">{week.id}</code> of <strong>{groupName}</strong> from its
          nominations. Live scores on games that still exist are preserved; a game whose nomination is
          gone disappears from the slate, and any pick pointing at it stops counting.
        </>
      ),
      confirmLabel: "Re-materialize",
    }))) {
      return;
    }
    await action.run(`materialize:${week.id}`, async () => {
      await adminRematerializeNominations({ groupId: groupId!, weekId: week.id, force: true });
      return `Slate rebuilt for ${week.id}.`;
    });
  }

  async function removeWeek(week: WithId<WeekDoc>) {
    if (!(await confirm({
      title: "Delete this week doc?",
      body: (
        <>
          <p>
            Deletes <code className="font-mono">groups/{groupId}/weeks/{week.id}</code> from{" "}
            <strong>{groupName}</strong>.
          </p>
          <p className="mt-2 text-amber-300">
            Its nominations, games, picks, and submissions are <strong>not</strong> removed — a client
            delete cannot recurse, and orphaned subcollections are invisible in the app but still
            billable. Clean up with:
            <code className="mt-1 block font-mono text-xs">
              firebase firestore:delete groups/{groupId}/weeks/{week.id} --recursive
            </code>
          </p>
        </>
      ),
      confirmLabel: "Delete week",
      requireText: week.id,
    }))) {
      return;
    }
    await action.run(`delete:${week.id}`, async () => {
      await writeAudit("adminDeleteWeek", `groups/${groupId}/weeks/${week.id}`, week, null);
      await deleteDoc(doc(db, "groups", groupId!, "weeks", week.id));
      return `Week ${week.id} deleted.`;
    });
  }

  return (
    <>
      {dialog}
      <PageHeader
        title={`${groupName} — weeks`}
        subtitle={`${weeks.data.length} week doc(s), newest first`}
        actions={
          <Link to="/audit/weeks" className="text-sm text-slate-400 underline hover:text-slate-200">
            Week audit
          </Link>
        }
      />
      <GroupTabs groupId={groupId} />
      <ErrorBanner error={weeks.error ?? action.error} onDismiss={action.clearError} />
      {action.message ? (
        <Banner tone="success" onDismiss={action.clearMessage}>
          {action.message}
        </Banner>
      ) : null}

      {weeks.data.length === 0 && !weeks.loading ? (
        <EmptyState>This league has no week docs yet.</EmptyState>
      ) : null}

      <div className="space-y-4">
        {weeks.data.map((week) => {
          const expectedId =
            week.seasonYear != null && week.weekNumber != null
              ? `${week.seasonYear}-W${week.weekNumber}`
              : null;
          const misaligned = expectedId != null && expectedId !== week.id;
          const isExpanded = expanded === week.id;

          return (
            <Card
              key={week.id}
              title={week.id}
              description={
                week.seasonYear != null && week.weekNumber != null
                  ? `Season ${week.seasonYear} · Week ${week.weekNumber}`
                  : "Missing seasonYear or weekNumber"
              }
              actions={
                <div className="flex items-center gap-2">
                  <WeekStatusBadge status={week.status} />
                  {misaligned ? <Badge tone="danger">expected {expectedId}</Badge> : null}
                  <Link
                    to={`/groups/${groupId}/weeks/${week.id}/picks`}
                    className="text-sm text-slate-400 underline hover:text-slate-200"
                  >
                    Picks
                  </Link>
                </div>
              }
            >
              <div className="grid gap-4 lg:grid-cols-[1fr_1fr_auto]">
                <Field label="Status">
                  <Select
                    value={draftStatus(week)}
                    disabled={action.busy}
                    onChange={(event) =>
                      setStatusDraft((previous) => ({
                        ...previous,
                        [week.id]: event.target.value as WeekStatus,
                      }))
                    }
                  >
                    {WEEK_STATUSES.map((status) => (
                      <option key={status} value={status}>
                        {status}
                      </option>
                    ))}
                  </Select>
                </Field>
                <Field label="Pick deadline" hint="Clear the field to remove the deadline entirely.">
                  <TextInput
                    type="datetime-local"
                    value={draftDeadline(week)}
                    disabled={action.busy}
                    onChange={(event) =>
                      setDeadlineDraft((previous) => ({ ...previous, [week.id]: event.target.value }))
                    }
                  />
                </Field>
                <div className="flex items-end">
                  <Button
                    variant="primary"
                    pending={action.isPending(`status:${week.id}`)}
                    disabled={action.busy}
                    onClick={() => void applyWeek(week)}
                  >
                    Apply
                  </Button>
                </div>
              </div>

              <dl className="mt-4 flex flex-wrap gap-x-6 gap-y-1 text-xs text-slate-500">
                <div>
                  <dt className="inline">nominationCount </dt>
                  <dd className="inline font-mono text-slate-300">{week.nominationCount ?? 0}</dd>
                </div>
                <div>
                  <dt className="inline">slateSize </dt>
                  <dd className="inline font-mono text-slate-300">{week.slateSize ?? "—"}</dd>
                </div>
                <div>
                  <dt className="inline">selectionDeadline </dt>
                  <dd className="inline font-mono text-slate-300">
                    {formatTimestamp(week.selectionDeadline)}
                  </dd>
                </div>
                <div>
                  <dt className="inline">lockedAt </dt>
                  <dd className="inline font-mono text-slate-300">{formatTimestamp(week.lockedAt)}</dd>
                </div>
                <div>
                  <dt className="inline">scoredAt </dt>
                  <dd className="inline font-mono text-slate-300">{formatTimestamp(week.scoredAt)}</dd>
                </div>
              </dl>

              <div className="mt-4 flex flex-wrap gap-2">
                <Button
                  pending={action.isPending(`materialize:${week.id}`)}
                  disabled={action.busy}
                  onClick={() => void rematerialize(week)}
                >
                  Re-materialize slate
                </Button>
                <Button onClick={() => setExpanded(isExpanded ? null : week.id)}>
                  {isExpanded ? "Hide slate & spreads" : "Slate & spreads"}
                </Button>
                <Button
                  variant="danger"
                  pending={action.isPending(`delete:${week.id}`)}
                  disabled={action.busy}
                  onClick={() => void removeWeek(week)}
                >
                  Delete week
                </Button>
              </div>

              {isExpanded ? (
                <div className="mt-4 border-t border-ink-600 pt-4">
                  <WeekSlateEditor groupId={groupId} weekId={week.id} />
                </div>
              ) : null}
            </Card>
          );
        })}
      </div>
    </>
  );
}
