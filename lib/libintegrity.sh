#!/bin/bash
# =============================================================================
# Module Integrity & Dependency Management
# =============================================================================
# Filepath: lib/libintegrity.sh
#
# Beschreibung:
#   Zentrale Verwaltung von Modul-Abhängigkeiten und System-Integrität
#   - integrity_check_module_dependencies() - Manifest-basierte Dependency-Prüfung
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
    logging_load_language_file "integrity"
    
    # Integrity-Modul benötigt:
    # - libsettings.sh (settings_get_value_ini, settings_get_array_ini)
    # - liblogging.sh (log_*, logging_load_language_file)
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
# integrity_check_module_dependencies
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
integrity_check_module_dependencies() {
    local module_name="$1"
    local conf_dir=$(folders_get_conf_dir) || conf_dir="${INSTALL_DIR}/conf"
    local manifest_file="${conf_dir}/lib${module_name}.ini"
    
    # Debug: Start der Abhängigkeitsprüfung
    log_debug "$MSG_DEBUG_CHECK_START '${module_name}'"
    
    # Sprachdatei laden (vor Manifest-Check!)
    log_message "Prüfe Abhängigkeiten für Modul: ${module_name}"
    logging_load_language_file "$module_name"
    
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
    db_file=$(settings_get_value_ini "${module_name}" "modulefiles" "db")

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
    
    # Lese externe Tools aus Manifest (via settings_get_array_ini)
    external_deps=$(settings_get_array_ini "${module_name}" "dependencies" "external")

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

    # Lese optionale Tools aus Manifest (via settings_get_array_ini)
    optional_deps=$(settings_get_array_ini "${module_name}" "dependencies" "optional")
    
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

# ===========================================================================
# _integrity_collect_modules
# ---------------------------------------------------------------------------
# Funktion.: Sammelt alle ladbaren Module aus den INI-Manifesten
# Parameter: $1 = result_array (Referenz auf das Ergebnis-Array)
# Rückgabe.: 0 = Module gefunden (Array wurde befüllt)
# .........  1 = Keine Module gefunden (Array bleibt leer)
# Extras...: Hilfsfunktion für integrity_load_modules()
# .........  Überspringt Core-Module und Module ohne .sh-Datei
# ===========================================================================
_integrity_collect_modules() {
    local -n result_array=$1  # Array per Reference 
    local conf_dir=$(folders_get_conf_dir)
    
    #-- Log: Start der Modulsammlung ----------------------------------------
    log_info "$MSG_SCANNING_MODULES: ${conf_dir}"

    #-- Alle gefundenen *.ini Dateien durchgehen (lib*.ini) -----------------
    for ini_file in "${conf_dir}"/lib*.ini; do
        [[ -f "$ini_file" ]] || continue
        
        #-- Extrahiere Modul-Name (lib<modulname>.ini → modulname) ----------
        local module_name=$(basename "$ini_file" .ini | sed 's/^lib//')

        # -------------------------------------------------------------------
        # Überspringe Core-Module (werden im Deamon explizit geladen) 
        # Sicherheitsfunktion, eigentlich haben diese Core-Module keine ini
        # Dateien, aber falls doch, sollen sie nicht als optionale Module 
        # erkannt werden. 
        # -------------------------------------------------------------------
        case "$module_name" in
            logging|settings|folders|files|integrity)
                log_debug "$MSG_SKIP_CORE_MODULE: ${module_name}"
                continue
                ;;
        esac
        
        #-- Lese notwendige Info's aus INI ----------------------------------
        local module_lib=$(settings_get_value_ini "${module_name}" "modulefiles" "lib")
        local requires=$(settings_get_value_ini "${module_name}" "dependencies" "internal")

        #-- Prüfe ob zur *.ini eine *.sh existiert --------------------------
        if [[ ! -f "$module_lib" ]]; then
            log_warning "$MSG_MODULE_LIB_MISSING: ${module_name} (${module_lib})"
            continue
        fi
                
        #-- Füge zu Ergebnis-Array hinzu (Format: module_name|requires) -----
        result_array[$module_name]="${internal_deps:-}"
        log_debug "$MSG_MODULE_FOUND: ${module_name} (deps: ${internal_deps:-KEINE})"
    done
    
    #-- Rückgabe: Erfolg wenn Module gefunden, sonst Fehler -----------------
    if [[ ${#result_array[@]} -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# ===========================================================================
# integrity_load_modules
# ---------------------------------------------------------------------------
# Funktion.: Auto-Discovery und Laden aller optionalen Module aus INI-Manifesten
# Parameter: keine
# Rückgabe.: 0 = Mindestens ein Modul geladen
#            1 = Keine Module gefunden oder Fehler
# Ablauf...: 1. Scanne conf/ nach lib*.ini Dateien
#            2. Parse [module] Sektion (priority, requires_modules)
#            3. Sortiere nach Priority (niedrig = zuerst)
#            4. Lade Module in korrekter Reihenfolge
#            5. Rufe {module}_check_dependencies() auf
# Extras...: Überspringt Module deren .sh fehlt (z.B. nur Config vorhanden)
#            Loggt fehlende Dependencies als Warnung (nicht kritisch)
# ===========================================================================
integrity_load_modules() {
    #-- Config-Verzeichnis ermitteln (via libfolders.sh) --------------------
    local conf_dir=$(folders_get_conf_dir) 
    
    #-- Erfasse alle Module durch die zugehörige INI-Datei ------------------
    declare -a modules_to_load=() # Assoziatives Array -> einfaches Entfernen
    if ! _integrity_collect_modules modules_to_load; then
        # Keine Module gefunden → Kein Laden nötig, aber auch kein Fehler ---
        log_info "$MSG_NO_OPTIONAL_MODULES"
        return 0
    fi
    # Module gefunden → Laden kann beginnen ---------------------------------
    log_info "Gefundene Module: ${!modules_pending[*]}"
   
    # Initialisiere Tracking-Variablen für den Ladeprozess ------------------
    local iteration=0                                   # aktueller Durchlauf
    local max_iterations=15      # Sicherheitslimit, Endlosschleife vermeiden
    local loaded_count=0                # Anzahl erfolgreich geladener Module
    local failed_count=0                      # Anzahl nicht geladener Module
    declare -A failed_modules=()
    
    #-- Phase 3: Iteratives Laden --------------------------------------------
    while [[ ${#modules_to_load[@]} -gt 0 ]] && [[ $iteration -lt $max_iterations ]]; do
        ((iteration++))
        log_debug "Iteration ${iteration}: ${#modules_to_load[@]} Module ausstehend (${!modules_to_load[*]})"
        
        #-- Array für erfolgreich verarbeitete Module in dieser Iteration ---
        declare -a processed_in_iteration=()
        
        #-- Durchlaufe alle ausstehenden Module -----------------------------
        for module_name in "${!modules_to_load[@]}"; do
            
            #-- Prüfe ob bereits geladen ------------------------------------
            if declare -f "${module_name}_check_dependencies" >/dev/null 2>&1; then
                log_debug "${module_name}: Bereits geladen (überspringe)"
                processed_in_iteration+=("$module_name")
                ((loaded_count++))
                continue
            fi
            
            #-- Lese interne Dependencies aus Array (modules_to_load) -------
            local internal_deps="${modules_to_load[$module_name]}"
            
            #-- Prüfe Dependencies DIREKT via declare -f --------------------
            local dependencies_met=true
            if [[ -n "$internal_deps" ]]; then
                IFS=',' read -ra DEPS <<< "$internal_deps"
                local missing_deps=()
                
                for dep in "${DEPS[@]}"; do
                    dep=$(echo "$dep" | xargs)  # Trim whitespace
                    
                    #-- Ist die check_dependencies Funktion verfügbar -------
                    if ! declare -f "${dep}_check_dependencies" >/dev/null 2>&1; then
                        dependencies_met=false
                        missing_deps+=("$dep")
                    fi
                done
                
                #-- Logge fehlende Dependencies ------------------------------
                if [[ ${#missing_deps[@]} -gt 0 ]]; then
                    log_debug "${module_name}: Warte auf: ${missing_deps[*]}"
                fi
            fi
            
            #-- Dependencies nicht erfüllt → nächste Iteration --------------
            if ! $dependencies_met; then
                continue
            fi
            
            #-- Dependencies erfüllt → Versuche Modul zu laden --------------
            log_info "$MSG_LOADING_MODULE: ${module_name}"
            local module_lib="${INSTALL_DIR}/lib/lib${module_name}.sh"
            
            #-- Schritt 1: source Modul-Library -----------------------------
            if ! source "$module_lib" 2>/dev/null; then
                log_error "${module_name}: $MSG_MODULE_LOAD_FAILED"
                failed_modules[$module_name]="source_failed"
                processed_in_iteration+=("$module_name")
                ((failed_count++))
                continue
            fi
            
            #-- Schritt 2: Prüfe ob check_dependencies Funktion existiert ---
            if ! declare -f "${module_name}_check_dependencies" >/dev/null 2>&1; then
                log_warning "${module_name}: $MSG_MODULE_CHECK_FUNC_MISSING"
                failed_modules[$module_name]="no_check_func"
                processed_in_iteration+=("$module_name")
                ((failed_count++))
                continue
            fi
            
            #-- Schritt 3: Rufe check_dependencies auf ----------------------
            if "${module_name}_check_dependencies"; then
                log_info "${module_name}: $MSG_MODULE_LOADED"
                processed_in_iteration+=("$module_name")
                ((loaded_count++))
            else
                log_warning "${module_name}: $MSG_MODULE_DEPS_NOT_MET"
                failed_modules[$module_name]="deps_not_met"
                processed_in_iteration+=("$module_name")
                ((failed_count++))
            fi
        done
        
        #-- Entferne verarbeitete Module aus modules_to_load ----------------
        for module_name in "${processed_in_iteration[@]}"; do
            unset modules_to_load[$module_name]
        done
        
        #-- Stagnations-Check: Wurden Fortschritte gemacht ------------------
        if [[ ${#processed_in_iteration[@]} -eq 0 ]]; then
            #-- Keine Fortschritte → Zirkuläre Dependencies/fehlende Module 
            log_error "Stagnation erkannt: Keine Module in Iteration ${iteration} verarbeitet"
            break
        fi
        
        log_debug "Iteration ${iteration}: ${#processed_in_iteration[@]} Module verarbeitet"
    done
    
    #-- Phase 4: Fehleranalyse & Diagnose ------------------------------------
    if [[ ${#modules_to_load[@]} -gt 0 ]]; then
        log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_error "KRITISCHER FEHLER: Unauflösbare Modul-Abhängigkeiten!"
        log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_error "Betroffene Module: ${!modules_to_load[*]}"
        log_error ""
        
        # Detaillierte Diagnose für jedes ungeladene Modul
        for module_name in "${!modules_to_load[@]}"; do
            local internal_deps="${modules_to_load[$module_name]}"  # ← Aus Array!
            
            log_error "┌─ Modul: ${module_name}"
            
            if [[ -n "$internal_deps" ]]; then
                log_error "│  Benötigt: ${internal_deps}"
                log_error "│  Dependency-Status:"
                
                IFS=',' read -ra DEPS <<< "$internal_deps"
                for dep in "${DEPS[@]}"; do
                    dep=$(echo "$dep" | xargs)
                    
                    if ! declare -f "${dep}_check_dependencies" >/dev/null 2>&1; then
                        log_error "│    ✗ ${dep} (nicht verfügbar)"
                    else
                        log_error "│    ✓ ${dep} (verfügbar - sollte nicht passieren!)"
                    fi
                done
            else
                log_error "│  Keine Dependencies definiert, aber trotzdem nicht ladbar"
                log_error "│  Mögliche Ursache: Syntaxfehler in lib${module_name}.sh"
            fi
            
            log_error "└─────────────────────────────────────────────────────────────"
        done
        
        log_error ""
        log_error "SERVICE NICHT STARTBAR - Bitte Dependencies auflösen!"
        log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        return 1
    fi
    
    #-- Phase 5: Zusammenfassung ---------------------------------------------
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "$MSG_MODULE_SUMMARY: ${loaded_count} $MSG_LOADED, ${failed_count} $MSG_FAILED"
    log_info "Iterationen benötigt: ${iteration}/${max_iterations}"
    
    if [[ $failed_count -gt 0 ]]; then
        log_warning ""
        log_warning "Fehlgeschlagene Module (Service läuft trotzdem):"
        for module_name in "${!failed_modules[@]}"; do
            local reason="${failed_modules[$module_name]}"
            case "$reason" in
                source_failed)
                    log_warning "  ✗ ${module_name}: Modul konnte nicht geladen werden (Syntaxfehler?)"
                    ;;
                no_check_func)
                    log_warning "  ✗ ${module_name}: check_dependencies() Funktion fehlt"
                    ;;
                deps_not_met)
                    log_warning "  ✗ ${module_name}: Externe Abhängigkeiten nicht erfüllt"
                    ;;
                *)
                    log_warning "  ✗ ${module_name}: ${reason}"
                    ;;
            esac
        done
    fi
    
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    return 0
}