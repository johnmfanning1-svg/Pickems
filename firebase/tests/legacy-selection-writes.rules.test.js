import { readFileSync, existsSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, deleteDoc, increment } from "firebase/firestore";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";

/**
 * Write shapes from PickService before #107 (3.5.9 live, 3.6.5 TestFlight).
 * Create and delete are transactions / deletes. A swap is `setData` on the
 * same nomination id, rewriting espnEventId and kickoff from the new game.
 * nominationCount is an absolute set after create and an increment after delete.
 * Commissioners use that same in-place setData for someone else's Selection.
 */

const here = dirname(fileURLToPath(import.meta.url));
const GROUP_ID = "group1";
const WEEK_ID = "2026-W3";
const COMMISH = "commish";
const MEMBER = "member";
const OTHER_MEMBER = "member2";
const OUTSIDER = "outsider";

let testEnv;
const rulesLogPath = resolve(here, "..", "firestore-debug.log");
let rulesLogCursor = 0;

const createdAt = new Date("2026-10-01T15:00:00Z");

function futureKickoff(hoursAhead = 48) {
  return new Date(Date.now() + hoursAhead * 60 * 60 * 1000);
}

function pastKickoff() {
  return new Date(Date.now() - 60 * 1000);
}

/** Fields `setData(from:)` writes for a Nomination. Nil logos are omitted. */
function nomination(submittedBy, espnEventId, kickoff, id = espnEventId) {
  return {
    id,
    submittedBy,
    submitterName: submittedBy,
    espnEventId,
    spread: 3.5,
    spreadTeamId: "333",
    homeTeamId: "333",
    homeTeamName: "Georgia",
    homeTeamAbbreviation: "UGA",
    awayTeamId: "61",
    awayTeamName: "Alabama",
    awayTeamAbbreviation: "ALA",
    kickoff,
    createdAt,
  };
}

/** In-place swap: same doc id, owner, and createdAt; the new game's body. */
function swapped(existing, espnEventId, kickoff) {
  return {
    ...existing,
    espnEventId,
    kickoff,
    spread: 6.5,
    spreadTeamId: "61",
    homeTeamId: "61",
    homeTeamName: "Alabama",
    homeTeamAbbreviation: "ALA",
    awayTeamId: "333",
    awayTeamName: "Georgia",
    awayTeamAbbreviation: "UGA",
  };
}

function nominationRef(db, id) {
  return doc(db, "groups", GROUP_ID, "weeks", WEEK_ID, "nominations", id);
}

function weekRef(db) {
  return doc(db, "groups", GROUP_ID, "weeks", WEEK_ID);
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
  rulesLogCursor = existsSync(rulesLogPath) ? statSync(rulesLogPath).size : 0;
});

afterAll(async () => {
  if (existsSync(rulesLogPath)) {
    const fresh = readFileSync(rulesLogPath).subarray(rulesLogCursor).toString("utf8");
    if (fresh.includes("1000 expressions")) {
      throw new Error(
        "Firestore rules hit the 1,000-expression evaluation limit. New emulator log tail:\n" +
          fresh.slice(-2000)
      );
    }
  }
  await testEnv?.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

async function seedSelectionWeek({
  vetoEnabled = false,
  deadlineOffsetMs = 60 * 60 * 1000,
  weekStatus = "selection",
  extraVetoes = [],
} = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "groups", GROUP_ID), {
      id: GROUP_ID,
      name: "Test League",
      inviteCode: "ABC123",
      commissionerId: COMMISH,
      memberIds: [COMMISH, MEMBER, OTHER_MEMBER],
      isPublic: false,
      rules: {
        vetoEnabled,
        vetoVotesNeeded: 2,
        selectionMode: "member",
      },
    });
    await setDoc(doc(db, "inviteCodes", "ABC123"), { groupId: GROUP_ID });
    await setDoc(weekRef(db), {
      id: WEEK_ID,
      seasonYear: 2026,
      weekNumber: 3,
      status: weekStatus,
      slateSize: 12,
      nominationCount: 1,
      selectionMode: "member",
      selectionDeadline: new Date(Date.now() + deadlineOffsetMs),
    });
    const vetoes = vetoEnabled ? [`${MEMBER}_999`, ...extraVetoes] : extraVetoes;
    for (const vetoId of vetoes) {
      const espnEventId = vetoId.slice(vetoId.indexOf("_") + 1);
      const submittedBy = vetoId.slice(0, vetoId.indexOf("_"));
      await setDoc(doc(db, "groups", GROUP_ID, "weeks", WEEK_ID, "vetoes", vetoId), {
        submittedBy,
        espnEventId,
      });
    }
  });
}

async function seedNomination(body, id = body.id) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(nominationRef(ctx.firestore(), id), body);
  });
}

describe.each([
  { label: "off", vetoEnabled: false },
  { label: "on", vetoEnabled: true },
])("pre-#107 nomination writes with vetoes $label", ({ vetoEnabled }) => {
  it("creates a selection by setData on nominations/{espnEventId}", async () => {
    await seedSelectionWeek({ vetoEnabled });
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const kickoff = futureKickoff();
    const body = nomination(MEMBER, "501", kickoff);
    await assertSucceeds(setDoc(nominationRef(memberDb, "501"), body));
    const saved = await assertSucceeds(getDoc(nominationRef(memberDb, "501")));
    expect(saved.data().espnEventId).toBe("501");
    expect(saved.data().submittedBy).toBe(MEMBER);
    expect(saved.data().kickoff.toMillis()).toBe(kickoff.getTime());
  });

  it("deletes the owner's selection while Selections are open", async () => {
    await seedSelectionWeek({ vetoEnabled });
    const kickoff = futureKickoff();
    await seedNomination(nomination(MEMBER, "401", kickoff));
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(deleteDoc(nominationRef(memberDb, "401")));
    const gone = await assertSucceeds(getDoc(nominationRef(memberDb, "401")));
    expect(gone.exists()).toBe(false);
  });

  it("swaps in place when the new game has the same kickoff", async () => {
    await seedSelectionWeek({ vetoEnabled });
    const kickoff = futureKickoff();
    const existing = nomination(MEMBER, "401", kickoff);
    await seedNomination(existing);
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(setDoc(nominationRef(memberDb, "401"), swapped(existing, "402", kickoff)));
    const saved = await assertSucceeds(getDoc(nominationRef(memberDb, "401")));
    expect(saved.id).toBe("401");
    expect(saved.data().espnEventId).toBe("402");
    expect(saved.data().kickoff.toMillis()).toBe(kickoff.getTime());
    expect(saved.data().submittedBy).toBe(MEMBER);
    expect(saved.data().createdAt.toMillis()).toBe(createdAt.getTime());
    expect(saved.data().spread).toBe(6.5);
  });

  it("swaps in place when the new game has a different kickoff", async () => {
    await seedSelectionWeek({ vetoEnabled });
    const kickoff = futureKickoff(72);
    const later = futureKickoff(96);
    const existing = nomination(MEMBER, "401", kickoff);
    await seedNomination(existing);
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(setDoc(nominationRef(memberDb, "401"), swapped(existing, "402", later)));
    const saved = await assertSucceeds(getDoc(nominationRef(memberDb, "401")));
    expect(saved.id).toBe("401");
    expect(saved.data().espnEventId).toBe("402");
    expect(saved.data().kickoff.toMillis()).toBe(later.getTime());
    expect(saved.data().submittedBy).toBe(MEMBER);
  });

  it("updates nominationCount to an absolute total and by increment", async () => {
    await seedSelectionWeek({ vetoEnabled });
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const week = weekRef(memberDb);
    await assertSucceeds(updateDoc(week, { nominationCount: 2 }));
    await assertSucceeds(updateDoc(week, { nominationCount: increment(-1) }));
    const saved = await assertSucceeds(getDoc(week));
    expect(saved.data().nominationCount).toBe(1);
  });

  it("lets the commissioner swap another member's selection in place", async () => {
    await seedSelectionWeek({ vetoEnabled });
    const kickoff = futureKickoff();
    const later = futureKickoff(80);
    const same = nomination(MEMBER, "401", kickoff);
    const other = nomination(MEMBER, "402", kickoff, "402");
    await seedNomination(same);
    await seedNomination(other, "402");
    const commishDb = testEnv.authenticatedContext(COMMISH).firestore();
    await assertSucceeds(setDoc(nominationRef(commishDb, "401"), swapped(same, "501", later)));
    await assertSucceeds(setDoc(nominationRef(commishDb, "402"), swapped(other, "502", kickoff)));
    const changedKickoff = await assertSucceeds(getDoc(nominationRef(commishDb, "401")));
    expect(changedKickoff.data().espnEventId).toBe("501");
    expect(changedKickoff.data().kickoff.toMillis()).toBe(later.getTime());
    expect(changedKickoff.data().submittedBy).toBe(MEMBER);
    const sameKickoff = await assertSucceeds(getDoc(nominationRef(commishDb, "402")));
    expect(sameKickoff.data().espnEventId).toBe("502");
    expect(sameKickoff.data().kickoff.toMillis()).toBe(kickoff.getTime());
    expect(sameKickoff.data().submittedBy).toBe(MEMBER);
  });
});

describe("pre-#107 swaps still cannot move the veto window", () => {
  it("rejects a full overwrite that keeps the game and changes kickoff", async () => {
    await seedSelectionWeek({ vetoEnabled: true });
    const kickoff = futureKickoff();
    const existing = nomination(MEMBER, "401", kickoff);
    await seedNomination(existing);
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const ref = nominationRef(memberDb, "401");
    await assertFails(setDoc(ref, swapped(existing, "401", futureKickoff(90))));
    await assertFails(setDoc(ref, swapped(existing, "401", pastKickoff())));
    const omitted = swapped(existing, "401", kickoff);
    delete omitted.kickoff;
    await assertFails(setDoc(ref, omitted));
    const saved = await assertSucceeds(getDoc(ref));
    expect(saved.data().espnEventId).toBe("401");
    expect(saved.data().kickoff.toMillis()).toBe(kickoff.getTime());
  });

  it("rejects a swap onto a vetoed game, a past kickoff, a new owner, or a closed window", async () => {
    await seedSelectionWeek({
      vetoEnabled: true,
      extraVetoes: [`${MEMBER}_402`],
    });
    const kickoff = futureKickoff();
    const existing = nomination(MEMBER, "401", kickoff);
    await seedNomination(existing);
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const ref = nominationRef(memberDb, "401");
    await assertFails(setDoc(ref, swapped(existing, "402", kickoff)));
    await assertFails(setDoc(ref, swapped(existing, "402", futureKickoff(90))));
    await assertFails(setDoc(ref, swapped(existing, "403", pastKickoff())));
    const stolen = swapped(existing, "403", futureKickoff(90));
    stolen.submittedBy = OTHER_MEMBER;
    await assertFails(setDoc(ref, stolen));

    await seedSelectionWeek({ vetoEnabled: true, deadlineOffsetMs: -60 * 1000 });
    await seedNomination(existing);
    await assertFails(setDoc(ref, swapped(existing, "403", futureKickoff(90))));

    await seedSelectionWeek({ vetoEnabled: true, weekStatus: "picking" });
    await seedNomination(existing);
    await assertFails(setDoc(ref, swapped(existing, "403", futureKickoff(90))));

    const saved = await assertSucceeds(getDoc(ref));
    expect(saved.data().espnEventId).toBe("401");
    expect(saved.data().submittedBy).toBe(MEMBER);
  });

  it("keys the veto to the stored owner and lets the commissioner restore that game", async () => {
    await seedSelectionWeek({
      vetoEnabled: true,
      extraVetoes: [`${MEMBER}_402`, `${OTHER_MEMBER}_403`],
    });
    const kickoff = futureKickoff();
    const existing = nomination(MEMBER, "401", kickoff);
    await seedNomination(existing);
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const otherDb = testEnv.authenticatedContext(OTHER_MEMBER).firestore();
    await assertFails(
      setDoc(nominationRef(otherDb, "401"), swapped(existing, "404", futureKickoff(90)))
    );
    await assertSucceeds(
      setDoc(nominationRef(memberDb, "401"), swapped(existing, "403", futureKickoff(90)))
    );

    await seedNomination(nomination(MEMBER, "401", kickoff));
    const commishDb = testEnv.authenticatedContext(COMMISH).firestore();
    const later = futureKickoff(100);
    await assertSucceeds(
      setDoc(nominationRef(commishDb, "401"), swapped(existing, "402", later))
    );
    const restored = await assertSucceeds(getDoc(nominationRef(commishDb, "401")));
    expect(restored.data().espnEventId).toBe("402");
    expect(restored.data().kickoff.toMillis()).toBe(later.getTime());
    expect(restored.data().submittedBy).toBe(MEMBER);
  });

  it("rejects a swap from an owner who is not a league member", async () => {
    await seedSelectionWeek({ vetoEnabled: true });
    const kickoff = futureKickoff();
    const existing = nomination(OUTSIDER, "401", kickoff);
    await seedNomination(existing);
    const outsiderDb = testEnv.authenticatedContext(OUTSIDER).firestore();
    await assertFails(
      setDoc(nominationRef(outsiderDb, "401"), swapped(existing, "402", futureKickoff(90)))
    );
    const saved = await assertSucceeds(
      getDoc(nominationRef(testEnv.authenticatedContext(MEMBER).firestore(), "401"))
    );
    expect(saved.data().espnEventId).toBe("401");
    expect(saved.data().kickoff.toMillis()).toBe(kickoff.getTime());
  });
});

describe("swap kickoff must be the real game's when the catalog has it", () => {
  async function seedCatalog({ mirror = null, game = null, tally = false } = {}) {
    await seedSelectionWeek({ vetoEnabled: true });
    const saturday = futureKickoff(72);
    const existing = nomination(MEMBER, "401", saturday);
    await seedNomination(existing);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      if (mirror) {
        await setDoc(doc(db, "groups", GROUP_ID, "weeks", WEEK_ID, "gameLock", "current"), {
          kickoffs: mirror,
          liveIds: [],
        });
      }
      if (game) {
        await setDoc(doc(db, "groups", GROUP_ID, "weeks", WEEK_ID, "games", game.id), game.body);
      }
      if (tally) {
        await setDoc(doc(db, "groups", GROUP_ID, "weeks", WEEK_ID, "vetoTallies", "401"), {
          count: 1,
          votesNeeded: 2,
          espnEventId: "401",
        });
      }
    });
    return { saturday, existing };
  }

  it("allows an earlier future kickoff that matches the new game", async () => {
    const thursday = futureKickoff(24);
    const saturday = futureKickoff(72);
    const { existing } = await seedCatalog({
      mirror: { 401: saturday, 402: thursday },
    });
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    await assertSucceeds(
      setDoc(nominationRef(memberDb, "401"), swapped(existing, "402", thursday))
    );
    const saved = await assertSucceeds(getDoc(nominationRef(memberDb, "401")));
    expect(saved.data().espnEventId).toBe("402");
    expect(saved.data().kickoff.toMillis()).toBe(thursday.getTime());
    expect(thursday.getTime()).toBeLessThan(saturday.getTime());
  });

  it("rejects a one-second kickoff and a kickoff years ahead of the real game", async () => {
    const thursday = futureKickoff(24);
    const { saturday, existing } = await seedCatalog({
      mirror: { 401: futureKickoff(72), 402: thursday },
    });
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const ref = nominationRef(memberDb, "401");
    await assertFails(
      setDoc(ref, swapped(existing, "402", new Date(Date.now() + 1000)))
    );
    await assertFails(
      setDoc(ref, swapped(existing, "402", new Date(Date.now() + 5 * 365 * 24 * 60 * 60 * 1000)))
    );
    const saved = await assertSucceeds(getDoc(ref));
    expect(saved.data().espnEventId).toBe("401");
    expect(saved.data().kickoff.toMillis()).toBe(saturday.getTime());
  });

  it("rejects a round trip that moves the original game's kickoff", async () => {
    const thursday = futureKickoff(24);
    const saturday = futureKickoff(72);
    const { existing } = await seedCatalog({
      mirror: { 401: saturday, 402: thursday },
    });
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const ref = nominationRef(memberDb, "401");
    await assertSucceeds(setDoc(ref, swapped(existing, "402", thursday)));
    const onThursday = await assertSucceeds(getDoc(ref));
    await assertFails(setDoc(ref, swapped(onThursday.data(), "401", thursday)));
    await assertFails(setDoc(ref, swapped(onThursday.data(), "401", new Date(Date.now() + 1000))));
    const stillThursday = await assertSucceeds(getDoc(ref));
    expect(stillThursday.data().espnEventId).toBe("402");
    expect(stillThursday.data().kickoff.toMillis()).toBe(thursday.getTime());
    await assertSucceeds(setDoc(ref, swapped(stillThursday.data(), "401", saturday)));
    const restored = await assertSucceeds(getDoc(ref));
    expect(restored.data().espnEventId).toBe("401");
    expect(restored.data().kickoff.toMillis()).toBe(saturday.getTime());
  });

  it("uses the slate doc when the lock mirror has no kickoff for that event", async () => {
    const thursday = futureKickoff(24);
    const { existing } = await seedCatalog({
      game: {
        id: "402",
        body: { espnEventId: "402", kickoff: thursday, status: "scheduled" },
      },
    });
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const ref = nominationRef(memberDb, "401");
    await assertFails(setDoc(ref, swapped(existing, "402", futureKickoff(80))));
    await assertSucceeds(setDoc(ref, swapped(existing, "402", thursday)));
    const saved = await assertSucceeds(getDoc(ref));
    expect(saved.data().espnEventId).toBe("402");
    expect(saved.data().kickoff.toMillis()).toBe(thursday.getTime());
  });

  it("rejects an empty or non-string event id before the veto lookup", async () => {
    const { saturday, existing } = await seedCatalog();
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const ref = nominationRef(memberDb, "401");
    await assertFails(setDoc(ref, { ...swapped(existing, "402", futureKickoff(30)), espnEventId: "" }));
    await assertFails(setDoc(ref, { ...swapped(existing, "402", futureKickoff(30)), espnEventId: 402 }));
    const saved = await assertSucceeds(getDoc(ref));
    expect(saved.data().espnEventId).toBe("401");
    expect(saved.data().kickoff.toMillis()).toBe(saturday.getTime());
  });

  it("rejects a member event change while that nomination's veto tally exists", async () => {
    const thursday = futureKickoff(24);
    const { saturday, existing } = await seedCatalog({
      mirror: { 402: thursday },
      tally: true,
    });
    const memberDb = testEnv.authenticatedContext(MEMBER).firestore();
    const ref = nominationRef(memberDb, "401");
    await assertFails(setDoc(ref, swapped(existing, "402", thursday)));
    await assertSucceeds(setDoc(ref, { ...existing, spread: 9 }));
    const saved = await assertSucceeds(getDoc(ref));
    expect(saved.data().espnEventId).toBe("401");
    expect(saved.data().kickoff.toMillis()).toBe(saturday.getTime());
    expect(saved.data().spread).toBe(9);
    const commishDb = testEnv.authenticatedContext(COMMISH).firestore();
    await assertSucceeds(
      setDoc(nominationRef(commishDb, "401"), swapped(existing, "402", thursday))
    );
    const moved = await assertSucceeds(getDoc(nominationRef(commishDb, "401")));
    expect(moved.data().espnEventId).toBe("402");
    expect(moved.data().kickoff.toMillis()).toBe(thursday.getTime());
  });
});
