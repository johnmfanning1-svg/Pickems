import { collection, getCountFromServer, getDocs } from "firebase/firestore";
import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { Badge, WeekStatusBadge } from "@/components/Badge";
import { Banner, ErrorBanner } from "@/components/Banner";
import { Button } from "@/components/Button";
import { Card, EmptyState, PageHeader, StatTile } from "@/components/Card";
import { DataTable, type Column } from "@/components/DataTable";
import { useAuditLog, useGroups } from "@/hooks/queries";
import type { WithId } from "@/hooks/useFirestore";
import { describeError } from "@/lib/callables";
import { db } from "@/lib/firebase";
import { formatRelative, truncate } from "@/lib/format";
import { WEEK_STATUSES, type AuditEntryDoc, type WeekStatus } from "@/lib/types";

/** Scanning every group's weeks is a fan-out, so it is capped and disclosed. */
const WEEK_SCAN_GROUP_LIMIT = 100;

type StatusTally = Record<WeekStatus | "unknown", number>;

const EMPTY_TALLY: StatusTally = {
  selection: 0,
  picking: 0,
  locked: 0,
  scored: 0,
  unknown: 0,
};

export function DashboardPage() {
  const groups = useGroups();
  const audit = useAuditLog(null, 10);

  const [userCount, setUserCount] = useState<number | null>(null);
  const [countError, setCountError] = useState<string | null>(null);

  const [tally, setTally] = useState<StatusTally | null>(null);
  const [weekTotal, setWeekTotal] = useState(0);
  const [scanning, setScanning] = useState(false);
  const [scanError, setScanError] = useState<string | null>(null);
  const [scannedGroups, setScannedGroups] = useState(0);

  useEffect(() => {
    // An aggregation query, so this is one billed read rather than one per user.
    getCountFromServer(collection(db, "users"))
      .then((snapshot) => setUserCount(snapshot.data().count))
      .catch((error) => setCountError(describeError(error)));
  }, []);

  const groupIds = groups.data.map((group) => group.id);
  const groupCount = groupIds.length;

  const scanWeeks = useCallback(async (ids: string[]) => {
    setScanning(true);
    setScanError(null);
    try {
      const scoped = ids.slice(0, WEEK_SCAN_GROUP_LIMIT);
      const next = { ...EMPTY_TALLY };
      let total = 0;
      const snapshots = await Promise.all(
        scoped.map((id) => getDocs(collection(db, "groups", id, "weeks"))),
      );
      for (const snapshot of snapshots) {
        for (const week of snapshot.docs) {
          const status = week.data().status as WeekStatus | undefined;
          const key: WeekStatus | "unknown" =
            status && WEEK_STATUSES.includes(status) ? status : "unknown";
          next[key] += 1;
          total += 1;
        }
      }
      setTally(next);
      setWeekTotal(total);
      setScannedGroups(scoped.length);
    } catch (error) {
      setScanError(describeError(error));
    } finally {
      setScanning(false);
    }
  }, []);

  // Runs once per set of group ids; the listener updating a group name will not
  // retrigger it because only the ids are compared.
  const idKey = groupIds.join(",");
  useEffect(() => {
    if (!idKey) return;
    void scanWeeks(idKey.split(","));
  }, [idKey, scanWeeks]);

  const auditColumns: Column<WithId<AuditEntryDoc>>[] = [
    {
      key: "action",
      header: "Action",
      render: (row) => <span className="font-medium text-slate-100">{row.action ?? "—"}</span>,
    },
    {
      key: "actor",
      header: "Actor",
      render: (row) => <span className="text-slate-400">{row.actorEmail ?? row.actorUid ?? "—"}</span>,
    },
    {
      key: "target",
      header: "Target",
      render: (row) => (
        <code className="font-mono text-xs text-slate-400">{truncate(row.targetPath ?? "—", 56)}</code>
      ),
    },
    {
      key: "when",
      header: "When",
      render: (row) => <span className="text-slate-500">{formatRelative(row.createdAt)}</span>,
    },
  ];

  return (
    <>
      <PageHeader
        title="Dashboard"
        subtitle="Live counts straight from Firestore. Nothing here is cached."
        actions={
          <Button pending={scanning} onClick={() => void scanWeeks(groupIds)}>
            Rescan weeks
          </Button>
        }
      />

      <ErrorBanner error={groups.error ?? countError ?? scanError} />

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile
          label="Groups"
          value={groups.loading && groupCount === 0 ? "…" : groupCount}
          hint="Unscoped list — only the admin claim permits it"
        />
        <StatTile label="Users" value={userCount ?? "…"} hint="users/ collection count" />
        <StatTile
          label="Public leagues"
          value={groups.data.filter((group) => group.isPublic === true).length}
          hint="isPublic == true"
        />
        <StatTile
          label="Weeks"
          value={tally ? weekTotal : "…"}
          hint={
            scannedGroups > 0 && groupCount > scannedGroups
              ? `first ${scannedGroups} of ${groupCount} groups`
              : "across every group"
          }
        />
      </div>

      <Card title="Weeks by status" description="A week stuck in the wrong status is the usual support ticket.">
        {tally ? (
          <div className="flex flex-wrap gap-4">
            {(["selection", "picking", "locked", "scored"] as WeekStatus[]).map((status) => (
              <div key={status} className="flex items-center gap-2">
                <WeekStatusBadge status={status} />
                <span className="text-lg font-semibold text-slate-100">{tally[status]}</span>
              </div>
            ))}
            {tally.unknown > 0 ? (
              <div className="flex items-center gap-2">
                <Badge tone="danger">no status</Badge>
                <span className="text-lg font-semibold text-slate-100">{tally.unknown}</span>
              </div>
            ) : null}
          </div>
        ) : (
          <EmptyState>{scanning ? "Scanning…" : "No weeks found."}</EmptyState>
        )}
        {tally && tally.unknown > 0 ? (
          <div className="mt-4">
            <Banner tone="warning" title="Weeks with no status">
              Check <Link className="underline" to="/audit/weeks">Week audit</Link> — these are the
              docs that split nominations across two weeks (Risk R1).
            </Banner>
          </div>
        ) : null}
      </Card>

      <Card
        title="Recent admin actions"
        description="Append-only; even an admin cannot rewrite an entry."
        actions={
          <Link to="/audit/log" className="text-sm text-slate-400 underline hover:text-slate-200">
            Full log
          </Link>
        }
      >
        <DataTable
          columns={auditColumns}
          rows={audit.data}
          rowKey={(row) => row.id}
          loading={audit.loading}
          empty="No admin actions recorded yet."
        />
        <ErrorBanner error={audit.error} />
      </Card>
    </>
  );
}
