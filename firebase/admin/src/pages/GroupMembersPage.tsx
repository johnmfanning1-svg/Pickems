import { arrayUnion, doc, getDoc, serverTimestamp, setDoc, updateDoc } from "firebase/firestore";
import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { Badge } from "@/components/Badge";
import { Banner, ErrorBanner } from "@/components/Banner";
import { Button } from "@/components/Button";
import { Card, PageHeader } from "@/components/Card";
import { DataTable, type Column } from "@/components/DataTable";
import { Field, TextInput } from "@/components/Fields";
import { GroupTabs } from "@/components/GroupTabs";
import { useConfirm } from "@/components/useConfirm";
import { useGroup, useMembers } from "@/hooks/queries";
import { useAction } from "@/hooks/useAction";
import type { WithId } from "@/hooks/useFirestore";
import { writeAudit } from "@/lib/audit";
import { adminRemoveMember, adminTransferCommissioner } from "@/lib/callables";
import { db } from "@/lib/firebase";
import { formatTimestamp, record } from "@/lib/format";
import type { MemberDoc, UserDoc } from "@/lib/types";

export function GroupMembersPage() {
  const { id: groupId } = useParams<{ id: string }>();
  const { data: group, error: groupError } = useGroup(groupId);
  const members = useMembers(groupId);
  const action = useAction();
  const { confirm, dialog } = useConfirm();
  const [newUserId, setNewUserId] = useState("");

  if (!groupId) return <Banner tone="error" title="Missing group id" />;

  const groupName = group?.name ?? groupId;
  const memberIds = group?.memberIds ?? [];

  /**
   * Members in `memberIds` with no member doc (or the reverse) are exactly the
   * drift that makes a league look broken in the app, so both directions show up
   * in the table rather than only the docs that happen to exist.
   */
  const orphanIds = memberIds.filter((id) => !members.data.some((member) => member.id === id));
  const missingFromArray = members.data.filter((member) => !memberIds.includes(member.id));

  async function addMember() {
    const uid = newUserId.trim();
    if (!uid) return;
    const profileSnap = await getDoc(doc(db, "users", uid)).catch(() => null);
    const profile = profileSnap?.data() as UserDoc | undefined;
    if (!profileSnap?.exists()) {
      const proceed = await confirm({
        title: "No user profile found",
        body: (
          <>
            There is no <code className="font-mono">users/{uid}</code> doc. Adding this uid anyway
            creates a member with the placeholder name <strong>Unknown</strong>. Double-check the uid
            first — a typo here puts a ghost member in the standings.
          </>
        ),
        confirmLabel: "Add anyway",
      });
      if (!proceed) return;
    }

    await action.run("add", async () => {
      const displayName = profile?.displayName ?? "Unknown";
      await setDoc(
        doc(db, "groups", groupId!, "members", uid),
        {
          id: uid,
          displayName,
          avatarColorHex: profile?.avatarColorHex ?? "#DC2626",
          role: "member",
          joinedAt: serverTimestamp(),
          seasonWins: 0,
          seasonLosses: 0,
        },
        { merge: true },
      );
      await updateDoc(doc(db, "groups", groupId!), { memberIds: arrayUnion(uid) });
      await writeAudit("adminAddMember", `groups/${groupId}/members/${uid}`, null, {
        userId: uid,
        displayName,
      });
      setNewUserId("");
      return `${displayName} added.`;
    });
  }

  async function removeMember(member: WithId<MemberDoc>) {
    if (!(await confirm({
      title: "Remove this member?",
      body: (
        <>
          Removes <strong>{member.displayName ?? member.id}</strong> from <strong>{groupName}</strong> and
          deletes their member, career, pick, and submission docs across every week. Their season
          record cannot be recovered.
        </>
      ),
      confirmLabel: "Remove member",
      requireText: member.displayName || member.id,
    }))) {
      return;
    }
    await action.run(`remove:${member.id}`, async () => {
      const result = await adminRemoveMember({ groupId: groupId!, userId: member.id });
      return `Removed — cleaned ${result.weeksCleaned} week(s).`;
    });
  }

  async function transferCommissioner(member: WithId<MemberDoc>) {
    if (!(await confirm({
      title: "Transfer the commissioner role?",
      body: (
        <>
          <strong>{member.displayName ?? member.id}</strong> becomes commissioner of{" "}
          <strong>{groupName}</strong> and gains slate and deadline control. The current commissioner is
          demoted to member.
        </>
      ),
      tone: "primary",
      confirmLabel: "Transfer",
    }))) {
      return;
    }
    await action.run(`transfer:${member.id}`, async () => {
      await adminTransferCommissioner({ groupId: groupId!, userId: member.id });
      return `${member.displayName ?? member.id} is now commissioner.`;
    });
  }

  async function resetRecord(member: WithId<MemberDoc>) {
    if (!(await confirm({
      title: "Reset season record?",
      body: (
        <>
          Sets <strong>{member.displayName ?? member.id}</strong> to 0-0 for the current season in{" "}
          <strong>{groupName}</strong>. Standings keep the old numbers until a week is rescored.
        </>
      ),
      confirmLabel: "Reset to 0-0",
    }))) {
      return;
    }
    await action.run(`reset:${member.id}`, async () => {
      await updateDoc(doc(db, "groups", groupId!, "members", member.id), {
        seasonWins: 0,
        seasonLosses: 0,
      });
      await writeAudit(
        "adminResetMemberRecord",
        `groups/${groupId}/members/${member.id}`,
        { seasonWins: member.seasonWins ?? 0, seasonLosses: member.seasonLosses ?? 0 },
        { seasonWins: 0, seasonLosses: 0 },
      );
      return "Season record reset.";
    });
  }

  const columns: Column<WithId<MemberDoc>>[] = [
    {
      key: "member",
      header: "Member",
      render: (member) => (
        <div className="min-w-0">
          <p className="font-medium text-slate-100">{member.displayName ?? "(no name)"}</p>
          <p className="font-mono text-xs text-slate-500">{member.id}</p>
        </div>
      ),
    },
    {
      key: "role",
      header: "Role",
      render: (member) =>
        group?.commissionerId === member.id ? (
          <Badge tone="success">commissioner</Badge>
        ) : (
          <Badge>{member.role ?? "member"}</Badge>
        ),
    },
    {
      key: "record",
      header: "Season",
      render: (member) => record(member.seasonWins, member.seasonLosses),
    },
    {
      key: "joined",
      header: "Joined",
      render: (member) => <span className="text-slate-500">{formatTimestamp(member.joinedAt)}</span>,
    },
    {
      key: "sync",
      header: "memberIds",
      render: (member) =>
        memberIds.includes(member.id) ? (
          <Badge tone="success">in array</Badge>
        ) : (
          <Badge tone="danger">missing</Badge>
        ),
    },
    {
      key: "actions",
      header: "",
      className: "text-right",
      render: (member) => (
        <div className="flex justify-end gap-2 whitespace-nowrap">
          <Button
            pending={action.isPending(`transfer:${member.id}`)}
            disabled={action.busy || group?.commissionerId === member.id}
            onClick={() => void transferCommissioner(member)}
          >
            Make commissioner
          </Button>
          <Button
            pending={action.isPending(`reset:${member.id}`)}
            disabled={action.busy}
            onClick={() => void resetRecord(member)}
          >
            Reset W-L
          </Button>
          <Button
            variant="danger"
            pending={action.isPending(`remove:${member.id}`)}
            disabled={action.busy || group?.commissionerId === member.id}
            onClick={() => void removeMember(member)}
          >
            Remove
          </Button>
        </div>
      ),
    },
  ];

  return (
    <>
      {dialog}
      <PageHeader
        title={`${groupName} — members`}
        subtitle={`${members.data.length} member docs · ${memberIds.length} ids in memberIds`}
        actions={
          <Link to={`/groups/${groupId}`} className="text-sm text-slate-400 underline hover:text-slate-200">
            Overview
          </Link>
        }
      />
      <GroupTabs groupId={groupId} />
      <ErrorBanner error={groupError ?? members.error ?? action.error} onDismiss={action.clearError} />
      {action.message ? (
        <Banner tone="success" onDismiss={action.clearMessage}>
          {action.message}
        </Banner>
      ) : null}

      {orphanIds.length > 0 ? (
        <Banner tone="warning" title="Ids in memberIds with no member doc">
          <code className="font-mono text-xs">{orphanIds.join(", ")}</code> — these users count toward
          member totals but have no profile in the league. Removing them requires the callable, which
          also strips the id from the array.
        </Banner>
      ) : null}
      {missingFromArray.length > 0 ? (
        <Banner tone="warning" title="Member docs missing from memberIds">
          {missingFromArray.map((member) => member.displayName ?? member.id).join(", ")} — rules gate
          reads on <code className="font-mono">memberIds</code>, so these members cannot see the league
          until the array is repaired.
        </Banner>
      ) : null}

      <Card title="Members">
        <DataTable
          columns={columns}
          rows={members.data}
          rowKey={(member) => member.id}
          loading={members.loading}
          empty="No member docs in this league."
        />
      </Card>

      <Card
        title="Add a member"
        description="By Auth uid — the client cannot look accounts up by email. Copy the uid from Firebase Auth or the users collection."
      >
        <div className="flex flex-wrap items-end gap-3">
          <Field label="User id">
            <TextInput
              value={newUserId}
              onChange={(event) => setNewUserId(event.target.value)}
              placeholder="firebase auth uid"
              className="w-80 font-mono"
            />
          </Field>
          <Button
            variant="primary"
            pending={action.isPending("add")}
            disabled={action.busy || !newUserId.trim()}
            onClick={() => void addMember()}
          >
            Add member
          </Button>
        </div>
      </Card>
    </>
  );
}
