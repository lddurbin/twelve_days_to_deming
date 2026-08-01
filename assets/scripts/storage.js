// ============================================================
// Storage — guarded localStorage access.
//
// localStorage can throw (disabled, private browsing, quota, etc.);
// every read/write goes through here so that failure mode is handled
// once instead of duplicated per script.
// ============================================================

export function safeGet(key) {
  try {
    return localStorage.getItem(key);
  } catch (e) {
    return null;
  }
}

export function safeSet(key, value) {
  try {
    if (value === null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch (e) {
    // localStorage may be disabled
  }
}

// Loaded as type="module" — see telemetry.js for the same pattern and its
// timing caveat. reading-prefs.js is a classic script and can't `import`
// this, so it reaches these via window.safeGet/safeSet instead.
if (typeof window !== "undefined") {
  window.safeGet = safeGet;
  window.safeSet = safeSet;
}
