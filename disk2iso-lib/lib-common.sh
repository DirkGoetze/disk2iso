#!/bin/bash
################################################################################
# disk2iso v1.1.0 - Common Functions Library
# Filepath: disk2iso-lib/lib-common.sh
#
# Beschreibung:
#   - copy_data_disc() - Daten-Disc kopieren mit dd
#   - copy_data_disc_ddrescue() - Daten-Disc kopieren mit ddrescue
#   - reset_disc_variables, cleanup_disc_operation
#   - check_disk_space, monitor_copy_progress
#
# Version: 1.0.0
# Datum: 01.01.2026
################################################################################

# ============================================================================
# PATH CONSTANTS
# ============================================================================

readonly DATA_DIR="data"
readonly TEMP_DIR=".temp"
readonly MOUNTPOINTS_DIR=".temp/mountpoints"

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
        log_message "$MSG_OPTIONAL_TOOLS_INFO ${optional_missing[*]}"
        log_message "$MSG_INSTALL_GENISOIMAGE_GDDRESCUE"
    fi
    
    return 0
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Hinweis: check_disk_space() wurde nach lib-systeminfo.sh verschoben

# ============================================================================
# DATA DISC COPY - DDRESCUE (für Daten-Discs)
# ============================================================================

# Funktion zum Kopieren von Daten-Discs mit ddrescue
# Schneller und robuster als dd
copy_data_disc_ddrescue() {
    log_message "$MSG_METHOD_DDRESCUE"
    
    # ddrescue benötigt Map-Datei
    local mapfile="${iso_filename}.mapfile"
    
    # Ermittle Disc-Größe mit isoinfo
    local volume_size=""
    local total_bytes=0
    
    if command -v isoinfo >/dev/null 2>&1; then
        volume_size=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null | grep "Volume size is:" | awk '{print $4}')
        if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
            total_bytes=$((volume_size * 2048))
            log_message "$MSG_ISO_VOLUME_DETECTED $volume_size $MSG_ISO_BLOCKS ($(( total_bytes / 1024 / 1024 )) $MSG_PROGRESS_MB)"
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
    # Starte ddrescue im Hintergrund
    if [[ $total_bytes -gt 0 ]]; then
        ddrescue -b 2048 -s "$total_bytes" -n "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$log_filename" &
    else
        ddrescue -b 2048 -n "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$log_filename" &
    fi
    local ddrescue_pid=$!
    
    # Überwache Fortschritt (alle 60 Sekunden)
    local start_time=$(date +%s)
    local last_log_time=$start_time
    
    while kill -0 "$ddrescue_pid" 2>/dev/null; do
        sleep 30
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - last_log_time))
        
        # Log alle 60 Sekunden
        if [[ $elapsed -ge 60 ]]; then
            local copied_mb=0
            if [[ -f "$iso_filename" ]]; then
                local file_size=$(stat -c %s "$iso_filename" 2>/dev/null)
                if [[ -n "$file_size" ]]; then
                    copied_mb=$((file_size / 1024 / 1024))
                fi
            fi
            
            local percent=0
            local eta="--:--:--"
            
            if [[ $total_bytes -gt 0 ]] && [[ $copied_mb -gt 0 ]]; then
                local total_mb=$((total_bytes / 1024 / 1024))
                percent=$((copied_mb * 100 / total_mb))
                if [[ $percent -gt 100 ]]; then percent=100; fi
                
                # Berechne geschätzte Restzeit
                local total_elapsed=$((current_time - start_time))
                if [[ $percent -gt 0 ]]; then
                    local estimated_total=$((total_elapsed * 100 / percent))
                    local remaining=$((estimated_total - total_elapsed))
                    local hours=$((remaining / 3600))
                    local minutes=$(((remaining % 3600) / 60))
                    local seconds=$((remaining % 60))
                    eta=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
                fi
                
                log_message "$MSG_DATA_PROGRESS: ${copied_mb} $MSG_PROGRESS_MB / ${total_mb} $MSG_PROGRESS_MB (${percent}%) - $MSG_REMAINING: ${eta}"
                
                # MQTT: Fortschritt senden
                if [[ "$MQTT_SUPPORT" == "true" ]] && declare -f mqtt_publish_progress >/dev/null 2>&1; then
                    mqtt_publish_progress "$percent" "$copied_mb" "$total_mb" "$eta"
                fi
            else
                log_message "$MSG_DATA_PROGRESS: ${copied_mb} $MSG_PROGRESS_MB $MSG_COPIED"
            fi
            
            last_log_time=$current_time
        fi
    done
    
    # Warte auf ddrescue Prozess-Ende
    wait "$ddrescue_pid"
    local ddrescue_exit=$?
    
    # Prüfe Ergebnis
    if [[ $ddrescue_exit -eq 0 ]]; then
        log_message "$MSG_DATA_DISC_SUCCESS_DDRESCUE"
        rm -f "$mapfile"
        return 0
    else
        log_message "$MSG_ERROR_DDRESCUE_FAILED"
        rm -f "$mapfile"
        return 1
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
            log_message "$MSG_ISO_VOLUME_DETECTED $volume_size $MSG_ISO_BLOCKS_SIZE $block_size $MSG_ISO_BYTES ($(( total_bytes / 1024 / 1024 )) $MSG_PROGRESS_MB)"
            
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
    log_message "$MSG_COPYING_COMPLETE_DISC"
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
                log_message "$MSG_PROGRESS ${current_mb} $MSG_PROGRESS_OF ${total_mb} $MSG_PROGRESS_MB (${percent}$MSG_PROGRESS_PERCENT)"
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
        # Unmount alle eventuellen Mountpoints im Temp-Verzeichnis
        if command -v findmnt >/dev/null 2>&1; then
            # Finde und unmounte alle Mountpoints unterhalb von temp_pathname
            findmnt -R -n -o TARGET "$temp_pathname" 2>/dev/null | sort -r | while read -r mountpoint; do
                umount "$mountpoint" 2>/dev/null || umount -l "$mountpoint" 2>/dev/null
            done
        else
            # Fallback: Versuche bekannte Mountpoints zu unmounten
            find "$temp_pathname" -type d 2>/dev/null | while read -r dir; do
                umount "$dir" 2>/dev/null || true
            done
        fi
        
        # Gib dem System kurz Zeit zum Unmounten
        sleep 1
        
        # Lösche Temp-Verzeichnis (mit force)
        rm -rf "$temp_pathname" 2>/dev/null || {
            # Fallback: Versuche mit sudo falls Permission-Fehler
            log_message "$MSG_WARNING_TEMP_DIR_DELETE_FAILED"
            sudo rm -rf "$temp_pathname" 2>/dev/null || true
        }
    fi
    
    # 2. Unvollständige ISO-Datei löschen (nur bei Fehler)
    if [[ "$status" == "failure" ]] && [[ -n "$iso_filename" ]] && [[ -f "$iso_filename" ]]; then
        rm -f "$iso_filename"
    fi
    
    # 3. Disc auswerfen (immer)
    if [[ -b "$CD_DEVICE" ]]; then
        eject "$CD_DEVICE" 2>/dev/null
        
        # In Container-Umgebungen: Warte auf manuellen Medium-Wechsel
        if [[ "$status" == "success" ]]; then
            # Nutze LXC-sichere Methode wenn in Container
            if $IS_CONTAINER; then
                wait_for_medium_change_lxc_safe "$CD_DEVICE" 300  # 5 Minuten Timeout
            else
                wait_for_medium_change "$CD_DEVICE" 300  # 5 Minuten Timeout
            fi
        fi
    fi
    
    # 4. Variablen zurücksetzen (immer)
    reset_disc_variables
}
