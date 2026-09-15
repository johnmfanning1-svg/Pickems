import { deleteDoc, doc, serverTimestamp, setDoc } from "firebase/firestore";
import { useEffect, useMemo, useState } from "react";
import { Banner, ErrorBanner } from "@/components/Banner";
import { Button } from "@/components/Button";
import { Card, PageHeader } from "@/components/Card";
import { DataTable, type Column } from "@/components/DataTable";
import { Field, TextInput } from "@/components/Fields";
import { useConfirm } from "@/components/useConfirm";
import { useSupportInboxConfig, useSupportMessages } from "@/hooks/queries";
import { useAction } from "@/hooks/useAction";
import type { WithId } from "@/hooks/useFirestore";
import { writeAudit } from "@/lib/audit";
import { db } from "@/lib/firebase";
import { formatRelative, formatTimestamp } from "@/lib/format";
import type { SupportMessageDoc } from "@/lib/types";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Private inbox for https://pickems-fb.web.app/support.
 *
 * The public page never sees this address. `submitSupport` reads
 * `adminConfig/support.inboxEmail` (or SUPPORT_INBOX_EMAIL) server-side.
 */
export function SupportInboxPage() {
  const messages = useSupportMessages();
  const config = useSupportInboxConfig();
  const action = useAction();
  const { confirm, dialog } = useConfirm();
  const [inboxEmail, setInboxEmail] = useState("");
  const [expanded, setExpanded] = useState<string | null>(null);

  const savedInbox = config.data?.inboxEmail ?? "";

  useEffect(() => {
    if (savedInbox) setInboxEmail(savedInbox);
  }, [savedInbox]);

  const columns: Column<WithId<SupportMessageDoc>>[] = useMemo(
    () => [
      {
        key: "when",
        header: "When",
        render: (row) => (
          <div className="whitespace-nowrap">
            <p className="text-slate-200">{formatTimestamp(row.createdAt)}</p>
            <p className="text-xs text-slate-500">{formatRelative(row.createdAt)}</p>
          </div>
        ),
      },
      {
        key: "from",
        header: "From",
        render: (row) => (
          <div>
            <p className="text-slate-200">{row.name || "—"}</p>
            <p className="font-mono text-xs text-slate-400">{row.email || "—"}</p>
          </div>
        ),
      },
      {
        key: "subject",
        header: "Subject",
        render: (row) => <span>{row.subject || "Pickems support request"}</span>,
      },
      {
        key: "via",
        header: "Mail",
        render: (row) => (
          <span className="font-mono text-xs text-slate-400">{row.deliveredVia || "none"}</span>
        ),
      },
    ],
    [],
  );

  async function saveInbox() {
    const value = inboxEmail.trim();
    if (value && !EMAIL_RE.test(value)) {
      return;
    }
    await action.run("inbox", async () => {
      await setDoc(
        doc(db, "adminConfig", "support"),
        { inboxEmail: value, updatedAt: serverTimestamp() },
        { merge: true },
      );
      await writeAudit(
        "adminUpdateSupportInbox",
        "adminConfig/support",
        { configured: Boolean(savedInbox) },
        { configured: Boolean(value) },
      );
      return value ? "Support inbox updated." : "Support inbox cleared. Messages still land in this list.";
    });
  }

  async function remove(row: WithId<SupportMessageDoc>) {
    if (
      !(await confirm({
        title: "Delete this support message?",
        body: "Removes it from the inbox. Email already forwarded is not unsent.",
        tone: "danger",
        confirmLabel: "Delete",
      }))
    ) {
      return;
    }
    await action.run(`delete:${row.id}`, async () => {
      await deleteDoc(doc(db, "supportMessages", row.id));
      await writeAudit("adminDeleteSupportMessage", row.path, { email: row.email ?? null }, null);
      return "Message deleted.";
    });
  }

  return (
    <div className="space-y-6">
      {dialog}
      <PageHeader
        title="Support inbox"
        subtitle="Messages from the public /support form. The recipient address stays on the server — never on the static page."
      />
      {action.error ? <ErrorBanner error={action.error} /> : null}
      {action.message ? <Banner tone="success">{action.message}</Banner> : null}
      {messages.error ? <ErrorBanner error={messages.error} /> : null}
      {config.error ? <ErrorBanner error={config.error} /> : null}

      <Card>
        <form
          className="flex flex-col gap-3 sm:flex-row sm:items-end"
          onSubmit={(event) => {
            event.preventDefault();
            void saveInbox();
          }}
        >
          <div className="min-w-0 flex-1">
            <Field
              label="Forward copies to"
              hint="Stored in adminConfig/support, readable only with the admin claim. Leave blank to keep messages in this list only."
            >
              <TextInput
                type="email"
                autoComplete="off"
                placeholder={savedInbox || "you@example.com"}
                value={inboxEmail}
                onChange={(event) => setInboxEmail(event.target.value)}
              />
            </Field>
          </div>
          <Button type="submit" disabled={action.isPending("inbox")}>
            {action.isPending("inbox") ? "Saving…" : savedInbox ? "Update inbox" : "Save inbox"}
          </Button>
        </form>
        {savedInbox ? (
          <p className="mt-3 text-xs text-slate-500">
            Currently forwarding to <code className="font-mono">{savedInbox}</code>
          </p>
        ) : (
          <p className="mt-3 text-xs text-slate-500">
            No inbox configured yet. Submissions still appear below after <code className="font-mono">submitSupport</code> is deployed.
          </p>
        )}
      </Card>

      <Card>
        <DataTable
          columns={columns}
          rows={messages.data}
          rowKey={(row) => row.id}
          loading={messages.loading}
          empty="No support messages yet."
        />
      </Card>

      {messages.data.length > 0 ? (
        <Card>
          <p className="mb-3 text-xs font-medium uppercase tracking-wide text-slate-400">Message</p>
          <div className="space-y-3">
            {messages.data.slice(0, 20).map((row) => (
              <article key={row.id} className="rounded-md border border-ink-600 bg-ink-900 p-3">
                <button
                  type="button"
                  className="flex w-full items-start justify-between gap-3 text-left"
                  onClick={() => setExpanded((current) => (current === row.id ? null : row.id))}
                >
                  <span className="min-w-0">
                    <span className="block truncate text-sm text-slate-200">
                      {row.subject || "Pickems support request"}
                    </span>
                    <span className="block truncate text-xs text-slate-500">
                      {row.email} · {formatTimestamp(row.createdAt)}
                    </span>
                  </span>
                  <span className="shrink-0 text-xs text-slate-500">
                    {expanded === row.id ? "Hide" : "Show"}
                  </span>
                </button>
                {expanded === row.id ? (
                  <div className="mt-3 space-y-3">
                    <pre className="whitespace-pre-wrap break-words font-sans text-sm text-slate-200">
                      {row.message || "—"}
                    </pre>
                    <Button
                      variant="ghost"
                      onClick={() => void remove(row)}
                      disabled={action.isPending(`delete:${row.id}`)}
                    >
                      Delete
                    </Button>
                  </div>
                ) : null}
              </article>
            ))}
          </div>
        </Card>
      ) : null}
    </div>
  );
}
