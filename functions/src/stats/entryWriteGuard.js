/**
 * Last-writer-wins guard for client entry uploads.
 *
 * Every entry doc carries `modifiedAt` (epoch ms): the app stamps it on each
 * create/edit, admin scripts stamp it on server-side edits, and
 * clientUploadTimeEntriesBatch stamps it when a client sends none. A client
 * that re-uploads its whole local history (the daily repair) may be working
 * from a stale on-device cache — observed live 2026-09-11: a device booted
 * from Firestore's cache and pushed month-old copies over server-side edits
 * before the fresh snapshot ever reached it. Content-only change detection
 * cannot tell "stale" from "edited", so the stamp decides:
 *
 *   - server doc has no stamp            → accept (pre-guard data)
 *   - client sends a newer/equal stamp   → accept (a real edit, or same copy)
 *   - client sends an older stamp        → reject as stale
 *   - client sends NO stamp but server has one → reject: a build that predates
 *     the field cannot know whether its copy is current, and the docs it can
 *     collide with are exactly the ones a newer build or an admin touched.
 *
 * Rejected writes are skipped, never errored, so the repair still lands every
 * doc the device legitimately owns. The device adopts the server copy on its
 * next snapshot (applyRemoteEntries replaces local by id).
 */

/** Firestore Timestamp, {_seconds}, Date, ISO string or number → epoch ms (null if absent/invalid). */
function stampToMillis(v) {
  if (v == null) return null;
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (typeof v === "object" && typeof v._seconds === "number") {
    return v._seconds * 1000 + Math.floor((v._nanoseconds || 0) / 1e6);
  }
  if (v instanceof Date) return Number.isFinite(v.getTime()) ? v.getTime() : null;
  if (typeof v === "string") {
    const ms = Date.parse(v);
    return Number.isFinite(ms) ? ms : null;
  }
  return null;
}

/**
 * @param {object|undefined} existingData stored timeEntries doc (undefined when absent)
 * @param {object} payloadRaw entry as sent by the client
 * @returns {{ stale: boolean, reason: string|null, existingMs: number|null, payloadMs: number|null }}
 */
function staleWriteDecision(existingData, payloadRaw) {
  const existingMs = existingData ? stampToMillis(existingData.modifiedAt) : null;
  const payloadMs = payloadRaw ? stampToMillis(payloadRaw.modifiedAt) : null;
  if (existingMs == null) {
    return { stale: false, reason: null, existingMs, payloadMs };
  }
  if (payloadMs == null) {
    return { stale: true, reason: "unstamped-client", existingMs, payloadMs };
  }
  if (payloadMs < existingMs) {
    return { stale: true, reason: "older-stamp", existingMs, payloadMs };
  }
  return { stale: false, reason: null, existingMs, payloadMs };
}

module.exports = { stampToMillis, staleWriteDecision };
