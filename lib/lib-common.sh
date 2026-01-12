#!/bin/bash
################################################################################
# disk2iso v1.3.0 - Common Functions Library
# Filepath: lib/lib-common.sh
#
# Beschreibung:
#   - copy_data_disc() - Daten-Disc kopieren mit dd
#   - copy_data_disc_ddrescue() - Daten-Disc kopieren mit ddrescue
#   - reset_disc_variables, cleanup_disc_operation
#   - check_disk_space, monitor_copy_progress
#
# Version: 1.3.0
# Datum: 06.01.2026
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
# Nutzt ensure_subfolder aus lib-folders.sh für konsistente Ordner-Verwaltung
get_path_data() {
    ensure_subfolder "$DATA_DIR"
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
        log_message "$MSG_ERROR_CRITICAL_TOOLS_MISSING ${missing[*]}"
        log_message "$MSG_INSTALLATION_CORE_TOOLS"
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

# Funktion: Berechne und logge Kopierfortschritt (zentral für alle Methoden)
# Parameter: $1 = Aktuell kopierte Bytes
#            $2 = Gesamtgröße in Bytes
#            $3 = Start-Zeit (Unix-Timestamp)
#            $4 = Log-Präfix (z.B. "DATA", "DVD", "BLURAY")
# Rückgabe: Setzt $percent und $eta als lokale Variablen
calculate_and_log_progress() {
    local current_bytes=$1
    local total_bytes=$2
    local start_time=$3
    local log_prefix=$4
    
    # Konvertiere zu MB für Anzeige
    local current_mb=$((current_bytes / 1024 / 1024))
    local total_mb=$((total_bytes / 1024 / 1024))
    
    # Initialisiere Ausgabewerte
    percent=0
    eta="--:--:--"
    
    # Berechne Prozent und ETA wenn möglich
    if [[ $total_bytes -gt 0 ]] && [[ $current_bytes -gt 0 ]]; then
        percent=$((current_bytes * 100 / total_bytes))
        if [[ $percent -gt 100 ]]; then percent=100; fi
        
        # Berechne geschätzte Restzeit
        local current_time=$(date +%s)
        local total_elapsed=$((current_time - start_time))
        if [[ $percent -gt 0 ]]; then
            local estimated_total=$((total_elapsed * 100 / percent))
            local remaining=$((estimated_total - total_elapsed))
            local hours=$((remaining / 3600))
            local minutes=$(((remaining % 3600) / 60))
            local seconds=$((remaining % 60))
            eta=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
        fi
        
        # Log-Nachricht mit Präfix
        log_message "${log_prefix} $MSG_PROGRESS: ${current_mb} $MSG_PROGRESS_MB $MSG_PROGRESS_OF ${total_mb} $MSG_PROGRESS_MB (${percent}%) - $MSG_REMAINING: ${eta}"
        
        # API: Fortschritt senden (IMMER)
        if declare -f api_update_progress >/dev/null 2>&1; then
            api_update_progress "$percent" "$current_mb" "$total_mb" "$eta"
        fi
        
        # MQTT: Fortschritt senden (optional)
        if [[ "$MQTT_SUPPORT" == "true" ]] && declare -f mqtt_publish_progress >/dev/null 2>&1; then
            mqtt_publish_progress "$percent" "$current_mb" "$total_mb" "$eta"
        fi
        
        # systemd-notify: Status aktualisieren (wenn verfügbar)
        if command -v systemd-notify >/dev/null 2>&1; then
            systemd-notify --status="${log_prefix}: ${current_mb} MB / ${total_mb} MB (${percent}%)" 2>/dev/null
        fi
    else
        # Fallback: Nur kopierte Größe
        log_message "${log_prefix} $MSG_PROGRESS: ${current_mb} $MSG_PROGRESS_MB $MSG_COPIED"
    fi
}

# Funktion: Ermittle Disc-Größe mit isoinfo
# Rückgabe: Setzt globale Variablen $volume_size (Blöcke), $total_bytes und $block_size
#           Return-Code: 0 = Größe ermittelt, 1 = Keine Größe verfügbar
get_disc_size() {
    block_size=2048  # Fallback-Wert für optische Medien
    volume_size=""
    total_bytes=0
    
    if command -v isoinfo >/dev/null 2>&1; then
        local isoinfo_output
        isoinfo_output=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null)
        
        # Lese Block Size dynamisch aus (falls verfügbar)
        local detected_block_size
        detected_block_size=$(echo "$isoinfo_output" | grep -i "Logical block size is:" | awk '{print $5}')
        if [[ -n "$detected_block_size" ]] && [[ "$detected_block_size" =~ ^[0-9]+$ ]]; then
            block_size=$detected_block_size
        fi
        
        # Lese Volume Size aus
        volume_size=$(echo "$isoinfo_output" | grep "Volume size is:" | awk '{print $4}')
        if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
            total_bytes=$((volume_size * block_size))
            return 0
        fi
    fi
    
    # Keine Größe ermittelt
    volume_size=""
    total_bytes=0
    return 1
}

# ============================================================================
# DATA DISC COPY - DDRESCUE (für Daten-Discs)
# ============================================================================

# Funktion zum Kopieren von Daten-Discs mit ddrescue
# Schneller und robuster als dd
copy_data_disc_ddrescue() {
    log_message "$MSG_METHOD_DDRESCUE"
    
    # ddrescue benötigt Map-Datei (im .temp Verzeichnis, wird auto-gelöscht)
    local mapfile="${temp_pathname}/$(basename "${iso_filename}").mapfile"
    
    # Ermittle Disc-Größe mit isoinfo
    get_disc_size
    if [[ $total_bytes -gt 0 ]]; then
        log_message "$MSG_ISO_VOLUME_DETECTED $volume_size $MSG_ISO_BLOCKS_SIZE 2048 $MSG_ISO_BYTES ($(( total_bytes / 1024 / 1024 )) $MSG_PROGRESS_MB)"
    fi
    
    # Prüfe Speicherplatz (ISO-Größe + 5% Puffer)
    if [[ $total_bytes -gt 0 ]]; then
        local size_mb=$((total_bytes / 1024 / 1024))
        local required_mb=$((size_mb + size_mb * 5 / 100))
        if ! check_disk_space "$required_mb"; then
            # Mapfile wird mit temp_pathname automatisch gelöscht
            return 1
        fi
    fi
    
    # Kopiere mit ddrescue
    # Starte ddrescue im Hintergrund
    # -b: Blockgröße (dynamisch ermittelt)
    # -r: Retry-Count aus Konfiguration
    # -n: No-scrape (erster Durchlauf ohne Retry)
    if [[ $total_bytes -gt 0 ]]; then
        ddrescue -b "$block_size" -r "$DDRESCUE_RETRIES" -s "$total_bytes" "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$log_filename" &
    else
        ddrescue -b "$block_size" -r "$DDRESCUE_RETRIES" "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$log_filename" &
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
            local current_bytes=0
            if [[ -f "$iso_filename" ]]; then
                current_bytes=$(stat -c %s "$iso_filename" 2>/dev/null || echo 0)
            fi
            
            # Nutze zentrale Fortschrittsberechnung
            calculate_and_log_progress "$current_bytes" "$total_bytes" "$start_time" "$MSG_DATA_PROGRESS"
            
            last_log_time=$current_time
        fi
    done
    
    # Warte auf ddrescue Prozess-Ende
    wait "$ddrescue_pid"
    local ddrescue_exit=$?
    
    # Prüfe Ergebnis
    if [[ $ddrescue_exit -eq 0 ]]; then
        log_message "$MSG_DATA_DISC_SUCCESS_DDRESCUE"
        # Mapfile wird mit temp_pathname automatisch gelöscht
        return 0
    else
        log_message "$MSG_ERROR_DDRESCUE_FAILED"
        # Mapfile wird mit temp_pathname automatisch gelöscht
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
    # Versuche Volume-Größe mit isoinfo zu ermitteln
    get_disc_size
    
    if [[ $total_bytes -gt 0 ]]; then
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
    
    # Fallback: Kopiere komplette Disc (ohne Fortschrittsanzeige, da Größe unbekannt)
    log_message "$MSG_COPYING_COMPLETE_DISC"
    if dd if="$CD_DEVICE" of="$iso_filename" bs="$block_size" conv=noerror,sync status=progress 2>>"$log_filename"; then
        return 0
    else
        return 1
    fi
}

# Hilfsfunktion: Überwacht Kopierfortschritt für dd-Methode
monitor_copy_progress() {
    local dd_pid=$1
    local total_bytes=$2
    local start_time=$(date +%s)
    local last_log_mb=0
    
    while kill -0 "$dd_pid" 2>/dev/null; do
        if [[ -f "$iso_filename" ]]; then
            local current_bytes=$(stat -c%s "$iso_filename" 2>/dev/null || echo 0)
            local current_mb=$((current_bytes / 1024 / 1024))
            
            # Log-Eintrag alle 500 MB
            if (( current_mb >= last_log_mb + 500 )); then
                calculate_and_log_progress "$current_bytes" "$total_bytes" "$start_time" "$MSG_DATA_PROGRESS"
                last_log_mb=$current_mb
            fi
        fi
        
        sleep 2
    done
    
    # Abschluss-Status
    if command -v systemd-notify >/dev/null 2>&1; then
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
        if eject "$CD_DEVICE" 2>/dev/null; then
            log_message "$MSG_DISC_EJECTED"
        else
            log_message "$MSG_EJECT_FAILED"
        fi
        
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
