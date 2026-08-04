import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { Badge } from "@/components/Badge";
import { ErrorBanner } from "@/components/Banner";
import { PageHeader } from "@/components/Card";
import { DataTable, type Column } from "@/components/DataTable";
import { TextInput } from "@/components/Fields";
import { useGroups } from "@/hooks/queries";
import type { WithId } from "@/hooks/useFirestore";
import { formatTimestamp } from "@/lib/format";
import type { GroupDoc } from "@/lib/types";

export function GroupsPage() {
  const { data, loading, error } = useGroups();
  const [search, setSearch] = useState("");

  const rows = useMemo(() => {
    const needle = search.trim().toLowerCase();
    if (!needle) return data;
    return data.filter((group) =>
      [group.name, group.inviteCode, group.id, group.commissionerId]
        .filter((value): value is string => typeof value === "string")
        .some((value) => value.toLowerCase().includes(needle)),
    );
  }, [data, search]);

  const columns: Column<WithId<GroupDoc>>[] = [
    {
      key: "name",
      header: "Group",
      render: (group) => (
        <div className="min-w-0">
          <Link to={`/groups/${group.id}`} className="font-medium text-slate-100 underline-offset-2 hover:underline">
            {group.name || <span className="text-red-400">(no name)</span>}
          </Link>
          <p className="font-mono text-xs text-slate-500">{group.id}</p>
        </div>
      ),
    },
    {
      key: "invite",
      header: "Invite code",
      render: (group) => <code className="font-mono text-slate-300">{group.inviteCode ?? "—"}</code>,
    },
    {
      key: "members",
      header: "Members",
      render: (group) => group.memberIds?.length ?? 0,
    },
    {
      key: "public",
      header: "Visibility",
      render: (group) =>
        group.isPublic === true ? <Badge tone="info">public</Badge> : <Badge>private</Badge>,
    },
    {
      key: "created",
      header: "Created",
      render: (group) => <span className="text-slate-500">{formatTimestamp(group.createdAt)}</span>,
    },
    {
      key: "links",
      header: "",
      className: "text-right",
      render: (group) => (
        <span className="flex justify-end gap-3 whitespace-nowrap text-xs">
          <Link to={`/groups/${group.id}/members`} className="text-slate-400 underline hover:text-slate-200">
            Members
          </Link>
          <Link to={`/groups/${group.id}/weeks`} className="text-slate-400 underline hover:text-slate-200">
            Weeks
          </Link>
        </span>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title="Groups"
        subtitle={`${rows.length} of ${data.length} leagues`}
        actions={
          <TextInput
            type="search"
            placeholder="Search name, code, id…"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            className="w-64"
          />
        }
      />
      <ErrorBanner error={error} />
      <DataTable
        columns={columns}
        rows={rows}
        rowKey={(group) => group.id}
        loading={loading}
        empty={search ? "No leagues match that search." : "No leagues exist yet."}
      />
    </>
  );
}
