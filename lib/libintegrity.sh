#!/bin/bash
# =============================================================================
# Module Integrity & Dependency Management
# =============================================================================
# Filepath: lib/libintegrity.sh
#
# Beschreibung:
#   Zentrale Verwaltung von Modul-Abhängigkeiten und System-Integrität
#   - check_module_dependencies() - Manifest-basierte Dependency-Prüfung
#   - Validierung von Modul-Dateien, Ordnern und externen Tools
#   - Basis für zukünftige Features (Auto-Update, Repair, Diagnostics)
#   - Verwendet INI-Manifeste (conf/lib<module>.ini)
#
# -----------------------------------------------------------------------------
# Dependencies: libconfig (INI-Parsing), liblogging, libfolders
# -----------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.3.0
# Last Change: 2026-02-07
# =============================================================================

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

# ===========================================================================
# integrity_check_dependencies
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
integrity_check_dependencies() {
    # Lade Modul-Sprachdatei
    load_module_language "integrity"
    
    # Integrity-Modul benötigt:
    # - libsettings.sh (settings_get_value_ini, settings_get_array_ini)
    # - liblogging.sh (log_*, load_module_language)
    # - libfolders.sh (folders_ensure_subfolder)
    # - libfiles.sh (files_get_*_path)
    
    # Prüfe ob benötigte Funktionen verfügbar sind
    if ! declare -f settings_get_value_ini >/dev/null 2>&1; then
        echo "$MSG_ERROR_GET_INI_VALUE_MISSING" >&2
        return 1
    fi
    
    if ! declare -f log_info >/dev/null 2>&1; then
        echo "$MSG_ERROR_LOG_INFO_MISSING" >&2
        return 1
    fi
    
    return 0
}

# ===========================================================================
# MODULE DEPENDENCY CHECKING (MANIFEST-BASED)
# ===========================================================================

# ===========================================================================
# check_module_dependencies
# ---------------------------------------------------------------------------
# Funktion.: Standard Dependency-Check aus INI-Manifest
# Parameter: $1 = module_name (z.B. "audio", "dvd", "metadata")
# Rückgabe.: 0 = Alle kritischen Abhängigkeiten erfüllt
#            1 = Kritische Abhängigkeiten fehlen (Modul nicht nutzbar)
# Nutzt....: INI-Format: conf/lib<module>.ini
# Prüft....: - Modul-Dateien (lib, lang, conf, www)
#            - Modul-Ordner (output, cache, logs, etc.)
#            - Externe Tools (critical + optional)
# TODO.....: Interne Modul-Abhängigkeiten prüfen (z.B. [moduledependencies] required=liblogging,libconfig)
#            Implementierung: declare -f Prüfung für benötigte Funktionen aus anderen lib*.sh Modulen
# ===========================================================================
check_module_dependencies() {
    local module_name="$1"
    local conf_dir
    conf_dir=$(folders_get_conf_dir) || conf_dir="${INSTALL_DIR}/conf"
    local manifest_file="${conf_dir}/lib${module_name}.ini"
    
    # Debug: Start der Abhängigkeitsprüfung
    log_debug "$MSG_DEBUG_CHECK_START '${module_name}'"
    
    # Sprachdatei laden (vor Manifest-Check!)
    log_message "Prüfe Abhängigkeiten für Modul: ${module_name}"
    load_module_language "$module_name"
    
    # Prüfe ob Manifest existiert
    if [[ ! -f "$manifest_file" ]]; then
        # Kein Manifest - Modul entscheidet selbst (kein Fehler!)
        log_info "${module_name}: $MSG_INFO_NO_MANIFEST"
        return 0
    fi

    # ------------------------------------------------------------------------
    # Lade DB-Datei falls definiert 
    # ------------------------------------------------------------------------
    local db_file
    db_file=$(config_get_value_ini "${module_name}" "modulefiles" "db")

    if [[ -n "$db_file" ]]; then
        local db_path="${INSTALL_DIR}/${db_file}"
        
        if [[ -f "$db_path" ]]; then
            # shellcheck source=/dev/null
            source "$db_path" || {
                log_error "${module_name}: $MSG_ERROR_DB_LOAD_FAILED: ${db_file}"
                return 1
            }
            log_debug "${module_name}: $MSG_DEBUG_DB_LOADED: ${db_file}"
        else
            log_error "${module_name}: $MSG_ERROR_DB_NOT_FOUND: ${db_path}"
            return 1
        fi
    fi

    # ------------------------------------------------------------------------
    # Alle anderen Modul Dateien selbst auf Existens prüfen
    # ------------------------------------------------------------------------
    local module_files_missing=()          # Array der fehlenden Modul-Dateien
    # Liste aller möglichen Datei-Typen (entspricht INI-Keys)
    local file_types=("db" "lib" "lang" "docu" "router" "html" "css" "js")
    
    for file_type in "${file_types[@]}"; do
        # Lese Dateiname aus Manifest
        local filename
        filename=$(settings_get_value_ini "${module_name}" "modulefiles" "$file_type")
        
        # Nur prüfen wenn Eintrag existiert
        if [[ -n "$filename" ]]; then
            # Ermittle vollständigen Pfad (via libfiles.sh)
            local file_path
            case "$file_type" in
                lib)
                    file_path=$(files_get_lib_path "$filename")
                    ;;
                lang)
                    file_path=$(files_get_lang_path "$filename")
                    ;;
                conf)
                    file_path=$(files_get_conf_path "$filename")
                    ;;
                docu)
                    file_path=$(files_get_doc_path "$filename")
                    ;;
                html)
                    file_path=$(files_get_html_path "$filename")
                    ;;
                css)
                    file_path=$(files_get_css_path "$filename")
                    ;;
                js)
                    file_path=$(files_get_js_path "$filename")
                    ;;
                router)
                    file_path=$(files_get_router_path "$filename")
                    ;;
                *)
                    # Unbekannter file_type → Warnung
                    log_warning "${module_name}: $MSG_WARNING_UNKNOWN_FILE_TYPE: ${file_type}"
                    continue
                    ;;
            esac
            
            # Prüfe Existenz (mit Wildcard-Support für Sprachdateien)
            if [[ "$file_type" == "lang" ]] && [[ "$file_path" == *\** ]]; then
                # Sprachdateien: Prüfe ob MINDESTENS eine existiert
                if ! compgen -G "$file_path" > /dev/null 2>&1; then
                    module_files_missing+=("${file_type}: ${filename} (keine Sprachdateien gefunden)")
                fi
            else
                # Normale Dateien: Exakte Existenzprüfung
                if [[ ! -f "$file_path" ]]; then
                    module_files_missing+=("${file_type}: ${filename} → ${file_path}")
                fi
            fi
        fi
    done
    
    # Auswertung der Modul-Dateien
    if [[ ${#module_files_missing[@]} -gt 0 ]]; then
        # Fehlende Modul-Dateien → Warnung (NICHT kritisch, Modul kann trotzdem funktionieren)
        log_warning "${module_name}: $MSG_WARNING_MODULE_FILES_MISSING"
        for missing_file in "${module_files_missing[@]}"; do
            log_warning "  - ${missing_file}"
        done
        log_info "${module_name}: $MSG_INFO_CHECK_INSTALLATION"
    fi

    # ------------------------------------------------------------------------
    # Modul-Ordner prüfen/erstellen 
    # ------------------------------------------------------------------------
    local folder_creation_failed=()  # Array der fehlgeschlagenen Erstellungen
    local folder_creation_success=() # Array der erfolgreichen Erstellungen
    
    # Prüfe ob folders_ensure_subfolder() verfügbar ist
    if ! declare -f folders_ensure_subfolder >/dev/null 2>&1; then
        log_warning "${module_name}: $MSG_WARNING_FOLDERS_ENSURE_SUBFOLDER_MISSING"
    else
        # Liste aller möglichen Ordner-Typen (entspricht INI-Keys in [folders])
        local folder_types=("output" "temp" "logs" "cache" "thumbs" "covers")
        
        for folder_type in "${folder_types[@]}"; do
            # Lese Ordner-Namen aus Manifest
            local folder_name
            folder_name=$(settings_get_value_ini "${module_name}" "folders" "$folder_type")
            
            # Nur prüfen wenn Eintrag existiert
            if [[ -n "$folder_name" ]]; then
                # Versuche Ordner zu erstellen/prüfen (via folders_ensure_subfolder)
                local folder_path
                
                if folder_path=$(folders_ensure_subfolder "$folder_name" 2>&1); then
                    # Erfolgreich erstellt/geprüft
                    folder_creation_success+=("${folder_type}: ${folder_path}")
                    log_info "${module_name}: $MSG_INFO_FOLDER_OK: ${folder_type} → ${folder_path}"
                else
                    # Erstellung fehlgeschlagen → KRITISCH!
                    folder_creation_failed+=("${folder_type}: ${folder_name} (Fehler: ${folder_path})")
                    log_error "${module_name}: $MSG_ERROR_FOLDER_CREATION_FAILED: ${folder_type} → ${folder_name}"
                fi
            fi
        done
    fi
    
    # Auswertung: Ordner-Erstellung fehlgeschlagen?
    if [[ ${#folder_creation_failed[@]} -gt 0 ]]; then
        # Kritische Ordner konnten nicht erstellt werden → Modul nicht nutzbar
        log_error "${module_name}: $MSG_ERROR_CRITICAL_FOLDERS_MISSING"
        for failed_folder in "${folder_creation_failed[@]}"; do
            log_error "  - ${failed_folder}"
        done
        log_info "${module_name}: $MSG_INFO_CHECK_WRITE_PERMISSIONS: ${OUTPUT_DIR}"
        return 1
    fi
     
    # ------------------------------------------------------------------------
    # Kritische Abhängigkeiten prüfen
    # ------------------------------------------------------------------------
    local missing=()                      # Array der fehlende kritische Tools
    local external_deps                 # Kritische externe Tools aus Manifest
    
    # Lese externe Tools aus Manifest (via config_get_array_ini)
    external_deps=$(config_get_array_ini "${module_name}" "dependencies" "external")

    # Prüfung der kritischen Tools, falls definiert
    if [[ -n "$external_deps" ]]; then

        # Elementweise prüfen
        while IFS= read -r tool; do
            [[ -z "$tool" ]] && continue  # Überspringe leere Zeilen

            if ! command -v "$tool" >/dev/null 2>&1; then
                missing+=("$tool") # Sammle fehlende Tools
            fi
        done <<< "$external_deps"
    fi
    
    # Auswertung der Kritische Tools 
    if [[ ${#missing[@]} -gt 0 ]]; then
        # Es fehlen Tools → Modul nicht nutzbar
        log_error "${module_name}: $MSG_ERROR_CRITICAL_TOOLS_MISSING: ${missing[*]}"
        log_info "${module_name}: $MSG_INFO_INSTALL_TOOLS ${missing[*]}"
        return 1
    fi
    
    # ------------------------------------------------------------------------
    # Optionale Abhängigkeiten prüfen
    # ------------------------------------------------------------------------
    local optional_missing=()             # Array der fehlende optionale Tools
    local optional_deps                         # Optionale Tools aus Manifest

    # Lese optionale Tools aus Manifest (via config_get_array_ini)
    optional_deps=$(config_get_array_ini "${module_name}" "dependencies" "optional")
    
    # Prüfung der optionalen Tools, falls definiert
    if [[ -n "$optional_deps" ]]; then

        # Elementweise prüfen
        while IFS= read -r tool; do
            [[ -z "$tool" ]] && continue           # Überspringe leere Zeilen
            
            if ! command -v "$tool" >/dev/null 2>&1; then
                optional_missing+=("$tool") # Sammle fehlende optionale Tools
            fi
        done <<< "$optional_deps"
    fi
    
    # Auswertung der optionale Tools 
    if [[ ${#optional_missing[@]} -gt 0 ]]; then
        # Es fehlen optionale Tools → Warnung ausgeben
        log_warning "${module_name}: $MSG_WARNING_OPTIONAL_TOOLS_MISSING"
        log_info "${module_name}: $MSG_INFO_RECOMMENDED_INSTALL ${optional_missing[*]}"
    fi
        
    # ------------------------------------------------------------------------
    # Abhängigkeiten geprüft - Alles vorhanden
    # ------------------------------------------------------------------------
    # Erfolgreiche Ordner-Erstellung loggen (Info-Level)
    if [[ ${#folder_creation_success[@]} -gt 0 ]]; then
        log_info "${module_name}: $MSG_INFO_FOLDERS_AVAILABLE (${#folder_creation_success[@]} $MSG_INFO_FOLDERS_CHECKED)"
    fi
    
    # Debug: Erfolgreiche Prüfung
    log_debug "$MSG_DEBUG_CHECK_COMPLETE '${module_name}' ($MSG_DEBUG_ALL_DEPS_MET)"
    
    log_info "${module_name}: $MSG_INFO_ALL_DEPENDENCIES_OK"
    return 0
}
