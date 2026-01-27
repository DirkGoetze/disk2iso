#!/bin/bash
# ===========================================================================
# Blu-ray Library
# ===========================================================================
# Filepath: lib/libbluray.sh
#
# Beschreibung:
#   Funktionen für Blu-ray-Ripping und -Konvertierung
#   - copy_bluray_ddrescue() - Blu-ray mit ddrescue (verschlüsselt, robust)
#   - copy_bluray_dd() - Blu-ray mit dd (verschlüsselt, langsam)
#   - Unterstützung für große Datenmengen (bis 50GB)
#   - Integration mit TMDB Metadata-Abfrage
#
# ---------------------------------------------------------------------------
# Dependencies: liblogging, libfolders, libcommon (optional: libtmdb)
# ---------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.2.1
# Last Change: 2026-01-26 20:00
# ===========================================================================

# ===========================================================================
# DEPENDENCY CHECK
# ===========================================================================
readonly MODULE_NAME_BLURAY="bluray"         # Globale Variable für Modulname
SUPPORT_BLURAY=false                                  # Globales Support Flag

# ===========================================================================
# check_dependencies_bluray
# ---------------------------------------------------------------------------
# Funktion.: Prüfe alle Modul-Abhängigkeiten (Modul-Dateien, Ausgabe-Ordner, 
# .........  kritische und optionale Software für die Ausführung des Modul),
# .........  lädt nach erfolgreicher Prüfung die Sprachdatei für das Modul.
# Parameter: keine
# Rückgabe.: 0 = Verfügbar (Module nutzbar)
# .........  1 = Nicht verfügbar (Modul deaktiviert)
# Extras...: Setzt SUPPORT_BLURAY=true bei erfolgreicher Prüfung
# ===========================================================================
check_dependencies_bluray() {
    log_debug "$MSG_DEBUG_BLURAY_CHECK_START"

    #-- Alle Modul Abhängigkeiten prüfen -------------------------------------
    check_module_dependencies "$MODULE_NAME_BLURAY" || return 1

    #-- Setze Verfügbarkeit -------------------------------------------------
    SUPPORT_BLURAY=true
    log_debug "$MSG_DEBUG_BLURAY_CHECK_COMPLETE"
    
    #-- Abhängigkeiten erfüllt ----------------------------------------------
    log_info "$MSG_BLURAY_SUPPORT_AVAILABLE"
    return 0
}

# ============================================================================
# PATH GETTER
# ============================================================================

# ===========================================================================
# get_path_bluray
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Ausgabepfad des Modul für die Verwendung in anderen
# .........  abhängigen Modulen
# Parameter: keine
# Rückgabe.: Vollständiger Pfad zum Modul Verzeichnis
# Hinweis..: Ordner wird bereits in check_module_dependencies() erstellt
# ===========================================================================
get_path_bluray() {
    echo "${OUTPUT_DIR}/${MODULE_NAME_BLURAY}"
}

# TODO: Ab hier ist das Modul noch nicht fertig implementiert!

# ============================================================================
# BLURAY COPY - DDRESCUE (Methode 1 - Verschlüsselt, Robust)
# ============================================================================

# Funktion zum Kopieren von Blu-rays mit ddrescue
# Schneller als dd bei Lesefehlern, ISO bleibt verschlüsselt
# KEIN Fallback - Methode wird zu Beginn gewählt
copy_bluray_ddrescue() {
    # Initialisiere Kopiervorgang-Log
    init_copy_log "$disc_label" "bluray"
    
    log_copying "$MSG_METHOD_DDRESCUE_ENCRYPTED"
    
    # ddrescue benötigt Map-Datei (im .temp Verzeichnis, wird auto-gelöscht)
    local mapfile="${temp_pathname}/$(basename "${iso_filename}").mapfile"
    
    # Ermittle Disc-Größe mit isoinfo (falls verfügbar)
    local volume_size=""
    local total_bytes=0
    
    if command -v isoinfo >/dev/null 2>&1; then
        volume_size=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null | grep "Volume size is:" | awk '{print $4}')
        if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
            total_bytes=$((volume_size * 2048))
            log_copying "$MSG_ISO_VOLUME_DETECTED $volume_size $MSG_ISO_BLOCKS ($(( total_bytes / 1024 / 1024 )) $MSG_PROGRESS_MB)"
        fi
    fi
    
    # Fallback: Bei UDF-Blu-rays liefert isoinfo keine Größe - verwende blockdev
    if [[ $total_bytes -eq 0 ]]; then
        local blockdev_cmd=""
        if command -v blockdev >/dev/null 2>&1; then
            blockdev_cmd="blockdev"
        elif [[ -x /usr/sbin/blockdev ]]; then
            blockdev_cmd="/usr/sbin/blockdev"
        fi
        
        if [[ -n "$blockdev_cmd" ]] && [[ -b "$CD_DEVICE" ]]; then
            local device_size=$($blockdev_cmd --getsize64 "$CD_DEVICE" 2>/dev/null)
            if [[ -n "$device_size" ]] && [[ "$device_size" =~ ^[0-9]+$ ]]; then
                total_bytes=$device_size
                volume_size=$((device_size / 2048))
                log_copying "$MSG_DISC_SIZE_DETECTED $(( total_bytes / 1024 / 1024 )) $MSG_DISC_SIZE_MB"
            fi
        fi
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
    log_copying "$MSG_START_DDRESCUE_BLURAY"
    
    # ddrescue Parameter:
    # -b 2048: Blockgröße für optische Medien
    # -r 1: Max 1 Retry bei Lesefehlern (verhindert wildes Hin-und-Her-Springen)
    # -s: Größe begrenzen (falls bekannt)
    
    # Verhindere konkurrierende Zugriffe durch udisks/automount während ddrescue läuft
    # Öffne das Device mit flock (exklusives Lock) falls verfügbar
    local use_flock=false
    if command -v flock >/dev/null 2>&1; then
        use_flock=true
    fi
    
    # Starte ddrescue im Hintergrund (mit oder ohne flock)
    if $use_flock; then
        if [[ $total_bytes -gt 0 ]]; then
            flock -x "$CD_DEVICE" ddrescue -b 2048 -r 1 -s "$total_bytes" "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$copy_log_filename" &
        else
            flock -x "$CD_DEVICE" ddrescue -b 2048 -r 1 "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$copy_log_filename" &
        fi
    else
        if [[ $total_bytes -gt 0 ]]; then
            ddrescue -b 2048 -r 1 -s "$total_bytes" "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$copy_log_filename" &
        else
            ddrescue -b 2048 -r 1 "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$copy_log_filename" &
        fi
    fi
    local ddrescue_pid=$!
    
    # Überwache Fortschritt (alle 60 Sekunden)
    # stat liest nur Filesystem-Metadaten, nicht die Datei selbst - stört ddrescue nicht
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
                
                log_info "$MSG_BLURAY_PROGRESS ${copied_mb} $MSG_PROGRESS_MB / ${total_mb} $MSG_PROGRESS_MB (${percent}%) - $MSG_REMAINING: ${eta}"
                
                # API: Fortschritt senden (IMMER)
                if declare -f api_update_progress >/dev/null 2>&1; then
                    api_update_progress "$percent" "$copied_mb" "$total_mb" "$eta"
                fi
                
                # MQTT: Fortschritt senden (optional)
                if [[ "$SUPPORT_MQTT" == "true" ]] && declare -f mqtt_publish_progress >/dev/null 2>&1; then
                    mqtt_publish_progress "$percent" "$copied_mb" "$total_mb" "$eta"
                fi
            else
                log_info "$MSG_BLURAY_PROGRESS ${copied_mb} $MSG_PROGRESS_MB $MSG_COPIED"
            fi
            
            last_log_time=$current_time
        fi
    done
    
    # Warte auf ddrescue Prozess-Ende (blockiert bis ddrescue fertig ist)
    # WICHTIG: Kein is_disc_inserted() Check während ddrescue läuft!
    wait "$ddrescue_pid"
    local ddrescue_exit=$?
    
    # Prüfe Ergebnis
    if [[ $ddrescue_exit -eq 0 ]]; then
        log_copying "$MSG_BLURAY_DDRESCUE_SUCCESS"
        
        # Erstelle Metadaten für Archiv-Ansicht
        if declare -f create_dvd_archive_metadata >/dev/null 2>&1; then
            local movie_title=$(extract_movie_title "$disc_label")
            create_dvd_archive_metadata "$movie_title" "bd-video" || true
        fi
        
        # Mapfile wird mit temp_pathname automatisch gelöscht
        finish_copy_log
        return 0
    else
        log_error "$MSG_ERROR_DDRESCUE_FAILED"
        # Mapfile wird mit temp_pathname automatisch gelöscht
        finish_copy_log
        return 1
    fi
}
