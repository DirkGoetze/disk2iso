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
            log_info "$MSG_LANG_FILE_LOADED $(basename "$lang_file")" >&2
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
                log_info "$MSG_LANG_FALLBACK_LOADED $(basename "$fallback_file")" >&2
            fi
        else
            # Keine Sprachdatei gefunden - Module funktionieren trotzdem
            if declare -f log_message >/dev/null 2>&1; then
                log_warning "$MSG_WARNING_NO_LANG_FILE ${module_name}.${LANGUAGE}" >&2
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

# Globale Variable für aktuelles Kopiervorgang-Log
copy_log_filename=""

# Funktion: Initialisiere Kopiervorgang-spezifisches Log
# Parameter: $1 = Disc-ID/Label (z.B. "audio_cd_cb0cd60e" oder "ronan_keating_destination")
#            $2 = Disc-Typ (z.B. "audio-cd", "dvd", "bluray", "data")
# Setzt: copy_log_filename
# Erstellt: Log-Datei im .log/ Verzeichnis
init_copy_log() {
    local disc_id="$1"
    local disc_type="$2"
    
    # Erstelle Log-Verzeichnis falls nicht vorhanden
    local log_dir="${OUTPUT_DIR}/${LOG_DIR}"
    mkdir -p "$log_dir"
    
    # Setze Kopiervorgang-Log-Dateiname
    copy_log_filename="${log_dir}/${disc_id}.log"
    
    # Erstelle/Leere Log-Datei
    > "$copy_log_filename"
    
    # Schreibe Header
    echo "========================================" >> "$copy_log_filename"
    echo "Kopiervorgang gestartet: $(date '+%Y-%m-%d %H:%M:%S')" >> "$copy_log_filename"
    echo "Medium: $disc_id" >> "$copy_log_filename"
    echo "Typ: $disc_type" >> "$copy_log_filename"
    echo "========================================" >> "$copy_log_filename"
}

# Funktion: Schreibe ins Kopiervorgang-Log
# Parameter: $1 = Nachricht
# Ausgabe: Konsole + copy_log_filename (falls gesetzt)
log_copying() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$message"
    if [[ -n "$copy_log_filename" ]]; then
        echo "$message" >> "$copy_log_filename"
    fi
}

# Funktion: Beende Kopiervorgang-Log
# Schreibt Footer und setzt copy_log_filename zurück
finish_copy_log() {
    if [[ -n "$copy_log_filename" ]]; then
        echo "========================================" >> "$copy_log_filename"
        echo "Kopiervorgang beendet: $(date '+%Y-%m-%d %H:%M:%S')" >> "$copy_log_filename"
        echo "========================================" >> "$copy_log_filename"
        copy_log_filename=""
    fi
}

# Funktion für allgemeines Logging (Service/System)
# Parameter: $1 = Nachricht zum Loggen
# Ausgabe: Konsole (kein File-Logging für Service-Messages)
log_message() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$message"
}

# Funktion für Info-Logging (alias für log_message)
# Parameter: $1 = Info-Nachricht
log_info() {
    log_info "ℹ️  $1"
}

# Funktion für Warning-Logging
# Parameter: $1 = Warning-Nachricht
# Ausgabe: Konsole + stderr
log_warning() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - ⚠️  WARNING: $1"
    echo "$message" >&2
}

# Funktion für Error-Logging
# Parameter: $1 = Error-Nachricht
# Ausgabe: Konsole + stderr
log_error() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - ❌ ERROR: $1"
    echo "$message" >&2
}

# Funktion für Debug-Logging
# Parameter: $1 = Debug-Nachricht
# Ausgabe: Nur wenn DEBUG=1 gesetzt ist
log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        local message="$(date '+%Y-%m-%d %H:%M:%S') - 🐛 DEBUG: $1"
        echo "$message" >&2
    fi
}

# ============================================================================
# ENDE DER LOGGING LIBRARY
# ============================================================================
