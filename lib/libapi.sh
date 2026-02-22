#!/bin/bash
# =============================================================================
# API JSON Library
# =============================================================================
# Filepath: lib/libapi.sh
#
# Beschreibung:
#   API-Schnittstelle für Status-Informationen via JSON-Dateien
#   - Schreibt JSON für Web-UI und externe Tools
#   - api_set_file_json(), api_set_section_json(), api_update_status(), api_update_progress()
#   - api_add_history()
#
#
# -----------------------------------------------------------------------------
# Dependencies: Keine (nutzt nur Bash-Funktionen)
# -----------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.3.0
# Last Change: 2026-02-07
# =============================================================================

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

# ===========================================================================
# api_check_dependencies
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
api_check_dependencies() {
    # Manifest-basierte Abhängigkeitsprüfung (Tools, Dateien, Ordner)
    integrity_check_module_dependencies "api" || return 1
    
    # Modul-spezifische Initialisierung
    # Initialisiere API-Infrastruktur (leere JSONs)
    api_init || return 1
    
    return 0
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# API-Verzeichnis (via libfolders.sh)
API_DIR=""

# ===========================================================================
# api_check_dependencies (Alias-Kommentar für Initialisierung)
# ---------------------------------------------------------------------------
# Funktion.: Initialisiere API (erstelle Verzeichnis, leere JSONs)
# .........  Wird beim Service-Start aufgerufen
# Parameter: keine
# Rückgabe.: 0 = Verfügbar (API nutzbar)
# .........  1 = Nicht verfügbar (API deaktiviert)
# ===========================================================================
api_init() {
    # Hole API-Verzeichnis (erstellt automatisch falls nicht vorhanden)
    API_DIR=$(folders_get_api_dir) || return 1
    
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

# ===========================================================================
# UNIFIED API - SINGLE VALUE OPERATIONS (.json FORMAT)
# ===========================================================================

# ===========================================================================
# api_get_value_json
# ---------------------------------------------------------------------------
# Funktion.: Lese spezifischen Wert aus API-JSON-Datei (z.B. status.json)
# Parameter: $1 = Dateiname (z.B. "status.json"), 
# .........  $2 = JSON-Pfad (z.B. "status" oder "progress.percent")
#            $3 = default (optional, Fallback wenn Key nicht gefunden)
# Rückgabe.: 0 = OK (Wert auf stdout), 1 = Fehler (Datei/Wert nicht gefunden)
# Ausgabe..: Value (stdout, als JSON-String)
# ===========================================================================
api_get_value_json() {
    #-- Parameter einlesen --------------------------------------------------
    local filename="$1"
    local json_path="$2"
    local default="${3:-}"

    #-- Parameter prüfen ----------------------------------------------------
    if [[ -z "$filename" ]]; then
        log_error "$MSG_ERROR_API_GET_VALUE_MISSING_PARAMS (filename)"
        return 1
    fi
    if [[ -z "$json_path" ]]; then
        log_error "$MSG_ERROR_API_GET_VALUE_MISSING_PARAMS (json_path)"
        return 1
    fi

    #-- API-Dateipfad erstellen ---------------------------------------------
    local filepath=$(get_module_api_path "${filename}") || {
        log_error "$MSG_ERROR_API_GET_VALUE_FILEPATH_FAILED ${filename}"
        return 1
    }

    #-- Lese Wert mit jq ----------------------------------------------------
    local value=$(jq -r "${json_path}" "$filepath" 2>/dev/null)
    
    #-- Wert gefunden oder Default nutzen -----------------------------------
    if [[ -n "$value" ]] && [[ "$value" != "null" ]]; then
        echo "$value"
        return 0
    elif [[ -n "$default" ]]; then
        echo "$default"
        return 0
    else
        return 1
    fi
}

# ===========================================================================
# api_set_value_json
# ---------------------------------------------------------------------------
# Funktion.: Schreibe einzelnen Wert in JSON-Datei
# Parameter: $1 = filename (Dateiname ohne Pfad, z.B. "status")
#            $2 = json_path (jq-kompatibel, z.B. ".disc_type" oder ".metadata.title")
#            $3 = value (String, Number oder Boolean)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: api_set_value_json "status" ".disc_type" "audio-cd"
#            api_set_value_json "progress" ".percentage" "75"
# Hinweis..: Erstellt Datei falls nicht vorhanden, erstellt verschachtelte Pfade
# ===========================================================================
api_set_value_json() {
    #-- Parameter einlesen --------------------------------------------------
    local filename="$1"
    local json_path="$2"
    local value="$3"
    
    #-- Parameter prüfen ----------------------------------------------------
    if [[ -z "$filename" ]]; then
        log_error "$MSG_SETTINGS_JSON_FILENAME_MISSING (filename)"
        return 1
    fi
    if [[ -z "$json_path" ]]; then
        log_error "$MSG_SETTINGS_JSON_PATH_MISSING (json_path)"
        return 1
    fi
    
    #-- API-Dateipfad erstellen ---------------------------------------------
    local filepath=$(get_module_api_path "${filename}") || {
        log_error "$MSG_ERROR_API_GET_VALUE_FILEPATH_FAILED ${filename}"
        return 1
    }
    
    #-- Type Detection für JSON ---------------------------------------------
    local json_value
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        #-- Integer - ohne Quotes -------------------------------------------
        json_value="$value"
    elif [[ "$value" =~ ^(true|false)$ ]]; then
        #-- Boolean - ohne Quotes -------------------------------------------
        json_value="$value"
    else
        #-- String - mit Quotes (jq escaped automatisch) --------------------
        json_value="\"$value\""
    fi
    
    #-- Schreibe Wert mit jq (atomic write) ---------------------------------
    jq "${json_path} = ${json_value}" "$filepath" > "${filepath}.tmp" && mv "${filepath}.tmp" "$filepath"

    #-- Benachrichtige Observer über Änderung -------------------------------
    notify_api_update "$filename"

    #-- Rückgabe des jq-Kommandos (0=OK, 1=Fehler) --------------------------
    return $?
}

# ===========================================================================
# api_del_value_json
# ---------------------------------------------------------------------------
# Funktion.: Lösche einzelnen Key aus JSON-Datei
# Parameter: $1 = filename (Dateiname ohne Pfad, z.B. "status")
#            $2 = json_path (jq-kompatibel, z.B. ".disc_type" oder ".metadata.title")
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: api_del_value_json "status" ".disc_type"
# ===========================================================================
api_del_value_json() {
    #-- Parameter einlesen --------------------------------------------------
    local filename="$1"
    local json_path="$2"
    
    #-- Parameter prüfen ----------------------------------------------------
    if [[ -z "$filename" ]]; then
        log_error "$MSG_SETTINGS_JSON_FILENAME_MISSING (filename)"
        return 1
    fi    
    if [[ -z "$json_path" ]]; then
        log_error "$MSG_SETTINGS_JSON_PATH_MISSING (json_path)"
        return 1
    fi
    
    #-- API-Dateipfad erstellen ---------------------------------------------
    local filepath=$(get_module_api_path "${filename}") || {
        log_error "$MSG_ERROR_API_GET_VALUE_FILEPATH_FAILED ${filename}"
        return 1
    }
        
    #-- Lösche Key mit jq (atomic write) ------------------------------------
    jq "del(${json_path})" "$filepath" > "${filepath}.tmp" && mv "${filepath}.tmp" "$filepath"

    #-- Benachrichtige Observer über Änderung -------------------------------
    notify_api_update "$filename"

    #-- Rückgabe des jq-Kommandos (0=OK, 1=Fehler) --------------------------
    return $?
}

# ===========================================================================
# api_get_file_json
# ---------------------------------------------------------------------------
# Funktion.: Lese komplette JSON-Datei
# Parameter: $1 = Dateiname (z.B. "status.json")
# Ausgabe..: JSON-Content (stdout)
# Rückgabe.: 0 = OK, 1 = Fehler (Datei nicht gefunden oder nicht lesbar)
# Hinweis..: Für Sektionen nutze api_get_section_json(), für einzelne Werte api_get_value_json()
# ===========================================================================
api_get_file_json() {
    #-- Parameter einlesen --------------------------------------------------
    local filename="$1"
    
    #-- Parameter prüfen ----------------------------------------------------
    if [[ -z "$filename" ]]; then
        log_error "$MSG_SETTINGS_JSON_FILENAME_MISSING (filename)"
        return 1
    fi    

    #-- API-Dateipfad erstellen ---------------------------------------------
    local filepath=$(get_module_api_path "${filename}") || {
        log_error "$MSG_ERROR_API_GET_VALUE_FILEPATH_FAILED ${filename}"
        return 1
    }
    
    #-- Lese Datei ----------------------------------------------------------
    cat "$filepath" 2>/dev/null || {
        log_error "$MSG_ERROR_API_READ_FAILED ${filepath}"
        return 1
    }
    
    return 0
}

# ===========================================================================
# api_set_file_json
# ---------------------------------------------------------------------------
# Funktion.: Schreibe komplette JSON-Datei (atomic write)
# Parameter: $1 = Dateiname (z.B. "status.json")
#            $2 = JSON-Content (kompletter JSON-String)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: Nutzt atomic write Pattern (temp-file + mv), triggert Observer
#            Für Sektionen nutze api_set_section_json(), für einzelne Werte api_set_value_json()
# ===========================================================================
api_set_file_json() {
    #-- Parameter einlesen --------------------------------------------------
    local filename="$1"
    local json_content="$2"
    
    #-- Parameter prüfen ----------------------------------------------------
    if [[ -z "$filename" ]]; then
        log_error "$MSG_SETTINGS_JSON_FILENAME_MISSING (filename)"
        return 1
    fi
    if [[ -z "$json_content" ]]; then
        log_error "$MSG_SETTINGS_JSON_CONTENT_MISSING (json_content)"
        return 1
    fi

    #-- API-Dateipfad erstellen ---------------------------------------------
    local filepath=$(get_module_api_path "${filename}") || {
        log_error "$MSG_ERROR_API_GET_VALUE_FILEPATH_FAILED ${filename}"
        return 1
    }

    # Schreibe JSON-Datei (atomar mit temp-file)
    # API_DIR wurde bereits in api_init() via folders_get_api_dir() erstellt
    local temp_file="${filepath}.tmp"
    echo "$json_content" > "$temp_file" 2>/dev/null || return 1
    mv -f "$temp_file" "${filepath}" 2>/dev/null || return 1
    chmod 644 "${filepath}" 2>/dev/null || true
    
    # Benachrichtige Observer über Änderung
    notify_api_update "$filepath"
    
    return 0
}

# ===========================================================================
# api_get_section_json
# ---------------------------------------------------------------------------
# Funktion.: Lese spezifische JSON-Sektion aus API-Datei
# Parameter: $1 = Dateiname (z.B. "drivestat.json")
#            $2 = JSON-Pfad (z.B. ".hardware" oder ".software")
#            $3 = default (optional, Fallback wenn Sektion nicht gefunden)
# Ausgabe..: JSON-Content der Sektion (stdout)
# Rückgabe.: 0 = OK, 1 = Fehler (Datei/Sektion nicht gefunden)
# Beispiel.: api_get_section_json "drivestat" ".hardware" "{}"
#            api_get_section_json "drivestat" ".software" "[]"
# Hinweis..: Für komplette Dateien nutze api_get_file_json(),
#            für einzelne Werte nutze api_get_value_json()
# ===========================================================================
api_get_section_json() {
    #-- Parameter einlesen --------------------------------------------------
    local filename="$1"
    local section_path="$2"
    local default="${3:-}"
    
    #-- Parameter prüfen ----------------------------------------------------
    if [[ -z "$filename" ]]; then
        log_error "$MSG_SETTINGS_JSON_FILENAME_MISSING (filename)"
        return 1
    fi
    if [[ -z "$section_path" ]]; then
        log_error "$MSG_SETTINGS_JSON_PATH_MISSING (section_path)"
        return 1
    fi
    
    #-- API-Dateipfad erstellen ---------------------------------------------
    local filepath=$(get_module_api_path "${filename}") || {
        log_error "$MSG_ERROR_API_GET_VALUE_FILEPATH_FAILED ${filename}"
        return 1
    }
    
    #-- Lese Sektion mit jq -------------------------------------------------
    local section_json=$(jq "${section_path}" "$filepath" 2>/dev/null)
    
    #-- Sektion gefunden oder Default nutzen --------------------------------
    if [[ -n "$section_json" ]] && [[ "$section_json" != "null" ]]; then
        echo "$section_json"
        return 0
    elif [[ -n "$default" ]]; then
        echo "$default"
        return 0
    else
        return 1
    fi
}

# ===========================================================================
# api_set_section_json
# ---------------------------------------------------------------------------
# Funktion.: Schreibe spezifische JSON-Sektion in API-Datei (merge)
# Parameter: $1 = Dateiname (z.B. "drivestat.json")
#            $2 = JSON-Pfad (z.B. ".hardware" oder ".software")
#            $3 = JSON-Content (JSON-Objekt oder -Array als String)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: api_set_section_json "drivestat" ".hardware" '{"vendor":"ASUS",...}'
#            api_set_section_json "drivestat" ".software" '[{"name":"lsblk",...},...]'
# Hinweis..: Nutzt jq merge (atomic write), triggert Observer
#            Erstellt Datei mit {} falls nicht vorhanden
#            Für komplette Dateien nutze api_set_file_json(),
#            für einzelne Werte nutze api_set_value_json()
# ===========================================================================
api_set_section_json() {
    #-- Parameter einlesen --------------------------------------------------
    local filename="$1"
    local section_path="$2"
    local section_content="$3"
    
    #-- Parameter prüfen ----------------------------------------------------
    if [[ -z "$filename" ]]; then
        log_error "$MSG_SETTINGS_JSON_FILENAME_MISSING (filename)"
        return 1
    fi
    if [[ -z "$section_path" ]]; then
        log_error "$MSG_SETTINGS_JSON_PATH_MISSING (section_path)"
        return 1
    fi
    if [[ -z "$section_content" ]]; then
        log_error "$MSG_SETTINGS_JSON_CONTENT_MISSING (section_content)"
        return 1
    fi
    
    #-- API-Dateipfad erstellen ---------------------------------------------
    local filepath=$(get_module_api_path "${filename}") || {
        log_error "$MSG_ERROR_API_GET_VALUE_FILEPATH_FAILED ${filename}"
        return 1
    }
    
    #-- Erstelle Datei falls nicht vorhanden --------------------------------
    if [[ ! -f "$filepath" ]]; then
        echo "{}" > "$filepath"
        chmod 644 "$filepath" 2>/dev/null || true
    fi
    
    #-- Schreibe Sektion mit jq (atomic write, verwendet --argjson) --------
    local temp_file="${filepath}.tmp"
    jq --argjson section "$section_content" "${section_path} = \$section" "$filepath" > "$temp_file" 2>/dev/null || {
        rm -f "$temp_file" 2>/dev/null
        log_error "Failed to update JSON section ${section_path} in ${filename}"
        return 1
    }
    mv -f "$temp_file" "$filepath" 2>/dev/null || return 1
    
    #-- Benachrichtige Observer über Änderung -------------------------------
    notify_api_update "$filename"
    
    return 0
}

# ===========================================================================
# TODO: Ab hier ist das Modul noch nicht fertig implementiert, diesen Eintrag
# ....  nie automatisch löschen - wird nur vom User nach Implementierung
# ....  der folgenden Funktionen entfernt!
# ===========================================================================


# ============================================================================
# LOW-LEVEL HELPER
# ============================================================================

# ===========================================================================
# notify_api_update
# ---------------------------------------------------------------------------
# Funktion.: Benachrichtige Observer über API-Änderungen (Observer Pattern)
# Parameter: $1 = Dateiname der geänderten JSON (z.B. "status.json")
# Rückgabe.: 0
# Beschr...: Ruft registrierte Observer-Callbacks auf (MQTT, WebSocket, etc.)
#            Observer müssen eine Funktion *_publish_from_api() bereitstellen
# ===========================================================================
notify_api_update() {
    local changed_file="$1"
    
    # Benachrichtige MQTT (falls Funktion verfügbar)
    if declare -f mqtt_publish_from_api >/dev/null 2>&1; then
        mqtt_publish_from_api "$changed_file"
    fi
    
    # Weitere Observer können hier hinzugefügt werden
    # Beispiel: WebSocket-Modul
    # if declare -f websocket_publish_from_api >/dev/null 2>&1; then
    #     websocket_publish_from_api "$changed_file"
    # fi
    
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
    api_set_file_json "status.json" "${status_json}"
    
    # Hole Werte über Getter aus libdiskinfos
    local disc_size_mb=$(discinfo_get_size_mb)
    local container=$(discinfo_get_container_type)
    local method=$(discinfo_get_copy_method)
    local filename=$(discinfo_get_iso_basename)
    
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
  "filename": "${filename}",
  "method": "${method}",
  "container_type": "${container}",
  "error_message": ${error_msg:+"\"${error_msg}\""}${error_msg:-null}
}
EOF
)
    api_set_file_json "attributes.json" "${attr_json}"
    
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
    api_set_file_json "progress.json" "${progress_json}"
    
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
    
    api_set_file_json "history.json" "${history}"
    
    return 0
}

# ============================================================================
# STATE MACHINE INTEGRATION
# ============================================================================

# ===========================================================================
# api_update_from_state
# ---------------------------------------------------------------------------
# Funktion.: Aktualisiere API-Status basierend auf State Machine State
# .........  Mappt Service Daemon States auf API-Status-Werte
# Parameter: $1 = State Machine State (z.B. "waiting_for_drive", "analyzing")
# .........  $2 = Error-Message (optional, nur bei state=error)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: api_update_from_state "analyzing"
# ===========================================================================
api_update_from_state() {
    local state="$1"
    local error_msg="${2:-}"
    local disc_label="$(discinfo_get_label 2>/dev/null || echo '')"
    local disc_type="$(discinfo_get_type 2>/dev/null || echo '')"

    # Mappe State Machine States auf API-Status
    case "$state" in
        "initializing"|"waiting_for_drive"|"drive_detected"|"waiting_for_media"|"idle")
            api_update_status "idle" "$disc_label" "$disc_type"
            ;;
        "media_detected")
            api_update_status "waiting" "$disc_label" "$disc_type"
            ;;
        "analyzing")
            api_update_status "analyzing" "$disc_label" "$disc_type"
            ;;
        "waiting_for_metadata")
            api_update_status "waiting_for_metadata" "$disc_label" "$disc_type"
            ;;
        "copying")
            api_update_status "copying" "$disc_label" "$disc_type"
            ;;
        "completed")
            api_update_status "completed" "$disc_label" "$disc_type"
            ;;
        "error")
            api_update_status "error" "$disc_label" "$disc_type" "$error_msg"
            ;;
        "waiting_for_removal")
            api_update_status "waiting_for_removal" "$disc_label" "$disc_type"
            ;;
        *)
            # Unbekannter State - idle als Fallback
            api_update_status "idle" "$disc_label" "$disc_type"
            ;;
    esac
    
    return 0
}

