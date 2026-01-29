#!/bin/bash
# ===========================================================================
# DVD Library
# ===========================================================================
# Filepath: lib/libdvd.sh
#
# Beschreibung:
#   Funktionen für DVD-Ripping und -Konvertierung
#   - copy_video_dvd() - Video-DVD mit dvdbackup+genisoimage (entschlüsselt)
#   - copy_video_dvd_ddrescue() - Video-DVD/BD mit ddrescue (verschlüsselt)
#   - Intelligentes Fallback-System bei Fehlern
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
readonly MODULE_NAME_DVD="dvd"               # Globale Variable für Modulname
SUPPORT_DVD=false                                     # Globales Support Flag
INITIALIZED_DVD=false                       # Initialisierung war erfolgreich
ACTIVATED_DVD=false                              # In Konfiguration aktiviert

# ===========================================================================
# check_dependencies_dvd
# ---------------------------------------------------------------------------
# Funktion.: Prüfe alle Modul-Abhängigkeiten (Modul-Dateien, Ausgabe-Ordner, 
# .........  kritische und optionale Software für die Ausführung des Modul),
# .........  lädt nach erfolgreicher Prüfung die Sprachdatei für das Modul.
# Parameter: keine
# Rückgabe.: 0 = Verfügbar (Module nutzbar)
# .........  1 = Nicht verfügbar (Modul deaktiviert)
# Extras...: Setzt SUPPORT_DVD=true bei erfolgreicher Prüfung
# ===========================================================================
check_dependencies_dvd() {
    log_debug "$MSG_DEBUG_DVD_CHECK_START"

    #-- Alle Modul Abhängigkeiten prüfen -------------------------------------
    check_module_dependencies "$MODULE_NAME_DVD" || return 1

    #-- Lade Modul-Konfiguration --------------------------------------------
    load_config_dvd || return 1

    #-- Setze Verfügbarkeit -------------------------------------------------
    SUPPORT_DVD=true
    log_debug "$MSG_DEBUG_DVD_CHECK_COMPLETE"
    
    #-- Abhängigkeiten erfüllt ----------------------------------------------
    log_info "$MSG_VIDEO_SUPPORT_AVAILABLE"
    return 0
}

# ===========================================================================
# load_config_dvd
# ---------------------------------------------------------------------------
# Funktion.: Lade DVD-Modul Konfiguration und setze Initialisierung
# Parameter: keine
# Rückgabe.: 0 = Erfolgreich geladen
# Setzt....: INITIALIZED_DVD=true, ACTIVATED_DVD=true
# Hinweis..: DVD-Modul hat keine API-Config, daher nur Flags setzen
# .........  Modul ist immer aktiviert wenn Support vorhanden
# ===========================================================================
load_config_dvd() {
    # DVD-Video ist immer aktiviert wenn Support verfügbar (keine Runtime-Deaktivierung)
    ACTIVATED_DVD=true
    
    # Setze Initialisierungs-Flag
    INITIALIZED_DVD=true
    
    log_info "DVD-Video: Konfiguration geladen"
    return 0
}

# ===========================================================================
# is_dvd_ready
# ---------------------------------------------------------------------------
# Funktion.: Prüfe ob DVD-Modul supported wird, initialisiert wurde und
# .........  aktiviert ist. Wenn true ist alles bereit für die Nutzung.
# Parameter: keine
# Rückgabe.: 0 = Bereit, 1 = Nicht bereit
# ===========================================================================
is_dvd_ready() {
    [[ "$SUPPORT_DVD" == "true" ]] && \
    [[ "$INITIALIZED_DVD" == "true" ]] && \
    [[ "$ACTIVATED_DVD" == "true" ]]
}

# ============================================================================
# PATH CONSTANTS
# ============================================================================

# ===========================================================================
# get_path_dvd
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Ausgabepfad des Modul für die Verwendung in anderen
# .........  abhängigen Modulen
# Parameter: keine
# Rückgabe.: Vollständiger Pfad zum Modul Verzeichnis
# Hinweis: Ordner wird bereits in check_module_dependencies() erstellt
# ===========================================================================
get_path_dvd() {
    echo "${OUTPUT_DIR}/${MODULE_NAME_DVD}"
}

# TODO: Ab hier ist das Modul noch nicht fertig implementiert!

readonly FAILED_DISCS_FILE=".failed_dvds"

# ============================================================================
# PATH GETTER
# ============================================================================

# ============================================================================
# FEHLER-TRACKING SYSTEM
# ============================================================================

# Funktion: Ermittle eindeutigen Identifier für DVD
# Rückgabe: String mit disc_label und disc_type (z.B. "supernatural_season_10_disc_3:dvd-video")
get_dvd_identifier() {
    echo "$(discinfo_get_label):$(discinfo_get_type)"
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
# VIDEO DVD COPY - DVDBACKUP + GENISOIMAGE (Methode 1 - Schnellste)
# ============================================================================

# Funktion zum Kopieren von Video-DVDs mit Entschlüsselung
# Nutzt dvdbackup (mit libdvdcss) + genisoimage
# Mit intelligentem Fallback: dvdbackup → ddrescue → Ablehnung
copy_video_dvd() {
    # Initialisiere Kopiervorgang-Log
    init_copy_log "$(discinfo_get_label)" "dvd"
    
    # Nutze zentrale Fehler-Tracking Funktionen aus libcommon.sh
    local failure_count=$(get_disc_failure_count)
    
    # ========================================================================
    # TMDB METADATA BEFORE COPY (wenn verfügbar)
    # ========================================================================
    
    local skip_tmdb=false
    local disc_id=$(get_disc_identifier)  # Zentrale Funktion aus libcommon.sh
    
    # Prüfe ob TMDB BEFORE Copy verfügbar ist
    if declare -f query_tmdb_before_copy >/dev/null 2>&1; then
        # Extrahiere Filmtitel aus disc_label
        local movie_title
        if declare -f extract_movie_title_from_label >/dev/null 2>&1; then
            movie_title=$(extract_movie_title_from_label "$(discinfo_get_label)")
        else
            # Fallback: Einfache Konvertierung
            movie_title=$(echo "$(discinfo_get_label)" | tr '_' ' ' | sed 's/\b\(.)/ \u\1/g')
        fi
        
        log_info "TMDB: Suche nach '$movie_title'..."
        
        # Query TMDB
        if query_tmdb_before_copy "$movie_title" "$(discinfo_get_type)" "$disc_id"; then
            # TMDB Query erfolgreich - warte auf User-Auswahl
            log_info "TMDB: Warte auf User-Auswahl..."
            
            # Hole TMDB Response (aus .tmdbquery Datei)
            local output_base
            output_base=$(get_type_subfolder "$(discinfo_get_type)")
            local tmdbquery_file="${output_base}/${dvd_id}_tmdb.tmdbquery"
            
            if [[ -f "$tmdbquery_file" ]]; then
                local tmdb_json
                tmdb_json=$(cat "$tmdbquery_file")
                
                # Warte auf Auswahl
                if declare -f wait_for_tmdb_selection >/dev/null 2>&1; then
                    if wait_for_tmdb_selection "$disc_id" "$tmdb_json"; then
                        # User hat ausgewählt - disc_label wurde aktualisiert
                        log_info "TMDB: Metadata-Auswahl erfolgreich - neues Label: $(discinfo_get_label)"
                        
                        # Re-initialisiere Log mit neuem Label
                        init_copy_log "$(discinfo_get_label)" "dvd"
                    else
                        log_info "TMDB: Metadata übersprungen - verwende generisches Label"
                        skip_tmdb=true
                    fi
                else
                    log_warning "TMDB: wait_for_tmdb_selection() nicht verfügbar"
                    skip_tmdb=true
                fi
            else
                log_warning "TMDB: Query-Datei nicht gefunden"
                skip_tmdb=true
            fi
        else
            log_info "TMDB: Keine Treffer oder Abfrage fehlgeschlagen"
            skip_tmdb=true
        fi
    else
        log_info "TMDB: BEFORE Copy nicht verfügbar - verwende generisches Label"
        skip_tmdb=true
    fi
    
    # ========================================================================
    # DVD COPY WORKFLOW
    # ========================================================================
    
    # Prüfe Fehler-Historie
    if [[ $failure_count -ge 2 ]]; then
        # DVD ist bereits 2x fehlgeschlagen → Ablehnung
        log_error "$MSG_ERROR_DVD_REJECTED"
        log_error "$MSG_ERROR_DVD_REJECTED_HINT"
        finish_copy_log
        return 1
    elif [[ $failure_count -eq 1 ]]; then
        # DVD ist bereits 1x fehlgeschlagen → Automatischer Fallback auf ddrescue
        log_warning "$MSG_WARNING_DVD_FAILED_BEFORE"
        log_copying "$MSG_FALLBACK_TO_DDRESCUE"
        
        # Update COPY_METHOD für API/MQTT Anzeige
        export COPY_METHOD="ddrescue"
        
        copy_video_dvd_ddrescue
        return $?
    fi
    
    # Erste Versuch: Normale dvdbackup-Methode
    log_copying "$MSG_METHOD_DVDBACKUP"
    
    # Erstelle temporäres Verzeichnis für DVD-Struktur (unter temp_pathname)
    # dvdbackup erstellt automatisch Unterordner, daher nutzen wir temp_pathname direkt
    local temp_dvd="$temp_pathname"
    
    # Ermittle DVD-Größe für Fortschrittsanzeige
    local dvd_size_mb=0
    get_disc_size
    if [[ $total_bytes -gt 0 ]]; then
        dvd_size_mb=$((total_bytes / 1024 / 1024))
        log_copying "$MSG_DVD_SIZE: ${dvd_size_mb} $MSG_PROGRESS_MB"
    fi
    
    # Prüfe Speicherplatz (Overhead wird automatisch berechnet)
    if [[ $dvd_size_mb -gt 0 ]]; then
        if ! check_disk_space "$dvd_size_mb"; then
            return 1
        fi
    fi
    
    # Starte dvdbackup im Hintergrund mit Fortschrittsanzeige
    # -M = Mirror (komplette DVD), -n = Name override (direkt VIDEO_TS)
    log_copying "$MSG_EXTRACT_DVD_STRUCTURE"
    dvdbackup -M -n "dvd" -i "$CD_DEVICE" -o "$temp_dvd" >>"$copy_log_filename" 2>&1 &
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
        log_error "$MSG_ERROR_DVDBACKUP_FAILED (Exit-Code: $dvdbackup_exit)"
        
        # Registriere Fehlschlag für automatischen Fallback (zentrale Funktion)
        register_disc_failure "dvdbackup"
        log_warning "$MSG_DVD_MARKED_FOR_RETRY"
        
        rm -rf "$temp_dvd"
        finish_copy_log
        return 1
    fi
    
    log_copying "$MSG_DVD_STRUCTURE_EXTRACTED"
    
    # VIDEO_TS ist jetzt direkt unter temp_dvd/dvd/VIDEO_TS
    local video_ts_dir="${temp_dvd}/dvd/VIDEO_TS"
    
    if [[ ! -d "$video_ts_dir" ]]; then
        log_error "$MSG_ERROR_NO_VIDEO_TS"
        finish_copy_log
        return 1
    fi
    
    # Erstelle ISO aus VIDEO_TS Struktur
    log_copying "$MSG_CREATE_DECRYPTED_ISO"
    if genisoimage -dvd-video -V "$(discinfo_get_label)" -o "$iso_filename" "$(dirname "$video_ts_dir")" 2>>"$copy_log_filename"; then
        log_copying "$MSG_DECRYPTED_DVD_SUCCESS"
        
        # Erfolg → Lösche eventuelle Fehler-Historie (zentrale Funktion)
        clear_disc_failures
        
        # Erstelle Metadaten für Archiv-Ansicht
        if declare -f create_dvd_archive_metadata >/dev/null 2>&1; then
            local movie_title=$(extract_movie_title "$(discinfo_get_label)")
            create_dvd_archive_metadata "$movie_title" "dvd-video" || true
        fi
        
        rm -rf "$temp_dvd"
        finish_copy_log
        return 0
    else
        log_error "$MSG_ERROR_GENISOIMAGE_FAILED"
        
        # Registriere Fehlschlag (genisoimage-Fehler, zentrale Funktion)
        register_disc_failure "genisoimage"
        
        rm -rf "$temp_dvd"
        finish_copy_log
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
    # Initialisiere Kopiervorgang-Log (falls noch nicht von copy_video_dvd initialisiert)
    if [[ -z "$copy_log_filename" ]]; then
        init_copy_log "$(discinfo_get_label)" "dvd"
    fi
    
    log_copying "$MSG_METHOD_DDRESCUE_ENCRYPTED"
    
    # ddrescue benötigt Map-Datei (im .temp Verzeichnis, wird auto-gelöscht)
    local mapfile="${temp_pathname}/$(basename "${iso_filename}").mapfile"
    
    # Ermittle Disc-Größe mit isoinfo
    get_disc_size
    if [[ $total_bytes -gt 0 ]]; then
        log_copying "$MSG_ISO_VOLUME_DETECTED $volume_size $MSG_ISO_BLOCKS ($(( total_bytes / 1024 / 1024 )) $MSG_PROGRESS_MB)"
    fi
    
    # Prüfe Speicherplatz (Overhead wird automatisch berechnet)
    if [[ $total_bytes -gt 0 ]]; then
        local size_mb=$((total_bytes / 1024 / 1024))
        if ! check_disk_space "$size_mb"; then
            # Mapfile wird mit temp_pathname automatisch gelöscht
            return 1
        fi
    fi
    
    # Kopiere mit ddrescue
    # Starte ddrescue im Hintergrund
    if [[ $total_bytes -gt 0 ]]; then
        ddrescue -b 2048 -s "$total_bytes" -n "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$copy_log_filename" &
    else
        ddrescue -b 2048 -n "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$copy_log_filename" &
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
        log_copying "$MSG_VIDEO_DVD_DDRESCUE_SUCCESS"
        
        # Erfolg → Lösche eventuelle Fehler-Historie (zentrale Funktion)
        clear_disc_failures
        
        # Erstelle Metadaten für Archiv-Ansicht (verwende disc_type für DVD/Blu-ray)
        if declare -f create_dvd_archive_metadata >/dev/null 2>&1; then
            local movie_title=$(extract_movie_title "$(discinfo_get_label)")
            create_dvd_archive_metadata "$movie_title" "$(discinfo_get_type)" || true
        fi
        
        # Mapfile wird mit temp_pathname automatisch gelöscht
        finish_copy_log
        return 0
    else
        log_error "$MSG_ERROR_DDRESCUE_FAILED"
        
        # Registriere Fehlschlag für finale Ablehnung (zentrale Funktion)
        register_disc_failure "ddrescue"
        log_error "$MSG_DVD_FINAL_FAILURE"
        
        # Mapfile wird mit temp_pathname automatisch gelöscht
        finish_copy_log
        return 1
    fi
}
