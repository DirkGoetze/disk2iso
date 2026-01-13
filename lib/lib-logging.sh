#!/bin/bash
################################################################################
# disk2iso v1.2.0 - Logging Library
# Filepath: lib/lib-logging.sh
#
# Beschreibung:
#   Zentrale Logging-Funktionen für alle Module:
#   - Timestamped Logging mit optionaler Datei-Ausgabe
#   - Modulares Sprachsystem
#   - Wird von allen Modulen verwendet
#
# Version: 1.2.0
# Datum: 06.01.2026
################################################################################

# ============================================================================
# PATH CONSTANTS
# ============================================================================

readonly LOG_DIR=".log"

# ============================================================================
# PATH GETTER
# ============================================================================

# Funktion: Ermittle Pfad für Log-Dateien
# Rückgabe: Vollständiger Pfad zu log/
get_path_log() {
    echo "${OUTPUT_DIR}/${LOG_DIR}"
}

# ============================================================================
# LANGUAGE SYSTEM
# ============================================================================

# ============================================================================
# LANGUAGE FALLBACK MESSAGES (Hardcoded - loaded before language files)
# ============================================================================

# Diese Meldungen müssen hardcoded sein, da sie vor dem Laden der Sprachdateien
# verwendet werden können und das Sprachsystem selbst betreffen
readonly MSG_LANG_FILE_LOADED="Sprachdatei geladen:"
readonly MSG_LANG_FALLBACK_LOADED="Fallback: Sprachdatei geladen:"
readonly MSG_WARNING_NO_LANG_FILE="WARNUNG: Keine Sprachdatei gefunden für:"

# ============================================================================
# LANGUAGE FILE LOADING
# ============================================================================

# Funktion: Lade modul-spezifische Sprachdatei
# Parameter: $1 = Modul-Name (z.B. "common", "cd", "dvd", "bluray")
# Lädt: lang/lib-[modul].[LANGUAGE]
# Beispiel: load_module_language "cd" lädt lang/lib-cd.de
load_module_language() {
    local module_name="$1"
    
    # Für Hauptskript (disk2iso) ohne lib- Präfix suchen
    # Für Module mit lib- Präfix suchen
    local lang_file
    if [[ -f "${SCRIPT_DIR}/lang/${module_name}.${LANGUAGE}" ]]; then
        lang_file="${SCRIPT_DIR}/lang/${module_name}.${LANGUAGE}"
    else
        lang_file="${SCRIPT_DIR}/lang/lib-${module_name}.${LANGUAGE}"
    fi
    
    if [[ -f "$lang_file" ]]; then
        source "$lang_file"
        # Optional: Log-Nachricht nur wenn log_message bereits definiert
        if declare -f log_message >/dev/null 2>&1; then
            log_message "$MSG_LANG_FILE_LOADED $(basename "$lang_file")"
        fi
    else
        # Fallback auf Englisch
        local fallback_file
        if [[ -f "${SCRIPT_DIR}/lang/${module_name}.en" ]]; then
            fallback_file="${SCRIPT_DIR}/lang/${module_name}.en"
        else
            fallback_file="${SCRIPT_DIR}/lang/lib-${module_name}.en"
        fi
        
        if [[ -f "$fallback_file" ]]; then
            source "$fallback_file"
            if declare -f log_message >/dev/null 2>&1; then
                log_message "$MSG_LANG_FALLBACK_LOADED $(basename "$fallback_file")"
            fi
        else
            # Keine Sprachdatei gefunden - Module funktionieren trotzdem
            if declare -f log_message >/dev/null 2>&1; then
                log_message "$MSG_WARNING_NO_LANG_FILE ${module_name}.${LANGUAGE}"
            fi
        fi
    fi
}

# Lade Debug-Messages (immer Englisch - Entwicklersprache)
# Diese werden nur benötigt wenn DEBUG=1 gesetzt ist
if [[ "${DEBUG:-0}" == "1" ]] || [[ "${VERBOSE:-0}" == "1" ]]; then
    DEBUG_LANG_FILE="${SCRIPT_DIR}/../lang/debugmsg.en"
    if [[ -f "$DEBUG_LANG_FILE" ]]; then
        source "$DEBUG_LANG_FILE"
    fi
fi

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

# Funktion für Logging (verwendet aktuelles log_filename)
# Parameter: $1 = Nachricht zum Loggen
# Ausgabe: Konsole + Optional log_filename (falls gesetzt)
log_message() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$message"
    if [[ -n "$log_filename" ]]; then
        echo "$message" >> "$log_filename"
    fi
}

# ============================================================================
# ENDE DER LOGGING LIBRARY
# ============================================================================
