# 🥁 NavaDrummer

App móvil de aprendizaje de batería con MIDI nativo, visualización de notas cayendo (estilo InstaDrum), y catálogo de canciones reales.

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
Descargar y colocar en `assets/fonts/`:
- [Orbitron](https://fonts.google.com/specimen/Orbitron): `Orbitron-Regular.ttf`, `Orbitron-Bold.ttf`
- [JetBrains Mono](https://www.jetbrains.com/legalnotices/): `JetBrainsMono-Regular.ttf`, `JetBrainsMono-Bold.ttf`

### 5. Correr
```bash
flutter run
```

---

## 🖥️ Panel Admin
Abrir `admin_panel/index.html` en el navegador (o deployar en Firebase Hosting).
Actualizar las credenciales de Firebase en el `<script>` al final del archivo.

Solo el owner puede acceder — crear el usuario admin en Firebase Console → Authentication → Add user.

---

## 📁 Estructura del proyecto

```
nava_drummer/
├── android/                    # Plugin nativo Android (MIDI API + BLE)
├── ios/                        # Plugin nativo iOS (CoreMIDI + CoreBluetooth)
├── assets/midi/                # 39 archivos MIDI (16 lecciones + 23 canciones reales)
├── admin_panel/index.html      # Panel web del dueño para gestionar el catálogo
├── firebase/                   # Reglas de seguridad Firestore + Storage
├── lib/
│   ├── core/
│   │   ├── practice_engine.dart    # Motor de juego 60 FPS
│   │   └── firebase_init.dart      # Inicialización Firebase + Crashlytics
│   ├── data/
│   │   ├── datasources/local/
│   │   │   ├── midi_engine.dart        # Platform channel MIDI
│   │   │   ├── midi_file_parser.dart   # Parser SMF binario
│   │   │   └── audio_hit_detector.dart # Fallback micrófono
│   │   ├── models/firestore_models.dart
│   │   └── repositories/firebase_repositories.dart
│   ├── domain/
│   │   ├── entities/entities.dart   # Todas las entidades del dominio
│   │   ├── repositories/            # Interfaces abstractas
│   │   └── usecases/
│   │       ├── usecases.dart           # Casos de uso + AI coach + lecciones
│   │       ├── song_catalog.dart       # 16 canciones de práctica
│   │       └── real_song_catalog.dart  # 23 canciones reales
│   ├── presentation/
│   │   ├── bloc/blocs.dart          # AuthBloc, ProgressBloc, SongsBloc
│   │   ├── screens/                 # 4 pantallas principales
│   │   ├── widgets/falling_notes_view.dart  # Visualizador 60 FPS
│   │   └── theme/nava_theme.dart    # Diseño neon oscuro
│   ├── injection.dart               # Inyección de dependencias
│   └── main.dart                    # Entry point
└── test/                        # Unit + Integration + Benchmarks
```

---

## 🎵 Catálogo de canciones (39 total)

### ✝️ Música Cristiana (8)
| Canción | Artista | BPM |
|---------|---------|-----|
| Oceans (Where Feet May Fail) | Hillsong UNITED | 58 |
| Shout to the Lord | Darlene Zschech | 72 |
| Cristo Te Necesito | CCM Latino | 68 |
| Renuévame | Marcos Witt | 75 |
| Open the Eyes of My Heart | Paul Baloche | 96 |
| God of Wonders | Steve Hindalong | 104 |
| How Great Is Our God | Chris Tomlin | 76 |
| Agnus Dei | Michael W. Smith | 66 |

### 🎸 Rock Clásico (5) • 🎵 Pop Moderno (4) • 🔥 Metal (3) • 🎷 Funk/Soul (3)
AC/DC, Nirvana, Beatles, Led Zeppelin, Bruno Mars, MJ, Ed Sheeran, Metallica, Megadeth, Stevie Wonder, James Brown, Earth Wind & Fire

### 📚 Lecciones de práctica (16)
Quarter Notes → Blast Beat — de principiante a experto

---

## ⚡ Arquitectura técnica

- **Latencia MIDI**: < 5ms (Dart) + < 15ms (nativo) = < 20ms total
- **Frame rate**: 60 FPS garantizados (CustomPainter, no rebuilds por frame)
- **Timestamps**: microsegundos precisos (CoreMIDI / SystemClock.elapsedRealtimeNanos)
- **Arquitectura**: Clean Architecture — Presentation (BLoC) → Domain → Data
- **Threading**: MIDI en THREAD_PRIORITY_AUDIO (Android) / .userInteractive (iOS)

---

## ✅ Tests

```bash
flutter test test/unit/
flutter test test/integration/
flutter test test/benchmarks/
```
