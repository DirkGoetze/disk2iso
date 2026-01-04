#!/bin/bash
################################################################################
# disk2iso v1.1.0 - System Information Library
# Filepath: disk2iso-lib/lib-systeminfo.sh
#
# Beschreibung:
#   - Container-Erkennung (LXC, Docker, Podman)
#   - Speicherplatz-Prüfung
#   - Medium-Wechsel-Erkennung (für Container-Umgebungen)
#   - System-Informationen und Monitoring
#
# Version: 1.0.0
# Datum: 02.01.2026
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
        echo "FEHLER: System-Tools fehlen: ${missing[*]}"
        echo "Installation: apt-get install coreutils util-linux"
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
