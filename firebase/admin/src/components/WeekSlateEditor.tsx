import { doc, updateDoc } from "firebase/firestore";
import { useState } from "react";
import { Badge } from "./Badge";
import { Banner, ErrorBanner } from "./Banner";
import { Button } from "./Button";
import { DataTable, type Column } from "./DataTable";
import { Select, TextInput } from "./Fields";
import { useConfirm } from "./useConfirm";
import { useNominations, useSlateGames } from "@/hooks/queries";
import { useAction } from "@/hooks/useAction";
import type { WithId } from "@/hooks/useFirestore";
import { writeAudit } from "@/lib/audit";
import { db } from "@/lib/firebase";
import { favoriteSpreadLabel, formatTimestamp, matchupLabel } from "@/lib/format";
import type { SlateGameDoc } from "@/lib/types";

/**
 * Spread editor for one week's materialized slate.
 *
 * `spread` and `spreadTeamId` are a pair: the number is a magnitude and the id
 * says who it applies to, exactly as `SlateGame.spreadLabel(for:)` reads them on
 * iOS. Editing one without the other flips the favourite, so both are saved
 * together and previewed before saving.
 */
export function WeekSlateEditor({ groupId, weekId }: { groupId: string; weekId: string }) {
  const games = useSlateGames(groupId, weekId);
  const nominations = useNominations(groupId, weekId);
  const action = useAction();
  const { confirm, dialog } = useConfirm();
  const [edits, setEdits] = useState<Record<string, { spread: string; spreadTeamId: string }>>({});

  function editFor(game: WithId<SlateGameDoc>) {
    return (
      edits[game.id] ?? {
        spread: String(game.spread ?? 0),
        spreadTeamId: game.spreadTeamId ?? game.homeTeamId,
      }
    );
  }

  function setEdit(gameId: string, patch: Partial<{ spread: string; spreadTeamId: string }>) {
    setEdits((previous) => {
      const current = previous[gameId];
      if (!current) return previous;
      return { ...previous, [gameId]: { ...current, ...patch } };
    });
  }

  function beginEdit(game: WithId<SlateGameDoc>) {
    setEdits((previous) => ({
      ...previous,
      [game.id]: {
        spread: String(game.spread ?? 0),
        spreadTeamId: game.spreadTeamId ?? game.homeTeamId,
      },
    }));
  }

  async function saveSpread(game: WithId<SlateGameDoc>) {
    const edit = editFor(game);
    const spread = Number(edit.spread);
    if (!Number.isFinite(spread)) {
      return;
    }
    if (!(await confirm({
      title: "Change this line?",
      body: (
        <>
          {matchupLabel(game.awayTeamAbbreviation, game.homeTeamAbbreviation)} becomes{" "}
          <strong>
            {edit.spreadTeamId === game.homeTeamId ? game.homeTeamAbbreviation : game.awayTeamAbbreviation}{" "}
            {favoriteSpreadLabel(spread)}
          </strong>
          . Scoring for this game is recomputed from the new line the next time the week is scored or
          rescored — picks already made are not changed.
        </>
      ),
      tone: "primary",
      confirmLabel: "Save line",
    }))) {
      return;
    }
    await action.run(`spread:${game.id}`, async () => {
      await updateDoc(doc(db, "groups", groupId, "weeks", weekId, "games", game.id), {
        spread: Math.abs(spread),
        spreadTeamId: edit.spreadTeamId,
      });
      await writeAudit(
        "adminUpdateGameSpread",
        `groups/${groupId}/weeks/${weekId}/games/${game.id}`,
        { spread: game.spread, spreadTeamId: game.spreadTeamId },
        { spread: Math.abs(spread), spreadTeamId: edit.spreadTeamId },
      );
      setEdits((previous) => {
        const next = { ...previous };
        delete next[game.id];
        return next;
      });
      return "Line updated.";
    });
  }

  const columns: Column<WithId<SlateGameDoc>>[] = [
    {
      key: "matchup",
      header: "Matchup",
      render: (game) => (
        <div className="min-w-0">
          <p className="text-slate-100">
            {matchupLabel(game.awayTeamName ?? game.awayTeamAbbreviation, game.homeTeamName ?? game.homeTeamAbbreviation)}
          </p>
          <p className="font-mono text-xs text-slate-500">
            {game.id} · espn {game.espnEventId ?? "—"}
          </p>
        </div>
      ),
    },
    {
      key: "kickoff",
      header: "Kickoff",
      render: (game) => <span className="text-slate-400">{formatTimestamp(game.kickoff)}</span>,
    },
    {
      key: "status",
      header: "Status",
      render: (game) => (
        <div className="space-y-1">
          <Badge tone={game.status === "final" ? "success" : game.status === "inProgress" ? "warning" : "neutral"}>
            {game.status ?? "—"}
          </Badge>
          {game.homeScore != null || game.awayScore != null ? (
            <p className="text-xs text-slate-500">
              {game.awayScore ?? 0}–{game.homeScore ?? 0}
            </p>
          ) : null}
        </div>
      ),
    },
    {
      key: "line",
      header: "Line",
      render: (game) => {
        const isEditing = edits[game.id] != null;
        if (!isEditing) {
          return (
            <div className="flex items-center gap-3">
              <span className="font-mono text-slate-200">
                {game.spreadTeamId === game.homeTeamId ? game.homeTeamAbbreviation : game.awayTeamAbbreviation}{" "}
                {favoriteSpreadLabel(game.spread ?? 0)}
              </span>
              <Button variant="ghost" disabled={action.busy} onClick={() => beginEdit(game)}>
                Edit
              </Button>
            </div>
          );
        }
        const edit = editFor(game);
        return (
          <div className="flex flex-wrap items-center gap-2">
            <Select
              value={edit.spreadTeamId}
              className="w-32"
              onChange={(event) => setEdit(game.id, { spreadTeamId: event.target.value })}
            >
              <option value={game.homeTeamId}>{game.homeTeamAbbreviation} (home)</option>
              <option value={game.awayTeamId}>{game.awayTeamAbbreviation} (away)</option>
            </Select>
            <TextInput
              type="number"
              step="0.5"
              min="0"
              value={edit.spread}
              className="w-24 font-mono"
              onChange={(event) => setEdit(game.id, { spread: event.target.value })}
            />
            <Button
              variant="primary"
              pending={action.isPending(`spread:${game.id}`)}
              disabled={action.busy}
              onClick={() => void saveSpread(game)}
            >
              Save
            </Button>
            <Button
              variant="ghost"
              onClick={() =>
                setEdits((previous) => {
                  const next = { ...previous };
                  delete next[game.id];
                  return next;
                })
              }
            >
              Cancel
            </Button>
          </div>
        );
      },
    },
  ];

  const countsDisagree =
    games.data.length > 0 && nominations.data.length > 0 && games.data.length !== nominations.data.length;

  return (
    <div className="space-y-3">
      {dialog}
      <ErrorBanner error={games.error ?? action.error} onDismiss={action.clearError} />
      {action.message ? (
        <Banner tone="success" onDismiss={action.clearMessage}>
          {action.message}
        </Banner>
      ) : null}
      {countsDisagree ? (
        <Banner tone="warning" title="Slate does not match nominations">
          {nominations.data.length} nomination(s) but {games.data.length} game(s). Re-materialize to
          rebuild the slate from nominations.
        </Banner>
      ) : null}
      <DataTable
        columns={columns}
        rows={games.data}
        rowKey={(game) => game.id}
        loading={games.loading}
        empty="No games materialized for this week yet."
      />
    </div>
  );
}
