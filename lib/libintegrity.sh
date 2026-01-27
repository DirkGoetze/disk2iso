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
# Version: 1.2.1
# Last Change: 2026-01-26 20:30
# =============================================================================

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

# ===========================================================================
# check_dependencies_integrity
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
check_dependencies_integrity() {
    # Integrity-Modul benötigt:
    # - libconfig.sh (get_ini_value, get_ini_array)
    # - liblogging.sh (log_*, load_module_language)
    # - libfolders.sh (ensure_subfolder, get_module_file_path)
    
    # Prüfe ob benötigte Funktionen verfügbar sind
    if ! declare -f get_ini_value >/dev/null 2>&1; then
        echo "FEHLER: get_ini_value() nicht verfügbar (libconfig.sh nicht geladen?)" >&2
        return 1
    fi
    
    if ! declare -f log_info >/dev/null 2>&1; then
        echo "FEHLER: log_info() nicht verfügbar (liblogging.sh nicht geladen?)" >&2
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
# ===========================================================================
check_module_dependencies() {
    local module_name="$1"
    local manifest_file="${INSTALL_DIR}/conf/lib${module_name}.ini"
    
    # Debug: Start der Abhängigkeitsprüfung
    log_debug "check_module_dependencies: Start für Modul '${module_name}'"
    
    # Sprachdatei laden (vor Manifest-Check!)
    log_message "Prüfe Abhängigkeiten für Modul: ${module_name}"
    load_module_language "$module_name"
    
    # Prüfe ob Manifest existiert
    if [[ ! -f "$manifest_file" ]]; then
        # Kein Manifest - Modul entscheidet selbst (kein Fehler!)
        log_info "${module_name}: Kein Manifest gefunden, überspringe Abhängigkeitsprüfung"
        return 0
    fi
        
    # ------------------------------------------------------------------------
    # Modul Dateien selbst auf Existens prüfen
    # ------------------------------------------------------------------------
    local module_files_missing=()          # Array der fehlenden Modul-Dateien
    # Liste aller möglichen Datei-Typen (entspricht INI-Keys)
    local file_types=("lib" "lang" "docu" "router" "html" "css" "js")
    
    for file_type in "${file_types[@]}"; do
        # Lese Dateiname aus Manifest
        local filename
        filename=$(get_ini_value "$manifest_file" "modulefiles" "$file_type")
        
        # Nur prüfen wenn Eintrag existiert
        if [[ -n "$filename" ]]; then
            # Ermittle vollständigen Pfad (via libfolders.sh)
            local file_path
            file_path=$(get_module_file_path "$file_type" "$filename")
            
            if [[ -z "$file_path" ]]; then
                # Unbekannter file_type → Warnung
                log_warning "${module_name}: Unbekannter Datei-Typ in Manifest: ${file_type}"
                continue
            fi
            
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
        log_warning "${module_name}: Modul-Dateien fehlen (Modul unvollständig installiert oder beschädigt?):"
        for missing_file in "${module_files_missing[@]}"; do
            log_warning "  - ${missing_file}"
        done
        log_info "${module_name}: Hinweis: Prüfen Sie die Modul-Installation oder aktualisieren Sie das Manifest"
    fi

    # ------------------------------------------------------------------------
    # Modul-Ordner prüfen/erstellen 
    # ------------------------------------------------------------------------
    local folder_creation_failed=()  # Array der fehlgeschlagenen Erstellungen
    local folder_creation_success=() # Array der erfolgreichen Erstellungen
    
    # Prüfe ob ensure_subfolder() verfügbar ist
    if ! declare -f ensure_subfolder >/dev/null 2>&1; then
        log_warning "${module_name}: ensure_subfolder() nicht verfügbar - überspringe Ordner-Prüfung"
    else
        # Liste aller möglichen Ordner-Typen (entspricht INI-Keys in [folders])
        local folder_types=("output" "temp" "logs" "cache" "thumbs" "covers")
        
        for folder_type in "${folder_types[@]}"; do
            # Lese Ordner-Namen aus Manifest
            local folder_name
            folder_name=$(get_ini_value "$manifest_file" "folders" "$folder_type")
            
            # Nur prüfen wenn Eintrag existiert
            if [[ -n "$folder_name" ]]; then
                # Versuche Ordner zu erstellen/prüfen (via ensure_subfolder)
                local folder_path
                
                if folder_path=$(ensure_subfolder "$folder_name" 2>&1); then
                    # Erfolgreich erstellt/geprüft
                    folder_creation_success+=("${folder_type}: ${folder_path}")
                    log_info "${module_name}: Ordner OK: ${folder_type} → ${folder_path}"
                else
                    # Erstellung fehlgeschlagen → KRITISCH!
                    folder_creation_failed+=("${folder_type}: ${folder_name} (Fehler: ${folder_path})")
                    log_error "${module_name}: Ordner-Erstellung fehlgeschlagen: ${folder_type} → ${folder_name}"
                fi
            fi
        done
    fi
    
    # Auswertung: Ordner-Erstellung fehlgeschlagen?
    if [[ ${#folder_creation_failed[@]} -gt 0 ]]; then
        # Kritische Ordner konnten nicht erstellt werden → Modul nicht nutzbar
        log_error "${module_name}: Kritische Ordner fehlen und konnten nicht erstellt werden:"
        for failed_folder in "${folder_creation_failed[@]}"; do
            log_error "  - ${failed_folder}"
        done
        log_info "${module_name}: Prüfen Sie Schreibrechte in OUTPUT_DIR: ${OUTPUT_DIR}"
        return 1
    fi
     
    # ------------------------------------------------------------------------
    # Kritische Abhängigkeiten prüfen
    # ------------------------------------------------------------------------
    local missing=()                      # Array der fehlende kritische Tools
    local external_deps                 # Kritische externe Tools aus Manifest
    
    # Lese externe Tools aus Manifest
    external_deps=$(get_ini_array "$manifest_file" "dependencies" "external")

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
        log_error "${module_name}: Kritische Tools fehlen: ${missing[*]}"
        log_info "${module_name}: Installation: sudo apt install ${missing[*]}"
        return 1
    fi
    
    # ------------------------------------------------------------------------
    # Optionale Abhängigkeiten prüfen
    # ------------------------------------------------------------------------
    local optional_missing=()             # Array der fehlende optionale Tools
    local optional_deps                         # Optionale Tools aus Manifest

    # Lese optionale Tools aus Manifest
    optional_deps=$(get_ini_array "$manifest_file" "dependencies" "optional")
    
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
        log_warning "${module_name}: Optionale Tools fehlen (reduzierte Funktionalität)"
        log_info "${module_name}: Empfohlen: sudo apt install ${optional_missing[*]}"
    fi
        
    # ------------------------------------------------------------------------
    # Abhängigkeiten geprüft - Alles vorhanden
    # ------------------------------------------------------------------------
    # Erfolgreiche Ordner-Erstellung loggen (Info-Level)
    if [[ ${#folder_creation_success[@]} -gt 0 ]]; then
        log_info "${module_name}: Modul-Ordner verfügbar (${#folder_creation_success[@]} Ordner geprüft/erstellt)"
    fi
    
    # Debug: Erfolgreiche Prüfung
    log_debug "check_module_dependencies: Abgeschlossen für Modul '${module_name}' (alle Abhängigkeiten erfüllt)"
    
    log_info "${module_name}: Alle Modul-Abhängigkeiten erfüllt"
    return 0
}
