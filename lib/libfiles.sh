#!/bin/bash
# =============================================================================
# File Management Library
# =============================================================================
# Filepath: lib/libfiles.sh
#
# Beschreibung:
#   Verwaltung von Dateinamen und Datei-Operationen
#   - Dateinamen-Bereinigung (sanitize_filename)
#   - ISO-Dateinamen-Generierung
#   - MD5/LOG-Dateinamen-Ableitung
#   - Basename-Extraktion
#
# -----------------------------------------------------------------------------
# Dependencies: Keine (nutzt nur Bash-Funktionen)
# -----------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.2.1
# Last Change: 2026-01-26 20:00
# =============================================================================

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

# ===========================================================================
# files_check_dependencies
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
files_check_dependencies() {
    # Lade Sprachdatei für dieses Modul
    load_module_language "files"
    
    # Files-Modul benötigt keine externen Tools
    # Verwendet nur Bash-Funktionen (basename, sed)
    return 0
}

# ============================================================================
# FAILED DISC TRACKING PATH
# ============================================================================
readonly FAILED_DISCS_FILE=".failed_discs"    # Zentrale Fehler-Tracking Datei

# ===========================================================================
# get_failed_disc_path
# ---------------------------------------------------------------------------
# Funktion.: Liefert Pfad zur Failed-Disc-Tracking-Datei (INI-Format)
# Parameter: keine
# Rückgabe.: 0 = Datei existiert/wurde erstellt (Pfad in stdout)
#            1 = Fehler beim Erstellen/Zugriff
# Beispiel.: local failed_file
#            failed_file=$(get_failed_disc_path) || return 1
#            → "/media/iso/.failed_discs"
# Extras...: Erstellt Datei automatisch falls nicht vorhanden
#            Nutzt folders_get_output_dir() aus libfolders.sh
#            Pattern für alle Dateipfad-Funktionen in libfiles.sh
# ===========================================================================
get_failed_disc_path() {
    #-- Eröffne Debug-Log ---------------------------------------------------
    log_debug "get_failed_disc_path: Start"

    #-- Ermittle Ausgabe-Ordner ---------------------------------------------    
    local out_dir
    out_dir=$(folders_get_output_dir) || {
        log_error "get_failed_disc_path: folders_get_output_dir fehlgeschlagen"
        return 1
    }
    
    #-- Vollständigen Pfad zur Failed-Disc-Datei erstellen ------------------
    local failed_file="${out_dir}/${FAILED_DISCS_FILE}"
    
    #-- Prüfe ob Datei bereits existiert ------------------------------------
    if [[ -f "$failed_file" ]]; then
        log_debug "get_failed_disc_path: Datei existiert bereits: $failed_file"
        echo "$failed_file"
        return 0
    fi
    
    #-- Erstelle Datei mit INI-Header ---------------------------------------
    log_debug "get_failed_disc_path: Erstelle neue Datei: $failed_file"
    {
        echo "# Failed Disc Tracking (INI Format)"
        echo "# Format: UUID:LABEL:SIZE_MB=timestamp|method|retry_count"
        echo "# Sections: [data], [audio], [dvd], [bluray]"
        echo ""
    } > "$failed_file"
    
    if [[ $? -eq 0 ]]; then
        #-- Prüfe ob Erstellung erfolgreich war -----------------------------
        if [[ -f "$failed_file" ]]; then
            log_debug "get_failed_disc_path: Datei erfolgreich erstellt: $failed_file"
            echo "$failed_file"
            return 0
        else
            log_error "get_failed_disc_path: Datei-Erstellung fehlgeschlagen (Datei nicht vorhanden): $failed_file"
            return 1
        fi
    else
        log_error "get_failed_disc_path: Datei-Erstellung fehlgeschlagen (cat-Fehler): $failed_file"
        return 1
    fi
}

# ============================================================================
# FILENAME SANITIZATION
# ============================================================================

# Funktion zur Bereinigung des Dateinamens
# Entfernt ungültige Zeichen für Dateinamen
sanitize_filename() {
    local filename="$1"
    # Entferne ungültige Zeichen und ersetze sie durch Unterstriche
    echo "$filename" | sed 's/[<>:"/\\|?*]/_/g' | sed 's/[[:space:]]/_/g' | sed 's/__*/_/g'
}

# ============================================================================
# FILENAME GENERATION
# ============================================================================

# ===========================================================================
# get_unique_iso_path
# ---------------------------------------------------------------------------
# Funktion.: Finde eindeutigen Dateinamen mit Auto-Increment
# Parameter: $1 = target_dir (Zielverzeichnis)
#            $2 = base_name (Basis-Name ohne .iso)
#            $3 = existing_file (optional, existierende Datei die umbenannt wird)
# Rückgabe.: Eindeutiger Pfad (mit _1, _2 etc. falls nötig)
# ===========================================================================
get_unique_iso_path() {
    local target_dir="$1"
    local base_name="$2"
    local existing_file="${3:-}"
    
    local base_filename="${base_name}.iso"
    local full_path="${target_dir}/${base_filename}"
    
    # Prüfe ob Datei bereits existiert und füge Nummer hinzu
    local counter=1
    while [[ -f "$full_path" ]] && [[ "$full_path" != "$existing_file" ]]; do
        base_filename="${base_name}_${counter}.iso"
        full_path="${target_dir}/${base_filename}"
        ((counter++))
    done
    
    echo "$full_path"
}

# ============================================================================
# FILENAME INITIALIZATION
# ============================================================================

# ===========================================================================
# init_filenames
# ---------------------------------------------------------------------------
# Funktion.: Initialisiere alle Dateinamen basierend auf disc_label und disc_type
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beschr...: Setzt DISC_INFO Felder: iso_filename, md5_filename, log_filename,
#            iso_basename, temp_pathname
#            Nutzt discinfo_get_label() und discinfo_get_type()
#            WICHTIG: Muss NACH Metadata-Auswahl aufgerufen werden!
# ===========================================================================
init_filenames() {
    # Prüfe ob disc_label und disc_type bereits gesetzt sind
    local disc_label
    local disc_type
    
    if ! disc_label=$(discinfo_get_label); then
        log_error \"init_filenames: disc_label nicht gesetzt!\"
        return 1
    fi
    
    if ! disc_type=$(discinfo_get_type); then
        log_error \"init_filenames: disc_type nicht gesetzt!\"
        return 1
    fi
    
    # 1. ISO-Dateinamen generieren
    local target_dir
    case "$disc_type" in
        audio-cd)
            target_dir=$(get_path_audio)
            ;;
        cd-rom|dvd-rom|bd-rom)
            target_dir=$(folders_get_modul_output_dir)
            ;;
        dvd-video)
            target_dir=$(get_path_dvd)
            ;;
        bd-video)
            target_dir=$(get_path_bluray)
            ;;
        *)
            target_dir=$(folders_get_modul_output_dir)
            ;;
    esac
    local iso_path=$(get_unique_iso_path \"$target_dir\" \"$disc_label\")
    discinfo_set_iso_filename \"$iso_path\"
    
    # 2. MD5-Dateinamen ableiten
    local md5_path=\"${iso_path%.iso}.md5\"
    discinfo_set_md5_filename \"$md5_path\"
    
    # 3. Log-Dateinamen ableiten (im separaten log/ Verzeichnis)
    local base_name=$(basename \"${iso_path%.iso}\")
    local log_path="$(folders_get_log_dir)/${base_name}.log"
    discinfo_set_log_filename \"$log_path\"
    
    # 4. ISO-Basisname extrahieren
    local iso_base=$(basename \"$iso_path\")
    discinfo_set_iso_basename \"$iso_base\"
    
    # 5. Temp-Pathname erstellen (falls nicht bereits vorhanden)
    local temp_path
    if ! temp_path=$(discinfo_get_temp_pathname); then
        temp_path=$(folders_get_temp_dir)
        discinfo_set_temp_pathname \"$temp_path\"
    fi
    
    # Setze alte globale Variablen für Rückwärtskompatibilität (DEPRECATED)
    iso_filename=\"$iso_path\"
    md5_filename=\"$md5_path\"
    log_filename=\"$log_path\"
    iso_basename=\"$iso_base\"
    temp_pathname=\"$temp_path\"
    
    log_debug \"init_filenames: ISO='$iso_path', MD5='$md5_path', LOG='$log_path', TEMP='$temp_path'\"
    return 0
}

# ============================================================================
# MODULE INI PATH HELPER
# ============================================================================

# ===========================================================================
# get_module_ini_path
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt vollständigen Pfad zur Modul-INI-Datei (Self-Healing)
# Parameter: $1 = module_name (z.B. "tmdb", "audio", "metadata")
# Rückgabe.: 0 = Datei existiert/wurde erstellt (Pfad in stdout)
#            1 = Fehler (Parameter fehlt oder Erstellung fehlgeschlagen)
# Beispiel.: local ini_file
#            ini_file=$(get_module_ini_path "tmdb") || return 1
#            → "/opt/disk2iso/conf/libtmdb.ini"
# Extras...: Erstellt Datei automatisch falls nicht vorhanden (Heile dich selbst)
# Nutzt....: folders_get_conf_dir() aus libfolders.sh
# ===========================================================================
get_module_ini_path() {
    local module_name="$1"
    
    if [[ -z "$module_name" ]]; then
        log_error "get_module_ini_path: Module name missing" 2>/dev/null || echo "ERROR: Module name missing" >&2
        return 1
    fi
    
    local conf_dir
    conf_dir=$(folders_get_conf_dir) || {
        log_error "get_module_ini_path: folders_get_conf_dir failed" 2>/dev/null || echo "ERROR: folders_get_conf_dir failed" >&2
        return 1
    }
    
    local ini_file="${conf_dir}/lib${module_name}.ini"
    
    # Prüfe ob Datei bereits existiert
    if [[ -f "$ini_file" ]]; then
        echo "$ini_file"
        return 0
    fi
    
    # Erstelle Datei mit INI-Header (Self-Healing)
    log_debug "get_module_ini_path: Creating missing INI file: $ini_file" 2>/dev/null
    {
        echo "# Module Configuration: lib${module_name}.ini"
        echo "# Auto-generated on $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
    } > "$ini_file"
    
    if [[ $? -eq 0 ]] && [[ -f "$ini_file" ]]; then
        log_debug "get_module_ini_path: File created successfully: $ini_file" 2>/dev/null
        echo "$ini_file"
        return 0
    else
        log_error "get_module_ini_path: File creation failed: $ini_file" 2>/dev/null || echo "ERROR: File creation failed" >&2
        return 1
    fi
}

# ===========================================================================
# get_module_conf_path
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt vollständigen Pfad zur Modul-CONF-Datei (Self-Healing)
# Parameter: $1 = module_name (z.B. "disk2iso")
# Rückgabe.: 0 = Datei existiert/wurde erstellt (Pfad in stdout)
#            1 = Fehler (Parameter fehlt oder Erstellung fehlgeschlagen)
# Beispiel.: local conf_file
#            conf_file=$(get_module_conf_path "disk2iso") || return 1
#            → "/opt/disk2iso/conf/disk2iso.conf"
# Extras...: Erstellt Datei automatisch falls nicht vorhanden (Heile dich selbst)
# Nutzt....: folders_get_conf_dir() aus libfolders.sh
# ===========================================================================
get_module_conf_path() {
    local module_name="$1"
    
    if [[ -z "$module_name" ]]; then
        log_error "get_module_conf_path: Module name missing" 2>/dev/null || echo "ERROR: Module name missing" >&2
        return 1
    fi
    
    local conf_dir
    conf_dir=$(folders_get_conf_dir) || {
        log_error "get_module_conf_path: folders_get_conf_dir failed" 2>/dev/null || echo "ERROR: folders_get_conf_dir failed" >&2
        return 1
    }
    
    local conf_file="${conf_dir}/${module_name}.conf"
    
    # Prüfe ob Datei bereits existiert
    if [[ -f "$conf_file" ]]; then
        echo "$conf_file"
        return 0
    fi
    
    # Erstelle Datei mit CONF-Header (Self-Healing)
    log_debug "get_module_conf_path: Creating missing CONF file: $conf_file" 2>/dev/null
    {
        echo "# Module Configuration: ${module_name}.conf"
        echo "# Auto-generated on $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
    } > "$conf_file"
    
    if [[ $? -eq 0 ]] && [[ -f "$conf_file" ]]; then
        log_debug "get_module_conf_path: File created successfully: $conf_file" 2>/dev/null
        echo "$conf_file"
        return 0
    else
        log_error "get_module_conf_path: File creation failed: $conf_file" 2>/dev/null || echo "ERROR: File creation failed" >&2
        return 1
    fi
}

# ============================================================================
# FILE PATH GETTER (INSTALL_DIR-BASED)
# ============================================================================

# ===========================================================================
# files_get_lib_path
# ---------------------------------------------------------------------------
# Funktion.: Liefert vollständigen Pfad zu einem Bash-Modul
# Parameter: $1 = filename (z.B. "libmetadata.sh" oder "metadata" [DEPRECATED])
# Rückgabe.: Vollständiger Pfad zur Datei
# Beispiel.: files_get_lib_path "libmetadata.sh"
#            → "/opt/disk2iso/lib/libmetadata.sh"
#            files_get_lib_path "metadata"  # DEPRECATED
#            → "/opt/disk2iso/lib/libmetadata.sh"
# Nutzt....: folders_get_lib_dir() aus libfolders.sh
# Hinweis..: Fallback für Modulname (ohne lib-Prefix/Suffix) ist DEPRECATED
# ===========================================================================
files_get_lib_path() {
    local filename="$1"
    
    if [[ -z "$filename" ]]; then
        return 1
    fi
    
    # DEPRECATED: Automatische Konstruktion wenn nur Modulname übergeben wurde
    if [[ "$filename" != *.sh ]]; then
        log_warning "files_get_lib_path: DEPRECATED - Bitte vollständigen Dateinamen verwenden statt Modulname: '${filename}'"
        filename="lib${filename}.sh"
    fi
    
    local lib_dir
    lib_dir=$(folders_get_lib_dir) || return 1
    
    echo "${lib_dir}/${filename}"
}

# ===========================================================================
# files_get_lang_path
# ---------------------------------------------------------------------------
# Funktion.: Liefert vollständigen Pfad zu einer Sprachdatei
# Parameter: $1 = filename (z.B. "libfolders", "libfolders.de" oder "folders" [DEPRECATED])
# Rückgabe.: Vollständiger Pfad zur Datei (mit Wildcard wenn ohne Suffix)
# Beispiel.: files_get_lang_path "libfolders.de"
#            → "/opt/disk2iso/lang/libfolders.de"
#            files_get_lang_path "libfolders"
#            → "/opt/disk2iso/lang/libfolders.*"
#            files_get_lang_path "folders"  # DEPRECATED
#            → "/opt/disk2iso/lang/libfolders.*"
# Nutzt....: folders_get_lang_dir() aus libfolders.sh
# Hinweis..: Ohne Suffix (.de/.en/.es/.fr) wird Wildcard-Pattern zurückgegeben
#            Fallback für Modulname (ohne lib-Prefix) ist DEPRECATED
# ===========================================================================
files_get_lang_path() {
    local filename="$1"
    
    if [[ -z "$filename" ]]; then
        return 1
    fi
    
    # DEPRECATED: Automatische Konstruktion wenn nur Modulname übergeben wurde
    if [[ "$filename" != lib* ]] && [[ "$filename" != debug* ]]; then
        log_warning "files_get_lang_path: DEPRECATED - Bitte vollständigen Dateinamen verwenden statt Modulname: '${filename}'"
        filename="lib${filename}"
    fi
    
    local lang_dir
    lang_dir=$(folders_get_lang_dir) || return 1
    
    # Prüfe ob Dateiname bereits Sprach-Suffix hat
    if [[ "$filename" =~ \.(de|en|es|fr|it)$ ]]; then
        echo "${lang_dir}/${filename}"
    else
        # Gib Pattern zurück (für Existenz-Check mit Wildcard)
        echo "${lang_dir}/${filename}.*"
    fi
}

# ===========================================================================
# files_get_conf_path
# ---------------------------------------------------------------------------
# Funktion.: Liefert vollständigen Pfad zu einer Konfigurations-Datei
# Parameter: $1 = filename (z.B. "disk2iso.conf", "libtmdb.ini" oder "tmdb" [DEPRECATED])
# Rückgabe.: Vollständiger Pfad zur Datei
# Beispiel.: files_get_conf_path "disk2iso.conf"
#            → "/opt/disk2iso/conf/disk2iso.conf"
#            files_get_conf_path "libtmdb.ini"
#            → "/opt/disk2iso/conf/libtmdb.ini"
#            files_get_conf_path "tmdb"  # DEPRECATED
#            → "/opt/disk2iso/conf/libtmdb.ini"
# Nutzt....: folders_get_conf_dir() aus libfolders.sh
# Hinweis..: Fallback für Modulname (ohne lib-Prefix/Suffix) ist DEPRECATED
# ===========================================================================
files_get_conf_path() {
    local filename="$1"
    
    if [[ -z "$filename" ]]; then
        return 1
    fi
    
    # DEPRECATED: Automatische Konstruktion wenn nur Modulname übergeben wurde
    if [[ "$filename" != *.* ]] && [[ "$filename" != disk2iso ]]; then
        log_warning "files_get_conf_path: DEPRECATED - Bitte vollständigen Dateinamen verwenden statt Modulname: '${filename}'"
        filename="lib${filename}.ini"
    fi
    
    local conf_dir
    conf_dir=$(folders_get_conf_dir) || return 1
    
    echo "${conf_dir}/${filename}"
}

# ===========================================================================
# files_get_doc_path
# ---------------------------------------------------------------------------
# Funktion.: Liefert vollständigen Pfad zu einer Dokumentations-Datei
# Parameter: $1 = filename (z.B. "Handbuch.md" oder "Installation.md")
# Rückgabe.: Vollständiger Pfad zur Datei
# Beispiel.: files_get_doc_path "Handbuch.md"
#            → "/opt/disk2iso/doc/Handbuch.md"
# Nutzt....: folders_get_doc_dir() aus libfolders.sh
# ===========================================================================
files_get_doc_path() {
    local filename="$1"
    
    if [[ -z "$filename" ]]; then
        return 1
    fi
    
    local doc_dir
    doc_dir=$(folders_get_doc_dir) || return 1
    
    echo "${doc_dir}/${filename}"
}

# ===========================================================================
# files_get_html_path
# ---------------------------------------------------------------------------
# Funktion.: Liefert vollständigen Pfad zu einem HTML-Template
# Parameter: $1 = filename (z.B. "header.html" oder "footer.html")
# Rückgabe.: Vollständiger Pfad zur Datei
# Beispiel.: files_get_html_path "header.html"
#            → "/opt/disk2iso/www/templates/header.html"
# Nutzt....: folders_get_html_dir() aus libfolders.sh
# ===========================================================================
files_get_html_path() {
    local filename="$1"
    
    if [[ -z "$filename" ]]; then
        return 1
    fi
    
    local html_dir
    html_dir=$(folders_get_html_dir) || return 1
    
    echo "${html_dir}/${filename}"
}

# ===========================================================================
# files_get_css_path
# ---------------------------------------------------------------------------
# Funktion.: Liefert vollständigen Pfad zu einem CSS-Stylesheet
# Parameter: $1 = filename (z.B. "main.css" oder "theme.css")
# Rückgabe.: Vollständiger Pfad zur Datei
# Beispiel.: files_get_css_path "main.css"
#            → "/opt/disk2iso/www/static/css/main.css"
# Nutzt....: folders_get_css_dir() aus libfolders.sh
# ===========================================================================
files_get_css_path() {
    local filename="$1"
    
    if [[ -z "$filename" ]]; then
        return 1
    fi
    
    local css_dir
    css_dir=$(folders_get_css_dir) || return 1
    
    echo "${css_dir}/${filename}"
}

# ===========================================================================
# files_get_js_path
# ---------------------------------------------------------------------------
# Funktion.: Liefert vollständigen Pfad zu einer JavaScript-Datei
# Parameter: $1 = filename (z.B. "app.js" oder "utils.js")
# Rückgabe.: Vollständiger Pfad zur Datei
# Beispiel.: files_get_js_path "app.js"
#            → "/opt/disk2iso/www/static/js/app.js"
# Nutzt....: folders_get_js_dir() aus libfolders.sh
# ===========================================================================
files_get_js_path() {
    local filename="$1"
    
    if [[ -z "$filename" ]]; then
        return 1
    fi
    
    local js_dir
    js_dir=$(folders_get_js_dir) || return 1
    
    echo "${js_dir}/${filename}"
}

# ===========================================================================
# files_get_router_path
# ---------------------------------------------------------------------------
# Funktion.: Liefert vollständigen Pfad zu einer Python-Router-Datei
# Parameter: $1 = filename (z.B. "api.py" oder "routes_api.py")
# Rückgabe.: Vollständiger Pfad zur Datei
# Beispiel.: files_get_router_path "api.py"
#            → "/opt/disk2iso/www/routes/routes_api.py"
#            files_get_router_path "routes_api.py"
#            → "/opt/disk2iso/www/routes/routes_api.py"
# Nutzt....: folders_get_router_dir() aus libfolders.sh
# Hinweis..: Fügt automatisch "routes_" Prefix hinzu wenn nicht vorhanden
# ===========================================================================
files_get_router_path() {
    local filename="$1"
    
    if [[ -z "$filename" ]]; then
        return 1
    fi
    
    local router_dir
    router_dir=$(folders_get_router_dir) || return 1
    
    # Füge "routes_" Prefix hinzu wenn nicht vorhanden
    if [[ "$filename" == routes_* ]]; then
        echo "${router_dir}/${filename}"
    else
        echo "${router_dir}/routes_${filename}"
    fi
}

# ============================================================================
# MODULE FOLDER PATH WITH INI FALLBACK LOGIC
# ============================================================================

# ===========================================================================
# files_get_module_folder_path
# ---------------------------------------------------------------------------
# Funktion.: Ermittle vollständigen Pfad zu Modul-Ordner mit Fallback-Logik
# Parameter: $1 = module_name (z.B. "tmdb", "audio", "metadata")
#            $2 = folder_type (z.B. "cache", "covers", "temp", "logs")
# Rückgabe.: Vollständiger Pfad zum Ordner
# Beispiel.: files_get_module_folder_path "tmdb" "cache"
#            → "/media/iso/metadata/tmdb/cache"
# Fallbacks: 1. [folders] <folder_type> aus INI (spezifisch)
#            2. [folders] output aus INI + /<folder_type> (konstruiert)
#            3. folders_get_output_dir() + /<folder_type> (global)
# Nutzt....: get_module_ini_path() für INI-Datei
#            config_get_value_ini() aus libconfig.sh für Werte
#            folders_get_output_dir() aus libfolders.sh als Fallback
# ===========================================================================
files_get_module_folder_path() {
    local module_name="$1"
    local folder_type="$2"
    
    if [[ -z "$module_name" ]] || [[ -z "$folder_type" ]]; then
        return 1
    fi
    
    local folder_path
    local output_path
    
    # 1. Primär: Spezifischer Ordner aus INI
    folder_path=$(config_get_value_ini "$module_name" "folders" "$folder_type")
    
    if [[ -n "$folder_path" ]]; then
        echo "${OUTPUT_DIR}/${folder_path}"
        return 0
    fi
    
    # 2. Fallback: output-Basis + Unterordner
    output_path=$(config_get_value_ini "$module_name" "folders" "output")
    
    if [[ -n "$output_path" ]]; then
        echo "${OUTPUT_DIR}/${output_path}/${folder_type}"
        return 0
    fi
    
    # 3. Letzter Fallback: Globaler Output-Ordner
    echo "$(folders_get_output_dir)/${folder_type}"
}

# ============================================================================
# ENDE DER FILE MANAGEMENT LIBRARY
# ============================================================================
