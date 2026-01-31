#!/bin/bash
# ===========================================================================
# MQTT Library
# ===========================================================================
# Filepath: lib/libmqtt.sh
#
# Beschreibung:
#   MQTT-Integration für Home Assistant und andere Systeme
#   - Status-Updates (idle, copying, waiting, completed, error)
#   - Fortschritts-Updates (Prozent, MB, ETA)
#   - Medium-Informationen (Label, Typ, Größe)
#   - Availability-Tracking (online/offline)
#
# ---------------------------------------------------------------------------
# Dependencies: liblogging.sh (log_debug, log_info, log_warning, log_error)
#               libconfig.sh (get_module_ini_path, get_ini_value)
#               libapi.sh (api_read_json)
#               Externes Tool: mosquitto_pub
# ---------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.3.0
# Last Change: 2026-01-29 21:00
# ===========================================================================

# ===========================================================================
# MODULE NAME
# ===========================================================================
readonly MODULE_NAME_MQTT="mqtt"             # Globale Variable für Modulname

# ===========================================================================
# DEPENDENCY CHECK
# ===========================================================================
SUPPORT_MQTT=false                                    # Globales Support Flag
INITIALIZED_MQTT=false                      # Initialisierung war erfolgreich
ACTIVATED_MQTT=false                             # In Konfiguration aktiviert

# ===========================================================================
# check_dependencies_mqtt
# ---------------------------------------------------------------------------
# Funktion.: Prüfe alle Modul-Abhängigkeiten (Modul-Dateien, Ausgabe-Ordner, 
# .........  kritische und optionale Software für die Ausführung des Modul),
# .........  lädt nach erfolgreicher Prüfung die Sprachdatei für das Modul.
# Parameter: keine
# Rückgabe.: 0 = Verfügbar (Module nutzbar)
# .........  1 = Nicht verfügbar (Modul deaktiviert)
# Extras...: Setzt SUPPORT_MQTT=true bei erfolgreicher Prüfung
# ===========================================================================
check_dependencies_mqtt() {
    log_debug "$MSG_DEBUG_MQTT_CHECK_START"

    #-- Alle Modul Abhängigkeiten prüfen -------------------------------------
    check_module_dependencies "$MODULE_NAME_MQTT" || return 1

    #-- Lade MQTT-Konfiguration aus INI -------------------------------------
    load_mqtt_config || return 1
    log_debug "$MSG_DEBUG_MQTT_CONFIG_LOADED: $MQTT_BROKER:$MQTT_PORT"

    #-- Setze Verfügbarkeit -------------------------------------------------
    SUPPORT_MQTT=true
    log_debug "$MSG_DEBUG_MQTT_CHECK_COMPLETE"
    
    #-- Abhängigkeiten erfüllt ----------------------------------------------
    log_info "$MSG_MQTT_SUPPORT_AVAILABLE"
    return 0
}

# ===========================================================================
# is_mqtt_ready
# ---------------------------------------------------------------------------
# Funktion.: Prüfe ob MQTT Modul supported wird, initialisiert wurde und in 
# .........  den Einstellungen aktviert wurde. Wenn true ist alles bereit 
# .........  ist für die Nutzung.
# Parameter: keine
# Rückgabe.: 0 = Bereit, 1 = Nicht bereit
# ===========================================================================
is_mqtt_ready() {
    #-- Prüfe Support (Abhängikeiten erfüllt) -------------------------------
    if [[ "$SUPPORT_MQTT" != "true" ]]; then
        log_debug "$MSG_DEBUG_MQTT_NOT_SUPPORTED"
        return 1
    fi
    
    #-- Prüfe Initialisierung (Konfiguration geladen) -----------------------
    if [[ "$INITIALIZED_MQTT" != "true" ]]; then
        log_debug "$MSG_DEBUG_MQTT_NOT_INITIALIZED"
        return 1
    fi
    
    #-- Prüfe Aktivierung (In Konfiguration aktiviert) ----------------------
    if [[ "$ACTIVATED_MQTT" != "true" ]]; then
        log_debug "$MSG_DEBUG_MQTT_NOT_ACTIVATED"
        return 1
    fi
    
    #-- Alles bereit --------------------------------------------------------
    log_debug "$MSG_DEBUG_MQTT_READY"
    return 0
}

# ===========================================================================
# PATH GETTER
# ===========================================================================

# ===========================================================================
# get_path_mqtt
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Ausgabepfad des Modul für die Verwendung in anderen
# .........  abhängigen Modulen
# Parameter: keine
# Rückgabe.: Vollständiger Pfad zum Modul Verzeichnis
# Hinweis: Ordner wird bereits in check_module_dependencies() erstellt
# ===========================================================================
get_path_mqtt() {
    #-- Bestimme Ausgabeordner des Moduls -----------------------------------
    local mqtt_dir="${OUTPUT_DIR}/${MODULE_NAME_MQTT}"

    #-- Debug Meldung und Rückgabe ------------------------------------------
    log_debug "$MSG_DEBUG_MQTT_PATH ${mqtt_dir}" 
    echo "${mqtt_dir}"
    return 0
}

# ===========================================================================
# MQTT API CONFIGURATION / INITIALIZATION
# ===========================================================================

# ===========================================================================
# _mqtt_get_defaults
# ---------------------------------------------------------------------------
# Funktion.: Liefert MQTT-Defaults (Wiederverwendbar, verhindert Code-Duplikation)
# Parameter: $1 = Key (broker, port, user, password, topic_prefix, client_id, qos, retain, enabled)
# Rückgabe.: Default-Wert für den Key
# Hinweis..: Private Funktion (Präfix _)
# ===========================================================================
_mqtt_get_defaults() {
    local key="$1"
    
    case "$key" in
        broker) echo "192.168.20.13" ;;
        port) echo "1883" ;;
        user) echo "" ;;
        password) echo "" ;;
        topic_prefix) echo "homeassistant/sensor/disk2iso" ;;
        client_id) echo "disk2iso-${HOSTNAME}" ;;
        qos) echo "0" ;;
        retain) echo "true" ;;
        enabled) echo "false" ;;
        *) echo "" ;;
    esac
}

# ===========================================================================
# load_mqtt_config
# ---------------------------------------------------------------------------
# Funktion.: Lade MQTT-Konfiguration aus libmqtt.ini [api] Sektion
# .........  und setze Defaults falls INI-Werte fehlen
# Parameter: keine
# Rückgabe.: 0 = Erfolgreich geladen
# Setzt....: MQTT_BROKER, MQTT_PORT, MQTT_USER, MQTT_PASSWORD,
# .........  MQTT_TOPIC_PREFIX, MQTT_CLIENT_ID, MQTT_QOS, MQTT_RETAIN
# Nutzt....: get_ini_value() aus libconfig.sh
# Hinweis..: Wird von check_dependencies_mqtt() aufgerufen
# .........  MQTT_ENABLED wird aus disk2iso.conf gelesen (bleibt unverändert)
# ===========================================================================
load_mqtt_config() {
    #-- Lokale Variablen ----------------------------------------------------
    local broker port user password topic_prefix client_id qos retain

    #-- Ermittle Pfad zur Modul INI -----------------------------------------
    local ini_file=$(get_module_ini_path "mqtt")
    
    #-- Lese MQTT-Konfiguration aus INI (falls existiert) -------------------
    if [[ -f "$ini_file" ]]; then
        broker=$(get_ini_value "$ini_file" "api" "broker")
        port=$(get_ini_value "$ini_file" "api" "port")
        user=$(get_ini_value "$ini_file" "api" "user")
        password=$(get_ini_value "$ini_file" "api" "password")
        topic_prefix=$(get_ini_value "$ini_file" "api" "topic_prefix")
        client_id=$(get_ini_value "$ini_file" "api" "client_id")
        qos=$(get_ini_value "$ini_file" "api" "qos")
        retain=$(get_ini_value "$ini_file" "api" "retain")
    else
        log_warning "$MSG_MQTT_INI_NOT_FOUND: $ini_file"
    fi
    
    #-- Setze Variablen mit Defaults (INI-Werte überschreiben Defaults) -----
    #-- Prüfe zuerst ob Wert bereits aus disk2iso.conf gesetzt wurde --------
    #-- Nutzt _mqtt_get_defaults() für konsistente Defaults -----------------
    MQTT_BROKER="${MQTT_BROKER:-${broker:-$(_mqtt_get_defaults broker)}}"
    MQTT_PORT="${MQTT_PORT:-${port:-$(_mqtt_get_defaults port)}}"
    MQTT_USER="${MQTT_USER:-${user:-$(_mqtt_get_defaults user)}}"
    MQTT_PASSWORD="${MQTT_PASSWORD:-${password:-$(_mqtt_get_defaults password)}}"
    MQTT_TOPIC_PREFIX="${MQTT_TOPIC_PREFIX:-${topic_prefix:-$(_mqtt_get_defaults topic_prefix)}}"
    MQTT_CLIENT_ID="${MQTT_CLIENT_ID:-${client_id:-$(_mqtt_get_defaults client_id)}}"
    MQTT_QOS="${MQTT_QOS:-${qos:-$(_mqtt_get_defaults qos)}}"
    MQTT_RETAIN="${MQTT_RETAIN:-${retain:-$(_mqtt_get_defaults retain)}}"
    
    #-- Setze Initialisierungs-Flag -----------------------------------------
    INITIALIZED_MQTT=true

    #-- Setze Aktiviert-Flag basierend auf MQTT_ENABLED aus disk2iso.conf ---
    ACTIVATED_MQTT="${MQTT_ENABLED:-false}"
    
    #-- Log und Rückgabe ----------------------------------------------------
    log_info "$MSG_MQTT_CONFIG_LOADED $MQTT_BROKER:$MQTT_PORT"
    log_info "$MSG_DEBUG_MQTT_ACTIVATED $ACTIVATED_MQTT"
    return 0
}

# ===========================================================================
# MQTT PUBLISHING HELPERS
# ===========================================================================
# Aktuelle Werte (für Delta-Publishing - Vermeidet doppelte Updates)
MQTT_LAST_STATE=""                                # Letzter gesendeter Status
MQTT_LAST_PROGRESS=0              # Letzter gesendeter Fortschritt in Prozent
MQTT_LAST_UPDATE=0               # Timestamp des letzten Fortschritts-Updates

# ===========================================================================
# mqtt_publish
# ---------------------------------------------------------------------------
# Funktion.: Basis-MQTT-Publish, wird von anderen MQTT-Funktionen genutzt um
# .........  Nachrichten zu senden.
# Beispiel.: mqtt_publish "state" "copying"
# Parameter: $1 = Topic (relativ zu PREFIX)
# .........  $2 = Payload
# Rückgabe.: 0 = Erfolgreich, 1 = Fehler
# ===========================================================================
mqtt_publish() {
    #-- Prüfe ob MQTT bereit ist --------------------------------------------
    if ! is_mqtt_ready; then return 1; fi
    
    #-- Parse Parameter -----------------------------------------------------
    local topic="${MQTT_TOPIC_PREFIX}/$1"
    local payload="$2"
    local retain_flag=""
    
    #-- Retain-Flag setzen --------------------------------------------------
    if [[ "${MQTT_RETAIN:-true}" == "true" ]]; then
        retain_flag="-r"
    fi
    
    #-- Publish mit oder ohne Authentifizierung -----------------------------
    if [[ -n "${MQTT_USER:-}" ]] && [[ -n "${MQTT_PASSWORD:-}" ]]; then
        #-- Mit Authentifizierung -------------------------------------------
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
        #-- Ohne Authentifizierung ------------------------------------------
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

    #-- Auswertung des Exit-Codes -------------------------------------------    
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "$MSG_MQTT_PUBLISH_FAILED ${topic}: ${payload} (Exit: $exit_code)"
        return 1
    fi
    
    return 0
}

# ===========================================================================
# _mqtt_test_broker
# ---------------------------------------------------------------------------
# Funktion.: Helper-Funktion zum Testen der Broker-Erreichbarkeit
# .........  Wiederverwendbar für mqtt_init_connection() und mqtt_test_connection()
# Parameter: $1 = broker (z.B. "192.168.20.10")
# .........  $2 = port (z.B. 1883)
# .........  $3 = user (optional)
# .........  $4 = password (optional)
# Rückgabe.: 0 = Verbindung erfolgreich, 1 = Fehler
# Hinweis..: Keine Logging-Ausgaben (reine Test-Funktion)
# ===========================================================================
_mqtt_test_broker() {
    local broker="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    
    #-- Test-Nachricht vorbereiten ------------------------------------------
    local test_topic="disk2iso/test"
    local test_message='{"test":true,"timestamp":"'$(date -Iseconds)'"}'
    
    #-- Baue mosquitto_pub Befehl ------------------------------------------
    local cmd=(mosquitto_pub -h "${broker}" -p "${port}" -t "${test_topic}" -m "${test_message}" -q 0)
    
    #-- Auth-Parameter hinzufügen wenn vorhanden ---------------------------
    if [[ -n "${user}" ]]; then
        cmd+=(-u "${user}")
        [[ -n "${password}" ]] && cmd+=(-P "${password}")
    fi
    
    #-- Führe Test mit Timeout durch (5 Sekunden) --------------------------
    timeout 5 "${cmd[@]}" 2>/dev/null
    return $?
}

# ===========================================================================
# mqtt_init_connection
# ---------------------------------------------------------------------------
# Funktion.: Initialisieren der MQTT-Verbindung, inklusive einem Test der 
# .........  Broker-Erreichbarkeit
# Parameter: keine
# Rückgabe.: 0 = OK, 1 = MQTT nicht verfügbar/deaktiviert
# Extras...: Sendet Initial Availability und Idle-State
# ===========================================================================
mqtt_init_connection() {
    #-- Prüfe ob MQTT bereit ist --------------------------------------------
    if ! is_mqtt_ready; then return 1; fi
    
    #-- Prüfe Broker-Erreichbarkeit mit Helper-Funktion --------------------
    if ! _mqtt_test_broker "$MQTT_BROKER" "$MQTT_PORT" "$MQTT_USER" "$MQTT_PASSWORD"; then
        log_error "$MSG_MQTT_ERROR_BROKER_UNREACHABLE $MQTT_BROKER:$MQTT_PORT"
        return 1
    fi
    log_info "$MSG_MQTT_INITIALIZED $MQTT_BROKER:$MQTT_PORT"
    
    #-- Sende Initial "Verfügbar" -------------------------------------------
    mqtt_publish_availability "online"
    
    #-- Sende "Stauts: Warten" ----------------------------------------------
    mqtt_publish_state "idle"
    
    return 0
}

# ===========================================================================
# mqtt_publish_availability
# ---------------------------------------------------------------------------
# Funktion: Sende Verfügbarkeits-Status
# Parameter: $1 = "online" oder "offline"
# Rückgabe.: 0 = Erfolgreich, 1 = Fehler
# Topic: {prefix}/availability
# ===========================================================================
mqtt_publish_availability() {
    #-- Prüfe ob MQTT bereit ist --------------------------------------------
    if ! is_mqtt_ready; then return 1; fi
    
    #-- Parse Parameter -----------------------------------------------------
    local status="$1"
    
    #-- Meldung senden ------------------------------------------------------
    mqtt_publish "availability" "${status}"
    
    #-- Auswertung und Log --------------------------------------------------
    if [[ "$status" == "online" ]]; then
        log_info "$MSG_MQTT_ONLINE"
    else
        log_info "$MSG_MQTT_OFFLINE"
    fi
    
    return 0
}

# ===========================================================================
# mqtt_publish_from_api
# ---------------------------------------------------------------------------
# Funktion.: Observer-Callback für API-Änderungen
# Parameter: $1 = Dateiname der geänderten JSON (z.B. "status.json")
# Rückgabe.: 0 = OK, 1 = MQTT nicht bereit
# Beschr...: Wird von libapi.sh::notify_api_update() aufgerufen
#            Liest JSON aus API und publisht via MQTT
# ===========================================================================
mqtt_publish_from_api() {
    #-- Prüfe ob MQTT bereit ist --------------------------------------------
    if ! is_mqtt_ready; then return 1; fi
    
    #-- Parse Parameter -----------------------------------------------------
    local changed_file="$1"
    
    #-- Handle die verschiedenen JSON-Dateien -------------------------------
    case "$changed_file" in
        "status.json"|"attributes.json")
            mqtt_publish_state_from_api
            ;;
        "progress.json")
            mqtt_publish_progress_from_api
            ;;
        "history.json")
            # History wird nicht via MQTT publiziert
            return 0
            ;;
        *)
            log_debug "$MSG_DEBUG_MQTT_UNKNOWN_FILE ${changed_file}"
            return 0
            ;;
    esac
    
    return 0
}

# ===========================================================================
# mqtt_publish_state_from_api
# ---------------------------------------------------------------------------
# Funktion.: Publishe State und Attributes aus API-JSON-Dateien
# Parameter: keine
# Rückgabe.: 0 = OK, 1 = Fehler
# Beschr...: Liest status.json und attributes.json, publisht via MQTT
# ===========================================================================
mqtt_publish_state_from_api() {
    #-- Lese JSON aus API ---------------------------------------------------
    local state_json=$(api_read_json "status.json") || {
        log_warning "$MSG_WARN_MQTT_STATUS_UNREADABLE"
        return 1
    }
    local attr_json=$(api_read_json "attributes.json") || {
        log_warning "$MSG_WARN_MQTT_ATTRIBUTES_UNREADABLE"
        return 1
    }
    
    #-- Extrahiere Status für Tracking (verhindert doppelte Updates) --------
    local current_state=$(echo "$state_json" | grep -oP '"status"\s*:\s*"\K[^"]+' 2>/dev/null || echo "unknown")
    
    #-- Vermeide doppelte Updates -------------------------------------------
    if [[ "$current_state" == "$MQTT_LAST_STATE" ]] && [[ "$current_state" != "copying" ]]; then
        return 0
    fi
    
    #-- Tracking-Variablen bei State-Wechsel zurücksetzen -------------------
    if [[ "$current_state" == "copying" ]] && [[ "$MQTT_LAST_STATE" != "copying" ]]; then
        MQTT_LAST_PROGRESS=0
        MQTT_LAST_UPDATE=0
    fi
    if [[ "$current_state" == "idle" ]] || [[ "$current_state" == "waiting" ]]; then
        MQTT_LAST_PROGRESS=0
        MQTT_LAST_UPDATE=0
    fi
    MQTT_LAST_STATE="$current_state"
    
    #-- MQTT Publishing -----------------------------------------------------
    mqtt_publish "state" "${state_json}"
    mqtt_publish "attributes" "${attr_json}"
    
    #-- Progress auf 0 bei idle/waiting -------------------------------------
    if [[ "$current_state" == "idle" ]] || [[ "$current_state" == "waiting" ]]; then
        mqtt_publish "progress" "0"
    fi

    #-- Log und Rückgabe ----------------------------------------------------
    log_debug "$MSG_DEBUG_MQTT_STATE_PUBLISHED '${current_state}'"
    return 0
}

# ===========================================================================
# mqtt_publish_progress_from_api
# ---------------------------------------------------------------------------
# Funktion.: Publishe Progress aus API-JSON-Datei
# Parameter: keine
# Rückgabe.: 0 = OK, 1 = Fehler
# Beschr...: Liest progress.json und attributes.json, publisht via MQTT
#            Wendet Rate-Limiting und Delta-Check an
# ===========================================================================
mqtt_publish_progress_from_api() {
    #-- Lese JSON aus API ---------------------------------------------------
    local progress_json=$(api_read_json "progress.json") || {
        log_warning "$MSG_WARN_MQTT_PROGRESS_UNREADABLE"
        return 1
    }    
    local attr_json=$(api_read_json "attributes.json") || {
        log_warning "$MSG_WARN_MQTT_ATTRIBUTES_UNREADABLE"
        return 1
    }
    
    #-- Extrahiere Prozent-Wert für Rate-Limiting ---------------------------
    local percent=$(echo "$progress_json" | grep -oP '"percent"\s*:\s*\K[0-9]+' 2>/dev/null || echo "0")
    
    #-- Rate-Limiting: Nur alle 10 Sekunden updaten -------------------------
    local current_time=$(date +%s)
    local time_diff=$((current_time - MQTT_LAST_UPDATE))
    
    if [[ $time_diff -lt 10 ]] && [[ $percent -ne 100 ]]; then
        return 0
    fi
    
    #-- Delta-Check: Nur bei Änderung > 1% publishen ------------------------
    local percent_diff=$((percent - MQTT_LAST_PROGRESS))
    if [[ $percent_diff -lt 1 ]] && [[ $percent -ne 100 ]] && [[ $percent -ge $MQTT_LAST_PROGRESS ]]; then
        return 0
    fi
    
    MQTT_LAST_PROGRESS=$percent
    MQTT_LAST_UPDATE=$current_time
    
    #-- MQTT Publishing -----------------------------------------------------
    mqtt_publish "progress" "${percent}"
    mqtt_publish "attributes" "${attr_json}"
    
    #-- Log und Rückgabe ----------------------------------------------------
    log_debug "$MSG_DEBUG_MQTT_PROGRESS_PUBLISHED ${percent}%"
    return 0
}

# ===========================================================================
# mqtt_publish_state
# ---------------------------------------------------------------------------
# Funktion.: Sende Status-Update
# Parameter: keine
# Rückgabe.: 0 = OK, 1 = Fehler
# Hinweis..: Diese Funktion ist ein Wrapper für Abwärtskompatibilität.
# .........  JSON-Daten werden aus API gelesen, Parameter werden ignoriert.
# .........  Nutze stattdessen: api_update_status() -> notify_api_update() -> mqtt_publish_from_api()
# ===========================================================================
mqtt_publish_state() {
    #-- Funktion liest direkt aus API ---------------------------------------
    mqtt_publish_state_from_api
    return $?
}

# ===========================================================================
# mqtt_publish_progress
# ---------------------------------------------------------------------------
# Funktion: Sende Fortschritts-Update
# Parameter: keine
# Rückgabe.: 0 = OK, 1 = Fehler
# Hinweis..: Diese Funktion ist ein Wrapper für Abwärtskompatibilität.
# .........  JSON-Daten werden aus API gelesen, Parameter werden ignoriert.
# .........  Nutze stattdessen: api_update_status() -> notify_api_update() -> mqtt_publish_from_api()
# ===========================================================================
mqtt_publish_progress() {
    #-- Funktion liest direkt aus API ---------------------------------------
    mqtt_publish_progress_from_api
    return $?
}

# ===========================================================================
# mqtt_publish_complete
# ---------------------------------------------------------------------------
# Funktion.: Sende Abschluss-Meldung
# Parameter: keine
# Rückgabe.: 0 = OK, 1 = Fehler
# Hinweis..: Status muss bereits via api_update_status("completed") gesetzt sein
# .........  Diese Funktion triggert nur das MQTT-Publishing
# ===========================================================================
mqtt_publish_complete() {
    #-- Funktion liest direkt aus API ---------------------------------------
    mqtt_publish_state_from_api
    mqtt_publish_progress_from_api    
    return $?
}

# ===========================================================================
# mqtt_publish_error
# ---------------------------------------------------------------------------
# Funktion.: Sende Fehler-Meldung
# Parameter: keine
# Rückgabe.: 0 = OK, 1 = Fehler
# Hinweis..: Status muss bereits via api_update_status("error", ..., ..., "$error_msg") gesetzt sein
# .........  Diese Funktion triggert nur das MQTT-Publishing
# ===========================================================================
mqtt_publish_error() {
    #-- Funktion liest direkt aus API ---------------------------------------
    mqtt_publish_state_from_api    
    return $?
}

# ===========================================================================
# mqtt_cleanup
# ---------------------------------------------------------------------------
# Funktion: MQTT Cleanup beim Beenden, Setzt Availability auf offline
# Parameter: keine
# Rückgabe.: 0 = OK, 1 = Fehler
# ===========================================================================
mqtt_cleanup() {
    mqtt_publish_availability "offline"
    return $?
}

# ============================================================================
# CLI INTERFACE - Web-API Integration
# ============================================================================

# ===========================================================================
# mqtt_export_config_json
# ---------------------------------------------------------------------------
# Funktion.: Exportiert aktuelle MQTT-Konfiguration als JSON für Web-UI
# Parameter: keine
# Rückgabe.: 0 = Erfolgreich
# Output...: JSON zu stdout
# Beispiel.: ./lib/libmqtt.sh export-config
# ===========================================================================
mqtt_export_config_json() {
    #-- Ermittle Pfad zur Config --------------------------------------------
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    local ini_file="${INSTALL_DIR:-/opt/disk2iso}/conf/libmqtt.ini"
    
    #-- Defaults setzen (nutzt _mqtt_get_defaults() für Konsistenz) ---------
    local mqtt_enabled=$(_mqtt_get_defaults enabled)
    local mqtt_broker=$(_mqtt_get_defaults broker)
    local mqtt_port=$(_mqtt_get_defaults port)
    local mqtt_user=$(_mqtt_get_defaults user)
    local mqtt_password=$(_mqtt_get_defaults password)
    local topic_prefix=$(_mqtt_get_defaults topic_prefix)
    local client_id=$(_mqtt_get_defaults client_id)
    local qos=$(_mqtt_get_defaults qos)
    local retain=$(_mqtt_get_defaults retain)
    
    #-- Source libconfig.sh um get_ini_value() zu nutzen --------------------
    local lib_dir="${INSTALL_DIR:-/opt/disk2iso}/lib"
    if [[ -f "$lib_dir/libconfig.sh" ]]; then
        source "$lib_dir/libconfig.sh"
    fi
    
    #-- Lese Werte aus disk2iso.conf (überschreibt Defaults) ---------------
    if [[ -f "$config_file" ]]; then
        while IFS='=' read -r key value; do
            #-- Entferne Whitespace und Kommentare --------------------------
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
            
            case "$key" in
                MQTT_ENABLED) mqtt_enabled="$value" ;;
                MQTT_BROKER) mqtt_broker="$value" ;;
                MQTT_PORT) mqtt_port="$value" ;;
                MQTT_USER) mqtt_user="$value" ;;
                MQTT_PASSWORD) mqtt_password="$value" ;;
            esac
        done < "$config_file"
    fi
    
    #-- Lese erweiterte Werte aus libmqtt.ini (nutzt get_ini_value) --------
    if [[ -f "$ini_file" ]]; then
        local ini_topic_prefix=$(get_ini_value "$ini_file" "api" "topic_prefix")
        local ini_client_id=$(get_ini_value "$ini_file" "api" "client_id")
        local ini_qos=$(get_ini_value "$ini_file" "api" "qos")
        local ini_retain=$(get_ini_value "$ini_file" "api" "retain")
        
        [[ -n "$ini_topic_prefix" ]] && topic_prefix="$ini_topic_prefix"
        [[ -n "$ini_client_id" ]] && client_id="$ini_client_id"
        [[ -n "$ini_qos" ]] && qos="$ini_qos"
        [[ -n "$ini_retain" ]] && retain="$ini_retain"
    fi
    
    #-- Baue JSON-Output ----------------------------------------------------
    cat <<EOF
{
  "mqtt_enabled": $mqtt_enabled,
  "mqtt_broker": "$mqtt_broker",
  "mqtt_port": $mqtt_port,
  "mqtt_user": "$mqtt_user",
  "mqtt_password": "$mqtt_password",
  "topic_prefix": "$topic_prefix",
  "client_id": "$client_id",
  "qos": $qos,
  "retain": $retain
}
EOF
    return 0
}

# ===========================================================================
# mqtt_update_config
# ---------------------------------------------------------------------------
# Funktion.: Nimmt JSON entgegen, validiert Werte, schreibt Config
# Parameter: JSON via stdin
# Rückgabe.: 0 = Erfolgreich, 1 = Fehler
# Output...: JSON-Response zu stdout
# Beispiel.: echo '{"mqtt_enabled": true}' | ./lib/libmqtt.sh update-config
# ===========================================================================
mqtt_update_config() {
    #-- Lese JSON von stdin -------------------------------------------------
    local json_input
    json_input=$(cat)
    
    if [[ -z "$json_input" ]]; then
        echo '{"success": false, "error": "Keine Daten empfangen"}'
        return 1
    fi
    
    #-- Parse JSON-Werte mit jq (robuster als grep/awk) --------------------
    local mqtt_enabled=$(echo "$json_input" | jq -r '.mqtt_enabled // ""' 2>/dev/null)
    local mqtt_broker=$(echo "$json_input" | jq -r '.mqtt_broker // ""' 2>/dev/null)
    local mqtt_port=$(echo "$json_input" | jq -r '.mqtt_port // ""' 2>/dev/null)
    local mqtt_user=$(echo "$json_input" | jq -r '.mqtt_user // ""' 2>/dev/null)
    local mqtt_password=$(echo "$json_input" | jq -r '.mqtt_password // ""' 2>/dev/null)
    
    #-- Source libconfig.sh um Setter-Funktionen zu nutzen ------------------
    local lib_dir="${INSTALL_DIR:-/opt/disk2iso}/lib"
    if [[ -f "$lib_dir/libconfig.sh" ]]; then
        source "$lib_dir/libconfig.sh"
    else
        echo '{"success": false, "error": "libconfig.sh nicht gefunden"}'
        return 1
    fi
    
    #-- Validierung und Schreiben -------------------------------------------
    local updated_keys=()
    local errors=()
    
    #-- MQTT_ENABLED --------------------------------------------------------
    if [[ -n "$mqtt_enabled" ]]; then
        if set_mqtt_enabled "$mqtt_enabled" 2>/dev/null; then
            updated_keys+=("MQTT_ENABLED")
        else
            errors+=("mqtt_enabled: Ungültiger Wert")
        fi
    fi
    
    #-- MQTT_BROKER ---------------------------------------------------------
    if [[ -n "$mqtt_broker" ]]; then
        if set_mqtt_broker "$mqtt_broker" 2>/dev/null; then
            updated_keys+=("MQTT_BROKER")
        else
            errors+=("mqtt_broker: Schreibfehler")
        fi
    fi
    
    #-- MQTT_PORT -----------------------------------------------------------
    if [[ -n "$mqtt_port" ]]; then
        if set_mqtt_port "$mqtt_port" 2>/dev/null; then
            updated_keys+=("MQTT_PORT")
        else
            errors+=("mqtt_port: Ungültiger Port")
        fi
    fi
    
    #-- MQTT_USER -----------------------------------------------------------
    if [[ -n "$mqtt_user" ]] || echo "$json_input" | grep -q '"mqtt_user"'; then
        if set_mqtt_user "$mqtt_user" 2>/dev/null; then
            updated_keys+=("MQTT_USER")
        else
            errors+=("mqtt_user: Schreibfehler")
        fi
    fi
    
    #-- MQTT_PASSWORD -------------------------------------------------------
    if [[ -n "$mqtt_password" ]] || echo "$json_input" | grep -q '"mqtt_password"'; then
        if set_mqtt_password "$mqtt_password" 2>/dev/null; then
            updated_keys+=("MQTT_PASSWORD")
        else
            errors+=("mqtt_password: Schreibfehler")
        fi
    fi
    
    #-- Baue Response -------------------------------------------------------
    if [[ ${#errors[@]} -eq 0 ]]; then
        local keys_json=$(printf '"%s",' "${updated_keys[@]}")
        keys_json="[${keys_json%,}]"
        echo "{\"success\": true, \"updated_keys\": $keys_json, \"restart_required\": true}"
        return 0
    else
        local errors_json=$(printf '"%s",' "${errors[@]}")
        errors_json="[${errors_json%,}]"
        echo "{\"success\": false, \"errors\": $errors_json}"
        return 1
    fi
}

# ===========================================================================
# mqtt_test_connection
# ---------------------------------------------------------------------------
# Funktion.: CLI-Wrapper für Verbindungstest (nutzt Helper-Funktion)
# Parameter: JSON via stdin
# Rückgabe.: 0 = Erfolgreich, 1 = Fehler
# Output...: JSON-Response zu stdout
# Beispiel.: echo '{"broker": "192.168.20.10"}' | ./lib/libmqtt.sh test-connection
# ===========================================================================
mqtt_test_connection() {
    #-- Lese JSON von stdin -------------------------------------------------
    local json_input
    json_input=$(cat)
    
    if [[ -z "$json_input" ]]; then
        echo '{"success": false, "error": "Keine Daten empfangen"}'
        return 1
    fi
    
    #-- Parse JSON-Werte mit jq (robuster als grep/awk) --------------------
    local broker=$(echo "$json_input" | jq -r '.broker // ""' 2>/dev/null)
    local port=$(echo "$json_input" | jq -r '.port // 1883' 2>/dev/null)
    local user=$(echo "$json_input" | jq -r '.user // ""' 2>/dev/null)
    local password=$(echo "$json_input" | jq -r '.password // ""' 2>/dev/null)
    
    #-- Validierung ---------------------------------------------------------
    if [[ -z "$broker" ]]; then
        echo '{"success": false, "error": "Broker-Adresse fehlt"}'
        return 1
    fi
    
    #-- Nutze Helper-Funktion für Test --------------------------------------
    if _mqtt_test_broker "$broker" "$port" "$user" "$password"; then
        echo '{"success": true, "message": "Verbindung erfolgreich"}'
        return 0
    else
        echo '{"success": false, "error": "Verbindung fehlgeschlagen"}'
        return 1
    fi
}

# ============================================================================
# CLI ENTRY POINT
# ============================================================================

# ===========================================================================
# main
# ---------------------------------------------------------------------------
# Funktion.: Haupteinstiegspunkt für CLI-Aufrufe
# Parameter: $1 = Befehl (export-config, update-config, test-connection)
# Rückgabe.: Exit-Code der aufgerufenen Funktion
# Beispiel.: ./lib/libmqtt.sh export-config
# ===========================================================================
main() {
    local command="$1"
    
    case "$command" in
        "export-config")
            mqtt_export_config_json
            ;;
        "update-config")
            mqtt_update_config
            ;;
        "test-connection")
            mqtt_test_connection
            ;;
        *)
            echo '{"success": false, "error": "Ungültiger Befehl. Verfügbar: export-config, update-config, test-connection"}' >&2
            exit 1
            ;;
    esac
}

# Wenn direkt aufgerufen (nicht gesourced), führe main() aus
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# ============================================================================
# ENDE DER MQTT LIBRARY
# ============================================================================
