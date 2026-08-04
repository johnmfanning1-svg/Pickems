import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { Badge, WeekStatusBadge } from "@/components/Badge";
import { Banner, ErrorBanner } from "@/components/Banner";
import { Button } from "@/components/Button";
import { Card, EmptyState, PageHeader } from "@/components/Card";
import { Select } from "@/components/Fields";
import { useConfirm } from "@/components/useConfirm";
import { pickForUser, useGroup, useMembers, usePicks, useSlateGames, useWeek } from "@/hooks/queries";
import { useAction } from "@/hooks/useAction";
import type { WithId } from "@/hooks/useFirestore";
import { adminRescoreWeek, adminScoreWeek, adminUpsertPick } from "@/lib/callables";
import { favoriteSpreadLabel, formatTimestamp } from "@/lib/format";
import type { MemberDoc, SlateGameDoc } from "@/lib/types";

type PickDraft = Record<string, Record<string, string>>;

export function WeekPicksPage() {
  const { id: groupId, weekId } = useParams<{ id: string; weekId: string }>();
  const { data: group } = useGroup(groupId);
  const week = useWeek(groupId, weekId);
  const games = useSlateGames(groupId, weekId);
  const members = useMembers(groupId);
  const picks = usePicks(groupId, weekId);
  const action = useAction();
  const { confirm, dialog } = useConfirm();

  const [drafts, setDrafts] = useState<PickDraft>({});
  const [confidenceDrafts, setConfidenceDrafts] = useState<Record<string, string>>({});

  if (!groupId || !weekId) return <Banner tone="error" title="Missing group or week id" />;
  const groupName = group?.name ?? groupId;

  function currentPicks(userId: string): Record<string, string> {
    const stored = pickForUser(picks.data, userId)?.picks ?? {};
    return { ...stored, ...(drafts[userId] ?? {}) };
  }

  function hasDraft(userId: string): boolean {
    return drafts[userId] != null || confidenceDrafts[userId] != null;
  }

  function setCell(userId: string, gameId: string, teamId: string) {
    setDrafts((previous) => ({
      ...previous,
      [userId]: { ...(previous[userId] ?? {}), [gameId]: teamId },
    }));
  }

  function discardDraft(userId: string) {
    setDrafts((previous) => {
      const next = { ...previous };
      delete next[userId];
      return next;
    });
    setConfidenceDrafts((previous) => {
      const next = { ...previous };
      delete next[userId];
      return next;
    });
  }

  /** Cell outcome once a game is final — the fast read on "did this member cover". */
  function outcome(game: WithId<SlateGameDoc>, teamId: string | undefined) {
    if (!teamId || game.status !== "final" || !game.winnerTeamId) return null;
    return game.winnerTeamId === teamId ? "win" : "loss";
  }

  async function savePicks(member: WithId<MemberDoc>, isLocked: boolean | undefined) {
    const merged = currentPicks(member.id);
    // A blank select means "no pick", which is an absent key, not an empty value.
    const cleaned = Object.fromEntries(
      Object.entries(merged).filter(([, teamId]) => typeof teamId === "string" && teamId.length > 0),
    );
    const existing = pickForUser(picks.data, member.id);
    const confidence =
      confidenceDrafts[member.id] ?? existing?.confidenceGameId ?? "";

    // `adminUpsertPick` writes with `set({ merge: true })`, and Firestore
    // deep-merges map fields — so an omitted game keeps its stored pick. Adding
    // and changing picks works; clearing one does not.
    const cleared = Object.keys(existing?.picks ?? {}).filter((gameId) => !cleaned[gameId]);

    if (!(await confirm({
      title: "Write this member's picks?",
      body: (
        <>
          <p>
            Overwrites the pick doc for <strong>{member.displayName ?? member.id}</strong> in{" "}
            <strong>{groupName}</strong>, week <code className="font-mono">{weekId}</code> with{" "}
            {Object.keys(cleaned).length} selection(s). Standings do not change until the week is
            rescored.
          </p>
          {cleared.length > 0 ? (
            <p className="mt-2 text-amber-300">
              {cleared.length} cell(s) were blanked, but blanking cannot remove a pick: the callable
              merges the picks map, so those games keep the team already stored. Change them to the
              other team instead, or clear them in the Firebase console.
            </p>
          ) : null}
        </>
      ),
      tone: "primary",
      confirmLabel: "Write picks",
    }))) {
      return;
    }

    await action.run(`pick:${member.id}`, async () => {
      await adminUpsertPick({
        groupId: groupId!,
        weekId: weekId!,
        userId: member.id,
        picks: cleaned,
        isLocked: isLocked ?? existing?.isLocked ?? false,
        confidenceGameId: confidence === "" ? null : confidence,
      });
      discardDraft(member.id);
      return `Picks written for ${member.displayName ?? member.id}.`;
    });
  }

  async function toggleLock(member: WithId<MemberDoc>) {
    const existing = pickForUser(picks.data, member.id);
    const nextLocked = !(existing?.isLocked === true);
    if (!(await confirm({
      title: nextLocked ? "Lock this member's picks?" : "Unlock this member's picks?",
      body: nextLocked ? (
        <>
          Marks <strong>{member.displayName ?? member.id}</strong> as submitted. The submission mirror
          other members can see is updated too.
        </>
      ) : (
        <>
          Lets <strong>{member.displayName ?? member.id}</strong> edit picks again, even after the
          deadline. Their submitted timestamp is cleared.
        </>
      ),
      tone: "primary",
      confirmLabel: nextLocked ? "Lock" : "Unlock",
    }))) {
      return;
    }
    await action.run(`lock:${member.id}`, async () => {
      await adminUpsertPick({
        groupId: groupId!,
        weekId: weekId!,
        userId: member.id,
        picks: existing?.picks ?? {},
        isLocked: nextLocked,
      });
      return nextLocked ? "Picks locked." : "Picks unlocked.";
    });
  }

  async function rescore() {
    if (!(await confirm({
      title: "Rescore this week?",
      body: (
        <>
          Recomputes week results, awards, and standings for <strong>{groupName}</strong> week{" "}
          <code className="font-mono">{weekId}</code>. Season records are re-summed from every scored
          week rather than incremented, so running this twice is safe.
        </>
      ),
      tone: "primary",
      confirmLabel: "Rescore",
    }))) {
      return;
    }
    await action.run("rescore", async () => {
      const result = await adminRescoreWeek({ groupId: groupId!, weekId: weekId! });
      return `Rescored ${result.entries.length} member(s) across ${result.weeksSummed} week(s).`;
    });
  }

  async function scoreAndFinalize() {
    if (!(await confirm({
      title: "Score and finalize this week?",
      body: (
        <>
          Scores <strong>{groupName}</strong> week <code className="font-mono">{weekId}</code> from its
          current games, updates awards and standings, and sets the week status to{" "}
          <code className="font-mono">scored</code> — the same thing the scheduler does once every game
          is final. Only final games contribute, and season records are re-summed, so running it again
          is safe.
        </>
      ),
      tone: "primary",
      confirmLabel: "Score & finalize",
    }))) {
      return;
    }
    await action.run("finalize", async () => {
      const result = await adminScoreWeek({ groupId: groupId!, weekId: weekId! });
      return `Week finalized — scored ${result.entries.length} member(s) across ${result.weeksSummed} week(s).`;
    });
  }

  const loading = week.loading || games.loading || members.loading || picks.loading;

  return (
    <>
      {dialog}
      <PageHeader
        title={`${groupName} — week ${weekId}`}
        subtitle={
          <span className="flex flex-wrap items-center gap-2">
            <WeekStatusBadge status={week.data?.status} />
            <span>
              {games.data.length} game(s) · {members.data.length} member(s) · deadline{" "}
              {formatTimestamp(week.data?.pickDeadline)}
            </span>
          </span>
        }
        actions={
          <>
            <Link
              to={`/groups/${groupId}/weeks`}
              className="text-sm text-slate-400 underline hover:text-slate-200"
            >
              All weeks
            </Link>
            <Button
              pending={action.isPending("rescore")}
              disabled={action.busy}
              onClick={() => void rescore()}
            >
              Rescore week
            </Button>
            <Button
              variant="primary"
              pending={action.isPending("finalize")}
              disabled={action.busy}
              onClick={() => void scoreAndFinalize()}
            >
              Score &amp; finalize
            </Button>
          </>
        }
      />

      <ErrorBanner
        error={week.error ?? games.error ?? members.error ?? picks.error ?? action.error}
        onDismiss={action.clearError}
      />
      {action.message ? (
        <Banner tone="success" onDismiss={action.clearMessage}>
          {action.message}
        </Banner>
      ) : null}

      {!week.exists && !week.loading ? (
        <Banner tone="error" title="No week doc">
          <code className="font-mono">
            groups/{groupId}/weeks/{weekId}
          </code>{" "}
          does not exist.
        </Banner>
      ) : null}

      {games.data.length === 0 && !loading ? (
        <EmptyState>
          No games in this slate yet. Materialize the slate from the Weeks tab before editing picks.
        </EmptyState>
      ) : (
        <Card
          title="Picks grid"
          description="Members down, slate games across. A blank cell is no pick at all, not an empty pick."
        >
          <div className="-mx-4 overflow-x-auto px-4">
            <table className="min-w-full border-separate border-spacing-0 text-sm">
              <thead>
                <tr>
                  <th
                    scope="col"
                    className="sticky left-0 z-20 border-b border-ink-600 bg-ink-800 px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-400"
                  >
                    Member
                  </th>
                  {games.data.map((game) => (
                    <th
                      key={game.id}
                      scope="col"
                      className="border-b border-ink-600 bg-ink-800 px-2 py-2 text-left text-xs font-semibold text-slate-400"
                    >
                      <span className="block whitespace-nowrap text-slate-300">
                        {game.awayTeamAbbreviation} @ {game.homeTeamAbbreviation}
                      </span>
                      <span className="block whitespace-nowrap font-mono text-[10px] text-slate-500">
                        {game.spreadTeamId === game.homeTeamId
                          ? game.homeTeamAbbreviation
                          : game.awayTeamAbbreviation}{" "}
                        {favoriteSpreadLabel(game.spread ?? 0)}
                      </span>
                    </th>
                  ))}
                  <th
                    scope="col"
                    className="border-b border-ink-600 bg-ink-800 px-2 py-2 text-left text-xs font-semibold uppercase tracking-wide text-slate-400"
                  >
                    Confidence
                  </th>
                  <th className="border-b border-ink-600 bg-ink-800 px-2 py-2" />
                </tr>
              </thead>
              <tbody>
                {members.data.map((member) => {
                  const existing = pickForUser(picks.data, member.id);
                  const values = currentPicks(member.id);
                  const dirty = hasDraft(member.id);
                  return (
                    <tr key={member.id} className="hover:bg-ink-700/40">
                      <th
                        scope="row"
                        className="sticky left-0 z-10 border-b border-ink-700 bg-ink-800 px-3 py-2 text-left font-normal"
                      >
                        <span className="block font-medium text-slate-100">
                          {member.displayName ?? member.id}
                        </span>
                        <span className="mt-0.5 flex items-center gap-2">
                          {existing?.isLocked === true ? (
                            <Badge tone="success">submitted</Badge>
                          ) : (
                            <Badge tone="warning">open</Badge>
                          )}
                          <span className="text-xs text-slate-500">
                            {Object.keys(existing?.picks ?? {}).length}/{games.data.length}
                          </span>
                        </span>
                      </th>

                      {games.data.map((game) => {
                        const value = values[game.id] ?? "";
                        const result = outcome(game, value || undefined);
                        return (
                          <td key={game.id} className="border-b border-ink-700 px-2 py-2">
                            <Select
                              value={value}
                              disabled={action.busy}
                              className={`w-28 ${
                                result === "win"
                                  ? "border-emerald-700 text-emerald-300"
                                  : result === "loss"
                                    ? "border-red-800 text-red-300"
                                    : ""
                              }`}
                              onChange={(event) => setCell(member.id, game.id, event.target.value)}
                            >
                              <option value="">—</option>
                              <option value={game.awayTeamId}>{game.awayTeamAbbreviation}</option>
                              <option value={game.homeTeamId}>{game.homeTeamAbbreviation}</option>
                            </Select>
                          </td>
                        );
                      })}

                      <td className="border-b border-ink-700 px-2 py-2">
                        <Select
                          value={confidenceDrafts[member.id] ?? existing?.confidenceGameId ?? ""}
                          disabled={action.busy}
                          className="w-32"
                          onChange={(event) =>
                            setConfidenceDrafts((previous) => ({
                              ...previous,
                              [member.id]: event.target.value,
                            }))
                          }
                        >
                          <option value="">none</option>
                          {games.data.map((game) => (
                            <option key={game.id} value={game.id}>
                              {game.awayTeamAbbreviation} @ {game.homeTeamAbbreviation}
                            </option>
                          ))}
                        </Select>
                      </td>

                      <td className="border-b border-ink-700 px-2 py-2">
                        <div className="flex justify-end gap-2 whitespace-nowrap">
                          <Button
                            variant="primary"
                            pending={action.isPending(`pick:${member.id}`)}
                            disabled={action.busy || !dirty}
                            onClick={() => void savePicks(member, existing?.isLocked)}
                          >
                            Save
                          </Button>
                          {dirty ? (
                            <Button variant="ghost" onClick={() => discardDraft(member.id)}>
                              Reset
                            </Button>
                          ) : null}
                          <Button
                            pending={action.isPending(`lock:${member.id}`)}
                            disabled={action.busy}
                            onClick={() => void toggleLock(member)}
                          >
                            {existing?.isLocked === true ? "Unlock" : "Lock"}
                          </Button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          {members.data.length === 0 && !loading ? (
            <EmptyState>No member docs in this league.</EmptyState>
          ) : null}
        </Card>
      )}
    </>
  );
}
