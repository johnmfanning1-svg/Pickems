import { useState, type FormEvent } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { UNAUTHORIZED_MESSAGE, useAuth } from "@/auth/AuthContext";
import { Banner, ErrorBanner } from "@/components/Banner";
import { Button } from "@/components/Button";
import { Field, TextInput } from "@/components/Fields";
import { FullPageSpinner } from "@/components/Spinner";
import { describeError } from "@/lib/callables";
import { isFirebaseConfigured, missingFirebaseConfigKeys } from "@/lib/firebase";

export function LoginPage() {
  const { status, error, signInWithEmail, signInWithGoogle } = useAuth();
  const location = useLocation();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [localError, setLocalError] = useState<string | null>(null);
  const [pending, setPending] = useState<"email" | "google" | null>(null);

  if (status === "loading") return <FullPageSpinner label="Checking session…" />;
  if (status === "admin") {
    const from = (location.state as { from?: string } | null)?.from;
    return <Navigate to={from && from !== "/login" ? from : "/"} replace />;
  }

  async function attempt(kind: "email" | "google", action: () => Promise<void>) {
    setPending(kind);
    setLocalError(null);
    try {
      await action();
    } catch (caught) {
      // The claim rejection is already surfaced through context state; anything
      // else is a credential or popup failure worth spelling out.
      const described = describeError(caught);
      setLocalError(described === UNAUTHORIZED_MESSAGE ? null : described);
    } finally {
      setPending(null);
    }
  }

  function onSubmit(event: FormEvent) {
    event.preventDefault();
    void attempt("email", () => signInWithEmail(email, password));
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-4 py-10">
      <div className="w-full max-w-sm space-y-5">
        <div className="text-center">
          <p className="text-sm font-bold uppercase tracking-[0.2em] text-brand">Pickems</p>
          <h1 className="mt-1 text-xl font-semibold text-slate-50">Admin portal</h1>
          <p className="mt-1 text-sm text-slate-500">Super-admin accounts only.</p>
        </div>

        {!isFirebaseConfigured ? (
          <Banner tone="warning" title="Firebase config is missing">
            Copy <code className="font-mono">.env.example</code> to{" "}
            <code className="font-mono">.env.local</code> and fill{" "}
            {missingFirebaseConfigKeys.join(", ")}. Sign-in cannot work until then.
          </Banner>
        ) : null}

        {status === "unauthorized" ? (
          <Banner tone="error" title={UNAUTHORIZED_MESSAGE}>
            That account signed in successfully but does not carry the{" "}
            <code className="font-mono">admin</code> claim, so the session was ended. Ask an existing
            admin to grant it, then sign in again.
          </Banner>
        ) : null}

        <ErrorBanner error={localError ?? (status === "unauthorized" ? null : error)} />

        <form onSubmit={onSubmit} className="space-y-3 rounded-xl border border-ink-600 bg-ink-800 p-4">
          <Field label="Email">
            <TextInput
              type="email"
              autoComplete="username"
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
          </Field>
          <Field label="Password">
            <TextInput
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </Field>
          <Button
            type="submit"
            variant="primary"
            className="w-full"
            pending={pending === "email"}
            disabled={pending != null}
          >
            Sign in
          </Button>

          <div className="flex items-center gap-3 py-1">
            <span className="h-px flex-1 bg-ink-600" />
            <span className="text-xs uppercase tracking-wide text-slate-600">or</span>
            <span className="h-px flex-1 bg-ink-600" />
          </div>

          <Button
            className="w-full"
            pending={pending === "google"}
            disabled={pending != null}
            onClick={() => void attempt("google", signInWithGoogle)}
          >
            Continue with Google
          </Button>
        </form>

        <p className="text-center text-xs text-slate-600">
          Admin rights come from an Auth custom claim, checked with a forced token refresh. A claim
          granted moments ago is live as soon as you sign in here.
        </p>
      </div>
    </div>
  );
}
