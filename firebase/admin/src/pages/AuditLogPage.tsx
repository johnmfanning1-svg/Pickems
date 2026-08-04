import { useMemo, useState } from "react";
import { Banner, ErrorBanner } from "@/components/Banner";
import { Card, PageHeader } from "@/components/Card";
import { DataTable, type Column } from "@/components/DataTable";
import { Field, Select, TextInput } from "@/components/Fields";
import { useAuditLog } from "@/hooks/queries";
import type { WithId } from "@/hooks/useFirestore";
import { formatRelative, formatTimestamp } from "@/lib/format";
import type { AuditEntryDoc } from "@/lib/types";

/** Actions the portal and callables write, so the filter is not a guessing game. */
const KNOWN_ACTIONS = [
  "setAdminRole",
  "adminSetWeekStatus",
  "adminRematerializeNominations",
  "adminUpsertPick",
  "adminRemoveMember",
  "adminTransferCommissioner",
  "adminAuditWeekIds",
  "adminRescoreWeek",
  "adminRenameGroup",
  "adminSetGroupVisibility",
  "adminUpdateGroupRules",
  "adminSetInviteCode",
  "adminDeleteGroup",
  "adminAddMember",
  "adminResetMemberRecord",
  "adminDeleteWeek",
  "adminDeleteOrphanWeek",
  "adminUpdateGameSpread",
  "adminUpdateAppConfig",
  "adminUpdateAppConfigRaw",
  "adminSoftDeleteMessage",
  "adminRestoreMessage",
  "adminDeleteMessage",
];

function JsonCell({ value }: { value: unknown }) {
  if (value == null) return <span className="text-slate-600">—</span>;
  const text = typeof value === "string" ? value : JSON.stringify(value, null, 2);
  if (text.length <= 60) {
    return <code className="font-mono text-xs text-slate-400">{text}</code>;
  }
  return (
    <details>
      <summary className="cursor-pointer text-xs text-slate-500 hover:text-slate-300">
        {text.length} chars
      </summary>
      <pre className="mt-1 max-h-64 max-w-md overflow-auto rounded bg-ink-900 p-2 font-mono text-[11px] text-slate-300">
        {text}
      </pre>
    </details>
  );
}

export function AuditLogPage() {
  const [actionFilter, setActionFilter] = useState("");
  const [search, setSearch] = useState("");
  const { data, loading, error } = useAuditLog(actionFilter || null, 200);

  const rows = useMemo(() => {
    const needle = search.trim().toLowerCase();
    if (!needle) return data;
    return data.filter((entry) =>
      [entry.actorEmail, entry.actorUid, entry.targetPath, entry.action]
        .filter((value): value is string => typeof value === "string")
        .some((value) => value.toLowerCase().includes(needle)),
    );
  }, [data, search]);

  const columns: Column<WithId<AuditEntryDoc>>[] = [
    {
      key: "when",
      header: "When",
      render: (entry) => (
        <div className="whitespace-nowrap">
          <p className="text-slate-200">{formatTimestamp(entry.createdAt)}</p>
          <p className="text-xs text-slate-500">{formatRelative(entry.createdAt)}</p>
        </div>
      ),
    },
    {
      key: "action",
      header: "Action",
      render: (entry) => <span className="font-medium text-slate-100">{entry.action ?? "—"}</span>,
    },
    {
      key: "actor",
      header: "Actor",
      render: (entry) => (
        <div className="min-w-0">
          <p className="text-slate-300">{entry.actorEmail ?? "—"}</p>
          <p className="font-mono text-xs text-slate-500">{entry.actorUid ?? "—"}</p>
        </div>
      ),
    },
    {
      key: "target",
      header: "Target",
      render: (entry) => (
        <code className="break-all font-mono text-xs text-slate-400">{entry.targetPath ?? "—"}</code>
      ),
    },
    { key: "before", header: "Before", render: (entry) => <JsonCell value={entry.before} /> },
    { key: "after", header: "After", render: (entry) => <JsonCell value={entry.after} /> },
  ];

  return (
    <>
      <PageHeader
        title="Audit log"
        subtitle="Append-only. Rules deny update and delete outright, so not even an admin can rewrite history here."
      />
      <ErrorBanner error={error} />
      {error?.includes("index") ? (
        <Banner tone="warning" title="Missing index">
          Filtering by action needs the (action ASC, createdAt DESC) composite index. Deploy it with{" "}
          <code className="font-mono">firebase deploy --only firestore:indexes</code> and wait for it to
          report Enabled.
        </Banner>
      ) : null}

      <Card title="Filter">
        <div className="flex flex-wrap items-end gap-3">
          <Field label="Action" hint="Uses the composite index.">
            <Select
              value={actionFilter}
              className="w-72"
              onChange={(event) => setActionFilter(event.target.value)}
            >
              <option value="">All actions</option>
              {KNOWN_ACTIONS.map((name) => (
                <option key={name} value={name}>
                  {name}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Search" hint="Client-side, over the loaded page.">
            <TextInput
              type="search"
              placeholder="actor, target path…"
              value={search}
              className="w-72"
              onChange={(event) => setSearch(event.target.value)}
            />
          </Field>
        </div>
      </Card>

      <Card title="Entries" description={`${rows.length} of the ${data.length} most recent`}>
        <DataTable
          columns={columns}
          rows={rows}
          rowKey={(entry) => entry.id}
          loading={loading}
          empty="No audit entries match."
        />
      </Card>
    </>
  );
}
