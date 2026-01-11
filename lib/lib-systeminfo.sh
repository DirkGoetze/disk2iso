#!/bin/bash
################################################################################
# disk2iso v1.3.0 - System Information Library
# Filepath: lib/lib-systeminfo.sh
#
# Beschreibung:
#   - Container-Erkennung (LXC, Docker, Podman)
#   - Speicherplatz-Prüfung
#   - Medium-Wechsel-Erkennung (für Container-Umgebungen)
#   - System-Informationen und Monitoring
#
# Version: 1.3.0
# Datum: 06.01.2026
################################################################################

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

IS_CONTAINER=false
CONTAINER_TYPE=""

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

# Lade Sprachdatei für dieses Modul
load_module_language "systeminfo"

# Funktion: Prüfe System-Abhängigkeiten
# Rückgabe: 0 = OK, 1 = Fehler
check_systeminfo_dependencies() {
    local missing=()
    
    # Basis-Tools für Systeminformationen
    command -v df >/dev/null 2>&1 || missing+=("df")
    command -v blkid >/dev/null 2>&1 || missing+=("blkid")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_message "$MSG_ERROR_SYSTEM_TOOLS_MISSING ${missing[*]}"
        log_message "$MSG_INSTALLATION_SYSTEM_TOOLS"
        return 1
    fi
    
    return 0
}

# ============================================================================
# CONTAINER DETECTION
# ============================================================================

# Funktion: Erkenne Container-Umgebung
# Setzt globale Variablen: IS_CONTAINER, CONTAINER_TYPE
detect_container_environment() {
    IS_CONTAINER=false
    CONTAINER_TYPE=""
    
    # Methode 1: Prüfe /proc/1/environ auf container=
    if [[ -f /proc/1/environ ]]; then
        local env_content=$(tr '\0' '\n' < /proc/1/environ 2>/dev/null)
        
        if echo "$env_content" | grep -q "^container=lxc$"; then
            IS_CONTAINER=true
            CONTAINER_TYPE="lxc"
            log_message "$MSG_CONTAINER_DETECTED LXC"
            return 0
        elif echo "$env_content" | grep -q "^container=docker$"; then
            IS_CONTAINER=true
            CONTAINER_TYPE="docker"
            log_message "$MSG_CONTAINER_DETECTED Docker"
            return 0
        elif echo "$env_content" | grep -q "^container=podman$"; then
            IS_CONTAINER=true
            CONTAINER_TYPE="podman"
            log_message "$MSG_CONTAINER_DETECTED Podman"
            return 0
        fi
    fi
    
    # Methode 2: Prüfe auf Docker-spezifische Dateien
    if [[ -f /.dockerenv ]]; then
        IS_CONTAINER=true
        CONTAINER_TYPE="docker"
        log_message "$MSG_CONTAINER_DETECTED Docker"
        return 0
    fi
    
    # Methode 3: Prüfe /proc/1/cgroup
    if [[ -f /proc/1/cgroup ]]; then
        if grep -q ":/lxc/" /proc/1/cgroup 2>/dev/null; then
            IS_CONTAINER=true
            CONTAINER_TYPE="lxc"
            log_message "$MSG_CONTAINER_DETECTED LXC"
            return 0
        elif grep -q ":/docker/" /proc/1/cgroup 2>/dev/null; then
            IS_CONTAINER=true
            CONTAINER_TYPE="docker"
            log_message "$MSG_CONTAINER_DETECTED Docker"
            return 0
        fi
    fi
    
    # Keine Container-Umgebung erkannt
    log_message "$MSG_NATIVE_ENVIRONMENT_DETECTED"
    return 0
}

# ============================================================================
# DISK SPACE CHECK
# ============================================================================

# Funktion zur Prüfung des verfügbaren Speicherplatzes
# Parameter: $1 = benötigte Größe in MB
# Rückgabe: 0 = genug Platz, 1 = zu wenig Platz
check_disk_space() {
    local required_mb=$1
    
    # Ermittle verfügbaren Speicherplatz am Ausgabepfad
    local available_mb=$(df -BM "$OUTPUT_DIR" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/M//')
    
    if [[ -z "$available_mb" ]] || [[ ! "$available_mb" =~ ^[0-9]+$ ]]; then
        log_message "$MSG_WARNING_DISK_SPACE_CHECK_FAILED"
        return 0  # Fahre fort, wenn Prüfung fehlschlägt
    fi
    
    log_message "$MSG_DISK_SPACE_INFO ${available_mb} $MSG_DISK_SPACE_MB_AVAILABLE ${required_mb} $MSG_DISK_SPACE_MB_REQUIRED"
    
    if [[ $available_mb -lt $required_mb ]]; then
        log_message "$MSG_ERROR_INSUFFICIENT_DISK_SPACE ${required_mb} $MSG_DISK_SPACE_MB_AVAILABLE_SHORT ${available_mb} MB"
        return 1
    fi
    
    return 0
}

# ============================================================================
# MEDIUM IDENTIFICATION
# ============================================================================

# Funktion: Ermittle eindeutige Medium-Kennung
# Parameter: $1 = Device-Pfad (z.B. /dev/sr0)
# Rückgabe: String mit "UUID:LABEL:SIZE" oder leer bei Fehler
get_medium_identifier() {
    local device="$1"
    local uuid=""
    local label=""
    local size=""
    
    # Prüfe ob Device existiert und ein Block-Device ist
    if [[ ! -b "$device" ]]; then
        return 1
    fi
    
    # Versuche UUID und Label mit blkid zu ermitteln
    if command -v blkid >/dev/null 2>&1; then
        local blkid_output=$(blkid -p "$device" 2>/dev/null)
        
        if [[ -n "$blkid_output" ]]; then
            # Extrahiere UUID (falls vorhanden)
            uuid=$(echo "$blkid_output" | grep -oP 'UUID="?\K[^"]+' 2>/dev/null || echo "")
            
            # Extrahiere Label (falls vorhanden)
            label=$(echo "$blkid_output" | grep -oP 'LABEL="?\K[^"]+' 2>/dev/null || echo "")
        fi
    fi
    
    # Ermittle Disc-Größe mit blockdev (falls verfügbar)
    if command -v blockdev >/dev/null 2>&1; then
        size=$(blockdev --getsize64 "$device" 2>/dev/null || echo "")
    fi
    
    # Fallback: isoinfo für ISO-Volumen (oft zuverlässiger für optische Medien)
    if [[ -z "$label" ]] && command -v isoinfo >/dev/null 2>&1; then
        label=$(isoinfo -d -i "$device" 2>/dev/null | grep "Volume id:" | sed 's/Volume id: //' | tr -d ' ' || echo "")
    fi
    
    # Baue Identifier-String
    local identifier="${uuid}:${label}:${size}"
    
    # Prüfe ob mindestens ein Wert vorhanden ist
    if [[ "$identifier" == "::" ]]; then
        return 1
    fi
    
    echo "$identifier"
    return 0
}

# ============================================================================
# MEDIUM CHANGE DETECTION
# ============================================================================

# Funktion: Warte auf Medium-Wechsel (nur in Container-Umgebungen)
# Parameter: $1 = Device-Pfad (z.B. /dev/sr0)
#            $2 = Timeout in Sekunden (optional, default: 300 = 5 Minuten)
# Rückgabe: 0 = neues Medium erkannt, 1 = Timeout oder Fehler
wait_for_medium_change() {
    local device="$1"
    local timeout="${2:-300}"
    local poll_interval=3
    
    # Nur in Container-Umgebungen aktiv
    if ! $IS_CONTAINER; then
        return 0  # Native Hardware: eject funktioniert, kein Warten nötig
    fi
    
    log_message "$MSG_CONTAINER_MANUAL_EJECT"
    log_message "$MSG_WAITING_FOR_MEDIUM_CHANGE"
    
    # Ermittle aktuelles Medium
    local old_identifier=$(get_medium_identifier "$device")
    
    if [[ -z "$old_identifier" ]]; then
        log_message "$MSG_WARNING_NO_MEDIUM_IDENTIFIER"
        # Fallback: Warte auf beliebiges Medium
        old_identifier="::"
    fi
    
    local elapsed=0
    local new_identifier=""
    
    while [[ $elapsed -lt $timeout ]]; do
        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        
        # Prüfe auf neues Medium
        new_identifier=$(get_medium_identifier "$device")
        
        # Vergleiche Identifier
        if [[ -n "$new_identifier" ]] && [[ "$new_identifier" != "$old_identifier" ]]; then
            log_message "$MSG_NEW_MEDIUM_DETECTED"
            return 0
        fi
        
        # Log alle 30 Sekunden
        if (( elapsed % 30 == 0 )); then
            log_message "$MSG_STILL_WAITING $elapsed $MSG_SECONDS_OF $timeout $MSG_SECONDS"
        fi
    done
    
    # Timeout erreicht
    log_message "$MSG_TIMEOUT_WAITING_FOR_MEDIUM"
    return 1
}

# ============================================================================
# MEDIUM CHANGE DETECTION - LXC SAFE
# ============================================================================

# Funktion: Warte auf Medium-Wechsel (LXC-Container-optimiert)
# Verwendet Label-basierte Erkennung statt Identifier-Vergleich
# Prüft ob Disk bereits konvertiert wurde (verhindert Duplikate)
# Parameter: $1 = Device-Pfad (z.B. /dev/sr0)
#            $2 = Timeout in Sekunden (optional, default: 300 = 5 Minuten)
# Rückgabe: 0 = neues Medium erkannt, 1 = Timeout oder Fehler
wait_for_medium_change_lxc_safe() {
    local device="$1"
    local timeout="${2:-300}"
    local poll_interval=5
    local elapsed=0
    
    # Sichere ursprüngliche Werte der globalen Variablen
    local original_disc_type="${disc_type:-}"
    local original_disc_label="${disc_label:-}"
    
    log_message "$MSG_CONTAINER_MANUAL_EJECT"
    log_message "$MSG_WAITING_FOR_MEDIUM_CHANGE"
    
    while [[ $elapsed -lt $timeout ]]; do
        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        
        # Prüfe ob überhaupt eine Disk eingelegt ist
        if ! is_disc_inserted; then
            # Keine Disk → weiter warten
            if (( elapsed % 30 == 0 )); then
                log_message "$MSG_STILL_WAITING $elapsed $MSG_SECONDS_OF $timeout $MSG_SECONDS"
            fi
            continue
        fi
        
        # Disk erkannt → Ermittle Typ und Label
        detect_disc_type
        get_disc_label
        
        # Prüfe ob ISO mit diesem Label bereits existiert
        local target_dir=$(get_type_subfolder "$disc_type")
        
        # Prüfe ob target_dir erfolgreich ermittelt wurde
        if [[ -z "$target_dir" ]]; then
            log_message "$MSG_ERROR_TARGET_DIR $disc_type"
            # Stelle ursprüngliche Werte wieder her und fahre fort
            disc_type="$original_disc_type"
            disc_label="$original_disc_label"
            continue
        fi
        
        # Prüfe ob eine Datei mit diesem Label bereits existiert
        local iso_exists=false
        local potential_iso="${target_dir}/${disc_label}.iso"
        
        if [[ -f "$potential_iso" ]]; then
            iso_exists=true
        else
            # Prüfe auch auf nummerierte Duplikate (_1, _2, _3, ...)
            # Breche bei erster Lücke ab (wie get_iso_filename())
            local counter=1
            while [[ -f "${target_dir}/${disc_label}_${counter}.iso" ]]; do
                iso_exists=true
                # Erste Duplikat gefunden - reicht für unsere Prüfung
                break
            done
        fi
        
        if $iso_exists; then
            # Disk wurde bereits konvertiert → weiter warten
            log_message "$MSG_DISC_ALREADY_CONVERTED ${disc_label}.iso $MSG_WAITING_FOR_NEW_DISC"
            
            # Stelle ursprüngliche Werte wieder her
            disc_type="$original_disc_type"
            disc_label="$original_disc_label"
            
            if (( elapsed % 30 == 0 )); then
                log_message "$MSG_STILL_WAITING $elapsed $MSG_SECONDS_OF $timeout $MSG_SECONDS"
            fi
        else
            # Neue Disk gefunden! (ISO existiert noch nicht)
            # Globale Variablen bleiben auf neue Werte gesetzt (disc_type und disc_label)
            log_message "$MSG_NEW_MEDIUM_DETECTED (${disc_type}: ${disc_label})"
            return 0
        fi
    done
    
    # Timeout erreicht - stelle ursprüngliche Werte wieder her
    disc_type="$original_disc_type"
    disc_label="$original_disc_label"
    log_message "$MSG_TIMEOUT_WAITING_FOR_MEDIUM"
    return 1
}

# ============================================================================
# SYSTEM INFORMATION COLLECTION
# ============================================================================

# Funktion: Sammle System-Informationen für API
# Schreibt: system.json im API-Verzeichnis
collect_system_information() {
    local api_dir="${INSTALL_DIR:-/opt/disk2iso}/api"
    local output_file="${api_dir}/system.json"
    
    # Erstelle API-Verzeichnis falls nicht vorhanden
    mkdir -p "$api_dir" 2>/dev/null || return 1
    
    # OS Informationen
    local os_name="Unknown"
    local os_version="Unknown"
    local kernel_version=$(uname -r 2>/dev/null || echo "Unknown")
    local architecture=$(uname -m 2>/dev/null || echo "Unknown")
    local hostname_value=$(hostname 2>/dev/null || echo "Unknown")
    local uptime_value=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "Unknown")
    
    # Distribution erkennen
    if [[ -f /etc/os-release ]]; then
        os_name=$(grep "^NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
        os_version=$(grep "^VERSION=" /etc/os-release | cut -d= -f2 | tr -d '"')
    elif [[ -f /etc/debian_version ]]; then
        os_name="Debian"
        os_version=$(cat /etc/debian_version)
    fi
    
    # Container-Typ
    local container_status="false"
    local container_type_value="none"
    if $IS_CONTAINER; then
        container_status="true"
        container_type_value="$CONTAINER_TYPE"
    fi
    
    # Laufwerk-Informationen
    local optical_drive="none"
    local optical_drive_model="Unknown"
    if [[ -b "$CD_DEVICE" ]]; then
        optical_drive="$CD_DEVICE"
        # Versuche Modell zu ermitteln
        if [[ -f "/sys/block/$(basename $CD_DEVICE)/device/model" ]]; then
            optical_drive_model=$(cat "/sys/block/$(basename $CD_DEVICE)/device/model" 2>/dev/null | xargs)
        fi
    fi
    
    # Speicherplatz
    local output_dir_space="0"
    local output_dir_total="0"
    local output_dir_used_percent="0"
    if [[ -d "$OUTPUT_DIR" ]]; then
        local df_output=$(df -BG "$OUTPUT_DIR" 2>/dev/null | tail -1)
        if [[ -n "$df_output" ]]; then
            output_dir_total=$(echo "$df_output" | awk '{print $2}' | sed 's/G//')
            output_dir_space=$(echo "$df_output" | awk '{print $4}' | sed 's/G//')
            output_dir_used_percent=$(echo "$df_output" | awk '{print $5}' | sed 's/%//')
        fi
    fi
    
    # Software-Versionen (Kernsoftware)
    local cdparanoia_version="Not installed"
    local lame_version="Not installed"
    local dvdbackup_version="Not installed"
    local ddrescue_version="Not installed"
    local genisoimage_version="Not installed"
    local python_version="Not installed"
    local flask_version="Not installed"
    local mosquitto_version="Not installed"
    
    if command -v cdparanoia >/dev/null 2>&1; then
        cdparanoia_version=$(cdparanoia --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
    fi
    
    if command -v lame >/dev/null 2>&1; then
        lame_version=$(lame --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
    fi
    
    if command -v dvdbackup >/dev/null 2>&1; then
        dvdbackup_version=$(dvdbackup --version 2>&1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
    fi
    
    if command -v ddrescue >/dev/null 2>&1; then
        ddrescue_version=$(ddrescue --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
    fi
    
    if command -v genisoimage >/dev/null 2>&1; then
        genisoimage_version=$(genisoimage --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
    fi
    
    if command -v python3 >/dev/null 2>&1; then
        python_version=$(python3 --version 2>&1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
    fi

    if python3 -c "import flask" 2>/dev/null; then
        flask_version=$(python3 -c "import importlib.metadata; print(importlib.metadata.version('flask'))" 2>/dev/null || echo "installed")
    elif [[ -f "/opt/disk2iso/venv/bin/python3" ]]; then
        # Prüfe auch im venv
        if /opt/disk2iso/venv/bin/python3 -c "import flask" 2>/dev/null; then
            flask_version=$(/opt/disk2iso/venv/bin/python3 -c "import importlib.metadata; print(importlib.metadata.version('flask'))" 2>/dev/null || echo "installed")
        fi
    fi

    if command -v mosquitto >/dev/null 2>&1; then
        mosquitto_version=$(mosquitto -h 2>&1 | grep -oP 'version \K\d+\.\d+(\.\d+)?' || echo "installed")
    fi
    
    # Timestamp
    local timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
    
    # Erstelle JSON (manuell, um jq-Abhängigkeit zu vermeiden)
    cat > "$output_file" <<EOF
{
  "os": {
    "distribution": "$os_name",
    "version": "$os_version",
    "kernel": "$kernel_version",
    "architecture": "$architecture",
    "hostname": "$hostname_value",
    "uptime": "$uptime_value"
  },
  "container": {
    "is_container": $container_status,
    "type": "$container_type_value"
  },
  "hardware": {
    "optical_drive": "$optical_drive",
    "drive_model": "$optical_drive_model"
  },
  "storage": {
    "output_dir": "$OUTPUT_DIR",
    "total_gb": $output_dir_total,
    "free_gb": $output_dir_space,
    "used_percent": $output_dir_used_percent
  },
  "software": {
    "cdparanoia": "$cdparanoia_version",
    "lame": "$lame_version",
    "dvdbackup": "$dvdbackup_version",
    "ddrescue": "$ddrescue_version",
    "genisoimage": "$genisoimage_version",
    "python": "$python_version",
    "flask": "$flask_version",
    "mosquitto": "$mosquitto_version"
  },
  "timestamp": "$timestamp"
}
EOF
    
    chmod 644 "$output_file" 2>/dev/null || true
    return 0
}
