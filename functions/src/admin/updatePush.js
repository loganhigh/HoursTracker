// "New Update!" push sent alongside an update announcement. Only users whose
// device last reported an older version (or never reported one) get it, so
// people who already updated aren't pinged.

/** Numeric dotted-version compare ("3.4" < "3.10"); missing parts are 0. */
function isVersionOlder(lhs, rhs) {
  const a = String(lhs || "").split(".").map((p) => parseInt(p, 10) || 0);
  const b = String(rhs || "").split(".").map((p) => parseInt(p, 10) || 0);
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const x = a[i] || 0;
    const y = b[i] || 0;
    if (x !== y) return x < y;
  }
  return false;
}

/** Unknown version (pre-stamping builds) counts as out of date. */
function needsUpdatePush(userData, version) {
  const installed = String(userData?.appVersion || "").trim();
  if (!installed) return true;
  return isVersionOlder(installed, version);
}

function updatePushMessage(version) {
  return {
    title: `Download the latest update v${version}!`,
    body: "Tap to get it on the App Store.",
  };
}

module.exports = { isVersionOlder, needsUpdatePush, updatePushMessage };
