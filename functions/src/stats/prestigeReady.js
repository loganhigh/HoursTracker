/**
 * "You can Prestige" pushes — pure copy + reminder logic, no I/O
 * (index.js `notifyOnPrestigeReady` / `prestigeReminderDaily` do the reads
 * and sends; see test/prestigeReady.test.js).
 *
 * Per finished run: one push when the run is first seen finished, then one
 * reminder REMINDER_AFTER_MS later if they still haven't pressed Prestige.
 * Nothing after that for the run — the You tab button stays either way.
 */

const DAY_MS = 24 * 60 * 60 * 1000;
const REMINDER_AFTER_MS = 5 * DAY_MS;

function tierLabel(next, tierNames) {
  const name = tierNames[Math.min(next, tierNames.length - 1)];
  return name ? `P${next} ${name}` : `P${next}`;
}

/** Push copy. `stage` 1 = first push, 2 = the reminder. */
function prestigeReadyMessage(prestige, stage, tierNames = []) {
  const next = (Number(prestige) || 0) + 1;
  const label = tierLabel(next, tierNames);
  if (stage === 2) {
    return {
      title: "Your Prestige is waiting 👑",
      body: `You finished Level 25. Tap to Prestige to ${label} — XP you've earned since carries over.`,
    };
  }
  return {
    title: "Level 25 complete 👑",
    body: `Tap to Prestige to ${label}. Your hours and badges stay, and extra XP carries over.`,
  };
}

/**
 * What to do with one `_prestigeReady/{uid}_{p}` event today.
 * `event` = {prestige, createdAtMs, remindedAtMs?}; `currentPrestige` = the
 * user's gamification prestige now. Returns "remind" | "done" | "wait".
 */
function prestigeReminderDecision(event, currentPrestige, nowMs) {
  if (!event) return "done";
  if (event.remindedAtMs) return "done";
  // Pressed Prestige (or was corrected) since — this run is over.
  if (Number(currentPrestige) !== Number(event.prestige)) return "done";
  const created = Number(event.createdAtMs) || 0;
  if (!created || nowMs - created < REMINDER_AFTER_MS) return "wait";
  return "remind";
}

module.exports = {
  REMINDER_AFTER_MS,
  prestigeReadyMessage,
  prestigeReminderDecision,
};
