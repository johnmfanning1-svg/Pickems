import { Timestamp, deleteDoc, doc, setDoc, updateDoc } from "firebase/firestore";
import { useState } from "react";
import { Badge } from "./Badge";
import { Banner, ErrorBanner } from "./Banner";
import { Button } from "./Button";
import { Field, Select, TextInput } from "./Fields";
import { useConfirm } from "./useConfirm";
import { useNominations, useSlateGames } from "@/hooks/queries";
import { useAction } from "@/hooks/useAction";
import type { WithId } from "@/hooks/useFirestore";
import { adminUpdateGameResult } from "@/lib/callables";
import { writeAudit } from "@/lib/audit";
import { db } from "@/lib/firebase";
import {
  favoriteSpreadLabel,
  formatTimestamp,
  fromDateTimeLocalValue,
  matchupLabel,
} from "@/lib/format";
import type { GameStatus, SlateGameDoc } from "@/lib/types";

/**
 * Full slate editor for one week: add and remove games, set point spreads, and
 * post live results (score, status, ATS-covered team).
 *
 * `spread` and `spreadTeamId` are a pair — the number is a magnitude and the id
 * says who it applies to, exactly as `SlateGame.spreadLabel(for:)` reads them on
 * iOS. Results route through the `adminUpdateGameResult` callable so the covered
 * team is computed by the same function the scoring scheduler uses.
 */

type LineEdit = { spread: string; spreadTeamId: string };
type ResultEdit = { status: GameStatus; homeScore: string; awayScore: string; winner: string };

type AddForm = {
  espnEventId: string;
  homeTeamId: string;
  homeTeamName: string;
  homeTeamAbbreviation: string;
  awayTeamId: string;
  awayTeamName: string;
  awayTeamAbbreviation: string;
  spread: string;
  favorite: "home" | "away";
  kickoff: string;
};

const EMPTY_ADD: AddForm = {
  espnEventId: "",
  homeTeamId: "",
  homeTeamName: "",
  homeTeamAbbreviation: "",
  awayTeamId: "",
  awayTeamName: "",
  awayTeamAbbreviation: "",
  spread: "0",
  favorite: "home",
  kickoff: "",
};

export function WeekSlateEditor({ groupId, weekId }: { groupId: string; weekId: string }) {
  const games = useSlateGames(groupId, weekId);
  const nominations = useNominations(groupId, weekId);
  const action = useAction();
  const { confirm, dialog } = useConfirm();
  const [lineEdit, setLineEdit] = useState<Record<string, LineEdit>>({});
  const [resultEdit, setResultEdit] = useState<Record<string, ResultEdit>>({});
  const [add, setAdd] = useState<AddForm | null>(null);

  function beginLine(game: WithId<SlateGameDoc>) {
    setLineEdit((prev) => ({
      ...prev,
      [game.id]: {
        spread: String(game.spread ?? 0),
        spreadTeamId: game.spreadTeamId ?? game.homeTeamId,
      },
    }));
  }

  function cancelLine(gameId: string) {
    setLineEdit((prev) => {
      const next = { ...prev };
      delete next[gameId];
      return next;
    });
  }

  function beginResult(game: WithId<SlateGameDoc>) {
    setResultEdit((prev) => ({
      ...prev,
      [game.id]: {
        status: (game.status as GameStatus) ?? "scheduled",
        homeScore: game.homeScore != null ? String(game.homeScore) : "",
        awayScore: game.awayScore != null ? String(game.awayScore) : "",
        winner: "auto",
      },
    }));
  }

  function cancelResult(gameId: string) {
    setResultEdit((prev) => {
      const next = { ...prev };
      delete next[gameId];
      return next;
    });
  }

  async function saveLine(game: WithId<SlateGameDoc>) {
    const edit = lineEdit[game.id];
    if (!edit) return;
    const spread = Number(edit.spread);
    if (!Number.isFinite(spread)) return;
    if (
      !(await confirm({
        title: "Change this line?",
        body: (
          <>
            {matchupLabel(game.awayTeamAbbreviation, game.homeTeamAbbreviation)} becomes{" "}
            <strong>
              {edit.spreadTeamId === game.homeTeamId
                ? game.homeTeamAbbreviation
                : game.awayTeamAbbreviation}{" "}
              {favoriteSpreadLabel(spread)}
            </strong>
            . Scoring for this game is recomputed from the new line the next time the week is scored or
            rescored — picks already made are not changed.
          </>
        ),
        tone: "primary",
        confirmLabel: "Save line",
      }))
    ) {
      return;
    }
    await action.run(`line:${game.id}`, async () => {
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
      cancelLine(game.id);
      return "Line updated.";
    });
  }

  async function saveResult(game: WithId<SlateGameDoc>) {
    const edit = resultEdit[game.id];
    if (!edit) return;
    const payload: {
      groupId: string;
      weekId: string;
      gameId: string;
      status: GameStatus;
      homeScore?: number | null;
      awayScore?: number | null;
      winnerTeamId?: string | null;
    } = { groupId, weekId, gameId: game.id, status: edit.status };

    if (edit.status === "final") {
      const home = Number(edit.homeScore);
      const away = Number(edit.awayScore);
      if (edit.homeScore === "" || edit.awayScore === "" || !Number.isFinite(home) || !Number.isFinite(away)) {
        action.run(`result:${game.id}`, async () => {
          throw new Error("Enter both final scores before marking this game final.");
        });
        return;
      }
      payload.homeScore = home;
      payload.awayScore = away;
      if (edit.winner === "push") payload.winnerTeamId = null;
      else if (edit.winner !== "auto") payload.winnerTeamId = edit.winner;
    } else {
      if (edit.homeScore !== "") payload.homeScore = Number(edit.homeScore);
      if (edit.awayScore !== "") payload.awayScore = Number(edit.awayScore);
    }

    if (
      !(await confirm({
        title: "Post this game result?",
        body: (
          <>
            <p>
              {matchupLabel(game.awayTeamAbbreviation, game.homeTeamAbbreviation)} →{" "}
              <strong>{edit.status}</strong>
              {edit.status === "final" ? (
                <>
                  {" "}
                  at{" "}
                  <strong>
                    {edit.awayScore || 0}–{edit.homeScore || 0}
                  </strong>
                </>
              ) : null}
              .
            </p>
            {edit.status === "final" ? (
              <p className="mt-2 text-sky-300">
                The ATS-covered team{" "}
                {edit.winner === "auto"
                  ? "is computed from the score and the line."
                  : edit.winner === "push"
                    ? "is recorded as a push."
                    : "is set manually."}{" "}
                Rescore or finalize the week afterwards to fold this into standings.
              </p>
            ) : null}
          </>
        ),
        tone: "primary",
        confirmLabel: "Save result",
      }))
    ) {
      return;
    }
    await action.run(`result:${game.id}`, async () => {
      await adminUpdateGameResult(payload);
      cancelResult(game.id);
      return "Result saved.";
    });
  }

  async function removeGame(game: WithId<SlateGameDoc>) {
    if (
      !(await confirm({
        title: "Remove this game from the slate?",
        body: (
          <>
            Deletes <code className="font-mono">{game.id}</code> (
            {matchupLabel(game.awayTeamAbbreviation, game.homeTeamAbbreviation)}) from this week&apos;s
            slate. Any pick pointing at it stops counting. Re-materializing rebuilds the slate from
            nominations, so remove the nomination too if it should stay gone.
          </>
        ),
        confirmLabel: "Remove game",
        requireText: game.id,
      }))
    ) {
      return;
    }
    await action.run(`remove:${game.id}`, async () => {
      await writeAudit(
        "adminRemoveGame",
        `groups/${groupId}/weeks/${weekId}/games/${game.id}`,
        game,
        null,
      );
      await deleteDoc(doc(db, "groups", groupId, "weeks", weekId, "games", game.id));
      return "Game removed.";
    });
  }

  async function saveNewGame() {
    if (!add) return;
    const id = add.espnEventId.trim();
    const homeId = add.homeTeamId.trim();
    const awayId = add.awayTeamId.trim();
    const spread = Number(add.spread);
    if (!id || !homeId || !awayId || !Number.isFinite(spread)) {
      action.run("add-game", async () => {
        throw new Error("Game id, both team ids, and a numeric spread are required.");
      });
      return;
    }
    const kickoff = fromDateTimeLocalValue(add.kickoff);
    const payload = {
      id,
      espnEventId: id,
      homeTeamId: homeId,
      homeTeamName: add.homeTeamName.trim() || homeId,
      homeTeamAbbreviation: add.homeTeamAbbreviation.trim() || homeId.slice(0, 4).toUpperCase(),
      homeTeamLogoURL: null,
      awayTeamId: awayId,
      awayTeamName: add.awayTeamName.trim() || awayId,
      awayTeamAbbreviation: add.awayTeamAbbreviation.trim() || awayId.slice(0, 4).toUpperCase(),
      awayTeamLogoURL: null,
      spread: Math.abs(spread),
      spreadTeamId: add.favorite === "home" ? homeId : awayId,
      kickoff: kickoff ? Timestamp.fromDate(new Date(kickoff)) : null,
      status: "scheduled" as const,
      homeScore: null,
      awayScore: null,
      winnerTeamId: null,
    };
    await action.run("add-game", async () => {
      await setDoc(doc(db, "groups", groupId, "weeks", weekId, "games", id), payload);
      await writeAudit(
        "adminAddGame",
        `groups/${groupId}/weeks/${weekId}/games/${id}`,
        null,
        payload,
      );
      setAdd(null);
      return "Game added to the slate.";
    });
  }

  const countsDisagree =
    games.data.length > 0 &&
    nominations.data.length > 0 &&
    games.data.length !== nominations.data.length;

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
          rebuild the slate from nominations, or add/remove games below.
        </Banner>
      ) : null}

      <div className="flex justify-end">
        <Button
          variant={add ? "ghost" : "primary"}
          disabled={action.busy}
          onClick={() => setAdd(add ? null : { ...EMPTY_ADD })}
        >
          {add ? "Cancel add" : "Add game"}
        </Button>
      </div>

      {add ? (
        <div className="rounded-lg border border-ink-600 bg-ink-900/50 p-4">
          <p className="mb-3 text-xs uppercase tracking-wide text-slate-400">Add a game</p>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <Field label="Game / ESPN event id">
              <TextInput
                value={add.espnEventId}
                onChange={(e) => setAdd({ ...add, espnEventId: e.target.value })}
                className="font-mono"
              />
            </Field>
            <Field label="Kickoff">
              <TextInput
                type="datetime-local"
                value={add.kickoff}
                onChange={(e) => setAdd({ ...add, kickoff: e.target.value })}
              />
            </Field>
            <Field label="Favorite (spread applies to)">
              <Select value={add.favorite} onChange={(e) => setAdd({ ...add, favorite: e.target.value as "home" | "away" })}>
                <option value="home">Home</option>
                <option value="away">Away</option>
              </Select>
            </Field>
            <Field label="Away team id">
              <TextInput value={add.awayTeamId} onChange={(e) => setAdd({ ...add, awayTeamId: e.target.value })} className="font-mono" />
            </Field>
            <Field label="Away name">
              <TextInput value={add.awayTeamName} onChange={(e) => setAdd({ ...add, awayTeamName: e.target.value })} />
            </Field>
            <Field label="Away abbr">
              <TextInput value={add.awayTeamAbbreviation} onChange={(e) => setAdd({ ...add, awayTeamAbbreviation: e.target.value })} />
            </Field>
            <Field label="Home team id">
              <TextInput value={add.homeTeamId} onChange={(e) => setAdd({ ...add, homeTeamId: e.target.value })} className="font-mono" />
            </Field>
            <Field label="Home name">
              <TextInput value={add.homeTeamName} onChange={(e) => setAdd({ ...add, homeTeamName: e.target.value })} />
            </Field>
            <Field label="Home abbr">
              <TextInput value={add.homeTeamAbbreviation} onChange={(e) => setAdd({ ...add, homeTeamAbbreviation: e.target.value })} />
            </Field>
            <Field label="Spread (magnitude)">
              <TextInput
                type="number"
                step="0.5"
                min="0"
                value={add.spread}
                onChange={(e) => setAdd({ ...add, spread: e.target.value })}
                className="font-mono"
              />
            </Field>
          </div>
          <div className="mt-3 flex justify-end">
            <Button variant="primary" pending={action.isPending("add-game")} disabled={action.busy} onClick={() => void saveNewGame()}>
              Save game
            </Button>
          </div>
        </div>
      ) : null}

      {games.data.length === 0 && !games.loading ? (
        <p className="rounded-lg border border-dashed border-ink-600 px-4 py-8 text-center text-sm text-slate-500">
          No games materialized for this week yet.
        </p>
      ) : null}

      <div className="space-y-2">
        {games.data.map((game) => {
          const line = lineEdit[game.id];
          const result = resultEdit[game.id];
          return (
            <div key={game.id} className="rounded-lg border border-ink-600 bg-ink-800 p-3">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-slate-100">
                    {matchupLabel(
                      game.awayTeamName ?? game.awayTeamAbbreviation,
                      game.homeTeamName ?? game.homeTeamAbbreviation,
                    )}
                  </p>
                  <p className="font-mono text-xs text-slate-500">
                    {game.id} · {formatTimestamp(game.kickoff)}
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <Badge
                    tone={
                      game.status === "final"
                        ? "success"
                        : game.status === "inProgress"
                          ? "warning"
                          : "neutral"
                    }
                  >
                    {game.status ?? "—"}
                  </Badge>
                  {game.homeScore != null || game.awayScore != null ? (
                    <span className="font-mono text-xs text-slate-400">
                      {game.awayScore ?? 0}–{game.homeScore ?? 0}
                    </span>
                  ) : null}
                  <span className="font-mono text-xs text-slate-300">
                    {game.spreadTeamId === game.homeTeamId
                      ? game.homeTeamAbbreviation
                      : game.awayTeamAbbreviation}{" "}
                    {favoriteSpreadLabel(game.spread ?? 0)}
                  </span>
                </div>
              </div>

              {line ? (
                <div className="mt-3 flex flex-wrap items-end gap-2 border-t border-ink-700 pt-3">
                  <Field label="Favorite">
                    <Select
                      value={line.spreadTeamId}
                      className="w-36"
                      onChange={(e) => setLineEdit((p) => ({ ...p, [game.id]: { ...line, spreadTeamId: e.target.value } }))}
                    >
                      <option value={game.homeTeamId}>{game.homeTeamAbbreviation} (home)</option>
                      <option value={game.awayTeamId}>{game.awayTeamAbbreviation} (away)</option>
                    </Select>
                  </Field>
                  <Field label="Spread">
                    <TextInput
                      type="number"
                      step="0.5"
                      min="0"
                      value={line.spread}
                      className="w-24 font-mono"
                      onChange={(e) => setLineEdit((p) => ({ ...p, [game.id]: { ...line, spread: e.target.value } }))}
                    />
                  </Field>
                  <Button variant="primary" pending={action.isPending(`line:${game.id}`)} disabled={action.busy} onClick={() => void saveLine(game)}>
                    Save line
                  </Button>
                  <Button variant="ghost" onClick={() => cancelLine(game.id)}>
                    Cancel
                  </Button>
                </div>
              ) : null}

              {result ? (
                <div className="mt-3 flex flex-wrap items-end gap-2 border-t border-ink-700 pt-3">
                  <Field label="Status">
                    <Select
                      value={result.status}
                      className="w-32"
                      onChange={(e) => setResultEdit((p) => ({ ...p, [game.id]: { ...result, status: e.target.value as GameStatus } }))}
                    >
                      <option value="scheduled">scheduled</option>
                      <option value="inProgress">inProgress</option>
                      <option value="final">final</option>
                    </Select>
                  </Field>
                  <Field label={`${game.awayTeamAbbreviation} (away)`}>
                    <TextInput
                      type="number"
                      min="0"
                      value={result.awayScore}
                      className="w-20 font-mono"
                      onChange={(e) => setResultEdit((p) => ({ ...p, [game.id]: { ...result, awayScore: e.target.value } }))}
                    />
                  </Field>
                  <Field label={`${game.homeTeamAbbreviation} (home)`}>
                    <TextInput
                      type="number"
                      min="0"
                      value={result.homeScore}
                      className="w-20 font-mono"
                      onChange={(e) => setResultEdit((p) => ({ ...p, [game.id]: { ...result, homeScore: e.target.value } }))}
                    />
                  </Field>
                  {result.status === "final" ? (
                    <Field label="Covered (ATS)">
                      <Select
                        value={result.winner}
                        className="w-40"
                        onChange={(e) => setResultEdit((p) => ({ ...p, [game.id]: { ...result, winner: e.target.value } }))}
                      >
                        <option value="auto">auto (from score)</option>
                        <option value={game.awayTeamId}>{game.awayTeamAbbreviation} covered</option>
                        <option value={game.homeTeamId}>{game.homeTeamAbbreviation} covered</option>
                        <option value="push">push (no cover)</option>
                      </Select>
                    </Field>
                  ) : null}
                  <Button variant="primary" pending={action.isPending(`result:${game.id}`)} disabled={action.busy} onClick={() => void saveResult(game)}>
                    Save result
                  </Button>
                  <Button variant="ghost" onClick={() => cancelResult(game.id)}>
                    Cancel
                  </Button>
                </div>
              ) : null}

              {!line && !result ? (
                <div className="mt-3 flex flex-wrap gap-2 border-t border-ink-700 pt-3">
                  <Button disabled={action.busy} onClick={() => beginLine(game)}>
                    Edit line
                  </Button>
                  <Button disabled={action.busy} onClick={() => beginResult(game)}>
                    Edit result
                  </Button>
                  <Button variant="danger" pending={action.isPending(`remove:${game.id}`)} disabled={action.busy} onClick={() => void removeGame(game)}>
                    Remove
                  </Button>
                </div>
              ) : null}
            </div>
          );
        })}
      </div>
    </div>
  );
}
