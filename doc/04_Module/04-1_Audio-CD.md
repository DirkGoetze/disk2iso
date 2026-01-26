# Kapitel 4.1: Audio-CD Modul (lib-cd.sh)

Professionelles Audio-CD Ripping mit automatischer Metadaten-Erfassung und MP3-Encoding.

## Inhaltsverzeichnis

1. [Übersicht](#übersicht)
2. [Funktionsweise](#funktionsweise)
3. [Metadaten-Erfassung](#metadaten-erfassung)
4. [Ausgabe-Struktur](#ausgabe-struktur)
5. [Konfiguration](#konfiguration)
6. [Fehlerbehandlung](#fehlerbehandlung)
7. [Performance](#performance)
8. [Nachträgliche Metadaten](#nachträgliche-metadaten)

---

## Übersicht

### Modul-Aktivierung

**Automatisch aktiviert** wenn folgende Tools installiert sind:

- `cdparanoia` - Lossless Audio-Extraktion
- `lame` - MP3-Encoding
- `genisoimage` - ISO-Erstellung (optional)

**Prüfung**:

```bash
# Modul-Status
grep "MODULE_AUDIO_CD" /opt/disk2iso/lib/config.sh

# Dependencies prüfen
which cdparanoia lame genisoimage
```

### Features

#### 🎵 Audio-Extraktion

- **cdparanoia**: Lossless Ripping mit Fehlerkorrektur
- **Jitter-Correction**: Automatische Synchronisation
- **C2-Fehler-Erkennung**: Maximale Qualität
- **Retry-Mechanismus**: Bis zu 20 Versuche pro Sektor

#### 🎶 MP3-Encoding

- **LAME VBR V2**: ~190 kbps durchschnittlich (fest kodiert)
- **Qualität**: Transparent für die meisten Hörer
- **ID3v2.4 Tags**: Vollständige Metadaten
- **Gapless Playback**: Unterstützt

#### 📊 Metadaten

- **Primär**: MusicBrainz-API (Disc-ID basiert)
- **Fallback 1**: CD-TEXT (icedax/cd-info)
- **Fallback 2**: `Unknown_Artist/Unknown_Album`
- **Cover-Download**: Cover Art Archive (500x500 px)
- **NFO-Dateien**: Jellyfin/Kodi-kompatibel

#### 🔄 Interaktive Auswahl

- **Mehrfach-Treffer**: Automatisches Modal im Web-Interface
- **Manuelle Eingabe**: Falls keine passende MusicBrainz-Treffer
- **Timeout**: 5 Minuten → dann automatische Auswahl

---

## Funktionsweise

### Ablauf-Diagramm

```plain
Audio-CD einlegen
    ↓
[lib-diskinfos.sh] is_audio_cd() → true
    ↓
[disk2iso.sh] Lade lib-cd.sh
    ↓
[lib-cd.sh] copy_audio_cd()
    ├─► get_disc_id() → "wXyz1234..."
    ├─► musicbrainz_lookup() → Album-Daten
    │   └─► Bei mehreren Treffern:
    │       ├─► Erstelle musicbrainz_releases.json
    │       ├─► Status: waiting_user_input
    │       ├─► Web-Interface Modal anzeigen
    │       └─► Warte auf Benutzer-Auswahl (max 5 Min)
    ├─► ensure_audio_dir() → /audio/Artist/Album/
    ├─► extract_tracks() (cdparanoia)
    │   └─► Pro Track:
    │       ├─► cdparanoia -d /dev/sr0 -w 1
    │       ├─► lame -V2 --quiet track01.wav track01.mp3
    │       ├─► eyeD3 --remove-all track01.mp3 (alte Tags löschen)
    │       └─► eyeD3 --add-tags track01.mp3 (neue Tags)
    ├─► download_cover() → folder.jpg
    ├─► create_nfo() → album.nfo
    └─► cleanup_temp()
    ↓
[lib-logging.sh] log_success()
    ↓
[lib-mqtt.sh] publish_mqtt() (falls aktiviert)
```

### Code-Struktur

**Datei**: `lib/lib-cd.sh` (~800 Zeilen)

#### Haupt-Funktionen

```bash
copy_audio_cd() {
    # Hauptfunktion: Orchestriert gesamten Prozess
    local device="$1"
    local output_dir="$2"
    local disc_label="$3"
}

get_disc_id() {
    # Disc-ID via cdparanoia
    # Return: "wXyz1234AbCd5678"
}

musicbrainz_lookup() {
    # MusicBrainz-API-Abfrage
    # Return: JSON mit Album-Daten
}

extract_tracks() {
    # Track-für-Track Extraktion
    # cdparanoia → LAME → eyeD3
}

download_cover() {
    # Cover Art Archive
    # Download: folder.jpg (500x500)
}

create_nfo() {
    # Jellyfin NFO-Datei
}
```

---

## Metadaten-Erfassung

### MusicBrainz-Integration

#### Disc-ID Berechnung

```bash
# Disc-ID via cdparanoia
disc_id=$(cdparanoia -d /dev/sr0 -Q 2>&1 | grep "CDDB" | awk '{print $2}')
# → "76118c18"
```

**Alternative** (wenn cdparanoia keine CDDB-ID liefert):

```bash
# libdiscid verwenden
discid /dev/sr0
# → "wXyz1234AbCd5678 24 150 23456 45678 ..."
```

#### API-Abfrage

**Endpunkt**: `https://musicbrainz.org/ws/2/discid/{disc_id}?fmt=json&inc=artist-credits+recordings`

**Beispiel-Request**:

```bash
curl -s "https://musicbrainz.org/ws/2/discid/76118c18?fmt=json&inc=artist-credits+recordings"
```

**Response** (vereinfacht):

```json
{
  "releases": [
    {
      "title": "Remember",
      "artist-credit": [{"name": "Cat Stevens"}],
      "date": "1999",
      "country": "GB",
      "media": [
        {
          "format": "CD",
          "track-count": 24,
          "tracks": [
            {"title": "Morning Has Broken", "position": 1},
            {"title": "Can't Keep It In", "position": 2},
            ...
          ]
        }
      ],
      "id": "a1b2c3d4-5678-90ab-cdef-1234567890ab"
    }
  ]
}
```

#### Mehrfach-Treffer

**Wenn `releases.length > 1`:**

1. **Erstelle JSON-Datei**: `/opt/disk2iso/api/musicbrainz_releases.json`

   ```json
   {
     "disc_id": "76118c18",
     "releases": [
       {
         "index": 0,
         "artist": "Cat Stevens",
         "album": "Remember",
         "year": 1999,
         "country": "GB",
         "tracks": 24,
         "score": 100
       },
       {
         "index": 1,
         "artist": "Cat Stevens",
         "album": "Remember",
         "year": 1999,
         "country": "AU",
         "tracks": 24,
         "score": 95
       }
     ]
   }
   ```

2. **Status setzen**: `waiting_user_input`

3. **MQTT-Benachrichtigung**: `waiting - MusicBrainz: 7 Alben gefunden`

4. **Web-Interface Modal**: Automatische Anzeige in `/www/templates/musicbrainz_modal.html`

5. **Polling**: Prüft alle 5 Sekunden auf Benutzer-Auswahl in `musicbrainz_selection.json`

6. **Timeout**: Nach 5 Minuten → Automatische Auswahl des Release mit höchstem Score

**Beispiel-Szenario**:

```plain
Disc-ID: 76118c18
→ 7 Releases gefunden:
  [0] Cat Stevens - Remember (1999, GB)       Score: 100 ← Beste Übereinstimmung
  [1] Cat Stevens - Remember (1999, AU)       Score: 95
  [2] Cat Stevens - Remember (1999, NZ)       Score: 95
  [3] Various Artists - なつかしの... (2010, JP) Score: 40
  [4] Zarah Leander - Kann denn... (1997)     Score: 20
  [5] ...
→ Benutzer wählt [0] im Web-Interface
→ System fährt fort mit GB-Version
```

#### Manuelle Metadaten-Eingabe

**Falls kein Release passt:**

Web-Interface bietet Formular:

```plain
Artist: _______________________
Album:  _______________________
Year:   ____
```

**Technisch**:

```json
// POST /api/musicbrainz/manual
{
  "artist": "My Band",
  "album": "My Album",
  "year": 2023
}
```

**Resultat**: Keine MusicBrainz-ID, keine Cover, keine Track-Titel (nur "Track 01", "Track 02", ...)

### CD-TEXT Fallback

**Wenn MusicBrainz fehlschlägt:**

```bash
# CD-TEXT auslesen (icedax)
icedax -J -D /dev/sr0 -g 2>&1 | grep -E "Albumtitle|Performer"

# Oder cd-info
cd-info --no-device-info /dev/sr0 | grep -E "title|performer"
```

**Verfügbarkeit**: Nur ~20% der Audio-CDs haben CD-TEXT

### Unknown-Fallback

**Wenn alle Methoden fehlschlagen:**

```plain
/audio/
└── Unknown_Artist/
    └── Unknown_Album/
        ├── Track_01.mp3
        ├── Track_02.mp3
        └── ...
```

**ID3-Tags**:

- Artist: `Unknown Artist`
- Album: `Unknown Album`
- Title: `Track 01`, `Track 02`, ...
- Year: (leer)

---

## Ausgabe-Struktur

### Verzeichnis-Layout

```plain
/srv/disk2iso/audio/
└── Pink Floyd/
    └── The Wall (1979)/
        ├── 01 - In the Flesh.mp3
        ├── 02 - The Thin Ice.mp3
        ├── 03 - Another Brick in the Wall (Part I).mp3
        ├── ...
        ├── 26 - Outside the Wall.mp3
        ├── folder.jpg              # 500x500 px Cover
        └── album.nfo               # Jellyfin-Metadaten
```

### Dateinamen-Schema

**Mit MusicBrainz**:

```plain
{track_number:02d} - {track_title}.mp3
```

**Beispiele**:

- `01 - Morning Has Broken.mp3`
- `14 - Wild World.mp3`

**Sanitizing**:

- Sonderzeichen: `/ \ : * ? " < > |` → `_`
- Umlaute: `ä → ae`, `ö → oe`, `ü → ue`, `ß → ss`
- Leerzeichen: Erhalten (nicht ersetzt)

### MP3-Metadaten (ID3v2.4)

**Tags**:

```plain
Artist: Pink Floyd
Album: The Wall
Title: In the Flesh?
Year: 1979
Track: 1/26
Genre: Rock
AlbumArtist: Pink Floyd
MusicBrainzAlbumId: a1b2c3d4-5678-90ab-cdef-1234567890ab
MusicBrainzTrackId: 9z8y7x6w-5v4u-3t2s-1r0q-ponmlkjihgfe
```

**Cover**: Embedded (APIC frame, JPEG, 500x500 px)

### NFO-Datei (Jellyfin/Kodi)

**Datei**: `album.nfo`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<album>
  <title>The Wall</title>
  <artist>Pink Floyd</artist>
  <year>1979</year>
  <genre>Rock</genre>
  <rating>5.0</rating>
  <musicbrainzalbumid>a1b2c3d4-5678-90ab-cdef-1234567890ab</musicbrainzalbumid>
</album>
```

**Jellyfin-Import**: Automatisch erkannt bei Scan

---

## Konfiguration

### Fest kodierte Einstellungen

**In `lib/lib-cd.sh` (Zeile ~50-60):**

```bash
# MP3-Qualität (fest)
readonly LAME_QUALITY="2"  # VBR V2 (~190 kbps)

# MusicBrainz (immer aktiviert)
readonly USE_MUSICBRAINZ="true"

# Cover-Download (immer aktiviert)
readonly DOWNLOAD_COVERS="true"

# NFO-Erstellung (immer aktiviert)
readonly CREATE_NFO="true"
```

**Nicht konfigurierbar** ohne Code-Änderung.

### Anpassbare Optionen

**Wenn gewünscht** (Code editieren):

#### MP3-Qualität ändern

```bash
# In lib-cd.sh, Funktion encode_track()
# Zeile ~400

# Original:
lame -V2 --quiet "$wav_file" "$mp3_file"

# Höhere Qualität (V0 = ~245 kbps):
lame -V0 --quiet "$wav_file" "$mp3_file"

# Konstante Bitrate (320 kbps):
lame -b 320 --quiet "$wav_file" "$mp3_file"

# FLAC statt MP3 (verlustfrei):
flac --best --silent "$wav_file" -o "${mp3_file%.mp3}.flac"
```

#### MusicBrainz deaktivieren

```bash
# In lib-cd.sh, Funktion copy_audio_cd()
# Zeile ~150
# Kommentiere aus:
# musicbrainz_lookup "$disc_id"

# Ersatz: Immer CD-TEXT verwenden
read_cd_text "$device"
```

---

## Fehlerbehandlung

### cdparanoia Fehler

**Problem**: Lesefehler bei Track 5

**Log**:

```plain
[WARNING] Track 5: cdparanoia meldet 12 Fehler
[INFO] Retry: Track 5 mit erhöhter Overlap
[SUCCESS] Track 5: Jitter korrigiert, 0 finale Fehler
```

**Mechanismus**:

- **Retry**: Bis zu 3 Versuche mit erhöhter Overlap
- **Fallback**: Wenn >100 Fehler → Track mit Fehlern akzeptieren (Log-Warnung)

### MusicBrainz API-Fehler

**Problem**: API nicht erreichbar

**Log**:

```plain
[WARNING] MusicBrainz-API nicht erreichbar
[INFO] Fallback: CD-TEXT Suche...
[INFO] CD-TEXT gefunden: Artist - Album
```

**Graceful Degradation**: CD-TEXT → Unknown

### Voller Speicher

**Problem**: Kein Platz während MP3-Encoding

**Log**:

```plain
[ERROR] Encoding Track 8 fehlgeschlagen: No space left on device
[ERROR] Cleanup: Entferne temporäre Dateien
[ERROR] Audio-CD abgebrochen: Speicherplatz voll
```

**Cleanup**: Alle Temp-Dateien werden entfernt, State → `error`

---

## Performance

### Verarbeitungszeiten

**Gemessen** (12 Tracks, 47 Min Spielzeit):

| Phase | Dauer | Details |
|-------|-------|---------|
| Disc-ID | 2s | cdparanoia TOC-Analyse |
| MusicBrainz | 1s | API-Request + Parsing |
| Track 1-12 Extraktion | 8 Min | cdparanoia (0.6x Realtime) |
| Track 1-12 Encoding | 3 Min | LAME VBR V2 |
| ID3-Tags | 30s | eyeD3 (12 Tracks) |
| Cover-Download | 2s | Cover Art Archive |
| **Gesamt** | **~15 Min** | **0.32x Realtime** |

**Realtime-Faktor**: Audio-CD (47 Min) → 15 Min Verarbeitung = **0.32x**

### Optimierungen

#### Sequenzielle Verarbeitung

**Aktuell** (platzsparend):

```plain
Track 1: WAV → MP3 → Löschen WAV → ID3-Tags
Track 2: WAV → MP3 → Löschen WAV → ID3-Tags
...
```

**Resultat**: Max. 50 MB Temp-Speicher (1 WAV)

**Alternative** (parallel, nicht implementiert):

```plain
Alle Tracks: WAV extrahieren (parallel)
→ 700 MB Temp-Speicher (14 WAVs)
Alle Tracks: MP3 encodieren (parallel)
→ 2x schneller, aber mehr RAM
```

#### cdparanoia Tuning

**Problem**: Zu viele Retries bei Scratches

**Lösung**:

```bash
# In lib-cd.sh, Funktion extract_track()
# Max Retries reduzieren:
cdparanoia -d "$device" -w "$track" --max-retries 10
# (Standard: 20)
```

**Trade-off**: Schneller, aber mehr Fehler akzeptiert

---

## Nachträgliche Metadaten

Seit Version 1.2.0: Metadaten für bereits erstellte Audio-ISOs nachträglich hinzufügen.

### Anwendungsfall

**Situation**: Audio-CD bereits gerippt, aber:

- MusicBrainz-API war offline → `Unknown_Artist/Unknown_Album`
- Falsche Album-Auswahl getroffen
- Manuelle Metadaten waren unvollständig

**Lösung**: "Add Metadata" Button im Web-Interface Archive-Seite

### Ablauf

1. **Web-Interface**: Archiv → Audio-CD ohne Metadaten → "Add Metadata"
2. **MusicBrainz-Suche**: Disc-ID aus ISO extrahieren → API-Abfrage
3. **Auswahl-Modal**: Wie bei normaler CD (falls mehrere Treffer)
4. **Remastering**:
   - MP3s aus ISO extrahieren
   - Neue ID3-Tags schreiben (eyeD3)
   - Cover downloaden
   - NFO erstellen
   - Neue ISO erstellen
5. **Ersetzen**: Alte ISO durch neue ISO ersetzen

### Technische Details

**API-Endpunkte**:

```plain
GET  /api/metadata/musicbrainz/search?iso_path=/audio/Unknown_Artist/...iso
POST /api/metadata/musicbrainz/apply
```

**Prozess** (in `lib-cd-metadata.sh`):

```bash
remaster_audio_iso() {
    local iso_path="$1"
    local musicbrainz_id="$2"
    
    # ISO mounten
    mount -o loop,ro "$iso_path" /mnt/temp
    
    # MP3s kopieren
    cp /mnt/temp/*.mp3 /tmp/remaster/
    
    # Metadaten aus MusicBrainz
    get_album_data "$musicbrainz_id"
    
    # ID3-Tags neu schreiben
    for mp3 in /tmp/remaster/*.mp3; do
        eyeD3 --remove-all "$mp3"
        eyeD3 --artist "$artist" --album "$album" "$mp3"
    done
    
    # Cover + NFO
    download_cover "$musicbrainz_id"
    create_nfo
    
    # Neue ISO
    genisoimage -o "$iso_path.new" /tmp/remaster/
    mv "$iso_path.new" "$iso_path"
    
    # Cleanup
    umount /mnt/temp
    rm -rf /tmp/remaster
}
```

---

## Weiterführende Links

- **[← Zurück: Kapitel 4 - Optionale Module](../04_Module/)**
- **[Kapitel 4.4.1: MusicBrainz-Integration →](04-4_Metadaten/04-4-1_MusicBrainz.md)**
- **[Kapitel 5: Fehlerhandling →](../05_Fehlerhandling.md)**
- **[Kapitel 6: Entwickler →](../06_Entwickler.md)**

---

**Version:** 1.2.0  
**Letzte Aktualisierung:** 26. Januar 2026
