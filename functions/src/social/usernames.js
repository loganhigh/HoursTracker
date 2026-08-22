/**
 * Usernames — the handle friends add each other by.
 *
 * One canonical form: lowercase, 3–20 characters, starts with a letter, then
 * letters / digits / underscore. Uniqueness is enforced by the
 * `usernames/{username}` reservation collection (Admin-SDK-only writes, see
 * firestore.rules) inside the claimUsername transaction — never client-side.
 */

const USERNAME_MIN = 3;
const USERNAME_MAX = 20;
const USERNAME_FORMAT = /^[a-z][a-z0-9_]{2,19}$/;

// Handles that would impersonate the app or its staff. Matched on the
// canonical form, so casing and leading/trailing whitespace don't matter.
const RESERVED_USERNAMES = new Set([
  "admin", "admins", "administrator", "administrators", "root", "system",
  "support", "help", "helpdesk", "staff", "team", "official", "moderator",
  "moderators", "mod", "mods", "dev", "devs", "developer", "developers",
  "hourtracker", "hour_tracker", "hourstracker", "hours_tracker", "tracker",
  "trackedhours", "tracked_hours", "apple", "google", "firebase",
  "null", "undefined", "anonymous", "deleted", "unknown", "me", "you",
]);

/** Canonical form of whatever the user typed: trimmed, lowercased, no leading @. */
function normalizeUsername(raw) {
  return String(raw || "")
    .trim()
    .replace(/^@+/, "")
    .toLowerCase();
}

/**
 * Validates a canonical username. Returns null when it is acceptable, or a
 * user-facing reason. `isBlocked` is the shared name-moderation check so
 * handles get the same slur/impersonation filter as display names.
 */
function usernameProblem(username, isBlocked = () => false) {
  if (!username) return "Choose a username.";
  if (username.length < USERNAME_MIN) return `Usernames need at least ${USERNAME_MIN} characters.`;
  if (username.length > USERNAME_MAX) return `Usernames can be at most ${USERNAME_MAX} characters.`;
  if (!/^[a-z]/.test(username)) return "Usernames must start with a letter.";
  if (!USERNAME_FORMAT.test(username)) return "Use letters, numbers, and underscores only.";
  if (RESERVED_USERNAMES.has(username)) return "That username is reserved.";
  if (isBlocked(username)) return "That username isn't allowed.";
  return null;
}

module.exports = {
  USERNAME_MIN,
  USERNAME_MAX,
  USERNAME_FORMAT,
  RESERVED_USERNAMES,
  normalizeUsername,
  usernameProblem,
};
