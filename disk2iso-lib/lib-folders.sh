#!/bin/bash
################################################################################
# disk2iso v1.0.0 - Folder Management Library
# Filepath: disk2iso-lib/lib-folders.sh
#
# Beschreibung:
#   Verwaltung von Verzeichnissen:
#   - Temp-Verzeichnis-Erstellung
#   - Temp-Verzeichnis-Bereinigung
#   - Lazy Initialization für Output-Ordner
#
# Version: 1.0.0
# Datum: 01.01.2026
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
# Prüft temp_base (wurde bei Installation angelegt), erstellt nur Unterordner
# Setzt globale Variable: temp_pathname
# Nutzt Lazy Initialization für temp_base und TEMP_DIR Konstante
get_temp_pathname() {
    # Stelle sicher dass OUTPUT_DIR existiert
    get_out_folder
    
    # Nutze Konstante aus lib-common.sh
    local temp_base="${OUTPUT_DIR}/${TEMP_DIR}"
    
    # Lazy Initialization: temp_base nur einmal prüfen
    if [[ "$_TEMP_BASE_CREATED" == false ]]; then
        if [[ ! -d "$temp_base" ]]; then
            log_message "FEHLER: Temp-Verzeichnis existiert nicht: $temp_base"
            return 1
        fi
        _TEMP_BASE_CREATED=true
    fi
    
    # Generiere eindeutigen Unterordner basierend auf iso_basename
    local basename_without_ext="${iso_basename%.iso}"
    temp_pathname="${temp_base}/${basename_without_ext}_$$"
    mkdir -p "$temp_pathname" 2>/dev/null || {
        log_message "FEHLER: Kann Temp-Unterordner nicht erstellen: $temp_pathname"
        return 1
    }
    
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
# Erstellt Mount-Point im OUTPUT_DIR/.temp/mountpoints für sichere Schreibrechte
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

# Funktion zum Prüfen des Log-Verzeichnisses
# Prüft ob Log-Verzeichnis existiert (wurde bei Installation angelegt)
# Nutzt Lazy Initialization - wird nur einmal pro Session geprüft
get_log_folder() {
    # Lazy Initialization: Log-Verzeichnis nur einmal prüfen
    if [[ "$_LOG_DIR_CREATED" == false ]]; then
        local log_dir="$(dirname "$log_filename")"
        if [[ ! -d "$log_dir" ]]; then
            log_message "FEHLER: Log-Verzeichnis existiert nicht: $log_dir"
            return 1
        fi
        log_message "$MSG_LOG_DIR_CREATED: $log_dir"
        _LOG_DIR_CREATED=true
    fi
}

# Funktion zum Prüfen des Ausgabe-Verzeichnisses
# Prüft ob OUTPUT_DIR existiert (wurde bei Installation angelegt)
# Nutzt Lazy Initialization - wird nur einmal pro Session geprüft
get_out_folder() {
    # Lazy Initialization: OUTPUT_DIR nur einmal prüfen
    if [[ "$_OUTPUT_DIR_CREATED" == false ]]; then
        if [[ ! -d "$OUTPUT_DIR" ]]; then
            log_message "FEHLER: Ausgabeverzeichnis existiert nicht: $OUTPUT_DIR"
            return 1
        fi
        log_message "$MSG_OUTPUT_DIR_CREATED: $OUTPUT_DIR"
        _OUTPUT_DIR_CREATED=true
    fi
}

# Funktion zum Prüfen von Typ-spezifischen Unterordnern
# Parameter: $1 = disc_type (audio-cd, cd-rom, dvd-video, dvd-rom, bd-video, bd-rom)
# Rückgabe: Unterordner-Pfad
# Nutzt Getter-Methoden mit Fallback-Logik aus den jeweiligen Modulen
# Unterordner wurden bei Installation angelegt
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
    
    # Prüfe ob Verzeichnis existiert
    if [[ ! -d "$full_path" ]]; then
        log_message "WARNUNG: Typ-Verzeichnis existiert nicht: $full_path"
        # Versuche es anzulegen (Fallback)
        mkdir -p "$full_path" 2>/dev/null || return 1
    fi
    
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
