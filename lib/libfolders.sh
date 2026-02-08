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
#   - folders_ensure_subfolder() für alle Module
#   - cleanup_temp() für automatische Bereinigung
#
# -----------------------------------------------------------------------------
# Dependencies: liblogging (für log_* Funktionen)
# -----------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.3.0
# Last Change: 2026-02-07
# =============================================================================

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

# ===========================================================================
# folders_check_dependencies
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
folders_check_dependencies() {
    # Lade Sprachdatei für dieses Modul
    load_module_language "folders"
    
    # Prüfe/Erstelle OUTPUT_DIR (kritisch für alle Folder-Operationen)
    folders_get_output_dir || return 1
    
    # Folders-Modul benötigt nur mkdir
    # mkdir ist POSIX-Standard und auf jedem System verfügbar
    return 0
}

# ============================================================================
# GENERIC HELPER FUNCTIONS
# ============================================================================
# Globale Festsetzung für Zugriffsrechte in Ordnern -------------------------
readonly DIR_PERMISSIONS_NORMAL="755"        # Normale Ordner
readonly DIR_PERMISSIONS_PUBLIC="777"        # Öffentl. Ordner (.log, .temp)

# ===========================================================================
# folders_ensure_subfolder
# ---------------------------------------------------------------------------
# Funktion.: Stelle sicher dass ein Unterordner existiert, der Ordner muss
# .........  expliziet übergeben werden, Verschachtelung ('.temp/mount') wird 
# .........  nicht unterstützt.
# Parameter: $1 = Unterordner-Name 
# Rückgabe.: 0 = Erfolg
# .........  1 = Fehler
# Hinweis..: - Setzt 755 für normale Ordner
# .........  - Setzt 777 für .log/.temp Ordner (Multi-User-Zugriff)
# .........  - Fast-Path wenn Ordner bereits existiert
# ===========================================================================
folders_ensure_subfolder() {
    local subfolder="$1"
    
    #-- Parameter-Validierung -----------------------------------------------
    if [[ -z "$subfolder" ]]; then
        log_error "$MSG_ERROR_ENSURE_SUBFOLDER_NO_NAME"
        return 1
    fi
    
    #-- hier schon vollständigen Pfad erstellen für die 1. Prüfung ----------
    local full_path="${OUTPUT_DIR}/${subfolder}"

    #-- Prüfung in zwei Schritten -------------------------------------------
    #-- 1. Ordner existiert bereits -----------------------------------------    
    if [[ -d "$full_path" ]]; then
        log_debug "$MSG_DEBUG_SUBFOLDER_EXISTS '${subfolder}'"
        return 0
    fi
    
    #-- 2. Prüfe ob Parent-Dir existiert (für Self-Repair) ------------------
    local parent_dir="$(dirname "$full_path")"
    if [[ ! -d "$parent_dir" ]]; then
        log_error "$MSG_ERROR_PARENT_DIR_MISSING $parent_dir (für $subfolder)" >&2
        return 1
    fi
    
    #-- Erstelle Ordner -----------------------------------------------------
    if mkdir -p "$full_path" 2>/dev/null; then
        log_info "$MSG_SUBFOLDER_CREATED $full_path" >&2
        #-- Setzen der Berechtigungen ---------------------------------------
        local perms="755"
        if [[ "$subfolder" =~ ^\.(log|temp) ]] || [[ "$subfolder" =~ /\.(log|temp)($|/) ]]; then
            chmod $DIR_PERMISSIONS_NORMAL "$full_path" 2>/dev/null
            log_debug "$MSG_DEBUG_SUBFOLDER_PERMISSIONS_NORMAL ${DIR_PERMISSIONS_NORMAL}"
        else
            chmod $DIR_PERMISSIONS_PUBLIC "$full_path" 2>/dev/null
            log_debug "$MSG_DEBUG_SUBFOLDER_PERMISSIONS_PUBLIC ${DIR_PERMISSIONS_PUBLIC}"
        fi
    else
        #-- Fehler loggen und Return-Code setzen ----------------------------
        log_error "$MSG_ERROR_CREATE_SUBFOLDER $full_path" >&2
        return 1
    fi

    #-- Melde Erfolg zurück -------------------------------------------------
    return 0
}

# ============================================================================
# CORE FOLDER MANAGEMENT FUNCTIONS
# ============================================================================
# ============================================================================
# PATH CONSTANTS
# ============================================================================
# Globale Flags für Lazy Initialization -------------------------------------
_OUTPUT_DIR_CREATED=false                    # Ausgabe-Verzeichnis erstellt
_TEMP_DIR_CREATED=false                      # Temp-Verzeichnis erstellt
_LOG_DIR_CREATED=false                       # Log-Verzeichnis erstellt
_MOUNT_DIR_CREATED=false                     # Mount-Verzeichnis erstellt

# ===========================================================================
# folders_get_output_dir
# ---------------------------------------------------------------------------
# Funktion.: Stellt sicher, dass das Ausgabe-Verzeichnis existiert, es wird
# .........  normalerweise bei der Installation angelegt, kann aber bei
# .........  Bedarf automatisch erstellt werden (Self-Repair)
# Parameter: keine
# Rückgabe.: Pfad zum OUTPUT_DIR (ohne trailing slash)
# .........  Return-Code: 0 = Erfolg, 1 = Fehler (nicht erstellbar)
# Hinweis..: Nutzt Lazy Initialization - wird nur einmal pro Session geprüft
# .........  Erstellt Ordner automatisch wenn Parent-Dir existiert
# .........  Verwendet settings_get_output_dir() aus libsettings.sh für Pfad
# ===========================================================================
folders_get_output_dir() {
    #-- Lazy Initialization: Ausgabe-Verzeichnis nur einmal prüfen ----------
    if [[ "$_OUTPUT_DIR_CREATED" == false ]]; then
        #-- Lese Ausgabe-Verzeichnis aus Konfiguration ----------------------
        local output_dir=$(settings_get_output_dir) || {
            log_error "$MSG_ERROR_OUTPUT_DIR_READ_FAILED" >&2
            echo ""
            return 1
        }
        
        #-- Kontrolle ob das Ausgabe-Verzeichnis bereits existiert ----------
        if [[ ! -d "$output_dir" ]]; then
            log_warning "$MSG_WARNING_OUTPUT_DIR_MISSING $output_dir$MSG_SUFFIX_TRY_CREATE" >&2
            
            #-- Prüfe ob Parent-Directory existiert -------------------------
            local parent_dir="$(dirname "$output_dir")"
            if [[ ! -d "$parent_dir" ]]; then
                log_error "$MSG_ERROR_OUTPUT_DIR_PARENT_MISSING $parent_dir" >&2
                echo ""
                return 1
            fi
            
            #-- Versuche das Ausgabe-Verzeichnis zu erstellen ---------------
            if ! mkdir -p "$output_dir" 2>/dev/null; then
                log_error "$MSG_ERROR_OUTPUT_DIR_CREATE_FAILED $output_dir$MSG_SUFFIX_MISSING_PERMISSIONS" >&2
                echo ""
                return 1
            fi
            
            #-- Setze Berechtigungen ----------------------------------------
            chmod $DIR_PERMISSIONS_PUBLIC "$output_dir" 2>/dev/null
            log_info "$MSG_INFO_OUTPUT_DIR_CREATED $output_dir" >&2

            #-- Flag setzen -----------------------------------------------------
            _OUTPUT_DIR_CREATED=true
        fi
    fi

    #-- Gebe Ausgabe-Verzeichnis zurück -------------------------------------
    echo "${output_dir%/}"
    return 0
}

# ===========================================================================
# folders_get_temp_dir
# ---------------------------------------------------------------------------
# Funktion.: Prüft das Vorhandensein des Temp-Ordner unterhalb des Ausgabe-
# .........  Verzeichnis, erstellt diesen falls notwendig, und gibt den
# .........  vollständigen Pfad zurück.
# Parameter: keine
# Rückgabe.: Pfad zum Temp-Verzeichnis (ohne trailing slash)
# .........  Return-Code: 0 = Erfolg, 1 = Fehler (nicht erstellbar)
# Hinweis..: Nutzt Lazy Initialization - wird nur einmal pro Session geprüft
# ===========================================================================
folders_get_temp_dir() {
    #-- Ermitteln des kompletten Verzeichnis-Pfad ---------------------------
    local temp_dir="$(folders_get_output_dir)/.temp"

    #-- Lazy Initialization: Verzeichnis nur einmal prüfen ------------------
    if [[ "$_TEMP_DIR_CREATED" == false ]]; then
        #-- Prüfe ob Temp-Verzeichnis existiert -----------------------------
        if [[ ! -d "$temp_dir" ]]; then
            log_warning "$MSG_WARNING_TEMP_DIR_MISSING $temp_dir$MSG_SUFFIX_TRY_CREATE" >&2

            #-- Prüfe ob Parent-Directory existiert ---------------------------
            local parent_dir="$(dirname "$temp_dir")"
            if [[ ! -d "$parent_dir" ]]; then
                log_error "$MSG_ERROR_TEMP_DIR_PARENT_MISSING $parent_dir" >&2
                return 1
            fi

            #-- Versuche das Temp-Verzeichnis zu erstellen --------------------
            if ! folders_ensure_subfolder "$temp_dir"; then
                log_error "$MSG_ERROR_TEMP_DIR_CREATE_FAILED $temp_dir$MSG_SUFFIX_MISSING_PERMISSIONS" >&2
                return 1
            fi
            log_info "$MSG_INFO_TEMP_DIR_CREATED $temp_dir" >&2

            #-- Flag setzen -----------------------------------------------------
            _TEMP_DIR_CREATED=true
        fi
    fi

    #-- Gebe Verzeichnis zurück geben ---------------------------------------
    echo "${temp_dir%/}"
    return 0
}

# ===========================================================================
# folders_get_log_dir
# ---------------------------------------------------------------------------
# Funktion.: Prüft das Vorhandensein des Log-Ordner unterhalb des Ausgabe-
# .........  Verzeichnis, erstellt diesen falls notwendig, und gibt den
# .........  vollständigen Pfad zurück.
# Parameter: keine
# Rückgabe.: Pfad zum Log-Verzeichnis (ohne trailing slash)
# .........  Return-Code: 0 = Erfolg, 1 = Fehler (nicht erstellbar)
# Hinweis..: Nutzt Lazy Initialization - wird nur einmal pro Session geprüft
# .........  Log-Verzeichnis hat 777 Permissions für Multi-User-Zugriff
# ===========================================================================
folders_get_log_dir() {
    #-- Ermitteln des kompletten Verzeichnis-Pfad ---------------------------
    local log_dir="$(folders_get_output_dir)/.log"

    #-- Lazy Initialization: Verzeichnis nur einmal prüfen ------------------
    if [[ "$_LOG_DIR_CREATED" == false ]]; then
        #-- Prüfe ob Log-Verzeichnis existiert ------------------------------
        if [[ ! -d "$log_dir" ]]; then
            log_warning "$MSG_WARNING_LOG_DIR_MISSING $log_dir$MSG_SUFFIX_TRY_CREATE" >&2

            #-- Prüfe ob Parent-Directory existiert -------------------------
            local parent_dir="$(dirname "$log_dir")"
            if [[ ! -d "$parent_dir" ]]; then
                log_error "$MSG_ERROR_LOG_DIR_PARENT_MISSING $parent_dir" >&2
                return 1
            fi

            #-- Versuche das Log-Verzeichnis zu erstellen -------------------
            if ! folders_ensure_subfolder ".log"; then
                log_error "$MSG_ERROR_LOG_DIR_CREATE_FAILED $log_dir$MSG_SUFFIX_MISSING_PERMISSIONS" >&2
                return 1
            fi
            log_info "$MSG_INFO_LOG_DIR_CREATED $log_dir" >&2
        fi

        #-- Flag setzen -----------------------------------------------------
        _LOG_DIR_CREATED=true
    fi

    #-- Gebe Verzeichnis zurück ---------------------------------------------
    echo "${log_dir%/}"
    return 0
}

# ===========================================================================
# folders_get_modul_output_dir
# ---------------------------------------------------------------------------
# Funktion.: Prüft das Vorhandensein des übergebenen Modulspezifischen 
# .........  Ausgabe-Ordner unterhalb des Standard Ausgabe-Verzeichnis, 
# .........  erstellt diesen falls notwendig und gibt den vollständigen 
# .........  Pfad zurück.
# Parameter: $1 = Modulspezifischer Unterordner (optional, default: "data")
# Rückgabe.: Pfad zum Modulspezifischen-Verzeichnis (ohne trailing slash)
# .........  Return-Code: 0 = Erfolg, 1 = Fehler (nicht erstellbar)
# ===========================================================================
folders_get_modul_output_dir() {
    #-- Paramter Handling und Ermitteln des kompletten Verzeichnis-Pfad -----
    local module_subdir="$(folders_get_output_dir)/${1:-$DATA_DIR}"

    #-- Prüfe ob Data-Verzeichnis existiert ---------------------------------
    if [[ ! -d "$module_subdir" ]]; then
        log_warning "$MSG_WARNING_MODULE_DIR_MISSING $module_subdir$MSG_SUFFIX_TRY_CREATE" >&2

        #-- Prüfe ob Parent-Directory existiert -----------------------------
        local parent_dir="$(dirname "$module_subdir")"
        if [[ ! -d "$parent_dir" ]]; then
            log_error "$MSG_ERROR_MODULE_DIR_PARENT_MISSING $parent_dir" >&2
            return 1
        fi

        #-- Versuche das Data-Verzeichnis zu erstellen ----------------------
        if ! folders_ensure_subfolder "$module_subdir"; then
            log_error "$MSG_ERROR_MODULE_DIR_CREATE_FAILED $module_subdir$MSG_SUFFIX_MISSING_PERMISSIONS" >&2
            return 1
        fi
        log_info "$MSG_INFO_MODULE_DIR_CREATED $module_subdir" >&2
    fi

    #-- Gebe Verzeichnis zurück ---------------------------------------------
    echo "${module_subdir%/}"
    return 0
}

# ============================================================================
# TEMP FOLDER MANAGEMENT
# ============================================================================

# ===========================================================================
# folders_get_mount_dir
# ---------------------------------------------------------------------------
# Funktion.: Prüft das Vorhandensein des Mount-Ordner unterhalb des Temp-
# .........  Verzeichnis, erstellt diesen falls notwendig, und gibt den
# .........  vollständigen Pfad zurück.
# Parameter: keine
# Rückgabe.: Pfad zum Mount-Verzeichnis (ohne trailing slash)
# .........  Return-Code: 0 = Erfolg, 1 = Fehler (nicht erstellbar)
# Hinweis..: Nutzt Lazy Initialization - wird nur einmal pro Session geprüft
# .........  Mount-Verzeichnis hat 777 Permissions für Multi-User-Zugriff
# .........  Pfad: ${OUTPUT_DIR}/.temp/mountpoints
# ===========================================================================
folders_get_mount_dir() {
    #-- Ermitteln des kompletten Verzeichnis-Pfad ---------------------------
    local mount_dir="$(folders_get_temp_dir)/mountpoints"

    #-- Lazy Initialization: Verzeichnis nur einmal prüfen ------------------
    if [[ "$_MOUNT_DIR_CREATED" == false ]]; then
        #-- Prüfe ob Mount-Verzeichnis existiert ----------------------------
        if [[ ! -d "$mount_dir" ]]; then
            log_warning "$MSG_WARNING_MOUNT_DIR_MISSING $mount_dir$MSG_SUFFIX_TRY_CREATE" >&2

            #-- Prüfe ob Parent-Directory existiert -------------------------
            local parent_dir="$(dirname "$mount_dir")"
            if [[ ! -d "$parent_dir" ]]; then
                log_error "$MSG_ERROR_MOUNT_DIR_PARENT_MISSING $parent_dir" >&2
                return 1
            fi

            #-- Versuche das Mount-Verzeichnis zu erstellen -----------------
            if ! folders_ensure_subfolder "$MOUNTPOINTS_DIR"; then
                log_error "$MSG_ERROR_MOUNT_DIR_CREATE_FAILED $mount_dir$MSG_SUFFIX_MISSING_PERMISSIONS" >&2
                return 1
            fi
            log_info "$MSG_INFO_MOUNT_DIR_CREATED $mount_dir" >&2
        fi

        #-- Flag setzen -----------------------------------------------------
        _MOUNT_DIR_CREATED=true
    fi

    #-- Gebe Verzeichnis zurück ---------------------------------------------
    echo "${mount_dir%/}"
    return 0
}

# ===========================================================================
# folders_get_unique_mountpoint
# ---------------------------------------------------------------------------
# Funktion.: Erstellt einen eindeutigen temporären Mount-Point
# Parameter: keine
# Rückgabe.: Pfad zum Mount-Point (individueller Unterordner)
# .........  Return-Code: 0 = Erfolg, 1 = Fehler (nicht erstellbar)
# Hinweis..: Nutzt folders_get_mount_dir() für konsistentes Base-Verzeichnis
# .........  Generiert eindeutigen Namen mit PID und RANDOM
# .........  Jeder Aufruf erstellt einen NEUEN Mount-Point
# ===========================================================================
folders_get_unique_mountpoint() {
    #-- Hole Mount-Base-Verzeichnis (mit Lazy Initialization) ---------------
    local mount_base=$(folders_get_mount_dir) || return 1
    
    #-- Generiere eindeutigen Mount-Point Namen ----------------------------
    local mount_point="${mount_base}/mount_$$_${RANDOM}"
    
    #-- Erstelle Mount-Point ------------------------------------------------
    if ! mkdir -p "$mount_point" 2>/dev/null; then
        log_error "$MSG_ERROR_MOUNT_POINT_CREATE_FAILED $mount_point" >&2
        return 1
    fi
    
    #-- Setze Berechtigungen für Multi-User-Zugriff ------------------------
    chmod $DIR_PERMISSIONS_PUBLIC "$mount_point" 2>/dev/null
    
    #-- Gebe Mount-Point zurück ---------------------------------------------
    echo "$mount_point"
    return 0
}

# ===========================================================================
# PATH GETTER FÜR CORE VERZEICHNISSE
# ===========================================================================
# ---------------------------------------------------------------------------
# Ordner für Core-Modul-Komponenten (relativ zu INSTALL_DIR)
# ---------------------------------------------------------------------------
readonly MODULE_LIB_DIR="lib"                    # Bash-Module
readonly MODULE_LANG_DIR="lang"                  # Sprachdateien
readonly MODULE_CONF_DIR="conf"                  # Konfiguration
readonly MODULE_DOC_DIR="doc"                    # Dokumentation
readonly MODULE_API_DIR="api"                    # API JSON-Dateien

# ===========================================================================
# folders_get_lib_dir
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Pfad zum Library-Verzeichnis für Bash-Module
# Parameter: keine
# Rückgabe.: 0 = Ordner existiert (Pfad in stdout)
# .........  1 = Ordner fehlt (leerer String in stdout)
# Beispiel.: folders_get_lib_dir → "/opt/disk2iso/lib"
# Hinweis..: Erstellt KEINEN Ordner - nur von install.sh erstellt
# ===========================================================================
folders_get_lib_dir() {
    #-- Ermitteln des kompletten Verzeichnis-Pfad ---------------------------
    local lib_dir="${INSTALL_DIR}/${MODULE_LIB_DIR}"
    
    #-- Prüfe ob Verzeichnis existiert --------------------------------------
    if [[ ! -d "$lib_dir" ]]; then
        echo ""
        return 1
    fi
    
    #-- Gebe Verzeichnis zurück ---------------------------------------------
    echo "$lib_dir"
    return 0
}

# ===========================================================================
# folders_get_lang_dir
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Pfad zum Sprach-Verzeichnis für Language-Dateien
# Parameter: keine
# Rückgabe.: 0 = Ordner existiert (Pfad in stdout)
# .........  1 = Ordner fehlt (leerer String in stdout)
# Beispiel.: folders_get_lang_dir → "/opt/disk2iso/lang"
# Hinweis..: Erstellt KEINEN Ordner - nur von install.sh erstellt
# ===========================================================================
folders_get_lang_dir() {
    #-- Ermitteln des kompletten Verzeichnis-Pfad ---------------------------
    local lang_dir="${INSTALL_DIR}/${MODULE_LANG_DIR}"
    
    #-- Prüfe ob Verzeichnis existiert --------------------------------------
    if [[ ! -d "$lang_dir" ]]; then
        echo ""
        return 1
    fi
    
    #-- Gebe Verzeichnis zurück ---------------------------------------------
    echo "$lang_dir"
    return 0
}

# ===========================================================================
# folders_get_conf_dir
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Pfad zum Konfigurations-Verzeichnis
# Parameter: keine
# Rückgabe.: 0 = Ordner existiert (Pfad in stdout)
# .........  1 = Ordner fehlt (leerer String in stdout)
# Beispiel.: folders_get_conf_dir → "/opt/disk2iso/conf"
# Hinweis..: Erstellt KEINEN Ordner - nur von install.sh erstellt
# ===========================================================================
folders_get_conf_dir() {
    #-- Ermitteln des kompletten Verzeichnis-Pfad ---------------------------
    local conf_dir="${INSTALL_DIR}/${MODULE_CONF_DIR}"
    
    #-- Prüfe ob Verzeichnis existiert --------------------------------------
    if [[ ! -d "$conf_dir" ]]; then
        echo ""
        return 1
    fi
    
    #-- Gebe Verzeichnis zurück ---------------------------------------------
    echo "$conf_dir"
    return 0
}

# ===========================================================================
# folders_get_doc_dir
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Pfad zum Dokumentations-Verzeichnis
# Parameter: keine
# Rückgabe.: 0 = Ordner existiert (Pfad in stdout)
# .........  1 = Ordner fehlt (leerer String in stdout)
# Beispiel.: folders_get_doc_dir → "/opt/disk2iso/doc"
# Hinweis..: Erstellt KEINEN Ordner - nur von install.sh erstellt
# ===========================================================================
folders_get_doc_dir() {
    #-- Ermitteln des kompletten Verzeichnis-Pfad ---------------------------
    local doc_dir="${INSTALL_DIR}/${MODULE_DOC_DIR}"
    
    #-- Prüfe ob Verzeichnis existiert --------------------------------------
    if [[ ! -d "$doc_dir" ]]; then
        echo ""
        return 1
    fi
    
    #-- Gebe Verzeichnis zurück ---------------------------------------------
    echo "$doc_dir"
    return 0
}

# ===========================================================================
# folders_get_api_dir
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Pfad zum API-Verzeichnis für JSON-Dateien
# Parameter: keine
# Rückgabe.: 0 = Ordner existiert (Pfad in stdout)
# .........  1 = Ordner fehlt (leerer String in stdout)
# Beispiel.: folders_get_api_dir → "/opt/disk2iso/api"
# Hinweis..: Erstellt KEINEN Ordner - nur von install.sh erstellt
# ===========================================================================
folders_get_api_dir() {
    #-- Ermitteln des kompletten Verzeichnis-Pfad ---------------------------
    local api_dir="${INSTALL_DIR}/${MODULE_API_DIR}"
    
    #-- Prüfe ob Verzeichnis existiert --------------------------------------
    if [[ ! -d "$api_dir" ]]; then
        echo ""
        return 1
    fi
    
    #-- Gebe Verzeichnis zurück ---------------------------------------------
    echo "$api_dir"
    return 0
}

# ---------------------------------------------------------------------------
# Ordner für Web-Frontend (relativ zu INSTALL_DIR)
# ---------------------------------------------------------------------------
readonly MODULE_HTML_DIR="services/disk2iso-web/templates"  # HTML-Partials
readonly MODULE_CSS_DIR="services/disk2iso-web/static/css"  # Stylesheets
readonly MODULE_JS_DIR="services/disk2iso-web/static/js"    # JavaScript

# ===========================================================================
# folders_get_html_dir
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Pfad zum HTML-Template-Verzeichnis
# Parameter: keine
# Rückgabe.: 0 = Ordner existiert (Pfad in stdout)
# .........  1 = Ordner fehlt (leerer String in stdout)
# Beispiel.: folders_get_html_dir → "/opt/disk2iso/services/disk2iso-web/templates"
# Hinweis..: Erstellt KEINEN Ordner - nur von install.sh erstellt
# ===========================================================================
folders_get_html_dir() {
    #-- Ermitteln des kompletten Verzeichnis-Pfad ---------------------------
    local html_dir="${INSTALL_DIR}/${MODULE_HTML_DIR}"
    
    #-- Prüfe ob Verzeichnis existiert --------------------------------------
    if [[ ! -d "$html_dir" ]]; then
        echo ""
        return 1
    fi
    
    #-- Gebe Verzeichnis zurück ---------------------------------------------
    echo "$html_dir"
    return 0
}

# ===========================================================================
# folders_get_css_dir
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Pfad zum CSS-Verzeichnis für Stylesheets
# Parameter: keine
# Rückgabe.: 0 = Ordner existiert (Pfad in stdout)
# .........  1 = Ordner fehlt (leerer String in stdout)
# Beispiel.: folders_get_css_dir → "/opt/disk2iso/services/disk2iso-web/static/css"
# Hinweis..: Erstellt KEINEN Ordner - nur von install.sh erstellt
# ===========================================================================
folders_get_css_dir() {
    #-- Ermitteln des kompletten Verzeichnis-Pfad ---------------------------
    local css_dir="${INSTALL_DIR}/${MODULE_CSS_DIR}"
    
    #-- Prüfe ob Verzeichnis existiert --------------------------------------
    if [[ ! -d "$css_dir" ]]; then
        echo ""
        return 1
    fi
    
    #-- Gebe Verzeichnis zurück ---------------------------------------------
    echo "$css_dir"
    return 0
}

# ===========================================================================
# folders_get_js_dir
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Pfad zum JavaScript-Verzeichnis
# Parameter: keine
# Rückgabe.: 0 = Ordner existiert (Pfad in stdout)
# .........  1 = Ordner fehlt (leerer String in stdout)
# Beispiel.: folders_get_js_dir → "/opt/disk2iso/services/disk2iso-web/static/js"
# Hinweis..: Erstellt KEINEN Ordner - nur von install.sh erstellt
# ===========================================================================
folders_get_js_dir() {
    #-- Ermitteln des kompletten Verzeichnis-Pfad ---------------------------
    local js_dir="${INSTALL_DIR}/${MODULE_JS_DIR}"
    
    #-- Prüfe ob Verzeichnis existiert --------------------------------------
    if [[ ! -d "$js_dir" ]]; then
        echo ""
        return 1
    fi
    
    #-- Gebe Verzeichnis zurück ---------------------------------------------
    echo "$js_dir"
    return 0
}

# ---------------------------------------------------------------------------
# Ordner für Web-Backend (relativ zu INSTALL_DIR)
# ---------------------------------------------------------------------------
readonly MODULE_ROUTER_DIR="services/disk2iso-web/routes"  # Python-Routes

# ===========================================================================
# folders_get_router_dir
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Pfad zum Python-Router-Verzeichnis
# Parameter: keine
# Rückgabe.: 0 = Ordner existiert (Pfad in stdout)
# .........  1 = Ordner fehlt (leerer String in stdout)
# Beispiel.: folders_get_router_dir → "/opt/disk2iso/services/disk2iso-web/routes"
# Hinweis..: Erstellt KEINEN Ordner - nur von install.sh erstellt
# ===========================================================================
folders_get_router_dir() {
    #-- Ermitteln des kompletten Verzeichnis-Pfad ---------------------------
    local router_dir="${INSTALL_DIR}/${MODULE_ROUTER_DIR}"
    
    #-- Prüfe ob Verzeichnis existiert --------------------------------------
    if [[ ! -d "$router_dir" ]]; then
        echo ""
        return 1
    fi
    
    #-- Gebe Verzeichnis zurück ---------------------------------------------
    echo "$router_dir"
    return 0
}

# ============================================================================
# ENDE DER FOLDER MANAGEMENT LIBRARY
# ============================================================================
