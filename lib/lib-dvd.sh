#!/bin/bash
################################################################################
# disk2iso v1.3.0 - DVD Library
# Filepath: lib/lib-dvd.sh
#
# Beschreibung:
#   Funktionen für DVD-Ripping und -Konvertierung
#   - copy_video_dvd() - Video-DVD mit dvdbackup + genisoimage (entschlüsselt)
#   - copy_video_dvd_ddrescue() - Video-DVD/BD mit ddrescue (verschlüsselt)
#
# Version: 1.3.0
# Datum: 06.01.2026
################################################################################

# ============================================================================
# PATH CONSTANTS
# ============================================================================

readonly DVD_DIR="dvd"
readonly FAILED_DISCS_FILE=".failed_dvds"

# ============================================================================
# FEHLER-TRACKING SYSTEM
# ============================================================================

# Funktion: Ermittle eindeutigen Identifier für DVD
# Rückgabe: String mit disc_label und disc_type (z.B. "supernatural_season_10_disc_3:dvd-video")
get_dvd_identifier() {
    echo "${disc_label}:${disc_type}"
}

# Funktion: Prüfe ob DVD bereits fehlgeschlagen ist
# Parameter: $1 = DVD-Identifier
# Rückgabe: Anzahl der bisherigen Fehlversuche (0-2)
get_dvd_failure_count() {
    local identifier="$1"
    local failed_file="${OUTPUT_DIR}/${FAILED_DISCS_FILE}"
    
    if [[ ! -f "$failed_file" ]]; then
        echo 0
        return
    fi
    
    local count=$(grep -c "^${identifier}|" "$failed_file" 2>/dev/null || true)
    if [[ -z "$count" || "$count" == "0" ]]; then
        echo 0
    else
        echo "$count"
    fi
}

# Funktion: Registriere DVD-Fehlschlag
# Parameter: $1 = DVD-Identifier
#            $2 = Fehlgeschlagene Methode (dvdbackup/ddrescue)
register_dvd_failure() {
    local identifier="$1"
    local method="$2"
    local failed_file="${OUTPUT_DIR}/${FAILED_DISCS_FILE}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Format: identifier|timestamp|method
    echo "${identifier}|${timestamp}|${method}" >> "$failed_file"
}

# Funktion: Entferne DVD aus Fehler-Liste (nach erfolgreichem Kopieren)
# Parameter: $1 = DVD-Identifier
clear_dvd_failures() {
    local identifier="$1"
    local failed_file="${OUTPUT_DIR}/${FAILED_DISCS_FILE}"
    
    if [[ -f "$failed_file" ]]; then
        sed -i "/^${identifier}|/d" "$failed_file"
    fi
}

# ============================================================================
# PATH GETTER
# ============================================================================

# Funktion: Ermittle Pfad für Video-DVDs
# Rückgabe: Vollständiger Pfad zu dvd/ oder Fallback zu data/
# Nutzt ensure_subfolder aus lib-folders.sh für konsistente Ordner-Verwaltung
get_path_dvd() {
    if [[ "$VIDEO_DVD_SUPPORT" == true ]] && [[ -n "$DVD_DIR" ]]; then
        ensure_subfolder "$DVD_DIR"
    else
        # Fallback auf data/ wenn DVD-Modul nicht geladen
        ensure_subfolder "data"
    fi
}

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

# Lade Sprachdatei für dieses Modul
load_module_language "dvd"

# Funktion: Prüfe Video-DVD/BD Abhängigkeiten
# Rückgabe: 0 = Mindestens eine Methode verfügbar, 1 = Keine Methode verfügbar
check_video_dvd_dependencies() {
    local available_methods=()
    local missing_methods=()
    
    # Methode 1: dvdbackup (Entschlüsselung)
    if command -v dvdbackup >/dev/null 2>&1 && command -v genisoimage >/dev/null 2>&1; then
        available_methods+=("dvdbackup (entschlüsselt)")
    else
        missing_methods+=("dvdbackup+genisoimage")
    fi
    
    # Methode 2: ddrescue (robust)
    if command -v ddrescue >/dev/null 2>&1; then
        available_methods+=("ddrescue (verschlüsselt, robust)")
    else
        missing_methods+=("ddrescue")
    fi
    
    # Methode 3: dd (immer verfügbar, bereits in lib-common geprüft)
    available_methods+=("dd (verschlüsselt, langsam)")
    
    # Logging
    if [[ ${#available_methods[@]} -gt 0 ]]; then
        log_message "$MSG_VIDEO_SUPPORT_AVAILABLE ${available_methods[*]}"
        
        if [[ ${#missing_methods[@]} -gt 0 ]]; then
            log_message "$MSG_EXTENDED_METHODS_AVAILABLE ${missing_methods[*]}"
            log_message "$MSG_INSTALLATION_DVD"
        fi
        
        return 0
    else
        log_message "$MSG_ERROR_NO_VIDEO_METHOD"
        return 1
    fi
}

# ============================================================================
# VIDEO DVD COPY - DVDBACKUP + GENISOIMAGE (Methode 1 - Schnellste)
# ============================================================================

# Funktion zum Kopieren von Video-DVDs mit Entschlüsselung
# Nutzt dvdbackup (mit libdvdcss) + genisoimage
# Mit intelligentem Fallback: dvdbackup → ddrescue → Ablehnung
copy_video_dvd() {
    local dvd_id=$(get_dvd_identifier)
    local failure_count=$(get_dvd_failure_count "$dvd_id")
    
    # Prüfe Fehler-Historie
    if [[ $failure_count -ge 2 ]]; then
        # DVD ist bereits 2x fehlgeschlagen → Ablehnung
        log_message "$MSG_ERROR_DVD_REJECTED"
        log_message "$MSG_ERROR_DVD_REJECTED_HINT"
        return 1
    elif [[ $failure_count -eq 1 ]]; then
        # DVD ist bereits 1x fehlgeschlagen → Automatischer Fallback auf ddrescue
        log_message "$MSG_WARNING_DVD_FAILED_BEFORE"
        log_message "$MSG_FALLBACK_TO_DDRESCUE"
        return copy_video_dvd_ddrescue
    fi
    
    # Erste Versuch: Normale dvdbackup-Methode
    log_message "$MSG_METHOD_DVDBACKUP"
    
    # Erstelle temporäres Verzeichnis für DVD-Struktur (unter temp_pathname)
    # dvdbackup erstellt automatisch Unterordner, daher nutzen wir temp_pathname direkt
    local temp_dvd="$temp_pathname"
    
    # Ermittle DVD-Größe für Fortschrittsanzeige
    local dvd_size_mb=0
    get_disc_size
    if [[ $total_bytes -gt 0 ]]; then
        dvd_size_mb=$((total_bytes / 1024 / 1024))
        log_message "$MSG_DVD_SIZE: ${dvd_size_mb} $MSG_PROGRESS_MB"
    fi
    
    # Prüfe Speicherplatz (DVD-Größe + 5% Puffer)
    if [[ $dvd_size_mb -gt 0 ]]; then
        local required_mb=$((dvd_size_mb + dvd_size_mb * 5 / 100))
        if ! check_disk_space "$required_mb"; then
            return 1
        fi
    fi
    
    # Starte dvdbackup im Hintergrund mit Fortschrittsanzeige
    # -M = Mirror (komplette DVD), -n = Name override (direkt VIDEO_TS)
    log_message "$MSG_EXTRACT_DVD_STRUCTURE"
    dvdbackup -M -n "dvd" -i "$CD_DEVICE" -o "$temp_dvd" >>"$log_filename" 2>&1 &
    local dvdbackup_pid=$!
    
    # Überwache Fortschritt (alle 60 Sekunden)
    local start_time=$(date +%s)
    local last_log_time=$start_time
    
    while kill -0 "$dvdbackup_pid" 2>/dev/null; do
        sleep 5
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - last_log_time))
        
        # Log alle 60 Sekunden
        if [[ $elapsed -ge 60 ]]; then
            local copied_mb=0
            if [[ -d "$temp_dvd" ]]; then
                copied_mb=$(du -sm "$temp_dvd" 2>/dev/null | awk '{print $1}')
                # Fallback wenn du fehlschlägt oder leer
                copied_mb=${copied_mb:-0}
            fi
            
            # Konvertiere MB zu Bytes für zentrale Funktion (mit Validierung)
            local current_bytes=0
            local total_bytes=0
            if [[ "$copied_mb" =~ ^[0-9]+$ ]]; then
                current_bytes=$((copied_mb * 1024 * 1024))
            fi
            if [[ "$dvd_size_mb" =~ ^[0-9]+$ ]] && [[ $dvd_size_mb -gt 0 ]]; then
                total_bytes=$((dvd_size_mb * 1024 * 1024))
            fi
            
            # Nutze zentrale Fortschrittsberechnung
            calculate_and_log_progress "$current_bytes" "$total_bytes" "$start_time" "DVD"
            
            last_log_time=$current_time
        fi
    done
    
    # Warte auf dvdbackup Prozess-Ende
    wait "$dvdbackup_pid"
    local dvdbackup_exit=$?
    
    # Prüfe Ergebnis
    if [[ $dvdbackup_exit -ne 0 ]]; then
        log_message "$MSG_ERROR_DVDBACKUP_FAILED (Exit-Code: $dvdbackup_exit)"
        
        # Registriere Fehlschlag für automatischen Fallback
        local dvd_id=$(get_dvd_identifier)
        register_dvd_failure "$dvd_id" "dvdbackup"
        log_message "$MSG_DVD_MARKED_FOR_RETRY"
        
        rm -rf "$temp_dvd"
        return 1
    fi
    
    log_message "$MSG_DVD_STRUCTURE_EXTRACTED"
    
    # VIDEO_TS ist jetzt direkt unter temp_dvd/dvd/VIDEO_TS
    local video_ts_dir="${temp_dvd}/dvd/VIDEO_TS"
    
    if [[ ! -d "$video_ts_dir" ]]; then
        log_message "$MSG_ERROR_NO_VIDEO_TS"
        return 1
    fi
    
    # Erstelle ISO aus VIDEO_TS Struktur
    log_message "$MSG_CREATE_DECRYPTED_ISO"
    if genisoimage -dvd-video -V "$disc_label" -o "$iso_filename" "$(dirname "$video_ts_dir")" 2>>"$log_filename"; then
        log_message "$MSG_DECRYPTED_DVD_SUCCESS"
        
        # Erfolg → Lösche eventuelle Fehler-Historie
        local dvd_id=$(get_dvd_identifier)
        clear_dvd_failures "$dvd_id"
        
        rm -rf "$temp_dvd"
        return 0
    else
        log_message "$MSG_ERROR_GENISOIMAGE_FAILED"
        
        # Registriere Fehlschlag (genisoimage-Fehler)
        local dvd_id=$(get_dvd_identifier)
        register_dvd_failure "$dvd_id" "genisoimage"
        
        rm -rf "$temp_dvd"
        return 1
    fi
}

# ============================================================================
# VIDEO DVD COPY - DDRESCUE (Methode 2 - Mittelschnell)
# ============================================================================

# Funktion zum Kopieren von Video-DVDs mit ddrescue
# Schneller als dd bei Lesefehlern, ISO bleibt verschlüsselt
# KEIN Fallback - Methode wird zu Beginn gewählt
copy_video_dvd_ddrescue() {
    log_message "$MSG_METHOD_DDRESCUE_ENCRYPTED"
    
    # ddrescue benötigt Map-Datei
    local mapfile="${iso_filename}.mapfile"
    
    # Ermittle Disc-Größe mit isoinfo
    get_disc_size
    if [[ $total_bytes -gt 0 ]]; then
        log_message "$MSG_ISO_VOLUME_DETECTED $volume_size $MSG_ISO_BLOCKS ($(( total_bytes / 1024 / 1024 )) $MSG_PROGRESS_MB)"
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
            local current_bytes=0
            if [[ -f "$iso_filename" ]]; then
                current_bytes=$(stat -c %s "$iso_filename" 2>/dev/null || echo 0)
            fi
            
            # Nutze zentrale Fortschrittsberechnung
            calculate_and_log_progress "$current_bytes" "$total_bytes" "$start_time" "$MSG_DVD_PROGRESS"
            
            last_log_time=$current_time
        fi
    done
    
    # Warte auf ddrescue Prozess-Ende
    wait "$ddrescue_pid"
    local ddrescue_exit=$?
    
    # Prüfe Ergebnis
    if [[ $ddrescue_exit -eq 0 ]]; then
        log_message "$MSG_VIDEO_DVD_DDRESCUE_SUCCESS"
        
        # Erfolg → Lösche eventuelle Fehler-Historie
        local dvd_id=$(get_dvd_identifier)
        clear_dvd_failures "$dvd_id"
        
        rm -f "$mapfile"
        return 0
    else
        log_message "$MSG_ERROR_DDRESCUE_FAILED"
        
        # Registriere Fehlschlag für finale Ablehnung
        local dvd_id=$(get_dvd_identifier)
        register_dvd_failure "$dvd_id" "ddrescue"
        log_message "$MSG_DVD_FINAL_FAILURE"
        
        rm -f "$mapfile"
        return 1
    fi
}
