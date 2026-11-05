/**
 * Global board chat + direct messages — the pure parts (validation,
 * moderation, @mentions) so they can be unit tested without Firestore.
 *
 * Messages are only ever written by the sendGlobalChatMessage /
 * sendDirectMessage callables (firestore.rules deny client writes), so these
 * checks are the whole gate.
 */

const MESSAGE_MAX = 500;
const MAX_MENTIONS = 5;
/** Seconds between two messages from the same person. */
const MIN_SECONDS_BETWEEN_MESSAGES = 3;

// Chat filter. Word-level only: unlike the name filter it never matches
// across word boundaries, so ordinary sentences ("thanks for the support",
// "class assignment") get through. Hate slurs, sexual content, self-harm
// taunts and strong profanity are refused outright.
const CHAT_BLOCKED_WORDS = new Set([
  "nigger", "niggers", "nigga", "niggas", "faggot", "faggots", "fag", "fags",
  "dyke", "coon", "coons", "spic", "spics", "kike", "kikes", "chink", "chinks",
  "gook", "gooks", "beaner", "beaners", "tranny", "trannies", "wetback",
  "retard", "retarded", "raghead", "towelhead",
  "kys", "rape", "raped", "rapist", "pedo", "pedophile", "molester",
  "porn", "blowjob", "handjob", "dildo", "hentai", "onlyfans", "nudes",
  "cum", "jizz", "cunt", "cunts", "whore", "whores", "slut", "sluts",
  "fuck", "fucking", "fucker", "fuckers", "fucked", "motherfucker",
  "bitch", "bitches", "pussy", "cock", "dick", "dickhead", "asshole",
  "twat", "wanker", "skank",
]);
const CHAT_BLOCKED_PHRASES = ["kill yourself", "kill urself", "killyourself", "go die"];

const LEET = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i" };

function squeezeRuns(s) {
  return s.replace(/(.)\1+/g, "$1");
}

/** Trimmed text with runs of blank lines collapsed. */
function cleanMessage(raw) {
  return String(raw || "")
    .replace(/\r\n?/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function messageIsBlocked(text) {
  const lowered = String(text || "")
    .normalize("NFKC")
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}/gu, "");
  // Mentions are usernames, which already passed the name filter.
  const withoutMentions = lowered.replace(/@[a-z0-9_]+/g, " ");
  const spaced = withoutMentions.replace(/\s+/g, " ");
  if (CHAT_BLOCKED_PHRASES.some((p) => spaced.includes(p))) return true;
  for (const raw of withoutMentions.split(/[^\p{L}\p{N}@$!]+/u)) {
    if (!raw) continue;
    let word = "";
    for (const ch of raw) word += LEET[ch] || ch;
    word = word.replace(/[^a-z]/g, "");
    if (!word) continue;
    if (CHAT_BLOCKED_WORDS.has(word) || CHAT_BLOCKED_WORDS.has(squeezeRuns(word))) return true;
    // "fuuuck", "fucking" variants.
    if (squeezeRuns(word).startsWith("fuck") || squeezeRuns(word).startsWith("motherfuck")) return true;
  }
  return false;
}

/** null when the message can be sent, otherwise a user-facing reason. */
function messageProblem(text) {
  if (!text) return "Type a message first.";
  if (text.length > MESSAGE_MAX) return `Messages can be at most ${MESSAGE_MAX} characters.`;
  if (messageIsBlocked(text)) return "Keep it friendly — that message wasn't sent.";
  return null;
}

/** Unique, lowercased usernames tagged with @ in the text, in order. */
function extractMentions(text) {
  const found = [];
  const re = /(^|[^a-zA-Z0-9_])@([a-zA-Z][a-zA-Z0-9_]{2,19})(?![a-zA-Z0-9_])/g;
  let match;
  while ((match = re.exec(String(text || ""))) !== null) {
    const name = match[2].toLowerCase();
    if (!found.includes(name)) found.push(name);
    if (found.length >= MAX_MENTIONS) break;
  }
  return found;
}

/** One thread per pair of people, whoever writes first. */
function directThreadId(uidA, uidB) {
  return [uidA, uidB].sort().join("_");
}

/** Lock-screen preview: one line, capped. */
function pushPreview(text, max = 160) {
  const line = String(text || "").replace(/\s+/g, " ").trim();
  return line.length > max ? `${line.slice(0, max - 1)}…` : line;
}

module.exports = {
  MESSAGE_MAX,
  MAX_MENTIONS,
  MIN_SECONDS_BETWEEN_MESSAGES,
  cleanMessage,
  messageIsBlocked,
  messageProblem,
  extractMentions,
  directThreadId,
  pushPreview,
};
