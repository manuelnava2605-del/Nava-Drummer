"use strict";
/**
 * NavaDrummer — Cloud Functions
 *
 * onSongIniUploaded
 * ─────────────────
 * Trigger: Storage object finalised at  Songs/{songFolder}/song.ini
 *
 * What it does:
 *   1. Downloads and parses the song.ini content.
 *   2. Reads the existing Firestore document (if any) to preserve manual
 *      fields (isPremium, xpReward, requiredLevel, order).
 *   3. Creates or updates the document in the `Songs` collection.
 *      • New song  → version = 1
 *      • Update    → version incremented by 1 (triggers re-download on clients)
 *
 * Document ID = the Storage folder name, e.g. "Coda - Aún"
 * storageFolderPath = "Songs/Coda - Aún"
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.onSongIniUploaded = void 0;
const admin = require("firebase-admin");
const storage_1 = require("firebase-functions/v2/storage");
admin.initializeApp();
const db = admin.firestore();
// ── INI parser ────────────────────────────────────────────────────────────────
function parseIni(text) {
    const map = {};
    for (const rawLine of text.split("\n")) {
        const line = rawLine.trim();
        if (!line || line.startsWith("[") || line.startsWith(";"))
            continue;
        const eq = line.indexOf("=");
        if (eq < 0)
            continue;
        const key = line.substring(0, eq).trim().toLowerCase();
        const val = line.substring(eq + 1).trim();
        if (key)
            map[key] = val;
    }
    return map;
}
// ── Mapping helpers ───────────────────────────────────────────────────────────
function mapDifficulty(diffStr) {
    const n = parseInt(diffStr !== null && diffStr !== void 0 ? diffStr : "-1", 10);
    if (n < 0)
        return "beginner";
    if (n <= 1)
        return "beginner";
    if (n <= 3)
        return "intermediate";
    if (n <= 5)
        return "advanced";
    return "expert";
}
function mapGenre(raw) {
    const g = (raw !== null && raw !== void 0 ? raw : "").toLowerCase();
    if (g.includes("metal") || g.includes("rock"))
        return "rock";
    if (g.includes("pop") || g.includes("wave"))
        return "pop";
    if (g.includes("jazz"))
        return "jazz";
    if (g.includes("funk"))
        return "funk";
    if (g.includes("latin") || g.includes("latino"))
        return "latin";
    if (g.includes("cristiana") || g.includes("christian") || g.includes("worship"))
        return "cristiana";
    return "rock";
}
function calcXpReward(diffStr, isPro) {
    const n = parseInt(diffStr !== null && diffStr !== void 0 ? diffStr : "0", 10);
    const base = 100 + Math.max(0, Math.min(n, 6)) * 25;
    return isPro ? Math.round(base * 1.5) : base;
}
// ── Cloud Function ────────────────────────────────────────────────────────────
exports.onSongIniUploaded = (0, storage_1.onObjectFinalized)({ region: "us-central1" }, async (event) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q;
    const filePath = event.data.name; // e.g. "Songs/Coda - Aún/song.ini"
    if (!filePath)
        return;
    // Only process song.ini files inside Songs/{folder}/
    const match = filePath.match(/^Songs\/([^/]+)\/song\.ini$/i);
    if (!match)
        return;
    const folderName = match[1]; // "Coda - Aún"
    const docId = folderName; // Firestore doc ID = folder name
    console.log(`[onSongIniUploaded] Processing: ${filePath} → Songs/${docId}`);
    // ── 1. Download and parse song.ini ──────────────────────────────────────
    const bucket = admin.storage().bucket(event.data.bucket);
    const [iniBytes] = await bucket.file(filePath).download();
    const ini = parseIni(iniBytes.toString("utf-8"));
    const title = (_a = ini["name"]) !== null && _a !== void 0 ? _a : folderName;
    const artist = (_b = ini["artist"]) !== null && _b !== void 0 ? _b : "Unknown";
    const genre = mapGenre(ini["genre"]);
    const difficulty = mapDifficulty((_c = ini["diff_drums"]) !== null && _c !== void 0 ? _c : ini["diff_drums_real"]);
    const bpm = parseInt((_d = ini["bpm"]) !== null && _d !== void 0 ? _d : "120", 10);
    const songLenMs = parseInt((_e = ini["song_length"]) !== null && _e !== void 0 ? _e : "0", 10);
    const durationSec = songLenMs > 0 ? Math.round(songLenMs / 1000) : 180;
    const isProDrums = ((_f = ini["pro_drums"]) !== null && _f !== void 0 ? _f : "").toLowerCase() === "true";
    const techniqueTag = isProDrums ? "Pro Drums" : undefined;
    const album = (_g = ini["album"]) !== null && _g !== void 0 ? _g : "";
    const year = (_h = ini["year"]) !== null && _h !== void 0 ? _h : "";
    const description = album
        ? (year ? `${album} (${year})` : album)
        : (_j = ini["loading_phrase"]) !== null && _j !== void 0 ? _j : undefined;
    // ── 2. Read existing document to preserve manual overrides ──────────────
    const docRef = db.collection("Songs").doc(docId);
    const existing = await docRef.get();
    const prev = existing.exists ? ((_k = existing.data()) !== null && _k !== void 0 ? _k : {}) : {};
    const isNew = !existing.exists;
    const prevVer = (_l = prev["version"]) !== null && _l !== void 0 ? _l : 0;
    const newVer = isNew ? 1 : prevVer + 1;
    // ── 3. Build and write the document ─────────────────────────────────────
    const doc = Object.assign(Object.assign({ title,
        artist,
        difficulty,
        genre,
        bpm, durationSeconds: durationSec, storageFolderPath: `Songs/${folderName}`, midiStoragePath: "", isPremium: (_m = prev["isPremium"]) !== null && _m !== void 0 ? _m : false, xpReward: (_o = prev["xpReward"]) !== null && _o !== void 0 ? _o : calcXpReward(ini["diff_drums"], isProDrums), requiredLevel: (_p = prev["requiredLevel"]) !== null && _p !== void 0 ? _p : 1, order: (_q = prev["order"]) !== null && _q !== void 0 ? _q : 0, version: newVer }, (techniqueTag ? { techniqueTag } : {})), (description ? { description } : {}));
    await docRef.set(doc, { merge: false }); // full overwrite of auto-fields
    console.log(`[onSongIniUploaded] ${isNew ? "Created" : "Updated"} Songs/${docId} ` +
        `v${newVer} — "${artist} - ${title}" (${difficulty}, ${genre})`);
});
//# sourceMappingURL=index.js.map