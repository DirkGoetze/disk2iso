#!/bin/bash
# =============================================================================
# Configuration Management Library
# =============================================================================
# Filepath: lib/libconfig.sh
#
# Beschreibung:
#   Standalone Config-Management ohne Dependencies für Web-API
#   - update_config_value() - Schreibe einzelnen Wert in config.sh
#   - get_all_config_values() - Lese alle Werte als JSON
#   - Kann ohne logging/folders verwendet werden
#
# -----------------------------------------------------------------------------
# Dependencies: Keine (nutzt nur awk, sed, grep - POSIX-Standard)
# -----------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.2.1
# Last Change: 2026-01-26 20:00
# =============================================================================

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

# Funktion: Prüfe Config-Modul Abhängigkeiten
# Rückgabe: 0 = OK (awk, sed, grep sind POSIX-Standard)
check_dependencies_config() {
    # Config-Modul nutzt POSIX-Standard-Tools
    # Diese sind auf jedem Linux-System verfügbar
    # Keine explizite Prüfung erforderlich
    return 0
}

# ============================================================================
# GLOBALE LAUFZEIT-VARIABLEN
# ============================================================================
# Diese Variablen werden zur Laufzeit gesetzt und sollten NICHT manuell
# in disk2iso.conf geändert werden.

OUTPUT_DIR=""      # Ausgabeordner für ISO-Dateien (wird per Parameter oder DEFAULT gesetzt)
disc_label=""      # Normalisierter Label-Name der Disc
iso_filename=""    # Vollständiger Pfad zur ISO-Datei
md5_filename=""    # Vollständiger Pfad zur MD5-Datei
log_filename=""    # Vollständiger Pfad zur Log-Datei
iso_basename=""    # Basis-Dateiname ohne Pfad (z.B. "dvd_video.iso")
temp_pathname=""   # Temp-Verzeichnis für aktuellen Kopiervorgang
disc_type=""       # "data" (vereinfacht)
disc_block_size="" # Block Size des Mediums (wird gecacht)
disc_volume_size="" # Volume Size des Mediums in Blöcken (wird gecacht)

# ============================================================================
# CONFIG MANAGEMENT - NEUE ARCHITEKTUR
# ============================================================================

# Globale Service-Restart-Flags
disk2iso_restart_required=false
disk2iso_web_restart_required=false

# Config-Metadaten: Key → Handler:RestartService
declare -A CONFIG_HANDLERS=(
    ["DEFAULT_OUTPUT_DIR"]="set_default_output_dir:disk2iso"
    ["MP3_QUALITY"]="set_mp3_quality:none"
    ["DDRESCUE_RETRIES"]="set_ddrescue_retries:none"
    ["USB_DRIVE_DETECTION_ATTEMPTS"]="set_usb_detection_attempts:none"
    ["USB_DRIVE_DETECTION_DELAY"]="set_usb_detection_delay:none"
    ["MQTT_ENABLED"]="set_mqtt_enabled:disk2iso"
    ["MQTT_BROKER"]="set_mqtt_broker:disk2iso"
    ["MQTT_PORT"]="set_mqtt_port:disk2iso"
    ["MQTT_USER"]="set_mqtt_user:disk2iso"
    ["MQTT_PASSWORD"]="set_mqtt_password:disk2iso"
    ["TMDB_API_KEY"]="set_tmdb_api_key:disk2iso-web"
)

# ============================================================================
# CONFIG SETTER FUNCTIONS
# ============================================================================

set_default_output_dir() {
    local value="$1"
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    if [[ ! -d "$value" ]]; then
        echo '{"success": false, "message": "Verzeichnis existiert nicht"}' >&2
        return 1
    fi
    if [[ ! -w "$value" ]]; then
        echo '{"success": false, "message": "Verzeichnis nicht beschreibbar"}' >&2
        return 1
    fi
    
    /usr/bin/sed -i "s|^DEFAULT_OUTPUT_DIR=.*|DEFAULT_OUTPUT_DIR=\"${value}\"|" "$config_file" 2>/dev/null
    return $?
}

set_mp3_quality() {
    local value="$1"
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    if ! [[ "$value" =~ ^[0-9]$ ]]; then
        echo '{"success": false, "message": "Ungültiger Wert (0-9 erlaubt)"}' >&2
        return 1
    fi
    
    /usr/bin/sed -i "s|^MP3_QUALITY=.*|MP3_QUALITY=${value}|" "$config_file" 2>/dev/null
    return $?
}

set_ddrescue_retries() {
    local value="$1"
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo '{"success": false, "message": "Ungültiger Wert (Zahl erwartet)"}' >&2
        return 1
    fi
    
    /usr/bin/sed -i "s|^DDRESCUE_RETRIES=.*|DDRESCUE_RETRIES=${value}|" "$config_file" 2>/dev/null
    return $?
}

set_usb_detection_attempts() {
    local value="$1"
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo '{"success": false, "message": "Ungültiger Wert (Zahl erwartet)"}' >&2
        return 1
    fi
    
    /usr/bin/sed -i "s|^USB_DRIVE_DETECTION_ATTEMPTS=.*|USB_DRIVE_DETECTION_ATTEMPTS=${value}|" "$config_file" 2>/dev/null
    return $?
}

set_usb_detection_delay() {
    local value="$1"
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo '{"success": false, "message": "Ungültiger Wert (Zahl erwartet)"}' >&2
        return 1
    fi
    
    /usr/bin/sed -i "s|^USB_DRIVE_DETECTION_DELAY=.*|USB_DRIVE_DETECTION_DELAY=${value}|" "$config_file" 2>/dev/null
    return $?
}

set_mqtt_enabled() {
    local value="$1"
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    if [[ "$value" != "true" && "$value" != "false" ]]; then
        echo '{"success": false, "message": "Ungültiger Wert (true/false)"}' >&2
        return 1
    fi
    
    /usr/bin/sed -i "s|^MQTT_ENABLED=.*|MQTT_ENABLED=${value}|" "$config_file" 2>/dev/null
    return $?
}

set_mqtt_broker() {
    local value="$1"
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    /usr/bin/sed -i "s|^MQTT_BROKER=.*|MQTT_BROKER=\"${value}\"|" "$config_file" 2>/dev/null
    return $?
}

set_mqtt_port() {
    local value="$1"
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
        echo '{"success": false, "message": "Ungültiger Port (1-65535)"}' >&2
        return 1
    fi
    
    /usr/bin/sed -i "s|^MQTT_PORT=.*|MQTT_PORT=${value}|" "$config_file" 2>/dev/null
    return $?
}

set_mqtt_user() {
    local value="$1"
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    /usr/bin/sed -i "s|^MQTT_USER=.*|MQTT_USER=\"${value}\"|" "$config_file" 2>/dev/null
    return $?
}

set_mqtt_password() {
    local value="$1"
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    /usr/bin/sed -i "s|^MQTT_PASSWORD=.*|MQTT_PASSWORD=\"${value}\"|" "$config_file" 2>/dev/null
    return $?
}

set_tmdb_api_key() {
    local value="$1"
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    /usr/bin/sed -i "s|^TMDB_API_KEY=.*|TMDB_API_KEY=\"${value}\"|" "$config_file" 2>/dev/null
    return $?
}

# ============================================================================
# CONFIG MANAGEMENT - MAIN FUNCTIONS
# ============================================================================

apply_config_changes() {
    local json_input="$1"
    
    if [[ -z "$json_input" ]]; then
        echo '{"success": false, "message": "Keine Änderungen übergeben"}'
        return 1
    fi
    
    # Setze Restart-Flags zurück
    disk2iso_restart_required=false
    disk2iso_web_restart_required=false
    
    local errors=()
    local processed=0
    
    # Iteriere über alle definierten Config-Handler
    for config_key in "${!CONFIG_HANDLERS[@]}"; do
        # Extrahiere Wert aus JSON (mit grep/awk da jq möglicherweise nicht verfügbar)
        local value=$(echo "$json_input" | /usr/bin/grep -o "\"${config_key}\"[[:space:]]*:[[:space:]]*[^,}]*" | /usr/bin/awk -F':' '{gsub(/^[ \t"]+|[ \t"]+$/, "", $2); print $2}')
        
        if [[ -n "$value" ]]; then
            # Parse Handler und Service
            local handler=$(echo "${CONFIG_HANDLERS[$config_key]}" | /usr/bin/cut -d: -f1)
            local restart_service=$(echo "${CONFIG_HANDLERS[$config_key]}" | /usr/bin/cut -d: -f2)
            
            # Rufe Setter auf
            if $handler "$value" 2>&1; then
                ((processed++))
                
                # Setze entsprechendes Restart-Flag
                case "$restart_service" in
                    disk2iso) disk2iso_restart_required=true ;;
                    disk2iso-web) disk2iso_web_restart_required=true ;;
                esac
            else
                errors+=("${config_key}: Setter fehlgeschlagen")
            fi
        fi
    done
    
    # Führe Service-Neustarts durch
    local restart_info=$(perform_service_restarts)
    
    # Erstelle Response
    if [ ${#errors[@]} -eq 0 ]; then
        echo "{\"success\": true, \"processed\": $processed, \"restart_info\": $restart_info}"
        return 0
    else
        local error_list=""
        for error in "${errors[@]}"; do
            error_list="${error_list}\"${error}\","
        done
        error_list="${error_list%,}"  # Entferne letztes Komma
        echo "{\"success\": false, \"processed\": $processed, \"errors\": [$error_list]}"
        return 1
    fi
}

perform_service_restarts() {
    local disk2iso_restarted=false
    local disk2iso_web_restarted=false
    local disk2iso_error=""
    local disk2iso_web_error=""
    
    # Starte disk2iso Service neu
    if [ "$disk2iso_restart_required" = true ]; then
        if /usr/bin/systemctl restart disk2iso 2>/dev/null; then
            disk2iso_restarted=true
        else
            disk2iso_error="Service-Neustart fehlgeschlagen"
        fi
    fi
    
    # Starte disk2iso-web Service neu
    if [ "$disk2iso_web_restart_required" = true ]; then
        if /usr/bin/systemctl restart disk2iso-web 2>/dev/null; then
            disk2iso_web_restarted=true
        else
            disk2iso_web_error="Service-Neustart fehlgeschlagen"
        fi
    fi
    
    # JSON-Response (kompakt)
    local response="{\"disk2iso_restarted\":$disk2iso_restarted,\"disk2iso_web_restarted\":$disk2iso_web_restarted"
    [[ -n "$disk2iso_error" ]] && response="${response},\"disk2iso_error\":\"$disk2iso_error\""
    [[ -n "$disk2iso_web_error" ]] && response="${response},\"disk2iso_web_error\":\"$disk2iso_web_error\""
    response="${response}}"
    
    echo "$response"
}

# ============================================================================
# SERVICE MANAGEMENT FUNKTIONEN
# ============================================================================

# Funktion: Startet einzelnen Service manuell neu
# Parameter: $1 = Service-Name ("disk2iso" oder "disk2iso-web")
# Rückgabe: JSON mit Success-Status
restart_service() {
    local service_name="$1"
    
    # Validierung: Nur erlaubte Services
    if [[ "$service_name" != "disk2iso" && "$service_name" != "disk2iso-web" ]]; then
        echo '{"success": false, "message": "Ungültiger Service-Name"}'
        return 1
    fi
    
    # Service neu starten
    if /usr/bin/systemctl restart "$service_name" 2>/dev/null; then
        echo "{\"success\": true, \"message\": \"Service ${service_name} wurde neu gestartet\"}"
        return 0
    else
        echo "{\"success\": false, \"message\": \"Neustart von ${service_name} fehlgeschlagen\"}"
        return 1
    fi
}

# ============================================================================
# CONFIG MANAGEMENT FUNKTIONEN (LEGACY - für Kompatibilität)
# ============================================================================

# Funktion: Aktualisiere einzelnen Config-Wert in config.sh
# Parameter: $1 = Key (z.B. "DEFAULT_OUTPUT_DIR")
#            $2 = Value (z.B. "/media/iso")
#            $3 = Quote-Mode ("quoted" oder "unquoted", default: auto-detect)
# Rückgabe: JSON mit {"success": true} oder {"success": false, "message": "..."}
update_config_value() {
    local key="$1"
    local value="$2"
    local quote_mode="${3:-auto}"
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    if [[ -z "$key" ]]; then
        echo '{"success": false, "message": "Key erforderlich"}'
        return 1
    fi
    
    if [[ ! -f "$config_file" ]]; then
        echo '{"success": false, "message": "config.sh nicht gefunden"}'
        return 1
    fi
    
    # Auto-detect quote mode basierend auf aktuellem Wert
    if [[ "$quote_mode" == "auto" ]]; then
        local current_line=$(/usr/bin/grep "^${key}=" "$config_file" | /usr/bin/head -1)
        if [[ "$current_line" =~ =\".*\" ]]; then
            quote_mode="quoted"
        else
            quote_mode="unquoted"
        fi
    fi
    
    # Erstelle neue Zeile
    local new_line
    if [[ "$quote_mode" == "quoted" ]]; then
        new_line="${key}=\"${value}\""
    else
        new_line="${key}=${value}"
    fi
    
    # Aktualisiere mit sed (in-place)
    if /usr/bin/sed -i "s|^${key}=.*|${new_line}|" "$config_file" 2>/dev/null; then
        echo '{"success": true}'
        return 0
    else
        echo '{"success": false, "message": "Schreibfehler"}'
        return 1
    fi
}

# Funktion: Lese alle Config-Werte als JSON
# Rückgabe: JSON mit allen Konfigurations-Werten
get_all_config_values() {
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    if [[ ! -f "$config_file" ]]; then
        echo '{"success": false, "message": "config.sh nicht gefunden"}'
        return 1
    fi
    
    # Extrahiere relevante Werte mit awk (entferne Kommentare)
    local values=$(/usr/bin/awk -F'=' '
        /^DEFAULT_OUTPUT_DIR=/ { 
            gsub(/#.*/, "", $2)
            gsub(/^[ \t"]+|[ \t"]+$/, "", $2)
            print "\"output_dir\": \"" $2 "\"," 
        }
        /^MP3_QUALITY=/ { 
            gsub(/#.*/, "", $2)
            gsub(/^[ \t]+|[ \t]+$/, "", $2)
            print "\"mp3_quality\": " $2 "," 
        }
        /^DDRESCUE_RETRIES=/ { 
            gsub(/#.*/, "", $2)
            gsub(/^[ \t]+|[ \t]+$/, "", $2)
            print "\"ddrescue_retries\": " $2 "," 
        }
        /^USB_DRIVE_DETECTION_ATTEMPTS=/ { 
            gsub(/#.*/, "", $2)
            gsub(/^[ \t]+|[ \t]+$/, "", $2)
            print "\"usb_detection_attempts\": " $2 "," 
        }
        /^USB_DRIVE_DETECTION_DELAY=/ { 
            gsub(/#.*/, "", $2)
            gsub(/^[ \t]+|[ \t]+$/, "", $2)
            print "\"usb_detection_delay\": " $2 "," 
        }
        /^MQTT_ENABLED=/ { 
            gsub(/#.*/, "", $2)
            gsub(/^[ \t]+|[ \t]+$/, "", $2)
            print "\"mqtt_enabled\": " ($2 == "true" ? "true" : "false") "," 
        }
        /^MQTT_BROKER=/ { 
            gsub(/#.*/, "", $2)
            gsub(/^[ \t"]+|[ \t"]+$/, "", $2)
            print "\"mqtt_broker\": \"" $2 "\"," 
        }
        /^MQTT_PORT=/ { 
            gsub(/#.*/, "", $2)
            gsub(/^[ \t]+|[ \t]+$/, "", $2)
            print "\"mqtt_port\": " $2 "," 
        }
        /^MQTT_USER=/ { 
            gsub(/#.*/, "", $2)
            gsub(/^[ \t"]+|[ \t"]+$/, "", $2)
            print "\"mqtt_user\": \"" $2 "\"," 
        }
        /^MQTT_PASSWORD=/ { 
            gsub(/#.*/, "", $2)
            gsub(/^[ \t"]+|[ \t"]+$/, "", $2)
            print "\"mqtt_password\": \"" $2 "\"," 
        }
        /^TMDB_API_KEY=/ { 
            gsub(/#.*/, "", $2)
            gsub(/^[ \t"]+|[ \t"]+$/, "", $2)
            print "\"tmdb_api_key\": \"" $2 "\"," 
        }
    ' "$config_file")
    
    # Entferne letztes Komma
    local output=$(echo "$values" | /usr/bin/sed '$ s/,$//')
    
    # Ausgabe nur zu stdout (kein logging)
    echo "{\"success\": true, ${output}}"
    return 0
}

# ============================================================================
# HIGH-LEVEL CONFIG UPDATE FUNKTIONEN
# ============================================================================

# Funktion: Speichere komplette Konfiguration und starte Service neu
# Parameter: JSON-String mit allen Config-Werten
#           { "output_dir": "/media/iso", "mp3_quality": 2, ... }
# Rückgabe: JSON mit {"success": true} oder {"success": false, "message": "..."}
save_config_and_restart() {
    local json_input="$1"
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"
    
    if [[ -z "$json_input" ]]; then
        echo '{"success": false, "message": "Keine Konfigurationsdaten empfangen"}'
        return 1
    fi
    
    # Validiere output_dir falls vorhanden
    local output_dir=$(echo "$json_input" | /usr/bin/grep -o '"output_dir"[[:space:]]*:[[:space:]]*"[^"]*"' | /usr/bin/cut -d'"' -f4)
    if [[ -n "$output_dir" ]]; then
        if [[ ! -d "$output_dir" ]]; then
            echo "{\"success\": false, \"message\": \"Ausgabeverzeichnis existiert nicht: ${output_dir}\"}"
            return 1
        fi
        if [[ ! -w "$output_dir" ]]; then
            echo "{\"success\": false, \"message\": \"Ausgabeverzeichnis ist nicht beschreibbar: ${output_dir}\"}"
            return 1
        fi
    fi
    
    # Mapping: JSON-Key -> Config-Key
    declare -A config_mapping=(
        ["output_dir"]="DEFAULT_OUTPUT_DIR"
        ["mp3_quality"]="MP3_QUALITY"
        ["ddrescue_retries"]="DDRESCUE_RETRIES"
        ["usb_detection_attempts"]="USB_DRIVE_DETECTION_ATTEMPTS"
        ["usb_detection_delay"]="USB_DRIVE_DETECTION_DELAY"
        ["mqtt_enabled"]="MQTT_ENABLED"
        ["mqtt_broker"]="MQTT_BROKER"
        ["mqtt_port"]="MQTT_PORT"
        ["mqtt_user"]="MQTT_USER"
        ["mqtt_password"]="MQTT_PASSWORD"
        ["tmdb_api_key"]="TMDB_API_KEY"
    )
    
    # Aktualisiere alle Werte
    local failed=0
    for json_key in "${!config_mapping[@]}"; do
        local config_key="${config_mapping[$json_key]}"
        
        # Extrahiere Wert aus JSON
        local value
        if [[ "$json_key" == "mqtt_enabled" ]]; then
            # Boolean: true/false ohne Quotes
            value=$(echo "$json_input" | /usr/bin/grep -o "\"${json_key}\"[[:space:]]*:[[:space:]]*[^,}]*" | /usr/bin/awk -F':' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
        else
            # String oder Number
            value=$(echo "$json_input" | /usr/bin/grep -o "\"${json_key}\"[[:space:]]*:[[:space:]]*[^,}]*" | /usr/bin/awk -F':' '{gsub(/^[ \t"]+|[ \t"]+$/, "", $2); print $2}')
        fi
        
        # Nur updaten wenn Wert vorhanden
        if [[ -n "$value" ]]; then
            local result=$(update_config_value "$config_key" "$value")
            if ! echo "$result" | /usr/bin/grep -q '"success": true'; then
                failed=1
                echo "$result"
                return 1
            fi
        fi
    done
    
    # Starte disk2iso Service neu
    if /usr/bin/systemctl restart disk2iso 2>/dev/null; then
        echo '{"success": true, "message": "Konfiguration gespeichert. Service wurde neu gestartet."}'
        return 0
    else
        echo '{"success": true, "message": "Konfiguration gespeichert, aber Service-Neustart fehlgeschlagen.", "restart_failed": true}'
        return 0  # Config wurde gespeichert, daher success=true
    fi
}

# ===========================================================================
# MANIFEST-BASED DEPENDENCY CHECKING (INI-FORMAT)
# ===========================================================================

# ===========================================================================
# get_ini_value
# ---------------------------------------------------------------------------
# Funktion.: Lese einzelnen Wert aus INI-Manifest
# Parameter: $1 = ini_file (z.B. "conf/libcd.ini")
#            $2 = section (z.B. "metadata")
#            $3 = key (z.B. "name")
# Rückgabe.: Value (String), leer bei Fehler
# Beispiel.: get_ini_value "conf/libcd.ini" "metadata" "version"
#            → "1.2.0"
# ===========================================================================
get_ini_value() {
    local ini_file="$1"
    local section="$2"
    local key="$3"
    
    if [[ ! -f "$ini_file" ]]; then
        return 1
    fi
    
    # awk-Logik: Finde Sektion, dann Key innerhalb der Sektion
    awk -F'=' -v section="[${section}]" -v key="$key" '
        # Wenn Zeile = Section-Header → Sektion gefunden
        $0 == section { in_section=1; next }
        
        # Wenn neue Section beginnt → Sektion verlassen
        /^\[.*\]/ { in_section=0 }
        
        # Wenn in Sektion UND Key matcht → Wert extrahieren
        in_section && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
            # Entferne Whitespace vor/nach Wert
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
            print $2
            exit
        }
    ' "$ini_file"
}

# ===========================================================================
# get_ini_array
# ---------------------------------------------------------------------------
# Funktion.: Lese komma-separierte Liste aus INI
# Parameter: $1 = ini_file
#            $2 = section
#            $3 = key
# Rückgabe.: Array-Elemente (eine Zeile pro Element)
# Beispiel.: get_ini_array "conf/libcd.ini" "dependencies" "external"
#            → "cdparanoia\nlame\ngenisoimage"
# ===========================================================================
get_ini_array() {
    local ini_file="$1"
    local section="$2"
    local key="$3"
    
    # Lese Wert (Komma-separiert)
    local value
    value=$(get_ini_value "$ini_file" "$section" "$key")
    
    if [[ -n "$value" ]]; then
        # Split by Komma, trim Whitespace
        echo "$value" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    fi
}

# ===========================================================================
# check_module_dependencies_from_manifest
# ---------------------------------------------------------------------------
# Funktion.: Standard Dependency-Check aus INI-Manifest
# Parameter: $1 = module_name (z.B. "cd", "dvd", "metadata")
# Rückgabe.: 0 = Alle kritischen Tools vorhanden, 1 = Fehler
# Nutzt....: INI-Format: conf/lib<module>.ini
# ===========================================================================
check_module_dependencies() {
    local module_name="$1"
    local manifest_file="${INSTALL_DIR}/conf/lib${module_name}.ini"
    
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
        log_warning "${module_name}: Modul-Dateien fehlen (Modul unvollständig installiert oder beschädiigt?):"
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
    # Kritische Abhängikeiten prüfen
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
    # Optionale Abhängikeiten prüfen
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
    # Abhängikeiten geprüft - Alles vorhanden
    # ------------------------------------------------------------------------
    # Erfolgreiche Ordner-Erstellung loggen (Info-Level)
    if [[ ${#folder_creation_success[@]} -gt 0 ]]; then
        log_info "${module_name}: Modul-Ordner verfügbar (${#folder_creation_success[@]} Ordner geprüft/erstellt)"
    fi
    log_info "${module_name}: Alle Modul-Abhängigkeiten erfüllt"
    return 0
}
