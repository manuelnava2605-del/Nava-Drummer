#!/usr/bin/env node
// Moves moov atom before mdat (faststart / web-optimized MP4)
// Usage: node mp4faststart.js input.m4a output.m4a
const fs = require('fs');

const input  = process.argv[2];
const output = process.argv[3];

if (!input || !output) {
  console.error('Usage: node mp4faststart.js <input> <output>');
  process.exit(1);
}

const buf = fs.readFileSync(input);
const len = buf.length;

// Parse top-level boxes
const boxes = [];
let pos = 0;
while (pos < len) {
  if (pos + 8 > len) break;
  let size = buf.readUInt32BE(pos);
  const type = buf.slice(pos + 4, pos + 8).toString('ascii');
  if (size === 1) {
    // Extended 64-bit size
    size = Number(buf.readBigUInt64BE(pos + 8));
  } else if (size === 0) {
    size = len - pos;
  }
  boxes.push({ type, start: pos, size });
  pos += size;
}

console.log('Boxes found:', boxes.map(b => `${b.type}@${b.start}(${b.size})`).join(', '));

const moovBox = boxes.find(b => b.type === 'moov');
const mdatBox = boxes.find(b => b.type === 'mdat');

if (!moovBox) { console.error('No moov box found!'); process.exit(1); }
if (!mdatBox) { console.error('No mdat box found!'); process.exit(1); }

if (moovBox.start < mdatBox.start) {
  console.log('moov is already before mdat — copying as-is');
  fs.copyFileSync(input, output);
  process.exit(0);
}

// Compute offset adjustment: moov will move to just after pre-mdat boxes
// (everything before mdat that isn't moov)
const beforeMdat = boxes.filter(b => b.start < mdatBox.start && b.type !== 'moov');
const newMoovOffset = beforeMdat.reduce((sum, b) => sum + b.size, 0);
const oldMoovOffset = moovBox.start;

// Chunk offsets in stco/co64 are absolute file positions pointing into mdat data.
// mdat will shift right by moovSize bytes (moov inserted before it).
const chunkDelta = moovBox.size; // mdat moves forward by moovSize

console.log(`moov: ${oldMoovOffset} → ${newMoovOffset}  chunk offset delta: +${chunkDelta}`);

// Patch moov: update stco/co64 chunk offsets
const moovData = Buffer.from(buf.slice(moovBox.start, moovBox.start + moovBox.size));
patchChunkOffsets(moovData, chunkDelta);

// Build output: pre-mdat boxes + patched moov + mdat + remaining boxes
const parts = [];
for (const b of beforeMdat) {
  parts.push(buf.slice(b.start, b.start + b.size));
}
parts.push(moovData);
parts.push(buf.slice(mdatBox.start, mdatBox.start + mdatBox.size));
// Any boxes after mdat that aren't moov
for (const b of boxes.filter(b => b.start > mdatBox.start && b.type !== 'moov')) {
  parts.push(buf.slice(b.start, b.start + b.size));
}

fs.writeFileSync(output, Buffer.concat(parts));
console.log(`Written ${output} (${Buffer.concat(parts).length} bytes)`);

function patchChunkOffsets(buf, delta) {
  // Walk box tree inside moov looking for stco/co64
  walkBoxes(buf, 0, buf.length, delta);
}

function walkBoxes(buf, start, end, delta) {
  let pos = start;
  while (pos + 8 <= end) {
    let size = buf.readUInt32BE(pos);
    const type = buf.slice(pos + 4, pos + 8).toString('ascii');
    if (size === 0) size = end - pos;
    if (size < 8) break;

    if (type === 'stco') {
      // 32-bit chunk offset table
      const version = buf[pos + 8];
      const count = buf.readUInt32BE(pos + 12);
      let off = pos + 16;
      for (let i = 0; i < count; i++) {
        const old = buf.readUInt32BE(off);
        buf.writeUInt32BE(old + delta, off);
        off += 4;
      }
      console.log(`  Patched stco: ${count} entries`);
    } else if (type === 'co64') {
      const count = buf.readUInt32BE(pos + 12);
      let off = pos + 16;
      for (let i = 0; i < count; i++) {
        const old = Number(buf.readBigInt64BE(off));
        buf.writeBigInt64BE(BigInt(old + delta), off);
        off += 8;
      }
      console.log(`  Patched co64: ${count} entries`);
    } else if (['moov','trak','mdia','minf','stbl','udta','meta','ilst','dinf'].includes(type)) {
      // Container box — recurse
      const innerStart = type === 'meta' ? pos + 12 : pos + 8;
      walkBoxes(buf, innerStart, pos + size, delta);
    }
    pos += size;
  }
}
