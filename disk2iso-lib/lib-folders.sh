#!/bin/bash
################################################################################
# Folder Management Library
# Filepath: disk2iso-lib/lib-folders.sh
#
# Beschreibung:
#   Sammlung aller Funktionen zur Verwaltung von Dateipfaden und Verzeichnissen:
#   - Temp-Verzeichnis-Erstellung
#   - Temp-Verzeichnis-Bereinigung
#   - Lazy Initialization für wiederholte Aufrufe
#
# Quellen:
#   - lib-diskinfos.sh (get_temp_pathname, cleanup_temp_pathname)
#
# Konsolidiert: 13.12.2025
# Optimiert: 13.12.2025 - Lazy Initialization hinzugefügt
################################################################################

# Globale Flags für Lazy Initialization
_OUTPUT_DIR_CREATED=false
_LOG_DIR_CREATED=false
_TEMP_BASE_CREATED=false

# Lade Sprachdatei für dieses Modul
load_module_language "folders"

# ============================================================================
# TEMP FOLDER MANAGEMENT
# Quelle: lib-diskinfos.sh
# ============================================================================

# Funktion zum Erstellen des Temp-Verzeichnisses
# Erstellt strukturiertes Temp-Verzeichnis im OUTPUT_DIR
# Setzt globale Variable: temp_pathname
# Nutzt Lazy Initialization für temp_base und TEMP_DIR Konstante
get_temp_pathname() {
    # Stelle sicher dass OUTPUT_DIR existiert
    get_out_folder
    
    # Nutze Konstante aus lib-common.sh
    local temp_base="${OUTPUT_DIR}/${TEMP_DIR}"
    
    # Lazy Initialization: temp_base nur einmal erstellen
    if [[ "$_TEMP_BASE_CREATED" == false ]]; then
        mkdir -p "$temp_base"
        _TEMP_BASE_CREATED=true
    fi
    
    # Generiere eindeutigen Unterordner basierend auf iso_basename
    local basename_without_ext="${iso_basename%.iso}"
    temp_pathname="${temp_base}/${basename_without_ext}_$$"
    mkdir -p "$temp_pathname"
    
    log_message "$MSG_TEMP_DIR_CREATED: $temp_pathname"
}

# Funktion zum Aufräumen des Temp-Verzeichnisses
# Löscht temp_pathname und setzt Variable zurück
cleanup_temp_pathname() {
    if [[ -n "$temp_pathname" ]] && [[ -d "$temp_pathname" ]]; then
        rm -rf "$temp_pathname"
        log_message "$MSG_TEMP_DIR_CLEANED: $temp_pathname"
        temp_pathname=""
    fi
}

# Funktion zum Erstellen eines temporären Mount-Points
# Erstellt Mount-Point im OUTPUT_DIR/temp/mountpoints für sichere Schreibrechte
# Gibt den Pfad zurück
# Rückgabe: Mount-Point Pfad
get_tmp_mount() {
    # Stelle sicher dass OUTPUT_DIR existiert
    get_out_folder
    
    # Nutze Konstante aus lib-common.sh
    local mount_base="${OUTPUT_DIR}/${MOUNTPOINTS_DIR}"
    
    # mount_base wird bei jedem Aufruf erstellt (mehrere parallele Mounts möglich)
    mkdir -p "$mount_base"
    
    # Generiere eindeutigen Mount-Point Namen
    local mount_point="${mount_base}/mount_$$_${RANDOM}"
    mkdir -p "$mount_point"
    
    echo "$mount_point"
}

# ============================================================================
# SPECIFIC FOLDER CREATION
# ============================================================================

# Funktion zum Erstellen des Log-Verzeichnisses
# Erstellt Verzeichnis für Log-Datei
# Nutzt Lazy Initialization - wird nur einmal pro Session erstellt
get_log_folder() {
    # Lazy Initialization: Log-Verzeichnis nur einmal erstellen
    if [[ "$_LOG_DIR_CREATED" == false ]]; then
        local log_dir="$(dirname "$log_filename")"
        mkdir -p "$log_dir"
        log_message "$MSG_LOG_DIR_CREATED: $log_dir"
        _LOG_DIR_CREATED=true
    fi
}

# Funktion zum Erstellen des Ausgabe-Verzeichnisses
# Erstellt OUTPUT_DIR falls nicht vorhanden
# Nutzt Lazy Initialization - wird nur einmal pro Session erstellt
get_out_folder() {
    # Lazy Initialization: OUTPUT_DIR nur einmal erstellen
    if [[ "$_OUTPUT_DIR_CREATED" == false ]]; then
        mkdir -p "$OUTPUT_DIR"
        log_message "$MSG_OUTPUT_DIR_CREATED: $OUTPUT_DIR"
        _OUTPUT_DIR_CREATED=true
    fi
}

# Funktion zum Erstellen von Typ-spezifischen Unterordnern
# Parameter: $1 = disc_type (audio-cd, cd-rom, dvd-video, dvd-rom, bd-video, bd-rom)
# Rückgabe: Unterordner-Pfad
# Nutzt Getter-Methoden mit Fallback-Logik aus den jeweiligen Modulen
get_type_subfolder() {
    local dtype="$1"
    local full_path=""
    
    case "$dtype" in
        audio-cd)
            full_path=$(get_path_audio)
            ;;
        cd-rom|dvd-rom|bd-rom)
            full_path=$(get_path_data)
            ;;
        dvd-video)
            full_path=$(get_path_dvd)
            ;;
        bd-video)
            full_path=$(get_path_bd)
            ;;
        *)
            # Default Fallback für unbekannte Typen
            full_path=$(get_path_data)
            ;;
    esac
    
    mkdir -p "$full_path"
    echo "$full_path"
}

# Funktion zum Erstellen des Album-Verzeichnisses für Audio-CDs
# Parameter: $1 = album_dir Pfad
# Rückgabe: 0 = erfolgreich, 1 = Fehler
# Hinweis: Jeder Aufruf erstellt ein neues Verzeichnis (unterschiedliche Alben)
get_album_folder() {
    local album_dir="$1"
    
    # Stelle sicher dass OUTPUT_DIR existiert
    get_out_folder
    
    if ! mkdir -p "$album_dir"; then
        return 1
    fi
    log_message "$MSG_ALBUM_DIR_CREATED: $album_dir"
    return 0
}

# Funktion zum Erstellen des Blu-ray Backup-Verzeichnisses
# Parameter: $1 = backup_dir Pfad
# Rückgabe: 0 = erfolgreich, 1 = Fehler
# Hinweis: Jeder Aufruf erstellt ein neues Verzeichnis (unterschiedliche Discs)
get_bd_backup_folder() {
    local backup_dir="$1"
    
    # Stelle sicher dass OUTPUT_DIR existiert
    get_out_folder
    
    if ! mkdir -p "$backup_dir"; then
        log_message "$MSG_ERROR_BACKUP_DIR_FAILED: $backup_dir"
        return 1
    fi
    log_message "$MSG_BACKUP_DIR_CREATED: $backup_dir"
    return 0
}

# ============================================================================
# ENDE DER FOLDER MANAGEMENT LIBRARY
# ============================================================================
