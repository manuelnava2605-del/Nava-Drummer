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

import * as admin from "firebase-admin";
import { onObjectFinalized } from "firebase-functions/v2/storage";

admin.initializeApp();
const db = admin.firestore();

// ── INI parser ────────────────────────────────────────────────────────────────

function parseIni(text: string): Record<string, string> {
  const map: Record<string, string> = {};
  for (const rawLine of text.split("\n")) {
    const line = rawLine.trim();
    if (!line || line.startsWith("[") || line.startsWith(";")) continue;
    const eq = line.indexOf("=");
    if (eq < 0) continue;
    const key = line.substring(0, eq).trim().toLowerCase();
    const val = line.substring(eq + 1).trim();
    if (key) map[key] = val;
  }
  return map;
}

// ── Mapping helpers ───────────────────────────────────────────────────────────

function mapDifficulty(diffStr: string | undefined): string {
  const n = parseInt(diffStr ?? "-1", 10);
  if (n < 0) return "beginner";
  if (n <= 1) return "beginner";
  if (n <= 3) return "intermediate";
  if (n <= 5) return "advanced";
  return "expert";
}

function mapGenre(raw: string | undefined): string {
  const g = (raw ?? "").toLowerCase();
  if (g.includes("metal") || g.includes("rock")) return "rock";
  if (g.includes("pop") || g.includes("wave")) return "pop";
  if (g.includes("jazz")) return "jazz";
  if (g.includes("funk")) return "funk";
  if (g.includes("latin") || g.includes("latino")) return "latin";
  if (g.includes("cristiana") || g.includes("christian") || g.includes("worship")) return "cristiana";
  return "rock";
}

function calcXpReward(diffStr: string | undefined, isPro: boolean): number {
  const n = parseInt(diffStr ?? "0", 10);
  const base = 100 + Math.max(0, Math.min(n, 6)) * 25;
  return isPro ? Math.round(base * 1.5) : base;
}

// ── Cloud Function ────────────────────────────────────────────────────────────

export const onSongIniUploaded = onObjectFinalized(
  { region: "us-central1" },
  async (event) => {
    const filePath = event.data.name; // e.g. "Songs/Coda - Aún/song.ini"
    if (!filePath) return;

    // Only process song.ini files inside Songs/{folder}/
    const match = filePath.match(/^Songs\/([^/]+)\/song\.ini$/i);
    if (!match) return;

    const folderName = match[1]; // "Coda - Aún"
    const docId      = folderName; // Firestore doc ID = folder name

    console.log(`[onSongIniUploaded] Processing: ${filePath} → Songs/${docId}`);

    // ── 1. Download and parse song.ini ──────────────────────────────────────
    const bucket = admin.storage().bucket(event.data.bucket);
    const [iniBytes] = await bucket.file(filePath).download();
    const ini = parseIni(iniBytes.toString("utf-8"));

    const title      = ini["name"]    ?? folderName;
    const artist     = ini["artist"]  ?? "Unknown";
    const genre      = mapGenre(ini["genre"]);
    const difficulty = mapDifficulty(ini["diff_drums"] ?? ini["diff_drums_real"]);
    const bpm        = parseInt(ini["bpm"] ?? "120", 10);
    const songLenMs  = parseInt(ini["song_length"] ?? "0", 10);
    const durationSec = songLenMs > 0 ? Math.round(songLenMs / 1000) : 180;
    const isProDrums = (ini["pro_drums"] ?? "").toLowerCase() === "true";
    const techniqueTag = isProDrums ? "Pro Drums" : undefined;
    const album      = ini["album"]   ?? "";
    const year       = ini["year"]    ?? "";
    const description = album
      ? (year ? `${album} (${year})` : album)
      : ini["loading_phrase"] ?? undefined;

    // ── 2. Read existing document to preserve manual overrides ──────────────
    const docRef  = db.collection("Songs").doc(docId);
    const existing = await docRef.get();
    const prev    = existing.exists ? (existing.data() ?? {}) : {};

    const isNew   = !existing.exists;
    const prevVer = (prev["version"] as number | undefined) ?? 0;
    const newVer  = isNew ? 1 : prevVer + 1;

    // ── 3. Build and write the document ─────────────────────────────────────
    const doc: Record<string, unknown> = {
      title,
      artist,
      difficulty,
      genre,
      bpm,
      durationSeconds:   durationSec,
      storageFolderPath: `Songs/${folderName}`,
      midiStoragePath:   "",       // unused — full package path is in storageFolderPath
      isPremium:         (prev["isPremium"]     as boolean | undefined) ?? false,
      xpReward:          (prev["xpReward"]      as number  | undefined) ?? calcXpReward(ini["diff_drums"], isProDrums),
      requiredLevel:     (prev["requiredLevel"] as number  | undefined) ?? 1,
      order:             (prev["order"]         as number  | undefined) ?? 0,
      version:           newVer,
      ...(techniqueTag ? { techniqueTag } : {}),
      ...(description   ? { description }  : {}),
    };

    await docRef.set(doc, { merge: false }); // full overwrite of auto-fields

    console.log(
      `[onSongIniUploaded] ${isNew ? "Created" : "Updated"} Songs/${docId} ` +
      `v${newVer} — "${artist} - ${title}" (${difficulty}, ${genre})`
    );
  }
);
