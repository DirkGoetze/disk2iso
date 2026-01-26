# Kapitel 4.3: Blu-ray-Video Modul (lib-bluray.sh)

Robustes Backup von Blu-ray-Discs mit ddrescue und UDF 2.50+ Support.

## Inhaltsverzeichnis

1. [Übersicht](#übersicht)
2. [Funktionsweise](#funktionsweise)
3. [Verschlüsselung](#verschlüsselung)
4. [Ausgabe-Struktur](#ausgabe-struktur)
5. [Konfiguration](#konfiguration)
6. [Performance](#performance)
7. [Nachträgliche Metadaten](#nachträgliche-metadaten)

---

## Übersicht

### Modul-Aktivierung

**Automatisch aktiviert** wenn folgende Tools installiert sind:

- `ddrescue` - Robustes Kopieren mit Fehlertoleranz
- `isoinfo` - UDF-Label-Erkennung (aus `genisoimage`)
- `blkid` - Fallback für Label-Erkennung

**Prüfung**:
```bash
# Modul-Status
grep "MODULE_BLURAY" /opt/disk2iso/lib/config.sh

# Dependencies prüfen
which ddrescue isoinfo blkid
```

### Features

#### 💿 1:1 Bit-genaue Kopie

- **ddrescue**: Sektor-für-Sektor Kopie mit automatischer Fehlerkorrektur
- **UDF 2.50+**: Moderne Blu-ray-Dateisysteme
- **Große Medien**: Bis 100 GB+ (Dual/Triple-Layer)
- **MD5-Checksummen**: Integritätsprüfung

#### 🔐 Verschlüsselte ISOs

- **AACS/BD+**: ISO enthält verschlüsselte Daten
- **Keine Entschlüsselung**: Nicht in disk2iso implementiert
- **Externe Tools**: MakeMKV, AnyDVD HD für Wiedergabe

#### 🛡️ Robustheit

- **Fehlertoleranz**: ddrescue überspringt defekte Sektoren
- **Retry-Mechanismus**: Mehrfache Versuche pro Sektor
- **Mapfile**: Fortschritt wird gespeichert (bei Abbruch fortsetzbar)
- **Fallback**: dd (schnell, aber ohne Fehlertoleranz)

#### 🎬 TMDB-Metadaten (v1.2.0+)

- **Film-Suche**: Automatisch nach Titel
- **Interaktive Auswahl**: Modal bei mehreren Treffern
- **NFO-Dateien**: Jellyfin/Kodi-kompatibel
- **Poster-Download**: -thumb.jpg (w500)

---

## Funktionsweise

### Ablauf-Diagramm

```
Blu-ray einlegen
    ↓
[lib-diskinfos.sh] is_bluray_video() → true
    ├─► UDF 2.50+ Dateisystem?
    └─► BDMV-Ordner vorhanden?
    ↓
[lib-bluray.sh] copy_bluray_video()
    ├─► get_disc_label() → "ALITA_BATTLE_ANGEL"
    ├─► ensure_bluray_dir() → /bd/
    ├─► get_disc_size() → 48.2 GB
    ├─► copy_with_ddrescue() (primär)
    │   ├─► ddrescue -n -b 2048 /dev/sr0 output.iso mapfile
    │   ├─► Fortschritts-Monitoring (alle 5s)
    │   ├─► Erfolg? → ISO fertig
    │   └─► Fehler? → copy_with_dd() (Fallback)
    ├─► copy_with_dd() (Fallback, nur wenn ddrescue fehlschlägt)
    │   └─► dd if=/dev/sr0 of=output.iso bs=2048
    ├─► create_md5_checksum()
    └─► cleanup_temp()
    ↓
[lib-logging.sh] log_success()
    ↓
[lib-mqtt.sh] publish_mqtt() (falls aktiviert)
```

### Code-Struktur

**Datei**: `lib/lib-bluray.sh` (~300 Zeilen)

#### Haupt-Funktionen

```bash
copy_bluray_video() {
    # Hauptfunktion: Orchestriert Blu-ray-Backup
    local device="$1"
    local output_dir="$2"
    local disc_label="$3"
}

copy_with_ddrescue() {
    # Primäre Methode: Robustes Kopieren
    # ddrescue mit Mapfile
}

copy_with_dd() {
    # Fallback: Schnelles Kopieren
    # dd (keine Fehlertoleranz)
}

get_disc_size() {
    # Disc-Größe via blockdev
    # Return: Bytes
}
```

---

## Verschlüsselung

### AACS (Advanced Access Content System)

**Was ist AACS?**

- **DRM-System** für Blu-rays (ähnlich CSS für DVDs)
- **Volume-ID + Title Keys**: Verschlüsselt auf Disc
- **AACS-Versionen**: v1 (2006) bis v72+ (2024+)

**Problem**: disk2iso kann AACS **nicht** entschlüsseln

**Resultat**: ISO enthält **verschlüsselte** Daten

### Wiedergabe verschlüsselter ISOs

#### Option 1: MakeMKV

**Kostenlos während Beta** (seit 2008):

```bash
# MakeMKV installieren (Ubuntu/Debian)
sudo add-apt-repository ppa:heyarje/makemkv-beta
sudo apt update
sudo apt install makemkv-bin makemkv-oss

# ISO öffnen
makemkvcon mkv iso:/path/to/MOVIE.iso all /output/dir/
```

**Resultat**: Entschlüsselte .mkv-Datei (H.264/H.265 + Audio)

#### Option 2: VLC mit libaacs

**Installation**:
```bash
# libaacs installieren
sudo apt install libaacs0 libbluray-bdj

# KEYDB.cfg herunterladen (Community-Projekt)
mkdir -p ~/.config/aacs/
wget https://vlc-bluray.whoknowsmy.name/files/KEYDB.cfg -O ~/.config/aacs/KEYDB.cfg
```

**VLC öffnen**:
```bash
vlc bluray:///path/to/MOVIE.iso
```

**Einschränkung**: KEYDB.cfg enthält nur ältere Keys (~2015). Neuere Blu-rays funktionieren nicht.

#### Option 3: Kodi + libaacs

Wie VLC, nutzt gleiche KEYDB.cfg.

### BD+ (zusätzliche Verschlüsselung)

**Was ist BD+?**

- **Zusätzliche Schicht** auf manchen Blu-rays
- **VM-basiert**: Code-Entschlüsselung zur Laufzeit
- **Schwerer zu knacken** als AACS

**Unterstützung**:
- ❌ **VLC**: Nein
- ✅ **MakeMKV**: Ja (automatisch)
- ⚠️ **libaacs**: Teilweise (nur ältere Versionen)

### Unverschlüsselte Blu-rays

**Selten**, aber existent:
- Indie-Filme
- Fan-Releases
- Selbst-gebrannte Blu-rays

**Wiedergabe**: Direkt in VLC, Kodi ohne weitere Tools

---

## Ausgabe-Struktur

### Verzeichnis-Layout

```
/srv/disk2iso/bd/
├── ALITA_BATTLE_ANGEL.iso
├── ALITA_BATTLE_ANGEL.md5
├── AVATAR.iso
├── AVATAR.md5
├── BLADE_RUNNER_2049.iso
└── BLADE_RUNNER_2049.md5
```

### ISO-Inhalt

**1:1 Kopie der Blu-ray-Struktur**:

```
BDMV/
├── index.bdmv              # Haupt-Index
├── MovieObject.bdmv        # Java-Objekte für Menü
├── AUXDATA/                # Zusatzdaten
├── BACKUP/                 # Backups von Metadaten
├── BDJO/                   # Java-Objekte
│   └── 00000.bdjo
├── CLIPINF/                # Clip-Informationen
│   ├── 00000.clpi
│   └── ...
├── JAR/                    # Java-Archive (Menüs)
│   └── 00000.jar
├── META/                   # Metadaten
│   └── DL/
│       └── bdmt_eng.xml
├── PLAYLIST/               # Playlists
│   ├── 00000.mpls         # Haupt-Playlist
│   ├── 00001.mpls         # Extras
│   └── ...
└── STREAM/                 # Video/Audio-Streams
    ├── 00000.m2ts         # Haupt-Film (H.264/H.265)
    ├── 00001.m2ts         # Extras
    └── ...

CERTIFICATE/                # AACS-Zertifikate
├── BACKUP/
└── id.bdmv
```

**Größe**: Typisch 25-50 GB (Single/Dual-Layer), bis 100 GB (Triple-Layer)

### Metadaten (v1.2.0+)

**Mit TMDB-Integration**:

```
/srv/disk2iso/bd/
├── BLADE_RUNNER_2049.iso
├── BLADE_RUNNER_2049.md5
├── BLADE_RUNNER_2049.nfo       # Jellyfin-Metadaten
└── BLADE_RUNNER_2049-thumb.jpg # Poster (w500)
```

**BLADE_RUNNER_2049.nfo**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<movie>
  <title>Blade Runner 2049</title>
  <year>2017</year>
  <director>Denis Villeneuve</director>
  <genre>Sci-Fi</genre>
  <genre>Thriller</genre>
  <runtime>164</runtime>
  <rating>8.0</rating>
  <plot>Young Blade Runner K's discovery of a long-buried secret...</plot>
  <tmdbid>335984</tmdbid>
</movie>
```

---

## Konfiguration

### Fest kodierte Einstellungen

**In `lib/lib-bluray.sh`**:

```bash
# Methoden-Reihenfolge (fest)
readonly BLURAY_METHOD_PRIMARY="ddrescue"  # Robust, mit Fehlertoleranz
readonly BLURAY_METHOD_FALLBACK="dd"       # Schnell, ohne Fehlertoleranz

# ddrescue Blockgröße (fest)
readonly DDRESCUE_BLOCK_SIZE=2048          # Blu-ray Sektor-Größe

# Fortschritts-Intervall (fest)
readonly PROGRESS_INTERVAL=5               # Sekunden
```

**Nicht konfigurierbar** ohne Code-Änderung.

### Anpassbare Optionen

**Wenn gewünscht** (Code editieren):

#### ddrescue-Optionen

```bash
# In lib-bluray.sh, Funktion copy_with_ddrescue()
# Zeile ~180

# Original (Standard):
ddrescue -n -b 2048 "$device" "$iso_file" "$mapfile"

# Mit Retries (langsamer, aber robuster):
ddrescue -r 3 -b 2048 "$device" "$iso_file" "$mapfile"
# -r 3: Bis zu 3 Versuche pro Sektor

# Direkter I/O (schneller auf manchen Systemen):
ddrescue -d -n -b 2048 "$device" "$iso_file" "$mapfile"
# -d: Direct I/O (umgeht Kernel-Cache)

# Maximale Fehlertoleranz:
ddrescue -r 5 -R -b 2048 "$device" "$iso_file" "$mapfile"
# -R: Reverse-Pass (liest rückwärts bei Fehlern)
```

#### dd Block-Größe

```bash
# In lib-bluray.sh, Funktion copy_with_dd()
# Zeile ~250

# Original (Standard):
dd if="$device" of="$iso_file" bs=2048 status=progress

# Größere Blöcke (schneller):
dd if="$device" of="$iso_file" bs=1M status=progress
# Achtung: Kann bei Fehlern zu Datenverlust führen!
```

---

## Performance

### Verarbeitungszeiten

**Gemessen** (46.6 GB Blu-ray, ddrescue):

| Phase | Dauer | Geschwindigkeit | Details |
|-------|-------|-----------------|---------|
| Label-Erkennung | 3s | - | isoinfo |
| ddrescue | 39 Min | 20 MB/s | Keine Lesefehler |
| MD5-Checksumme | 3 Min | 260 MB/s | - |
| **Gesamt** | **~42 Min** | **18.5 MB/s** | **Durchschnitt** |

**Mit Lesefehlern** (beschädigte Disc):

| Phase | Dauer | Details |
|-------|-------|---------|
| ddrescue (1. Pass) | 45 Min | Normale Geschwindigkeit |
| ddrescue (Retry defekte Sektoren) | 25 Min | Langsam, viele Retries |
| MD5 | 3 Min | - |
| **Gesamt** | **~73 Min** | **10.6 MB/s durchschnittlich** |

**Fallback mit dd** (ohne Fehlertoleranz):

| Phase | Dauer | Geschwindigkeit |
|-------|-------|-----------------|
| dd | 35 Min | 22 MB/s |
| MD5 | 3 Min | 260 MB/s |
| **Gesamt** | **~38 Min** | **20.5 MB/s** |

### Geschwindigkeits-Faktoren

#### Laufwerk-Geschwindigkeit

**Problem**: Laufwerk zu laut bei maximaler Geschwindigkeit

**Lösung**:
```bash
# Vor Start: Geschwindigkeit begrenzen
sudo hdparm -E 4 /dev/sr0    # 4x Speed (~18 MB/s max für Blu-ray)

# Nach Abschluss: Zurücksetzen
sudo hdparm -E 255 /dev/sr0  # Max Speed
```

**Blu-ray-Geschwindigkeiten**:
- 1x = 4.5 MB/s
- 2x = 9 MB/s
- 4x = 18 MB/s
- 6x = 27 MB/s (typisches Maximum)

#### USB vs. SATA

**Messung**:
- **SATA**: 20-25 MB/s
- **USB 3.0**: 18-22 MB/s
- **USB 2.0**: 8-12 MB/s ← Bottleneck!

**Empfehlung**: USB 3.0 oder SATA-Anschluss

#### Netzwerk-Speicher

**Messung**:
- **Lokal (SSD)**: 22 MB/s
- **NFS (Gigabit)**: 20 MB/s
- **CIFS (Gigabit)**: 18 MB/s
- **CIFS (100 Mbit)**: 11 MB/s ← Bottleneck!

**Empfehlung**: Gigabit-Ethernet oder besser

### Fortschritts-Monitoring

**ddrescue liefert Live-Fortschritt**:

```
# Beispiel-Ausgabe (in Logs)
[INFO] ddrescue: 12.5 GB / 46.6 GB (26%, 20 MB/s, ETA 28:30)
[INFO] ddrescue: 25.0 GB / 46.6 GB (53%, 21 MB/s, ETA 17:05)
[INFO] ddrescue: 37.5 GB / 46.6 GB (80%, 19 MB/s, ETA 07:58)
[SUCCESS] ddrescue: 46.6 GB / 46.6 GB (100%, 20 MB/s)
```

**Technisch** (in `lib-bluray.sh`):
```bash
# Fortschritt aus ddrescue stderr parsen
ddrescue -n -b 2048 "$device" "$iso_file" "$mapfile" 2>&1 | \
    while read -r line; do
        if [[ "$line" =~ rescued:[[:space:]]+([0-9]+) ]]; then
            current_bytes="${BASH_REMATCH[1]}"
            percent=$((current_bytes * 100 / total_bytes))
            log_info "Fortschritt: $percent% ($current_bytes / $total_bytes)"
        fi
    done
```

---

## Nachträgliche Metadaten

Seit Version 1.2.0: TMDB-Metadaten für bereits erstellte Blu-ray-ISOs nachträglich hinzufügen.

### Anwendungsfall

**Situation**: Blu-ray bereits gebackupt, aber ohne TMDB-Metadaten

**Lösung**: "Add Metadata" Button im Web-Interface Archive-Seite

### Ablauf

1. **Web-Interface**: Archiv → Blu-ray ohne Metadaten → "Add Metadata"
2. **Titel-Extraktion**: Aus Dateiname (`BLADE_RUNNER_2049.iso` → "Blade Runner 2049")
3. **TMDB-Suche**: Film-Suche
4. **Auswahl-Modal**: Bei mehreren Treffern
5. **Metadaten erstellen**:
   - NFO-Datei schreiben
   - Poster downloaden
6. **Keine ISO-Änderung**: Nur Zusatzdateien (.nfo, -thumb.jpg)

### Technische Details

**API-Endpunkte**: Identisch zu DVD (siehe Kapitel 4.2)

```
GET  /api/metadata/tmdb/search?query=Blade+Runner+2049&type=movie
POST /api/metadata/tmdb/apply
```

**Beispiel-Request**:
```json
POST /api/metadata/tmdb/apply
{
  "iso_path": "/srv/disk2iso/bd/BLADE_RUNNER_2049.iso",
  "tmdb_id": 335984,
  "type": "movie"
}
```

**Prozess**: Identisch zu DVD-Metadaten (siehe [Kapitel 4.2](04-2_DVD-Video.md#nachträgliche-metadaten))

---

## Weiterführende Links

- **[← Zurück: Kapitel 4.2 - DVD-Video](04-2_DVD-Video.md)**
- **[Kapitel 4.4: Metadaten-Module →](04-4_Metadaten/)**
- **[Kapitel 4.4.2: TMDB-Integration →](04-4_Metadaten/04-4-2_TMDB.md)**
- **[Kapitel 5: Fehlerhandling →](../05_Fehlerhandling.md)**

---

**Version:** 1.2.0  
**Letzte Aktualisierung:** 26. Januar 2026
