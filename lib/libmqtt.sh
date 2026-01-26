#!/bin/bash
################################################################################
# disk2iso v1.2.0 - MQTT Library
# Filepath: lib/libmqtt.sh
#
# Beschreibung:
#   MQTT-Integration für Home Assistant und andere Systeme
#   - Status-Updates (idle, copying, waiting, completed, error)
#   - Fortschritts-Updates (Prozent, MB, ETA)
#   - Medium-Informationen (Label, Typ, Größe)
#   - Availability-Tracking (online/offline)
#
# Abhängigkeiten:
#   - mosquitto-clients (mosquitto_pub)
#
# Version: 1.2.0
# Datum: 06.01.2026
################################################################################

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================
# Globale Variable für Modulname
readonly MODULE_NAME_MQTT="mqtt"
# Globale Variable für Verfügbarkeit
MQTT_SUPPORT=false

# ===========================================================================
# check_dependencies_mqtt
# ---------------------------------------------------------------------------
# Funktion.: Prüfe alle MQTT Modul-Abhängigkeiten (Modul-Dateien, 
# .........  Ausgabe-Ordner, kritische und optionale Software), lädt bei 
# .........  erfolgreicher Prüfung die Sprachdatei für das Modul.
# Parameter: keine
# Rückgabe.: 0 = Verfügbar (Modul nutzbar)
# .........  1 = Nicht verfügbar (Modul deaktiviert)
# Extras...: Setzt MQTT_SUPPORT=true bei erfolgreicher Prüfung
# ===========================================================================
check_dependencies_mqtt() {

    #-- Alle Modul Abhängigkeiten prüfen -------------------------------------
    check_module_dependencies "$MODULE_NAME_MQTT" || return 1

    #-- Setze Verfügbarkeit -------------------------------------------------
    MQTT_SUPPORT=true
    
    #-- Abhängigkeiten erfüllt ----------------------------------------------
    log_info "$MSG_MQTT_SUPPORT_AVAILABLE"
    return 0
}

# ============================================================================
# GLOBALE VARIABLEN
# ============================================================================

# ============================================================================
# MQTT CONFIGURATION (aus config.sh)
# ============================================================================

# Diese Variablen werden aus config.sh geladen:
# MQTT_ENABLED=false
# MQTT_BROKER="192.168.20.10"
# MQTT_PORT=1883
# MQTT_USER=""
# MQTT_PASSWORD=""
# MQTT_TOPIC_PREFIX="homeassistant/sensor/disk2iso"
# MQTT_CLIENT_ID="disk2iso-${HOSTNAME}"
# MQTT_QOS=0
# MQTT_RETAIN=true
# MQTT-Status (wird durch check_dependencies_mqtt gesetzt)

MQTT_AVAILABLE=false

# Aktuelle Werte (für Delta-Publishing)
MQTT_LAST_STATE=""
MQTT_LAST_PROGRESS=0
MQTT_LAST_UPDATE=0

# API-Verzeichnis wird von libapi.sh definiert (readonly)
# API_DIR ist bereits in libapi.sh als readonly gesetzt
# NICHT hier nochmal definieren da libapi.sh VOR libmqtt.sh geladen wird

# ============================================================================
# MQTT INITIALIZATION
# ============================================================================

# Funktion: Initialisiere MQTT-Modul
# Prüft Konfiguration und Verfügbarkeit
# Rückgabe: 0 = OK, 1 = MQTT nicht verfügbar/deaktiviert
mqtt_init() {
    # Prüfe ob MQTT aktiviert ist
    if [[ "${MQTT_ENABLED:-false}" != "true" ]]; then
        log_info "$MSG_MQTT_DISABLED"
        MQTT_AVAILABLE=false
        return 1
    fi
    
    # Prüfe ob MQTT-Support verfügbar ist (wurde bereits von check_dependencies_mqtt geprüft)
    if [[ "$MQTT_SUPPORT" != "true" ]]; then
        log_warning "$MSG_MQTT_NOT_AVAILABLE"
        MQTT_AVAILABLE=false
        return 1
    fi
    
    # Prüfe Broker-Konfiguration
    if [[ -z "${MQTT_BROKER:-}" ]]; then
        log_error "$MSG_MQTT_ERROR_NO_BROKER"
        MQTT_AVAILABLE=false
        return 1
    fi
    
    # Setze Client-ID falls nicht definiert
    if [[ -z "${MQTT_CLIENT_ID:-}" ]]; then
        MQTT_CLIENT_ID="disk2iso-${HOSTNAME}"
    fi
    
    # Setze Defaults
    MQTT_PORT="${MQTT_PORT:-1883}"
    MQTT_QOS="${MQTT_QOS:-0}"
    MQTT_RETAIN="${MQTT_RETAIN:-true}"
    MQTT_TOPIC_PREFIX="${MQTT_TOPIC_PREFIX:-homeassistant/sensor/disk2iso}"
    
    MQTT_AVAILABLE=true
    log_info "$MSG_MQTT_INITIALIZED $MQTT_BROKER:$MQTT_PORT"
    
    # Sende Initial Availability
    mqtt_publish_availability "online"
    
    # Sende Idle-State
    mqtt_publish_state "idle"
    
    return 0
}

# ============================================================================
# API JSON FILE HELPER
# ============================================================================

# HINWEIS: api_write_json() und api_add_history() werden aus libapi.sh geladen
# Diese Funktionen sind bereits in libapi.sh definiert und müssen nicht dupliziert werden

# ============================================================================
# MQTT PUBLISH HELPER
# ============================================================================

# Funktion: Basis-MQTT-Publish
# Parameter: $1 = Topic (relativ zu PREFIX), $2 = Payload
# Beispiel: mqtt_publish "state" "copying"
mqtt_publish() {
    if [[ "$MQTT_AVAILABLE" != "true" ]]; then
        return 1
    fi
    
    local topic="${MQTT_TOPIC_PREFIX}/$1"
    local payload="$2"
    local retain_flag=""
    
    # Retain-Flag setzen
    if [[ "${MQTT_RETAIN:-true}" == "true" ]]; then
        retain_flag="-r"
    fi
    
    # Publish mit oder ohne Authentifizierung
    if [[ -n "${MQTT_USER:-}" ]] && [[ -n "${MQTT_PASSWORD:-}" ]]; then
        # Mit Authentifizierung
        mosquitto_pub \
            -h "${MQTT_BROKER}" \
            -p "${MQTT_PORT}" \
            -i "${MQTT_CLIENT_ID}" \
            -q "${MQTT_QOS}" \
            ${retain_flag} \
            -u "${MQTT_USER}" \
            -P "${MQTT_PASSWORD}" \
            -t "${topic}" \
            -m "${payload}" \
            2>/dev/null
    else
        # Ohne Authentifizierung
        mosquitto_pub \
            -h "${MQTT_BROKER}" \
            -p "${MQTT_PORT}" \
            -i "${MQTT_CLIENT_ID}" \
            -q "${MQTT_QOS}" \
            ${retain_flag} \
            -t "${topic}" \
            -m "${payload}" \
            2>/dev/null
    fi
    
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "$MSG_MQTT_PUBLISH_FAILED ${topic}: ${payload} (Exit: $exit_code)"
        return 1
    fi
    
    return 0
}

# ============================================================================
# AVAILABILITY
# ============================================================================

# Funktion: Sende Availability-Status
# Parameter: $1 = "online" oder "offline"
# Topic: {prefix}/availability
mqtt_publish_availability() {
    local status="$1"
    
    if [[ "$MQTT_AVAILABLE" != "true" ]]; then
        return 1
    fi
    
    mqtt_publish "availability" "${status}"
    
    if [[ "$status" == "online" ]]; then
        log_info "$MSG_MQTT_ONLINE"
    else
        log_info "$MSG_MQTT_OFFLINE"
    fi
    
    return 0
}

# ============================================================================
# STATE UPDATES
# ============================================================================

# Funktion: Sende Status-Update
# Parameter: 
#   $1 = State (idle|copying|waiting|completed|error)
#   $2 = Disc Label (optional)
#   $3 = Disc Type (optional)
#   $4 = Error Message (optional, nur bei error)
#
# Topics:
#   {prefix}/state - JSON mit Status + Timestamp
#   {prefix}/attributes - JSON mit allen Details
mqtt_publish_state() {
    local state="$1"
    local label="${2:-}"
    local type="${3:-}"
    local error_msg="${4:-}"
    
    # Timestamp
    local timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
    
    # State Topic (einfaches JSON)
    local state_json=$(cat <<EOF
{
  "status": "${state}",
  "timestamp": "${timestamp}"
}
EOF
)
    
    # IMMER status.json für API schreiben (unabhängig von MQTT)
    api_write_json "status.json" "${state_json}"
    
    # Attributes Topic (vollständige Informationen)
    local disc_size_mb=0
    if [[ -n "${disc_volume_size:-}" ]] && [[ -n "${disc_block_size:-}" ]]; then
        disc_size_mb=$(( disc_volume_size * disc_block_size / 1024 / 1024 ))
    fi
    
    # Container-Info
    local container="${CONTAINER_TYPE:-none}"
    if [[ "${IS_CONTAINER:-false}" == "true" ]]; then
        container="${CONTAINER_TYPE:-unknown}"
    fi
    
    # Methode (falls verfügbar aus globalem Kontext)
    local method="${COPY_METHOD:-unknown}"
    
    local attr_json=$(cat <<EOF
{
  "disc_label": "${label}",
  "disc_type": "${type}",
  "disc_size_mb": ${disc_size_mb},
  "progress_percent": 0,
  "progress_mb": 0,
  "total_mb": ${disc_size_mb},
  "eta": "",
  "filename": "${iso_basename:-}",
  "method": "${method}",
  "container_type": "${container}",
  "error_message": ${error_msg:+"\"${error_msg}\""}${error_msg:-null}
}
EOF
)
    
    # IMMER attributes.json für API schreiben (unabhängig von MQTT)
    api_write_json "attributes.json" "${attr_json}"
    
    # Ab hier: Nur MQTT-spezifische Logik
    if [[ "$MQTT_AVAILABLE" != "true" ]]; then
        return 0
    fi
    
    # Vermeide doppelte Updates
    if [[ "$state" == "$MQTT_LAST_STATE" ]] && [[ "$state" != "copying" ]]; then
        return 0
    fi
    
    # Wenn neuer Kopiervorgang startet: Reset Tracking-Variablen
    if [[ "$state" == "copying" ]] && [[ "$MQTT_LAST_STATE" != "copying" ]]; then
        MQTT_LAST_PROGRESS=0
        MQTT_LAST_UPDATE=0
    fi
    
    # Wenn zu idle/waiting wechselt: Reset Progress auf 0
    if [[ "$state" == "idle" ]] || [[ "$state" == "waiting" ]]; then
        MQTT_LAST_PROGRESS=0
        MQTT_LAST_UPDATE=0
    fi
    
    MQTT_LAST_STATE="$state"
    
    # MQTT Publishing
    mqtt_publish "state" "${state_json}"
    mqtt_publish "attributes" "${attr_json}"
    
    # Progress-Topic auf 0 setzen bei idle/waiting
    if [[ "$state" == "idle" ]] || [[ "$state" == "waiting" ]]; then
        mqtt_publish "progress" "0"
    fi
    
    # Log
    case "$state" in
        idle)
            log_info "$MSG_MQTT_STATE_IDLE"
            ;;
        copying)
            log_info "$MSG_MQTT_STATE_COPYING ${label} (${type})"
            ;;
        waiting)
            log_info "$MSG_MQTT_STATE_WAITING"
            ;;
        completed)
            log_info "$MSG_MQTT_STATE_COMPLETED ${label}"
            ;;
        error)
            log_error "$MSG_MQTT_STATE_ERROR ${error_msg}"
            ;;
    esac
    
    return 0
}

# ============================================================================
# PROGRESS UPDATES
# ============================================================================

# Funktion: Sende Fortschritts-Update
# Parameter:
#   $1 = Prozent (0-100)
#   $2 = Kopierte MB (optional)
#   $3 = Gesamt MB (optional)
#   $4 = ETA (optional, Format: "HH:MM:SS")
#
# Topics:
#   {prefix}/progress - Nur Prozent-Wert (für einfache Gauges)
#   {prefix}/attributes - Update mit aktuellen Werten
mqtt_publish_progress() {
    local percent="$1"
    local copied_mb="${2:-0}"
    local total_mb="${3:-0}"
    local eta="${4:-}"
    
    # NICHT mehr progress.json schreiben - das macht api_update_progress!
    # mqtt_publish_progress ist NUR für MQTT-Publishing zuständig
    
    # Ab hier: Nur MQTT-spezifische Logik
    if [[ "$MQTT_AVAILABLE" != "true" ]]; then
        return 0
    fi
    
    # Rate-Limiting: Nur alle 10 Sekunden updaten
    local current_time=$(date +%s)
    local time_diff=$((current_time - MQTT_LAST_UPDATE))
    
    if [[ $time_diff -lt 10 ]] && [[ $percent -ne 100 ]]; then
        return 0
    fi
    
    # Delta-Check: Nur bei Änderung > 1% publishen
    # Wenn percent < MQTT_LAST_PROGRESS: Neuer Kopiervorgang gestartet -> Sende Update
    local percent_diff=$((percent - MQTT_LAST_PROGRESS))
    if [[ $percent_diff -lt 1 ]] && [[ $percent -ne 100 ]] && [[ $percent -ge $MQTT_LAST_PROGRESS ]]; then
        return 0
    fi
    
    MQTT_LAST_PROGRESS=$percent
    MQTT_LAST_UPDATE=$current_time
    
    # MQTT Publishing
    mqtt_publish "progress" "${percent}"
    
    # Bestimme Einheit basierend auf Disc-Typ (Audio-CD = Tracks, sonst MB)
    local unit="MB"
    if [[ "${disc_type:-}" == "audio-cd" ]]; then
        unit="Tracks"
    fi
    
    # Attributes Topic (Update nur relevante Felder)
    local attr_json=$(cat <<EOF
{
  "disc_label": "${disc_label:-}",
  "disc_type": "${disc_type:-}",
  "disc_size_mb": ${total_mb},
  "progress_percent": ${percent},
  "progress_mb": ${copied_mb},
  "total_mb": ${total_mb},
  "progress_unit": "${unit}",
  "eta": "${eta}",
  "filename": "${iso_basename:-}",
  "method": "${COPY_METHOD:-unknown}",
  "container_type": "${CONTAINER_TYPE:-none}",
  "error_message": null
}
EOF
)
    
    mqtt_publish "attributes" "${attr_json}"
    
    # Log-Ausgabe mit korrekter Einheit
    log_info "$MSG_MQTT_PROGRESS ${percent}% (${copied_mb}/${total_mb} ${unit}, ETA: ${eta})"
    
    return 0
}

# ============================================================================
# COMPLETION
# ============================================================================

# Funktion: Sende Abschluss-Meldung
# Parameter:
#   $1 = Filename (ISO)
#   $2 = Dauer (optional, Format: "HH:MM:SS" oder Sekunden)
mqtt_publish_complete() {
    if [[ "$MQTT_AVAILABLE" != "true" ]]; then
        return 0
    fi
    
    local filename="$1"
    local duration="${2:-}"
    
    # State auf completed setzen
    mqtt_publish_state "completed" "${disc_label:-}" "${disc_type:-}"
    
    # Progress auf 100%
    mqtt_publish_progress 100 "${disc_volume_size:-0}" "${disc_volume_size:-0}" "00:00:00"
    
    # Füge zur History hinzu
    api_add_history "completed" "${disc_label:-}" "${disc_type:-}" "success"
    
    log_info "$MSG_MQTT_COMPLETED ${filename} (${duration})"
    
    return 0
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

# Funktion: Sende Fehler-Meldung
# Parameter:
#   $1 = Error Message
mqtt_publish_error() {
    if [[ "$MQTT_AVAILABLE" != "true" ]]; then
        return 0
    fi
    
    local error_message="$1"
    
    # State auf error setzen
    mqtt_publish_state "error" "${disc_label:-}" "${disc_type:-}" "${error_message}"
    
    # Füge zur History hinzu
    api_add_history "error" "${disc_label:-}" "${disc_type:-}" "error"
    
    log_error "$MSG_MQTT_ERROR ${error_message}"
    
    return 0
}

# ============================================================================
# CLEANUP
# ============================================================================

# Funktion: MQTT Cleanup beim Beenden
# Setzt Availability auf offline
mqtt_cleanup() {
    if [[ "$MQTT_AVAILABLE" == "true" ]]; then
        mqtt_publish_availability "offline"
    fi
}

# ============================================================================
# ENDE DER MQTT LIBRARY
# ============================================================================
