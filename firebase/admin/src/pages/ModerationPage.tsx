import { collection, deleteDoc, doc, getDocs, updateDoc } from "firebase/firestore";
import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { Badge } from "@/components/Badge";
import { Banner, ErrorBanner } from "@/components/Banner";
import { Button } from "@/components/Button";
import { Card, EmptyState, PageHeader, StatTile } from "@/components/Card";
import { Spinner } from "@/components/Spinner";
import { useConfirm } from "@/components/useConfirm";
import { useReportedMessages } from "@/hooks/queries";
import { useAction } from "@/hooks/useAction";
import type { WithId } from "@/hooks/useFirestore";
import { writeAudit } from "@/lib/audit";
import { describeError } from "@/lib/callables";
import { db } from "@/lib/firebase";
import { formatTimestamp } from "@/lib/format";
import type { ChatMessageDoc, MessageReportDoc } from "@/lib/types";

/**
 * Reported-message queue — App Review Guideline 1.2 depends on someone actually
 * working this list, so it is the one screen that has to stay usable.
 *
 * `reportCount` is only ever moved by a Cloud Function; rules pin it to 0 on
 * create and never list it in an update allow-list, so a client cannot inflate
 * or clear it. That makes the count trustworthy as a triage signal.
 */

function groupIdFromPath(path: string): string | null {
  const match = /^groups\/([^/]+)\/messages\//.exec(path);
  return match?.[1] ?? null;
}

function Reporters({ messagePath }: { messagePath: string }) {
  const [reports, setReports] = useState<MessageReportDoc[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getDocs(collection(db, `${messagePath}/reports`))
      .then((snapshot) =>
        setReports(snapshot.docs.map((entry) => ({ id: entry.id, ...entry.data() }) as MessageReportDoc)),
      )
      .catch((caught) => setError(describeError(caught)));
  }, [messagePath]);

  if (error) return <p className="text-xs text-red-400">{error}</p>;
  if (!reports) return <Spinner />;
  if (reports.length === 0) {
    return (
      <p className="text-xs text-slate-500">
        No report docs — the counter moved without them, which means a function incremented it directly.
      </p>
    );
  }
  return (
    <ul className="space-y-1 text-xs">
      {reports.map((report) => (
        <li key={report.id} className="text-slate-400">
          <code className="font-mono">{report.reporterUid ?? report.id}</code>
          {report.reason ? ` — ${report.reason}` : ""}
          <span className="text-slate-600"> · {formatTimestamp(report.createdAt)}</span>
        </li>
      ))}
    </ul>
  );
}

export function ModerationPage() {
  const { data, loading, error } = useReportedMessages();
  const action = useAction();
  const { confirm, dialog } = useConfirm();
  const [expanded, setExpanded] = useState<string | null>(null);

  const setDeleted = useCallback(
    async (message: WithId<ChatMessageDoc>, isDeleted: boolean) => {
      if (!(await confirm({
        title: isDeleted ? "Hide this message?" : "Restore this message?",
        body: isDeleted ? (
          <>
            Sets <code className="font-mono">isDeleted: true</code>. The message stops rendering for
            members but stays in Firestore, so thread order survives and the text is still available if
            Apple or a member asks what was removed.
          </>
        ) : (
          <>
            Makes this message visible to the group again. Its report count is unchanged, so it stays in
            this queue.
          </>
        ),
        tone: isDeleted ? "danger" : "primary",
        confirmLabel: isDeleted ? "Hide message" : "Restore",
      }))) {
        return;
      }
      await action.run(`hide:${message.path}`, async () => {
        await updateDoc(doc(db, message.path), { isDeleted });
        await writeAudit(
          isDeleted ? "adminSoftDeleteMessage" : "adminRestoreMessage",
          message.path,
          { isDeleted: message.isDeleted ?? false, text: message.text ?? null },
          { isDeleted },
        );
        return isDeleted ? "Message hidden." : "Message restored.";
      });
    },
    [action, confirm],
  );

  const hardDelete = useCallback(
    async (message: WithId<ChatMessageDoc>) => {
      if (!(await confirm({
        title: "Permanently delete this message?",
        body: (
          <>
            <p>
              Removes the document outright. Prefer hiding it — a soft delete keeps the evidence, and
              evidence is what an App Review escalation asks for.
            </p>
            <p className="mt-2 text-amber-300">
              The <code className="font-mono">reports</code> subcollection is not deleted with it and
              becomes orphaned.
            </p>
          </>
        ),
        confirmLabel: "Delete permanently",
        requireText: "delete",
      }))) {
        return;
      }
      await action.run(`delete:${message.path}`, async () => {
        await writeAudit("adminDeleteMessage", message.path, message, null);
        await deleteDoc(doc(db, message.path));
        return "Message deleted.";
      });
    },
    [action, confirm],
  );

  // A collection-group query needs a `match /{path=**}/messages/{id}` rule; the
  // per-group match alone does not authorize it.
  const looksLikeRulesGap =
    error != null && /permission|insufficient/i.test(error);
  const looksLikeMissingIndex = error != null && /index/i.test(error);

  const hidden = data.filter((message) => message.isDeleted === true).length;
  const worst = data.reduce((max, message) => Math.max(max, message.reportCount ?? 0), 0);

  return (
    <>
      {dialog}
      <PageHeader
        title="Moderation"
        subtitle="Every message with at least one report, across all leagues. Guideline 1.2 assumes this queue gets worked."
      />

      <ErrorBanner error={action.error} onDismiss={action.clearError} />
      {action.message ? (
        <Banner tone="success" onDismiss={action.clearMessage}>
          {action.message}
        </Banner>
      ) : null}

      {looksLikeRulesGap ? (
        <Banner tone="error" title="This query is not authorized by the current rules">
          <p>
            Firestore does not apply <code className="font-mono">match /groups/&#123;groupId&#125;/messages/&#123;messageId&#125;</code>{" "}
            to a <em>collection group</em> query — that needs a recursive-wildcard match. Ask the rules
            owner (Lane F) to add:
          </p>
          <pre className="mt-2 overflow-auto rounded bg-ink-900 p-2 font-mono text-[11px] text-slate-300">
{`match /{path=**}/messages/{messageId} {
  allow read: if isSuperAdmin();
}`}
          </pre>
          <p className="mt-2">
            Until then, work reports league by league from the chat feed. Everything else in this console
            is unaffected.
          </p>
        </Banner>
      ) : null}
      {looksLikeMissingIndex ? (
        <Banner tone="warning" title="Missing collection-group index">
          Needs the (reportCount ASC, createdAt DESC) COLLECTION_GROUP index on{" "}
          <code className="font-mono">messages</code>. Deploy with{" "}
          <code className="font-mono">firebase deploy --only firestore:indexes</code> and wait for
          Enabled.
        </Banner>
      ) : null}
      {error && !looksLikeRulesGap && !looksLikeMissingIndex ? <ErrorBanner error={error} /> : null}

      <div className="grid gap-3 sm:grid-cols-3">
        <StatTile label="Reported messages" value={loading ? "…" : data.length} />
        <StatTile label="Already hidden" value={hidden} hint="isDeleted == true" />
        <StatTile label="Most reports" value={worst} hint="highest reportCount" />
      </div>

      {data.length === 0 && !loading && !error ? (
        <Banner tone="success" title="Queue is empty">
          No message currently carries a report.
        </Banner>
      ) : null}

      <div className="space-y-3">
        {data.map((message) => {
          const groupId = groupIdFromPath(message.path);
          const isExpanded = expanded === message.path;
          return (
            <Card key={message.path}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge tone={(message.reportCount ?? 0) >= 3 ? "danger" : "warning"}>
                      {message.reportCount ?? 0} report{(message.reportCount ?? 0) === 1 ? "" : "s"}
                    </Badge>
                    {message.isDeleted === true ? <Badge tone="neutral">hidden</Badge> : null}
                    <span className="text-sm text-slate-300">{message.displayName ?? "Unknown"}</span>
                    <span className="text-xs text-slate-500">{formatTimestamp(message.createdAt)}</span>
                    {message.weekId ? (
                      <span className="text-xs text-slate-500">week {message.weekId}</span>
                    ) : null}
                  </div>

                  <p className="mt-2 whitespace-pre-wrap break-words rounded-lg bg-ink-900 p-3 text-sm text-slate-100">
                    {message.text ?? <span className="text-slate-600">(no text)</span>}
                  </p>

                  <p className="mt-2 break-all font-mono text-xs text-slate-600">{message.path}</p>
                  <p className="mt-1 flex flex-wrap gap-3 text-xs">
                    {groupId ? (
                      <Link to={`/groups/${groupId}`} className="text-slate-400 underline hover:text-slate-200">
                        Open league
                      </Link>
                    ) : null}
                    {groupId ? (
                      <Link
                        to={`/groups/${groupId}/members`}
                        className="text-slate-400 underline hover:text-slate-200"
                      >
                        Members
                      </Link>
                    ) : null}
                    <span className="text-slate-600">author {message.userId ?? "—"}</span>
                  </p>
                </div>

                <div className="flex shrink-0 flex-col gap-2">
                  {message.isDeleted === true ? (
                    <Button
                      pending={action.isPending(`hide:${message.path}`)}
                      disabled={action.busy}
                      onClick={() => void setDeleted(message, false)}
                    >
                      Restore
                    </Button>
                  ) : (
                    <Button
                      variant="danger"
                      pending={action.isPending(`hide:${message.path}`)}
                      disabled={action.busy}
                      onClick={() => void setDeleted(message, true)}
                    >
                      Hide
                    </Button>
                  )}
                  <Button onClick={() => setExpanded(isExpanded ? null : message.path)}>
                    {isExpanded ? "Hide reporters" : "Reporters"}
                  </Button>
                  <Button
                    variant="ghost"
                    pending={action.isPending(`delete:${message.path}`)}
                    disabled={action.busy}
                    onClick={() => void hardDelete(message)}
                  >
                    Delete
                  </Button>
                </div>
              </div>

              {isExpanded ? (
                <div className="mt-3 border-t border-ink-600 pt-3">
                  <Reporters messagePath={message.path} />
                </div>
              ) : null}
            </Card>
          );
        })}
      </div>

      {loading && data.length === 0 ? <EmptyState>Loading reported messages…</EmptyState> : null}
    </>
  );
}
