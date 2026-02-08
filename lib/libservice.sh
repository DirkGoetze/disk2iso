#!/bin/bash
# ===========================================================================
# Service Management Library
# ===========================================================================
# Filepath: lib/libservice.sh
#
# Beschreibung:
#   Service-Status und -Steuerung für systemd Services
#   - service_collect_status_info() - Sammelt Service-Status
#   - service_get_status_info() - Liest Service-Status aus JSON
#   - Unterstützt: disk2iso, disk2iso-web, disk2iso-volatile-updater
#
# ---------------------------------------------------------------------------
# Dependencies: liblogging, libsettings
# ---------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.3.0
# Last Change: 2026-02-07
# ===========================================================================

# ===========================================================================
# service_check_dependencies
# ---------------------------------------------------------------------------
# Funktion.: Prüfe Dependencies für Service-Management
# Parameter: keine
# Rückgabe.: 0 = Verfügbar, 1 = Nicht verfügbar
# ===========================================================================
service_check_dependencies() {
    local missing=()
    
    command -v systemctl >/dev/null 2>&1 || missing+=("systemctl")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Kritische Tools für Service-Management fehlen: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# ===========================================================================
# service_get_status
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Status eines systemd Service
# Parameter: $1 = Service-Name (ohne .service)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Ausgabe..: JSON mit status (active/inactive/error/not_installed) und running (true/false)
# ===========================================================================
service_get_status() {
    local service_name="$1"
    
    # Timestamp der Prüfung
    local timestamp=$(date -Iseconds)
    
    # Prüfe ob Service existiert
    if ! systemctl list-unit-files "${service_name}.service" 2>/dev/null | grep -q "${service_name}.service"; then
        echo "{\"status\":\"not_installed\",\"running\":false,\"timestamp\":\"${timestamp}\"}"
        return 0
    fi
    
    # Prüfe Service-Status
    local status_text=$(systemctl is-active "${service_name}" 2>/dev/null)
    local status="inactive"
    local running=false
    
    case "$status_text" in
        active)
            status="active"
            running=true
            ;;
        inactive)
            status="inactive"
            running=false
            ;;
        failed)
            status="error"
            running=false
            ;;
        *)
            status="inactive"
            running=false
            ;;
    esac
    
    # Timestamp der Prüfung hinzufügen
    local timestamp=$(date -Iseconds)
    
    echo "{\"status\":\"${status}\",\"running\":${running},\"timestamp\":\"${timestamp}\"}"
}

# ===========================================================================
# service_collect_status_info
# ---------------------------------------------------------------------------
# Funktion.: Sammle Service-Status und schreibe in service_status.json
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: FLÜCHTIG - zyklisch ausführen (z.B. alle 10s)
# Schreibt.: api/service_status.json
# ===========================================================================
service_collect_status_info() {
    local api_dir=$(folders_get_api_dir) || return 1
    local json_file="${api_dir}/service_status.json"
    
    # Sammle Status aller Services
    local disk2iso_status=$(service_get_status "disk2iso")
    local webui_status=$(service_get_status "disk2iso-web")
    local updater_status=$(service_get_status "disk2iso-volatile-updater")
    
    # Erstelle JSON
    local json="{
  \"disk2iso\": ${disk2iso_status},
  \"disk2iso-web\": ${webui_status},
  \"disk2iso-volatile-updater\": ${updater_status},
  \"timestamp\": \"$(date -Iseconds)\"
}"
    
    echo "$json" > "$json_file"
}

# ===========================================================================
# service_get_status_info
# ---------------------------------------------------------------------------
# Funktion.: Lese Service-Status aus JSON
# Parameter: $1 = Service-Name (optional, ohne gibt alle zurück)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Ausgabe..: JSON-String (stdout)
# ===========================================================================
service_get_status_info() {
    local service_name="${1:-}"
    local api_dir=$(folders_get_api_dir) || return 1
    local json_file="${api_dir}/service_status.json"
    
    # Fallback: Sammle Daten wenn JSON nicht existiert
    if [[ ! -f "$json_file" ]]; then
        service_collect_status_info || return 1
    fi
    
    if [[ -n "$service_name" ]]; then
        # Extrahiere spezifischen Service (rudimentäres JSON-Parsing)
        local service_json=$(grep -A 2 "\"${service_name}\":" "$json_file" | tail -2 | tr -d ' \n')
        echo "{${service_json}}"
    else
        # Gib alle Services zurück
        cat "$json_file"
    fi
}

# ===========================================================================
# service_restart
# ---------------------------------------------------------------------------
# Funktion.: Starte einen Service neu
# Parameter: $1 = Service-Name (ohne .service)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
service_restart() {
    local service_name="$1"
    
    if systemctl restart "${service_name}.service" 2>/dev/null; then
        log_info "Service ${service_name} erfolgreich neu gestartet"
        return 0
    else
        log_error "Fehler beim Neustart von Service ${service_name}"
        return 1
    fi
}
