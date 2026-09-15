import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  SlidingWindowRateLimit,
  chooseMailBackend,
  clientIp,
  formSubmitUrl,
  parseSupportBody,
  sentRedirectUrl,
  validateSupportPayload,
  web3formsJson,
} from "./supportPayload";

describe("parseSupportBody", () => {
  it("reads JSON objects and trims fields", () => {
    expect(
      parseSupportBody({
        name: "  Sam  ",
        email: "sam@example.com",
        subject: " Help ",
        message: " Kickoff lock? ",
        honey: "",
      })
    ).toEqual({
      name: "Sam",
      email: "sam@example.com",
      subject: "Help",
      message: "Kickoff lock?",
      honey: "",
    });
  });

  it("parses urlencoded bodies including the FormSubmit honeypot name", () => {
    const body = "name=Sam&email=sam%40example.com&message=Hello&_honey=bot";
    expect(parseSupportBody(body, "application/x-www-form-urlencoded")).toEqual({
      name: "Sam",
      email: "sam@example.com",
      subject: "",
      message: "Hello",
      honey: "bot",
    });
  });

  it("parses JSON strings", () => {
    const parsed = parseSupportBody(
      JSON.stringify({ email: "a@b.co", message: "hi", name: "", subject: "" }),
      "application/json"
    );
    expect(parsed.email).toBe("a@b.co");
    expect(parsed.message).toBe("hi");
  });
});

describe("validateSupportPayload", () => {
  const ok = {
    name: "Sam",
    email: "sam@example.com",
    subject: "",
    message: "Need a hand with invite codes.",
    honey: "",
  };

  it("accepts a normal message", () => {
    expect(validateSupportPayload(ok)).toBeNull();
  });

  it("rejects a missing or malformed reply-to", () => {
    expect(validateSupportPayload({ ...ok, email: "" })).toBe("invalid_email");
    expect(validateSupportPayload({ ...ok, email: "not-an-email" })).toBe("invalid_email");
  });

  it("rejects an empty body", () => {
    expect(validateSupportPayload({ ...ok, message: "" })).toBe("empty_message");
  });

  it("rejects oversized fields", () => {
    expect(validateSupportPayload({ ...ok, message: "x".repeat(5001) })).toBe("too_long");
  });
});

describe("mail backends", () => {
  it("prefers Web3Forms so the inbox address never has to leave the server", () => {
    expect(chooseMailBackend("abc", "someone@example.com")).toBe("web3forms");
    expect(chooseMailBackend("", "someone@example.com")).toBe("formsubmit");
    expect(chooseMailBackend("", "")).toBe("none");
  });

  it("builds a FormSubmit URL from the configured inbox, not a hardcoded address", () => {
    expect(formSubmitUrl("ops@example.com")).toBe("https://formsubmit.co/ajax/ops%40example.com");
    expect(formSubmitUrl("ops@example.com")).not.toMatch(/gmail/i);
  });

  it("puts the Web3Forms key in the POST body instead of an email address", () => {
    const body = web3formsJson("test-key", {
      name: "Sam",
      email: "sam@example.com",
      subject: "Invite",
      message: "Code expired",
      honey: "",
    });
    expect(body.access_key).toBe("test-key");
    expect(JSON.stringify(body)).not.toMatch(/johnmfanning1/i);
  });
});

describe("sentRedirectUrl", () => {
  it("stays on the Hosting origin that posted", () => {
    expect(sentRedirectUrl("https://pickems-fb.web.app")).toBe(
      "https://pickems-fb.web.app/support?sent=1"
    );
    expect(sentRedirectUrl("http://127.0.0.1:5000")).toBe("http://127.0.0.1:5000/support?sent=1");
  });

  it("ignores open-redirect hosts", () => {
    expect(sentRedirectUrl("https://evil.example")).toBe(
      "https://pickems-fb.web.app/support?sent=1"
    );
  });
});

describe("rate limit and client IP", () => {
  it("reads the first x-forwarded-for hop", () => {
    expect(
      clientIp({
        headers: { "x-forwarded-for": "1.1.1.1, 2.2.2.2" },
      })
    ).toBe("1.1.1.1");
  });

  it("trips after the window fills", () => {
    let now = 1_000_000;
    const limiter = new SlidingWindowRateLimit(1_000, 3, () => now);
    expect(limiter.tooMany("1.1.1.1")).toBe(false);
    expect(limiter.tooMany("1.1.1.1")).toBe(false);
    expect(limiter.tooMany("1.1.1.1")).toBe(false);
    expect(limiter.tooMany("1.1.1.1")).toBe(true);
    now += 1_001;
    expect(limiter.tooMany("1.1.1.1")).toBe(false);
  });
});

describe("public support page", () => {
  const html = readFileSync(resolve(process.cwd(), "../../web/support.html"), "utf8");

  it("does not publish a personal inbox or mailto", () => {
    expect(html).not.toMatch(/johnmfanning1@gmail\.com/i);
    expect(html).not.toMatch(/mailto:/i);
    expect(html).not.toMatch(/formsubmit/i);
  });

  it("posts to the same-origin Cloud Function rewrite", () => {
    expect(html).toMatch(/action="\/api\/support"/);
  });
});

describe("public docs do not republish the personal inbox", () => {
  const root = resolve(process.cwd(), "../..");
  const files = [
    "web/support.html",
    "web/index.html",
    "web/join.html",
    "docs/DOMAIN.md",
    "docs/privacy-policy.md",
    "docs/privacy-policy.html",
    "docs/terms.md",
    "docs/terms.html",
  ];

  it.each(files)("%s has no johnmfanning1@gmail.com", (rel) => {
    const text = readFileSync(resolve(root, rel), "utf8");
    expect(text).not.toMatch(/johnmfanning1@gmail\.com/i);
  });
});
