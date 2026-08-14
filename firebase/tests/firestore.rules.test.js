import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import {
  doc,
  collection,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  deleteDoc,
  deleteField,
  query,
  where,
  serverTimestamp,
} from "firebase/firestore";
import { afterAll, afterEach, beforeAll, describe, it } from "vitest";

const here = dirname(fileURLToPath(import.meta.url));

const GROUP_ID = "group1";
const WEEK_ID = "2026-W3";
const COMMISH = "commish";
const MEMBER = "member";
const OTHER_MEMBER = "member2";
const OUTSIDER = "outsider";
const ADMIN_UID = "superadmin";

let testEnv;

/** Signed-in context with the super-admin custom claim. */
function adminCtx() {
  return testEnv.authenticatedContext(ADMIN_UID, { admin: true });
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "groups", GROUP_ID), {
      id: GROUP_ID,
      name: "Test League",
      inviteCode: "ABC123",
      commissionerId: COMMISH,
      memberIds: [COMMISH, MEMBER, OTHER_MEMBER],
      isPublic: false,
    });
    for (const uid of [COMMISH, MEMBER, OTHER_MEMBER]) {
      await setDoc(doc(db, "groups", GROUP_ID, "members", uid), {
        id: uid,
        displayName: uid,
        avatarColorHex: "#DC2626",
        role: uid === COMMISH ? "commissioner" : "member",
        seasonWins: 0,
        seasonLosses: 0,
      });
    }
    // `picking` with a future deadline: picks are open and not yet public.
    await setDoc(doc(db, "groups", GROUP_ID, "weeks", WEEK_ID), {
      id: WEEK_ID,
      seasonYear: 2026,
      weekNumber: 3,
      status: "picking",
      slateSize: 5,
      nominationCount: 5,
      pickDeadline: new Date(Date.now() + 60 * 60 * 1000),
    });
    for (const uid of [MEMBER, OTHER_MEMBER]) {
      await setDoc(doc(db, "groups", GROUP_ID, "weeks", WEEK_ID, "picks", uid), {
        id: uid,
        userId: uid,
        displayName: uid,
        picks: { game1: "home" },
        isLocked: false,
      });
    }
    await setDoc(doc(db, "groups", GROUP_ID, "messages", "msg1"), {
      id: "msg1",
      groupId: GROUP_ID,
      weekId: null,
      userId: MEMBER,
      displayName: MEMBER,
      avatarColorHex: "#DC2626",
      text: "roll tide",
      createdAt: new Date(),
      isDeleted: false,
      reportCount: 0,
    });
    await setDoc(doc(db, "appConfig", "live"), { chatEnabled: true, minimumBuild: 230 });
  });
}

function newMessage(uid, overrides = {}) {
  return {
    id: "new1",
    groupId: GROUP_ID,
    weekId: null,
    userId: uid,
    displayName: uid,
    avatarColorHex: "#DC2626",
    text: "hello",
    createdAt: serverTimestamp(),
    isDeleted: false,
    reportCount: 0,
    ...overrides,
  };
}

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "pickems-rules-test",
    firestore: {
      rules: readFileSync(resolve(here, "..", "firestore.rules"), "utf8"),
      host: process.env.FIRESTORE_EMULATOR_HOST?.split(":")[0] ?? "127.0.0.1",
      port: Number(process.env.FIRESTORE_EMULATOR_HOST?.split(":")[1] ?? 8080),
    },
  });
});

afterAll(async () => {
  await testEnv?.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

describe("chat messages", () => {
  it("lets a member read the thread and keeps a non-member out", async () => {
    await seed();
    const messages = collection(testEnv.authenticatedContext(MEMBER).firestore(), "groups", GROUP_ID, "messages");
    await assertSucceeds(getDocs(messages));

    const outsiderMessages = collection(
      testEnv.authenticatedContext(OUTSIDER).firestore(),
      "groups",
      GROUP_ID,
      "messages"
    );
    await assertFails(getDocs(outsiderMessages));
  });

  it("lets a super admin read a thread in a group they are not in", async () => {
    await seed();
    const messages = collection(adminCtx().firestore(), "groups", GROUP_ID, "messages");
    await assertSucceeds(getDocs(messages));
  });

  it("accepts a well-formed message from a member", async () => {
    await seed();
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(
      setDoc(doc(db, "groups", GROUP_ID, "messages", "new1"), newMessage(MEMBER))
    );
  });

  it("rejects a spoofed author, empty text, and 501 characters", async () => {
    await seed();
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    const ref = doc(db, "groups", GROUP_ID, "messages", "new1");

    await assertFails(setDoc(ref, newMessage(MEMBER, { userId: OTHER_MEMBER })));
    await assertFails(setDoc(ref, newMessage(MEMBER, { text: "" })));
    await assertFails(setDoc(ref, newMessage(MEMBER, { text: "x".repeat(501) })));
    await assertSucceeds(setDoc(ref, newMessage(MEMBER, { text: "x".repeat(500) })));
  });

  it("rejects a client-forged reportCount or backdated createdAt", async () => {
    await seed();
    const db = testEnv.authenticatedContext(MEMBER).firestore();
    const ref = doc(db, "groups", GROUP_ID, "messages", "new1");

    await assertFails(setDoc(ref, newMessage(MEMBER, { reportCount: 3 })));
    await assertFails(setDoc(ref, newMessage(MEMBER, { isDeleted: true })));
    // A backdated timestamp would let a client pin a message to the top.
    await assertFails(setDoc(ref, newMessage(MEMBER, { createdAt: new Date(0) })));
  });

  it("lets the author edit text but not another member", async () => {
    await seed();
    const authorDb = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(
      updateDoc(doc(authorDb, "groups", GROUP_ID, "messages", "msg1"), { text: "war eagle" })
    );

    const otherDb = testEnv.authenticatedContext(OTHER_MEMBER).firestore();
    await assertFails(
      updateDoc(doc(otherDb, "groups", GROUP_ID, "messages", "msg1"), { text: "hacked" })
    );
  });

  it("lets a non-author change only reactions", async () => {
    await seed();
    const db = testEnv.authenticatedContext(OTHER_MEMBER).firestore();
    const ref = doc(db, "groups", GROUP_ID, "messages", "msg1");

    await assertSucceeds(updateDoc(ref, { reactions: { "🔥": [OTHER_MEMBER] } }));
    // Reactions may not be used as a trojan horse for text or the report count.
    await assertFails(updateDoc(ref, { reactions: { "🔥": [OTHER_MEMBER] }, text: "nope" }));
    await assertFails(updateDoc(ref, { reportCount: 5 }));
  });

  it("lets the commissioner soft-delete and a super admin hard-delete", async () => {
    await seed();
    const commishDb = testEnv.authenticatedContext(COMMISH).firestore();
    await assertSucceeds(
      updateDoc(doc(commishDb, "groups", GROUP_ID, "messages", "msg1"), { isDeleted: true })
    );
    await assertSucceeds(deleteDoc(doc(adminCtx().firestore(), "groups", GROUP_ID, "messages", "msg1")));
  });

  it("lets a member report a message only under their own uid", async () => {
    await seed();
    const db = testEnv.authenticatedContext(OTHER_MEMBER).firestore();
    const base = ["groups", GROUP_ID, "messages", "msg1", "reports"];
    await assertSucceeds(
      setDoc(doc(db, ...base, OTHER_MEMBER), {
        reporterUid: OTHER_MEMBER,
        reason: "abuse",
        createdAt: serverTimestamp(),
      })
    );
    await assertFails(
      setDoc(doc(db, ...base, MEMBER), {
        reporterUid: MEMBER,
        reason: "abuse",
        createdAt: serverTimestamp(),
      })
    );
  });
});

describe("appConfig and adminAudit", () => {
  it("lets any signed-in client read appConfig but only an admin write it", async () => {
    await seed();
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(getDoc(doc(memberDb, "appConfig", "live")));
    await assertFails(updateDoc(doc(memberDb, "appConfig", "live"), { chatEnabled: false }));

    await assertSucceeds(
      updateDoc(doc(adminCtx().firestore(), "appConfig", "live"), { chatEnabled: false })
    );
  });

  it("keeps adminAudit admin-only and append-only", async () => {
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    await assertFails(setDoc(doc(memberDb, "adminAudit", "e1"), { action: "nope" }));
    await assertFails(getDoc(doc(memberDb, "adminAudit", "e1")));

    const adminDb = adminCtx().firestore();
    await assertSucceeds(
      setDoc(doc(adminDb, "adminAudit", "e1"), {
        actorUid: ADMIN_UID,
        action: "adminSetWeekStatus",
        targetPath: `groups/${GROUP_ID}`,
        createdAt: serverTimestamp(),
      })
    );
    await assertSucceeds(getDoc(doc(adminDb, "adminAudit", "e1")));
    await assertFails(updateDoc(doc(adminDb, "adminAudit", "e1"), { action: "tampered" }));
    await assertFails(deleteDoc(doc(adminDb, "adminAudit", "e1")));
  });
});

describe("super admin blast radius", () => {
  it("lets an admin write a group they are not a member of", async () => {
    await seed();
    const adminDb = adminCtx().firestore();
    await assertSucceeds(updateDoc(doc(adminDb, "groups", GROUP_ID), { name: "Renamed by admin" }));
    await assertSucceeds(
      updateDoc(doc(adminDb, "groups", GROUP_ID, "weeks", WEEK_ID), { slateSize: 8 })
    );
    await assertSucceeds(getDocs(collection(adminDb, "groups", GROUP_ID, "members")));
  });

  it("still blocks a signed-in non-admin, non-member from the same writes", async () => {
    await seed();
    const outsiderDb = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(updateDoc(doc(outsiderDb, "groups", GROUP_ID), { name: "hijacked" }));
    await assertFails(
      updateDoc(doc(outsiderDb, "groups", GROUP_ID, "weeks", WEEK_ID), { slateSize: 99 })
    );
    await assertFails(getDocs(collection(outsiderDb, "groups", GROUP_ID, "members")));
    // The unscoped group list is the claim's privilege, not any signed-in user's.
    await assertFails(getDocs(collection(outsiderDb, "groups")));
    await assertSucceeds(getDocs(collection(adminCtx().firestore(), "groups")));
  });

  it("keeps the membership-scoped group list working for members", async () => {
    await seed();
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(
      getDocs(query(collection(memberDb, "groups"), where("memberIds", "array-contains", MEMBER)))
    );
  });
});

describe("existing invariants (regression)", () => {
  it("keeps a member's own pick readable pre-deadline and others' hidden", async () => {
    await seed();
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const own = doc(memberDb, "groups", GROUP_ID, "weeks", WEEK_ID, "picks", MEMBER);
    const theirs = doc(memberDb, "groups", GROUP_ID, "weeks", WEEK_ID, "picks", OTHER_MEMBER);

    await assertSucceeds(getDoc(own));
    await assertFails(getDoc(theirs));
    // The admin portal's pick grid depends on this read.
    await assertSucceeds(
      getDoc(doc(adminCtx().firestore(), "groups", GROUP_ID, "weeks", WEEK_ID, "picks", OTHER_MEMBER))
    );
  });

  it("keeps the commissioner week field allow-list in force for the commissioner", async () => {
    await seed();
    const commishDb = testEnv.authenticatedContext(COMMISH).firestore();
    const week = doc(commishDb, "groups", GROUP_ID, "weeks", WEEK_ID);

    await assertSucceeds(updateDoc(week, { status: "locked", lockedAt: new Date() }));
    // slateSize alone is not on the allow-list once the week left selection.
    await assertFails(updateDoc(week, { slateSize: 12 }));
  });

  it("lets the commissioner set a selection deadline and sync slate knobs while selecting", async () => {
    await seed();
    const adminDb = testEnv.authenticatedContext(COMMISH).firestore();
    // Reset week to selection for this case.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), "groups", GROUP_ID, "weeks", WEEK_ID),
        {
          id: WEEK_ID,
          status: "selection",
          slateSize: 12,
          selectionMode: "member",
          selectionsPerMember: 3,
          nominationCount: 0,
        },
        { merge: true }
      );
    });
    const week = doc(adminDb, "groups", GROUP_ID, "weeks", WEEK_ID);
    await assertSucceeds(
      updateDoc(week, {
        selectionDeadline: new Date(),
        selectionDeadlineSetAt: new Date(),
        selectionDeadlineSetBy: COMMISH,
      })
    );
    await assertSucceeds(
      updateDoc(week, {
        slateSize: 9,
        selectionMode: "member",
        selectionsPerMember: 3,
      })
    );
  });

  it("lets the commissioner extend pickDeadline alone and reopen a locked week", async () => {
    await seed();
    const commishDb = testEnv.authenticatedContext(COMMISH).firestore();
    const week = doc(commishDb, "groups", GROUP_ID, "weeks", WEEK_ID);

    await assertSucceeds(
      updateDoc(week, {
        pickDeadline: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      })
    );

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), "groups", GROUP_ID, "weeks", WEEK_ID),
        {
          status: "locked",
          lockedAt: new Date(),
          pickDeadline: new Date(Date.now() - 60 * 1000),
        },
        { merge: true }
      );
    });

    await assertSucceeds(
      updateDoc(week, {
        status: "picking",
        pickDeadline: new Date(Date.now() + 3 * 24 * 60 * 60 * 1000),
        lockedAt: deleteField(),
      })
    );
  });

  it("lets the commissioner reopen Selections after lock-early", async () => {
    await seed();
    const commishDb = testEnv.authenticatedContext(COMMISH).firestore();
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const week = doc(commishDb, "groups", GROUP_ID, "weeks", WEEK_ID);

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), "groups", GROUP_ID, "weeks", WEEK_ID),
        {
          status: "picking",
          lockedAt: new Date(),
          selectionDeadline: new Date(Date.now() - 60 * 1000),
          selectionDeadlineSetAt: new Date(),
          selectionDeadlineSetBy: COMMISH,
          selectionDeadlinePassedNotified: true,
        },
        { merge: true }
      );
    });

    await assertSucceeds(
      updateDoc(week, {
        status: "selection",
        lockedAt: deleteField(),
      })
    );
    await assertSucceeds(
      updateDoc(week, {
        selectionDeadline: deleteField(),
        selectionDeadlineSetAt: deleteField(),
        selectionDeadlineSetBy: deleteField(),
        selectionDeadlinePassedNotified: deleteField(),
      })
    );
    await assertFails(
      updateDoc(doc(memberDb, "groups", GROUP_ID, "weeks", WEEK_ID), {
        status: "selection",
      })
    );
  });

  it("keeps submissions readable by members and picks unforgeable by others", async () => {
    await seed();
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(
      setDoc(doc(memberDb, "groups", GROUP_ID, "weeks", WEEK_ID, "submissions", MEMBER), {
        id: MEMBER,
        userId: MEMBER,
        displayName: MEMBER,
        isLocked: false,
      })
    );
    await assertFails(
      setDoc(doc(memberDb, "groups", GROUP_ID, "weeks", WEEK_ID, "picks", OTHER_MEMBER), {
        id: OTHER_MEMBER,
        userId: OTHER_MEMBER,
        displayName: OTHER_MEMBER,
        picks: {},
        isLocked: false,
      })
    );
  });
});

describe("audit hardening (inviteCodes, member fields, pick delete, group create)", () => {
  it("allows invite code get but denies listing all codes", async () => {
    await seed();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "inviteCodes", "ABC123"), { groupId: GROUP_ID });
      await setDoc(doc(ctx.firestore(), "inviteCodes", "XYZ999"), { groupId: "other" });
    });
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(getDoc(doc(memberDb, "inviteCodes", "ABC123")));
    await assertFails(getDocs(collection(memberDb, "inviteCodes")));
  });

  it("blocks a member from rewriting their own seasonWins", async () => {
    await seed();
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    await assertFails(
      updateDoc(doc(memberDb, "groups", GROUP_ID, "members", MEMBER), { seasonWins: 99 })
    );
    await assertSucceeds(
      updateDoc(doc(memberDb, "groups", GROUP_ID, "members", MEMBER), {
        displayName: "Updated",
      })
    );
  });

  it("blocks self-delete of picks after the deadline", async () => {
    await seed();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "groups", GROUP_ID, "weeks", WEEK_ID), {
        pickDeadline: new Date(Date.now() - 60 * 1000),
        status: "picking",
      });
    });
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    await assertFails(
      deleteDoc(doc(memberDb, "groups", GROUP_ID, "weeks", WEEK_ID, "picks", MEMBER))
    );
  });

  it("lets the commissioner change only spread fields on a slate game", async () => {
    await seed();
    const gamePath = ["groups", GROUP_ID, "weeks", WEEK_ID, "games", "401671749"];
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), ...gamePath), {
        id: "401671749",
        espnEventId: "401671749",
        homeTeamId: "333",
        homeTeamName: "Alabama",
        awayTeamId: "61",
        awayTeamName: "Georgia",
        spread: 3.5,
        spreadTeamId: "333",
        status: "scheduled",
      });
    });

    const commishDb = testEnv.authenticatedContext(COMMISH).firestore();
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const game = doc(commishDb, ...gamePath);

    await assertSucceeds(updateDoc(game, { spread: 7, spreadTeamId: "61" }));
    await assertFails(updateDoc(game, { spread: 7, homeTeamName: "Bama" }));
    await assertFails(
      updateDoc(doc(memberDb, ...gamePath), { spread: 10, spreadTeamId: "333" })
    );
  });

  it("rejects group create that spoofs commissioner or extra members", async () => {
    const outsiderDb = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(doc(outsiderDb, "groups", "spoof1"), {
        id: "spoof1",
        name: "Hijack",
        inviteCode: "HIJACK",
        commissionerId: COMMISH,
        memberIds: [OUTSIDER],
        isPublic: false,
      })
    );
    await assertFails(
      setDoc(doc(outsiderDb, "groups", "spoof2"), {
        id: "spoof2",
        name: "Force add",
        inviteCode: "FORCE1",
        commissionerId: OUTSIDER,
        memberIds: [OUTSIDER, MEMBER],
        isPublic: false,
      })
    );
    await assertSucceeds(
      setDoc(doc(outsiderDb, "groups", "legit1"), {
        id: "legit1",
        name: "Legit",
        inviteCode: "LEGIT1",
        commissionerId: OUTSIDER,
        memberIds: [OUTSIDER],
        isPublic: false,
      })
    );
  });
});

describe("user profile reads", () => {
  it("lets a user read their own doc and blocks other signed-in users", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users", MEMBER), {
        displayName: MEMBER,
        fcmToken: "secret-token",
      });
    });
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const outsiderDb = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertSucceeds(getDoc(doc(memberDb, "users", MEMBER)));
    await assertFails(getDoc(doc(outsiderDb, "users", MEMBER)));
    await assertSucceeds(getDoc(doc(adminCtx().firestore(), "users", MEMBER)));
  });
});
