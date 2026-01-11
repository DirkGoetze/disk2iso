# Entwickler-Dokumentation

Technische Dokumentation für Entwickler, die disk2iso erweitern oder anpassen möchten.

## Inhaltsverzeichnis

1. [Architektur](#architektur)
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

## Architektur

### Überblick

disk2iso verwendet eine **modulare Plugin-Architektur** mit State Machine, Kern-Modulen und optionalen Media-Modulen.

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
        ├─► lib-cd.sh            (Audio-CD, nur wenn MODULE_AUDIO_CD=true)
        ├─► lib-dvd.sh           (Video-DVD, nur wenn MODULE_VIDEO_DVD=true)
        ├─► lib-bluray.sh        (Blu-ray, nur wenn MODULE_BLURAY=true)
        └─► lib-mqtt.sh          (MQTT, nur wenn MQTT_ENABLED=true)
```

### Komponenten-Verantwortlichkeiten

| Komponente | Verantwortung |
|------------|---------------|
| **disk2iso.sh** | State Machine, Hauptschleife, Disc-Überwachung, Modul-Loading |
| **lib-logging.sh** | Logging, Sprachsystem, Farben |
| **lib-api.sh** | JSON REST API Endpunkte (status, archive, logs, config, system) |
| **lib-diskinfos.sh** | Disc-Typ-Erkennung (audio-cd, dvd-video, bd-video, etc.) |
| **lib-drivestat.sh** | Laufwerk-Status (eingelegter →media, leer, offen) |
| **lib-common.sh** | Daten-Disc-Kopie (dd, ddrescue), Basis-Kopiermethoden |
| **lib-files.sh** | Datei-/Ordnernamen generieren, Sanitize |
| **lib-folders.sh** | Verzeichnis-Erstellung (lazy initialization) |
| **lib-tools.sh** | Abhängigkeiten prüfen, Tools installieren |
| **lib-cd.sh** | Audio-CD Ripping (cdparanoia, lame, MusicBrainz, CD-TEXT) |
| **lib-dvd.sh** | Video-DVD Backup (dvdbackup, genisoimage, Retry-Mechanismus) |
| **lib-bluray.sh** | Blu-ray Backup (ddrescue, dd) |
| **lib-mqtt.sh** | MQTT-Publishing (Status, Fortschritt, Home Assistant) |
| **lib-systeminfo.sh** | System-Informationen (OS, Hardware, Software) |

---

## State Machine

### Übersicht

disk2iso v1.3.0 implementiert eine **Finite State Machine** (FSM) für präzise Ablaufsteuerung und bessere Fehlerbehandlung.

### Definierte Zustände

```bash
readonly STATE_INITIALIZING="initializing"           # Start, Module laden
readonly STATE_WAITING_FOR_DRIVE="waiting_for_drive" # Laufwerk-Suche
readonly STATE_DRIVE_DETECTED="drive_detected"       # Laufwerk gefunden
readonly STATE_WAITING_FOR_MEDIA="waiting_for_media" # Warte auf Medium
readonly STATE_MEDIA_DETECTED="media_detected"       # Medium eingelegt
readonly STATE_ANALYZING="analyzing"                 # Disc-Typ ermitteln
readonly STATE_COPYING="copying"                     # Kopiervorgang läuft
readonly STATE_COMPLETED="completed"                 # Erfolgreich abgeschlossen
readonly STATE_ERROR="error"                         # Fehler aufgetreten
readonly STATE_WAITING_FOR_REMOVAL="waiting_for_removal" # Warte auf Entnahme
readonly STATE_IDLE="idle"                           # Bereit für nächstes Medium
```

### Zustandsübergänge

```
[initializing]
    ↓
[waiting_for_drive] ──(Laufwerk erkannt)──► [drive_detected]
    ↓                                              ↓
    └───────────(Polling 20s)─────────────────────┘
                                                   ↓
                                        [waiting_for_media]
                                                   ↓
                                         (Medium eingelegt)
                                                   ↓
                                         [media_detected]
                                                   ↓
                                           [analyzing]
                                                   ↓
                                           [copying]
                                          ↙        ↘
                                  (Erfolg)         (Fehler)
                                     ↓                ↓
                               [completed]        [error]
                                     ↓                ↓
                          [waiting_for_removal]  [waiting_for_removal]
                                     ↓
                              (Medium entfernt)
                                     ↓
                                  [idle]
                                     ↓
                          [waiting_for_media]
                                   (Loop)
```

### Polling-Intervalle

```bash
readonly POLL_DRIVE_INTERVAL=20    # Laufwerk-Suche: alle 20 Sekunden
readonly POLL_MEDIA_INTERVAL=2     # Medium-Erkennung: alle 2 Sekunden
readonly POLL_REMOVAL_INTERVAL=5   # Entnahme-Check: alle 5 Sekunden
```

### Implementierung

**State-Übergänge** via `transition_to_state()`:

```bash
transition_to_state() {
    local new_state="$1"
    local reason="${2:-}"
    
    log_message "State: $CURRENT_STATE → $new_state${reason:+ ($reason)}"
    CURRENT_STATE="$new_state"
    
    # API-Status aktualisieren
    update_api_state "$new_state" "$reason"
}
```

**State-Handler** in Hauptschleife:

```bash
while true; do
    case "$CURRENT_STATE" in
        "$STATE_WAITING_FOR_DRIVE")
            check_drive_availability
            ;;
        "$STATE_WAITING_FOR_MEDIA")
            check_media_inserted
            ;;
        "$STATE_COPYING")
            # Kopiervorgang läuft asynchron
            ;;
        # ... weitere States
    esac
    sleep "$POLL_INTERVAL"
done
```

### Vorteile

- ✅ **Vorhersagbar**: Klare Zustandsübergänge
- ✅ **Testbar**: Jeder State isoliert testbar
- ✅ **Fehlertoleranz**: Definierte Error-States
- ✅ **API-freundlich**: State via JSON abrufbar
- ✅ **Web-UI**: Live-Anzeige des aktuellen Zustands

---

## Modul-System

### Modul-Struktur

Jedes Modul ist eine eigenständige Bash-Datei mit:

1. **Funktions-Präfix**: Verhindert Namenskonflikte
2. **Abhängigkeits-Deklaration**: Welche Tools erforderlich
3. **Sprach-Dateien**: Übersetzungen (optional)
4. **Haupt-Funktion**: `copy_<media>` als Einstiegspunkt

**Beispiel**: `lib-cd.sh`

```bash
#!/bin/bash
# lib-cd.sh - Audio-CD Support

# Globale Variablen
CD_MODULE_VERSION="2.0.0"

# Abhängigkeiten (für lib-tools.sh)
CD_REQUIRED_TOOLS=(
    "cdparanoia"
    "lame"
    "eyed3"
    "curl"
    "jq"
)

# Haupt-Funktion (von disk2iso.sh aufgerufen)
copy_audio_cd() {
    local device="$1"
    local output_dir="$2"
    
    log_info "$(get_text 'cd.start')"
    
    # Disc-ID ermitteln
    local discid=$(cd_get_discid "$device")
    
    # MusicBrainz-Lookup
    if [[ "$MUSICBRAINZ_ENABLED" == "true" ]]; then
        cd_lookup_musicbrainz "$discid"
    fi
    
    # Tracks extrahieren
    cd_extract_tracks "$device" "$output_dir"
    
    # MP3-Encoding
    cd_encode_mp3 "$output_dir"
    
    # Cover herunterladen
    if [[ "$DOWNLOAD_COVERS" == "true" ]]; then
        cd_download_cover "$output_dir"
    fi
    
    log_success "$(get_text 'cd.complete')"
}

# Hilfsfunktionen (Präfix: cd_)
cd_get_discid() {
    # ...
}

cd_lookup_musicbrainz() {
    # ...
}

cd_extract_tracks() {
    # ...
}

cd_encode_mp3() {
    # ...
}

cd_download_cover() {
    # ...
}
```

### Modul-Loading

In `disk2iso.sh` (Hauptschleife):

```bash
# Disc-Typ erkennen
DISC_TYPE=$(get_disc_type "$CDROM_DEVICE")

case "$DISC_TYPE" in
    audio-cd)
        if [[ "$MODULE_AUDIO_CD" == "true" ]]; then
            source "$SCRIPT_DIR/disk2iso-lib/lib-cd.sh"
            copy_audio_cd "$CDROM_DEVICE" "$OUTPUT_DIR"
        else
            log_warning "$(get_text 'module.disabled' 'Audio-CD')"
            # Fallback zu Daten-Disc
            copy_data_disc "$CDROM_DEVICE" "$OUTPUT_DIR"
        fi
        ;;
    
    dvd-video)
        if [[ "$MODULE_VIDEO_DVD" == "true" ]]; then
            source "$SCRIPT_DIR/disk2iso-lib/lib-dvd.sh"
            copy_video_dvd "$CDROM_DEVICE" "$OUTPUT_DIR"
        else
            log_warning "$(get_text 'module.disabled' 'Video-DVD')"
            copy_data_disc "$CDROM_DEVICE" "$OUTPUT_DIR"
        fi
        ;;
    
    # ... weitere Disc-Typen
    
    *)
        # Unbekannt → Daten-Disc
        copy_data_disc "$CDROM_DEVICE" "$OUTPUT_DIR"
        ;;
esac
```

### Modul-Kommunikation

Module kommunizieren über:

1. **Rückgabewerte**: `return 0` (Erfolg) oder `return 1` (Fehler)
2. **Globale Variablen**: `$DISC_LABEL`, `$DISC_TYPE`, `$OUTPUT_DIR`
3. **Logs**: `log_info`, `log_warning`, `log_error`

**Beispiel**:

```bash
# In lib-cd.sh
copy_audio_cd() {
    # ...
    if ! cd_extract_tracks "$device" "$output_dir"; then
        log_error "$(get_text 'cd.extraction_failed')"
        return 1
    fi
    # ...
    return 0
}

# In disk2iso.sh
if copy_audio_cd "$CDROM_DEVICE" "$OUTPUT_DIR"; then
    log_success "Archivierung abgeschlossen"
    eject "$CDROM_DEVICE"
else
    log_error "Archivierung fehlgeschlagen"
    handle_error
fi
```

---

## Sprachsystem

### Struktur

Sprach-Dateien liegen in `disk2iso-lib/lang/`:

```
lang/
├── lib-cd.de
├── lib-cd.en
├── lib-dvd.de
├── lib-dvd.en
├── lib-common.de
└── lib-common.en
```

### Format

**lib-cd.de** (Deutsch):
```bash
# Audio-CD Modul (Deutsch)
cd.start="Starte Audio-CD Ripping..."
cd.discid="Disc-ID: %s"
cd.musicbrainz_found="MusicBrainz: %s - %s (%s)"
cd.musicbrainz_not_found="MusicBrainz: Keine Daten gefunden"
cd.track_progress="Track %d/%d: %s"
cd.encoding="Encoding zu MP3 (VBR V%d)..."
cd.cover_downloaded="Cover heruntergeladen: %dx%d px"
cd.complete="Audio-CD abgeschlossen: %d Tracks, %s"
cd.extraction_failed="Fehler bei Track-Extraktion"
```

**lib-cd.en** (English):
```bash
# Audio-CD Module (English)
cd.start="Starting audio CD ripping..."
cd.discid="Disc ID: %s"
cd.musicbrainz_found="MusicBrainz: %s - %s (%s)"
cd.musicbrainz_not_found="MusicBrainz: No data found"
cd.track_progress="Track %d/%d: %s"
cd.encoding="Encoding to MP3 (VBR V%d)..."
cd.cover_downloaded="Cover downloaded: %dx%d px"
cd.complete="Audio CD complete: %d tracks, %s"
cd.extraction_failed="Track extraction failed"
```

### Verwendung

In Modulen:

```bash
# Einfache Nachricht
log_info "$(get_text 'cd.start')"

# Mit Platzhaltern (printf-Syntax)
log_info "$(get_text 'cd.discid' "$discid")"
log_info "$(get_text 'cd.musicbrainz_found' "$artist" "$album" "$year")"
log_info "$(get_text 'cd.track_progress' "$current" "$total" "$title")"
```

### get_text Funktion

In `lib-logging.sh`:

```bash
get_text() {
    local key="$1"
    shift
    local args=("$@")
    
    # Sprachdatei ermitteln
    local module="${key%%.*}"       # cd, dvd, bluray, common
    local lang_file="$SCRIPT_DIR/disk2iso-lib/lang/lib-${module}.${LANG}"
    
    # Fallback zu English
    if [[ ! -f "$lang_file" ]]; then
        lang_file="$SCRIPT_DIR/disk2iso-lib/lang/lib-${module}.en"
    fi
    
    # Text aus Datei lesen
    local text=$(grep "^${key}=" "$lang_file" | cut -d'=' -f2- | sed 's/^"//;s/"$//')
    
    # Platzhalter ersetzen (printf)
    if [[ ${#args[@]} -gt 0 ]]; then
        # shellcheck disable=SC2059
        printf "$text" "${args[@]}"
    else
        echo "$text"
    fi
}
```

### Neue Sprache hinzufügen

1. **Sprach-Dateien erstellen**:
   ```bash
   cp disk2iso-lib/lang/lib-cd.en disk2iso-lib/lang/lib-cd.fr
   cp disk2iso-lib/lang/lib-dvd.en disk2iso-lib/lang/lib-dvd.fr
   # ... weitere Module
   ```

2. **Übersetzen**:
   ```bash
   # lib-cd.fr
   cd.start="Démarrage de l'extraction du CD audio..."
   cd.musicbrainz_found="MusicBrainz: %s - %s (%s)"
   # ...
   ```

3. **config.sh anpassen**:
   ```bash
   LANG="fr"
   ```

4. **Fallback testen**:
   ```bash
   # Fehlende Übersetzungen → Englisch
   get_text 'cd.new_feature'  # Nicht in .fr → .en
   ```

---

## API-Referenz

### Kern-Funktionen

#### Logging (lib-logging.sh)

```bash
log_info "message"              # [INFO] message
log_success "message"            # [SUCCESS] message
log_warning "message"            # [WARNING] message
log_error "message"              # [ERROR] message
log_debug "message"              # [DEBUG] message (nur wenn DEBUG=true)

get_text "key" [args...]        # Übersetzung abrufen
```

#### Disc-Informationen (lib-diskinfos.sh)

```bash
get_disc_type "$device"         # → audio-cd, dvd-video, bd-video, cd-rom, dvd-rom, bd-rom
get_disc_label "$device"        # → Disc-Label (String)
is_audio_cd "$device"           # → 0 (ja) oder 1 (nein)
is_video_dvd "$device"          # → 0 oder 1
is_bluray "$device"             # → 0 oder 1
```

**Beispiel**:
```bash
DISC_TYPE=$(get_disc_type "/dev/sr0")
if [[ "$DISC_TYPE" == "audio-cd" ]]; then
    DISC_LABEL=$(get_disc_label "/dev/sr0")
    echo "Audio-CD: $DISC_LABEL"
fi
```

#### Laufwerk-Status (lib-drivestat.sh)

```bash
get_drive_status "$device"      # → media, nodisc, tray_open
wait_for_disc "$device"         # Blockiert bis Disc eingelegt
eject_disc "$device"            # Disc auswerfen
close_tray "$device"            # Schublade schließen
```

**Beispiel**:
```bash
while true; do
    STATUS=$(get_drive_status "/dev/sr0")
    case "$STATUS" in
        media)
            echo "Disc eingelegt"
            break
            ;;
        nodisc)
            echo "Laufwerk leer"
            sleep 2
            ;;
        tray_open)
            echo "Schublade offen"
            sleep 2
            ;;
    esac
done
```

#### Dateinamen (lib-files.sh)

```bash
sanitize_filename "string"      # Bereinigt Dateinamen (Sonderzeichen entfernen)
generate_iso_filename "$label"  # → /path/to/label.iso
generate_md5_filename "$iso"    # → /path/to/label.md5
get_unique_filename "$path"     # → path_1, path_2 bei Duplikaten
```

**Beispiel**:
```bash
LABEL="Album: Greatest Hits (2023)"
SAFE_LABEL=$(sanitize_filename "$LABEL")
# → Album_Greatest_Hits_2023

ISO_FILE=$(generate_iso_filename "$SAFE_LABEL")
# → /srv/disk2iso/data/Album_Greatest_Hits_2023.iso
```

#### Ordner (lib-folders.sh)

```bash
ensure_output_dir                # Erstellt OUTPUT_DIR (lazy)
ensure_audio_dir                 # Erstellt OUTPUT_DIR/audio
ensure_dvd_dir                   # Erstellt OUTPUT_DIR/dvd
ensure_bd_dir                    # Erstellt OUTPUT_DIR/bd
ensure_data_dir                  # Erstellt OUTPUT_DIR/data
ensure_log_dir                   # Erstellt OUTPUT_DIR/log
ensure_temp_dir                  # Erstellt OUTPUT_DIR/temp
```

**Beispiel**:
```bash
copy_audio_cd() {
    ensure_audio_dir
    local artist_dir="$OUTPUT_DIR/audio/$ARTIST"
    mkdir -p "$artist_dir"
    # ...
}
```

#### Tools (lib-tools.sh)

```bash
check_tool "command"            # Prüft ob Tool installiert → 0 oder 1
check_all_tools                 # Prüft alle REQUIRED_TOOLS
install_missing_tools           # Installiert fehlende Tools (apt)
get_tool_version "command"      # → Version-String
```

**Beispiel**:
```bash
if ! check_tool "cdparanoia"; then
    log_error "cdparanoia nicht installiert"
    if confirm "Jetzt installieren?"; then
        install_missing_tools
    fi
fi
```

#### Basis-Kopiermethoden (lib-common.sh)

```bash
copy_with_dd "$device" "$output"        # Schnelle Kopie mit dd
copy_with_ddrescue "$device" "$output"  # Robuste Kopie mit ddrescue
create_md5_checksum "$file"             # Erstellt .md5-Datei
verify_md5_checksum "$file"             # Überprüft MD5
```

**Beispiel**:
```bash
ISO_FILE="/srv/disk2iso/data/disc.iso"

if copy_with_dd "/dev/sr0" "$ISO_FILE"; then
    create_md5_checksum "$ISO_FILE"
    log_success "Kopie abgeschlossen"
else
    log_warning "dd fehlgeschlagen, versuche ddrescue..."
    if copy_with_ddrescue "/dev/sr0" "$ISO_FILE"; then
        create_md5_checksum "$ISO_FILE"
        log_success "Kopie abgeschlossen (mit ddrescue)"
    else
        log_error "Beide Methoden fehlgeschlagen"
        return 1
    fi
fi
```

---

## Neue Module entwickeln

### Beispiel: lib-vcd.sh (Video-CD Support)

#### 1. Modul-Datei erstellen

```bash
nano disk2iso-lib/lib-vcd.sh
```

**Struktur**:

```bash
#!/bin/bash
# lib-vcd.sh - Video-CD Support

VCD_MODULE_VERSION="1.0.0"

# Abhängigkeiten
VCD_REQUIRED_TOOLS=(
    "vcdxrip"           # VCD-Extraktion
    "ffmpeg"            # Video-Konvertierung
)

# Haupt-Funktion
copy_video_cd() {
    local device="$1"
    local output_dir="$2"
    
    log_info "$(get_text 'vcd.start')"
    
    # VCD-Struktur analysieren
    local tracks=$(vcd_get_tracks "$device")
    log_info "$(get_text 'vcd.tracks_found' "$tracks")"
    
    # Tracks extrahieren
    ensure_vcd_dir
    local vcd_dir="$output_dir/vcd"
    
    for track in $(seq 1 "$tracks"); do
        log_info "$(get_text 'vcd.extracting_track' "$track" "$tracks")"
        vcdxrip -t "$track" -o "$vcd_dir/track${track}.mpg" "$device" || return 1
    done
    
    # Optional: Zu MP4 konvertieren
    if [[ "$VCD_CONVERT_TO_MP4" == "true" ]]; then
        vcd_convert_to_mp4 "$vcd_dir"
    fi
    
    log_success "$(get_text 'vcd.complete' "$tracks")"
    return 0
}

# Hilfsfunktionen
vcd_get_tracks() {
    local device="$1"
    vcdxrip -i "$device" 2>&1 | grep -c "Track"
}

vcd_convert_to_mp4() {
    local dir="$1"
    for mpg in "$dir"/*.mpg; do
        local mp4="${mpg%.mpg}.mp4"
        log_info "$(get_text 'vcd.converting' "$(basename "$mpg")")"
        ffmpeg -i "$mpg" -c:v libx264 -crf 23 -c:a aac -b:a 192k "$mp4" -y
        rm "$mpg"  # Optional: Original löschen
    done
}
```

#### 2. Sprachdateien erstellen

**disk2iso-lib/lang/lib-vcd.de**:
```bash
vcd.start="Starte Video-CD Extraktion..."
vcd.tracks_found="%d Video-Tracks gefunden"
vcd.extracting_track="Extrahiere Track %d/%d..."
vcd.converting="Konvertiere zu MP4: %s"
vcd.complete="Video-CD abgeschlossen: %d Tracks"
```

**disk2iso-lib/lang/lib-vcd.en**:
```bash
vcd.start="Starting Video-CD extraction..."
vcd.tracks_found="%d video tracks found"
vcd.extracting_track="Extracting track %d/%d..."
vcd.converting="Converting to MP4: %s"
vcd.complete="Video-CD complete: %d tracks"
```

#### 3. Disc-Erkennung erweitern

**lib-diskinfos.sh**:
```bash
is_video_cd() {
    local device="$1"
    
    # VCD-Signature prüfen
    local vcd_sig=$(dd if="$device" bs=1 count=8 skip=32808 2>/dev/null)
    if [[ "$vcd_sig" == "VIDEO_CD" ]]; then
        return 0
    fi
    return 1
}

get_disc_type() {
    local device="$1"
    
    # ... bestehende Prüfungen ...
    
    # VCD-Prüfung
    if is_video_cd "$device"; then
        echo "vcd-video"
        return 0
    fi
    
    # ... Rest ...
}
```

#### 4. Modul in disk2iso.sh integrieren

```bash
case "$DISC_TYPE" in
    # ... bestehende Cases ...
    
    vcd-video)
        if [[ "$MODULE_VIDEO_CD" == "true" ]]; then
            source "$SCRIPT_DIR/disk2iso-lib/lib-vcd.sh"
            copy_video_cd "$CDROM_DEVICE" "$OUTPUT_DIR"
        else
            log_warning "VCD-Modul deaktiviert"
            copy_data_disc "$CDROM_DEVICE" "$OUTPUT_DIR"
        fi
        ;;
esac
```

#### 5. config.sh erweitern

```bash
# VCD-Modul
MODULE_VIDEO_CD=true

# VCD-Einstellungen
VCD_CONVERT_TO_MP4=true    # MPEG-1 → MP4 konvertieren
VCD_DELETE_ORIGINAL=true   # .mpg nach Konvertierung löschen
```

#### 6. Installer anpassen

**install.sh** (Modul-Auswahl-Seite):
```bash
MODULES=$(whiptail --title "Modul-Auswahl" \
    --checklist "Wähle Module:" 20 70 4 \
    "MODULE_AUDIO_CD" "Audio-CD Support" ON \
    "MODULE_VIDEO_DVD" "Video-DVD Support" ON \
    "MODULE_VIDEO_CD" "Video-CD Support" OFF \
    "MODULE_BLURAY" "Blu-ray Support" OFF \
    3>&1 1>&2 2>&3)

# VCD-Abhängigkeiten
if [[ "$MODULES" == *"MODULE_VIDEO_CD"* ]]; then
    apt install -y vcdxrip ffmpeg
    cp disk2iso-lib/lib-vcd.sh /opt/disk2iso/disk2iso-lib/
fi
```

---

## Coding-Standards

### Bash Style Guide

#### Shebang & Header

```bash
#!/bin/bash
# lib-example.sh - Example Module
# Version: 1.0.0
# Description: Short description of the module
```

#### Variablen

```bash
# Globale Variablen: UPPERCASE
OUTPUT_DIR="/srv/disk2iso"
CDROM_DEVICE="/dev/sr0"

# Lokale Variablen: lowercase
local disc_type="audio-cd"
local output_file="/tmp/disc.iso"

# Funktions-Parameter: beschreibend
process_disc() {
    local device="$1"
    local output_dir="$2"
    # ...
}
```

#### Funktionen

```bash
# Naming: Modul-Präfix + Beschreibung
cd_extract_tracks() {
    local device="$1"
    local output_dir="$2"
    
    # Validierung
    if [[ ! -b "$device" ]]; then
        log_error "Invalid device: $device"
        return 1
    fi
    
    # Logic
    # ...
    
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
# Stattdessen explizite Fehlerprüfung
```

#### Logging

```bash
# Konsistente Log-Level
log_debug "Detailed information (only in DEBUG mode)"
log_info "Normal operation progress"
log_warning "Recoverable issues"
log_error "Critical failures"
log_success "Completion messages"

# Sprachsystem nutzen
log_info "$(get_text 'cd.track_progress' "$current" "$total" "$title")"
# NICHT: log_info "Track $current/$total: $title"
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
# Shellcheck-Compliance
# Ignorieren nur wenn nötig:
# shellcheck disable=SC2059
printf "$format_string" "${args[@]}"

# Regelmäßig prüfen:
shellcheck disk2iso.sh disk2iso-lib/*.sh
```

### Dokumentation

#### Funktions-Dokumentation

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
    local device="$1"
    local output_dir="$2"
    # ...
}
```

#### Inline-Kommentare

```bash
# Komplex→en Code erklären
# NICHT: Offensichtliches kommentieren

# Gut:
# MusicBrainz API hat Rate-Limit von 1 req/s
sleep 1

# Schlecht:
# Setze Variable auf 42
answer=42
```

---

## Testing

### Unit-Tests (mit bats)

**Installation**:
```bash
sudo apt install bats
```

**Test-Datei**: `tests/test-lib-cd.bats`

```bash
#!/usr/bin/env bats

# Setup
setup() {
    source disk2iso-lib/lib-logging.sh
    source disk2iso-lib/lib-cd.sh
    export DEBUG=false
}

# Tests
@test "sanitize_filename removes special chars" {
    result=$(sanitize_filename "Album: Greatest Hits (2023)")
    [[ "$result" == "Album_Greatest_Hits_2023" ]]
}

@test "cd_get_discid returns valid format" {
    # Mock cd-discid
    cd-discid() { echo "wXyz1234AbCd5678"; }
    export -f cd-discid
    
    result=$(cd_get_discid "/dev/sr0")
    [[ "$result" =~ ^[A-Za-z0-9]{16}$ ]]
}

@test "cd_extract_tracks creates WAV files" {
    skip "Requires physical CD"
    # Integration-Test
}
```

**Ausführen**:
```bash
bats tests/test-lib-cd.bats
```

### Integration-Tests

**Manuell**:
```bash
# 1. Test-Disc einlegen
# 2. Debug-Modus aktivieren
DEBUG=true sudo disk2iso

# 3. Log prüfen
tail -f /srv/disk2iso/.log/test_disc.log

# 4. Ausgabe validieren
ls -lh /srv/disk2iso/audio/
md5sum -c /srv/disk2iso/dvd/*.md5
```

### Mock-Tests

**Beispiel**: MusicBrainz-API testen ohne Internet

```bash
# tests/mocks/musicbrainz-response.json
{
  "artist": "Test Artist",
  "title": "Test Album",
  "date": "2023",
  "tracks": [
    {"position": 1, "title": "Track 1"},
    {"position": 2, "title": "Track 2"}
  ]
}

# Test-Funktion
test_musicbrainz_parse() {
    local response=$(cat tests/mocks/musicbrainz-response.json)
    local artist=$(echo "$response" | jq -r '.artist')
    [[ "$artist" == "Test Artist" ]] || return 1
}
```

---

## Debugging

### Debug-Modi

#### DEBUG=true

**Aktivieren**:
```bash
DEBUG=true sudo disk2iso
```

**Effekt**:
- Detaillierte Funktions-Aufrufe
- Tool-Kommandos mit Ausgabe
- API-Responses (JSON)
- Variablen-Werte

**Beispiel-Ausgabe**:
```
[DEBUG] check_disc_type() called
[DEBUG] Device: /dev/sr0
[DEBUG] Running: cdparanoia -d /dev/sr0 -Q
[DEBUG] Output:
cdparanoia III release 10.2 (September 11, 2008)
14 audio tracks found
[DEBUG] is_audio_cd() → true
[DEBUG] DISC_TYPE=audio-cd
```

#### DEBUG_SHELL=true

**Aktivieren**:
```bash
DEBUG=true DEBUG_SHELL=true sudo disk2iso
```

**Effekt**:
- Bei Fehler → Shell im Kontext öffnen
- Zugriff auf alle Variablen
- Manuelles Debugging möglich

**Beispiel**:
```
[ERROR] MusicBrainz-Lookup fehlgeschlagen
[DEBUG] Öffne Debug-Shell (exit zum Fortfahren)
bash-5.1# echo $DISCID
wXyz1234AbCd5678
bash-5.1# curl "https://musicbrainz.org/ws/2/discid/$DISCID?fmt=json"
{"error": "Rate limit exceeded"}
bash-5.1# exit
[INFO] Fahre fort ohne Metadaten...
```

### Trace-Modus

**Bash-Trace aktivieren**:
```bash
#!/bin/bash
set -x  # Am Anfang von disk2iso.sh

# ODER: Nur für Funktion
cd_extract_tracks() {
    set -x
    # ...
    set +x
}
```

**Ausgabe**:
```
+ cdparanoia -d /dev/sr0 -w 1
+ lame -V 2 --quiet track01.cdda.wav track01.mp3
+ eyeD3 --artist 'Pink Floyd' --album 'The Wall' track01.mp3
```

### Log-Analyse

**Log-Datei**:
```bash
tail -f /srv/disk2iso/.log/disc_label.log
```

**Fehler finden**:
```bash
grep -i error /srv/disk2iso/.log/*.log
grep -i warning /srv/disk2iso/.log/*.log
```

**Performance**:
```bash
# Zeitstempel-Differenzen
awk '/\[INFO\] Track/ {print $1, $2}' disc.log
```

### strace (System-Calls)

**Tool-Aufrufe verfolgen**:
```bash
strace -f -e trace=open,read,write -o strace.log sudo disk2iso
```

**Analyse**:
```bash
grep "cdparanoia" strace.log
grep "/dev/sr0" strace.log
```

---

## Weiterführende Links

- **[← Zurück zum Handbuch](Handbuch.md)**
- **[Verwendung](Verwendung.md)**
- **[Deinstallation →](Deinstallation.md)**

---

**Version**: 1.3.0 | **Letzte Aktualisierung**: 11.01.2026
