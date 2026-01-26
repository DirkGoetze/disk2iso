# Kapitel 4.4: Metadaten-System

Automatische und nachträgliche Metadaten-Erfassung für Audio-CDs, DVDs und Blu-rays.

## Inhaltsverzeichnis

1. [Übersicht](#übersicht)
2. [Architektur](#architektur)
3. [Provider](#provider)
4. [Ausgabe-Formate](#ausgabe-formate)
5. [Interaktive Auswahl](#interaktive-auswahl)
6. [Nachträgliche Erfassung](#nachträgliche-erfassung)
7. [API-Referenz](#api-referenz)

---

## Übersicht

### Was sind Metadaten?

**Metadaten** = Informationen über das Medium:

- **Audio-CDs**: Artist, Album, Jahr, Genre, Cover, Track-Titel
- **DVDs/Blu-rays**: Titel, Jahr, Regisseur, Genre, Laufzeit, Rating, Poster

### Warum Metadaten?

#### 📚 Media-Server Integration

**Jellyfin, Kodi, Plex** erkennen Medien automatisch:

```
/audio/Pink Floyd/The Wall (1979)/
  ├── 01 - In the Flesh.mp3      # ID3-Tags
  ├── album.nfo                   # Jellyfin-Metadaten
  └── folder.jpg                  # Album-Cover

/dvd/THE_MATRIX.iso
  ├── THE_MATRIX.nfo              # Film-Metadaten
  └── THE_MATRIX-thumb.jpg        # Poster
```

**Resultat**: Professionelle Bibliothek mit Covern, Beschreibungen, Ratings

#### 🔍 Suchbarkeit

- **Dateiname**: `Unknown_Album.iso` → schwer zu finden
- **Mit Metadaten**: Suche nach "Pink Floyd" → sofort gefunden

#### 📊 Statistiken

- Anzahl Alben pro Artist
- Filme nach Genre
- Durchschnittliche Rating-Werte

---

## Architektur

### Komponenten-Übersicht

```
disk2iso Metadaten-System
    │
    ├─► Audio-CD Metadaten (lib-cd.sh)
    │   ├─► Provider: MusicBrainz
    │   ├─► Fallback: CD-TEXT
    │   ├─► Ausgabe: MP3 (ID3v2.4), album.nfo, folder.jpg
    │   └─► Nachträglich: lib-cd-metadata.sh
    │
    └─► DVD/Blu-ray Metadaten (lib-dvd-metadata.sh)
        ├─► Provider: TMDB (The Movie Database)
        ├─► Ausgabe: .nfo, -thumb.jpg
        └─► Nachträglich: Über Web-Interface API
```

### Metadaten-Lifecycle

#### Während Archivierung (Automatisch)

```
Disc einlegen
    ↓
Disc-Typ erkennen
    ↓
ISO/MP3s erstellen
    ↓
Metadaten-Provider abfragen
    ├─► Audio-CD: MusicBrainz
    └─► DVD/BD: TMDB
    ↓
Bei mehreren Treffern:
    ├─► Web-Interface Modal anzeigen
    └─► Benutzer-Auswahl (5 Min Timeout)
    ↓
Metadaten erstellen:
    ├─► Audio: ID3-Tags + NFO + Cover
    └─► Video: NFO + Poster
    ↓
Fertig
```

#### Nachträglich (Manuell)

```
Web-Interface → Archiv
    ↓
Medium ohne Metadaten auswählen
    ↓
"Add Metadata" Button klicken
    ↓
Provider-Suche
    ↓
Auswahl-Modal (falls mehrere Treffer)
    ↓
Metadaten erstellen/aktualisieren
    ↓
Fertig
```

---

## Provider

### MusicBrainz (Audio-CDs)

**URL**: https://musicbrainz.org

**API**: Kostenlos, kein API-Key erforderlich

**Funktionsweise**:
1. **Disc-ID** aus TOC berechnen (cdparanoia)
2. **MusicBrainz-Lookup** via Disc-ID
3. **Album-Daten** abrufen (Artist, Album, Tracks, Jahr)
4. **Cover-Download** via Cover Art Archive

**Details**: Siehe [Kapitel 4.4.1: MusicBrainz-Integration](04-4_Metadaten/04-4-1_MusicBrainz.md)

### TMDB (DVDs/Blu-rays)

**URL**: https://www.themoviedb.org

**API**: Kostenlos, API-Key erforderlich

**Funktionsweise**:
1. **Titel-Extraktion** aus Disc-Label
2. **TMDB-Suche** nach Film/TV-Serie
3. **Film-Details** abrufen (Regisseur, Genre, Rating)
4. **Poster-Download** (w500)

**Details**: Siehe [Kapitel 4.4.2: TMDB-Integration](04-4_Metadaten/04-4-2_TMDB.md)

### Provider-Vergleich

| Feature | MusicBrainz | TMDB |
|---------|-------------|------|
| **Disc-Typen** | Audio-CD | DVD, Blu-ray |
| **API-Key** | ❌ Nicht erforderlich | ✅ Erforderlich (kostenlos) |
| **Rate-Limit** | 1 req/s | 40 req/10s |
| **Datenqualität** | ⭐⭐⭐⭐⭐ Exzellent | ⭐⭐⭐⭐⭐ Exzellent |
| **Abdeckung** | ~2.5M Releases | ~900K Filme, ~200K TV-Serien |
| **Sprachen** | Mehrsprachig | Mehrsprachig |
| **Cover-Größe** | 500x500 (Cover Art Archive) | w500 (ca. 500px breit) |
| **Identifikation** | Disc-ID (100% genau) | Titel-Suche (Fuzzy) |

---

## Ausgabe-Formate

### ID3v2.4 Tags (MP3)

**Standard**: ID3v2.4 (neueste Version, 2000)

**Tags** (Audio-CD):
```
Artist: Pink Floyd
Album: The Wall
Title: In the Flesh?
Year: 1979
Track: 1/26
Genre: Rock
AlbumArtist: Pink Floyd
MusicBrainzAlbumId: a1b2c3d4-5678-90ab-cdef-1234567890ab
MusicBrainzTrackId: 9z8y7x6w-5v4u-3t2s-1r0q-ponmlkjihgfe
APIC: image/jpeg (Cover, 500x500)
```

**Tools**:
- **Schreiben**: eyeD3 (in lib-cd.sh)
- **Lesen**: `eyeD3 file.mp3` oder `id3v2 -l file.mp3`

### NFO-Dateien

**Format**: Custom Key-Value (für disk2iso) oder XML (für Jellyfin/Kodi)

#### Audio-CD (album.nfo)

**XML-Format** (Jellyfin/Kodi):
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

#### DVD/Blu-ray (.nfo)

**Key-Value-Format** (disk2iso):
```
TITLE=The Matrix
YEAR=1999
DIRECTOR=Lana Wachowski
GENRE=Action, Science Fiction
RUNTIME=136
RATING=8.2
TYPE=dvd-video
OVERVIEW=Set in the 22nd century, The Matrix tells the story of...
TMDBID=603
```

**Alternativ: XML** (für Jellyfin/Kodi, in Entwicklung):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<movie>
  <title>The Matrix</title>
  <year>1999</year>
  <director>Lana Wachowski</director>
  <genre>Action</genre>
  <runtime>136</runtime>
  <rating>8.2</rating>
  <plot>Set in the 22nd century...</plot>
  <tmdbid>603</tmdbid>
</movie>
```

### Cover/Poster-Bilder

#### Audio-CD (folder.jpg)

- **Größe**: 500x500 px
- **Format**: JPEG
- **Quelle**: Cover Art Archive (MusicBrainz)
- **Embedded**: Auch in MP3s (APIC frame)

**Verwendung**:
- Jellyfin/Kodi: Automatische Erkennung
- VLC: Anzeige im Player
- Dateimanager: Ordner-Vorschau

#### DVD/Blu-ray (-thumb.jpg)

- **Größe**: ~500px Breite (TMDB w500)
- **Format**: JPEG
- **Quelle**: TMDB
- **Dateiname**: `{ISO_NAME}-thumb.jpg`

**Beispiel**:
```
/dvd/
├── THE_MATRIX.iso
└── THE_MATRIX-thumb.jpg
```

---

## Interaktive Auswahl

### Wann wird Benutzer-Eingabe benötigt?

#### MusicBrainz (Audio-CD)

**Mehrere Releases** zur gleichen Disc-ID:

```
Disc-ID: 76118c18
→ 7 Releases gefunden:
  [0] Cat Stevens - Remember (1999, GB)       Score: 100
  [1] Cat Stevens - Remember (1999, AU)       Score: 95
  [2] Various Artists - なつかしの... (2010, JP) Score: 40
  ...
```

**Grund**: Verschiedene Länderpressungen, Reissues, Compilations

#### TMDB (DVD/Blu-ray)

**Mehrere Filme** mit ähnlichem Titel:

```
Suche: "Matrix"
→ 12 Filme gefunden:
  [0] The Matrix (1999)                Score: 100
  [1] The Matrix Reloaded (2003)       Score: 85
  [2] The Matrix Revolutions (2003)    Score: 85
  [3] Matrix (1993, TV-Film)           Score: 60
  ...
```

**Oder: Film vs. TV-Serie**:

```
Suche: "Breaking Bad"
→ Type-Selection Modal:
  [ ] Film
  [✓] TV-Serie
```

### Modal-Ablauf

#### 1. Automatischer Trigger

```bash
# In lib-cd.sh oder lib-dvd-metadata.sh
if [[ ${#releases[@]} -gt 1 ]]; then
    # JSON erstellen
    create_releases_json "$releases"
    
    # Status setzen
    update_api_status "waiting_user_input" "MusicBrainz: ${#releases[@]} Alben gefunden"
    
    # Warten auf Auswahl (max 5 Min)
    wait_for_user_selection 300
fi
```

#### 2. Web-Interface Polling

**JavaScript** (z.B. in `musicbrainz.js`):

```javascript
// Alle 5 Sekunden prüfen
setInterval(() => {
    fetch('/api/status')
        .then(r => r.json())
        .then(data => {
            if (data.state === 'waiting_user_input') {
                // Modal anzeigen
                showSelectionModal();
            }
        });
}, 5000);
```

#### 3. Modal-Anzeige

**HTML-Modal** mit Release-Liste:

```html
<div id="selection-modal" class="modal">
  <h2>Album auswählen (7 Treffer)</h2>
  <div class="releases">
    <div class="release-card" onclick="selectRelease(0)">
      <div class="release-info">
        <strong>Cat Stevens - Remember</strong>
        <span>1999, GB • 24 Tracks • Score: 100</span>
      </div>
    </div>
    <!-- Weitere Releases... -->
  </div>
  <button onclick="manualInput()">Manuelle Eingabe</button>
</div>
```

#### 4. Benutzer-Auswahl

**JavaScript**:

```javascript
function selectRelease(index) {
    fetch('/api/musicbrainz/select', {
        method: 'POST',
        body: JSON.stringify({index: index})
    })
    .then(() => {
        hideModal();
        showNotification('Album ausgewählt');
    });
}
```

#### 5. Backend-Fortsetzung

```bash
# In lib-cd.sh
wait_for_user_selection() {
    local timeout=$1
    local start_time=$(date +%s)
    
    while true; do
        # Prüfe auf Auswahl
        if [[ -f "$SELECTION_FILE" ]]; then
            selected_index=$(jq -r '.index' "$SELECTION_FILE")
            break
        fi
        
        # Timeout
        if (( $(date +%s) - start_time > timeout )); then
            # Automatische Auswahl (höchster Score)
            selected_index=0
            break
        fi
        
        sleep 2
    done
    
    # Mit gewähltem Release fortfahren
    process_release "$selected_index"
}
```

### Timeout-Verhalten

**Standard**: 5 Minuten

**Bei Timeout**:
- **Audio-CD**: Release mit höchstem Score
- **DVD/Blu-ray**: Erster Treffer (meist höchste Relevanz)

**Konfigurierbar** in `lib/config.sh`:
```bash
readonly METADATA_SELECTION_TIMEOUT=300  # Sekunden
```

---

## Nachträgliche Erfassung

### Use-Cases

1. **Provider war offline**: MusicBrainz/TMDB nicht erreichbar
2. **Falsche Auswahl**: Versehentlich falsches Album/Film gewählt
3. **Fehlende API-Key**: TMDB-Key nachträglich konfiguriert
4. **Manuelle Korrektur**: Metadaten aktualisieren

### Audio-CD Remastering

**Prozess**:

```
Web-Interface → Archiv → Audio-CD ohne Metadaten
    ↓
"Add Metadata" Button
    ↓
MusicBrainz-Suche (Disc-ID aus ISO extrahieren)
    ↓
Auswahl-Modal (bei mehreren Treffern)
    ↓
MP3s aus ISO extrahieren
    ↓
ID3-Tags neu schreiben
    ↓
Cover downloaden
    ↓
NFO erstellen
    ↓
Neue ISO erstellen
    ↓
Alte ISO ersetzen
```

**Technisch** (in `lib-cd-metadata.sh`):

```bash
remaster_audio_iso() {
    local iso_path="$1"
    local musicbrainz_id="$2"
    
    # ISO mounten
    mount -o loop,ro "$iso_path" "$MOUNT_POINT"
    
    # MP3s kopieren
    cp "$MOUNT_POINT"/*.mp3 "$TEMP_DIR"/
    
    # Metadaten abrufen
    album_data=$(get_musicbrainz_data "$musicbrainz_id")
    
    # ID3-Tags aktualisieren
    for mp3 in "$TEMP_DIR"/*.mp3; do
        eyeD3 --remove-all "$mp3"
        eyeD3 --artist "$artist" --album "$album" "$mp3"
    done
    
    # Cover + NFO
    download_cover "$musicbrainz_id"
    create_nfo "$album_data"
    
    # Neue ISO
    genisoimage -o "$iso_path.new" "$TEMP_DIR"/
    mv "$iso_path.new" "$iso_path"
    
    # Cleanup
    umount "$MOUNT_POINT"
    rm -rf "$TEMP_DIR"
}
```

### DVD/Blu-ray Metadaten

**Einfacher** (keine ISO-Änderung):

```
Web-Interface → Archiv → DVD/BD ohne Metadaten
    ↓
"Add Metadata" Button
    ↓
TMDB-Suche (Titel aus Dateiname extrahieren)
    ↓
Auswahl-Modal (bei mehreren Treffern)
    ↓
NFO-Datei erstellen
    ↓
Poster downloaden
    ↓
Fertig (ISO bleibt unverändert)
```

**Resultat**:
```
/dvd/
├── INCEPTION.iso          (unverändert)
├── INCEPTION.md5          (unverändert)
├── INCEPTION.nfo          (neu)
└── INCEPTION-thumb.jpg    (neu)
```

---

## API-Referenz

### MusicBrainz-Endpunkte

```bash
# Disc-ID-Lookup
GET https://musicbrainz.org/ws/2/discid/{disc_id}?fmt=json&inc=artist-credits+recordings

# Cover-Download
GET http://coverartarchive.org/release/{release_id}/front-500
```

### TMDB-Endpunkte

```bash
# Film-Suche
GET https://api.themoviedb.org/3/search/movie?api_key={key}&query={title}&language=de-DE

# TV-Serien-Suche
GET https://api.themoviedb.org/3/search/tv?api_key={key}&query={title}&language=de-DE

# Film-Details
GET https://api.themoviedb.org/3/movie/{movie_id}?api_key={key}&language=de-DE&append_to_response=credits

# Poster-Download
GET https://image.tmdb.org/t/p/w500{poster_path}
```

### disk2iso Web-API

```bash
# MusicBrainz-Releases abrufen
GET /api/musicbrainz/releases

# MusicBrainz-Auswahl
POST /api/musicbrainz/select
Content-Type: application/json
{"index": 0}

# Manuelle Metadaten
POST /api/musicbrainz/manual
Content-Type: application/json
{"artist": "My Band", "album": "My Album", "year": 2023}

# TMDB-Ergebnisse
GET /api/tmdb/results

# TMDB-Auswahl
POST /api/tmdb/select
Content-Type: application/json
{"index": 0, "type": "movie"}

# TMDB Type-Selection
POST /api/tmdb/type
Content-Type: application/json
{"type": "tv"}

# Nachträgliche Audio-Metadaten
POST /api/metadata/musicbrainz/apply
Content-Type: application/json
{"iso_path": "/audio/Unknown/Unknown.iso", "musicbrainz_id": "..."}

# Nachträgliche Video-Metadaten
POST /api/metadata/tmdb/apply
Content-Type: application/json
{"iso_path": "/dvd/MOVIE.iso", "tmdb_id": 603, "type": "movie"}
```

---

## Weiterführende Links

- **[← Zurück: Kapitel 4.3 - Blu-ray-Video](04-3_BD-Video.md)**
- **[Kapitel 4.4.1: MusicBrainz-Integration →](04-4_Metadaten/04-4-1_MusicBrainz.md)**
- **[Kapitel 4.4.2: TMDB-Integration →](04-4_Metadaten/04-4-2_TMDB.md)**
- **[Kapitel 4.5: MQTT-Integration →](04-5_MQTT.md)**
- **[Kapitel 5: Fehlerhandling →](../05_Fehlerhandling.md)**

---

**Version:** 1.2.0  
**Letzte Aktualisierung:** 26. Januar 2026
