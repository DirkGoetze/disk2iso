#!/bin/bash
#############################################################################
# disk2iso v1.2.0 - API JSON Library
# Filepath: lib/libapi.sh
#
# Beschreibung:
#   API-Schnittstelle für Status-Informationen.
#   Schreibt JSON-Dateien die von Web-UI und anderen Tools gelesen werden.
#   Unabhängig von MQTT - funktioniert IMMER.
#
# Version: 1.2.0
# Datum: 10.01.2026
#
# Funktionen:
#   - api_write_json()        : Schreibe JSON-Datei (low-level)
#   - api_update_status()     : Update Status (idle/copying/waiting/completed/error)
#   - api_update_progress()   : Update Fortschritt (während Kopieren)
#   - api_add_history()       : Füge History-Eintrag hinzu
#############################################################################

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

# Funktion: Prüfe API-Modul Abhängigkeiten
# Rückgabe: 0 = OK (Modul schreibt nur JSON-Dateien)
check_dependencies_api() {
    # API-Modul benötigt keine externen Tools
    # Schreibt nur JSON-Dateien mit Bash-Funktionen
    return 0
}

# API-Verzeichnis
readonly API_DIR="${INSTALL_DIR:-/opt/disk2iso}/api"

# ============================================================================
# LOW-LEVEL HELPER
# ============================================================================

# Funktion: Schreibe JSON in API-Datei (atomic write)
# Parameter: $1 = Dateiname (z.B. "status.json"), $2 = JSON-Content
# Rückgabe: 0 = OK, 1 = Fehler
api_write_json() {
    local filename="$1"
    local json_content="$2"
    
    # Erstelle API-Verzeichnis falls nicht vorhanden
    if [[ ! -d "$API_DIR" ]]; then
        mkdir -p "$API_DIR" 2>/dev/null || return 1
        chmod 755 "$API_DIR" 2>/dev/null || true
    fi
    
    # Schreibe JSON-Datei (atomar mit temp-file)
    local temp_file="${API_DIR}/.${filename}.tmp"
    echo "$json_content" > "$temp_file" 2>/dev/null || return 1
    mv -f "$temp_file" "${API_DIR}/${filename}" 2>/dev/null || return 1
    chmod 644 "${API_DIR}/${filename}" 2>/dev/null || true
    
    return 0
}

# ============================================================================
# STATUS UPDATES
# ============================================================================

# Funktion: Update Status
# Parameter:
#   $1 = Status (idle/waiting/copying/completed/error)
#   $2 = Disc-Label (optional)
#   $3 = Disc-Type (optional, z.B. "dvd-video", "audio-cd", "bluray")
#   $4 = Error-Message (optional, nur bei status=error)
# Schreibt: status.json, attributes.json
api_update_status() {
    local status="$1"
    local label="${2:-}"
    local type="${3:-}"
    local error_msg="${4:-}"
    
    local timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
    
    # Schreibe status.json
    local status_json=$(cat <<EOF
{
  "status": "${status}",
  "timestamp": "${timestamp}"
}
EOF
)
    api_write_json "status.json" "${status_json}"
    
    # Berechne Disc-Größe (falls verfügbar)
    local disc_size_mb=0
    if [[ -n "${disc_volume_size:-}" ]] && [[ -n "${disc_block_size:-}" ]]; then
        disc_size_mb=$(( disc_volume_size * disc_block_size / 1024 / 1024 ))
    fi
    
    # Container-Info
    local container="${CONTAINER_TYPE:-none}"
    if [[ "${IS_CONTAINER:-false}" == "true" ]]; then
        container="${CONTAINER_TYPE:-unknown}"
    fi
    
    # Methode (aus globalem Kontext)
    local method="${COPY_METHOD:-unknown}"
    
    # Schreibe attributes.json
    local attr_json=$(cat <<EOF
{
  "disc_label": "${label}",
  "disc_type": "${type}",
  "disc_size_mb": ${disc_size_mb},
  "progress_percent": 0,
  "progress_mb": 0,
  "total_mb": ${disc_size_mb},
  "total_tracks": 0,
  "eta": "",
  "filename": "${iso_basename:-}",
  "method": "${method}",
  "container_type": "${container}",
  "error_message": ${error_msg:+"\"${error_msg}\""}${error_msg:-null}
}
EOF
)
    api_write_json "attributes.json" "${attr_json}"
    
    # Bei idle/waiting: Reset progress auf 0
    if [[ "$status" == "idle" ]] || [[ "$status" == "waiting" ]]; then
        api_update_progress 0 0 0 ""
    fi
    
    return 0
}

# ============================================================================
# PROGRESS UPDATES
# ============================================================================

# Funktion: Update Fortschritt
# Parameter:
#   $1 = Prozent (0-100)
#   $2 = Kopierte MB
#   $3 = Gesamt MB
#   $4 = ETA (Format: "HH:MM:SS" oder leer)
# Schreibt: progress.json
api_update_progress() {
    local percent="$1"
    local copied_mb="${2:-0}"
    local total_mb="${3:-0}"
    local eta="${4:-}"
    
    local timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
    
    # Schreibe progress.json
    local progress_json=$(cat <<EOF
{
  "percent": ${percent},
  "copied_mb": ${copied_mb},
  "total_mb": ${total_mb},
  "eta": "${eta}",
  "timestamp": "${timestamp}"
}
EOF
)
    api_write_json "progress.json" "${progress_json}"
    
    return 0
}

# ============================================================================
# HISTORY
# ============================================================================

# Funktion: Füge History-Eintrag hinzu
# Parameter:
#   $1 = Status (completed/error)
#   $2 = Label
#   $3 = Typ
#   $4 = Ergebnis (success/error)
#   $5 = Fehlermeldung (optional, bei error)
# Schreibt: history.json (append)
api_add_history() {
    local status="$1"
    local label="$2"
    local type="$3"
    local result="$4"
    local error_msg="${5:-}"
    
    local timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
    
    # Lese bestehende History (max 50 Einträge)
    local history_file="${API_DIR}/history.json"
    local history="[]"
    if [[ -f "$history_file" ]]; then
        history=$(cat "$history_file" 2>/dev/null || echo "[]")
    fi
    
    # Neuer Eintrag
    local entry=$(cat <<EOF
{
  "timestamp": "${timestamp}",
  "label": "${label}",
  "type": "${type}",
  "status": "${status}",
  "result": "${result}",
  "error_message": ${error_msg:+"\"${error_msg}\""}${error_msg:-null}
}
EOF
)
    
    # Füge Eintrag hinzu (am Anfang, neueste zuerst)
    # Nutze jq falls verfügbar, sonst einfaches JSON-Array-Append
    if command -v jq >/dev/null 2>&1; then
        history=$(echo "$history" | jq ". |= [${entry}] + . | .[0:50]" 2>/dev/null || echo "[]")
    else
        # Fallback ohne jq: Einfaches Prepend (nicht schön aber funktioniert)
        history="[${entry}]"
    fi
    
    api_write_json "history.json" "${history}"
    
    return 0
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Funktion: Initialisiere API (erstelle Verzeichnis, leere JSONs)
# Wird beim Service-Start aufgerufen
api_init() {
    # Erstelle API-Verzeichnis
    if [[ ! -d "$API_DIR" ]]; then
        mkdir -p "$API_DIR" 2>/dev/null || return 1
        chmod 755 "$API_DIR" 2>/dev/null || true
    fi
    
    # Erstelle leere/default JSONs falls nicht vorhanden
    if [[ ! -f "${API_DIR}/status.json" ]]; then
        api_update_status "idle"
    fi
    
    if [[ ! -f "${API_DIR}/progress.json" ]]; then
        api_update_progress 0 0 0 ""
    fi
    
    if [[ ! -f "${API_DIR}/history.json" ]]; then
        echo "[]" > "${API_DIR}/history.json"
        chmod 644 "${API_DIR}/history.json" 2>/dev/null || true
    fi
    
    return 0
}
