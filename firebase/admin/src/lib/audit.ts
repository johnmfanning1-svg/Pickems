import { Timestamp, addDoc, collection, serverTimestamp } from "firebase/firestore";
import { auth, db } from "./firebase";

/**
 * `adminAudit` entries for actions the portal performs as *direct Firestore
 * writes* rather than through a callable. The callables in
 * `functions/src/admin.ts` log themselves; anything written straight from this
 * bundle has to log here or it leaves no trail.
 *
 * Rules make this collection append-only even for admins
 * (`allow update, delete: if false`), so an entry can be written but never
 * rewritten.
 */

/** Firestore rejects `undefined` and cannot store class instances. */
function auditable(value: unknown, depth = 0): unknown {
  if (value === undefined || value === null) return null;
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (depth >= 6) return String(value);
  if (Array.isArray(value)) return value.slice(0, 200).map((item) => auditable(item, depth + 1));
  if (typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [key, inner] of Object.entries(value as Record<string, unknown>)) {
      out[key] = auditable(inner, depth + 1);
    }
    return out;
  }
  if (typeof value === "number" || typeof value === "boolean" || typeof value === "string") {
    return value;
  }
  return String(value);
}

export async function writeAudit(
  action: string,
  targetPath: string,
  before: unknown,
  after: unknown,
): Promise<void> {
  const user = auth.currentUser;
  if (!user) throw new Error("Not signed in.");
  await addDoc(collection(db, "adminAudit"), {
    actorUid: user.uid,
    actorEmail: user.email ?? null,
    action,
    targetPath,
    before: auditable(before),
    after: auditable(after),
    createdAt: serverTimestamp(),
  });
}
