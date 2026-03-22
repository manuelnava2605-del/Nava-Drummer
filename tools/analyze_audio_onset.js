#!/usr/bin/env node
// tools/analyze_audio_onset.js
// Analyzes M4A/MP4 file structure to estimate audio lead-in silence.
// Reads ISOBMFF box structure (ftyp, moov, mdat) without requiring decoding.
// Usage: node tools/analyze_audio_onset.js assets/backing_tracks/te_quiero_hombres_g.m4a

const fs = require('fs');
const path = require('path');

const filePath = process.argv[2] || 'assets/backing_tracks/te_quiero_hombres_g.m4a';

let buf;
try {
  buf = fs.readFileSync(filePath);
} catch (e) {
  console.error(`Cannot read file: ${filePath}`);
  process.exit(1);
}

console.log('=== M4A/MP4 AUDIO ONSET ANALYSIS ===');
console.log(`File: ${filePath}`);
console.log(`File size: ${buf.length} bytes`);
console.log('');

// ── ISOBMFF box reader ────────────────────────────────────────────────────────
function readUint32BE(offset) {
  return buf.readUInt32BE(offset);
}
function readUint64BE(offset) {
  // Read as two 32-bit values (JS can't handle full 64-bit, but sizes < 4GB are fine)
  const hi = buf.readUInt32BE(offset);
  const lo = buf.readUInt32BE(offset + 4);
  return hi * 0x100000000 + lo;
}
function fourCC(offset) {
  return buf.slice(offset, offset + 4).toString('ascii');
}

// Parse top-level boxes
const boxes = [];
let offset = 0;
while (offset < buf.length - 8) {
  let size = readUint32BE(offset);
  const type = fourCC(offset + 4);
  let headerSize = 8;

  if (size === 1) {
    // Extended size
    size = readUint64BE(offset + 8);
    headerSize = 16;
  } else if (size === 0) {
    // Box extends to end of file
    size = buf.length - offset;
  }

  if (size < 8) break;

  boxes.push({ type, offset, size, dataOffset: offset + headerSize });
  offset += size;
}

console.log('=== TOP-LEVEL BOXES ===');
for (const box of boxes) {
  console.log(`  ${box.type.padEnd(8)} offset=${box.offset.toString().padStart(8)}  size=${box.size}`);
}
console.log('');

// ── Find moov box ─────────────────────────────────────────────────────────────
const moovBox = boxes.find(b => b.type === 'moov');
const mdatBox = boxes.find(b => b.type === 'mdat');

if (!moovBox) {
  console.log('ERROR: No moov box found. File may be corrupted or not faststart-converted.');
  process.exit(1);
}

console.log(`moov offset: ${moovBox.offset} (${moovBox.offset === 0 || boxes[0].type === 'ftyp' ? 'FASTSTART OK' : 'NOT FASTSTART - moov at end'})`);
const mdatBefore = mdatBox && mdatBox.offset < moovBox.offset;
console.log(`mdat before moov: ${mdatBefore ? 'NO (faststart)' : 'YES - moov is after ftyp'}`);
console.log('');

// ── Parse moov recursively to find key boxes ──────────────────────────────────
function parseBoxes(start, end, depth = 0) {
  const result = [];
  let p = start;
  while (p < end - 8) {
    let size = readUint32BE(p);
    if (p + 4 >= end) break;
    const type = fourCC(p + 4);
    let hSize = 8;
    if (size === 1) { size = readUint64BE(p + 8); hSize = 16; }
    if (size < 8 || size > buf.length) break;

    const box = { type, offset: p, size, dataOffset: p + hSize, depth };
    result.push(box);

    // Recurse into container boxes
    const containers = ['moov','trak','mdia','minf','stbl','edts','udta','meta','ilst'];
    if (containers.includes(type)) {
      box.children = parseBoxes(p + hSize, p + size, depth + 1);
    }

    p += size;
  }
  return result;
}

const moovTree = parseBoxes(moovBox.dataOffset, moovBox.offset + moovBox.size);

function findBox(tree, type) {
  for (const box of tree) {
    if (box.type === type) return box;
    if (box.children) {
      const found = findBox(box.children, type);
      if (found) return found;
    }
  }
  return null;
}

function findAllBoxes(tree, type) {
  const result = [];
  for (const box of tree) {
    if (box.type === type) result.push(box);
    if (box.children) result.push(...findAllBoxes(box.children, type));
  }
  return result;
}

// ── mvhd: movie header — total duration ──────────────────────────────────────
const mvhd = findBox(moovTree, 'mvhd');
if (mvhd) {
  const version = buf[mvhd.dataOffset];
  let timescale, duration;
  if (version === 1) {
    timescale = readUint32BE(mvhd.dataOffset + 20);
    const durHi = readUint32BE(mvhd.dataOffset + 24);
    const durLo = readUint32BE(mvhd.dataOffset + 28);
    duration = durHi * 0x100000000 + durLo;
  } else {
    timescale = readUint32BE(mvhd.dataOffset + 12);
    duration  = readUint32BE(mvhd.dataOffset + 16);
  }
  const totalDurationSec = duration / timescale;
  console.log(`=== MOVIE HEADER (mvhd) ===`);
  console.log(`  Movie timescale: ${timescale} ticks/sec`);
  console.log(`  Movie duration:  ${duration} ticks = ${totalDurationSec.toFixed(3)}s`);
  console.log('');
}

// ── Find audio track ─────────────────────────────────────────────────────────
const traks = findAllBoxes(moovTree, 'trak');
let audioTrak = null;
for (const trak of traks) {
  const hdlr = findBox(trak.children || [], 'hdlr');
  if (hdlr) {
    const handlerType = fourCC(hdlr.dataOffset + 8);
    if (handlerType === 'soun') { audioTrak = trak; break; }
  }
}

if (!audioTrak) {
  console.log('WARNING: No audio track found');
} else {
  console.log('=== AUDIO TRACK FOUND ===');

  // tkhd: track header
  const tkhd = findBox(audioTrak.children || [], 'tkhd');
  if (tkhd) {
    const version = buf[tkhd.dataOffset];
    let timescale_global, duration;
    // tkhd duration is in movie timescale
    if (version === 1) {
      duration = readUint32BE(tkhd.dataOffset + 24) * 0x100000000 + readUint32BE(tkhd.dataOffset + 28);
    } else {
      duration = readUint32BE(tkhd.dataOffset + 20);
    }
    console.log(`  Track duration: ${duration} (movie timescale units)`);
  }

  // mdhd: media header — audio-specific timescale
  const mdhd = findBox(audioTrak.children || [], 'mdhd');
  let audioTimescale = 44100;
  if (mdhd) {
    const version = buf[mdhd.dataOffset];
    if (version === 1) {
      audioTimescale = readUint32BE(mdhd.dataOffset + 20);
    } else {
      audioTimescale = readUint32BE(mdhd.dataOffset + 12);
    }
    const mediaDuration = version === 1
      ? readUint32BE(mdhd.dataOffset + 24) * 0x100000000 + readUint32BE(mdhd.dataOffset + 28)
      : readUint32BE(mdhd.dataOffset + 16);
    console.log(`  Audio timescale: ${audioTimescale} ticks/sec`);
    console.log(`  Audio duration:  ${mediaDuration} ticks = ${(mediaDuration/audioTimescale).toFixed(3)}s`);
  }

  // elst: edit list — CRITICAL for detecting initial silence / delay
  const edts = findBox(audioTrak.children || [], 'edts');
  if (edts) {
    const elst = findBox(edts.children || [], 'elst');
    if (elst) {
      const version = buf[elst.dataOffset];
      const flags   = (buf[elst.dataOffset+1] << 16) | (buf[elst.dataOffset+2] << 8) | buf[elst.dataOffset+3];
      const entryCount = readUint32BE(elst.dataOffset + 4);
      console.log('');
      console.log('=== EDIT LIST (elst) — TIMING CRITICAL ===');
      console.log(`  version=${version}, entry_count=${entryCount}`);

      let p = elst.dataOffset + 8;
      for (let i = 0; i < entryCount; i++) {
        let segmentDuration, mediaTime, mediaRate;
        if (version === 1) {
          const sdHi = readUint32BE(p); const sdLo = readUint32BE(p+4); p += 8;
          segmentDuration = sdHi * 0x100000000 + sdLo;
          const mtHi = readUint32BE(p); const mtLo = readUint32BE(p+4); p += 8;
          mediaTime = mtHi * 0x100000000 + mtLo;
        } else {
          segmentDuration = readUint32BE(p); p += 4;
          mediaTime = readUint32BE(p); p += 4;
          // mediaTime of -1 (0xFFFFFFFF) means "empty edit" (silence)
          if (mediaTime === 0xFFFFFFFF) mediaTime = -1;
        }
        mediaRate = readUint32BE(p); p += 4;

        // segmentDuration is in movie timescale, mediaTime in audio timescale
        const mvhdTimescale = mvhd ? (() => {
          const version = buf[mvhd.dataOffset];
          return version === 1 ? readUint32BE(mvhd.dataOffset + 20) : readUint32BE(mvhd.dataOffset + 12);
        })() : 1000;

        const segDurSec = segmentDuration / mvhdTimescale;
        const mediaTimeSec = mediaTime >= 0 ? mediaTime / audioTimescale : -1;

        console.log(`  Edit ${i}: segment_duration=${segmentDuration} (${segDurSec.toFixed(4)}s in movie ts)` +
                    `  media_time=${mediaTime}${mediaTime < 0 ? ' (EMPTY EDIT - silence)' : ` (${mediaTimeSec.toFixed(4)}s in audio ts)`}` +
                    `  rate=${mediaRate}`);

        if (mediaTime < 0) {
          console.log(`  *** EMPTY EDIT detected: ${segDurSec.toFixed(4)}s of silence at start of track ***`);
        } else if (mediaTime > 0) {
          console.log(`  *** POSITIVE media_time: audio starts at ${mediaTimeSec.toFixed(4)}s into media ***`);
          console.log(`  *** This means the audio file has ${mediaTimeSec.toFixed(4)}s of encoder delay to skip ***`);
        }
      }
    } else {
      console.log('  No elst box found in edts');
    }
  } else {
    console.log('  No edts/elst box — no edit list, audio starts at position 0');
  }

  // stts: sample-to-time table — check for leading silence via time-to-sample
  const stts = findBox(audioTrak.children || [], 'stts');
  if (stts) {
    const entryCount = readUint32BE(stts.dataOffset + 4);
    console.log('');
    console.log(`=== STTS (sample-to-time, ${entryCount} entries) ===`);
    let p2 = stts.dataOffset + 8;
    let totalSamples = 0;
    for (let i = 0; i < Math.min(entryCount, 5); i++) {
      const sampleCount    = readUint32BE(p2); p2 += 4;
      const sampleDuration = readUint32BE(p2); p2 += 4;
      const durationSec    = sampleDuration / audioTimescale;
      totalSamples += sampleCount;
      console.log(`  entry ${i}: count=${sampleCount}  duration_per_sample=${sampleDuration} (${(durationSec*1000).toFixed(2)}ms each)`);
    }
    if (entryCount > 5) console.log(`  ... (${entryCount - 5} more entries)`);
  }
}

// ── mdat position analysis ────────────────────────────────────────────────────
console.log('');
console.log('=== MDAT POSITION ===');
if (mdatBox) {
  console.log(`  mdat offset: ${mdatBox.offset}`);
  console.log(`  mdat size:   ${mdatBox.size} bytes`);
  console.log(`  mdat starts ${moovBox.offset < mdatBox.offset ? 'AFTER moov (faststart OK)' : 'BEFORE moov (not faststart)'}`);

  // Peek at first 64 bytes of mdat to check for near-zero values
  const dataStart = mdatBox.dataOffset;
  const peekEnd   = Math.min(dataStart + 64, buf.length);
  const peek      = buf.slice(dataStart, peekEnd);
  const maxVal    = Math.max(...peek);
  const avgVal    = peek.reduce((a, b) => a + b, 0) / peek.length;
  console.log(`  First 64 bytes of mdat: max=${maxVal}, avg=${avgVal.toFixed(1)}`);
  if (maxVal < 5) {
    console.log('  *** mdat starts with near-zero data — possible silence at beginning of audio ***');
  } else {
    console.log('  mdat starts with non-zero data — audio content begins immediately');
  }
} else {
  console.log('  No mdat box found (data may be fragmented)');
}

console.log('');
console.log('=== SUMMARY ===');
console.log('The elst (edit list) is the authoritative source for lead-in silence.');
console.log('  - Empty edit (media_time = -1): explicit silence inserted before audio');
console.log('  - media_time > 0: encoder delay in audio stream (AAC typical: 2112 samples)');
console.log('  - No elst: audio starts at sample 0 with no offset');
