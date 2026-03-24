#!/usr/bin/env node
// =============================================================================
// NavaDrummer — Bulk MIDI Upload  (Midisaya catalog)
// =============================================================================
//
// Sube todos los MIDIs del catálogo Midisaya a Firebase Storage + Firestore.
//
// Prerrequisitos:
//   1. Extrae el ZIP en:  C:\Temp\midisaya_extract\
//      (debe quedar:  C:\Temp\midisaya_extract\Midisaya\MIDIS\1.mid …)
//   2. Coloca la service account key en:  scripts\service-account.json
//      (Firebase Console → Project Settings → Service Accounts → Generate key)
//   3. npm install
//   4. node bulk_upload_midisaya.js
//
// Flags opcionales:
//   --dry-run     Parsea todo pero NO sube nada (ideal para probar)
//   --force       Re-sube canciones que ya existen en Storage
//   --limit=N     Solo procesa las primeras N entradas del Excel (para test)
//   --start=N     Empieza desde la fila N del Excel (para reanudar)
// =============================================================================

'use strict';

const admin      = require('firebase-admin');
const xlsx       = require('xlsx');
const fs         = require('fs');
const path       = require('path');
const { Midi }   = require('@tonejs/midi');

// ── Configuración ─────────────────────────────────────────────────────────────

const CONFIG = {
  serviceAccountPath : path.join(__dirname, 'service-account.json'),
  storageBucket      : 'nava-drummer.firebasestorage.app',
  firestoreCollection: 'Songs',

  // Directorio donde están los MIDI extraídos del ZIP
  midiSourceDir : 'C:\\Temp\\midisaya_extract\\Midisaya\\MIDIS',

  // Ruta al Excel dentro del ZIP extraído
  excelPath     : 'C:\\Temp\\midisaya_extract\\Midisaya\\midisaya (1).xlsx',

  // Cuántas canciones subir en paralelo (no subir demasiado para evitar errores)
  concurrency   : 4,

  // Escrituras de Firestore por batch (máximo 500)
  batchSize     : 400,
};

// ── Argumentos de línea de comandos ───────────────────────────────────────────

const args    = process.argv.slice(2);
const DRY_RUN = args.includes('--dry-run');
const FORCE   = args.includes('--force');
const LIMIT   = (() => { const a = args.find(a => a.startsWith('--limit=')); return a ? parseInt(a.split('=')[1]) : Infinity; })();
const START   = (() => { const a = args.find(a => a.startsWith('--start=')); return a ? parseInt(a.split('=')[1]) : 0; })();

// ── Firebase init ─────────────────────────────────────────────────────────────

let db, bucket;

function initFirebase() {
  if (!fs.existsSync(CONFIG.serviceAccountPath)) {
    console.error(`\n❌ No se encontró la service account key en:\n   ${CONFIG.serviceAccountPath}`);
    console.error('   Descárgala desde Firebase Console → Project Settings → Service Accounts\n');
    process.exit(1);
  }
  const serviceAccount = require(CONFIG.serviceAccountPath);
  admin.initializeApp({
    credential    : admin.credential.cert(serviceAccount),
    storageBucket : CONFIG.storageBucket,
  });
  db     = admin.firestore();
  bucket = admin.storage().bucket();
}

// ═════════════════════════════════════════════════════════════════════════════
// MIDI PARSER  (usa @tonejs/midi — librería probada y robusta)
// =============================================================================

/**
 * Parsea un archivo MIDI y devuelve { bpm, durationMs, numTracks }.
 * Devuelve null si el archivo no es MIDI válido o está corrupto.
 */
function parseMidi(buffer) {
  try {
    // Rechaza formato RIFF-MIDI (.rmi) que @tonejs/midi no soporta
    if (buffer.length < 4) return null;
    if (buffer.toString('ascii', 0, 4) === 'RIFF') return null;

    const midi       = new Midi(buffer);
    const firstTempo = midi.header.tempos[0];
    const bpm        = firstTempo ? Math.round(firstTempo.bpm) : 120;
    const durationMs = Math.round(midi.duration * 1000);
    const numTracks  = midi.tracks.length;

    return { bpm, durationMs, numTracks };
  } catch {
    return null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HELPERS
// =============================================================================

/**
 * Busca el archivo MIDI preferiendo la variante M (multi-track).
 * Prueba: NM.mid → NM.MID → N.mid → N.MID
 */
function findMidiFile(midiNumber) {
  const dir      = CONFIG.midiSourceDir;
  const variants = [
    `${midiNumber}M.mid`, `${midiNumber}M.MID`, `${midiNumber}m.mid`,
    `${midiNumber}.mid`,  `${midiNumber}.MID`,  `${midiNumber}.midi`,
  ];
  for (const v of variants) {
    const full = path.join(dir, v);
    if (fs.existsSync(full)) return full;
  }
  return null;
}

/**
 * Convierte título + artista a un nombre de carpeta de Storage limpio.
 * Elimina caracteres problemáticos y limita la longitud.
 */
function makeFolderName(artist, title) {
  const UNKNOWN = ['compositor desconocido', 'no conocido', 'unknown',
                   'desconocido', 'n/a', ''];

  const clean = (s) => (s || '')
    .replace(/[\/\\]/g, '-')   // slash → guión
    .replace(/\s+/g, ' ')      // espacios múltiples
    .trim();

  const a = clean(artist);
  const t = clean(title);

  const base = UNKNOWN.includes(a.toLowerCase()) ? t : `${a} - ${t}`;
  return base.substring(0, 220); // Storage permite hasta ~1024 bytes en path
}

/**
 * Estilo del Excel → diff_drums (0–7).
 * Influye en la dificultad y el xpReward en Firestore.
 */
function styleToDiff(style, bpm) {
  const s = (style || '').toLowerCase();
  if (s.includes('balada') || s.includes('gospel') || bpm < 65) return 2;
  if (s.includes('bossa')  || s.includes('country'))            return 3;
  if (s.includes('pop')    || s.includes('ethnic'))             return 3;
  if (s.includes('cumbia') || s.includes('salsa')  ||
      s.includes('merengue')|| s.includes('vallenato'))         return 4;
  if (s.includes('rock')   || s.includes('fusion') || bpm > 130) return 5;
  return 3; // intermedio por defecto
}

/** diff_drums → etiqueta de dificultad */
function diffLabel(diff) {
  if (diff <= 1) return 'beginner';
  if (diff <= 3) return 'intermediate';
  if (diff <= 5) return 'advanced';
  return 'expert';
}

/** Calcula xpReward igual que el Cloud Function */
function calcXpReward(diff, isPro = false) {
  const base = 100 + Math.max(0, Math.min(diff, 6)) * 25;
  return isPro ? Math.round(base * 1.5) : base;
}

/**
 * Genera el contenido de song.ini para un song (referencia futura).
 */
function makeSongIni(title, artist, bpm, durationMs, style, diff) {
  return [
    '[Song]',
    `name = ${title}`,
    `artist = ${artist}`,
    'genre = cristiana',
    `diff_drums = ${diff}`,
    `bpm = ${bpm}`,
    `song_length = ${durationMs}`,
    `loading_phrase = ${style}`,
    'charter = NavaDrummer',
    '',
  ].join('\n');
}

// ═════════════════════════════════════════════════════════════════════════════
// LECTURA DEL EXCEL
// =============================================================================

function readExcel() {
  if (!fs.existsSync(CONFIG.excelPath)) {
    console.error(`\n❌ Excel no encontrado en:\n   ${CONFIG.excelPath}`);
    console.error('   Verifica que el ZIP esté extraído en C:\\Temp\\midisaya_extract\\\n');
    process.exit(1);
  }

  const wb    = xlsx.readFile(CONFIG.excelPath);
  const sheet = wb.Sheets[wb.SheetNames[0]];
  const rows  = xlsx.utils.sheet_to_json(sheet, { defval: '' });

  // Normalizar nombres de columna (el Excel puede tener variantes)
  const catalog = [];
  for (const row of rows) {
    const keys   = Object.keys(row);
    const getCol = (...candidates) => {
      for (const c of candidates) {
        const found = keys.find(k => k.toUpperCase().includes(c.toUpperCase()));
        if (found) return String(row[found] || '').trim();
      }
      return '';
    };

    const midiNum = parseInt(getCol('MIDI', 'NUM', 'ID'));
    if (!midiNum || isNaN(midiNum)) continue;

    catalog.push({
      midiNumber : midiNum,
      title      : getCol('TITLE', 'TITULO', 'NOMBRE'),
      artist     : getCol('AUTHOR', 'ARTIST', 'AUTOR', 'ARTISTA'),
      sequencer  : getCol('SEQUENCER', 'SECUENCI'),
      style      : getCol('STYLE', 'ESTILO', 'GENERO'),
    });
  }

  return catalog;
}

// ═════════════════════════════════════════════════════════════════════════════
// CARGA DE UN SONG
// =============================================================================

async function uploadSong(entry, stats) {
  const { midiNumber, title, artist, style } = entry;

  // 1. Buscar archivo MIDI
  const midiPath = findMidiFile(midiNumber);
  if (!midiPath) {
    stats.missingMidi.push(midiNumber);
    return;
  }

  // 2. Parsear MIDI
  const midiBuffer = fs.readFileSync(midiPath);
  const midiInfo   = parseMidi(midiBuffer);
  if (!midiInfo) {
    stats.parseErrors.push({ midiNumber, path: midiPath });
    return;
  }

  const { bpm, durationMs, numTracks } = midiInfo;

  // Filtrar solo casos claramente corruptos (>35 min o <8 s)
  if (durationMs > 35 * 60 * 1000 || durationMs < 8_000) {
    stats.skippedDuration.push({ midiNumber, title, durationMs });
    return;
  }

  // 3. Calcular metadata
  const diff       = styleToDiff(style, bpm);
  const folderName = makeFolderName(artist, title);
  const storagePath = `Songs/${folderName}`;
  const docId       = folderName;

  // 4. En dry-run solo mostrar sin subir
  if (DRY_RUN) {
    console.log(`  [DRY] ${midiNumber.toString().padStart(4)} │ ${bpm.toString().padStart(3)} BPM │ ${msToMmSs(durationMs)} │ ${folderName.substring(0, 60)}`);
    stats.uploaded++;
    return;
  }

  // 5. Verificar si ya existe (skip si no --force)
  if (!FORCE) {
    const [exists] = await bucket.file(`${storagePath}/notes.mid`).exists();
    if (exists) {
      stats.skippedExisting++;
      return;
    }
  }

  // 6. Subir notes.mid
  await bucket.upload(midiPath, {
    destination : `${storagePath}/notes.mid`,
    metadata    : { contentType: 'audio/midi', cacheControl: 'public, max-age=31536000' },
  });

  // 7. Subir song.ini (para referencia y compatibilidad con Cloud Function)
  const iniContent = makeSongIni(title, artist, bpm, durationMs, style, diff);
  await bucket.file(`${storagePath}/song.ini`).save(iniContent, {
    contentType : 'text/plain',
  });

  // 8. Crear/actualizar documento en Firestore (acumulado para batch)
  stats.firestoreDocs.push({
    docId,
    data: {
      title,
      artist,
      difficulty       : diffLabel(diff),
      genre            : 'cristiana',
      bpm,
      durationSeconds  : Math.round(durationMs / 1000),
      storageFolderPath: storagePath,
      midiStoragePath  : '',
      isPremium        : false,
      xpReward         : calcXpReward(diff),
      requiredLevel    : 1,
      order            : midiNumber,
      version          : 1,
      techniqueTag     : style || undefined,
      description      : entry.sequencer ? `Secuenciado por ${entry.sequencer}` : undefined,
    },
  });

  stats.uploaded++;
  process.stdout.write(`\r  ✓ ${stats.uploaded} subidas | ${stats.skippedExisting} ya existían | ${stats.parseErrors.length + stats.missingMidi.length} errores   `);
}

// ═════════════════════════════════════════════════════════════════════════════
// ESCRITURA EN LOTE DE FIRESTORE
// =============================================================================

async function flushFirestoreBatch(docs) {
  if (docs.length === 0) return;

  // Fragmentar en batches de CONFIG.batchSize
  for (let i = 0; i < docs.length; i += CONFIG.batchSize) {
    const chunk  = docs.slice(i, i + CONFIG.batchSize);
    const batch  = db.batch();
    for (const { docId, data } of chunk) {
      // Limpiar campos undefined antes de escribir
      const cleanData = Object.fromEntries(
        Object.entries(data).filter(([, v]) => v !== undefined)
      );
      batch.set(db.collection(CONFIG.firestoreCollection).doc(docId), cleanData, { merge: false });
    }
    await batch.commit();
    process.stdout.write(`\r  ✓ Firestore: ${Math.min(i + CONFIG.batchSize, docs.length)}/${docs.length} documentos escritos   `);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HELPERS VARIOS
// =============================================================================

function msToMmSs(ms) {
  const s   = Math.round(ms / 1000);
  const min = Math.floor(s / 60);
  const sec = s % 60;
  return `${min.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`;
}

/** Ejecuta tareas con concurrencia limitada */
async function pool(tasks, concurrency) {
  const results = [];
  let i = 0;

  async function worker() {
    while (i < tasks.length) {
      const task = tasks[i++];
      results.push(await task());
    }
  }

  const workers = Array.from({ length: Math.min(concurrency, tasks.length) }, worker);
  await Promise.all(workers);
  return results;
}

// ═════════════════════════════════════════════════════════════════════════════
// MAIN
// =============================================================================

async function main() {
  console.log('\n╔══════════════════════════════════════════════════════════╗');
  console.log('║   NavaDrummer — Bulk Upload Midisaya                     ║');
  console.log('╚══════════════════════════════════════════════════════════╝\n');

  if (DRY_RUN) console.log('  ⚡ MODO DRY-RUN — no se sube nada\n');
  if (FORCE)   console.log('  ⚡ MODO FORCE — re-sube aunque ya exista\n');

  // Init Firebase (solo en modo real)
  if (!DRY_RUN) initFirebase();

  // Leer Excel
  console.log('  📄 Leyendo Excel…');
  const catalog = readExcel();
  console.log(`     ${catalog.length} entradas encontradas\n`);

  // Aplicar --start y --limit
  const entries = catalog.slice(START, START + LIMIT);
  console.log(`  🎵 Procesando ${entries.length} canciones (filas ${START + 1}–${START + entries.length})…\n`);

  const stats = {
    uploaded        : 0,
    skippedExisting : 0,
    missingMidi     : [],
    parseErrors     : [],
    skippedDuration : [],
    firestoreDocs   : [],
  };

  // Procesar con pool de concurrencia
  const tasks = entries.map(entry => () => uploadSong(entry, stats));
  await pool(tasks, DRY_RUN ? 8 : CONFIG.concurrency);

  // Escribir documentos Firestore en batch
  if (!DRY_RUN && stats.firestoreDocs.length > 0) {
    console.log(`\n\n  📦 Escribiendo ${stats.firestoreDocs.length} documentos en Firestore…`);
    await flushFirestoreBatch(stats.firestoreDocs);
  }

  // ── Reporte final ──────────────────────────────────────────────────────────
  console.log('\n\n╔══════════════════════════════════════════════════════════╗');
  console.log('║   REPORTE FINAL                                          ║');
  console.log('╠══════════════════════════════════════════════════════════╣');
  console.log(`║  ✅ Subidas / procesadas   ${stats.uploaded.toString().padStart(5)}                       ║`);
  console.log(`║  ⏭️  Ya existían (skip)     ${stats.skippedExisting.toString().padStart(5)}                       ║`);
  console.log(`║  ❌ MIDI no encontrado     ${stats.missingMidi.length.toString().padStart(5)}                       ║`);
  console.log(`║  ⚠️  Error de parseo       ${stats.parseErrors.length.toString().padStart(5)}                       ║`);
  console.log(`║  🕐 Duración anómala       ${stats.skippedDuration.length.toString().padStart(5)}                       ║`);
  console.log('╚══════════════════════════════════════════════════════════╝\n');

  // Guardar reporte detallado
  const reportPath = path.join(__dirname, `upload-report-${Date.now()}.json`);
  const report = {
    timestamp       : new Date().toISOString(),
    uploaded        : stats.uploaded,
    skippedExisting : stats.skippedExisting,
    missingMidi     : stats.missingMidi,
    parseErrors     : stats.parseErrors.map(e => ({ midi: e.midiNumber, file: path.basename(e.path) })),
    skippedDuration : stats.skippedDuration.map(e => ({ midi: e.midiNumber, title: e.title, duration: msToMmSs(e.durationMs) })),
  };

  if (!DRY_RUN) {
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
    console.log(`  📋 Reporte guardado en: ${path.basename(reportPath)}\n`);
  }
}

main().catch(err => {
  console.error('\n❌ Error fatal:', err.message);
  if (err.stack) console.error(err.stack);
  process.exit(1);
});
