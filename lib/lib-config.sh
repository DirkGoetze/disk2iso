#!/bin/bash
################################################################################
# disk2iso v1.2.0 - Configuration Management Library
# Filepath: lib/lib-config.sh
#
# Beschreibung:
#   Standalone Config-Management ohne Dependencies für Web-API
#   - update_config_value() - Schreibe einzelnen Wert in config.sh
#   - get_all_config_values() - Lese alle Werte als JSON
#
# Version: 1.2.0
# Datum: 14.01.2026
################################################################################

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
# CONFIG MANAGEMENT FUNKTIONEN
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
        local current_line=$(grep "^${key}=" "$config_file" | head -1)
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
    local output_dir=$(echo "$json_input" | grep -o '"output_dir"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)
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
            value=$(echo "$json_input" | grep -o "\"${json_key}\"[[:space:]]*:[[:space:]]*[^,}]*" | /usr/bin/awk -F':' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
        else
            # String oder Number
            value=$(echo "$json_input" | grep -o "\"${json_key}\"[[:space:]]*:[[:space:]]*[^,}]*" | /usr/bin/awk -F':' '{gsub(/^[ \t"]+|[ \t"]+$/, "", $2); print $2}')
        fi
        
        # Nur updaten wenn Wert vorhanden
        if [[ -n "$value" ]]; then
            local result=$(update_config_value "$config_key" "$value")
            if ! echo "$result" | grep -q '"success": true'; then
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
