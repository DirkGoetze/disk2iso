# Kapitel 4.2: DVD-Video Modul (lib-dvd.sh)

Automatisches Backup von Video-DVDs mit intelligenter Entschlüsselung und Fehler-Tracking.

## Inhaltsverzeichnis

1. [Übersicht](#übersicht)
2. [Funktionsweise](#funktionsweise)
3. [Entschlüsselung](#entschlüsselung)
4. [Fehler-Tracking](#fehler-tracking)
5. [Ausgabe-Struktur](#ausgabe-struktur)
6. [Konfiguration](#konfiguration)
7. [Performance](#performance)
8. [Nachträgliche Metadaten](#nachträgliche-metadaten)

---

## Übersicht

### Modul-Aktivierung

**Automatisch aktiviert** wenn folgende Tools installiert sind:
- `dvdbackup` - DVD-Entschlüsselung und Backup
- `libdvdcss2` - CSS-Entschlüsselung (erforderlich)
- `genisoimage` - ISO-Erstellung
- `ddrescue` - Fallback für beschädigte DVDs

**Prüfung**:
```bash
# Modul-Status
grep "MODULE_VIDEO_DVD" /opt/disk2iso/lib/config.sh

# Dependencies prüfen
which dvdbackup genisoimage ddrescue
ldconfig -p | grep libdvdcss
```

### Features

#### 📀 Entschlüsselte Backups
- **CSS-Entschlüsselung**: Automatisch via libdvdcss2
- **VIDEO_TS Struktur**: Saubere DVD-Struktur in ISO
- **Alle Features**: Menüs, Extras, Multi-Audio, Untertitel
- **Direkte Wiedergabe**: VLC, Kodi, Jellyfin ohne weitere Tools

#### 🔄 Intelligentes Fehler-Tracking
- **3-Stufen-System**: dvdbackup → ddrescue → reject
- **Persistente Liste**: `.failed_dvds` (max. 2 Versuche)
- **Automatischer Reject**: Nach 2 Fehlversuchen
- **Detaillierte Logs**: Fehlerursache pro DVD

#### 🎬 TMDB-Metadaten (v1.2.0+)
- **Film-Suche**: Automatisch nach Titel
- **TV-Serien**: Erkennung von Staffel/Disc-Nummer
- **Interaktive Auswahl**: Modal bei mehreren Treffern
- **NFO-Dateien**: Jellyfin/Kodi-kompatibel
- **Poster-Download**: -thumb.jpg (w500)

#### 🛡️ Robustheit
- **Retry-Mechanismus**: dvdbackup fehlgeschlagen → ddrescue versuchen
- **ddrescue**: Sektor-für-Sektor mit Fehlertoleranz
- **Checksummen**: MD5 für jede ISO
- **Cleanup**: Automatisches Temp-Verzeichnis löschen

---

## Funktionsweise

### Ablauf-Diagramm

```
Video-DVD einlegen
    ↓
[lib-diskinfos.sh] is_video_dvd() → true
    ↓
[lib-dvd.sh] check_failed_list()
    ├─► Disc in .failed_dvds? → Anzahl < 2?
    │   ├─► Ja: Retry erlauben
    │   └─► Nein: Reject (log + eject)
    ↓
[lib-dvd.sh] copy_video_dvd()
    ├─► get_disc_label() → "THE_MATRIX"
    ├─► ensure_dvd_dir() → /dvd/
    ├─► copy_with_dvdbackup() (Versuch 1)
    │   ├─► dvdbackup -M -i /dev/sr0 -o /tmp
    │   ├─► Erfolg? → genisoimage → ISO
    │   └─► Fehler? → Weiter zu Versuch 2
    ├─► copy_with_ddrescue() (Versuch 2, falls dvdbackup fehlschlug)
    │   ├─► ddrescue /dev/sr0 /tmp/dvd.iso
    │   ├─► Erfolg? → ISO fertig
    │   └─► Fehler? → Weiter zu Reject
    ├─► update_failed_list() (bei Fehler)
    │   ├─► Count < 2: Eintrag aktualisieren
    │   └─► Count = 2: Reject-Eintrag schreiben
    ├─► create_md5_checksum()
    └─► cleanup_temp()
    ↓
[lib-logging.sh] log_success() oder log_error()
    ↓
[lib-mqtt.sh] publish_mqtt() (falls aktiviert)
```

### Code-Struktur

**Datei**: `lib/lib-dvd.sh` (~600 Zeilen)

#### Haupt-Funktionen

```bash
copy_video_dvd() {
    # Hauptfunktion: Orchestriert DVD-Backup
    local device="$1"
    local output_dir="$2"
    local disc_label="$3"
}

copy_with_dvdbackup() {
    # Primäre Methode: Entschlüsseltes Backup
    # dvdbackup → genisoimage
}

copy_with_ddrescue() {
    # Fallback: Robustes Kopieren bei Lesefehlern
    # ddrescue (sektor-weise)
}

check_failed_list() {
    # Prüft .failed_dvds auf vorherige Fehler
    # Return: 0 = erlaubt, 1 = reject
}

update_failed_list() {
    # Aktualisiert .failed_dvds nach Fehler
}
```

---

## Entschlüsselung

### CSS (Content Scramble System)

**Problem**: Die meisten kommerziellen DVDs sind mit CSS verschlüsselt.

**Lösung**: libdvdcss2

#### libdvdcss2 Installation

**Debian/Ubuntu**:
```bash
# Repository hinzufügen (falls nicht vorhanden)
sudo apt install software-properties-common
sudo add-apt-repository ppa:videolan/master-daily
sudo apt update

# libdvdcss2 installieren
sudo apt install libdvd-pkg
sudo dpkg-reconfigure libdvd-pkg
```

**Debian 12 (direkt)**:
```bash
# Aus Debian Multimedia Repository
sudo apt install libdvdcss2
```

**Prüfung**:
```bash
ldconfig -p | grep libdvdcss
# Sollte zeigen: libdvdcss.so.2 => /usr/lib/x86_64-linux-gnu/libdvdcss.so.2
```

### dvdbackup mit libdvdcss2

**Funktionsweise**:
```bash
# dvdbackup nutzt libdvdcss2 automatisch
dvdbackup -M -i /dev/sr0 -o /tmp/dvd

# Optionen:
# -M : Mirror mode (komplette DVD)
# -i : Input device
# -o : Output directory
```

**Prozess**:
1. **libdvdcss2** liest Title Key von DVD
2. **Entschlüsselung** im laufenden Betrieb
3. **Ausgabe**: VIDEO_TS-Ordner mit entschlüsselten .VOB-Dateien
4. **genisoimage**: VIDEO_TS → ISO-Image

**Resultat**: ISO enthält **entschlüsselte** Daten → direkt abspielbar in VLC, Kodi, etc.

### Regionale Codes

**Problem**: DVD-Laufwerk hat Region-Code (z.B. Region 2 für Europa)

**Lösung**: libdvdcss2 umgeht Region-Codes in Software

**Warnung**: Laufwerk hat nur **5 Region-Änderungen** verfügbar. Danach fix!

```bash
# Region prüfen
regionset /dev/sr0

# Region ändern (max 5x!)
sudo regionset /dev/sr0 2  # Region 2 (Europa)
```

**Empfehlung**: RPC-1 Firmware für Laufwerk (keine Region-Sperre) oder Software-Player nutzen.

---

## Fehler-Tracking

### .failed_dvds Format

**Datei**: `/srv/disk2iso/.failed_dvds`

**Format**: `DISC_LABEL:count:timestamp`

**Beispiel**:
```
THE_MATRIX_SCRATCHED:1:2026-01-15_10-30-22
INCEPTION:2:2026-01-16_14-45-10
AVATAR_DAMAGED:1:2026-01-17_09-12-33
```

### Logik

#### Versuch 1: Frische DVD

```
Disc: THE_MATRIX_SCRATCHED
→ Nicht in .failed_dvds
→ Versuch mit dvdbackup
→ Fehler: Lesefehler bei Sektor 123456
→ Versuch mit ddrescue
→ Fehler: Zu viele defekte Sektoren
→ Eintrag in .failed_dvds: THE_MATRIX_SCRATCHED:1:2026-01-15_10-30-22
→ DVD auswerfen
```

**Log**:
```
[INFO] Disc-Typ: dvd-video
[INFO] Label: THE_MATRIX_SCRATCHED
[INFO] Nicht in Failed-Liste, Versuch 1
[INFO] dvdbackup: Start...
[ERROR] dvdbackup: Lesefehler bei Titel 1
[WARNING] Fallback zu ddrescue...
[INFO] ddrescue: Start (Sektor 0 - 3750000)
[ERROR] ddrescue: 512 defekte Sektoren
[ERROR] DVD-Backup fehlgeschlagen
[INFO] Failed-Liste: THE_MATRIX_SCRATCHED:1
[INFO] DVD ausgeworfen, bitte erneut versuchen
```

#### Versuch 2: Retry

**Am nächsten Tag**: DVD erneut einlegen (nach Reinigung)

```
Disc: THE_MATRIX_SCRATCHED
→ In .failed_dvds mit count=1
→ Log: "Retry-Versuch (2/2)"
→ Versuch mit dvdbackup
→ Erfolg!
→ Eintrag aus .failed_dvds entfernen
→ ISO erstellt
```

**Log**:
```
[INFO] Disc-Typ: dvd-video
[INFO] Label: THE_MATRIX_SCRATCHED
[WARNING] DVD bereits 1x fehlgeschlagen, Retry-Versuch (2/2)
[INFO] dvdbackup: Start...
[SUCCESS] dvdbackup: Alle Titel erfolgreich
[INFO] genisoimage: Erstelle ISO...
[SUCCESS] ISO: /srv/disk2iso/dvd/THE_MATRIX_SCRATCHED.iso (7.2 GB)
[INFO] Entferne aus Failed-Liste (Erfolg)
```

#### Versuch 3: Reject

**Wenn Versuch 2 auch fehlschlägt:**

```
Disc: THE_MATRIX_SCRATCHED
→ In .failed_dvds mit count=1
→ Versuch 2 fehlgeschlagen
→ Eintrag aktualisieren: count=2
→ DVD ab jetzt rejected
```

**Log**:
```
[INFO] Disc-Typ: dvd-video
[INFO] Label: THE_MATRIX_SCRATCHED
[WARNING] DVD bereits 1x fehlgeschlagen, Retry-Versuch (2/2)
[INFO] dvdbackup: Start...
[ERROR] dvdbackup: Lesefehler bei Titel 1
[WARNING] Fallback zu ddrescue...
[ERROR] ddrescue: 512 defekte Sektoren
[ERROR] DVD-Backup fehlgeschlagen (Versuch 2/2)
[WARNING] DVD nach 2 Fehlversuchen als defekt markiert
[INFO] Failed-Liste: THE_MATRIX_SCRATCHED:2
[INFO] DVD wird ab jetzt automatisch ausgeworfen
```

**Bei erneutem Einlegen** (Versuch 3+):
```
[INFO] Disc-Typ: dvd-video
[INFO] Label: THE_MATRIX_SCRATCHED
[ERROR] DVD in Failed-Liste mit 2 Fehlversuchen
[ERROR] DVD als defekt markiert, Backup abgelehnt
[INFO] DVD automatisch ausgeworfen
```

### Manuelle Verwaltung

#### Failed-Liste ansehen

```bash
cat /srv/disk2iso/.failed_dvds
```

#### DVD aus Liste entfernen

**Nach DVD-Reparatur** (z.B. professionelle Reinigung):

```bash
# Zeile mit DVD-Label entfernen
sudo nano /srv/disk2iso/.failed_dvds
# Oder:
sed -i '/THE_MATRIX_SCRATCHED/d' /srv/disk2iso/.failed_dvds
```

#### Komplett zurücksetzen

```bash
# Alle Einträge löschen
sudo rm /srv/disk2iso/.failed_dvds

# Service neu starten
sudo systemctl restart disk2iso
```

---

## Ausgabe-Struktur

### Verzeichnis-Layout

```
/srv/disk2iso/dvd/
├── THE_MATRIX.iso
├── THE_MATRIX.md5
├── INCEPTION.iso
├── INCEPTION.md5
├── AVATAR.iso
└── AVATAR.md5
```

### ISO-Inhalt

**Entschlüsselte VIDEO_TS-Struktur**:

```
VIDEO_TS/
├── VIDEO_TS.IFO           # DVD-Informationen
├── VIDEO_TS.VOB           # Menü-Video (oft 0 Bytes)
├── VIDEO_TS.BUP           # Backup von .IFO
├── VTS_01_0.IFO           # Titel 1 Informationen
├── VTS_01_0.BUP           # Backup
├── VTS_01_1.VOB           # Titel 1 Video (Teil 1, max 1 GB)
├── VTS_01_2.VOB           # Titel 1 Video (Teil 2)
├── VTS_01_3.VOB           # ...
├── VTS_02_0.IFO           # Titel 2 (z.B. Extras)
└── VTS_02_1.VOB
```

**Größe**: Typisch 4-8 GB (Dual-Layer bis 8.5 GB)

### Metadaten (v1.2.0+)

**Mit TMDB-Integration**:

```
/srv/disk2iso/dvd/
├── INCEPTION.iso
├── INCEPTION.md5
├── INCEPTION.nfo           # Jellyfin-Metadaten
└── INCEPTION-thumb.jpg     # Poster (w500)
```

**INCEPTION.nfo**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<movie>
  <title>Inception</title>
  <year>2010</year>
  <director>Christopher Nolan</director>
  <genre>Action</genre>
  <genre>Sci-Fi</genre>
  <genre>Thriller</genre>
  <runtime>148</runtime>
  <rating>8.8</rating>
  <plot>A thief who steals corporate secrets through...</plot>
  <tmdbid>27205</tmdbid>
</movie>
```

---

## Konfiguration

### Fest kodierte Einstellungen

**In `lib/lib-dvd.sh`**:

```bash
# Methoden-Reihenfolge (fest)
readonly DVD_METHOD_PRIMARY="dvdbackup"    # Entschlüsselt
readonly DVD_METHOD_FALLBACK="ddrescue"    # Verschlüsselt, robust
readonly DVD_METHOD_LAST="dd"              # Verschlüsselt, schnell

# Fehler-Tracking (fest)
readonly MAX_RETRY_COUNT=2                 # Max. 2 Versuche

# Temp-Verzeichnis (fest)
readonly DVD_TEMP_DIR="$OUTPUT_DIR/.temp"
```

**Nicht konfigurierbar** ohne Code-Änderung.

### Anpassbare Optionen

**Wenn gewünscht** (Code editieren):

#### ddrescue-Optionen

```bash
# In lib-dvd.sh, Funktion copy_with_ddrescue()
# Zeile ~350

# Original (Standard):
ddrescue -n -b 2048 /dev/sr0 "$iso_file" "$mapfile"

# Mehr Retries (langsamer, aber robuster):
ddrescue -r 3 -b 2048 /dev/sr0 "$iso_file" "$mapfile"

# Direkter I/O (schneller auf manchen Systemen):
ddrescue -d -n -b 2048 /dev/sr0 "$iso_file" "$mapfile"
```

#### Max Retry erhöhen

```bash
# In lib-dvd.sh, Zeile ~40
# Von 2 auf 3 ändern:
readonly MAX_RETRY_COUNT=3
```

**Achtung**: Mehr Versuche = mehr Zeit bei defekten DVDs.

---

## Performance

### Verarbeitungszeiten

**Gemessen** (7.5 GB DVD):

| Phase | Dauer | Methode | Details |
|-------|-------|---------|---------|
| Label-Erkennung | 3s | isoinfo | - |
| dvdbackup | 28 Min | CSS entschlüsseln | 4.5 MB/s durchschnittlich |
| genisoimage | 3 Min | VIDEO_TS → ISO | - |
| MD5-Checksumme | 2 Min | md5sum | 60 MB/s |
| **Gesamt** | **~33 Min** | **Entschlüsselt** | **3.8 MB/s** |

**Fallback** (mit ddrescue, verschlüsselt):

| Phase | Dauer | Details |
|-------|-------|---------|
| ddrescue | 65 Min | 2 MB/s (langsamer wegen Fehlertoleranz) |
| MD5 | 2 Min | - |
| **Gesamt** | **~67 Min** | **1.9 MB/s** |

### Geschwindigkeits-Faktoren

#### Laufwerk-Geschwindigkeit

**Problem**: DVD-Laufwerk zu laut

**Lösung**:
```bash
# Vor Start: Geschwindigkeit begrenzen
sudo hdparm -E 8 /dev/sr0    # 8x Speed (~10.5 MB/s max)

# Nach Abschluss: Zurücksetzen
sudo hdparm -E 255 /dev/sr0  # Max Speed
```

**Trade-off**: 8x statt 16x = doppelte Zeit, aber leiser

#### Netzwerk-Speicher

**Problem**: Ausgabe auf NFS/CIFS → langsamer

**Messung**:
- **Lokal (SSD)**: 4.5 MB/s
- **NFS (Gigabit)**: 3.8 MB/s
- **CIFS (100 Mbit)**: 1.2 MB/s ← Bottleneck!

**Empfehlung**: Gigabit-Ethernet für NAS

---

## Nachträgliche Metadaten

Seit Version 1.2.0: TMDB-Metadaten für bereits erstellte DVD-ISOs nachträglich hinzufügen.

### Anwendungsfall

**Situation**: DVD bereits gebackupt, aber ohne TMDB-Metadaten (z.B. TMDB-Modul war damals deaktiviert)

**Lösung**: "Add Metadata" Button im Web-Interface Archive-Seite

### Ablauf

1. **Web-Interface**: Archiv → DVD ohne Metadaten → "Add Metadata"
2. **Titel-Extraktion**: Aus Dateiname (`INCEPTION.iso` → Suche nach "Inception")
3. **TMDB-Suche**: Film- oder TV-Serien-Suche
4. **Auswahl-Modal**: Bei mehreren Treffern (z.B. "Inception" findet 5 Filme)
5. **Metadaten erstellen**:
   - NFO-Datei schreiben
   - Poster downloaden
6. **Keine ISO-Änderung**: Nur Zusatzdateien (.nfo, -thumb.jpg)

### Technische Details

**API-Endpunkte**:
```
GET  /api/metadata/tmdb/search?query=Inception&type=movie
POST /api/metadata/tmdb/apply
```

**Beispiel-Request**:
```json
POST /api/metadata/tmdb/apply
{
  "iso_path": "/srv/disk2iso/dvd/INCEPTION.iso",
  "tmdb_id": 27205,
  "type": "movie"
}
```

**Prozess** (in `lib-dvd-metadata.sh`):
```bash
add_tmdb_metadata() {
    local iso_path="$1"
    local tmdb_id="$2"
    
    # TMDB-API abfragen
    movie_data=$(curl -s "https://api.themoviedb.org/3/movie/$tmdb_id?api_key=$TMDB_API_KEY")
    
    # NFO erstellen
    create_movie_nfo "$movie_data" "${iso_path%.iso}.nfo"
    
    # Poster downloaden
    poster_url=$(echo "$movie_data" | jq -r '.poster_path')
    curl -s "https://image.tmdb.org/t/p/w500$poster_url" -o "${iso_path%.iso}-thumb.jpg"
}
```

---

## Weiterführende Links

- **[← Zurück: Kapitel 4.1 - Audio-CD](04-1_Audio-CD.md)**
- **[Kapitel 4.3: Blu-ray-Video →](04-3_BD-Video.md)**
- **[Kapitel 4.4.2: TMDB-Integration →](04-4_Metadaten/04-4-2_TMDB.md)**
- **[Kapitel 5: Fehlerhandling →](../05_Fehlerhandling.md)**

---

**Version:** 1.2.0  
**Letzte Aktualisierung:** 26. Januar 2026
