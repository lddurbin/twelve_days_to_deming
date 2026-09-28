// ============================================================
// Origin handoff — carries a returning reader's saved data from the old
// origin to the new one (#887, part of the domain move in #884).
//
// Everything the site saves is in localStorage, which browsers keep per
// origin. Once #888 redirects deming.leedurbin.co.nz to learndeming.org,
// the new origin would start empty and the reader's workbook would look
// wiped. A hidden iframe can't fetch it either: third-party storage is
// partitioned, so the iframe would see an empty store. The data has to be
// read first-party on the old origin, and carried across in the URL.
//
// Two halves share this one file, so the encoding and decoding can't drift
// apart:
//
//   send()    runs on the old origin's bridge page
//             (deploy/old-origin-bridge.html). It reads the carried keys,
//             serialises them into a `#td-import=` fragment, and
//             location.replace()s to the same path on the new origin.
//   receive() runs on every page of the site, and does nothing unless that
//             fragment is present. It strips the fragment, checks the
//             referrer, and writes the data into keys that are still empty.
//
// A fragment never reaches any server, so privacy.qmd's promise that answers
// never leave the browser still holds: they move between two pages of the
// same browser.
//
// This is a classic script, not a module, and is included first in <head>.
// That is deliberate: modules are deferred, and workbook.js and engagement.js
// cache their key's contents when they're first evaluated. Quarto's OJS
// runtime is itself a module that can evaluate before any of ours, so an
// importing module could run after workbook.js had already cached an empty
// workbook, and the reader's next keystroke would save that empty cache over
// what was just imported. A synchronous script in <head> runs before every
// module, so nothing has read storage yet when it writes.
//
// Being classic, it can't `import`. It exposes its functions as
// window.tdOriginHandoff for the bridge page and the tests.
// ============================================================

(function (root) {
  "use strict";

  var OLD_ORIGIN = "https://deming.leedurbin.co.nz";
  var NEW_ORIGIN = "https://learndeming.org";
  var FRAGMENT_PREFIX = "#td-import=";
  var PAYLOAD_VERSION = 1;

  // Firefox refuses URLs over 1 MiB (network.standard-url.max-length) and
  // Chrome over 2 MiB. Staying under Firefox's limit covers all three.
  // Measured: a full workbook, all 412 fields answered with 1,000 characters
  // each, encodes to about 580,000 characters; the limit is reached at
  // roughly 1,700 characters in every field. Past it, the bridge offers a
  // download instead (see send()).
  var MAX_URL_LENGTH = 1000000;

  // Every key the site writes: its own td:* keys, the Funnel Experiment's
  // dice, and Quarto's runtime preferences (reader mode, tabsets). Matching a
  // prefix, not a fixed list, means a td:* key added later is carried too.
  function isCarriedKey(key) {
    return /^td:/.test(key) || /^quarto-/.test(key) || key === "funnel_dice_sequence";
  }

  // Flat { field: value } maps are merged field by field, so a reader who has
  // already written a few answers on the new origin keeps those and gains the
  // rest. Every other key is taken whole, and only into an empty key.
  //
  // The value checks mirror the owners' read-time validators: workbook.js's
  // isValidAnswers() and engagement.js's isValidRatings(). Those reject the
  // WHOLE stored object if any one value is bad, so a single bad imported
  // value merged in would make the reader's existing answers unreadable. A
  // test checks the workbook rule against isValidAnswers() itself.
  var FIELD_MERGED = {
    "td:workbook": function (v) {
      return typeof v === "string" || typeof v === "number" || v === null;
    },
    "td:ratings": function (v) {
      return v === "up" || v === "down";
    },
  };

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function parseJson(raw) {
    try {
      return JSON.parse(raw);
    } catch (e) {
      return undefined;
    }
  }

  // base64url of the UTF-8 bytes, so answers in any script survive, and no
  // character in the fragment needs percent-encoding.
  function encodePayload(payload) {
    var bytes = new TextEncoder().encode(JSON.stringify(payload));
    var binary = "";
    for (var i = 0; i < bytes.length; i += 0x8000) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }

  // Returns { hash, data } or null. Anything malformed is null, never a throw.
  function decodePayload(encoded) {
    var payload;
    try {
      var b64 = encoded.replace(/-/g, "+").replace(/_/g, "/");
      while (b64.length % 4) b64 += "=";
      var binary = atob(b64);
      var bytes = new Uint8Array(binary.length);
      for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
      payload = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    } catch (e) {
      return null;
    }

    if (!isPlainObject(payload) || payload.v !== PAYLOAD_VERSION || !isPlainObject(payload.data)) {
      return null;
    }
    var keys = Object.keys(payload.data);
    for (var k = 0; k < keys.length; k++) {
      if (!isCarriedKey(keys[k]) || typeof payload.data[keys[k]] !== "string") return null;
    }
    var hash = typeof payload.hash === "string" && payload.hash.charAt(0) === "#" ? payload.hash : "";
    return { hash: hash, data: payload.data };
  }

  // The carried keys in `storage`, as { key: rawString }.
  function collect(storage) {
    var data = {};
    for (var i = 0; i < storage.length; i++) {
      var key = storage.key(i);
      if (key !== null && isCarriedKey(key)) data[key] = storage.getItem(key);
    }
    return data;
  }

  // Merge an imported flat map into an existing one. Returns the string to
  // store, or null when there's nothing to change or the import is unusable.
  function mergeFields(existingRaw, importedRaw, isValidValue) {
    var imported = parseJson(importedRaw);
    if (!isPlainObject(imported)) return null;
    var fields = Object.keys(imported);
    for (var i = 0; i < fields.length; i++) {
      if (!isValidValue(imported[fields[i]])) return null;
    }

    // An existing value the owner can't read is already lost to the reader,
    // so the import may replace it.
    var existing = existingRaw === null ? {} : parseJson(existingRaw);
    if (!isPlainObject(existing) || !Object.keys(existing).every(function (f) { return isValidValue(existing[f]); })) {
      existing = {};
    }

    var added = 0;
    for (var j = 0; j < fields.length; j++) {
      if (!Object.prototype.hasOwnProperty.call(existing, fields[j])) {
        existing[fields[j]] = imported[fields[j]];
        added++;
      }
    }
    return added > 0 ? JSON.stringify(existing) : null;
  }

  // Write `data` into `storage` without overwriting anything the reader
  // already has. Returns the keys that changed.
  function applyImport(data, storage) {
    var changed = [];
    Object.keys(data).forEach(function (key) {
      var existing = storage.getItem(key);
      var next = null;
      if (Object.prototype.hasOwnProperty.call(FIELD_MERGED, key)) {
        next = mergeFields(existing, data[key], FIELD_MERGED[key]);
      } else if (existing === null) {
        next = data[key];
      }
      if (next !== null) {
        storage.setItem(key, next);
        changed.push(key);
      }
    });
    return changed;
  }

  function fromOldOrigin(referrer) {
    try {
      return new URL(referrer).origin === OLD_ORIGIN;
    } catch (e) {
      return false;
    }
  }

  // New-origin half. `env` is { location, history, document, storage }.
  // Returns what it did, for the tests.
  function receive(env) {
    var hash = env.location.hash;
    if (hash.indexOf(FRAGMENT_PREFIX) !== 0) return { status: "none" };

    // Strip the fragment first, whatever happens next, so it never lingers
    // in the address bar, history or a copied link. The page's own fragment
    // (a section link) rides inside the payload and is put back.
    var payload = decodePayload(hash.slice(FRAGMENT_PREFIX.length));
    var restoredHash = payload ? payload.hash : "";
    env.history.replaceState(env.history.state, "", env.location.pathname + env.location.search + restoredHash);

    // Anyone can craft a link carrying this fragment. Only the bridge on the
    // old origin can make the browser report that origin as the referrer.
    // A rejected import still puts the page's own fragment back, so it still
    // needs the scroll.
    if (!fromOldOrigin(env.document.referrer)) return { status: "rejected-referrer", restoredHash: restoredHash };
    if (!payload) return { status: "rejected-payload" };

    var changed;
    try {
      changed = applyImport(payload.data, env.storage);
    } catch (e) {
      // Storage disabled or full: the reader's data is still on the old
      // origin, and the next visit through the bridge tries again.
      return { status: "failed", restoredHash: restoredHash };
    }
    return { status: "imported", changed: changed, restoredHash: restoredHash };
  }

  // Old-origin half. `env` is { location, storage, offerDownload(url, json) }.
  // Returns the URL it navigated to, or null when it offered a download.
  function send(env) {
    var target = NEW_ORIGIN + env.location.pathname + env.location.search;
    var data = {};
    try {
      data = collect(env.storage);
    } catch (e) {
      // Storage unreadable: there's nothing we can carry.
    }

    var url = target + env.location.hash;
    if (Object.keys(data).length > 0) {
      url = target + FRAGMENT_PREFIX + encodePayload({ v: PAYLOAD_VERSION, hash: env.location.hash, data: data });
      if (url.length > MAX_URL_LENGTH) {
        env.offerDownload(target + env.location.hash, JSON.stringify(data, null, 2));
        return null;
      }
    }
    env.location.replace(url);
    return url;
  }

  root.tdOriginHandoff = {
    OLD_ORIGIN: OLD_ORIGIN,
    NEW_ORIGIN: NEW_ORIGIN,
    FRAGMENT_PREFIX: FRAGMENT_PREFIX,
    MAX_URL_LENGTH: MAX_URL_LENGTH,
    isCarriedKey: isCarriedKey,
    encodePayload: encodePayload,
    decodePayload: decodePayload,
    collect: collect,
    mergeFields: mergeFields,
    applyImport: applyImport,
    receive: receive,
    send: send,
    workbookValueIsValid: FIELD_MERGED["td:workbook"],
  };

  if (typeof window !== "undefined" && typeof location !== "undefined" && location.hash.indexOf(FRAGMENT_PREFIX) === 0) {
    var storage = null;
    try {
      storage = window.localStorage;
    } catch (e) {
      // Accessing localStorage itself can throw when it's disabled.
    }
    var result = receive({
      location: location,
      history: history,
      document: document,
      storage: storage || { getItem: function () { throw new Error("no storage"); } },
    });

    // replaceState() doesn't scroll, so a section link carried through the
    // bridge would land at the top of the page. Scroll once it's parsed.
    if (result.restoredHash) {
      document.addEventListener("DOMContentLoaded", function () {
        try {
          var el = document.getElementById(decodeURIComponent(result.restoredHash.slice(1)));
          if (el) el.scrollIntoView();
        } catch (e) {
          // A malformed fragment just means no scroll.
        }
      });
    }
  }
})(typeof globalThis !== "undefined" ? globalThis : this);
