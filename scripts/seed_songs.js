// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Firestore Song Catalog Seeder
//
// Populates the Firestore "Songs" collection with production songs.
// Each song document corresponds to a package folder in Firebase Storage.
//
// Usage:
//   1. Install: npm install firebase-admin
//   2. Download your service account key from Firebase Console:
//      Project Settings → Service Accounts → Generate new private key
//   3. Set env var: export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
//   4. Run: node scripts/seed_songs.js
//
// After seeding:
//   • Upload song packages to Firebase Storage under Songs/<folder>/
//     (see remoterepository for expected file list: notes.mid, song.ogg, etc.)
//   • The Flutter app will fetch this catalog automatically on next launch.
// ─────────────────────────────────────────────────────────────────────────────

const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  // storageBucket: 'your-project-id.appspot.com',  // optional
});

const db = admin.firestore();

// ── Song Documents ────────────────────────────────────────────────────────────

const songs = [

  // ── PRODUCTION SONGS (backed by Firebase Storage packages) ─────────────────

  {
    id: 'te_quiero_hombres_g',
    title: 'Te Quiero',
    artist: 'Hombres G',
    genre: 'pop',
    difficulty: 'intermediate',
    bpm: 75,
    durationSeconds: 228,
    storageFolderPath: 'Songs/te_quiero_hombres_g',
    isPremium: false,
    isUnlocked: true,
    xpReward: 300,
    requiredLevel: 3,
    techniqueTag: '12/8 groove',
    description:
      'Clásico de Hombres G en compás de 12/8. ' +
      'Grooves de hi-hat y ride con sensación swing. ' +
      'Perfecto para trabajar el pulso ternario a 75 BPM.',
    order: 1,
    version: 1,
  },

  // Add more production songs here as you upload their packages to Storage.
  // Example:
  //
  // {
  //   id: 'coda_aun',
  //   title: 'Aún',
  //   artist: 'Coda',
  //   genre: 'cristiana',
  //   difficulty: 'beginner',
  //   bpm: 72,
  //   durationSeconds: 240,
  //   storageFolderPath: 'Songs/Coda - Aún',
  //   isPremium: false,
  //   isUnlocked: true,
  //   xpReward: 150,
  //   requiredLevel: 1,
  //   techniqueTag: 'Worship groove',
  //   description: 'Balada cristiana contemporánea.',
  //   order: 2,
  //   version: 1,
  // },
];

// ── Seed ──────────────────────────────────────────────────────────────────────

async function seed() {
  console.log(`Seeding ${songs.length} song(s) to Firestore...`);
  const batch = db.batch();

  for (const song of songs) {
    const { id, ...data } = song;
    const ref = db.collection('Songs').doc(id);
    batch.set(ref, {
      ...data,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`  + ${id} (${data.title} — ${data.artist})`);
  }

  await batch.commit();
  console.log('Done. Songs collection updated.');
  process.exit(0);
}

seed().catch(err => {
  console.error('Seeding failed:', err);
  process.exit(1);
});
