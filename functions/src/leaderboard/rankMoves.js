/**
 * Pure decision logic for global-leaderboard rank-move notifications.
 *
 * Extracted from functions/index.js so every rule here — baselines, overtake
 * attribution, the five-minute inactivity gate, pending coalescing, milestone
 * hysteresis — is plain data-in/data-out and unit-testable without Firestore.
 * index.js owns all I/O (reading boards/presence, sending FCM, writing state);
 * this module owns every decision about WHAT to do.
 *
 * State shape (one entry per uid inside `_leaderboardNotify/state`):
 *   rank:   rank at the last SENT notification (the baseline).
 *   at:     ms timestamp of the last send (drives the throttle).
 *   best:   best milestone threshold ever awarded (e.g. 10 = "entered Top 10"
 *           already sent). Never re-awarded — sync noise around a boundary
 *           must not fire the same milestone twice.
 *   pending:{ rank, delta, overtaker, kind, since } — a move detected while
 *           the user was actively in the app. Held, coalesced against later
 *           moves, and delivered by the flush only after they have been out
 *           of the app for the inactivity window.
 */

const MILESTONES = [100, 50, 25, 10, 3, 1];

/** Five minutes: presence stamps older than this mean "not in the app". */
const INACTIVITY_MS = 5 * 60 * 1000;

/**
 * Which milestone, if any, `rank` newly crosses given the best already
 * awarded. Strictly-better-than-ever semantics: falling back out and
 * re-entering the Top 10 never re-awards it.
 */
function milestoneCrossed(bestAwarded, rank) {
  if (!Number.isFinite(rank) || rank < 1) return null;
  for (const m of [...MILESTONES].reverse()) { // check #1 first, then 3, 10…
    if (rank <= m && (!Number.isFinite(bestAwarded) || m < bestAwarded)) {
      return m;
    }
  }
  return null;
}

/**
 * The closest tracker who actually came past `cand` since their baseline:
 * above them now, below them then. Null when nobody did — a rank can also
 * drop because someone above left the board, which is an adjustment, not an
 * overtake, and must not be reported as one.
 */
function nearestOvertaker(cand, current, prevRankByUid) {
  let best = null;
  for (const entry of current) {
    if (!entry || entry.uid === cand.uid) continue;
    if (!Number.isFinite(entry.rank) || entry.rank >= cand.rank) continue;
    const was = prevRankByUid.get(entry.uid);
    const wasBelow = was === undefined || was > cand.baselineRank;
    if (!wasBelow) continue;
    if (!best || entry.rank > best.rank) best = entry;
  }
  if (!best) return null;
  return { uid: best.uid, name: String(best.name || "").trim() || "Someone" };
}

/**
 * Everyone `climber` moved past since their baseline: below them now, above
 * them then. Empty for a pure adjustment (people above them left the board),
 * which is what keeps "You passed Joey!" honest after a deletion.
 */
function passedUsers(climber, current, prevRankByUid) {
  const passed = [];
  for (const entry of current) {
    if (!entry || entry.uid === climber.uid) continue;
    if (!Number.isFinite(entry.rank) || entry.rank <= climber.rank) continue;
    const was = prevRankByUid.get(entry.uid);
    if (was === undefined || was > climber.baselineRank) continue; // was below or absent
    passed.push({ uid: entry.uid, name: String(entry.name || "").trim() || "Someone" });
  }
  return passed;
}

/**
 * Diff the authoritative board against per-user notified baselines.
 * Pure port of the candidate loop that lived in notifyLeaderboardRankMoves.
 *
 * Returns { candidates, nextState } where nextState carries every board
 * entry's state forward (plus recent off-board entries for enter/exit
 * throttling).
 */
function computeCandidates({ previous, current, state, now, offBoardTtlMs }) {
  const prevRankByUid = new Map(
    (previous || [])
      .filter((e) => e && typeof e.uid === "string" && Number.isFinite(e.rank))
      .map((e) => [e.uid, e.rank])
  );

  const nextState = {};
  const candidates = [];

  for (const entry of current || []) {
    const uid = entry?.uid;
    const rank = entry?.rank;
    if (typeof uid !== "string" || !Number.isFinite(rank)) continue;

    const last = state[uid];
    nextState[uid] = last ? { ...last } : { rank, at: 0 };

    const baseline = last ? last.rank : prevRankByUid.get(uid);
    if (baseline === undefined) {
      candidates.push({ uid, rank, delta: null, baselineRank: null, sortKey: 999 });
    } else if (baseline !== rank) {
      candidates.push({
        uid,
        rank,
        delta: baseline - rank, // positive = climbed
        baselineRank: baseline,
        sortKey: Math.abs(baseline - rank),
      });
    }
  }

  for (const [uid, last] of Object.entries(state || {})) {
    if (!nextState[uid] && last && now - (last.at || 0) < (offBoardTtlMs || 0)) {
      nextState[uid] = { ...last };
    }
  }

  candidates.sort((a, b) => b.sortKey - a.sortKey);
  return { candidates, nextState, prevRankByUid };
}

/**
 * The single decision point for one candidate: send now, hold as pending, or
 * drop. index.js calls this with I/O results (presence, prefs) and acts on
 * the verdict.
 *
 * Inputs:
 *   cand           — from computeCandidates
 *   entry          — the user's (carried-forward) state entry, mutated-safe copy
 *   now            — ms
 *   lastActiveMs   — presence stamp, or null when they have none
 *   alertsEnabled  — user preference
 *   throttleMs     — min gap between sends for one user
 *   overtaker      — nearestOvertaker() result for downward moves (or null)
 *   milestone      — milestoneCrossed() result for upward moves (or null)
 *
 * Returns { action: "send"|"pend"|"skip", entry, notification? }.
 */
function decideCandidate({ cand, entry, now, lastActiveMs, alertsEnabled, throttleMs, overtaker, milestone }) {
  const out = { ...entry };

  if (!alertsEnabled) {
    // Respect the opt-out but advance the baseline so a later opt-in doesn't
    // unleash a backlog of stale moves. Any pending dies with it.
    out.rank = cand.rank;
    out.at = now;
    delete out.pending;
    return { action: "skip", entry: out };
  }

  if (now - (entry.at || 0) < throttleMs) {
    return { action: "skip", entry: out };
  }

  const isActive = Number.isFinite(lastActiveMs) && now - lastActiveMs < INACTIVITY_MS;
  if (isActive) {
    // They're in the app watching the board animate — hold the notification.
    // Baseline (`rank`) deliberately does NOT advance: the eventual send is
    // composed against it, which is what coalesces every move in between.
    out.pending = {
      rank: cand.rank,
      delta: cand.delta,
      baselineRank: cand.baselineRank,
      overtaker: overtaker || null,
      milestone: milestone || null,
      since: entry.pending?.since || now,
    };
    return { action: "pend", entry: out };
  }

  const notification = composeNotification({
    rank: cand.rank,
    delta: cand.delta,
    overtakerName: overtaker?.name || null,
    milestone,
  });
  out.rank = cand.rank;
  out.at = now;
  if (milestone) out.best = milestone;
  delete out.pending;
  return { action: "send", entry: out, notification };
}

/**
 * Resolve one held pending entry during a flush pass.
 *
 * currentRank is the user's rank on the LATEST board (they may have moved
 * again since the pending was written); the send always describes the latest
 * authoritative state, never a replay of intermediate updates.
 *
 * Returns { action: "send"|"hold"|"clear", entry, notification? }.
 */
function resolvePending({ entry, now, lastActiveMs, currentRank, alertsEnabled }) {
  const out = { ...entry };
  const pending = entry.pending;
  if (!pending) return { action: "clear", entry: out };

  if (!alertsEnabled) {
    out.rank = Number.isFinite(currentRank) ? currentRank : pending.rank;
    out.at = now;
    delete out.pending;
    return { action: "clear", entry: out };
  }

  const isActive = Number.isFinite(lastActiveMs) && now - lastActiveMs < INACTIVITY_MS;
  if (isActive) {
    // Came back (or never left). Keep holding — a fresh five-minute absence
    // restarts eligibility, and the refresh keeps the payload current.
    return { action: "hold", entry: out };
  }

  const rank = Number.isFinite(currentRank) ? currentRank : pending.rank;
  const baseline = Number.isFinite(pending.baselineRank) ? pending.baselineRank : entry.rank;
  const delta = pending.delta === null ? null : (Number.isFinite(baseline) ? baseline - rank : pending.delta);

  // Net-zero after coalescing (#10 → #8 → #10): nothing worth saying.
  if (delta === 0) {
    out.rank = rank;
    delete out.pending;
    return { action: "clear", entry: out };
  }

  const milestone = pending.milestone && (!Number.isFinite(out.best) || pending.milestone < out.best)
    ? pending.milestone
    : null;
  const notification = composeNotification({
    rank,
    delta,
    overtakerName: delta !== null && delta < 0 ? (pending.overtaker?.name || null) : null,
    milestone,
  });
  out.rank = rank;
  out.at = now;
  if (milestone) out.best = milestone;
  delete out.pending;
  return { action: "send", entry: out, notification };
}

/** Wording for every rank-move push. One place, so tests pin it. */
function composeNotification({ rank, delta, overtakerName, milestone }) {
  if (milestone === 1) {
    return {
      title: "#1 in the world 🏆",
      body: "You're the top Hour Tracker on the entire global leaderboard!",
    };
  }
  if (milestone) {
    const spots = delta > 1 ? ` You climbed ${delta} spots.` : "";
    return {
      title: `You entered the Top ${milestone}! 🎉`,
      body: `You're now #${rank} on the global leaderboard.${spots}`,
    };
  }
  if (delta === null) {
    return {
      title: "Global leaderboard 🏆",
      body: `You're on the global leaderboard at #${rank}!`,
    };
  }
  if (delta > 0) {
    const spots = delta === 1 ? "1 spot" : `${delta} spots`;
    return {
      title: "You're climbing! 📈",
      body: `You moved up ${spots} to #${rank} on the global leaderboard.`,
    };
  }
  if (overtakerName) {
    return {
      title: `${overtakerName} passed you 👀`,
      body: `${overtakerName} moved ahead of you — you're now #${rank} on the global leaderboard.`,
    };
  }
  // Adjustment: rank fell but nobody actually came past (someone above left).
  return {
    title: "Leaderboard update",
    body: `You slipped to #${rank} on the global leaderboard — log some hours to climb back!`,
  };
}

/**
 * Deterministic id for one meaningful rank transition, so a Cloud Function
 * retry writing the same event collides instead of duplicating. Same
 * baseline→rank pair for the same user = same event.
 */
function eventId(uid, baselineRank, rank) {
  return `${uid}_${baselineRank ?? "enter"}_${rank}`;
}

/** The reusable event record (Section 18): overtakes, climbs, adjustments. */
function buildEvent({ cand, overtaker, passed, milestone, nowMs }) {
  const competitive = cand.delta === null
    || (cand.delta > 0 ? (passed || []).length > 0 : overtaker !== null);
  return {
    id: eventId(cand.uid, cand.baselineRank, cand.rank),
    type: cand.delta === null ? "entered"
      : cand.delta > 0 ? (competitive ? "climb" : "adjustment")
      : (competitive ? "overtaken" : "adjustment"),
    uid: cand.uid,
    oldRank: cand.baselineRank,
    newRank: cand.rank,
    delta: cand.delta,
    overtakerUid: overtaker?.uid || null,
    overtakerName: overtaker?.name || null,
    passedUids: (passed || []).map((p) => p.uid),
    milestone: milestone || null,
    atMs: nowMs,
  };
}

module.exports = {
  MILESTONES,
  INACTIVITY_MS,
  milestoneCrossed,
  nearestOvertaker,
  passedUsers,
  computeCandidates,
  decideCandidate,
  resolvePending,
  composeNotification,
  eventId,
  buildEvent,
};
