#!/bin/bash
################################################################################
# Common Functions Library - Mit Video-DVD Unterstützung
# Filepath: disk2iso-lib/lib-common.sh
#
# Beschreibung:
#   - copy_data_disc() - Daten-Disc kopieren mit dd
#   - copy_video_dvd() - Video-DVD mit dvdbackup + genisoimage (Fallback: dd)
#   - reset_disc_variables, cleanup_disc_operation
#
# Erweitert: 29.12.2025
################################################################################

# ============================================================================
# VIDEO DVD COPY - DVDBACKUP + GENISOIMAGE (Methode 1 - Schnellste)
# ============================================================================

# Funktion zum Kopieren von Video-DVDs mit Entschlüsselung
# Nutzt dvdbackup (mit libdvdcss) + genisoimage
# Fallback: copy_video_dvd_ddrescue() oder copy_data_disc()
copy_video_dvd() {
    # Prüfe ob dvdbackup und genisoimage verfügbar sind
    if ! command -v dvdbackup >/dev/null 2>&1 || ! command -v genisoimage >/dev/null 2>&1; then
        log_message "INFO: dvdbackup nicht verfügbar - Versuche ddrescue"
        copy_video_dvd_ddrescue
        return $?
    fi
    
    log_message "Methode 1: Kopiere Video-DVD mit dvdbackup (entschlüsselt)"
    
    # Erstelle temporäres Verzeichnis für DVD-Struktur
    local temp_dvd="${temp_pathname}/dvd_rip"
    mkdir -p "$temp_dvd"
    
    # Kopiere DVD-Struktur mit dvdbackup (entschlüsselt)
    # Timeout nach 60 Sekunden (verhindert Hängen ohne libdvdcss2)
    log_message "Extrahiere DVD-Struktur..."
    if ! timeout 60 dvdbackup -M -i "$CD_DEVICE" -o "$temp_dvd" 2>>"$log_filename"; then
        log_message "FEHLER: dvdbackup fehlgeschlagen (Timeout oder kein libdvdcss2) - Fallback auf ddrescue"
        rm -rf "$temp_dvd"
        copy_video_dvd_ddrescue
        return $?
    fi
    
    # Finde VIDEO_TS Ordner (dvdbackup erstellt Unterordner mit Titel)
    local video_ts_dir
    video_ts_dir=$(find "$temp_dvd" -type d -name "VIDEO_TS" | head -1)
    
    if [[ -z "$video_ts_dir" ]]; then
        log_message "FEHLER: Kein VIDEO_TS Ordner gefunden - Fallback auf ddrescue"
        rm -rf "$temp_dvd"
        copy_video_dvd_ddrescue
        return $?
    fi
    
    # Erstelle ISO aus VIDEO_TS Struktur
    log_message "Erstelle entschlüsselte ISO aus VIDEO_TS..."
    if genisoimage -dvd-video -V "$disc_label" -o "$iso_filename" "$(dirname "$video_ts_dir")" 2>>"$log_filename"; then
        log_message "✓ Entschlüsselte Video-DVD ISO erfolgreich erstellt"
        rm -rf "$temp_dvd"
        return 0
    else
        log_message "FEHLER: genisoimage fehlgeschlagen - Fallback auf ddrescue"
        rm -rf "$temp_dvd"
        copy_video_dvd_ddrescue
        return $?
    fi
}

# ============================================================================
# VIDEO DVD COPY - DDRESCUE (Methode 2 - Mittelschnell)
# ============================================================================

# Funktion zum Kopieren von Video-DVDs mit ddrescue
# Schneller als dd bei Lesefehlern, ISO bleibt verschlüsselt
# Fallback: copy_data_disc()
copy_video_dvd_ddrescue() {
    # Prüfe ob ddrescue verfügbar ist
    if ! command -v ddrescue >/dev/null 2>&1; then
        log_message "INFO: ddrescue nicht verfügbar - Fallback auf dd"
        copy_data_disc
        return $?
    fi
    
    log_message "Methode 2: Kopiere Video-DVD mit ddrescue (verschlüsselt, schnell)"
    
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
    
    # Kopiere mit ddrescue
    if [[ $total_bytes -gt 0 ]]; then
        # Mit bekannter Größe
        if ddrescue -b 2048 -s "$total_bytes" -n "$CD_DEVICE" "$iso_filename" "$mapfile" 2>>"$log_filename"; then
            log_message "✓ Video-DVD mit ddrescue erfolgreich kopiert"
            rm -f "$mapfile"
            return 0
        fi
    else
        # Ohne bekannte Größe (kopiert bis Ende)
        if ddrescue -b 2048 -n "$CD_DEVICE" "$iso_filename" "$mapfile" 2>>"$log_filename"; then
            log_message "✓ Video-DVD mit ddrescue erfolgreich kopiert"
            rm -f "$mapfile"
            return 0
        fi
    fi
    
    # Fallback wenn ddrescue fehlschlägt
    log_message "FEHLER: ddrescue fehlgeschlagen - Fallback auf dd"
    rm -f "$mapfile"
    copy_data_disc
    return $?
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
