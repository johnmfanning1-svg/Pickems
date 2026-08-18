import { deleteDoc, doc } from "firebase/firestore";
import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { Badge } from "@/components/Badge";
import { Banner, ErrorBanner } from "@/components/Banner";
import { Button } from "@/components/Button";
import { Card, EmptyState, PageHeader, StatTile } from "@/components/Card";
import { DataTable, type Column } from "@/components/DataTable";
import { Field, Select, TextInput } from "@/components/Fields";
import { useConfirm } from "@/components/useConfirm";
import { useGroups } from "@/hooks/queries";
import { useAction } from "@/hooks/useAction";
import { writeAudit } from "@/lib/audit";
import { adminAuditWeekIds, adminMigrateWeek0Split, adminRematerializeNominations, describeError } from "@/lib/callables";
import { db } from "@/lib/firebase";
import type { WeekAuditRow } from "@/lib/types";

const ISSUE_HELP: Record<string, string> = {
  misalignedWeekId:
    "The doc id disagrees with ESPN numbering. Members whose client derives the id from ESPN write to a different doc, which is how one real week ends up split in two.",
  duplicateWeekNumber:
    "Two week docs claim the same season and week number. Nominations and picks are split across both.",
  orphanWeek: "No nominations, games, or picks. Safe to delete.",
  gameNominationCountMismatch:
    "The materialized slate does not match the nominations. Re-materialize to rebuild it.",
  missingSeasonOrWeekNumber:
    "No seasonYear or weekNumber, so the expected id cannot be derived and the app cannot label the week.",
};

const ISSUE_TONE: Record<string, "danger" | "warning" | "neutral"> = {
  misalignedWeekId: "danger",
  duplicateWeekNumber: "danger",
  missingSeasonOrWeekNumber: "danger",
  gameNominationCountMismatch: "warning",
  orphanWeek: "neutral",
};

export function AuditWeeksPage() {
  const groups = useGroups();
  const action = useAction();
  const { confirm, dialog } = useConfirm();

  const [groupFilter, setGroupFilter] = useState("");
  const [seasonFilter, setSeasonFilter] = useState("");
  const [rows, setRows] = useState<WeekAuditRow[] | null>(null);
  const [groupsScanned, setGroupsScanned] = useState(0);
  const [scanning, setScanning] = useState(false);
  const [scanError, setScanError] = useState<string | null>(null);
  const [splitRows, setSplitRows] = useState<
    Array<{
      groupId: string;
      groupName: string | null;
      skipped: boolean;
      skipReason?: string;
      weekZeroGames: number;
      movedNominations: number;
      movedPickDocs: number;
      deletedWeekOneGames: number;
      clearedSubmissions: number;
      weekOnePickDeadline: string | null;
    }> | null
  >(null);

  const scan = useCallback(async (groupId: string, seasonYear: string) => {
    setScanning(true);
    setScanError(null);
    try {
      const season = seasonYear.trim() === "" ? undefined : Number(seasonYear);
      const result = await adminAuditWeekIds({
        ...(groupId ? { groupId } : {}),
        ...(season != null && Number.isInteger(season) ? { seasonYear: season } : {}),
      });
      setRows(result.rows);
      setGroupsScanned(result.groupsScanned);
    } catch (error) {
      setScanError(describeError(error));
      setRows(null);
    } finally {
      setScanning(false);
    }
  }, []);

  useEffect(() => {
    void scan("", "");
  }, [scan]);

  async function removeWeek(row: WeekAuditRow) {
    if (!(await confirm({
      title: "Delete this orphan week?",
      body: (
        <>
          Deletes <code className="font-mono">groups/{row.groupId}/weeks/{row.weekId}</code> from{" "}
          <strong>{row.groupName ?? row.groupId}</strong>. The audit reports no nominations, games, or
          picks, so nothing is lost — but re-run the scan afterwards to confirm.
        </>
      ),
      confirmLabel: "Delete week",
      requireText: row.weekId,
    }))) {
      return;
    }
    await action.run(`delete:${row.groupId}:${row.weekId}`, async () => {
      await writeAudit(
        "adminDeleteOrphanWeek",
        `groups/${row.groupId}/weeks/${row.weekId}`,
        row,
        null,
      );
      await deleteDoc(doc(db, "groups", row.groupId, "weeks", row.weekId));
      await scan(groupFilter, seasonFilter);
      return `Deleted ${row.weekId}.`;
    });
  }

  async function rematerialize(row: WeekAuditRow) {
    if (!(await confirm({
      title: "Re-materialize this slate?",
      body: (
        <>
          Rebuilds the slate for <code className="font-mono">{row.weekId}</code> in{" "}
          <strong>{row.groupName ?? row.groupId}</strong> from its {row.nominationCount} nomination(s).
        </>
      ),
      confirmLabel: "Re-materialize",
    }))) {
      return;
    }
    await action.run(`materialize:${row.groupId}:${row.weekId}`, async () => {
      await adminRematerializeNominations({
        groupId: row.groupId,
        weekId: row.weekId,
        force: true,
      });
      await scan(groupFilter, seasonFilter);
      return "Slate rebuilt.";
    });
  }

  async function runWeek0Split(dryRun: boolean) {
    if (!(await confirm({
      title: dryRun ? "Dry-run the Week 0 split?" : "Apply the Week 0 split?",
      body: dryRun
        ? "Reads every 2026-W1 doc and reports what would move onto 2026-W0. No writes."
        : (
          <>
            Creates <code className="font-mono">2026-W0</code> with the eight Aug 29 games,
            moves Saturday nominations/picks off <code className="font-mono">2026-W1</code>,
            and recomputes Week 1 pick deadlines. This cannot be undone from the portal.
          </>
        ),
      confirmLabel: dryRun ? "Dry run" : "Apply split",
      requireText: dryRun ? undefined : "SPLIT",
      tone: dryRun ? "primary" : "danger",
    }))) {
      return;
    }
    await action.run(`week0-split:${dryRun ? "dry" : "apply"}`, async () => {
      const result = await adminMigrateWeek0Split({
        dryRun,
        ...(groupFilter ? { groupId: groupFilter } : {}),
      });
      setSplitRows(result.groups);
      const migrated = result.groups.filter((g) => !g.skipped).length;
      const skipped = result.groups.length - migrated;
      return dryRun
        ? `Dry run: ${migrated} group(s) would migrate, ${skipped} skipped.`
        : `Applied: ${migrated} group(s) migrated, ${skipped} skipped.`;
    });
  }

  const columns: Column<WeekAuditRow>[] = [
    {
      key: "group",
      header: "League",
      render: (row) => (
        <div className="min-w-0">
          <Link to={`/groups/${row.groupId}`} className="font-medium text-slate-100 hover:underline">
            {row.groupName ?? "(no name)"}
          </Link>
          <p className="font-mono text-xs text-slate-500">{row.groupId}</p>
        </div>
      ),
    },
    {
      key: "week",
      header: "Week doc",
      render: (row) => (
        <div className="min-w-0">
          <Link
            to={`/groups/${row.groupId}/weeks/${row.weekId}/picks`}
            className="font-mono text-slate-200 hover:underline"
          >
            {row.weekId}
          </Link>
          {row.expectedWeekId && row.expectedWeekId !== row.weekId ? (
            <p className="font-mono text-xs text-red-400">expected {row.expectedWeekId}</p>
          ) : null}
        </div>
      ),
    },
    {
      key: "status",
      header: "Status",
      render: (row) => <span className="text-slate-400">{row.status ?? "—"}</span>,
    },
    {
      key: "counts",
      header: "Noms / games / picks",
      render: (row) => (
        <span className="font-mono text-slate-300">
          {row.nominationCount} / {row.gameCount} / {row.pickCount}
        </span>
      ),
    },
    {
      key: "issues",
      header: "Issues",
      render: (row) => (
        <div className="flex flex-wrap gap-1">
          {row.issues.map((issue) => (
            <span key={issue} title={ISSUE_HELP[issue] ?? issue}>
              <Badge tone={ISSUE_TONE[issue] ?? "warning"}>{issue}</Badge>
            </span>
          ))}
        </div>
      ),
    },
    {
      key: "actions",
      header: "",
      className: "text-right",
      render: (row) => {
        const isOrphan = row.issues.includes("orphanWeek");
        const canRematerialize = row.nominationCount > 0;
        return (
          <div className="flex justify-end gap-2 whitespace-nowrap">
            {canRematerialize ? (
              <Button
                pending={action.isPending(`materialize:${row.groupId}:${row.weekId}`)}
                disabled={action.busy}
                onClick={() => void rematerialize(row)}
              >
                Re-materialize
              </Button>
            ) : null}
            {isOrphan ? (
              <Button
                variant="danger"
                pending={action.isPending(`delete:${row.groupId}:${row.weekId}`)}
                disabled={action.busy}
                onClick={() => void removeWeek(row)}
              >
                Delete
              </Button>
            ) : (
              <Link
                to={`/groups/${row.groupId}/weeks`}
                className="text-xs text-slate-400 underline hover:text-slate-200"
              >
                Open weeks
              </Link>
            )}
          </div>
        );
      },
    },
  ];

  const misaligned = rows?.filter((row) => row.issues.includes("misalignedWeekId")).length ?? 0;
  const duplicates = rows?.filter((row) => row.issues.includes("duplicateWeekNumber")).length ?? 0;
  const orphans = rows?.filter((row) => row.issues.includes("orphanWeek")).length ?? 0;

  return (
    <>
      {dialog}
      <PageHeader
        title="Week audit"
        subtitle="Risk R1: a fallback week id that disagrees with ESPN mints a parallel week doc and splits a league's picks in two. Run this against production before every TestFlight invite."
        actions={
          <Button
            variant="primary"
            pending={scanning}
            onClick={() => void scan(groupFilter, seasonFilter)}
          >
            Run scan
          </Button>
        }
      />

      <ErrorBanner error={scanError ?? action.error} onDismiss={action.clearError} />
      {action.message ? (
        <Banner tone="success" onDismiss={action.clearMessage}>
          {action.message}
        </Banner>
      ) : null}

      <Card
        title="2026 Week 0 split"
        description="ESPN Week 1 is 99 games. This carves Saturday Aug 29 into 2026-W0 and leaves Sep 3–7 on 2026-W1."
      >
        <div className="flex flex-wrap gap-3">
          <Button variant="secondary" onClick={() => void runWeek0Split(true)}>
            Dry run
          </Button>
          <Button variant="danger" onClick={() => void runWeek0Split(false)}>
            Apply split
          </Button>
        </div>
        {splitRows != null ? (
          <div className="mt-4 overflow-x-auto">
            <table className="min-w-full text-left text-sm">
              <thead className="text-xs uppercase text-slate-500">
                <tr>
                  <th className="py-2 pr-4">League</th>
                  <th className="py-2 pr-4">Result</th>
                  <th className="py-2 pr-4">W0 games</th>
                  <th className="py-2 pr-4">Noms moved</th>
                  <th className="py-2 pr-4">W1 games removed</th>
                  <th className="py-2">W1 deadline</th>
                </tr>
              </thead>
              <tbody>
                {splitRows.map((row) => (
                  <tr key={row.groupId} className="border-t border-ink-600">
                    <td className="py-2 pr-4">
                      <div className="font-medium text-slate-100">{row.groupName ?? row.groupId}</div>
                      <div className="font-mono text-xs text-slate-500">{row.groupId}</div>
                    </td>
                    <td className="py-2 pr-4 text-slate-300">
                      {row.skipped ? row.skipReason ?? "skipped" : "migrated"}
                    </td>
                    <td className="py-2 pr-4">{row.weekZeroGames}</td>
                    <td className="py-2 pr-4">{row.movedNominations}</td>
                    <td className="py-2 pr-4">{row.deletedWeekOneGames}</td>
                    <td className="py-2 font-mono text-xs text-slate-400">
                      {row.weekOnePickDeadline ?? "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}
      </Card>

      <Card title="Scope">
        <div className="flex flex-wrap items-end gap-3">
          <Field label="League" hint="Blank scans every league.">
            <Select
              value={groupFilter}
              className="w-72"
              onChange={(event) => setGroupFilter(event.target.value)}
            >
              <option value="">All leagues</option>
              {groups.data.map((group) => (
                <option key={group.id} value={group.id}>
                  {group.name ?? group.id}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Season year" hint="Blank scans every season.">
            <TextInput
              type="number"
              placeholder="2026"
              value={seasonFilter}
              className="w-32"
              onChange={(event) => setSeasonFilter(event.target.value)}
            />
          </Field>
        </div>
      </Card>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Groups scanned" value={scanning ? "…" : groupsScanned} />
        <StatTile label="Misaligned ids" value={misaligned} hint="doc id ≠ {season}-W{number}" />
        <StatTile label="Duplicate weeks" value={duplicates} hint="same season and week number" />
        <StatTile label="Orphans" value={orphans} hint="no noms, games, or picks" />
      </div>

      {rows != null && rows.length === 0 ? (
        <Banner tone="success" title="No findings">
          Every week doc scanned has an id matching <code className="font-mono">{"{seasonYear}-W{weekNumber}"}</code>,
          with no duplicates or orphans.
        </Banner>
      ) : null}

      {misaligned > 0 || duplicates > 0 ? (
        <Banner tone="warning" title="Merging a split week is a manual job">
          There is no merge callable, and inventing one here would risk double-counting picks. To merge:
          open both week docs' picks grids, decide which doc is canonical (the one whose id matches ESPN
          numbering), copy the other doc's picks into it with the picks grid, rescore, then delete the
          loser once its counts read 0.
        </Banner>
      ) : null}

      <Card title="Findings" description="Clean weeks are omitted — an empty table is a pass.">
        {rows == null ? (
          <EmptyState>{scanning ? "Scanning…" : "Run a scan to see findings."}</EmptyState>
        ) : (
          <DataTable
            columns={columns}
            rows={rows}
            rowKey={(row) => `${row.groupId}:${row.weekId}`}
            loading={scanning}
            empty="No misaligned, duplicate, or orphan weeks."
          />
        )}
      </Card>
    </>
  );
}
