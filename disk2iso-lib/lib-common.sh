#!/bin/bash
################################################################################
# Common Functions Library
# Filepath: disk2iso-lib/lib-common.sh
#
# Beschreibung:
#   - copy_data_disc() - Daten-Disc kopieren mit dd
#   - copy_data_disc_ddrescue() - Daten-Disc kopieren mit ddrescue
#   - reset_disc_variables, cleanup_disc_operation
#   - check_disk_space, monitor_copy_progress
#
# Erweitert: 30.12.2025
################################################################################

# ============================================================================
# PATH CONSTANTS
# ============================================================================

readonly DATA_DIR="data"
readonly TEMP_DIR="temp"
readonly MOUNTPOINTS_DIR="temp/mountpoints"

# ============================================================================
# PATH GETTER
# ============================================================================

# Funktion: Ermittle Pfad für Daten-Discs (DATA)
# Rückgabe: Vollständiger Pfad zu data/
get_path_data() {
    echo "${OUTPUT_DIR}/${DATA_DIR}"
}

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

# Lade Sprachdatei für dieses Modul
load_module_language "common"

# Funktion: Prüfe Kern-Abhängigkeiten (kritisch)
# Rückgabe: 0 = OK, 1 = Fehler
check_common_dependencies() {
    local missing=()
    
    # Kritische Tools (müssen vorhanden sein)
    command -v dd >/dev/null 2>&1 || missing+=("dd")
    command -v md5sum >/dev/null 2>&1 || missing+=("md5sum")
    command -v lsblk >/dev/null 2>&1 || missing+=("lsblk")
    command -v eject >/dev/null 2>&1 || missing+=("eject")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "FEHLER: Kritische Tools fehlen: ${missing[*]}"
        echo "Installation: apt-get install coreutils util-linux eject"
        return 1
    fi
    
    # Optionale Tools (Performance-Verbesserung)
    local optional_missing=()
    command -v isoinfo >/dev/null 2>&1 || optional_missing+=("isoinfo")
    command -v ddrescue >/dev/null 2>&1 || optional_missing+=("ddrescue")
    
    if [[ ${#optional_missing[@]} -gt 0 ]]; then
        log_message "INFO: Optionale Tools für bessere Performance: ${optional_missing[*]}"
        log_message "Installation: apt-get install genisoimage gddrescue"
    fi
    
    return 0
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Funktion zur Prüfung des verfügbaren Speicherplatzes
# Parameter: $1 = benötigte Größe in MB
# Rückgabe: 0 = genug Platz, 1 = zu wenig Platz
check_disk_space() {
    local required_mb=$1
    
    # Ermittle verfügbaren Speicherplatz am Ausgabepfad
    local available_mb=$(df -BM "$OUTPUT_DIR" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/M//')
    
    if [[ -z "$available_mb" ]] || [[ ! "$available_mb" =~ ^[0-9]+$ ]]; then
        log_message "WARNUNG: Konnte verfügbaren Speicherplatz nicht ermitteln"
        return 0  # Fahre fort, wenn Prüfung fehlschlägt
    fi
    
    log_message "Speicherplatz: ${available_mb} MB verfügbar, ${required_mb} MB benötigt"
    
    if [[ $available_mb -lt $required_mb ]]; then
        log_message "FEHLER: Nicht genug Speicherplatz! Benötigt: ${required_mb} MB, Verfügbar: ${available_mb} MB"
        return 1
    fi
    
    return 0
}

# ============================================================================
# DATA DISC COPY - DDRESCUE (für Daten-Discs)
# ============================================================================

# Funktion zum Kopieren von Daten-Discs mit ddrescue
# Schneller und robuster als dd
copy_data_disc_ddrescue() {
    log_message "Methode: ddrescue (robust)"
    
    # ddrescue benötigt Map-Datei
    local mapfile="${iso_filename}.mapfile"
    
    # Ermittle Disc-Größe mit isoinfo
    local volume_size=""
    local total_bytes=0
    
    if command -v isoinfo >/dev/null 2>&1; then
        volume_size=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null | grep "Volume size is:" | awk '{print $4}')
        if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
            total_bytes=$((volume_size * 2048))
            log_message "ISO-Volume erkannt: $volume_size Blöcke ($(( total_bytes / 1024 / 1024 )) MB)"
        fi
    fi
    
    # Prüfe Speicherplatz (ISO-Größe + 5% Puffer)
    if [[ $total_bytes -gt 0 ]]; then
        local size_mb=$((total_bytes / 1024 / 1024))
        local required_mb=$((size_mb + size_mb * 5 / 100))
        if ! check_disk_space "$required_mb"; then
            rm -f "$mapfile"
            return 1
        fi
    fi
    
    # Kopiere mit ddrescue
    if [[ $total_bytes -gt 0 ]]; then
        # Mit bekannter Größe
        if ddrescue -b 2048 -s "$total_bytes" -n "$CD_DEVICE" "$iso_filename" "$mapfile" 2>>"$log_filename"; then
            log_message "✓ Daten-Disc mit ddrescue erfolgreich kopiert"
            rm -f "$mapfile"
            return 0
        else
            log_message "FEHLER: ddrescue fehlgeschlagen"
            rm -f "$mapfile"
            return 1
        fi
    else
        # Ohne bekannte Größe
        if ddrescue -b 2048 -n "$CD_DEVICE" "$iso_filename" "$mapfile" 2>>"$log_filename"; then
            log_message "✓ Daten-Disc mit ddrescue erfolgreich kopiert"
            rm -f "$mapfile"
            return 0
        else
            log_message "FEHLER: ddrescue fehlgeschlagen"
            rm -f "$mapfile"
            return 1
        fi
    fi
}

# ============================================================================
# DATA DISC COPY - DD (Methode 3 - Langsamste, immer verfügbar)
# ============================================================================

# Funktion zum Kopieren von Daten-Discs (CD/DVD/BD) mit dd
# Nutzt isoinfo (falls verfügbar) um exakte Volume-Größe zu ermitteln
# Sendet Fortschritt via systemd-notify für Service-Betrieb
copy_data_disc() {
    local block_size=2048
    local volume_size=""
    local total_bytes=0
    
    # Versuche Volume-Größe mit isoinfo zu ermitteln
    if command -v isoinfo >/dev/null 2>&1; then
        volume_size=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null | grep "Volume size is:" | awk '{print $4}')
        
        if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
            total_bytes=$((volume_size * block_size))
            log_message "ISO-Volume erkannt: $volume_size Blöcke à $block_size Bytes ($(( total_bytes / 1024 / 1024 )) MB)"
            
            # Prüfe Speicherplatz (ISO-Größe + 5% Puffer)
            local size_mb=$((total_bytes / 1024 / 1024))
            local required_mb=$((size_mb + size_mb * 5 / 100))
            if ! check_disk_space "$required_mb"; then
                return 1
            fi
            
            # Starte dd im Hintergrund
            dd if="$CD_DEVICE" of="$iso_filename" bs="$block_size" count="$volume_size" conv=noerror,sync status=progress 2>>"$log_filename" &
            local dd_pid=$!
            
            # Überwache Fortschritt und sende systemd-notify Status
            monitor_copy_progress "$dd_pid" "$total_bytes"
            
            # Warte auf dd und hole Exit-Code
            wait "$dd_pid"
            return $?
        fi
    fi
    
    # Fallback: Kopiere komplette Disc (ohne Fortschrittsanzeige, da Größe unbekannt)
    log_message "Kopiere komplette Disc (kein isoinfo verfügbar)"
    if dd if="$CD_DEVICE" of="$iso_filename" bs="$block_size" conv=noerror,sync status=progress 2>>"$log_filename"; then
        return 0
    else
        return 1
    fi
}

# Hilfsfunktion: Überwacht Kopierfortschritt und sendet systemd-notify
monitor_copy_progress() {
    local dd_pid=$1
    local total_bytes=$2
    local total_mb=$((total_bytes / 1024 / 1024))
    
    # Prüfe ob systemd-notify verfügbar ist
    local has_systemd_notify=false
    command -v systemd-notify >/dev/null 2>&1 && has_systemd_notify=true
    
    while kill -0 "$dd_pid" 2>/dev/null; do
        if [[ -f "$iso_filename" ]]; then
            local current_bytes=$(stat -c%s "$iso_filename" 2>/dev/null || echo 0)
            local current_mb=$((current_bytes / 1024 / 1024))
            local percent=0
            
            if [[ $total_bytes -gt 0 ]]; then
                percent=$((current_bytes * 100 / total_bytes))
            fi
            
            # Sende Status an systemd (wenn verfügbar)
            if $has_systemd_notify; then
                systemd-notify --status="Kopiere: ${current_mb} MB / ${total_mb} MB (${percent}%)" 2>/dev/null
            fi
            
            # Log-Eintrag alle 500 MB
            if (( current_mb % 500 == 0 )) && (( current_mb > 0 )); then
                log_message "Fortschritt: ${current_mb} MB / ${total_mb} MB (${percent}%)"
            fi
        fi
        
        sleep 2
    done
    
    # Abschluss-Status
    if $has_systemd_notify; then
        systemd-notify --status="Kopiervorgang abgeschlossen" 2>/dev/null
    fi
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Funktion zum Zurücksetzen aller Disc-Variablen
reset_disc_variables() {
    disc_label=""
    disc_type=""
    iso_filename=""
    md5_filename=""
    log_filename=""
    iso_basename=""
    temp_pathname=""
}

# Funktion zum vollständigen Aufräumen nach Disc-Operation
cleanup_disc_operation() {
    local status="${1:-unknown}"
    
    # 1. Temp-Verzeichnis aufräumen (falls vorhanden)
    if [[ -n "$temp_pathname" ]] && [[ -d "$temp_pathname" ]]; then
        rm -rf "$temp_pathname"
    fi
    
    # 2. Unvollständige ISO-Datei löschen (nur bei Fehler)
    if [[ "$status" == "failure" ]] && [[ -n "$iso_filename" ]] && [[ -f "$iso_filename" ]]; then
        rm -f "$iso_filename"
    fi
    
    # 3. Disc auswerfen (immer)
    if [[ -b "$CD_DEVICE" ]]; then
        eject "$CD_DEVICE" 2>/dev/null
    fi
    
    # 4. Variablen zurücksetzen (immer)
    reset_disc_variables
}
