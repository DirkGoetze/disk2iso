#!/bin/bash
################################################################################
# disk2iso v1.2.0 - Folder Management Library
# Filepath: lib/lib-folders.sh
#
# Beschreibung:
#   Verwaltung von Verzeichnissen:
#   - Temp-Verzeichnis-Erstellung
#   - Temp-Verzeichnis-Bereinigung
#   - Lazy Initialization für Output-Ordner
#
# Version: 1.2.0
# Datum: 06.01.2026
################################################################################

# Globale Flags für Lazy Initialization
_OUTPUT_DIR_CREATED=false
_LOG_DIR_CREATED=false
_TEMP_BASE_CREATED=false

# Lade Sprachdatei für dieses Modul
load_module_language "folders"

# ============================================================================
# GENERIC HELPER FUNCTIONS
# ============================================================================

# Generischer Helper: Stelle sicher dass ein Unterordner existiert
# Parameter: $1 = Unterordner-Name (relativ zu OUTPUT_DIR)
# Rückgabe: Vollständiger Pfad zum Unterordner
# Nutzt Lazy Initialization - erstellt Ordner nur einmal pro Name
ensure_subfolder() {
    local subfolder="$1"
    
    # Validierung
    if [[ -z "$subfolder" ]]; then
        log_error "$MSG_ERROR_ENSURE_SUBFOLDER_NO_NAME"
        return 1
    fi
    
    # Stelle sicher dass OUTPUT_DIR existiert
    get_out_folder || return 1
    
    # Vollständiger Pfad (entferne trailing slash von OUTPUT_DIR)
    local full_path="${OUTPUT_DIR%/}/${subfolder}"
    
    # Prüfe/Erstelle Ordner (idempotent)
    if [[ ! -d "$full_path" ]]; then
        if mkdir -p "$full_path" 2>/dev/null; then
            log_info "$MSG_SUBFOLDER_CREATED $full_path" >&2
        else
            log_error "$MSG_ERROR_CREATE_SUBFOLDER $full_path" >&2
            return 1
        fi
    fi
    
    echo "$full_path"
}

# ============================================================================
# TEMP FOLDER MANAGEMENT
# ============================================================================

# Funktion zum Erstellen des Temp-Verzeichnisses
# Prüft temp_base (wurde bei Installation angelegt), erstellt nur Unterordner
# Setzt globale Variable: temp_pathname
# Nutzt Lazy Initialization für temp_base und TEMP_DIR Konstante
#
# WICHTIG: Temp-Verzeichnis (.temp) hat 777 Permissions (siehe install.sh)!
# Grund: Service (root) + manuelle User-Aufrufe benötigen Write-Zugriff.
# Security: Akzeptabel für Trusted Environment (Home-Server)
get_temp_pathname() {
    # Nutze ensure_subfolder für temp_base (Konstante aus lib-common.sh)
    local temp_base
    temp_base=$(ensure_subfolder "$TEMP_DIR") || return 1
    
    # Markiere als erstellt (für Lazy Initialization Flag)
    _TEMP_BASE_CREATED=true
    
    # Generiere eindeutigen Unterordner basierend auf iso_basename
    local basename_without_ext="${iso_basename%.iso}"
    temp_pathname="${temp_base}/${basename_without_ext}_$$"
    mkdir -p "$temp_pathname" 2>/dev/null || {
        log_error "$MSG_ERROR_CREATE_TEMP_SUBFOLDER $temp_pathname"
        return 1
    }
    
    log_info "$MSG_TEMP_DIR_CREATED: $temp_pathname"
}

# Funktion zum Aufräumen des Temp-Verzeichnisses
# Löscht temp_pathname und setzt Variable zurück
cleanup_temp_pathname() {
    if [[ -n "$temp_pathname" ]] && [[ -d "$temp_pathname" ]]; then
        rm -rf "$temp_pathname"
        log_info "$MSG_TEMP_DIR_CLEANED: $temp_pathname"
        temp_pathname=""
    fi
}

# Funktion zum Erstellen eines temporären Mount-Points
# Erstellt Mount-Point im OUTPUT_DIR/.temp/mountpoints für sichere Schreibrechte
# Gibt den Pfad zurück
# Rückgabe: Mount-Point Pfad
get_tmp_mount() {
    # Nutze ensure_subfolder für mount_base (Konstante aus lib-common.sh)
    local mount_base
    mount_base=$(ensure_subfolder "$MOUNTPOINTS_DIR") || return 1
    
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
#
# WICHTIG: Log-Verzeichnis hat 777 Permissions (siehe install.sh)!
# Grund: Manuelle CLI-Aufrufe von verschiedenen Usern müssen in .log 
#        schreiben können. Service läuft als root, aber User A, B, C 
#        rufen disk2iso.sh auch manuell auf und müssen loggen können.
# Alternativen: Group-Management (höherer Setup-Aufwand)
# Security: Akzeptabel für Trusted Environment (Home-Server)
get_log_folder() {
    # Lazy Initialization: Log-Verzeichnis nur einmal prüfen
    if [[ "$_LOG_DIR_CREATED" == false ]]; then
        local log_dir="$(dirname "$log_filename")"
        if [[ ! -d "$log_dir" ]]; then
            log_error "$MSG_ERROR_LOG_DIR_NOT_EXIST $log_dir"
            return 1
        fi
        log_info "$MSG_LOG_DIR_CREATED: $log_dir"
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
            log_error "$MSG_ERROR_OUTPUT_DIR_NOT_EXIST $OUTPUT_DIR" >&2
            return 1
        fi
        log_info "$MSG_OUTPUT_DIR_CREATED: $OUTPUT_DIR" >&2
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
        log_warning "$MSG_WARNING_TYPE_DIR_NOT_EXIST $full_path"
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
    log_info "$MSG_ALBUM_DIR_CREATED: $album_dir"
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
        log_error "$MSG_ERROR_BACKUP_DIR_FAILED: $backup_dir"
        return 1
    fi
    log_info "$MSG_BACKUP_DIR_CREATED: $backup_dir"
    return 0
}

# ============================================================================
# ENDE DER FOLDER MANAGEMENT LIBRARY
# ============================================================================
