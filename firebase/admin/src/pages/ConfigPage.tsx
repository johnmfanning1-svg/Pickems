import { doc, serverTimestamp, setDoc } from "firebase/firestore";
import { useEffect, useState } from "react";
import { Banner, ErrorBanner } from "@/components/Banner";
import { Button } from "@/components/Button";
import { Card, PageHeader } from "@/components/Card";
import { Field, Select, TextArea, TextInput, Toggle } from "@/components/Fields";
import { useConfirm } from "@/components/useConfirm";
import { useAppConfig } from "@/hooks/queries";
import { useAction } from "@/hooks/useAction";
import { writeAudit } from "@/lib/audit";
import { setAdminRole } from "@/lib/callables";
import { db } from "@/lib/firebase";
import { formatTimestamp } from "@/lib/format";
import type { AppConfigDoc } from "@/lib/types";

/** Fields with real inputs. Everything else stays reachable through raw JSON. */
const TYPED_KEYS = [
  "chatEnabled",
  "top25FilterEnabled",
  "minimumBuild",
  "announcementTitle",
  "announcementBody",
  "maintenanceMessage",
  "updatedAt",
] as const;

interface ConfigForm {
  chatEnabled: boolean;
  top25FilterEnabled: boolean;
  minimumBuild: string;
  announcementTitle: string;
  announcementBody: string;
  maintenanceMessage: string;
}

const EMPTY_FORM: ConfigForm = {
  chatEnabled: false,
  top25FilterEnabled: false,
  minimumBuild: "",
  announcementTitle: "",
  announcementBody: "",
  maintenanceMessage: "",
};

function formFrom(config: AppConfigDoc | null): ConfigForm {
  if (!config) return EMPTY_FORM;
  return {
    chatEnabled: config.chatEnabled === true,
    top25FilterEnabled: config.top25FilterEnabled === true,
    minimumBuild: config.minimumBuild != null ? String(config.minimumBuild) : "",
    announcementTitle: config.announcementTitle ?? "",
    announcementBody: config.announcementBody ?? "",
    maintenanceMessage: config.maintenanceMessage ?? "",
  };
}

export function ConfigPage() {
  const config = useAppConfig();
  const action = useAction();
  const { confirm, dialog } = useConfirm();

  const [form, setForm] = useState<ConfigForm>(EMPTY_FORM);
  const [rawJson, setRawJson] = useState("{}");

  useEffect(() => {
    setForm(formFrom(config.data));
    const extras: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(config.data ?? {})) {
      if (key === "id" || key === "path") continue;
      if ((TYPED_KEYS as readonly string[]).includes(key)) continue;
      extras[key] = value;
    }
    setRawJson(JSON.stringify(extras, null, 2));
  }, [config.data]);

  function set<K extends keyof ConfigForm>(key: K, value: ConfigForm[K]) {
    setForm((previous) => ({ ...previous, [key]: value }));
  }

  async function saveFlags() {
    const minimumBuild = form.minimumBuild.trim() === "" ? null : Number(form.minimumBuild);
    if (minimumBuild != null && !Number.isInteger(minimumBuild)) {
      return;
    }
    if (!(await confirm({
      title: "Publish app config?",
      body: (
        <>
          <p>
            <code className="font-mono">appConfig/live</code> is read by every signed-in client at
            launch. This takes effect on the next launch, with no App Store release.
          </p>
          {config.data?.chatEnabled === true && !form.chatEnabled ? (
            <p className="mt-2 text-amber-300">
              Turning <code className="font-mono">chatEnabled</code> off is the chat kill switch — it
              only works if the client honours the flag.
            </p>
          ) : null}
          {minimumBuild != null ? (
            <p className="mt-2 text-amber-300">
              <code className="font-mono">minimumBuild {minimumBuild}</code> can force-update every
              user below that build. Confirm the build number is actually live in TestFlight or the App
              Store first.
            </p>
          ) : null}
        </>
      ),
      tone: "primary",
      confirmLabel: "Publish",
    }))) {
      return;
    }

    await action.run("flags", async () => {
      const payload: Record<string, unknown> = {
        chatEnabled: form.chatEnabled,
        top25FilterEnabled: form.top25FilterEnabled,
        minimumBuild,
        announcementTitle: form.announcementTitle.trim() || null,
        announcementBody: form.announcementBody.trim() || null,
        maintenanceMessage: form.maintenanceMessage.trim() || null,
        updatedAt: serverTimestamp(),
      };
      await setDoc(doc(db, "appConfig", "live"), payload, { merge: true });
      await writeAudit("adminUpdateAppConfig", "appConfig/live", config.data, {
        ...payload,
        updatedAt: null,
      });
      return "App config published.";
    });
  }

  async function saveRaw() {
    let parsed: unknown;
    try {
      parsed = JSON.parse(rawJson);
    } catch (caught) {
      await action.run("raw", async () => {
        throw new Error(`That is not valid JSON: ${(caught as Error).message}`);
      });
      return;
    }
    if (typeof parsed !== "object" || parsed == null || Array.isArray(parsed)) {
      await action.run("raw", async () => {
        throw new Error("Raw config must be a JSON object.");
      });
      return;
    }

    if (!(await confirm({
      title: "Merge these extra keys?",
      body: (
        <>
          Merges {Object.keys(parsed as object).length} key(s) into{" "}
          <code className="font-mono">appConfig/live</code> without touching the typed fields above.
          There is no schema check — a typo here ships a flag the app never reads.
        </>
      ),
      confirmLabel: "Merge keys",
      requireText: "live",
    }))) {
      return;
    }

    await action.run("raw", async () => {
      await setDoc(
        doc(db, "appConfig", "live"),
        { ...(parsed as Record<string, unknown>), updatedAt: serverTimestamp() },
        { merge: true },
      );
      await writeAudit("adminUpdateAppConfigRaw", "appConfig/live", config.data, parsed);
      return "Extra keys merged.";
    });
  }

  return (
    <>
      {dialog}
      <PageHeader
        title="App config"
        subtitle={
          <span>
            <code className="font-mono">appConfig/live</code> · last updated{" "}
            {formatTimestamp(config.data?.updatedAt)}
          </span>
        }
      />
      <ErrorBanner error={config.error ?? action.error} onDismiss={action.clearError} />
      {action.message ? (
        <Banner tone="success" onDismiss={action.clearMessage}>
          {action.message}
        </Banner>
      ) : null}
      {!config.exists && !config.loading ? (
        <Banner tone="warning" title="appConfig/live does not exist yet">
          Publishing below creates it. Seed <code className="font-mono">chatEnabled</code> and{" "}
          <code className="font-mono">minimumBuild</code> before the TestFlight invite.
        </Banner>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="Feature flags" description="Kill switches that ship without a build.">
          <div className="space-y-2">
            <Toggle
              label="chatEnabled"
              hint="Group chat. Turning this off is the Guideline 1.2 fallback if moderation slips."
              checked={form.chatEnabled}
              onChange={(next) => set("chatEnabled", next)}
            />
            <Toggle
              label="top25FilterEnabled"
              hint="Top 25 and conference filters in game browse."
              checked={form.top25FilterEnabled}
              onChange={(next) => set("top25FilterEnabled", next)}
            />
          </div>
          <div className="mt-4">
            <Field
              label="minimumBuild"
              hint="Blank means no minimum. Never set this above the newest build actually available."
            >
              <TextInput
                type="number"
                inputMode="numeric"
                value={form.minimumBuild}
                onChange={(event) => set("minimumBuild", event.target.value)}
                placeholder="230"
              />
            </Field>
          </div>
        </Card>

        <Card title="Marketing strings" description="Shown in-app; blank clears the field.">
          <div className="space-y-3">
            <Field label="announcementTitle">
              <TextInput
                value={form.announcementTitle}
                onChange={(event) => set("announcementTitle", event.target.value)}
              />
            </Field>
            <Field label="announcementBody">
              <TextArea
                rows={3}
                value={form.announcementBody}
                onChange={(event) => set("announcementBody", event.target.value)}
              />
            </Field>
            <Field label="maintenanceMessage" hint="Non-empty usually means the app shows a banner.">
              <TextInput
                value={form.maintenanceMessage}
                onChange={(event) => set("maintenanceMessage", event.target.value)}
              />
            </Field>
          </div>
        </Card>
      </div>

      <div>
        <Button
          variant="primary"
          pending={action.isPending("flags")}
          disabled={action.busy}
          onClick={() => void saveFlags()}
        >
          Publish app config
        </Button>
      </div>

      <Card
        title="Other keys"
        description="Anything in appConfig/live without a typed input above. Merged, never replaced — nothing here can delete a typed flag."
      >
        <TextArea
          rows={8}
          spellCheck={false}
          value={rawJson}
          onChange={(event) => setRawJson(event.target.value)}
        />
        <div className="mt-3">
          <Button pending={action.isPending("raw")} disabled={action.busy} onClick={() => void saveRaw()}>
            Merge extra keys
          </Button>
        </div>
      </Card>

      <AdminRolesCard />
    </>
  );
}

/**
 * Grant or revoke the `admin` claim. Lives here rather than on a group page
 * because the claim is global — it is not scoped to a league.
 */
function AdminRolesCard() {
  const action = useAction();
  const { confirm, dialog } = useConfirm();
  const [identifier, setIdentifier] = useState("");
  const [mode, setMode] = useState<"grant" | "revoke">("grant");

  async function apply() {
    const value = identifier.trim();
    if (!value) return;
    const byEmail = value.includes("@");
    const grant = mode === "grant";

    if (!(await confirm({
      title: grant ? "Grant super-admin?" : "Revoke super-admin?",
      body: grant ? (
        <>
          <strong>{value}</strong> gains commissioner-equivalent write access to <em>every</em> league,
          plus this console. Rules fold <code className="font-mono">isSuperAdmin()</code> into{" "}
          <code className="font-mono">isCommissioner()</code>, so the blast radius is global.
        </>
      ) : (
        <>
          <p>
            <strong>{value}</strong> loses admin access. You cannot revoke your own claim — use another
            admin account for that.
          </p>
          <p className="mt-2 text-amber-300">
            A revoke lands when their ID token next refreshes, up to an hour away. For an immediate
            cutoff, disable the account in Firebase Auth as well.
          </p>
        </>
      ),
      tone: grant ? "primary" : "danger",
      confirmLabel: grant ? "Grant admin" : "Revoke admin",
      requireText: value,
    }))) {
      return;
    }

    await action.run("role", async () => {
      const result = await setAdminRole({
        ...(byEmail ? { email: value } : { uid: value }),
        admin: grant,
      });
      setIdentifier("");
      return `${result.email ?? result.uid}: admin = ${result.admin}. ${result.note}`;
    });
  }

  return (
    <Card
      title="Super-admin roles"
      description="The admin claim is global and grants write access to every league. Grant it to as few accounts as possible."
    >
      {dialog}
      <ErrorBanner error={action.error} onDismiss={action.clearError} />
      {action.message ? (
        <div className="mb-3">
          <Banner tone="success" onDismiss={action.clearMessage}>
            {action.message}
          </Banner>
        </div>
      ) : null}
      <div className="flex flex-wrap items-end gap-3">
        <Field label="Email or uid">
          <TextInput
            value={identifier}
            onChange={(event) => setIdentifier(event.target.value)}
            placeholder="owner@pickems.app"
            className="w-80"
          />
        </Field>
        <Field label="Action">
          <Select value={mode} onChange={(event) => setMode(event.target.value as "grant" | "revoke")}>
            <option value="grant">grant admin</option>
            <option value="revoke">revoke admin</option>
          </Select>
        </Field>
        <Button
          variant={mode === "grant" ? "primary" : "danger"}
          pending={action.isPending("role")}
          disabled={action.busy || !identifier.trim()}
          onClick={() => void apply()}
        >
          Apply
        </Button>
      </div>
    </Card>
  );
}
