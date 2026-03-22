#!/usr/bin/env node
// tools/analyze_midi.js
// Reads a MIDI file and prints timing analysis for NavaDrummer sync debugging.
// Usage: node tools/analyze_midi.js assets/midi/te_quiero_hombres_g.mid

const fs = require('fs');
const path = require('path');

const filePath = process.argv[2] || 'assets/midi/te_quiero_hombres_g.mid';
const buf = fs.readFileSync(filePath);
let pos = 0;

function readUint32() {
  const v = buf.readUInt32BE(pos); pos += 4; return v;
}
function readUint16() {
  const v = buf.readUInt16BE(pos); pos += 2; return v;
}
function readByte() {
  return buf[pos++];
}
function readVarLen() {
  let value = 0, b;
  do {
    b = buf[pos++];
    value = (value << 7) | (b & 0x7F);
  } while (b & 0x80);
  return value;
}

// ── Parse header ──────────────────────────────────────────────────────────────
const magic = readUint32();
if (magic !== 0x4D546864) { console.error('Not a MIDI file'); process.exit(1); }
readUint32(); // chunk length (always 6)
const format    = readUint16();
const numTracks = readUint16();
const ppq       = readUint16();

console.log('=== MIDI FILE ANALYSIS ===');
console.log(`File: ${filePath}`);
console.log(`Format: ${format}, Tracks: ${numTracks}, PPQN: ${ppq}`);
console.log('');

// ── Parse all tracks ─────────────────────────────────────────────────────────
const tracks = [];
for (let t = 0; t < numTracks; t++) {
  const trackMagic = readUint32();
  if (trackMagic !== 0x4D54726B) { console.error(`Invalid track ${t}`); process.exit(1); }
  const chunkLen = readUint32();
  const end = pos + chunkLen;
  const events = [];
  let absoluteTick = 0;
  let runningStatus = 0;

  while (pos < end) {
    const delta = readVarLen();
    absoluteTick += delta;

    let statusByte = buf[pos];
    if (statusByte & 0x80) {
      statusByte = readByte();
      if (statusByte !== 0xF0 && statusByte !== 0xF7 && statusByte !== 0xFF) {
        runningStatus = statusByte;
      }
    } else {
      statusByte = runningStatus;
    }

    if (statusByte === 0xFF) {
      const metaType = readByte();
      const metaLen  = readVarLen();
      const metaData = buf.slice(pos, pos + metaLen);
      pos += metaLen;
      events.push({ type: 'meta', tick: absoluteTick, metaType, data: metaData });
    } else if (statusByte === 0xF0 || statusByte === 0xF7) {
      const len = readVarLen();
      pos += len;
    } else {
      const msgType = statusByte & 0xF0;
      const channel = statusByte & 0x0F;
      if (msgType === 0x80 || msgType === 0x90) {
        const note = readByte(), vel = readByte();
        events.push({ type: 'note', tick: absoluteTick, channel, note, vel,
                      isOn: msgType === 0x90 && vel > 0 });
      } else if (msgType === 0xA0 || msgType === 0xB0 || msgType === 0xE0) {
        pos += 2;
      } else if (msgType === 0xC0 || msgType === 0xD0) {
        pos += 1;
      }
    }
  }
  pos = end;
  tracks.push(events);
}

// ── Build tempo map ───────────────────────────────────────────────────────────
const tempoMap = [];
for (const events of tracks) {
  for (const ev of events) {
    if (ev.type === 'meta' && ev.metaType === 0x51 && ev.data.length >= 3) {
      const uspb = (ev.data[0] << 16) | (ev.data[1] << 8) | ev.data[2];
      tempoMap.push({ tick: ev.tick, uspb, bpm: 60000000 / uspb });
    }
  }
}
tempoMap.sort((a, b) => a.tick - b.tick);
if (tempoMap.length === 0) tempoMap.push({ tick: 0, uspb: 500000, bpm: 120 });

console.log('=== TEMPO EVENTS ===');
for (const t of tempoMap) {
  console.log(`  tick=${t.tick.toString().padStart(6)}  uspb=${t.uspb}  bpm=${t.bpm.toFixed(4)}`);
}
console.log('');

// ── Tick→seconds conversion ───────────────────────────────────────────────────
function tickToSeconds(tick) {
  let seconds = 0, lastTick = 0, currentUspb = 500000;
  for (const change of tempoMap) {
    if (change.tick >= tick) break;
    seconds += (change.tick - lastTick) * currentUspb / (ppq * 1000000.0);
    lastTick = change.tick;
    currentUspb = change.uspb;
  }
  seconds += (tick - lastTick) * currentUspb / (ppq * 1000000.0);
  return seconds;
}

// ── Find drum track ───────────────────────────────────────────────────────────
let drumTrack = null;
let maxDrumNotes = 0;
for (let i = 0; i < tracks.length; i++) {
  const ch10Notes = tracks[i].filter(e => e.type === 'note' && e.channel === 9).length;
  if (ch10Notes > maxDrumNotes) { maxDrumNotes = ch10Notes; drumTrack = tracks[i]; }
}
if (!drumTrack) {
  // fallback: track with most notes 35-81
  for (const t of tracks) {
    const n = t.filter(e => e.type === 'note' && e.note >= 35 && e.note <= 81).length;
    if (n > maxDrumNotes) { maxDrumNotes = n; drumTrack = t; }
  }
}

// ── Print first 20 note events ─────────────────────────────────────────────
const noteGM = {
  35: 'KD', 36: 'KD', 38: 'SD', 40: 'SD', 37: 'XS',
  42: 'HH', 44: 'HP', 46: 'OH', 49: 'C1', 55: 'C2',
  51: 'RD', 53: 'RB', 48: 'T1', 47: 'T2', 45: 'T2',
  43: 'FT', 41: 'FT'
};

const noteEvents = (drumTrack || [])
  .filter(e => e.type === 'note' && e.isOn)
  .map(e => ({ ...e, timeSeconds: tickToSeconds(e.tick) }));

noteEvents.sort((a, b) => a.tick - b.tick);

console.log('=== FIRST 20 NOTE EVENTS (drum track) ===');
const first20 = noteEvents.slice(0, 20);
for (const n of first20) {
  const pad = noteGM[n.note] || `N${n.note}`;
  const beat = n.tick / ppq;
  console.log(`  tick=${n.tick.toString().padStart(6)}  beat=${beat.toFixed(3).padStart(8)}  `+
              `time=${n.timeSeconds.toFixed(4).padStart(8)}s  note=${n.note} (${pad})  vel=${n.vel}`);
}
console.log('');

// ── Total duration ────────────────────────────────────────────────────────────
const lastNote = noteEvents[noteEvents.length - 1];
const totalDuration = lastNote ? tickToSeconds(lastNote.tick) + 2.0 : 0;
console.log(`=== TOTAL DURATION ===`);
console.log(`  Last note at: ${lastNote ? tickToSeconds(lastNote.tick).toFixed(3) : 0}s`);
console.log(`  Total (with 2s pad): ${totalDuration.toFixed(3)}s`);
console.log('');

// ── Beat grid ─────────────────────────────────────────────────────────────────
console.log('=== BEAT GRID (first 12 beats) ===');
for (let beat = 0; beat <= 12; beat++) {
  const tick = beat * ppq;
  const t = tickToSeconds(tick);
  console.log(`  beat ${beat.toString().padStart(2)}: tick=${tick.toString().padStart(6)}  time=${t.toFixed(4)}s`);
}
console.log('');

// ── 12/8 analysis ────────────────────────────────────────────────────────────
// In 12/8 time at dotted-quarter=75: one dotted-quarter = 3 eighth notes
// Each measure has 4 dotted-quarter beats = 12 eighth notes
// T_dotted_quarter = 60000/75 = 800ms
// T_eighth = 800/3 = 266.67ms
const firstTempoBpm = tempoMap[0].bpm;
const tBeatMs = 60000.0 / firstTempoBpm;
const tEighthMs = tBeatMs / 3.0; // if 12/8
const tDottedQuarterMs = tBeatMs; // if dotted-quarter IS the beat

console.log('=== TIMING ANALYSIS ===');
console.log(`  First tempo BPM: ${firstTempoBpm.toFixed(4)}`);
console.log(`  T_beat (quarter note): ${tBeatMs.toFixed(2)}ms`);
console.log(`  T_eighth (if 12/8): ${tEighthMs.toFixed(2)}ms`);
console.log(`  T_dotted_quarter (if 12/8 dotted-quarter beat): ${tDottedQuarterMs.toFixed(2)}ms`);
console.log('');

// ── Check if first note aligns with beat grid ─────────────────────────────────
if (noteEvents.length > 0) {
  const firstNoteTime = noteEvents[0].timeSeconds;
  const firstNoteTick = noteEvents[0].tick;
  console.log(`  First note: tick=${firstNoteTick}, time=${firstNoteTime.toFixed(4)}s`);
  console.log(`  First note beat position: ${(firstNoteTick / ppq).toFixed(3)}`);

  // Does first note start at beat 0 or is there a pickup/silence?
  if (firstNoteTime < 0.100) {
    console.log('  NOTE: Chart starts immediately at beat 0 (no audio lead-in gap in chart)');
  } else {
    console.log(`  NOTE: Chart has ${(firstNoteTime * 1000).toFixed(0)}ms gap before first note`);
  }
}

console.log('');
console.log('=== TIME SIGNATURE EVENTS ===');
for (const events of tracks) {
  for (const ev of events) {
    if (ev.type === 'meta' && ev.metaType === 0x58 && ev.data.length >= 2) {
      const num = ev.data[0];
      const den = 1 << ev.data[1];
      const click = ev.data[2];
      const sub = ev.data[3];
      console.log(`  tick=${ev.tick}  time_sig=${num}/${den}  click=${click}  sub=${sub}`);
    }
  }
}
