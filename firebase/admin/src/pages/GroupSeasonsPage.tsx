import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { Badge } from "@/components/Badge";
import { Banner, ErrorBanner } from "@/components/Banner";
import { Button } from "@/components/Button";
import { Card, EmptyState, PageHeader } from "@/components/Card";
import { DataTable, type Column } from "@/components/DataTable";
import { Field, Select, TextInput } from "@/components/Fields";
import { GroupTabs } from "@/components/GroupTabs";
import { useConfirm } from "@/components/useConfirm";
import { useCareer, useGroup, useMembers, useSeasons, useWeeks } from "@/hooks/queries";
import { useAction } from "@/hooks/useAction";
import type { WithId } from "@/hooks/useFirestore";
import { adminCloseSeason, adminSetCareerRecord } from "@/lib/callables";
import { formatTimestamp, record } from "@/lib/format";
import type { CareerRecordDoc } from "@/lib/types";

type CareerEdit = {
  titles: string;
  seasonWins: string;
  seasonLosses: string;
  seasonsPlayed: string;
  bestFinish: string;
};

/**
 * Season/dynasty ops: close a season into an archive + career crowns, review
 * past champions, and repair career records (crowns) directly.
 */
export function GroupSeasonsPage() {
  const { id: groupId } = useParams<{ id: string }>();
  const { data: group } = useGroup(groupId);
  const seasons = useSeasons(groupId);
  const career = useCareer(groupId);
  const members = useMembers(groupId);
  const weeks = useWeeks(groupId);
  const action = useAction();
  const { confirm, dialog } = useConfirm();

  const latestSeasonYear = weeks.data.reduce(
    (max, week) => (week.seasonYear != null && week.seasonYear > max ? week.seasonYear : max),
    0,
  );
  const [seasonYear, setSeasonYear] = useState<string>("");
  const [champion, setChampion] = useState<string>("auto");
  const [careerEdit, setCareerEdit] = useState<{ id: string; draft: CareerEdit } | null>(null);

  if (!groupId) return <Banner tone="error" title="Missing group id" />;
  const groupName = group?.name ?? groupId;
  const yearValue = seasonYear || (latestSeasonYear ? String(latestSeasonYear) : String(new Date().getFullYear()));

  const memberName = (uid: string | null | undefined) =>
    members.data.find((m) => m.id === uid)?.displayName ?? uid ?? "—";

  async function closeSeason() {
    const year = Number(yearValue);
    if (!Number.isInteger(year)) {
      action.run("close", async () => {
        throw new Error("Enter a valid season year.");
      });
      return;
    }
    const championName = champion === "auto" ? "the top of the standings" : memberName(champion);
    if (!(await confirm({
      title: `Close the ${year} season?`,
      body: (
        <>
          <p>
            Archives the current member records for <strong>{groupName}</strong> as season{" "}
            <strong>{year}</strong>, crowns <strong>{championName}</strong>, adds a career title to the
            champion, and resets every member to 0-0.
          </p>
          <p className="mt-2 text-amber-300">
            This runs once per year — closing again for {year} is blocked so crowns are never
            double-counted. Fix a mistake with the career editor below.
          </p>
        </>
      ),
      tone: "primary",
      confirmLabel: "Close season",
    }))) {
      return;
    }
    await action.run("close", async () => {
      const result = await adminCloseSeason({
        groupId: groupId!,
        seasonYear: year,
        ...(champion === "auto" ? {} : { championUserId: champion }),
      });
      setChampion("auto");
      return result.championDisplayName
        ? `Season ${year} closed — ${result.championDisplayName} crowned champion.`
        : `Season ${year} closed.`;
    });
  }

  function beginCareerEdit(row: WithId<CareerRecordDoc>) {
    setCareerEdit({
      id: row.id,
      draft: {
        titles: String(row.titles ?? 0),
        seasonWins: String(row.seasonWins ?? 0),
        seasonLosses: String(row.seasonLosses ?? 0),
        seasonsPlayed: String(row.seasonsPlayed ?? 0),
        bestFinish: row.bestFinish != null ? String(row.bestFinish) : "",
      },
    });
  }

  async function saveCareer(row: WithId<CareerRecordDoc>) {
    if (!careerEdit || careerEdit.id !== row.id) return;
    const draft = careerEdit.draft;
    const toInt = (value: string) => Number(value);
    const nums = [draft.titles, draft.seasonWins, draft.seasonLosses, draft.seasonsPlayed].map(toInt);
    if (nums.some((n) => !Number.isFinite(n) || n < 0)) {
      action.run(`career:${row.id}`, async () => {
        throw new Error("Titles and records must be non-negative numbers.");
      });
      return;
    }
    if (!(await confirm({
      title: "Update career record?",
      body: (
        <>
          Sets <strong>{row.displayName ?? row.id}</strong> to <strong>{draft.titles}</strong>{" "}
          crown(s), {draft.seasonWins}-{draft.seasonLosses} career, {draft.seasonsPlayed} season(s)
          played. This is a direct override — it does not touch season archives.
        </>
      ),
      tone: "primary",
      confirmLabel: "Save record",
    }))) {
      return;
    }
    await action.run(`career:${row.id}`, async () => {
      await adminSetCareerRecord({
        groupId: groupId!,
        userId: row.id,
        titles: toInt(draft.titles),
        seasonWins: toInt(draft.seasonWins),
        seasonLosses: toInt(draft.seasonLosses),
        seasonsPlayed: toInt(draft.seasonsPlayed),
        bestFinish: draft.bestFinish === "" ? null : toInt(draft.bestFinish),
      });
      setCareerEdit(null);
      return "Career record updated.";
    });
  }

  const careerColumns: Column<WithId<CareerRecordDoc>>[] = [
    {
      key: "member",
      header: "Member",
      render: (row) => (
        <div className="min-w-0">
          <p className="font-medium text-slate-100">{row.displayName ?? "(no name)"}</p>
          <p className="font-mono text-xs text-slate-500">{row.id}</p>
        </div>
      ),
    },
    {
      key: "crowns",
      header: "Crowns",
      render: (row) => {
        const edit = careerEdit?.id === row.id ? careerEdit.draft : null;
        if (edit) {
          return (
            <TextInput
              type="number"
              min="0"
              value={edit.titles}
              className="w-20 font-mono"
              onChange={(e) => setCareerEdit((prev) => (prev ? { ...prev, draft: { ...prev.draft, titles: e.target.value } } : prev))}
            />
          );
        }
        return (
          <span className="font-mono text-slate-200">
            {"\u{1F451}".repeat(Math.min(row.titles ?? 0, 5))}
            {(row.titles ?? 0) > 5 ? " " : ""}
            {row.titles ?? 0}
          </span>
        );
      },
    },
    {
      key: "career",
      header: "Career W-L",
      render: (row) => {
        const edit = careerEdit?.id === row.id ? careerEdit.draft : null;
        if (edit) {
          return (
            <div className="flex items-center gap-1">
              <TextInput type="number" min="0" value={edit.seasonWins} className="w-16 font-mono" onChange={(e) => setCareerEdit((prev) => (prev ? { ...prev, draft: { ...prev.draft, seasonWins: e.target.value } } : prev))} />
              <span className="text-slate-500">-</span>
              <TextInput type="number" min="0" value={edit.seasonLosses} className="w-16 font-mono" onChange={(e) => setCareerEdit((prev) => (prev ? { ...prev, draft: { ...prev.draft, seasonLosses: e.target.value } } : prev))} />
            </div>
          );
        }
        return <span className="font-mono text-slate-300">{record(row.seasonWins, row.seasonLosses)}</span>;
      },
    },
    {
      key: "seasons",
      header: "Seasons",
      render: (row) => {
        const edit = careerEdit?.id === row.id ? careerEdit.draft : null;
        if (edit) {
          return (
            <TextInput type="number" min="0" value={edit.seasonsPlayed} className="w-16 font-mono" onChange={(e) => setCareerEdit((prev) => (prev ? { ...prev, draft: { ...prev.draft, seasonsPlayed: e.target.value } } : prev))} />
          );
        }
        return <span className="font-mono text-slate-300">{row.seasonsPlayed ?? 0}</span>;
      },
    },
    {
      key: "best",
      header: "Best finish",
      render: (row) => {
        const edit = careerEdit?.id === row.id ? careerEdit.draft : null;
        if (edit) {
          return (
            <TextInput type="number" min="0" value={edit.bestFinish} placeholder="—" className="w-16 font-mono" onChange={(e) => setCareerEdit((prev) => (prev ? { ...prev, draft: { ...prev.draft, bestFinish: e.target.value } } : prev))} />
          );
        }
        return <span className="font-mono text-slate-300">{row.bestFinish != null ? `#${row.bestFinish}` : "—"}</span>;
      },
    },
    {
      key: "actions",
      header: "",
      className: "text-right",
      render: (row) => {
        const editing = careerEdit?.id === row.id;
        return (
          <div className="flex justify-end gap-2 whitespace-nowrap">
            {editing ? (
              <>
                <Button variant="primary" pending={action.isPending(`career:${row.id}`)} disabled={action.busy} onClick={() => void saveCareer(row)}>
                  Save
                </Button>
                <Button variant="ghost" onClick={() => setCareerEdit(null)}>
                  Cancel
                </Button>
              </>
            ) : (
              <Button disabled={action.busy} onClick={() => beginCareerEdit(row)}>
                Edit crowns
              </Button>
            )}
          </div>
        );
      },
    },
  ];

  return (
    <>
      {dialog}
      <PageHeader
        title={`${groupName} — seasons & dynasty`}
        subtitle={`${seasons.data.length} archived season(s) · ${career.data.length} career record(s)`}
        actions={
          <Link to={`/groups/${groupId}`} className="text-sm text-slate-400 underline hover:text-slate-200">
            Overview
          </Link>
        }
      />
      <GroupTabs groupId={groupId} />
      <ErrorBanner
        error={seasons.error ?? career.error ?? members.error ?? action.error}
        onDismiss={action.clearError}
      />
      {action.message ? (
        <Banner tone="success" onDismiss={action.clearMessage}>
          {action.message}
        </Banner>
      ) : null}

      <Card
        title="Close a season"
        description="Archives current member records, crowns a champion, credits career titles, and resets everyone to 0-0."
      >
        <div className="flex flex-wrap items-end gap-3">
          <Field label="Season year">
            <TextInput
              type="number"
              value={yearValue}
              onChange={(e) => setSeasonYear(e.target.value)}
              className="w-32 font-mono"
            />
          </Field>
          <Field label="Champion" hint="Auto uses the top of the standings (batting-average tie-break).">
            <Select value={champion} onChange={(e) => setChampion(e.target.value)} className="w-56">
              <option value="auto">Auto (standings leader)</option>
              {members.data.map((member) => (
                <option key={member.id} value={member.id}>
                  {member.displayName ?? member.id}
                </option>
              ))}
            </Select>
          </Field>
          <Button variant="primary" pending={action.isPending("close")} disabled={action.busy} onClick={() => void closeSeason()}>
            Close season
          </Button>
        </div>
      </Card>

      <Card title="Career & crowns" description="Cumulative dynasty records. Crowns are season titles.">
        <DataTable
          columns={careerColumns}
          rows={career.data}
          rowKey={(row) => row.id}
          loading={career.loading}
          empty="No career records yet. Close a season to create them, or add one with the editor."
        />
      </Card>

      <Card title="Archived seasons" description="Past champions and final standings.">
        {seasons.data.length === 0 && !seasons.loading ? (
          <EmptyState>No seasons have been closed for this league yet.</EmptyState>
        ) : (
          <div className="space-y-4">
            {seasons.data.map((season) => (
              <div key={season.id} className="rounded-lg border border-ink-600 bg-ink-900/40 p-4">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <p className="text-sm font-semibold text-slate-100">Season {season.seasonYear}</p>
                    <p className="text-xs text-slate-500">
                      {season.weekCount} week(s) · closed {formatTimestamp(season.closedAt)}
                    </p>
                  </div>
                  <Badge tone="success">
                    {"\u{1F451}"} {season.championDisplayName ?? memberName(season.championUserId)}
                  </Badge>
                </div>
                <ol className="mt-3 space-y-1 text-sm">
                  {[...(season.finalStandings ?? [])]
                    .sort((a, b) => (a.rank ?? 0) - (b.rank ?? 0))
                    .map((entry) => (
                      <li key={entry.id} className="flex items-center gap-2 text-slate-300">
                        <span className="w-6 text-right font-mono text-slate-500">#{entry.rank}</span>
                        <span className="min-w-0 flex-1 truncate">{entry.displayName}</span>
                        <span className="font-mono text-slate-400">{record(entry.seasonWins, entry.seasonLosses)}</span>
                      </li>
                    ))}
                </ol>
              </div>
            ))}
          </div>
        )}
      </Card>
    </>
  );
}
