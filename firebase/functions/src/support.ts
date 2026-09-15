import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import { defineString } from "firebase-functions/params";
import { logger } from "firebase-functions";
import {
  SlidingWindowRateLimit,
  chooseMailBackend,
  clientIp,
  formSubmitJson,
  formSubmitUrl,
  headerValue,
  parseSupportBody,
  sentRedirectUrl,
  validateSupportPayload,
  validationMessage,
  web3formsJson,
  type SupportPayload,
} from "./supportPayload";

/**
 * Optional. Empty default so scoring-function deploys are not blocked on Secret
 * Manager. Set in `functions/.env.pickems-fb` or Cloud Console. Do not commit
 * the real address.
 */
const supportInboxEmail = defineString("SUPPORT_INBOX_EMAIL", {
  default: "",
  description: "Private support inbox. Never put this in public HTML.",
});

const supportWeb3FormsKey = defineString("SUPPORT_WEB3FORMS_ACCESS_KEY", {
  default: "",
  description: "Optional Web3Forms access key used by submitSupport only.",
});

const rateLimit = new SlidingWindowRateLimit();

function db(): admin.firestore.Firestore {
  return admin.firestore();
}

function wantsJson(req: { headers: Record<string, unknown>; method?: string }): boolean {
  const accept = String(headerValue(req.headers as Record<string, string | string[] | undefined>, "accept") ?? "");
  const contentType = String(
    headerValue(req.headers as Record<string, string | string[] | undefined>, "content-type") ?? ""
  );
  return accept.includes("application/json") || contentType.includes("application/json");
}

function trimEnv(value: string | undefined): string | null {
  const trimmed = value?.trim() ?? "";
  return trimmed ? trimmed : null;
}

function requestBody(req: { body?: unknown; rawBody?: Buffer }): unknown {
  if (typeof req.body === "string" && req.body.trim()) return req.body;
  const record = req.body && typeof req.body === "object" && !Buffer.isBuffer(req.body)
    ? (req.body as Record<string, unknown>)
    : null;
  if (record && Object.keys(record).length > 0) return record;
  if (req.rawBody && req.rawBody.length > 0) return req.rawBody.toString("utf8");
  return req.body;
}

async function resolveInboxEmail(): Promise<string | null> {
  const fromParam = trimEnv(supportInboxEmail.value());
  if (fromParam) return fromParam;
  const snap = await db().doc("adminConfig/support").get();
  const stored = snap.data()?.inboxEmail;
  return typeof stored === "string" ? trimEnv(stored) : null;
}

async function resolveWeb3Key(): Promise<string | null> {
  return trimEnv(supportWeb3FormsKey.value());
}

async function postJson(url: string, body: Record<string, string>): Promise<boolean> {
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    if (!response.ok) {
      logger.warn("support mail provider rejected", { status: response.status });
      return false;
    }
    return true;
  } catch (error) {
    logger.warn("support mail provider failed", { error: String(error) });
    return false;
  }
}

export async function deliverSupportMail(
  payload: SupportPayload,
  web3Key: string | null,
  inbox: string | null
): Promise<"web3forms" | "formsubmit" | "none"> {
  const backend = chooseMailBackend(web3Key, inbox);
  if (backend === "web3forms" && web3Key) {
    const ok = await postJson("https://api.web3forms.com/submit", web3formsJson(web3Key, payload));
    return ok ? "web3forms" : "none";
  }
  if (backend === "formsubmit" && inbox) {
    const ok = await postJson(formSubmitUrl(inbox), formSubmitJson(payload));
    return ok ? "formsubmit" : "none";
  }
  return "none";
}

async function persistSupportMessage(
  payload: SupportPayload,
  deliveredVia: string,
  ip: string
): Promise<void> {
  await db().collection("supportMessages").add({
    name: payload.name || null,
    email: payload.email,
    subject: payload.subject || null,
    message: payload.message,
    deliveredVia,
    clientIp: ip,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

export const submitSupport = onRequest(
  {
    region: "us-central1",
    invoker: "public",
    cors: true,
    maxInstances: 4,
  },
  async (req, res) => {
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.set("Allow", "POST, OPTIONS");
      res.status(405).json({ ok: false, error: "POST only." });
      return;
    }

    const ip = clientIp({
      headers: req.headers as Record<string, string | string[] | undefined>,
      ip: req.ip,
    });
    if (rateLimit.tooMany(ip)) {
      logger.warn("support rate limited");
      res.status(429).json({ ok: false, error: "Too many messages. Try again in a few minutes." });
      return;
    }

    const contentType = String(req.headers["content-type"] ?? "");
    const payload = parseSupportBody(requestBody(req), contentType);

    if (payload.honey) {
      logger.info("support honeypot tripped");
      if (wantsJson(req)) {
        res.status(200).json({ ok: true });
      } else {
        res.redirect(
          303,
          sentRedirectUrl(
            headerValue(req.headers as Record<string, string | string[] | undefined>, "origin"),
            headerValue(req.headers as Record<string, string | string[] | undefined>, "referer")
          )
        );
      }
      return;
    }

    const invalid = validateSupportPayload(payload);
    if (invalid) {
      res.status(400).json({ ok: false, error: validationMessage(invalid) });
      return;
    }

    try {
      const [inbox, web3Key] = await Promise.all([resolveInboxEmail(), resolveWeb3Key()]);
      const deliveredVia = await deliverSupportMail(payload, web3Key, inbox);
      await persistSupportMessage(payload, deliveredVia, ip);
      logger.info("support message stored", { deliveredVia });
    } catch (error) {
      logger.error("support submit failed", { error: String(error) });
      res.status(500).json({ ok: false, error: "Could not send that just now. Try again in a minute." });
      return;
    }

    if (wantsJson(req)) {
      res.status(200).json({ ok: true });
      return;
    }
    res.redirect(
      303,
      sentRedirectUrl(
        headerValue(req.headers as Record<string, string | string[] | undefined>, "origin"),
        headerValue(req.headers as Record<string, string | string[] | undefined>, "referer")
      )
    );
  }
);
