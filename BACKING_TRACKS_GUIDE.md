# NavaDrummer — Guía de Backing Tracks con Moises Pro

## Flujo de trabajo

```
Moises Pro → Exportar sin batería → Renombrar → assets/backing_tracks/ → python3 register_backing_tracks.py → flutter run
```

## Lista completa de canciones y sus IDs

### ✝️ Cristiana (prioridad)
| Canción | Artista | ID del archivo |
|---------|---------|----------------|
| Quiero Conocer a Jesús | Generación 12 | `quiero_conocer_jesus.mp3` |
| Abre Mis Ojos | CCM Clásico | `abre_mis_ojos.mp3` |
| Eres Todopoderoso | Himno CCM | `eres_todopoderoso.mp3` |
| Te Alabaré Mi Buen Jesús | Himno Evangélico | `te_alabare.mp3` |
| El Señor Es Mi Pastor | Adoración Clásica | `el_senor_es_mi_pastor.mp3` |
| Bueno Es Alabar | Danilo Montero | `bueno_es_alabar.mp3` |
| Grande y Fuerte | Marcos Witt | `grande_y_fuerte.mp3` |
| Tu Fidelidad | Christine D'Clario | `tu_fidelidad.mp3` |
| Dios Incomparable | Generación 12 | `dios_incomparable.mp3` |
| Levántate Señor | Himno de Guerra | `levantate_senor.mp3` |
| Oceans | Hillsong UNITED | `oceans_hillsong.mp3` |
| Shout to the Lord | Hillsong | `shout_to_the_lord.mp3` |
| Cristo Te Necesito | CCM Latino | `cristo_te_necesito.mp3` |
| Renuévame | Marcos Witt | `renuevame.mp3` |
| Open the Eyes of My Heart | Paul Baloche | `open_the_eyes.mp3` |
| God of Wonders | Steve Hindalong | `god_of_wonders.mp3` |
| How Great Is Our God | Chris Tomlin | `how_great_is_our_god.mp3` |
| Agnus Dei | Michael W. Smith | `agnus_dei.mp3` |

### 🎸 Rock
| Canción | Artista | ID del archivo |
|---------|---------|----------------|
| Back in Black | AC/DC | `back_in_black.mp3` |
| Smells Like Teen Spirit | Nirvana | `smells_like_teen_spirit.mp3` |
| Come Together | The Beatles | `come_together.mp3` |
| Whole Lotta Love | Led Zeppelin | `whole_lotta_love.mp3` |
| Eye of the Tiger | Survivor | `eye_of_the_tiger.mp3` |

### 🎵 Pop
| Canción | Artista | ID del archivo |
|---------|---------|----------------|
| Billie Jean | Michael Jackson | `billie_jean.mp3` |
| Uptown Funk | Bruno Mars | `uptown_funk.mp3` |
| Shape of You | Ed Sheeran | `shape_of_you.mp3` |
| Just the Way You Are | Bruno Mars | `just_the_way_you_are.mp3` |

### 🎷 Funk / Soul
| Canción | Artista | ID del archivo |
|---------|---------|----------------|
| Superstition | Stevie Wonder | `superstition.mp3` |
| Get Up (I Feel Like Being a) Sex Machine | James Brown | `get_up_james_brown.mp3` |
| September | Earth, Wind & Fire | `september.mp3` |

### 🔥 Metal
| Canción | Artista | ID del archivo |
|---------|---------|----------------|
| Enter Sandman | Metallica | `enter_sandman.mp3` |
| Master of Puppets | Metallica | `master_of_puppets.mp3` |
| Holy Wars | Megadeth | `holy_wars.mp3` |

---

## Configuración en Moises

### Ajustes recomendados al exportar:
- **Formato**: MP3
- **Calidad**: 320 kbps (máxima)
- **Pistas activas**: Voz ✅ + Guitarra ✅ + Bajo ✅ + Teclado ✅
- **Pistas silenciadas**: Batería ❌

### Tip importante:
Moises a veces deja "bleeding" de batería (se escucha levemente).
Si pasa, baja el volumen de esa pista al 0% en el mezclador antes de exportar.

---

## Después de agregar los archivos

```bash
# 1. Registra los nuevos archivos
python3 register_backing_tracks.py

# 2. Reconstruye y corre
flutter run
```

La app detecta automáticamente si una canción tiene backing track.
Si no tiene, funciona igual pero en modo MIDI + sonidos de batería.

---

## Indicadores en la app

- 🎵 = Tiene backing track (pista completa con voz)
- 🥁 = Solo MIDI (sin pista de fondo)

