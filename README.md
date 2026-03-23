# 🥁 NavaDrummer

App móvil de aprendizaje de batería con MIDI nativo, visualización de notas cayendo (estilo videojuego), y catálogo de canciones reales en formato Clone Hero / RBN.

---

## 🚀 Setup en 5 pasos

### 1. Requisitos previos
```bash
flutter --version  # >= 3.16
dart --version     # >= 3.0
```

### 2. Dependencias
```bash
flutter pub get
```

### 3. Firebase (OBLIGATORIO)
1. Crear proyecto en [console.firebase.google.com](https://console.firebase.google.com)
2. Habilitar: **Authentication** (Email/Password + Anonymous), **Firestore**, **Storage**
3. Descargar y colocar:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`
4. Desplegar reglas:
```bash
firebase deploy --only firestore:rules,storage
```

### 4. Fuentes
Deben estar en `assets/fonts/`:
- **Orbitron**: `Orbitron-Regular.ttf`, `Orbitron-Bold.ttf`
- **JetBrains Mono**: `JetBrainsMono-Regular.ttf`, `JetBrainsMono-Bold.ttf`

### 5. Correr
```bash
flutter run
```

---

## 📁 Estructura del proyecto

```
nava_drummer/
├── assets/
│   ├── midi/                       # MIDI de lecciones de práctica
│   ├── sounds/                     # Samples de batería
│   ├── backing_tracks/             # Pistas de acompañamiento
│   ├── fonts/                      # Orbitron + JetBrains Mono
│   └── songs/                      # Canciones reales (paquetes Clone Hero/RBN)
│       ├── songs_manifest.json     # Lista de paquetes a cargar
│       ├── Coda - Aún/             # song.ini + notes.mid + stems OGG
│       └── Moenia - No Dices Más/  # song.ini + notes.mid + stems OGG
├── lib/
│   ├── core/
│   │   ├── global_timing_controller.dart  # Reloj global + MathTimingEngine + calibración
│   │   ├── practice_engine.dart           # Motor de juego 60 FPS
│   │   └── audio_service.dart             # Reproductor de audio
│   ├── data/
│   │   ├── datasources/local/
│   │   │   ├── midi_engine.dart           # Platform channel MIDI
│   │   │   ├── midi_file_parser.dart      # Parser SMF binario
│   │   │   └── song_package_loader.dart   # Carga paquetes Clone Hero/RBN
│   │   └── song_loader.dart               # Loader dinámico vía manifest JSON
│   ├── domain/
│   │   ├── entities/entities.dart         # Todas las entidades del dominio
│   │   └── usecases/
│   │       ├── song_catalog.dart          # Lecciones de práctica (NavaSongCatalog)
│   │       └── real_song_catalog.dart     # Catálogo estático de canciones reales
│   ├── presentation/
│   │   ├── screens/
│   │   │   ├── onboarding_screen.dart     # Intro de 2 slides
│   │   │   ├── song_library_screen.dart   # Biblioteca con filtros + búsqueda
│   │   │   ├── song_detail_screen.dart    # Detalle: elegir JUEGO o PARTITURA
│   │   │   ├── practice_screen.dart       # Pantalla de práctica (notas cayendo)
│   │   │   ├── calibration_screen.dart    # Ajuste de latencia (-100 a +100 ms)
│   │   │   └── dashboard_screen.dart      # Progreso y estadísticas
│   │   ├── widgets/
│   │   │   ├── falling_notes_view.dart    # Visualizador 60 FPS
│   │   │   └── practice_hud.dart          # HUD de práctica
│   │   └── theme/nava_theme.dart          # Diseño neon oscuro premium
│   ├── injection.dart                     # Inyección de dependencias
│   └── main.dart                          # Entry point
```

---

## 🎵 Catálogo de canciones

### Canciones reales (paquetes Clone Hero / RBN)

| Canción | Artista | Dificultad | BPM | Carta |
|---------|---------|-----------|-----|-------|
| Aún | Coda | Principiante | 120 | Henry13Hdz |
| No Dices Más | Moenia | Avanzado | 120 | Henry13Hdz / SkyDown |

### Lecciones de práctica (NavaSongCatalog)

16 lecciones progresivas: Quarter Notes → Blast Beat — de principiante a experto.

---

## 🎯 Agregar canciones

1. Coloca la carpeta del paquete en `assets/songs/NombreArtista - NombreCancion/`
2. Asegúrate de que contenga:
   - `song.ini` — metadatos (name, artist, bpm, diff_drums, genre, pro_drums)
   - `notes.mid` — MIDI de la batería
   - `drums.ogg` / otros stems
3. Agrega la carpeta en `pubspec.yaml` bajo `assets:`:
   ```yaml
   - assets/songs/NombreArtista - NombreCancion/
   ```
4. Agrega la ruta en `assets/songs/songs_manifest.json`:
   ```json
   {
     "songs": [
       "assets/songs/Coda - Aún",
       "assets/songs/Moenia - No Dices Más",
       "assets/songs/NombreArtista - NombreCancion"
     ]
   }
   ```
5. `flutter run` — la canción aparece automáticamente en la biblioteca.

---

## ⚡ Arquitectura técnica

- **Latencia MIDI**: < 5ms (Dart) + < 15ms (nativo) = < 20ms total
- **Calibración de usuario**: slider -100 a +100 ms (`GlobalTimingController.userOffsetMicros`)
- **Ventanas de timing**: PERFECT ±30ms · GOOD ±80ms · OKAY ±140ms
- **Frame rate**: 60 FPS garantizados (CustomPainter, sin rebuilds por frame)
- **Timestamps**: microsegundos precisos (CoreMIDI / SystemClock.elapsedRealtimeNanos)
- **Arquitectura**: Clean Architecture — Presentation → Domain → Data
- **Carga de canciones**: manifest JSON → `SongLoader` → merge con NavaSongCatalog

---

## 🎮 Flujo de la app

```
Onboarding (2 slides, solo primera vez)
  ↓
DeviceSetup (solo primera vez)
  ↓
SongLibraryScreen
  ↓ tap canción
SongDetailScreen
  ↓ tap JUEGO o PARTITURA
PracticeScreen (landscape)
  ↓ terminar
[Paywall si aplica]
```

---

## ✅ Tests

```bash
flutter test test/unit/
flutter test test/integration/
flutter test test/benchmarks/
```
