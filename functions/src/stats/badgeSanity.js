"use strict";

/**
 * Drops published badges that the server's own numbers contradict.
 *
 * The badge list is computed on the device and mirrored to users/{uid}.
 * Builds before 3.2 counted auto-filled "Off" days as days worked, so they
 * publish streak / perfect-month / days-worked badges the user never earned
 * ("100 Days Straight Worked" beside a real best streak of 16). Those builds
 * stay in the field, so the public profile is filtered here at publish time
 * against facts derived from the worked days the server already trusts.
 *
 * Only badges with a rule below are ever dropped; anything else (hours,
 * overtime, long-shift, level badges, and any badge added later) passes
 * through untouched. The stored list on users/{uid} is not modified.
 */

const MS_DAY = 86400000;

function dayNumber(iso) {
  const [y, m, d] = iso.split("-").map(Number);
  return Math.round(Date.UTC(y, m - 1, d) / MS_DAY);
}

function isoOf(dayNum) {
  return new Date(dayNum * MS_DAY).toISOString().slice(0, 10);
}

/** 0 Sun .. 6 Sat, from the calendar date alone (no time zone involved). */
function weekdayOf(iso) {
  return new Date(dayNumber(iso) * MS_DAY).getUTCDay();
}

function daysInMonth(year, month) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/**
 * @param {string[]} workedDayStrings distinct "yyyy-MM-dd" worked days
 * @param {number} bestStreak longest run of consecutive worked days
 * @param {number} workedShiftCount worked (non-off-day) entries
 */
function workedDayFacts({ workedDayStrings, bestStreak, workedShiftCount }) {
  const days = new Set(Array.isArray(workedDayStrings) ? workedDayStrings : []);
  let saturdays = 0;
  let sundays = 0;
  let perfectWeek = false;
  const byMonth = new Map();

  for (const iso of days) {
    const weekday = weekdayOf(iso);
    if (weekday === 6) saturdays += 1;
    if (weekday === 0) {
      sundays += 1;
      // The app's weeks run Sunday to Saturday for this badge.
      const start = dayNumber(iso);
      let full = true;
      for (let i = 1; i < 7 && full; i++) full = days.has(isoOf(start + i));
      if (full) perfectWeek = true;
    }
    const key = iso.slice(0, 7);
    byMonth.set(key, (byMonth.get(key) || 0) + 1);
  }

  let perfectMonth = false;
  let everyWeekendMonth = false;
  for (const [key, count] of byMonth) {
    const [year, month] = key.split("-").map(Number);
    const total = daysInMonth(year, month);
    if (count === total) perfectMonth = true;
    let weekendsWorked = true;
    for (let d = 1; d <= total && weekendsWorked; d++) {
      const iso = `${key}-${String(d).padStart(2, "0")}`;
      const weekday = weekdayOf(iso);
      if ((weekday === 0 || weekday === 6) && !days.has(iso)) weekendsWorked = false;
    }
    if (weekendsWorked) everyWeekendMonth = true;
  }

  return {
    bestStreak: Math.max(0, Number(bestStreak) || 0),
    shifts: Math.max(0, Number(workedShiftCount) || 0),
    distinctDays: days.size,
    saturdays,
    sundays,
    perfectWeek,
    perfectMonth,
    everyWeekendMonth,
  };
}

const streak = (n) => (f) => f.bestStreak >= n;
const shifts = (n) => (f) => f.shifts >= n;

/** Badge name → what must be true of the worked days for it to be real. */
const RULES = {
  // Consecutive days worked
  "3-Day Streak": streak(3),
  "5-Day Streak": streak(5),
  "No Days Off": streak(7),
  "10-Day Streak": streak(10),
  "14-Day Streak": streak(14),
  "21-Day Streak": streak(21),
  "30-Day Streak": streak(30),
  "60-Day Streak": streak(60),
  "90-Day Streak": streak(90),
  "6-Month Streak": streak(180),
  "1-Year Streak": streak(365),
  "Never Miss": streak(30),
  "No Missed Logs (7 Days)": streak(7),
  "No Missed Logs (30 Days)": streak(30),
  "Daily Logger": streak(30),
  "Restarted Strong": streak(7),
  "No Quit Mentality": streak(30),
  "Relentless": streak(60),
  "No Off Switch": streak(45),
  "Locked In": streak(21),
  "No Days Missed (90 Days)": streak(90),
  "No Days Missed (180 Days)": streak(180),
  "30 Days Straight Worked": streak(30),
  "60 Days Straight Worked": streak(60),
  "100 Days Straight Worked": streak(100),

  // Full weeks and months
  "Perfect Week": (f) => f.perfectWeek,
  "No Days Missed Week": (f) => f.perfectWeek,
  "Logged Every Shift This Week": (f) => f.perfectWeek,
  "Full Grind Week": (f) => f.perfectWeek,
  "Locked-In Week": (f) => f.perfectWeek && f.bestStreak >= 14,
  "Perfect Month": (f) => f.perfectMonth,
  "No Days Missed Month": (f) => f.perfectMonth,
  "Logged Every Shift This Month": (f) => f.perfectMonth,
  "Every Weekend Worked (Month)": (f) => f.everyWeekendMonth,

  // Days worked
  "Consistency King": (f) => f.distinctDays >= 100,
  "Weekend Starter": (f) => f.saturdays >= 3,
  "Saturday Grinder": (f) => f.saturdays >= 10,
  "Sunday Double-Time": (f) => f.sundays >= 2,
  "Sunday Warrior": (f) => f.sundays >= 5,
  "Sunday Demon": (f) => f.sundays >= 6,
  "Weekend Warrior": (f) => f.saturdays + f.sundays >= 20,
  "No Days Off Weekend": (f) => f.saturdays >= 8 && f.sundays >= 8,

  // Shifts logged
  "First Shift Logged": shifts(1),
  "Make It Count": shifts(1),
  "First Week Logged": shifts(5),
  "Work Mode Activated": shifts(7),
  "10 Shifts Logged": shifts(10),
  "Back on Track": shifts(14),
  "Consistent": shifts(20),
  "25 Shifts Logged": shifts(25),
  "Organized Worker": shifts(25),
  "Founding Member": shifts(30),
  "Habit Builder": shifts(30),
  "50 Shifts Logged": shifts(50),
  "Rise & Grind": shifts(50),
  "Work Machine": shifts(60),
  "100 Shifts Logged": shifts(100),
  "Always Tracking": shifts(100),
  "Never Late Logger": shifts(150),
  "200 Shifts Logged": shifts(200),
  "Certified Grinder": shifts(250),
  "Still Going": shifts(365),
  "365 Days Logged": shifts(365),
  "500 Shifts Logged": shifts(500),
  "750 Shifts Logged": shifts(750),
  "1,000 Shifts Logged": shifts(1000),
  "1,500 Shifts Logged": shifts(1500),
  "2,000 Shifts Logged": shifts(2000),
  "3,000 Shifts Logged": shifts(3000),
  "5,000 Shifts Logged": shifts(5000),
};

/**
 * @returns {{ badges: object[], dropped: string[] }} the badges that hold up,
 * in their original order, and the names that were removed.
 */
function sanitizeBadgeSummaries(summaries, stats) {
  if (!Array.isArray(summaries) || summaries.length === 0) return { badges: [], dropped: [] };
  const facts = workedDayFacts(stats || {});
  const badges = [];
  const dropped = [];
  for (const badge of summaries) {
    const name = badge && typeof badge.name === "string" ? badge.name : "";
    const rule = Object.prototype.hasOwnProperty.call(RULES, name) ? RULES[name] : null;
    if (rule && !rule(facts)) dropped.push(name);
    else badges.push(badge);
  }
  return { badges, dropped };
}

module.exports = { sanitizeBadgeSummaries, workedDayFacts };
