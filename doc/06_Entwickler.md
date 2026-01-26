# Kapitel 6: Entwickler-Dokumentation

Technische Dokumentation für Entwickler, die disk2iso erweitern oder anpassen möchten.

## Inhaltsverzeichnis

1. [Architektur-Übersicht](#architektur-übersicht)
2. [State Machine](#state-machine)
3. [Modul-System](#modul-system)
4. [Sprachsystem](#sprachsystem)
5. [REST API](#rest-api)
6. [Web-Interface](#web-interface)
7. [Neue Module entwickeln](#neue-module-entwickeln)
8. [Coding-Standards](#coding-standards)
9. [Testing](#testing)
10. [Debugging](#debugging)

---

## Architektur-Übersicht

### Komponenten-Diagramm

```
disk2iso.sh (Orchestrator + State Machine)
    │
    ├─► Kern-Module (immer geladen)
    │   ├─► lib-common.sh        (Basis-Funktionen, Daten-Discs)
    │   ├─► lib-logging.sh       (Logging + Sprachsystem)
    │   ├─► lib-api.sh           (JSON REST API)
    │   ├─► lib-files.sh         (Dateinamen-Verwaltung)
    │   ├─► lib-folders.sh       (Ordner-Verwaltung)
    │   ├─► lib-diskinfos.sh     (Disc-Typ-Erkennung)
    │   ├─► lib-drivestat.sh     (Laufwerk-Status)
    │   ├─► lib-systeminfo.sh    (System-Informationen)
    │   └─► lib-tools.sh         (Abhängigkeiten-Prüfung)
    │
    └─► Optionale Module (konditional geladen)
        ├─► lib-cd.sh            (Audio-CD)
        ├─► lib-dvd.sh           (Video-DVD)
        ├─► lib-bluray.sh        (Blu-ray)
        └─► lib-mqtt.sh          (MQTT/Home Assistant)
```

### Verantwortlichkeiten

| Komponente | Verantwortung | Zeilen | Komplexität |
|------------|---------------|--------|-------------|
| **disk2iso.sh** | State Machine, Hauptschleife, Disc-Überwachung | ~400 | Hoch |
| **lib-logging.sh** | Logging, Sprachsystem, Farben | ~150 | Niedrig |
| **lib-api.sh** | JSON REST API (status, archive, logs, config) | ~300 | Mittel |
| **lib-diskinfos.sh** | Disc-Typ-Erkennung (6 Typen) | ~250 | Mittel |
| **lib-drivestat.sh** | Laufwerk-Status (media, nodisc, tray_open) | ~100 | Niedrig |
| **lib-common.sh** | Daten-Disc-Kopie (dd, ddrescue) | ~200 | Mittel |
| **lib-files.sh** | Datei-/Ordnernamen, Sanitize | ~120 | Niedrig |
| **lib-folders.sh** | Verzeichnis-Erstellung (lazy) | ~80 | Niedrig |
| **lib-tools.sh** | Abhängigkeiten prüfen | ~100 | Niedrig |
| **lib-cd.sh** | Audio-CD Ripping (siehe Kapitel 4.1) | ~800 | Hoch |
| **lib-dvd.sh** | Video-DVD Backup (siehe Kapitel 4.2) | ~600 | Hoch |
| **lib-bluray.sh** | Blu-ray Backup (siehe Kapitel 4.3) | ~300 | Mittel |
| **lib-mqtt.sh** | MQTT-Publishing (siehe Kapitel 4.5) | ~400 | Mittel |

### Datenfluss

```
Disc einlegen
    ↓
[lib-drivestat.sh] get_drive_status() → "media"
    ↓
[lib-diskinfos.sh] get_disc_type() → "dvd-video"
    ↓
[lib-diskinfos.sh] get_disc_label() → "THE_MATRIX"
    ↓
[disk2iso.sh] Modul-Auswahl: lib-dvd.sh
    ↓
[lib-dvd.sh] copy_video_dvd()
    ├─► [lib-folders.sh] ensure_dvd_dir()
    ├─► [lib-files.sh] sanitize_filename()
    ├─► dvdbackup (extern)
    ├─► genisoimage (extern)
    ├─► [lib-common.sh] create_md5_checksum()
    └─► [lib-api.sh] update_api_progress()
    ↓
[lib-logging.sh] log_success()
    ↓
[lib-mqtt.sh] publish_mqtt() (falls aktiviert)
    ↓
[lib-drivestat.sh] eject_disc()
```

---

## State Machine

### Zustands-Definitionen

```bash
# In disk2iso.sh (Zeile ~30-40)
readonly STATE_INITIALIZING="initializing"
readonly STATE_WAITING_FOR_DRIVE="waiting_for_drive"
readonly STATE_DRIVE_DETECTED="drive_detected"
readonly STATE_WAITING_FOR_MEDIA="waiting_for_media"
readonly STATE_MEDIA_DETECTED="media_detected"
readonly STATE_ANALYZING="analyzing"
readonly STATE_COPYING="copying"
readonly STATE_COMPLETED="completed"
readonly STATE_ERROR="error"
readonly STATE_WAITING_FOR_REMOVAL="waiting_for_removal"
readonly STATE_IDLE="idle"
```

### Transition-Funktion

```bash
transition_to_state() {
    local new_state="$1"
    local reason="${2:-}"
    
    # Logging
    log_message "State: $CURRENT_STATE → $new_state${reason:+ ($reason)}"
    
    # State aktualisieren
    CURRENT_STATE="$new_state"
    
    # API-Status aktualisieren (für Web-Interface)
    update_api_state "$new_state" "$reason"
    
    # MQTT-Publishing (falls aktiviert)
    if [[ "$MQTT_ENABLED" == "true" ]]; then
        publish_mqtt_state "$new_state"
    fi
}
```

### Hauptschleife

```bash
# In disk2iso.sh (vereinfacht)
while true; do
    case "$CURRENT_STATE" in
        "$STATE_INITIALIZING")
            initialize_system
            transition_to_state "$STATE_WAITING_FOR_DRIVE"
            ;;
            
        "$STATE_WAITING_FOR_DRIVE")
            if check_drive_exists "$CDROM_DEVICE"; then
                transition_to_state "$STATE_DRIVE_DETECTED"
            fi
            sleep "$POLL_DRIVE_INTERVAL"
            ;;
            
        "$STATE_WAITING_FOR_MEDIA")
            if check_media_inserted "$CDROM_DEVICE"; then
                transition_to_state "$STATE_MEDIA_DETECTED"
            fi
            sleep "$POLL_MEDIA_INTERVAL"
            ;;
            
        "$STATE_ANALYZING")
            DISC_TYPE=$(get_disc_type "$CDROM_DEVICE")
            DISC_LABEL=$(get_disc_label "$CDROM_DEVICE")
            transition_to_state "$STATE_COPYING"
            ;;
            
        "$STATE_COPYING")
            if copy_disc "$CDROM_DEVICE" "$OUTPUT_DIR"; then
                transition_to_state "$STATE_COMPLETED"
            else
                transition_to_state "$STATE_ERROR"
            fi
            ;;
            
        "$STATE_COMPLETED"|"$STATE_ERROR")
            transition_to_state "$STATE_WAITING_FOR_REMOVAL"
            ;;
            
        "$STATE_WAITING_FOR_REMOVAL")
            if ! check_media_inserted "$CDROM_DEVICE"; then
                transition_to_state "$STATE_IDLE"
            fi
            sleep "$POLL_REMOVAL_INTERVAL"
            ;;
            
        "$STATE_IDLE")
            transition_to_state "$STATE_WAITING_FOR_MEDIA"
            ;;
    esac
done
```

---

## Modul-System

### Modul-Template

```bash
#!/bin/bash
# lib-example.sh - Example Module
# Version: 1.0.0

# =====================================================
# GLOBALE VARIABLEN
# =====================================================

EXAMPLE_MODULE_VERSION="1.0.0"

# Abhängigkeiten (für check_dependencies)
EXAMPLE_REQUIRED_TOOLS=(
    "tool1"
    "tool2"
)

# =====================================================
# HAUPT-FUNKTION
# =====================================================

copy_example_media() {
    local device="$1"
    local output_dir="$2"
    local disc_label="$3"
    
    log_info "$(get_text 'example.start')"
    
    # Validierung
    if [[ ! -b "$device" ]]; then
        log_error "$(get_text 'example.invalid_device' "$device")"
        return 1
    fi
    
    # Verzeichnis sicherstellen
    ensure_example_dir
    
    # Kopiervorgang
    local output_file="$output_dir/example/${disc_label}.ext"
    
    if ! example_copy_method "$device" "$output_file"; then
        log_error "$(get_text 'example.copy_failed')"
        return 1
    fi
    
    # Checksumme
    create_md5_checksum "$output_file"
    
    log_success "$(get_text 'example.complete' "$output_file")"
    return 0
}

# =====================================================
# HILFSFUNKTIONEN
# =====================================================

example_copy_method() {
    local device="$1"
    local output="$2"
    
    # Implementierung...
    return 0
}

ensure_example_dir() {
    mkdir -p "$OUTPUT_DIR/example"
}
```

### Modul-Integration

**1. In disk2iso.sh (Zeile ~150):**

```bash
# Modul laden (konditional)
if [[ "$MODULE_EXAMPLE" == "true" ]]; then
    source "$SCRIPT_DIR/disk2iso-lib/lib-example.sh"
fi
```

**2. Disc-Typ-Erkennung (lib-diskinfos.sh):**

```bash
is_example_media() {
    local device="$1"
    # Erkennungs-Logik
    return 0  # true
}

get_disc_type() {
    # ...
    if is_example_media "$device"; then
        echo "example-media"
        return 0
    fi
    # ...
}
```

**3. Case-Switch (disk2iso.sh, Zeile ~200):**

```bash
case "$DISC_TYPE" in
    example-media)
        if [[ "$MODULE_EXAMPLE" == "true" ]]; then
            copy_example_media "$CDROM_DEVICE" "$OUTPUT_DIR" "$DISC_LABEL"
        else
            copy_data_disc "$CDROM_DEVICE" "$OUTPUT_DIR"
        fi
        ;;
esac
```

---

## Sprachsystem

### Struktur

```
disk2iso-lib/lang/
├── lib-common.de       # Kern-Module
├── lib-common.en
├── lib-cd.de           # Audio-CD Modul
├── lib-cd.en
├── lib-dvd.de          # Video-DVD Modul
├── lib-dvd.en
└── lib-web.de          # Web-Interface
    lib-web.en
```

### Format

**Datei:** `disk2iso-lib/lang/lib-cd.de`

```bash
# Audio-CD Modul (Deutsch)
cd.start="Starte Audio-CD Ripping..."
cd.discid="Disc-ID: %s"
cd.musicbrainz_found="MusicBrainz: %s - %s (%s)"
cd.track_progress="Track %d/%d: %s"
cd.encoding="Encoding zu MP3 (VBR V%d)..."
cd.complete="Audio-CD abgeschlossen: %d Tracks, %s"
```

### get_text() Funktion

**Implementierung (lib-logging.sh):**

```bash
get_text() {
    local key="$1"
    shift
    local args=("$@")
    
    # Modul aus Key extrahieren (z.B. "cd.start" → "cd")
    local module="${key%%.*}"
    
    # Sprachdatei bestimmen
    local lang_file="$SCRIPT_DIR/disk2iso-lib/lang/lib-${module}.${LANGUAGE}"
    
    # Fallback zu English
    if [[ ! -f "$lang_file" ]]; then
        lang_file="$SCRIPT_DIR/disk2iso-lib/lang/lib-${module}.en"
    fi
    
    # Text aus Datei lesen
    local text=$(grep "^${key}=" "$lang_file" | cut -d'=' -f2- | sed 's/^"//;s/"$//')
    
    # Platzhalter ersetzen (printf-Syntax)
    if [[ ${#args[@]} -gt 0 ]]; then
        # shellcheck disable=SC2059
        printf "$text" "${args[@]}"
    else
        echo "$text"
    fi
}
```

### Verwendung

```bash
# Einfache Nachricht
log_info "$(get_text 'cd.start')"

# Mit Platzhaltern
log_info "$(get_text 'cd.discid' "$discid")"
log_info "$(get_text 'cd.musicbrainz_found' "$artist" "$album" "$year")"
log_info "$(get_text 'cd.track_progress' 5 14 "Track Title")"
```

### Neue Sprache hinzufügen

**1. Dateien erstellen:**
```bash
cp disk2iso-lib/lang/lib-cd.en disk2iso-lib/lang/lib-cd.fr
cp disk2iso-lib/lang/lib-dvd.en disk2iso-lib/lang/lib-dvd.fr
# ...
```

**2. Übersetzen:**
```bash
# lib-cd.fr
cd.start="Démarrage de l'extraction du CD audio..."
cd.musicbrainz_found="MusicBrainz: %s - %s (%s)"
# ...
```

**3. Konfiguration:**
```bash
# config.sh
readonly LANGUAGE="fr"
```

---

## REST API

### Endpunkt-Implementierung

**Datei:** `lib/lib-api.sh`

```bash
update_api_status() {
    local state="$1"
    local disc_type="$2"
    local disc_label="$3"
    
    # JSON erstellen
    cat > "$API_DIR/status.json" <<EOF
{
  "state": "$state",
  "disc_type": "$disc_type",
  "disc_label": "$disc_label",
  "progress": $(get_progress_json),
  "drive": "$CDROM_DEVICE",
  "output_dir": "$OUTPUT_DIR",
  "timestamp": "$(date -Iseconds)"
}
EOF
}

get_progress_json() {
    if [[ -f "$PROGRESS_FILE" ]]; then
        cat "$PROGRESS_FILE"
    else
        echo '{"percent": 0, "current_mb": 0, "total_mb": 0}'
    fi
}
```

### Flask-Backend

**Datei:** `www/app.py`

```python
from flask import Flask, jsonify
import json
import os

app = Flask(__name__)
API_DIR = "/opt/disk2iso/api"

@app.route('/api/status')
def get_status():
    """Aktueller Systemstatus"""
    status_file = os.path.join(API_DIR, 'status.json')
    
    if os.path.exists(status_file):
        with open(status_file, 'r') as f:
            return jsonify(json.load(f))
    
    return jsonify({"state": "unknown"}), 503

@app.route('/api/archive')
def get_archive():
    """Liste aller ISOs"""
    archive_file = os.path.join(API_DIR, 'archive.json')
    
    if os.path.exists(archive_file):
        with open(archive_file, 'r') as f:
            return jsonify(json.load(f))
    
    return jsonify({"audio": [], "dvd": [], "bd": [], "data": []})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

---

## Web-Interface

### Frontend-Architektur

```
www/
├── app.py                    # Flask-Backend
├── templates/
│   ├── base.html            # Layout + Navigation
│   ├── index.html           # Home (Status)
│   ├── archive.html         # Archive-Liste
│   ├── logs.html            # Logs
│   ├── config.html          # Konfiguration
│   ├── system.html          # System-Info
│   └── help.html            # Hilfe
├── static/
│   ├── css/
│   │   └── style.css        # Styling
│   └── js/
│       ├── index.js         # Home-Logik
│       ├── archive.js       # Archive-Logik
│       └── logs.js          # Logs-Logik
└── i18n.py                  # Sprachsystem
```

### Auto-Refresh (index.js)

```javascript
// Auto-Refresh alle 5 Sekunden
setInterval(function() {
    fetch('/api/status')
        .then(response => response.json())
        .then(data => {
            // State anzeigen
            document.getElementById('state').textContent = data.state;
            
            // Progress aktualisieren
            if (data.progress) {
                const percent = data.progress.percent;
                document.getElementById('progress-bar').style.width = percent + '%';
                document.getElementById('progress-text').textContent = percent + '%';
            }
        });
}, 5000);
```

---

## Neue Module entwickeln

Siehe Template oben und die detaillierten Modul-Dokumentationen:

- [Kapitel 4.1: Audio-CD Modul](04_Module/04-1_Audio-CD.md)
- [Kapitel 4.2: DVD-Video Modul](04_Module/04-2_DVD-Video.md)
- [Kapitel 4.3: BD-Video Modul](04_Module/04-3_BD-Video.md)
- [Kapitel 4.5: MQTT Modul](04_Module/04-5_MQTT.md)

---

## Coding-Standards

### Bash Style Guide

#### Variablen

```bash
# Globale Variablen: UPPERCASE
OUTPUT_DIR="/media/iso"
CDROM_DEVICE="/dev/sr0"

# Lokale Variablen: lowercase
local disc_type="audio-cd"
local output_file="/tmp/disc.iso"

# Konstanten: readonly
readonly SCRIPT_VERSION="1.2.0"
readonly MAX_RETRIES=3
```

#### Funktionen

```bash
# Naming: modul_funktion_beschreibung
cd_extract_tracks() {
    local device="$1"
    local output_dir="$2"
    
    # Validierung IMMER zuerst
    if [[ ! -b "$device" ]]; then
        log_error "Invalid device: $device"
        return 1
    fi
    
    # Logik...
    
    return 0
}
```

#### Fehlerbehandlung

```bash
# IMMER Rückgabewerte prüfen
if ! copy_with_dd "$device" "$iso_file"; then
    log_warning "dd failed, trying ddrescue..."
    if ! copy_with_ddrescue "$device" "$iso_file"; then
        log_error "Both methods failed"
        return 1
    fi
fi

# set -e VERMEIDEN (zu aggressiv)
# Stattdessen explizite Prüfung
```

#### Quoting

```bash
# IMMER Variablen in Quotes
local filename="$DISC_LABEL"
cp "$source" "$destination"

# Arrays: "@" statt "*"
for tool in "${REQUIRED_TOOLS[@]}"; do
    check_tool "$tool"
done
```

#### Shellcheck

```bash
# Regelmäßig prüfen
shellcheck disk2iso.sh disk2iso-lib/*.sh

# Ignorieren nur wenn nötig
# shellcheck disable=SC2059
printf "$format_string" "${args[@]}"
```

### Dokumentation

#### Funktions-Header

```bash
#######################################
# Extrahiert Audio-Tracks von einer CD
#
# Globals:
#   LAME_QUALITY - MP3-Encoding-Qualität
#   TEMP_DIR - Temporäres Arbeitsverzeichnis
#
# Arguments:
#   $1 - Device-Pfad (z.B. /dev/sr0)
#   $2 - Ausgabe-Verzeichnis
#
# Returns:
#   0 bei Erfolg, 1 bei Fehler
#
# Outputs:
#   Log-Nachrichten via log_info/log_error
#######################################
cd_extract_tracks() {
    # ...
}
```

---

## Testing

### Unit-Tests mit bats

**Installation:**
```bash
sudo apt install bats
```

**Test-Datei:** `tests/test-lib-files.bats`

```bash
#!/usr/bin/env bats

setup() {
    source disk2iso-lib/lib-files.sh
}

@test "sanitize_filename removes special chars" {
    result=$(sanitize_filename "Album: Greatest Hits (2023)")
    [[ "$result" == "Album_Greatest_Hits_2023" ]]
}

@test "sanitize_filename handles umlauts" {
    result=$(sanitize_filename "Für Elise")
    [[ "$result" == "Fuer_Elise" ]]
}

@test "generate_iso_filename creates correct path" {
    OUTPUT_DIR="/tmp"
    result=$(generate_iso_filename "test")
    [[ "$result" == "/tmp/data/test.iso" ]]
}
```

**Ausführen:**
```bash
bats tests/test-lib-files.bats
```

### Integration-Tests

```bash
# Mock-Disc erstellen
dd if=/dev/zero of=/tmp/test.iso bs=1M count=100

# Als Loop-Device mounten
sudo losetup /dev/loop0 /tmp/test.iso

# disk2iso mit Test-Device
sudo disk2iso --device /dev/loop0 --output /tmp/test-output

# Ergebnis validieren
ls -lh /tmp/test-output/data/
md5sum -c /tmp/test-output/data/*.md5
```

---

## Debugging

### Debug-Modi

```bash
# Debug-Ausgabe
DEBUG=true sudo disk2iso

# Verbose (alle Kommandos)
DEBUG=true VERBOSE=true sudo disk2iso

# Debug-Shell bei Fehler
DEBUG=true DEBUG_SHELL=true sudo disk2iso
```

### Trace-Modus

```bash
# set -x am Anfang
#!/bin/bash
set -x

# Ausgabe:
+ cdparanoia -d /dev/sr0 -w 1
+ lame -V 2 --quiet track01.wav track01.mp3
```

### strace

```bash
# System-Calls verfolgen
strace -f -e trace=open,read,write -o strace.log sudo disk2iso

# Analyse
grep "/dev/sr0" strace.log
```

---

## Weiterführende Links

- **[← Zurück: Kapitel 5 - Fehlerhandling](05_Fehlerhandling.md)**
- **[Kapitel 1 - Handbuch →](Handbuch.md)**
- **[Kapitel 2 - Installation →](02_Installation.md)**
- **[Kapitel 3 - Betrieb →](03_Betrieb.md)**
- **[Kapitel 4 - Optionale Module →](04_Module/)**

---

**Version:** 1.2.0  
**Letzte Aktualisierung:** 26. Januar 2026
