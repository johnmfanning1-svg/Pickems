import {
  GoogleAuthProvider,
  onIdTokenChanged,
  signInWithEmailAndPassword,
  signInWithPopup,
  signOut,
  type User,
} from "firebase/auth";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { auth } from "@/lib/firebase";

/**
 * Auth state for the portal, gated on the `admin` custom claim.
 *
 * The UI is *not* the security boundary — Hosting is public and this bundle is
 * readable by anyone. Firestore rules (`isSuperAdmin()`) and the callables'
 * `requireSuperAdmin()` are the real gate. This guard exists so a non-admin gets
 * a clear "not authorized" instead of a screen full of permission errors.
 */

export const UNAUTHORIZED_MESSAGE = "This account is not authorized.";

export type AuthStatus = "loading" | "signedOut" | "unauthorized" | "admin";

interface AuthContextValue {
  status: AuthStatus;
  user: User | null;
  /** Non-null after a rejected sign-in, cleared on the next attempt. */
  error: string | null;
  signInWithEmail: (email: string, password: string) => Promise<void>;
  signInWithGoogle: () => Promise<void>;
  signOutNow: () => Promise<void>;
  clearError: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

/**
 * A claim granted seconds ago is absent from the cached ID token, so a miss on
 * the cached token is re-checked against a forced refresh before we reject.
 */
async function hasAdminClaim(user: User): Promise<boolean> {
  const cached = await user.getIdTokenResult();
  if (cached.claims.admin === true) return true;
  const refreshed = await user.getIdTokenResult(true);
  return refreshed.claims.admin === true;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<AuthStatus>("loading");
  const [user, setUser] = useState<User | null>(null);
  const [error, setError] = useState<string | null>(null);
  // Guards against the explicit post-sign-in check and the token listener both
  // racing to reject the same session.
  const rejecting = useRef(false);

  useEffect(() => {
    // Fires on sign-in, sign-out, and every hourly token refresh — which is what
    // makes a revoked claim lose access without a manual sign-out.
    return onIdTokenChanged(auth, async (next) => {
      if (!next) {
        setUser(null);
        setStatus("signedOut");
        rejecting.current = false;
        return;
      }
      try {
        if (await hasAdminClaim(next)) {
          setUser(next);
          setStatus("admin");
          setError(null);
          return;
        }
      } catch {
        // Treated as unauthorized below: a token we cannot evaluate is not a
        // token we should trust.
      }
      if (rejecting.current) return;
      rejecting.current = true;
      setError(UNAUTHORIZED_MESSAGE);
      setUser(null);
      setStatus("unauthorized");
      // Never leave a half-authenticated session behind.
      await signOut(auth).catch(() => undefined);
      rejecting.current = false;
    });
  }, []);

  /** Rejects and tears the session down when the signed-in account is not an admin. */
  const enforceAdmin = useCallback(async (next: User) => {
    const forced = await next.getIdTokenResult(true);
    if (forced.claims.admin === true) return;
    rejecting.current = true;
    await signOut(auth).catch(() => undefined);
    rejecting.current = false;
    setUser(null);
    setStatus("unauthorized");
    setError(UNAUTHORIZED_MESSAGE);
    throw new Error(UNAUTHORIZED_MESSAGE);
  }, []);

  const signInWithEmail = useCallback(
    async (email: string, password: string) => {
      setError(null);
      const credential = await signInWithEmailAndPassword(auth, email.trim(), password);
      await enforceAdmin(credential.user);
    },
    [enforceAdmin],
  );

  const signInWithGoogle = useCallback(async () => {
    setError(null);
    const provider = new GoogleAuthProvider();
    provider.setCustomParameters({ prompt: "select_account" });
    const credential = await signInWithPopup(auth, provider);
    await enforceAdmin(credential.user);
  }, [enforceAdmin]);

  const signOutNow = useCallback(async () => {
    await signOut(auth);
    setError(null);
  }, []);

  const clearError = useCallback(() => setError(null), []);

  const value = useMemo<AuthContextValue>(
    () => ({ status, user, error, signInWithEmail, signInWithGoogle, signOutNow, clearError }),
    [status, user, error, signInWithEmail, signInWithGoogle, signOutNow, clearError],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

// Colocated with its provider on purpose — the context object is module-private
// so nothing can consume it without going through this hook.
// eslint-disable-next-line react-refresh/only-export-components
export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);
  if (!context) throw new Error("useAuth must be used inside <AuthProvider>.");
  return context;
}
