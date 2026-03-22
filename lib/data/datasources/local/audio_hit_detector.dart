// ─────────────────────────────────────────────────────────────────────────────
// TOMBSTONE — AudioHitDetector (microphone-based drum detection) REMOVED
//
// Microphone input was permanently removed from NavaDrummer on 2026-03-21.
//
// Architecture decision:
//   NavaDrummer supports exactly two input sources:
//     1. ConnectedDrum  — MIDI/USB/BLE hardware drum kit
//     2. OnScreenPad    — virtual pads rendered in the practice screen
//
// The RECORD_AUDIO permission was also removed from AndroidManifest.xml.
// ─────────────────────────────────────────────────────────────────────────────
