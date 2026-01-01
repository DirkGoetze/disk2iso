#!/bin/bash
################################################################################
# disk2iso v1.0.0 - Blu-ray Library
# Filepath: disk2iso-lib/lib-bluray.sh
#
# Beschreibung:
#   Funktionen für Blu-ray-Ripping und -Konvertierung
#   - copy_bluray_ddrescue() - Blu-ray mit ddrescue (verschlüsselt, robust)
#   - copy_bluray_dd() - Blu-ray mit dd (verschlüsselt, langsam)
#
# Version: 1.0.0
# Datum: 01.01.2026
################################################################################

# ============================================================================
# PATH CONSTANTS
# ============================================================================

readonly BD_DIR="bd"

# ============================================================================
# PATH GETTER
# ============================================================================

# Funktion: Ermittle Pfad für Blu-ray Videos
# Rückgabe: Vollständiger Pfad zu bd/ oder Fallback zu data/
get_path_bd() {
    if [[ "$BLURAY_SUPPORT" == true ]] && [[ -n "$BD_DIR" ]]; then
        echo "${OUTPUT_DIR}/${BD_DIR}"
    else
        # Fallback auf data/ wenn Blu-ray-Modul nicht geladen
        echo "${OUTPUT_DIR}/data"
    fi
}

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

# Lade Sprachdatei für dieses Modul
load_module_language "bluray"

# Funktion: Prüfe Blu-ray Abhängigkeiten
# Rückgabe: 0 = Mindestens eine Methode verfügbar, 1 = Keine Methode verfügbar
check_bluray_dependencies() {
    local available_methods=()
    local missing_methods=()
    
    # Methode 1: ddrescue (robust, verschlüsselt)
    if command -v ddrescue >/dev/null 2>&1; then
        available_methods+=("ddrescue (verschlüsselt, robust)")
    else
        missing_methods+=("ddrescue")
    fi
    
    # Methode 2: dd (immer verfügbar, bereits in lib-common geprüft)
    available_methods+=("dd (verschlüsselt, langsam)")
    
    # Logging
    if [[ ${#available_methods[@]} -gt 0 ]]; then
        log_message "$MSG_BLURAY_SUPPORT_INFO ${available_methods[*]}"
        
        if [[ ${#missing_methods[@]} -gt 0 ]]; then
            log_message "$MSG_RECOMMENDED_INSTALLATION ${missing_methods[*]}"
            log_message "$MSG_INSTALL_DDRESCUE_INFO"
        fi
        
        return 0
    else
        log_message "$MSG_ERROR_NO_BLURAY_METHOD_AVAILABLE"
        return 1
    fi
}

# ============================================================================
# BLURAY COPY - DDRESCUE (Methode 1 - Verschlüsselt, Robust)
# ============================================================================

# Funktion zum Kopieren von Blu-rays mit ddrescue
# Schneller als dd bei Lesefehlern, ISO bleibt verschlüsselt
# KEIN Fallback - Methode wird zu Beginn gewählt
copy_bluray_ddrescue() {
    log_message "$MSG_METHOD_DDRESCUE_ENCRYPTED"
    
    # ddrescue benötigt Map-Datei
    local mapfile="${iso_filename}.mapfile"
    
    # Ermittle Disc-Größe mit isoinfo (falls verfügbar)
    local volume_size=""
    local total_bytes=0
    
    if command -v isoinfo >/dev/null 2>&1; then
        volume_size=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null | grep "Volume size is:" | awk '{print $4}')
        if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
            total_bytes=$((volume_size * 2048))
            log_message "$MSG_ISO_VOLUME_DETECTED $volume_size $MSG_ISO_BLOCKS ($(( total_bytes / 1024 / 1024 )) $MSG_PROGRESS_MB)"
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
                log_message "$MSG_DISC_SIZE_DETECTED $(( total_bytes / 1024 / 1024 )) $MSG_DISC_SIZE_MB"
            fi
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
    log_message "$MSG_START_DDRESCUE_BLURAY"
    
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
            flock -x "$CD_DEVICE" ddrescue -b 2048 -r 1 -s "$total_bytes" "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$log_filename" &
        else
            flock -x "$CD_DEVICE" ddrescue -b 2048 -r 1 "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$log_filename" &
        fi
    else
        if [[ $total_bytes -gt 0 ]]; then
            ddrescue -b 2048 -r 1 -s "$total_bytes" "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$log_filename" &
        else
            ddrescue -b 2048 -r 1 "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$log_filename" &
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
                
                log_message "$MSG_BLURAY_PROGRESS ${copied_mb} $MSG_PROGRESS_MB / ${total_mb} $MSG_PROGRESS_MB (${percent}%) - $MSG_REMAINING: ${eta}"
            else
                log_message "$MSG_BLURAY_PROGRESS ${copied_mb} $MSG_PROGRESS_MB $MSG_COPIED"
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
        log_message "$MSG_BLURAY_DDRESCUE_SUCCESS"
        rm -f "$mapfile"
        return 0
    else
        log_message "$MSG_ERROR_DDRESCUE_FAILED"
        rm -f "$mapfile"
        return 1
    fi
}
