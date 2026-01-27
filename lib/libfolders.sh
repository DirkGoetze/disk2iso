#!/bin/bash
# =============================================================================
# Folder Management Library
# =============================================================================
# Filepath: lib/libfolders.sh
#
# Beschreibung:
#   Verwaltung von Verzeichnissen und temporären Ordnern
#   - Temp-Verzeichnis-Erstellung und Bereinigung
#   - Lazy Initialization für Output-Ordner
#   - ensure_subfolder() für alle Module
#   - cleanup_temp() für automatische Bereinigung
#
# -----------------------------------------------------------------------------
# Dependencies: liblogging (für log_* Funktionen)
# -----------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.2.1
# Last Change: 2026-01-26 20:00
# =============================================================================

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

# ===========================================================================
# check_dependencies_folders
# ---------------------------------------------------------------------------
# Funktion.: Prüfe alle Framework Abhängigkeiten (Modul-Dateien, die Modul
# .........  Ausgabe Ordner, kritische und optionale Software für die
# .........  Ausführung des Tool), lädt bei erfolgreicher Prüfung die
# .........  Sprachdatei für das Modul.
# Parameter: keine
# Rückgabe.: 0 = Verfügbar (Framework nutzbar)
# .........  1 = Nicht verfügbar (Framework deaktiviert)
# Extras...: Sollte so früh wie möglich nach dem Start geprüft werden, da
# .........  andere Module ggf. auf dieses Framework angewiesen sind. Am
# .........  besten direkt im Hauptskript (disk2iso) nach dem
# .........  Laden der libcommon.sh.
# ===========================================================================
check_dependencies_folders() {
    # Lade Sprachdatei für dieses Modul
    load_module_language "folders"
    
    # Folders-Modul benötigt nur mkdir
    # mkdir ist POSIX-Standard und auf jedem System verfügbar
    return 0
}

# Globale Flags für Lazy Initialization
_OUTPUT_DIR_CREATED=false
_LOG_DIR_CREATED=false
_TEMP_BASE_CREATED=false

# ============================================================================
# GENERIC HELPER FUNCTIONS
# ============================================================================

# Generischer Helper: Stelle sicher dass ein Unterordner existiert
# Parameter: $1 = Unterordner-Name (relativ zu OUTPUT_DIR)
# Rückgabe: Vollständiger Pfad zum Unterordner
# Nutzt Lazy Initialization - erstellt Ordner nur einmal pro Name
# Hinweis: Setzt 755 für normale Ordner, 777 für .log/.temp Ordner
ensure_subfolder() {
    local subfolder="$1"
    
    # Validierung
    if [[ -z "$subfolder" ]]; then
        log_error "$MSG_ERROR_ENSURE_SUBFOLDER_NO_NAME"
        return 1
    fi
    
    # Vollständiger Pfad (entferne trailing slash von OUTPUT_DIR)
    local full_path="${OUTPUT_DIR%/}/${subfolder}"
    
    # Fast-Path: Ordner existiert bereits
    if [[ -d "$full_path" ]]; then
        echo "$full_path"
        return 0
    fi
    
    # Slow-Path: Stelle sicher dass OUTPUT_DIR existiert
    get_out_folder || return 1
    
    # Erstelle Ordner
    if mkdir -p "$full_path" 2>/dev/null; then
        # Setze Berechtigungen (777 für .log/.temp, sonst 755)
        if [[ "$subfolder" =~ ^\.(log|temp) ]] || [[ "$subfolder" =~ /\.(log|temp)($|/) ]]; then
            chmod 777 "$full_path" 2>/dev/null
        else
            chmod 755 "$full_path" 2>/dev/null
        fi
        log_info "$MSG_SUBFOLDER_CREATED $full_path" >&2
    else
        log_error "$MSG_ERROR_CREATE_SUBFOLDER $full_path" >&2
        return 1
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
    # Nutze ensure_subfolder für temp_base (Konstante aus libcommon.sh)
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
    # Nutze ensure_subfolder für mount_base (Konstante aus libcommon.sh)
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
            full_path=$(get_path_bluray)
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

# ===========================================================================
# MODUL-ORDNER KONSTANTEN (für Manifest-Datei-Mapping)
# ===========================================================================

# Ordner für Modul-Komponenten (relativ zu INSTALL_DIR)
readonly MODULE_LIB_DIR="lib"                    # Bash-Module
readonly MODULE_LANG_DIR="lang"                  # Sprachdateien
readonly MODULE_CONF_DIR="conf"                  # Konfiguration
readonly MODULE_DOC_DIR="doc"                    # Dokumentation

# Web-Frontend Ordner
readonly MODULE_HTML_DIR="www/templates"         # HTML-Partials
readonly MODULE_CSS_DIR="www/static/css"         # Stylesheets
readonly MODULE_JS_DIR="www/static/js"           # JavaScript

# Backend Ordner
readonly MODULE_ROUTER_DIR="www/routes"          # Python-Routes

# ===========================================================================
# get_module_file_path
# ---------------------------------------------------------------------------
# Funktion.: Ermittle vollständigen Pfad zu Modul-Datei
# Parameter: $1 = file_type ("libary", "language", "js", "css", etc.)
#            $2 = filename (z.B. "libmetadata.sh")
# Rückgabe.: Vollständiger Pfad
# Beispiel.: get_module_file_path "libary" "libmetadata.sh"
#            → "/opt/disk2iso/lib/libmetadata.sh"
# ===========================================================================
get_module_file_path() {
    local file_type="$1"
    local filename="$2"
    
    if [[ -z "$file_type" ]] || [[ -z "$filename" ]]; then
        return 1
    fi
    
    local base_dir="${INSTALL_DIR:-/opt/disk2iso}"
    
    # Mappe file_type zu Ordner
    case "$file_type" in
        lib)
            echo "${base_dir}/${MODULE_LIB_DIR}/${filename}"
            ;;
        lang)
            # Sprachdateien haben Suffix (z.B. .de, .en)
            # Wenn filename ohne Suffix → nur Basis-Name
            if [[ "$filename" =~ \.(de|en|es|fr|it)$ ]]; then
                echo "${base_dir}/${MODULE_LANG_DIR}/${filename}"
            else
                # Gib Pattern zurück (für Existenz-Check mit Wildcard)
                echo "${base_dir}/${MODULE_LANG_DIR}/${filename}.*"
            fi
            ;;
        js)
            echo "${base_dir}/${MODULE_JS_DIR}/${filename}"
            ;;
        css)
            echo "${base_dir}/${MODULE_CSS_DIR}/${filename}"
            ;;
        html)
            echo "${base_dir}/${MODULE_HTML_DIR}/${filename}"
            ;;
        router)
            # Python-Dateien haben prefix "routes_"
            if [[ "$filename" == routes_* ]]; then
                echo "${base_dir}/${MODULE_ROUTER_DIR}/${filename}"
            else
                echo "${base_dir}/${MODULE_ROUTER_DIR}/routes_${filename}"
            fi
            ;;
        docu)
            echo "${base_dir}/${MODULE_DOC_DIR}/${filename}"
            ;;
        *)
            # Unbekannter Typ → Fehler
            return 1
            ;;
    esac
}

# ============================================================================
# ENDE DER FOLDER MANAGEMENT LIBRARY
# ============================================================================
