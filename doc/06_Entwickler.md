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
11. [DISC_INFO Best Practices](#disc_info-best-practices)

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
    ├─► [lib-folders.sh] folders_ensure_subfolder()
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

### Architektur-Prinzip (seit v1.2.0)

**Ziel**: Python nur als Mittler, komplette Business-Logic in Bash

```
Browser/User
    ↓
Python Routes (www/routes/routes_module.py)
    ↓ (subprocess + JSON)
Bash CLI-Interface (lib/libmodule.sh)
    ↓
Business-Logic (Bash-Funktionen)
    ↓
Externe Tools (dd, dvdbackup, mosquitto_pub, etc.)
```

**Vorteile**:
- ✅ Python-unabhängige CLI-Tools (direkt testbar)
- ✅ Keine Config-/Tool-Kenntnisse in Python
- ✅ Wiederverwendbare Helper-Funktionen
- ✅ DRY-Prinzip durchgesetzt

### Modul-Template (mit CLI-Interface)

> 💡 **Vollständiges Pattern**: Siehe [todo/Modul-CLI-Interface-Pattern.md](../../todo/Modul-CLI-Interface-Pattern.md)

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
    "jq"        # JSON-Parsing
    "tool1"
    "tool2"
)

# =====================================================
# HELPER-FUNKTIONEN (Wiederverwendbar)
# =====================================================

# Zentrale Default-Definition (Single Source of Truth)
_example_get_defaults() {
    local key="$1"
    case "$key" in
        enabled) echo "false" ;;
        setting_x) echo "default_value" ;;
        setting_y) echo "42" ;;
    esac
}

# Wiederverwendbare Test-Logik
_example_test_feature() {
    local param1="$1"
    local param2="$2"
    
    # Test-Logik...
    return 0  # 0 = success, 1 = failure
}

# =====================================================
# HAUPT-FUNKTION (Legacy, für disk2iso.sh)
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
    
    # Kopiervorgang (nutzt Helper)
    local output_file="$output_dir/example/${disc_label}.ext"
    
    if ! example_copy_method "$device" "$output_file"; then
        log_error "$(get_text 'example.copy_failed')"
        return 1
    fi
    
    # Checksumme
    create_md5_checksum "$output_file"
    
    log_success "$(get_text 'example.complete' "$output_file')"
    return 0
}

example_copy_method() {
    local device="$1"
    local output="$2"
    
    # Implementierung...
    return 0
}

ensure_example_dir() {
    mkdir -p "$OUTPUT_DIR/example"
}

# =====================================================
# CLI-INTERFACE (für Web-UI / externe Aufrufe)
# =====================================================

# Export Config als JSON
example_export_config_json() {
    # 1. Source libconfig.sh für get_ini_value
    local lib_dir="$(dirname "$BASH_SOURCE")"
    source "$lib_dir/libconfig.sh"
    
    # 2. Read main config
    local conf_file="$BASE_DIR/conf/disk2iso.conf"
    local example_enabled=$(get_ini_value "$conf_file" "example" "enabled")
    
    # 3. Read module config
    local ini_file="$BASE_DIR/conf/libexample.ini"
    local setting_x=$(get_ini_value "$ini_file" "section" "setting_x")
    
    # 4. Apply defaults
    example_enabled=${example_enabled:-$(_example_get_defaults enabled)}
    setting_x=${setting_x:-$(_example_get_defaults setting_x)}
    
    # 5. Build JSON
    cat <<EOF
{
  "example_enabled": ${example_enabled},
  "setting_x": "${setting_x}"
}
EOF
}

# Update Config via JSON
example_update_config() {
    # 1. Source dependencies
    local lib_dir="$(dirname "$BASH_SOURCE")"
    source "$lib_dir/libconfig.sh"
    
    # 2. Parse JSON from stdin (jq bevorzugt)
    read -r json_input
    local example_enabled=$(echo "$json_input" | jq -r '.example_enabled // "false"')
    local setting_x=$(echo "$json_input" | jq -r '.setting_x // ""')
    
    # 3. Validate (Business-Logic in Bash!)
    if [[ ! "$example_enabled" =~ ^(true|false)$ ]]; then
        echo '{"success": false, "error": "Invalid enabled value"}'
        return 1
    fi
    
    # 4. Write via libconfig.sh (nutzt set_example_* Funktionen)
    set_example_enabled "$example_enabled"
    set_example_setting_x "$setting_x"
    
    # 5. Response
    echo '{"success": true, "updated_keys": ["EXAMPLE_ENABLED", "SETTING_X"], "restart_required": true}'
}

# Test Feature via JSON
example_test_feature() {
    # 1. Parse JSON
    read -r json_input
    local param1=$(echo "$json_input" | jq -r '.param1')
    local param2=$(echo "$json_input" | jq -r '.param2 // "default"')
    
    # 2. Use helper function
    if _example_test_feature "$param1" "$param2"; then
        echo '{"success": true, "message": "Test erfolgreich"}'
    else
        echo '{"success": false, "error": "Test fehlgeschlagen"}'
    fi
}

# =====================================================
# MAIN ENTRY POINT
# =====================================================

main() {
    local command="$1"
    
    case "$command" in
        "export-config")
            example_export_config_json
            ;;
        "update-config")
            example_update_config
            ;;
        "test-feature")
            example_test_feature
            ;;
        *)
            echo '{"success": false, "error": "Ungültiger Befehl"}' >&2
            exit 1
            ;;
    esac
}

# Conditional execution (nur bei direktem Aufruf, nicht wenn gesourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

### CLI-Nutzung

**Direkt im Terminal**:

```bash
# Config exportieren
/opt/disk2iso/lib/libexample.sh export-config

# Config updaten (JSON via stdin)
echo '{"example_enabled": true, "setting_x": "new_value"}' | \
  /opt/disk2iso/lib/libexample.sh update-config

# Feature testen (JSON via stdin)
echo '{"param1": "test", "param2": "value"}' | \
  /opt/disk2iso/lib/libexample.sh test-feature
```

**Via Python (routes_example.py)**:

```python
import subprocess
import json
from pathlib import Path

BASE_DIR = Path('/opt/disk2iso')

def get_example_config():
    """Config via Bash-Script lesen"""
    result = subprocess.run(
        [f'{BASE_DIR}/lib/libexample.sh', 'export-config'],
        capture_output=True,
        text=True,
        check=True
    )
    return json.loads(result.stdout)

@app.route('/api/example/save', methods=['POST'])
def api_example_save():
    """Config via Bash-Script schreiben"""
    data = request.get_json()
    
    result = subprocess.run(
        [f'{BASE_DIR}/lib/libexample.sh', 'update-config'],
        input=json.dumps(data),
        capture_output=True,
        text=True
    )
    
    return jsonify(json.loads(result.stdout))
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

### Best Practices (DRY-Prinzip)

#### ❌ Anti-Pattern: Code-Duplikation

```bash
# FALSCH: Defaults an mehreren Stellen
mqtt_export_config_json() {
    local mqtt_enabled="false"
    local mqtt_broker="192.168.20.13"
    # ...
}

load_mqtt_config() {
    MQTT_BROKER="${MQTT_BROKER:-${broker:-192.168.20.13}}"
    # ...
}
```

#### ✅ Best Practice: Single Source of Truth

```bash
# RICHTIG: Zentrale Default-Definition
_mqtt_get_defaults() {
    local key="$1"
    case "$key" in
        enabled) echo "false" ;;
        broker) echo "192.168.20.13" ;;
        port) echo "1883" ;;
    esac
}

# Nutzung überall
mqtt_export_config_json() {
    local mqtt_enabled=$(_mqtt_get_defaults enabled)
    local mqtt_broker=$(_mqtt_get_defaults broker)
}

load_mqtt_config() {
    MQTT_BROKER="${MQTT_BROKER:-${broker:-$(_mqtt_get_defaults broker)}}"
}
```

#### ✅ Best Practice: libconfig.sh nutzen

```bash
# FALSCH: Eigene awk-Implementierung (16 Zeilen)
local ini_value=$(awk -F'=' '/^\[section\]/,/^\[/ {if ($1 ~ /^key/) {print $2}}' "$ini_file")

# RICHTIG: libconfig.sh sourcing (1 Zeile)
source "$lib_dir/libconfig.sh"
local ini_value=$(get_ini_value "$ini_file" "section" "key")
```

**Vorteile**:
- 75% weniger Code
- Nutzt getestete Core-Funktionen
- Konsistente INI-Parsing-Logik

#### ✅ Best Practice: Helper-Funktionen

```bash
# Wiederverwendbare Logik mit _ Präfix (private)
_mqtt_test_broker() {
    local broker="$1"
    local port="$2"
    # Test-Logik...
    return $?
}

# Nutzung in Legacy-Funktion
mqtt_init_connection() {
    if ! _mqtt_test_broker "$MQTT_BROKER" "$MQTT_PORT"; then
        log_error "Broker unreachable"
        return 1
    fi
}

# Nutzung in CLI-Funktion
mqtt_test_connection() {
    read -r json_input
    local broker=$(echo "$json_input" | jq -r '.broker')
    
    if _mqtt_test_broker "$broker" "$port"; then
        echo '{"success": true}'
    fi
}
```

**Vorteile**:
- Keine Code-Duplikation
- Einfacher zu testen
- Business-Logic bleibt zentral

### Modul-Checkliste

- [ ] Helper-Funktionen mit `_` Präfix für Wiederverwendung
- [ ] `_module_get_defaults()` für zentrale Default-Definition
- [ ] `module_export_config_json()` für Config-Export
- [ ] `module_update_config()` für Config-Update (nutzt libconfig.sh)
- [ ] `module_test_feature()` für Feature-Tests (optional)
- [ ] `main()` Entry Point mit case-Statement
- [ ] `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` Conditional
- [ ] Source libconfig.sh für get_ini_value() + Setter
- [ ] jq für JSON-Parsing nutzen
- [ ] Keine Code-Duplikation (DRY-Prinzip prüfen)

**Referenz-Implementierung**: [lib/libmqtt.sh](../../lib/libmqtt.sh) (100% architektur-konform seit v1.2.0)

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
│   ├─ base.html            # Layout + Navigation
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
