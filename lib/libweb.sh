#!/bin/bash
# =============================================================================
# Web Interface Helper Library
# =============================================================================
# Filepath: lib/libweb.sh
#
# Beschreibung:
#   Bash-Wrapper für Web-Interface Operationen.
#   Python-Layer ruft diese Funktionen auf - Geschäftslogik bleibt in Bash.
#
# Dependencies: libsettings.sh, libcommon.sh
# -----------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.3.0
# Last Change: 2026-02-08
# =============================================================================

# ===========================================================================
# web_set_language
# ---------------------------------------------------------------------------
# Funktion.: CLI-Wrapper für Sprachwechsel (wird von Python aufgerufen)
# Parameter: $1 = language (de, en, fr, es)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Ausgabe..: JSON auf stdout: {"status": "ok", "language": "de"}
# Beispiel.: /opt/disk2iso/lib/libweb.sh set_language en
# ===========================================================================
web_set_language() {
    local language="$1"
    
    # Lade libsettings falls nicht geladen
    if ! type -t settings_set_language &>/dev/null; then
        source "${INSTALL_DIR:-/opt/disk2iso}/lib/libsettings.sh" || {
            echo '{"status": "error", "message": "libsettings.sh not available"}'
            return 1
        }
    fi
    
    # Setze Sprache
    if settings_set_language "$language"; then
        echo "{\"status\": \"ok\", \"language\": \"${language}\"}"
        return 0
    else
        echo "{\"status\": \"error\", \"message\": \"Invalid language or write failed\"}"
        return 1
    fi
}

# ===========================================================================
# web_get_language
# ---------------------------------------------------------------------------
# Funktion.: CLI-Wrapper für Sprachabfrage (wird von Python aufgerufen)
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# Ausgabe..: JSON auf stdout: {"status": "ok", "language": "de"}
# Beispiel.: /opt/disk2iso/lib/libweb.sh get_language
# ===========================================================================
web_get_language() {
    # Lade libsettings falls nicht geladen
    if ! type -t settings_get_language &>/dev/null; then
        source "${INSTALL_DIR:-/opt/disk2iso}/lib/libsettings.sh" || {
            echo '{"status": "error", "message": "libsettings.sh not available"}'
            return 1
        }
    fi
    
    # Lese Sprache
    local language
    language=$(settings_get_language)
    
    if [[ -n "$language" ]]; then
        echo "{\"status\": \"ok\", \"language\": \"${language}\"}"
        return 0
    else
        echo "{\"status\": \"error\", \"message\": \"Could not read language\"}"
        return 1
    fi
}

# ===========================================================================
# MAIN - CLI Entry Point
# ===========================================================================
# Ermöglicht direkten Aufruf: ./libweb.sh <command> [args]
# ===========================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Skript wurde direkt aufgerufen (nicht gesourced)
    
    # Setze INSTALL_DIR wenn nicht gesetzt
    if [[ -z "$INSTALL_DIR" ]]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        export INSTALL_DIR="$(dirname "$SCRIPT_DIR")"
    fi
    
    # Lade libcommon für log_* Funktionen (falls verfügbar)
    if [[ -f "${INSTALL_DIR}/lib/libcommon.sh" ]]; then
        source "${INSTALL_DIR}/lib/libcommon.sh" 2>/dev/null || true
    fi
    
    # Parse Command
    command="$1"
    shift
    
    case "$command" in
        set_language)
            web_set_language "$@"
            ;;
        get_language)
            web_get_language "$@"
            ;;
        *)
            echo "{\"status\": \"error\", \"message\": \"Unknown command: $command\"}"
            echo "Usage: $0 {set_language|get_language} [args]" >&2
            exit 1
            ;;
    esac
fi
