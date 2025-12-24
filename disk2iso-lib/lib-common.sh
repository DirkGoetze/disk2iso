#!/bin/bash
################################################################################
# Common Functions Library - Minimal (nur Debian Standard-Tools)
# Filepath: disk2iso-lib/lib-common.sh
#
# Beschreibung:
#   Nur dd-basiertes Kopieren (Standard-Tool)
#   - copy_data_disc() - Daten-Disc kopieren mit dd
#   - reset_disc_variables, cleanup_disc_operation
#
# Vereinfacht: 24.12.2025
################################################################################

# ============================================================================
# DATA DISC COPY - NUR DD
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
