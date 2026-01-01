#!/bin/bash
################################################################################
# disk2iso v1.0.0 - Logging Library
# Filepath: disk2iso-lib/lib-logging.sh
#
# Beschreibung:
#   Zentrale Logging-Funktionen für alle Module:
#   - Timestamped Logging mit optionaler Datei-Ausgabe
#   - Modulares Sprachsystem
#   - Wird von allen Modulen verwendet
#
# Version: 1.0.0
# Datum: 01.01.2026
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

# Funktion: Lade modul-spezifische Sprachdatei
# Parameter: $1 = Modul-Name (z.B. "common", "cd", "dvd", "bluray")
# Lädt: lang/lib-[modul].[LANGUAGE]
# Beispiel: load_module_language "cd" lädt lang/lib-cd.de
load_module_language() {
    local module_name="$1"
    local lang_file="${SCRIPT_DIR}/disk2iso-lib/lang/lib-${module_name}.${LANGUAGE}"
    
    if [[ -f "$lang_file" ]]; then
        source "$lang_file"
        # Optional: Log-Nachricht nur wenn log_message bereits definiert
        if declare -f log_message >/dev/null 2>&1; then
            log_message "Sprachdatei geladen: lib-${module_name}.${LANGUAGE}"
        fi
    else
        # Fallback auf Englisch oder keine Meldung
        local fallback_file="${SCRIPT_DIR}/disk2iso-lib/lang/lib-${module_name}.en"
        if [[ -f "$fallback_file" ]]; then
            source "$fallback_file"
            if declare -f log_message >/dev/null 2>&1; then
                log_message "Fallback: Sprachdatei geladen: lib-${module_name}.en"
            fi
        else
            # Keine Sprachdatei gefunden - Module funktionieren trotzdem
            if declare -f log_message >/dev/null 2>&1; then
                log_message "WARNUNG: Keine Sprachdatei gefunden für: lib-${module_name}.${LANGUAGE}"
            fi
        fi
    fi
}

# Lade Debug-Messages (immer Englisch - Entwicklersprache)
# Diese werden nur benötigt wenn DEBUG=1 gesetzt ist
if [[ "${DEBUG:-0}" == "1" ]] || [[ "${VERBOSE:-0}" == "1" ]]; then
    DEBUG_LANG_FILE="${SCRIPT_DIR}/disk2iso-lib/lang/debugmsg.en"
    if [[ -f "$DEBUG_LANG_FILE" ]]; then
        source "$DEBUG_LANG_FILE"
    fi
fi

# ============================================================================
# LOGGING FUNCTIONS
# Quelle: functions.sh
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
