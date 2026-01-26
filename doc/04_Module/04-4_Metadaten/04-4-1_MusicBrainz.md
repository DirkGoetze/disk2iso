# Kapitel 4.4.1: MusicBrainz-Integration

Automatische Album-Metadaten für Audio-CDs via MusicBrainz und Cover Art Archive.

## Inhaltsverzeichnis

1. [Übersicht](#übersicht)
2. [MusicBrainz Datenbank](#musicbrainz-datenbank)
3. [Disc-ID Berechnung](#disc-id-berechnung)
4. [API-Abfragen](#api-abfragen)
5. [Mehrfach-Treffer](#mehrfach-treffer)
6. [Cover Art Archive](#cover-art-archive)
7. [Troubleshooting](#troubleshooting)

---

## Übersicht

### Was ist MusicBrainz?

**MusicBrainz** ist eine Community-gepflegte Musik-Enzyklopädie:

- **Open Database**: ~2.5 Millionen Releases
- **Disc-ID basiert**: 100% genaue Identifikation via TOC (Table of Contents)
- **Kostenlos**: API ohne Registrierung/API-Key
- **Non-Commercial**: Rate-Limit 1 Request/Sekunde

**Website**: https://musicbrainz.org

### Warum MusicBrainz?

#### 🎯 Präzise Identifikation

**Problem mit Titel-Suche** (wie bei TMDB):
- "Greatest Hits" → 10.000+ Treffer
- Fuzzy Matching fehleranfällig

**Lösung: Disc-ID**:
- Berechnet aus TOC (Track-Anzahl, Längen, Offsets)
- **Eindeutig** für jede CD-Pressung
- Findet **exakt** die richtige Version (Land, Jahr, Label)

**Beispiel**:
```
TOC: 14 Tracks, Offsets: 150, 23456, 45678, ...
→ Disc-ID: 76118c18
→ MusicBrainz: "Cat Stevens - Remember (1999, GB)"
```

#### 📊 Vollständige Metadaten

**MusicBrainz liefert**:
- Album-Titel, Artist, Jahr
- Track-Titel (alle 14 Tracks einzeln)
- MusicBrainz-IDs (für Referenzen)
- Label, Barcode, Release-Land
- Verknüpfungen zu Cover Art Archive

#### 🌍 Mehrsprachig

- Original-Titel + Übersetzungen
- Track-Titel in Originalsprache
- Artist-Aliase (z.B. "The Beatles" = "ビートルズ")

---

## MusicBrainz Datenbank

### Daten-Struktur

```
Artist
  ├─► Release-Group (Album-Konzept)
  │     ├─► Release (konkrete Pressung)
  │     │     ├─► Medium (CD 1, CD 2, ...)
  │     │     │     └─► Track 1-14
  │     │     └─► Medium-Format: CD, Vinyl, Digital
  │     └─► Release (andere Pressung, z.B. Japan)
  └─► Artist-Credit (Featured Artists)
```

**Beispiel: "The Wall"**:
```
Artist: Pink Floyd
Release-Group: The Wall (1979)
  ├─► Release 1: The Wall (1979, UK, Harvest)
  │     ├─► Medium 1: CD 1 (Disc-ID: abc123...)
  │     └─► Medium 2: CD 2 (Disc-ID: def456...)
  ├─► Release 2: The Wall (1979, US, Columbia)
  └─► Release 3: The Wall (1994, Remaster, EMI)
```

**Disc-ID** identifiziert **exakt** Medium 1 von Release 1.

### Community-Editing

**Jeder kann beitragen**:
- Neue Releases hinzufügen
- Track-Titel korrigieren
- Cover hochladen
- Disc-IDs hinzufügen

**Qualitätssicherung**:
- Voting-System
- Moderatoren
- Automatische Validierung

---

## Disc-ID Berechnung

### TOC (Table of Contents)

**Was ist TOC?**

- **Sektor-Offsets** jedes Tracks auf der CD
- **Lead-Out** (Ende der CD)
- **Track-Anzahl**

**Beispiel-TOC**:
```
Track 01: Offset 150 (00:02:00)
Track 02: Offset 23456 (05:12:56)
Track 03: Offset 45678 (10:08:78)
...
Track 14: Offset 187234 (41:38:34)
Lead-Out: Offset 212345 (47:12:45)
```

### Disc-ID Formel

**Berechnung** (vereinfacht):

```
1. Track-Offsets + Lead-Out sammeln
2. SHA-1 Hash über:
   - Track-Anzahl
   - Alle Offsets (sortiert)
   - Lead-Out
3. Base64-Encoding (erste 28 Zeichen)
4. URL-Safe Encoding
```

**Resultat**: `wXyz1234AbCd5678_-~` (28 Zeichen)

### cdparanoia TOC-Auslesen

**Command**:
```bash
cdparanoia -d /dev/sr0 -Q 2>&1
```

**Ausgabe**:
```
cdparanoia III release 10.2 (September 11, 2008)

Using cdda library version: 10.2
Using paranoia library version: 10.2
Checking /dev/sr0 for cdrom...

CDROM model sensed: TSSTcorp CDDVDW SH-S223C SB01

Disc mode is CDDA.
Table of Contents (audio tracks only):
track        length               begin        copy pre ch
===========================================================
  1.    23306 [05:10.56]        0 [00:00.00]    no   no  2
  2.    22230 [04:56.30]    23306 [05:10.56]    no   no  2
  3.    19567 [04:20.67]    45536 [10:07.11]    no   no  2
  ...
 14.     9876 [02:11.51]   178358 [39:38.08]    no   no  2
TOTAL  188234 [41:49.59]    (audio only)

The audio CD disc ID is [76118c18/14 150 23456 45678 ... 212345]
```

**Disc-ID**: `76118c18`

### libdiscid (Alternative)

**Installation**:
```bash
sudo apt install libdiscid0 libdiscid-dev
```

**Command**:
```bash
discid /dev/sr0
```

**Ausgabe**:
```
wXyz1234AbCd5678_-~ 14 150 23456 45678 ... 212345 188234
```

**Format**: `{disc_id} {track_count} {offset1} {offset2} ... {lead_out}`

### In disk2iso

**Funktion** (in `lib/lib-cd.sh`):

```bash
get_disc_id() {
    local device="$1"
    local disc_id=""
    
    # Versuch 1: cdparanoia
    local output=$(cdparanoia -d "$device" -Q 2>&1)
    disc_id=$(echo "$output" | grep "disc ID is" | awk '{print $6}' | tr -d '[]/')
    
    # Versuch 2: libdiscid (falls cdparanoia keine ID liefert)
    if [[ -z "$disc_id" ]]; then
        disc_id=$(discid "$device" 2>/dev/null | awk '{print $1}')
    fi
    
    echo "$disc_id"
}
```

---

## API-Abfragen

### Disc-ID Lookup

**Endpunkt**:
```
GET https://musicbrainz.org/ws/2/discid/{disc_id}?fmt=json&inc=artist-credits+recordings
```

**Beispiel-Request**:
```bash
curl -H "User-Agent: disk2iso/1.2.0 (https://github.com/user/disk2iso)" \
     "https://musicbrainz.org/ws/2/discid/76118c18?fmt=json&inc=artist-credits+recordings"
```

**User-Agent**: MusicBrainz verlangt aussagekräftigen User-Agent (sonst 403)

**Response** (vereinfacht):
```json
{
  "id": "76118c18",
  "offset-count": 14,
  "sectors": 188234,
  "releases": [
    {
      "id": "a1b2c3d4-5678-90ab-cdef-1234567890ab",
      "title": "Remember",
      "status": "Official",
      "date": "1999",
      "country": "GB",
      "barcode": "042284967020",
      "artist-credit": [
        {
          "artist": {
            "id": "9z8y7x6w-5v4u-3t2s-1r0q-ponmlkjihgfe",
            "name": "Cat Stevens",
            "sort-name": "Stevens, Cat"
          }
        }
      ],
      "media": [
        {
          "format": "CD",
          "track-count": 24,
          "tracks": [
            {
              "id": "track1-id",
              "position": 1,
              "title": "Morning Has Broken",
              "length": 186000,
              "recording": {
                "id": "recording1-id",
                "title": "Morning Has Broken"
              }
            },
            {
              "position": 2,
              "title": "Can't Keep It In",
              "length": 178000
            }
            // ... weitere Tracks
          ]
        }
      ]
    }
  ]
}
```

### Rate-Limiting

**MusicBrainz API**:
- **Limit**: 1 Request/Sekunde
- **Erlaubt**: Burst von 10 Requests, dann 1/s

**disk2iso Implementierung** (in `lib/lib-cd.sh`):

```bash
musicbrainz_lookup() {
    local disc_id="$1"
    
    # Rate-Limiting: Min. 1 Sekunde seit letztem Request
    local current_time=$(date +%s)
    if [[ -f "$LAST_MUSICBRAINZ_REQUEST" ]]; then
        local last_time=$(cat "$LAST_MUSICBRAINZ_REQUEST")
        local elapsed=$((current_time - last_time))
        if (( elapsed < 1 )); then
            sleep $((1 - elapsed))
        fi
    fi
    echo "$current_time" > "$LAST_MUSICBRAINZ_REQUEST"
    
    # API-Request
    curl -s -H "User-Agent: disk2iso/1.2.0" \
         "https://musicbrainz.org/ws/2/discid/$disc_id?fmt=json&inc=artist-credits+recordings"
}
```

---

## Mehrfach-Treffer

### Warum mehrere Releases?

**Disc-ID kann zu mehreren Releases gehören**:

1. **Verschiedene Länder**: GB, US, Japan-Pressung (gleiche TOC)
2. **Reissues**: Original + Remaster (gleiche TOC)
3. **Compilations**: Verschiedene Compilations mit gleicher Track-Auswahl
4. **Fehlerhafte Einträge**: Community-Duplikate

**Beispiel**:
```
Disc-ID: 76118c18
→ 7 Releases:
  [0] Cat Stevens - Remember (1999, GB)              Score: 100
  [1] Cat Stevens - Remember (1999, AU)              Score: 95
  [2] Cat Stevens - Remember (1999, NZ)              Score: 95
  [3] Various Artists - なつかしの... (2010, JP)      Score: 40
  [4] Zarah Leander - Kann denn... (1997)            Score: 20
```

### Scoring-Algorithmus

**disk2iso berechnet Score** (in `lib/lib-cd.sh`):

```bash
calculate_release_score() {
    local release="$1"
    local score=0
    
    # +50: Track-Anzahl stimmt überein
    if [[ "$track_count" == "$expected_tracks" ]]; then
        score=$((score + 50))
    fi
    
    # +30: Jahr passt (aus disc_label extrahiert)
    if [[ "$release_year" == "$expected_year" ]]; then
        score=$((score + 30))
    fi
    
    # +10: Status "Official" (vs. "Promotional")
    if [[ "$status" == "Official" ]]; then
        score=$((score + 10))
    fi
    
    # +10: Country Match (z.B. "DE" aus LANGUAGE)
    if [[ "$country" == "$preferred_country" ]]; then
        score=$((score + 10))
    fi
    
    echo "$score"
}
```

**Sortierung**: Höchster Score zuerst

### Automatische vs. Manuelle Auswahl

**Automatisch** (keine User-Intervention):
```bash
if [[ ${#releases[@]} -eq 1 ]]; then
    # Nur 1 Release → automatisch verwenden
    process_release "${releases[0]}"
fi
```

**Manuell** (Web-Interface Modal):
```bash
if [[ ${#releases[@]} -gt 1 ]]; then
    # Mehrere Releases → Benutzer-Auswahl
    create_releases_json "$releases"
    update_api_status "waiting_user_input" "MusicBrainz: ${#releases[@]} Alben gefunden"
    wait_for_user_selection 300  # 5 Min Timeout
fi
```

### Web-Interface Modal

**Modal-HTML** (`www/templates/musicbrainz_modal.html`):

```html
<div id="musicbrainz-modal" class="modal">
  <div class="modal-content">
    <h2>Album auswählen (7 Treffer)</h2>
    <div class="releases-grid">
      {{#releases}}
      <div class="release-card" onclick="selectRelease({{index}})">
        <div class="release-info">
          <strong>{{artist}} - {{album}}</strong>
          <div class="release-details">
            <span>{{year}}, {{country}}</span>
            <span>{{track_count}} Tracks</span>
            <span class="score">Score: {{score}}</span>
          </div>
        </div>
      </div>
      {{/releases}}
    </div>
    <button class="btn-secondary" onclick="manualInput()">
      Manuelle Eingabe
    </button>
  </div>
</div>
```

**JavaScript** (`www/static/js/musicbrainz.js`):

```javascript
function selectRelease(index) {
    fetch('/api/musicbrainz/select', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({index: index})
    })
    .then(response => {
        if (response.ok) {
            hideModal();
            showNotification('Album ausgewählt, Ripping wird fortgesetzt...');
        }
    });
}

function manualInput() {
    const artist = prompt('Artist:');
    const album = prompt('Album:');
    const year = prompt('Jahr:');
    
    fetch('/api/musicbrainz/manual', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({artist, album, year})
    })
    .then(() => {
        hideModal();
        showNotification('Manuelle Metadaten gespeichert');
    });
}
```

---

## Cover Art Archive

### Was ist Cover Art Archive?

**Teil von MusicBrainz**:
- Cover-Artwork für Releases
- Community-hochgeladen
- Verschiedene Typen: Front, Back, Booklet, ...
- Verschiedene Größen: 250, 500, 1200 (Original)

**Website**: https://coverartarchive.org

### API

**Endpunkt**:
```
GET http://coverartarchive.org/release/{release_id}/front-500
```

**release_id**: MusicBrainz-Release-ID (aus Disc-ID-Lookup)

**Beispiel**:
```bash
curl -L "http://coverartarchive.org/release/a1b2c3d4-5678-90ab-cdef-1234567890ab/front-500" \
     -o folder.jpg
```

**-L**: Follow redirects (Cover Art Archive leitet um zu Amazon S3)

### Größen

| URL | Größe | Verwendung |
|-----|-------|------------|
| `/front-250` | 250x250 | Thumbnails |
| `/front-500` | 500x500 | **disk2iso Standard** |
| `/front-1200` | 1200x1200 | High-Res |
| `/front` | Original | Oft >3000x3000, große Datei |

### Verfügbarkeit

**Nicht alle Releases haben Cover**:
- Alte/obskure Releases: ~40% Abdeckung
- Mainstream-Releases: ~95% Abdeckung

**Fallback in disk2iso**:

```bash
download_cover() {
    local release_id="$1"
    local output="$2"
    
    # Versuch 1: Cover Art Archive
    if curl -f -L "http://coverartarchive.org/release/$release_id/front-500" -o "$output" 2>/dev/null; then
        log_info "Cover heruntergeladen (500x500)"
        return 0
    fi
    
    # Versuch 2: Kleineres Cover
    if curl -f -L "http://coverartarchive.org/release/$release_id/front-250" -o "$output" 2>/dev/null; then
        log_warning "Cover nur in 250x250 verfügbar"
        return 0
    fi
    
    # Fallback: Kein Cover
    log_warning "Kein Cover verfügbar"
    return 1
}
```

### Embedding in MP3

**eyeD3** bettet Cover in APIC-Frame ein:

```bash
eyeD3 --add-image "$cover_file:FRONT_COVER:image/jpeg" "$mp3_file"
```

**Resultat**: Cover ist direkt in MP3-Datei (kein externes `folder.jpg` nötig für Player)

---

## Troubleshooting

### Fehler: "Disc-ID nicht gefunden"

**Ursache**: CD nicht in MusicBrainz-Datenbank

**Lösung**:
1. **CD-TEXT prüfen** (Fallback aktiviert):
   ```bash
   icedax -J -D /dev/sr0 -g
   ```
2. **Disc-ID manuell hinzufügen**:
   - https://musicbrainz.org/cdtoc/attach
   - Disc-ID eingeben
   - Release suchen und verknüpfen
3. **Manuelle Eingabe** im Web-Interface

### Fehler: "API nicht erreichbar"

**Ursache**: MusicBrainz-Server offline oder Netzwerkproblem

**Prüfung**:
```bash
curl -I https://musicbrainz.org
# Sollte: HTTP/1.1 200 OK
```

**Lösung**:
- Warten (MusicBrainz hat ~99.9% Uptime)
- CD-TEXT Fallback wird automatisch versucht
- Nachträgliche Metadaten-Erfassung später

### Fehler: "Rate limit exceeded"

**Ursache**: Zu viele Requests in kurzer Zeit (>1/s)

**Prüfung**:
```bash
# In Logs
grep "429 Too Many Requests" /opt/disk2iso/log/*.log
```

**Lösung**:
- disk2iso enthält automatisches Rate-Limiting
- Bei manuellen Tests: 1 Sekunde warten zwischen Requests

### Falsche Album-Auswahl

**Problem**: Versehentlich falsches Release gewählt

**Lösung**:
1. **Nachträgliche Korrektur** im Web-Interface:
   - Archiv → Audio-CD → "Add Metadata"
   - Korrekte Auswahl treffen
2. **Manuelle .nfo-Bearbeitung**:
   ```bash
   nano /srv/disk2iso/audio/Artist/Album/album.nfo
   ```

### Keine Cover trotz Release

**Problem**: Release in MusicBrainz, aber kein Cover in Cover Art Archive

**Lösung**:
1. **Cover hochladen** (Community-Beitrag):
   - https://coverartarchive.org/release/{release_id}
   - "Add Cover Art"
2. **Alternatives Cover** manuell:
   ```bash
   wget "https://example.com/cover.jpg" -O /srv/disk2iso/audio/Artist/Album/folder.jpg
   ```

---

## Weiterführende Links

- **[← Zurück: Kapitel 4.4 - Metadaten-System](../04-4_Metadaten.md)**
- **[Kapitel 4.4.2: TMDB-Integration →](04-4-2_TMDB.md)**
- **[Kapitel 4.1: Audio-CD Modul →](../04-1_Audio-CD.md)**
- **MusicBrainz-Website**: https://musicbrainz.org
- **Cover Art Archive**: https://coverartarchive.org
- **API-Dokumentation**: https://musicbrainz.org/doc/MusicBrainz_API

---

**Version:** 1.2.0  
**Letzte Aktualisierung:** 26. Januar 2026
