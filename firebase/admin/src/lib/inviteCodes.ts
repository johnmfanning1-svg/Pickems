import { deleteDoc, doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import { db } from "./firebase";

/**
 * Invite-code maintenance, mirroring `GroupService.updateInviteCode` on iOS:
 * `inviteCodes/{code}` is a uniqueness reservation, `groups/{id}.inviteCode` is
 * the display copy, and `publicLeagues/{id}` is a denormalized index that only
 * exists for public leagues.
 *
 * Order matters. The reservation is claimed before the group is repointed, so a
 * failure halfway leaves an orphan reservation (harmless) rather than a group
 * advertising a code nobody holds (a broken join link).
 */

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export function generateInviteCode(length = 6): string {
  const bytes = new Uint32Array(length);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (value) => CODE_ALPHABET[value % CODE_ALPHABET.length]).join("");
}

export function isValidInviteCode(code: string): boolean {
  return /^[A-Z0-9]{4,8}$/.test(code);
}

export async function isInviteCodeFree(code: string): Promise<boolean> {
  const snapshot = await getDoc(doc(db, "inviteCodes", code));
  return !snapshot.exists();
}

/** Finds an unused code, giving up rather than looping forever. */
export async function findFreeInviteCode(attempts = 6): Promise<string> {
  for (let index = 0; index < attempts; index += 1) {
    const candidate = generateInviteCode();
    if (await isInviteCodeFree(candidate)) return candidate;
  }
  throw new Error("Could not find an unused invite code. Try again.");
}

export async function setInviteCode(options: {
  groupId: string;
  newCode: string;
  previousCode: string | null;
  isPublic: boolean;
}): Promise<void> {
  const { groupId, newCode, previousCode, isPublic } = options;
  if (!isValidInviteCode(newCode)) {
    throw new Error("Invite codes are 4–8 characters, A–Z and 0–9 only.");
  }
  if (newCode === previousCode) return;
  if (!(await isInviteCodeFree(newCode))) {
    throw new Error(`Code ${newCode} is already reserved by another league.`);
  }

  await setDoc(doc(db, "inviteCodes", newCode), { groupId });
  await updateDoc(doc(db, "groups", groupId), { inviteCode: newCode });
  if (previousCode) {
    await deleteDoc(doc(db, "inviteCodes", previousCode)).catch(() => undefined);
  }
  if (isPublic) {
    // Best effort: the index is rebuilt by syncPublicLeagueIndex on the next
    // group update, so a failure here is cosmetic and self-healing.
    await updateDoc(doc(db, "publicLeagues", groupId), { inviteCode: newCode }).catch(
      () => undefined,
    );
  }
}
