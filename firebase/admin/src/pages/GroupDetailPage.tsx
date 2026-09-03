import { deleteDoc, doc, updateDoc } from "firebase/firestore";
import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { Banner, ErrorBanner } from "@/components/Banner";
import { Button } from "@/components/Button";
import { Card, PageHeader } from "@/components/Card";
import { Field, Select, TextInput, Toggle } from "@/components/Fields";
import { GroupTabs } from "@/components/GroupTabs";
import { FullPageSpinner } from "@/components/Spinner";
import { useConfirm } from "@/components/useConfirm";
import { useGroup } from "@/hooks/queries";
import { useAction } from "@/hooks/useAction";
import { writeAudit } from "@/lib/audit";
import { db } from "@/lib/firebase";
import { formatTimestamp } from "@/lib/format";
import { findFreeInviteCode, setInviteCode } from "@/lib/inviteCodes";
import { DEFAULT_GROUP_RULES, type GroupRules } from "@/lib/types";

export function GroupDetailPage() {
  const { id: groupId } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { data: group, exists, loading, error } = useGroup(groupId);
  const action = useAction();
  const { confirm, dialog } = useConfirm();

  const [name, setName] = useState("");
  const [inviteCode, setInviteCodeValue] = useState("");
  const [rules, setRules] = useState<GroupRules>(DEFAULT_GROUP_RULES);

  // Reseed the forms whenever the listener reports a new version of the doc, so
  // a save (or another admin's edit) leaves the inputs showing reality.
  useEffect(() => {
    if (!group) return;
    setName(group.name ?? "");
    setInviteCodeValue(group.inviteCode ?? "");
    setRules({ ...DEFAULT_GROUP_RULES, ...(group.rules ?? {}) });
  }, [group]);

  if (loading) return <FullPageSpinner label="Loading league…" />;
  if (!groupId) return <Banner tone="error" title="Missing group id" />;
  if (!exists || !group) {
    return (
      <>
        <PageHeader title="League not found" />
        <Banner tone="error" title={`No group doc at groups/${groupId}`}>
          It may have been deleted. <Link className="underline" to="/groups">Back to groups</Link>.
        </Banner>
      </>
    );
  }

  // Non-null past the guards above. The handlers below are hoisted function
  // declarations, so TypeScript will not carry that narrowing into them.
  const league = group;
  const id = groupId;
  const isPublic = league.isPublic === true;

  function setRule<K extends keyof GroupRules>(key: K, value: GroupRules[K]) {
    setRules((previous) => ({ ...previous, [key]: value }));
  }

  async function saveName() {
    const trimmed = name.trim();
    if (!trimmed) {
      return;
    }
    if (!(await confirm({
      title: "Rename league?",
      body: (
        <>
          <strong>{league.name}</strong> becomes <strong>{trimmed}</strong>. Members see the new name
          immediately.
        </>
      ),
      tone: "primary",
      confirmLabel: "Rename",
    }))) {
      return;
    }
    await action.run("name", async () => {
      await updateDoc(doc(db, "groups", id), { name: trimmed });
      await writeAudit("adminRenameGroup", `groups/${groupId}`, { name: league.name }, { name: trimmed });
      return "League renamed.";
    });
  }

  async function togglePublic(next: boolean) {
    if (!(await confirm({
      title: next ? "List league publicly?" : "Remove from Discover?",
      body: (
        <>
          <strong>{league.name}</strong> will {next ? "appear in" : "disappear from"} Discover for every
          signed-in user. The <code className="font-mono">publicLeagues</code> index is updated by the{" "}
          <code className="font-mono">syncPublicLeagueIndex</code> trigger, not by this console.
        </>
      ),
      tone: "primary",
      confirmLabel: next ? "Make public" : "Make private",
    }))) {
      return;
    }
    await action.run("public", async () => {
      await updateDoc(doc(db, "groups", id), { isPublic: next });
      await writeAudit("adminSetGroupVisibility", `groups/${groupId}`, { isPublic }, { isPublic: next });
      return next ? "League is public." : "League is private.";
    });
  }

  async function saveRules() {
    if (!(await confirm({
      title: "Save league rules?",
      body: (
        <>
          Rules drive slate size and deadlines for <strong>{league.name}</strong>. Changing{" "}
          <code className="font-mono">slateSize</code> mid-week does not re-materialize an existing
          slate — use the Weeks tab for that.
        </>
      ),
      tone: "primary",
      confirmLabel: "Save rules",
    }))) {
      return;
    }
    await action.run("rules", async () => {
      const nextRules = {
        ...rules,
        allowLatePicks: rules.pickDeadline === "rolling" ? false : rules.allowLatePicks,
      };
      await updateDoc(doc(db, "groups", id), { rules: nextRules });
      await writeAudit("adminUpdateGroupRules", `groups/${groupId}`, league.rules ?? null, nextRules);
      return "Rules saved.";
    });
  }

  async function applyInviteCode(nextCode: string) {
    const normalized = nextCode.trim().toUpperCase();
    if (!(await confirm({
      title: "Change invite code?",
      body: (
        <>
          Existing invite links for <strong>{league.name}</strong> stop working. New code:{" "}
          <code className="font-mono">{normalized}</code>.
        </>
      ),
      confirmLabel: "Change code",
    }))) {
      return;
    }
    await action.run("invite", async () => {
      await setInviteCode({
        groupId: id,
        newCode: normalized,
        previousCode: league.inviteCode ?? null,
        isPublic,
      });
      await writeAudit(
        "adminSetInviteCode",
        `groups/${groupId}`,
        { inviteCode: league.inviteCode ?? null },
        { inviteCode: normalized },
      );
      setInviteCodeValue(normalized);
      return `Invite code is now ${normalized}.`;
    });
  }

  async function regenerate() {
    await action.run("regenerate", async () => {
      const candidate = await findFreeInviteCode();
      setInviteCodeValue(candidate);
      return `Generated ${candidate} — press Save code to apply it.`;
    });
  }

  async function deleteGroup() {
    if (!(await confirm({
      title: "Delete this league?",
      body: (
        <>
          <p>
            Deletes <strong>{league.name}</strong>, its invite reservation, and its Discover entry.
          </p>
          <p className="mt-2 text-amber-300">
            Subcollections (members, weeks, picks, chat) are <strong>not</strong> removed — a client
            delete cannot recurse. Clean them with the Firebase console or the CLI:
            <code className="mt-1 block font-mono text-xs">
              firebase firestore:delete groups/{groupId} --recursive
            </code>
          </p>
        </>
      ),
      confirmLabel: "Delete league",
      requireText: league.name || id,
    }))) {
      return;
    }
    const succeeded = await action.run("delete", async () => {
      await writeAudit("adminDeleteGroup", `groups/${groupId}`, group, null);
      if (league.inviteCode) {
        await deleteDoc(doc(db, "inviteCodes", league.inviteCode)).catch(() => undefined);
      }
      await deleteDoc(doc(db, "publicLeagues", id)).catch(() => undefined);
      await deleteDoc(doc(db, "groups", id));
    });
    if (succeeded) navigate("/groups", { replace: true });
  }

  return (
    <>
      {dialog}
      <PageHeader
        title={group.name || "(no name)"}
        subtitle={
          <span className="font-mono text-xs">
            groups/{group.id} · commissioner {group.commissionerId ?? "—"} · created{" "}
            {formatTimestamp(group.createdAt)}
          </span>
        }
        actions={
          <Link
            to={`/groups/${groupId}/weeks`}
            className="text-sm text-slate-400 underline hover:text-slate-200"
          >
            Weeks
          </Link>
        }
      />
      <GroupTabs groupId={groupId} />
      <ErrorBanner error={error ?? action.error} onDismiss={action.clearError} />
      {action.message ? (
        <Banner tone="success" onDismiss={action.clearMessage}>
          {action.message}
        </Banner>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="Identity" description="Name and Discover visibility.">
          <div className="space-y-4">
            <Field label="League name">
              <TextInput value={name} onChange={(event) => setName(event.target.value)} />
            </Field>
            <Button
              variant="primary"
              pending={action.isPending("name")}
              disabled={action.busy || name.trim() === (group.name ?? "") || !name.trim()}
              onClick={() => void saveName()}
            >
              Save name
            </Button>

            <Toggle
              label="Listed in Discover"
              hint="Anyone signed in can find and join a public league."
              checked={isPublic}
              disabled={action.busy}
              onChange={(next) => void togglePublic(next)}
            />
          </div>
        </Card>

        <Card title="Invite code" description="Uniqueness is held by inviteCodes/{code}.">
          <div className="space-y-4">
            <Field label="Code" hint="4–8 characters, A–Z and 0–9.">
              <TextInput
                value={inviteCode}
                onChange={(event) => setInviteCodeValue(event.target.value.toUpperCase())}
                className="font-mono uppercase"
              />
            </Field>
            <div className="flex flex-wrap gap-2">
              <Button
                variant="primary"
                pending={action.isPending("invite")}
                disabled={action.busy || inviteCode.trim().toUpperCase() === (group.inviteCode ?? "")}
                onClick={() => void applyInviteCode(inviteCode)}
              >
                Save code
              </Button>
              <Button
                pending={action.isPending("regenerate")}
                disabled={action.busy}
                onClick={() => void regenerate()}
              >
                Generate random
              </Button>
            </div>
          </div>
        </Card>

        <Card
          title="League rules"
          description="Mirrors GroupRules on iOS — a field renamed there must be renamed here."
          className="lg:col-span-2"
        >
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Field label="Selection mode">
              <Select
                value={rules.selectionMode}
                onChange={(event) => setRule("selectionMode", event.target.value as GroupRules["selectionMode"])}
              >
                <option value="member">member — everyone nominates</option>
                <option value="commissioner">commissioner — commissioner picks the slate</option>
              </Select>
            </Field>
            {rules.selectionMode === "member" ? (
              <Field
                label="Nominations per member"
                hint="Either/or with slate size. Weekly target = members × this value."
              >
                <TextInput
                  type="number"
                  min={1}
                  max={20}
                  value={rules.selectionsPerMember}
                  onChange={(event) => setRule("selectionsPerMember", Number(event.target.value))}
                />
              </Field>
            ) : (
              <Field label="Games per week (slate size)" hint="Either/or with nominations per member.">
                <TextInput
                  type="number"
                  min={1}
                  max={40}
                  value={rules.slateSize}
                  onChange={(event) => setRule("slateSize", Number(event.target.value))}
                />
              </Field>
            )}
            <Field label="Deadline policy" hint="firstKickoff locks the whole slate at the earliest kickoff. rolling locks each game at its own kickoff. Applies when the next week opens.">
              <Select
                value={rules.pickDeadline}
                onChange={(event) => {
                  const next = event.target.value as GroupRules["pickDeadline"];
                  setRules((previous) => ({
                    ...previous,
                    pickDeadline: next,
                    allowLatePicks: next === "rolling" ? false : previous.allowLatePicks,
                  }));
                }}
              >
                <option value="firstKickoff">firstKickoff (entire slate)</option>
                <option value="rolling">rolling (each game at kickoff)</option>
                {rules.pickDeadline === "custom" && (
                  <option value="custom">custom (legacy)</option>
                )}
              </Select>
            </Field>
            <Field label="Custom deadline hour" hint="Only used if policy is custom.">
              <TextInput
                type="number"
                min={0}
                max={23}
                value={rules.customDeadlineHour}
                onChange={(event) => setRule("customDeadlineHour", Number(event.target.value))}
              />
            </Field>
            <Field label="Custom deadline minute">
              <TextInput
                type="number"
                min={0}
                max={59}
                value={rules.customDeadlineMinute}
                onChange={(event) => setRule("customDeadlineMinute", Number(event.target.value))}
              />
            </Field>
            <Field label="Tie breaker">
              <Select
                value={rules.tieBreaker}
                onChange={(event) => setRule("tieBreaker", event.target.value as GroupRules["tieBreaker"])}
              >
                <option value="commissionerOverride">commissionerOverride</option>
                <option value="headToHead">headToHead</option>
              </Select>
            </Field>
            {rules.pickDeadline !== "rolling" && (
              <Field label="Late pick penalty (wins)">
                <TextInput
                  type="number"
                  min={0}
                  max={10}
                  value={rules.latePickPenaltyWins}
                  onChange={(event) => setRule("latePickPenaltyWins", Number(event.target.value))}
                />
              </Field>
            )}
            <div className="space-y-1 pt-5">
              <Toggle
                label="Allow confidence pick"
                hint="One double-weight game per member."
                checked={rules.allowConfidencePick}
                onChange={(next) => setRule("allowConfidencePick", next)}
              />
              {rules.pickDeadline !== "rolling" && (
                <Toggle
                  label="Allow late picks"
                  hint="After the first kickoff, with a win penalty. Not available in rolling lock."
                  checked={rules.allowLatePicks}
                  onChange={(next) => setRule("allowLatePicks", next)}
                />
              )}
            </div>
          </div>
          <div className="mt-4">
            <Button
              variant="primary"
              pending={action.isPending("rules")}
              disabled={action.busy}
              onClick={() => void saveRules()}
            >
              Save rules
            </Button>
          </div>
        </Card>

        <Card title="Danger zone" description="Irreversible." className="lg:col-span-2 border-red-900/60">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <p className="text-sm text-slate-400">
              Deleting removes the group doc, its invite reservation, and its Discover entry.
              Subcollections must be cleaned separately.
            </p>
            <Button
              variant="danger"
              pending={action.isPending("delete")}
              disabled={action.busy}
              onClick={() => void deleteGroup()}
            >
              Delete league
            </Button>
          </div>
        </Card>
      </div>
    </>
  );
}
