#!/usr/bin/env node
/**
 * XP shadow-migration daily health report (READ-ONLY).
 *
 * Pulls the last 24h of Cloud Functions logs via `firebase-tools functions:log`
 * and reports on the server-XP shadow migration (see recompute.js
 * XP_OWNERSHIP_MODE): recompute volume, shadow MATCH/MISMATCH parity, every
 * level mismatch with a mechanically-attributed reason, plus recompute /
 * leaderboard / transaction / trigger failures.
 *
 * Usage: node scripts/shadow-health-report.mjs [--hours 24] [--lines 3000]
 * Appends each report to scripts/shadow-health/history.log.
 * Performs no writes to Firestore or production config of any kind.
 */

import { execFileSync } from "node:child_process";
import { appendFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");

const args = process.argv.slice(2);
function argValue(flag, fallback) {
  const i = args.indexOf(flag);
  return i >= 0 && args[i + 1] ? Number(args[i + 1]) : fallback;
}
const WINDOW_HOURS = argValue("--hours", 24);
const FETCH_LINES = argValue("--lines", 3000);

const raw = execFileSync(
  "npx",
  ["firebase-tools", "functions:log", "-n", String(FETCH_LINES)],
  { cwd: repoRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }
);

// Log line shape: `2026-07-09T06:36:22.198610Z D ontimeentrywritten: message`
const LINE_RE = /^(\d{4}-\d{2}-\d{2}T[\d:.]+Z)\s+(\S)\s+(\S+?):\s(.*)$/;
const cutoff = Date.now() - WINDOW_HOURS * 3600 * 1000;

const lines = [];
for (const rawLine of raw.split("\n")) {
  const m = rawLine.match(LINE_RE);
  if (!m) continue;
  const ts = Date.parse(m[1]);
  if (!Number.isFinite(ts) || ts < cutoff) continue;
  lines.push({ ts: m[1], epoch: ts, sev: m[2], fn: m[3], msg: m[4] });
}

const field = (msg, key) => {
  const m = msg.match(new RegExp(`${key}=(-?[\\d.]+)`));
  return m ? Number(m[1]) : null;
};
const strField = (msg, key) => {
  const m = msg.match(new RegExp(`${key}=(\\S+)`));
  return m ? m[1] : null;
};
const jsonField = (msg, key) => {
  const m = msg.match(new RegExp(`${key}=(\\{[^}]*\\})`));
  if (!m) return null;
  try { return JSON.parse(m[1]); } catch { return null; }
};

const recomputes = lines.filter((l) => l.msg.includes("recomputeUserStats committed"));
const shadows = lines.filter((l) => l.msg.includes("xpShadow uid="));
const matches = shadows.filter((l) => l.msg.includes("result=MATCH"));
const mismatches = shadows.filter((l) => l.msg.includes("result=MISMATCH"));

// Mechanical reason attribution for a mismatch line: diff the pushed client
// component breakdown (2.3+ builds) against the server's.
function mismatchReason(msg) {
  const client = jsonField(msg, "clientComponents");
  const server = jsonField(msg, "serverComponents");
  if (!client) {
    return "no clientComponents in log (pre-2.3 build hasn't pushed a breakdown yet); " +
      `raw drift=${field(msg, "drift")}`;
  }
  const diffs = [];
  const keys = new Set([...Object.keys(client), ...Object.keys(server || {})]);
  for (const k of keys) {
    const c = Number(client[k]) || 0;
    const s = server && k in server ? Number(server[k]) || 0 : null;
    if (s === null) {
      if (c !== 0) diffs.push({ k, delta: c, note: "client-only component" });
    } else if (c !== s) {
      diffs.push({ k, delta: c - s });
    }
  }
  if (diffs.length === 0) return "components identical — drift is in extras calibration";
  diffs.sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta));
  const label = {
    challenge: "challenge XP (client-only, fluctuates daily/weekly by design)",
    overtime: "overtime XP (client-only, needs device pay rules)",
    adminOffset: "admin XP offset (client-only)",
    streakDays: "worked-day count differs (likely timezone day-boundary)",
    weeklyCompletion: "40h-week count differs (likely week-boundary/timezone)",
    hourly: "hour totals differ — SERVER AND CLIENT SEE DIFFERENT ENTRIES, investigate",
    logging: "shift counts differ — SERVER AND CLIENT SEE DIFFERENT ENTRIES, investigate",
    longShift: "12h-shift count differs",
  };
  return diffs
    .slice(0, 3)
    .map((d) => `${d.k} Δ${d.delta}${label[d.k] ? ` — ${label[d.k]}` : ""}`)
    .join("; ");
}

// Failure sweeps
const failureBuckets = [
  ["Recompute failures", /recomputeUserStats failed/],
  ["Leaderboard delta failures", /applyLeaderboardDeltaForUser.*failed/],
  ["Leaderboard rebuild failures", /updateGlobalLeaderboard.*(failed|error)/i],
  ["Transaction retries/aborts", /ABORTED|cross-transaction contention|too much contention/i],
];
const failureReport = [];
for (const [name, re] of failureBuckets) {
  const hits = lines.filter((l) => re.test(l.msg));
  if (hits.length > 0) {
    failureReport.push(`- ${name}: ${hits.length}`);
    for (const h of hits.slice(0, 5)) {
      failureReport.push(`    ${h.ts} [${h.fn}] ${h.msg.slice(0, 220)}`);
    }
  }
}
// Any other ERROR-severity lines not already bucketed (unexpected trigger failures)
const errorLines = lines.filter(
  (l) => l.sev === "E" && !failureBuckets.some(([, re]) => re.test(l.msg))
);
if (errorLines.length > 0) {
  failureReport.push(`- Other ERROR-severity function logs: ${errorLines.length}`);
  for (const h of errorLines.slice(0, 5)) {
    failureReport.push(`    ${h.ts} [${h.fn}] ${h.msg.slice(0, 220)}`);
  }
}

// Rate over lines that carry the result= token (added 2026-07-09); older
// shadow lines without it are reported separately rather than skewing the rate.
const tokened = matches.length + mismatches.length;
const untokened = shadows.length - tokened;
const matchRate = tokened > 0
  ? ((matches.length / tokened) * 100).toFixed(1)
  : "n/a";

const out = [];
const windowNote = `${WINDOW_HOURS}h window ending ${new Date().toISOString()} (${lines.length} log lines scanned)`;

if (mismatches.length === 0 && failureReport.length === 0) {
  out.push("✅ Shadow Health Report");
  out.push(`- Window: ${windowNote}`);
  out.push(`- Recomputes: ${recomputes.length}`);
  out.push(`- Shadow comparisons: ${shadows.length}`);
  out.push(`- MATCH: ${matches.length}`);
  out.push(`- MISMATCH: 0`);
  out.push(`- Match Rate: ${matchRate}%${untokened > 0 ? ` (${untokened} pre-token shadow lines excluded)` : ""}`);
  out.push("- Recommendation: Continue shadow mode.");
} else {
  out.push("⚠️ Shadow Health Report — attention needed");
  out.push(`- Window: ${windowNote}`);
  out.push(`- Recomputes: ${recomputes.length}`);
  out.push(`- Shadow comparisons: ${shadows.length}`);
  out.push(`- MATCH: ${matches.length}`);
  out.push(`- MISMATCH: ${mismatches.length}`);
  out.push(`- Match Rate: ${matchRate}%${untokened > 0 ? ` (${untokened} pre-token shadow lines excluded)` : ""}`);
  if (mismatches.length > 0) {
    out.push("");
    out.push("LEVEL MISMATCHES:");
    for (const l of mismatches) {
      out.push(
        `- uid=${strField(l.msg, "uid")} at ${l.ts}\n` +
        `    clientXP=${field(l.msg, "clientXP")} serverXP=${field(l.msg, "serverXP")} ` +
        `clientLevel=${field(l.msg, "clientLevel")} serverLevel=${field(l.msg, "serverLevel")} ` +
        `prestige=${field(l.msg, "prestige")} hours=${field(l.msg, "hours")}\n` +
        `    reason: ${mismatchReason(l.msg)}`
      );
    }
  }
  if (failureReport.length > 0) {
    out.push("");
    out.push("FAILURES:");
    out.push(...failureReport);
  }
  out.push("");
  out.push("- Recommendation: HOLD shadow mode; investigate above before any flip.");
}

const report = out.join("\n");
console.log(report);

const historyDir = join(repoRoot, "scripts", "shadow-health");
mkdirSync(historyDir, { recursive: true });
appendFileSync(join(historyDir, "history.log"), report + "\n\n---\n\n");
