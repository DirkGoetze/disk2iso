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

# ===========================================================================
# config_check_dependencies
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
config_check_dependencies() {
    # Prüfe kritische Abhängigkeit: Existenz der Config-Datei
    config_validate_file || return 1
    
    # Config-Modul nutzt POSIX-Standard-Tools (awk, sed, grep)
    # Diese sind auf jedem Linux-System verfügbar
    return 0
}

# ===========================================================================
# CONFIG GETTER/SETTER FUNCTIONS 'disk2iso.conf'
# ===========================================================================
# Diese Funktionen lesen und schreiben Konfigurationswerte in der
# Datei disk2iso.conf im conf/ Verzeichnis.
# ---------------------------------------------------------------------------
# Globale Flags für Lazy Initialization -------------------------------------
_CONFIG_FILE_VALIDATED=false                 # Config-Datei wurde geprüft
_CONFIG_DEPENDENCIES_VALIDATED=false         # Dependencies geprüft (get_module_ini_path verfügbar)
_CONFIG_SAVE_DEFAULT_CONF=false              # Flag für rekursiven Default-Write (verhindert Endlosschleife)
_CONFIG_SAVE_DEFAULT_INI=false               # Flag für rekursiven Default-Write (verhindert Endlosschleife)

# ===========================================================================
# config_validate_file
# ---------------------------------------------------------------------------
# Funktion.: Prüft einmalig ob die disk2iso Konfigurationsdatei existiert
# Parameter: keine
# Rückgabe.: 0 = Datei existiert
# .........  1 = Datei fehlt (kritischer Fehler)
# Hinweis..: Nutzt Lazy Initialization - wird nur einmal pro Session geprüft
# .........  Wird automatisch von config_check_dependencies() aufgerufen
# ===========================================================================
config_validate_file() {
    #-- Setze Pfad zur Config-Datei --------------------------------------
    local config_file="${INSTALL_DIR:-/opt/disk2iso}/conf/disk2iso.conf"

    #-- Lazy Initialization: Nur einmal pro Session prüfen ------------------
    if [[ "$_CONFIG_FILE_VALIDATED" == false ]]; then
        if [[ ! -f "$config_file" ]]; then
            echo "FEHLER: Konfigurationsdatei nicht gefunden: $config_file" >&2
            return 1
        fi
        _CONFIG_FILE_VALIDATED=true
    fi
    return 0
}

# ===========================================================================
# config_validate_dependencies
# ---------------------------------------------------------------------------
# Funktion.: Prüft einmalig ob alle Module für die Pfad und Dateinamen 
# .........  Ermittlung verfügbar sind
# Parameter: keine
# Rückgabe.: 0 = Dependencies OK
# .........  1 = Dependencies fehlen (kritischer Fehler)
# Hinweis..: Nutzt Lazy Initialization - wird nur einmal pro Session geprüft
# .........  Prüft: folders_get_conf_dir() aus libfolders.sh
# .........         get_module_ini_path() aus libfiles.sh
# ===========================================================================
config_validate_dependencies() {
    #-- Bereits validiert? --------------------------------------------------
    [[ "$_CONFIG_DEPENDENCIES_VALIDATED" == "true" ]] && return 0
    
    #-- Prüfe ob folders_get_conf_dir() verfügbar ist (aus libfolders.sh) ---
    if ! type -t folders_get_conf_dir &>/dev/null; then
        echo "ERROR: folders_get_conf_dir() not available. Load libfolders.sh first!" >&2
        return 1
    fi

    #-- Prüfe ob get_module_ini_path() verfügbar ist (aus libfiles.sh) ------
    if ! type -t get_module_ini_path &>/dev/null; then
        echo "ERROR: get_module_ini_path() not available. Load libfiles.sh first!" >&2
        return 1
    fi
    
    #-- Dependencies OK -----------------------------------------------------
    _CONFIG_DEPENDENCIES_VALIDATED=true
    return 0
}

# ===========================================================================
# config_get_output_dir
# ---------------------------------------------------------------------------
# Funktion.: Lese OUTPUT_DIR aus disk2iso.conf oder verwende Fallback
# Parameter: keine
# Rückgabe.: OUTPUT_DIR Pfad (stdout, ohne trailing slash)
# .........  Return-Code: 0 = Erfolg, 1 = Fehler
# Beispiel.: output_dir=$(config_get_output_dir)
# Hinweis..: - Besondere Bedeutung dieser Funktion, da OUTPUT_DIR essentiell
# .........  - für die Funktionsweise von disk2iso ist. Daher hier separat
# .........  - implementiert, um Abhängigkeiten zu minimieren.
# .........  - Liest DEFAULT_OUTPUT_DIR oder OUTPUT_DIR aus Konfiguration
# .........  - Entfernt trailing slash für konsistente Rückgabe
# ===========================================================================
config_get_output_dir() {
    local output_dir=""
    
    #-- Stelle sicher dass Config-Datei validiert wurde --------------------
    config_validate_file || return 1
    
    #-- Lese OUTPUT_DIR aus Config -----------------------------------------
    # Lese DEFAULT_OUTPUT_DIR falls vorhanden
    output_dir=$(/usr/bin/grep -E '^DEFAULT_OUTPUT_DIR=' "$CONFIG_FILE" 2>/dev/null | /usr/bin/sed 's/^DEFAULT_OUTPUT_DIR=//;s/^"\(.*\)"$/\1/')
    
    # Fallback: Lese OUTPUT_DIR falls DEFAULT_OUTPUT_DIR nicht gesetzt
    if [[ -z "$output_dir" ]]; then
        output_dir=$(/usr/bin/grep -E '^OUTPUT_DIR=' "$CONFIG_FILE" 2>/dev/null | /usr/bin/sed 's/^OUTPUT_DIR=//;s/^"\(.*\)"$/\1/')
    fi
    
    #-- Fehlerfall: Kein OUTPUT_DIR gefunden -------------------------------
    if [[ -z "$output_dir" ]]; then
        echo "" >&2
        return 1
    fi
    
    #-- Entferne trailing slash und gebe zurück ---------------------------
    echo "${output_dir%/}"
    return 0
}

set_default_output_dir() {
    local value="$1"
    
    config_validate_file || return 1
    
    if [[ ! -d "$value" ]]; then
        echo '{"success": false, "message": "Verzeichnis existiert nicht"}' >&2
        return 1
    fi
    if [[ ! -w "$value" ]]; then
        echo '{"success": false, "message": "Verzeichnis nicht beschreibbar"}' >&2
        return 1
    fi
    
    /usr/bin/sed -i "s|^DEFAULT_OUTPUT_DIR=.*|DEFAULT_OUTPUT_DIR=\"${value}\"|" "$CONFIG_FILE" 2>/dev/null
    return $?
}

# ============================================================================
# UNIFIED CONFIG API - SINGLE VALUE OPERATIONS (.conf FORMAT)
# ============================================================================
# Format: .conf = Simple Key=Value (kein Section-Header)
# Beispiel: disk2iso.conf
#   OUTPUT_DIR="/media/iso"
#   MQTT_PORT=1883
#   MQTT_ENABLED=true

# ===========================================================================
# config_get_value_conf
# ---------------------------------------------------------------------------
# Funktion.: Lese einzelnen Wert aus .conf Datei
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "disk2iso")
#            $2 = key (z.B. "OUTPUT_DIR")
#            $3 = default (optional, Fallback wenn Key nicht gefunden)
# Rückgabe.: 0 = Erfolg (Wert oder Default), 1 = Fehler (Key fehlt, kein Default)
# Ausgabe..: Value (stdout), Quotes werden automatisch entfernt
# Beispiel.: output_dir=$(config_get_value_conf "disk2iso" "OUTPUT_DIR" "/opt/disk2iso/output")
# ===========================================================================
config_get_value_conf() {
    #-- Parameter einlesen --------------------------------------------------
    local module="$1"
    local key="$2"
    local default="${3:-}"
    
    #-- Parameter-Validierung -----------------------------------------------
    if [[ -z "$module" ]]; then
        log_error "config_get_value_conf: Module name missing" 2>/dev/null || echo "ERROR: Module name missing" >&2
        return 1
    fi
    
    if [[ -z "$key" ]]; then
        log_error "config_get_value_conf: Key missing" 2>/dev/null || echo "ERROR: Key missing" >&2
        return 1
    fi
    
    #-- Pfad-Resolution über zentrale Funktion ------------------------------
    local filepath
    filepath=$(get_module_conf_path "$module") || {
        log_error "config_get_value_conf: Path resolution failed for module: $module" 2>/dev/null || echo "ERROR: Path resolution failed" >&2
        return 1
    }
    
    #-- Lese Wert (nutze erste Zeile die passt) -----------------------------
    local value
    value=$(/usr/bin/sed -n "s/^${key}=\(.*\)/\1/p" "$filepath" | /usr/bin/head -1)
    
    #-- Entferne umschließende Quotes falls vorhanden -----------------------
    value=$(echo "$value" | /usr/bin/sed 's/^"\(.*\)"$/\1/')
    
    #-- Wert gefunden oder Default nutzen (Self-Healing) -------------------
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    elif [[ -n "$default" ]]; then
        # Self-Healing: Default-Wert in Config schreiben (falls nicht in Schleife)
        if [[ "$_CONFIG_SAVE_DEFAULT_CONF" == false ]]; then
            _CONFIG_SAVE_DEFAULT_CONF=true
            
            # Schreibe Default in Config-Datei
            if config_set_value_conf "$module" "$key" "$default" 2>/dev/null; then
                # Lese Wert erneut zur Bestätigung (rekursiver Aufruf)
                _CONFIG_SAVE_DEFAULT_CONF=false
                config_get_value_conf "$module" "$key" "$default"
                return $?
            else
                # Schreibfehler - gebe Default trotzdem zurück
                _CONFIG_SAVE_DEFAULT_CONF=false
                log_warning "config_get_value_conf: Default konnte nicht gespeichert werden: ${module}.${key}=${default}" 2>/dev/null
                echo "$default"
                return 0
            fi
        else
            # In rekursivem Aufruf - verhindere Endlosschleife
            echo "$default"
            return 0
        fi
    else
        return 1
    fi
}

# ===========================================================================
# config_set_value_conf
# ---------------------------------------------------------------------------
# Funktion.: Schreibe einzelnen Wert in .conf Datei (atomic write)
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "disk2iso")
#            $2 = key
#            $3 = value
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Type-Detection:
#   - Pure Integer (^-?[0-9]+$) → Ohne Quotes
#   - Boolean (true|false|0|1|yes|no) → Normalisiert zu true/false, ohne Quotes
#   - String → Mit Quotes, escaped
# Beispiel.: config_set_value_conf "disk2iso" "MQTT_PORT" "1883"
#            → MQTT_PORT=1883
#            config_set_value_conf "disk2iso" "MQTT_BROKER" "192.168.1.1"
#            → MQTT_BROKER="192.168.1.1"
# ===========================================================================
config_set_value_conf() {
    local module="$1"
    local key="$2"
    local value="$3"
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "config_set_value_conf: Module name missing" 2>/dev/null || echo "ERROR: Module name missing" >&2
        return 1
    fi
    
    if [[ -z "$key" ]]; then
        log_error "config_set_value_conf: Key missing" 2>/dev/null || echo "ERROR: Key missing" >&2
        return 1
    fi
    
    # Pfad-Resolution über zentrale Funktion
    local filepath
    filepath=$(get_module_conf_path "$module") || {
        log_error "config_set_value_conf: Path resolution failed for module: $module" 2>/dev/null || echo "ERROR: Path resolution failed" >&2
        return 1
    }
    
    # Type Detection (Smart Quoting)
    local formatted_value
    
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        # Pure Integer - keine Quotes
        formatted_value="${value}"
        
    elif [[ "$value" =~ ^(true|false|0|1|yes|no|on|off)$ ]]; then
        # Boolean - normalisieren zu true/false, keine Quotes
        case "$value" in
            true|1|yes|on)   formatted_value="true" ;;
            false|0|no|off)  formatted_value="false" ;;
        esac
        
    else
        # String - mit Quotes + Escaping
        # Escape existing quotes
        local escaped_value="${value//\"/\\\"}"
        formatted_value="\"${escaped_value}\""
    fi
    
    # Atomic write mit sed
    /usr/bin/sed -i "s|^${key}=.*|${key}=${formatted_value}|" "$filepath" 2>/dev/null
    return $?
}

# ===========================================================================
# config_del_value_conf
# ---------------------------------------------------------------------------
# Funktion.: Lösche einzelnen Wert aus .conf Datei
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "disk2iso")
#            $2 = key
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: config_del_value_conf "disk2iso" "OLD_KEY"
# ===========================================================================
config_del_value_conf() {
    local module="$1"
    local key="$2"
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "config_del_value_conf: Module name missing" 2>/dev/null || echo "ERROR: Module name missing" >&2
        return 1
    fi
    
    if [[ -z "$key" ]]; then
        log_error "config_del_value_conf: Key missing" 2>/dev/null || echo "ERROR: Key missing" >&2
        return 1
    fi
    
    # Pfad-Resolution über zentrale Funktion
    local filepath
    filepath=$(get_module_conf_path "$module") || {
        log_error "config_del_value_conf: Path resolution failed for module: $module" 2>/dev/null || echo "ERROR: Path resolution failed" >&2
        return 1
    }
    
    # Lösche Zeile mit sed (in-place)
    /usr/bin/sed -i "/^${key}=/d" "$filepath" 2>/dev/null
    return $?
}

# ============================================================================
# UNIFIED CONFIG API - SINGLE VALUE OPERATIONS (.ini FORMAT)
# ============================================================================
# Format: .ini = Sectioned Key=Value
# Beispiel: libaudio.ini
#   [dependencies]
#   optional=cdparanoia,lame,genisoimage
#   [metadata]
#   version=1.2.0

# ===========================================================================
# config_get_value_ini
# ---------------------------------------------------------------------------
# Funktion.: Lese einzelnen Wert aus .ini Datei (KERN-IMPLEMENTIERUNG)
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section (z.B. "dependencies")
#            $3 = key (z.B. "optional")
#            $4 = default (optional, Fallback wenn Key nicht gefunden)
# Rückgabe.: 0 = Erfolg (Wert oder Default), 1 = Fehler (Key fehlt, kein Default)
# Ausgabe..: Value (stdout)
# Beispiel.: tools=$(config_get_value_ini "audio" "dependencies" "optional" "")
# ===========================================================================
config_get_value_ini() {
    #-- Parameter einlesen --------------------------------------------------
    local module="$1"
    local section="$2"
    local key="$3"
    local default="${4:-}"
    
    #-- Validiere Dependencies ----------------------------------------------
    if ! type -t get_module_ini_path &>/dev/null; then
        log_error "config_get_value_ini: get_module_ini_path() not available. Load libfiles.sh first!" 2>/dev/null || echo "ERROR: get_module_ini_path() not available" >&2
        return 1
    fi
    
    #-- Hole Pfad zur INI-Datei via get_module_ini_path() -------------------
    local filepath=$(get_module_ini_path "$module") || {
        if [[ -n "$default" ]]; then
            echo "$default"
            return 0
        fi
        log_error "config_get_value_ini: Module INI not found: $module" 2>/dev/null || echo "ERROR: Module INI not found: $module" >&2
        return 1
    }
    
    #-- Validierung der Parameter -------------------------------------------
    if [[ -z "$module" ]]; then
        log_error "config_get_value_ini: Module name missing" 2>/dev/null || echo "ERROR: Module name missing" >&2
        return 1
    fi
    
    if [[ -z "$section" ]]; then
        log_error "config_get_value_ini: Section missing" 2>/dev/null || echo "ERROR: Section missing" >&2
        return 1
    fi
    
    if [[ -z "$key" ]]; then
        log_error "config_get_value_ini: Key missing" 2>/dev/null || echo "ERROR: Key missing" >&2
        return 1
    fi
    
    #-- awk-Logik für INI-Parsing -------------------------------------------
    local value
    value=$(awk -F'=' -v section="[${section}]" -v key="$key" '
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
    ' "$filepath")
    
    #-- Wert gefunden oder Default nutzen (Self-Healing) -------------------
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    elif [[ -n "$default" ]]; then
        # Self-Healing: Default-Wert in INI-Datei schreiben (falls nicht in Schleife)
        if [[ "$_CONFIG_SAVE_DEFAULT_INI" == false ]]; then
            _CONFIG_SAVE_DEFAULT_INI=true
            
            # Schreibe Default in INI-Datei
            if config_set_value_ini "$module" "$section" "$key" "$default" 2>/dev/null; then
                # Lese Wert erneut zur Bestätigung (rekursiver Aufruf)
                _CONFIG_SAVE_DEFAULT_INI=false
                config_get_value_ini "$module" "$section" "$key" "$default"
                return $?
            else
                # Schreibfehler - gebe Default trotzdem zurück
                _CONFIG_SAVE_DEFAULT_INI=false
                log_warning "config_get_value_ini: Default konnte nicht gespeichert werden: ${module}.[${section}].${key}=${default}" 2>/dev/null
                echo "$default"
                return 0
            fi
        else
            # In rekursivem Aufruf - verhindere Endlosschleife
            echo "$default"
            return 0
        fi
    else
        return 1
    fi
}

# ===========================================================================
# config_set_value_ini
# ---------------------------------------------------------------------------
# Funktion.: Schreibe/Aktualisiere einzelnen Wert in .ini Datei (KERN-IMPLEMENTIERUNG)
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section
#            $3 = key
#            $4 = value
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: INI-Format speichert immer als String, keine Type-Detection
# Beispiel.: config_set_value_ini "audio" "dependencies" "optional" "cdparanoia,lame"
# ===========================================================================
config_set_value_ini() {
    local module="$1"
    local section="$2"
    local key="$3"
    local value="$4"
    
    # Validiere Dependencies (Lazy Initialization)
    if ! type -t get_module_ini_path &>/dev/null; then
        log_error "config_set_value_ini: get_module_ini_path() not available. Load libfiles.sh first!" 2>/dev/null || echo "ERROR: get_module_ini_path() not available" >&2
        return 1
    fi
    
    # Hole Pfad zur INI-Datei via get_module_ini_path()
    local filepath
    filepath=$(get_module_ini_path "$module") || {
        log_error "config_set_value_ini: Module INI not found: $module" 2>/dev/null || echo "ERROR: Module INI not found: $module" >&2
        return 1
    }
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "config_set_value_ini: Module name missing" 2>/dev/null || echo "ERROR: Module name missing" >&2
        return 1
    fi
    
    if [[ -z "$section" ]]; then
        log_error "config_set_value_ini: Section missing" 2>/dev/null || echo "ERROR: Section missing" >&2
        return 1
    fi
    
    if [[ -z "$key" ]]; then
        log_error "config_set_value_ini: Key missing" 2>/dev/null || echo "ERROR: Key missing" >&2
        return 1
    fi
    
    # KERN-IMPLEMENTIERUNG: Atomic write mit awk
    # Hinweis: Datei-Existenz ist garantiert durch get_module_ini_path() (Self-Healing)
    # Escape Sonderzeichen für sed
    local escaped_key=$(echo "$key" | sed 's/[\/&]/\\&/g')
    local escaped_value=$(echo "$value" | sed 's/[\/&]/\\&/g')
    
    # Prüfe ob Section existiert
    if ! grep -q "^\[${section}\]" "$filepath" 2>/dev/null; then
        # Section fehlt - erstelle sie
        echo "" >> "$filepath"
        echo "[${section}]" >> "$filepath"
        echo "${key}=${value}" >> "$filepath"
        return 0
    fi
    
    # Prüfe ob Key in Section existiert
    if awk -v section="[${section}]" -v key="$key" '
        $0 == section { in_section=1; next }
        /^\[.*\]/ { in_section=0 }
        in_section && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" { found=1; exit }
        END { exit !found }
    ' "$filepath"; then
        # Key existiert - aktualisiere Wert
        awk -v section="[${section}]" -v key="$key" -v value="$value" '
            $0 == section { in_section=1; print; next }
            /^\[.*\]/ { in_section=0 }
            in_section && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
                print key "=" value
                next
            }
            { print }
        ' "$filepath" > "${filepath}.tmp" && mv "${filepath}.tmp" "$filepath"
    else
        # Key fehlt - füge in Section ein
        awk -v section="[${section}]" -v key="$key" -v value="$value" '
            $0 == section { in_section=1; print; print key "=" value; next }
            /^\[.*\]/ { in_section=0 }
            { print }
        ' "$filepath" > "${filepath}.tmp" && mv "${filepath}.tmp" "$filepath"
    fi
    
    return 0
}

# ===========================================================================
# config_del_value_ini
# ---------------------------------------------------------------------------
# Funktion.: Lösche einzelnen Key aus .ini Datei (KERN-IMPLEMENTIERUNG)
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section
#            $3 = key
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: config_del_value_ini "audio" "dependencies" "old_key"
# ===========================================================================
config_del_value_ini() {
    local module="$1"
    local section="$2"
    local key="$3"
    
    # Validiere Dependencies (Lazy Initialization)
    if ! type -t get_module_ini_path &>/dev/null; then
        log_error "config_del_value_ini: get_module_ini_path() not available. Load libfiles.sh first!" 2>/dev/null || echo "ERROR: get_module_ini_path() not available" >&2
        return 1
    fi
    
    # Hole Pfad zur INI-Datei via get_module_ini_path()
    local filepath
    filepath=$(get_module_ini_path "$module") || {
        log_error "config_del_value_ini: Module INI not found: $module" 2>/dev/null || echo "ERROR: Module INI not found: $module" >&2
        return 1
    }
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "config_del_value_ini: Module name missing" 2>/dev/null || echo "ERROR: Module name missing" >&2
        return 1
    fi
    
    if [[ -z "$section" ]]; then
        log_error "config_del_value_ini: Section missing" 2>/dev/null || echo "ERROR: Section missing" >&2
        return 1
    fi
    
    if [[ -z "$key" ]]; then
        log_error "config_del_value_ini: Key missing" 2>/dev/null || echo "ERROR: Key missing" >&2
        return 1
    fi
    
    # Hinweis: Datei-Existenz ist garantiert durch get_module_ini_path() (Self-Healing)
    # KERN-IMPLEMENTIERUNG: awk löscht Key=Value Zeile in angegebener Sektion
    awk -v section="[${section}]" -v key="$key" '
        $0 == section { in_section=1; print; next }
        /^\[.*\]/ { in_section=0 }
        in_section && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" { next }
        { print }
    ' "$filepath" > "${filepath}.tmp" && mv "${filepath}.tmp" "$filepath"
    
    return 0
}

# ============================================================================
# UNIFIED CONFIG API - ARRAY OPERATIONS (.ini FORMAT)
# ============================================================================
# Arrays werden als komma-separierte Werte gespeichert
# Beispiel: tools=cdparanoia,lame,genisoimage

# ===========================================================================
# config_get_array_ini
# ---------------------------------------------------------------------------
# Funktion.: Lese komma-separierte Liste aus .ini Datei als Bash-Array
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section (z.B. "dependencies")
#            $3 = key (z.B. "optional")
#            $4 = default (optional, komma-separiert wenn Key nicht gefunden)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Ausgabe..: Array-Elemente (eine Zeile pro Element)
# Beispiel.: mapfile -t tools < <(config_get_array_ini "audio" "dependencies" "optional")
#            → tools=("cdparanoia" "lame" "genisoimage")
# Hinweis..: Nutzt config_get_value_ini() intern
# ===========================================================================
config_get_array_ini() {
    local module="$1"
    local section="$2"
    local key="$3"
    local default="${4:-}"
    
    # Lese komma-separierte Liste
    local value
    value=$(config_get_value_ini "$module" "$section" "$key" "$default") || return 1
    
    if [[ -z "$value" ]]; then
        return 1
    fi
    
    # Split by Komma, trim Whitespace, ausgeben (eine Zeile pro Element)
    echo "$value" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
    return 0
}

# ===========================================================================
# config_set_array_ini
# ---------------------------------------------------------------------------
# Funktion.: Schreibe Bash-Array als komma-separierte Liste in .ini Datei
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section
#            $3 = key
#            $4+ = values (alle weiteren Parameter werden als Array-Elemente behandelt)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: config_set_array_ini "audio" "dependencies" "optional" "cdparanoia" "lame" "genisoimage"
#            → optional=cdparanoia,lame,genisoimage
#            
#            # Mit Array-Expansion:
#            tools=("cdparanoia" "lame" "genisoimage")
#            config_set_array_ini "audio" "dependencies" "optional" "${tools[@]}"
# Hinweis..: Nutzt config_set_value_ini() intern
# ===========================================================================
config_set_array_ini() {
    local module="$1"
    local section="$2"
    local key="$3"
    shift 3
    
    # Validierung
    if [[ $# -eq 0 ]]; then
        log_error "config_set_array_ini: No values provided" 2>/dev/null || echo "ERROR: No values provided" >&2
        return 1
    fi
    
    # Join Array zu komma-separiertem String
    local value
    local first=true
    for item in "$@"; do
        if [[ "$first" == true ]]; then
            value="$item"
            first=false
        else
            value="${value},${item}"
        fi
    done
    
    # Schreibe als einfachen Wert
    config_set_value_ini "$module" "$section" "$key" "$value"
}

# ===========================================================================
# config_del_array_ini
# ---------------------------------------------------------------------------
# Funktion.: Lösche Array-Key aus .ini Datei (Wrapper)
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section
#            $3 = key
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: config_del_array_ini "audio" "dependencies" "optional"
# Hinweis..: Wrapper um config_del_value_ini() - Arrays werden wie Werte gelöscht
# ===========================================================================
config_del_array_ini() {
    local module="$1"
    local section="$2"
    local key="$3"
    
    config_del_value_ini "$module" "$section" "$key"
}

# ============================================================================
# UNIFIED CONFIG API - SECTION OPERATIONS (.ini FORMAT)
# ============================================================================
# Operationen auf ganzen INI-Sektionen

# ===========================================================================
# config_get_section_ini
# ---------------------------------------------------------------------------
# Funktion.: Lese alle Key=Value Paare einer INI-Sektion
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section (z.B. "metadata")
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Ausgabe..: Key=Value Paare (eine Zeile pro Entry)
# Beispiel.: config_get_section_ini "audio" "metadata"
#            → "name=Audio Ripper"
#            → "version=1.2.0"
# Hinweis..: Ignoriert Kommentare und Leerzeilen
# ===========================================================================
config_get_section_ini() {
    local module="$1"
    local section="$2"
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "config_get_section_ini: Module name missing" 2>/dev/null || echo "ERROR: Module name missing" >&2
        return 1
    fi
    
    if [[ -z "$section" ]]; then
        log_error "config_get_section_ini: Section missing" 2>/dev/null || echo "ERROR: Section missing" >&2
        return 1
    fi
    
    # Validiere Dependencies
    if ! type -t get_module_ini_path &>/dev/null; then
        log_error "config_get_section_ini: get_module_ini_path() not available. Load libfiles.sh first!" 2>/dev/null || echo "ERROR: get_module_ini_path() not available" >&2
        return 1
    fi
    
    # Hole Pfad zur INI-Datei
    local filepath
    filepath=$(get_module_ini_path "$module") || {
        log_error "config_get_section_ini: Module INI not found: $module" 2>/dev/null || echo "ERROR: Module INI not found: $module" >&2
        return 1
    }
    
    # awk: Drucke alle Key=Value Zeilen innerhalb der Sektion
    awk -v section="[${section}]" '
        # Section-Header gefunden
        $0 == section { in_section=1; next }
        
        # Neue Section beginnt
        /^\[.*\]/ { in_section=0 }
        
        # In Sektion: Drucke Key=Value Zeilen (ignoriere Kommentare/Leerzeilen)
        in_section && /^[^#;[:space:]].*=/ { print $0 }
    ' "$filepath"
}

# ===========================================================================
# config_set_section_ini
# ---------------------------------------------------------------------------
# Funktion.: Erstelle/Überschreibe komplette INI-Sektion mit Key=Value Paaren
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section
#            $3+ = key=value Paare (alle weiteren Parameter)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: config_set_section_ini "audio" "metadata" "name=Audio Ripper" "version=1.2.0"
# Hinweis..: Löscht existierende Sektion komplett und erstellt sie neu
# ===========================================================================
config_set_section_ini() {
    local module="$1"
    local section="$2"
    shift 2
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "config_set_section_ini: Module name missing" 2>/dev/null || echo "ERROR: Module name missing" >&2
        return 1
    fi
    
    if [[ -z "$section" ]]; then
        log_error "config_set_section_ini: Section missing" 2>/dev/null || echo "ERROR: Section missing" >&2
        return 1
    fi
    
    if [[ $# -eq 0 ]]; then
        log_error "config_set_section_ini: No key=value pairs provided" 2>/dev/null || echo "ERROR: No key=value pairs provided" >&2
        return 1
    fi
    
    # Validiere Dependencies
    if ! type -t get_module_ini_path &>/dev/null; then
        log_error "config_set_section_ini: get_module_ini_path() not available. Load libfiles.sh first!" 2>/dev/null || echo "ERROR: get_module_ini_path() not available" >&2
        return 1
    fi
    
    # Hole Pfad zur INI-Datei
    local filepath
    filepath=$(get_module_ini_path "$module") || {
        log_error "config_set_section_ini: Module INI not found: $module" 2>/dev/null || echo "ERROR: Module INI not found: $module" >&2
        return 1
    }
    
    # Lösche existierende Sektion falls vorhanden
    config_del_section_ini "$module" "$section" 2>/dev/null
    
    # Erstelle neue Sektion
    echo "" >> "$filepath"
    echo "[${section}]" >> "$filepath"
    
    # Füge alle Key=Value Paare hinzu
    for pair in "$@"; do
        # Validiere Format key=value
        if [[ "$pair" =~ ^[^=]+=.* ]]; then
            echo "$pair" >> "$filepath"
        else
            log_warning "config_set_section_ini: Invalid key=value pair skipped: $pair" 2>/dev/null
        fi
    done
    
    return 0
}

# ===========================================================================
# config_del_section_ini
# ---------------------------------------------------------------------------
# Funktion.: Lösche komplette INI-Sektion inklusive aller Einträge
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: config_del_section_ini "audio" "metadata"
# Hinweis..: Entfernt Section-Header und alle zugehörigen Key=Value Zeilen
# ===========================================================================
config_del_section_ini() {
    local module="$1"
    local section="$2"
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "config_del_section_ini: Module name missing" 2>/dev/null || echo "ERROR: Module name missing" >&2
        return 1
    fi
    
    if [[ -z "$section" ]]; then
        log_error "config_del_section_ini: Section missing" 2>/dev/null || echo "ERROR: Section missing" >&2
        return 1
    fi
    
    # Validiere Dependencies
    if ! type -t get_module_ini_path &>/dev/null; then
        log_error "config_del_section_ini: get_module_ini_path() not available. Load libfiles.sh first!" 2>/dev/null || echo "ERROR: get_module_ini_path() not available" >&2
        return 1
    fi
    
    # Hole Pfad zur INI-Datei
    local filepath
    filepath=$(get_module_ini_path "$module") || {
        log_error "config_del_section_ini: Module INI not found: $module" 2>/dev/null || echo "ERROR: Module INI not found: $module" >&2
        return 1
    }
    
    # awk: Lösche Section-Header und alle zugehörigen Zeilen
    awk -v section="[${section}]" '
        # Section-Header gefunden - überspringe
        $0 == section { in_section=1; next }
        
        # Neue Section beginnt - verlasse Delete-Modus
        /^\[.*\]/ { in_section=0 }
        
        # In Section - überspringe alle Zeilen
        in_section { next }
        
        # Alle anderen Zeilen ausgeben
        { print }
    ' "$filepath" > "${filepath}.tmp" && mv "${filepath}.tmp" "$filepath"
    
    return 0
}

# ===========================================================================
# config_count_section_entries_ini
# ---------------------------------------------------------------------------
# Funktion.: Zähle Anzahl der Einträge in einer INI-Sektion
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section (z.B. "metadata")
# Rückgabe.: Anzahl der Einträge (0-N) via stdout
# Beispiel.: count=$(config_count_section_entries_ini "audio" "dependencies")
#            → "3"
# Hinweis..: Zählt nur Key=Value Zeilen, keine Kommentare/Leerzeilen
# ===========================================================================
config_count_section_entries_ini() {
    local module="$1"
    local section="$2"
    
    # Validierung
    if [[ -z "$module" ]] || [[ -z "$section" ]]; then
        echo 0
        return 0
    fi
    
    # Validiere Dependencies
    if ! type -t get_module_ini_path &>/dev/null; then
        echo 0
        return 0
    fi
    
    # Hole Pfad zur INI-Datei
    local filepath
    filepath=$(get_module_ini_path "$module") 2>/dev/null || {
        echo 0
        return 0
    }
    
    # awk: Zähle Key=Value Zeilen in Sektion
    local count=$(awk -v section="[${section}]" '
        $0 == section { in_section=1; next }
        /^\[.*\]/ { in_section=0 }
        in_section && /^[^#;[:space:]].*=/ { count++ }
        END { print count+0 }
    ' "$filepath")
    
    echo "$count"
}

# ============================================================================
# UNIFIED CONFIG API - JSON OPERATIONS
# ============================================================================
# JSON-Dateien für API-Status und Metadaten (api/ Verzeichnis)
# Beispiel: api/status.json, api/progress.json

# ===========================================================================
# config_get_value_json
# ---------------------------------------------------------------------------
# Funktion.: Lese einzelnen Wert aus JSON-Datei
# Parameter: $1 = json_file (Dateiname ohne Pfad, z.B. "status")
#            $2 = json_path (jq-kompatibel, z.B. ".disc_type" oder ".metadata.title")
#            $3 = default (optional, Fallback wenn Key nicht gefunden)
# Rückgabe.: 0 = Erfolg (Wert oder Default), 1 = Fehler (Key fehlt, kein Default)
# Ausgabe..: Value (stdout, als JSON-String)
# Beispiel.: disc_type=$(config_get_value_json "status" ".disc_type" "unknown")
# Hinweis..: Benötigt jq (wird bei Dependency-Check validiert)
# ===========================================================================
config_get_value_json() {
    local json_file="$1"
    local json_path="$2"
    local default="${3:-}"
    
    # Validierung
    if [[ -z "$json_file" ]]; then
        log_error "config_get_value_json: JSON filename missing" 2>/dev/null || echo "ERROR: JSON filename missing" >&2
        return 1
    fi
    
    if [[ -z "$json_path" ]]; then
        log_error "config_get_value_json: JSON path missing" 2>/dev/null || echo "ERROR: JSON path missing" >&2
        return 1
    fi
    
    # Pfad-Resolution: api/${json_file}.json
    local filepath="${INSTALL_DIR:-/opt/disk2iso}/api/${json_file}.json"
    
    # Prüfe ob Datei existiert
    if [[ ! -f "$filepath" ]]; then
        if [[ -n "$default" ]]; then
            echo "$default"
            return 0
        fi
        log_error "config_get_value_json: JSON file not found: $filepath" 2>/dev/null || echo "ERROR: JSON file not found" >&2
        return 1
    fi
    
    # Prüfe ob jq verfügbar ist
    if ! command -v jq &>/dev/null; then
        log_error "config_get_value_json: jq not available" 2>/dev/null || echo "ERROR: jq not available" >&2
        return 1
    fi
    
    # Lese Wert mit jq
    local value
    value=$(jq -r "${json_path}" "$filepath" 2>/dev/null)
    
    # Wert gefunden oder Default nutzen
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
# config_set_value_json
# ---------------------------------------------------------------------------
# Funktion.: Schreibe einzelnen Wert in JSON-Datei
# Parameter: $1 = json_file (Dateiname ohne Pfad, z.B. "status")
#            $2 = json_path (jq-kompatibel, z.B. ".disc_type" oder ".metadata.title")
#            $3 = value (String, Number oder Boolean)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: config_set_value_json "status" ".disc_type" "audio-cd"
#            config_set_value_json "progress" ".percentage" "75"
# Hinweis..: Erstellt Datei falls nicht vorhanden, erstellt verschachtelte Pfade
# ===========================================================================
config_set_value_json() {
    local json_file="$1"
    local json_path="$2"
    local value="$3"
    
    # Validierung
    if [[ -z "$json_file" ]]; then
        log_error "config_set_value_json: JSON filename missing" 2>/dev/null || echo "ERROR: JSON filename missing" >&2
        return 1
    fi
    
    if [[ -z "$json_path" ]]; then
        log_error "config_set_value_json: JSON path missing" 2>/dev/null || echo "ERROR: JSON path missing" >&2
        return 1
    fi
    
    # Pfad-Resolution: api/${json_file}.json
    local filepath="${INSTALL_DIR:-/opt/disk2iso}/api/${json_file}.json"
    
    # Prüfe ob jq verfügbar ist
    if ! command -v jq &>/dev/null; then
        log_error "config_set_value_json: jq not available" 2>/dev/null || echo "ERROR: jq not available" >&2
        return 1
    fi
    
    # Erstelle Datei falls nicht vorhanden
    if [[ ! -f "$filepath" ]]; then
        echo '{}' > "$filepath"
    fi
    
    # Type Detection für JSON
    local json_value
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        # Integer - ohne Quotes
        json_value="$value"
    elif [[ "$value" =~ ^(true|false)$ ]]; then
        # Boolean - ohne Quotes
        json_value="$value"
    else
        # String - mit Quotes (jq escaped automatisch)
        json_value="\"$value\""
    fi
    
    # Schreibe Wert mit jq (atomic write)
    jq "${json_path} = ${json_value}" "$filepath" > "${filepath}.tmp" && mv "${filepath}.tmp" "$filepath"
    return $?
}

# ===========================================================================
# config_del_value_json
# ---------------------------------------------------------------------------
# Funktion.: Lösche einzelnen Key aus JSON-Datei
# Parameter: $1 = json_file (Dateiname ohne Pfad, z.B. "status")
#            $2 = json_path (jq-kompatibel, z.B. ".disc_type" oder ".metadata.title")
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: config_del_value_json "status" ".disc_type"
# ===========================================================================
config_del_value_json() {
    local json_file="$1"
    local json_path="$2"
    
    # Validierung
    if [[ -z "$json_file" ]]; then
        log_error "config_del_value_json: JSON filename missing" 2>/dev/null || echo "ERROR: JSON filename missing" >&2
        return 1
    fi
    
    if [[ -z "$json_path" ]]; then
        log_error "config_del_value_json: JSON path missing" 2>/dev/null || echo "ERROR: JSON path missing" >&2
        return 1
    fi
    
    # Pfad-Resolution: api/${json_file}.json
    local filepath="${INSTALL_DIR:-/opt/disk2iso}/api/${json_file}.json"
    
    # Prüfe ob Datei existiert
    if [[ ! -f "$filepath" ]]; then
        return 0
    fi
    
    # Prüfe ob jq verfügbar ist
    if ! command -v jq &>/dev/null; then
        log_error "config_del_value_json: jq not available" 2>/dev/null || echo "ERROR: jq not available" >&2
        return 1
    fi
    
    # Lösche Key mit jq (atomic write)
    jq "del(${json_path})" "$filepath" > "${filepath}.tmp" && mv "${filepath}.tmp" "$filepath"
    return $?
}




# ===========================================================================
# TODO: Ab hier ist das Modul noch nicht fertig implementiert!
# ===========================================================================

# ============================================================================
# CONFIG MANAGEMENT - NEUE ARCHITEKTUR
# ============================================================================

# Globale Service-Restart-Flags
disk2iso_restart_required=false
disk2iso_web_restart_required=false

# Config-Metadaten: Key → Handler:RestartService
# HINWEIS: MQTT/TMDB/MP3 Config werden nun über Modul-INI-Dateien verwaltet
#          (libmqtt.ini, libtmdb.ini, libaudio.ini)
declare -A CONFIG_HANDLERS=(
    ["DEFAULT_OUTPUT_DIR"]="set_default_output_dir:disk2iso"
    ["DDRESCUE_RETRIES"]="set_ddrescue_retries:none"
    ["USB_DRIVE_DETECTION_ATTEMPTS"]="set_usb_detection_attempts:none"
    ["USB_DRIVE_DETECTION_DELAY"]="set_usb_detection_delay:none"
)

# ============================================================================
# CONFIG SETTER FUNCTIONS
# ============================================================================

set_ddrescue_retries() {
    local value="$1"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo '{"success": false, "message": "Ungültiger Wert (Zahl erwartet)"}' >&2
        return 1
    fi
    
    /usr/bin/sed -i "s|^DDRESCUE_RETRIES=.*|DDRESCUE_RETRIES=${value}|" "$CONFIG_FILE" 2>/dev/null
    return $?
}

set_usb_detection_attempts() {
    local value="$1"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo '{"success": false, "message": "Ungültiger Wert (Zahl erwartet)"}' >&2
        return 1
    fi
    
    /usr/bin/sed -i "s|^USB_DRIVE_DETECTION_ATTEMPTS=.*|USB_DRIVE_DETECTION_ATTEMPTS=${value}|" "$CONFIG_FILE" 2>/dev/null
    return $?
}

set_usb_detection_delay() {
    local value="$1"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo '{"success": false, "message": "Ungültiger Wert (Zahl erwartet)"}' >&2
        return 1
    fi
    
    /usr/bin/sed -i "s|^USB_DRIVE_DETECTION_DELAY=.*|USB_DRIVE_DETECTION_DELAY=${value}|" "$CONFIG_FILE" 2>/dev/null
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

# Funktion: Lese Config-Wert aus disk2iso.conf (WRAPPER für Rückwärtskompatibilität)
# Parameter: $1 = Key (z.B. "DEFAULT_OUTPUT_DIR")
# Rückgabe: JSON mit {"success": true, "value": "..."} oder {"success": false, "message": "..."}
# NOTE: LEGACY WRAPPER - Nutze config_get_value_conf() direkt für neue Implementierungen
get_config_value() {
    local key="$1"
    
    if [[ -z "$key" ]]; then
        echo '{"success": false, "message": "Key erforderlich"}'
        return 1
    fi
    
    # Nutze neue unified config API
    local value
    value=$(config_get_value_conf "disk2iso" "$key") || {
        echo '{"success": false, "message": "Key nicht gefunden"}'
        return 1
    }
    
    # Escape JSON special characters
    value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
    echo "{\"success\": true, \"value\": \"${value}\"}"
    return 0
}

# Funktion: Aktualisiere einzelnen Config-Wert in config.sh (WRAPPER für Rückwärtskompatibilität)
# Parameter: $1 = Key (z.B. "DEFAULT_OUTPUT_DIR")
#            $2 = Value (z.B. "/media/iso")
#            $3 = Quote-Mode (DEPRECATED, wird ignoriert - Type Detection erfolgt automatisch)
# Rückgabe: JSON mit {"success": true} oder {"success": false, "message": "..."}
# NOTE: LEGACY WRAPPER - Nutze config_set_value_conf() direkt für neue Implementierungen
update_config_value() {
    local key="$1"
    local value="$2"
    local quote_mode="${3:-auto}"
    
    if [[ -z "$key" ]]; then
        echo '{"success": false, "message": "Key erforderlich"}'
        return 1
    fi
    
    config_validate_file || {
        echo '{"success": false, "message": "config.sh nicht gefunden"}'
        return 1
    }
    
    # Nutze neue unified config API (quote_mode wird ignoriert - automatische Type Detection)
    if config_set_value_conf "disk2iso" "$key" "$value" 2>/dev/null; then
        echo '{"success": true}'
        return 0
    else
        echo '{"success": false, "message": "Schreibfehler"}'
        return 1
    fi
}

# Funktion: Lese alle Config-Werte als JSON (WRAPPER für Web-API)
# Rückgabe: JSON mit allen Konfigurations-Werten
# NOTE: DEPRECATED - Nur noch für Core-Settings (disk2iso.conf)
#       Module lesen ihre Konfiguration aus eigenen INI-Dateien
#       Python-API sollte config_get_value_conf() oder config_get_value_ini() direkt nutzen
#       (Field-by-field, nicht als Batch)
get_all_config_values() {
    config_validate_file || {
        echo '{"success": false, "message": "disk2iso.conf nicht gefunden"}'
        return 1
    }
    
    # Lese nur Core-Settings aus disk2iso.conf (keine Modul-Settings mehr!)
    local output_dir=$(config_get_value_conf "disk2iso" "DEFAULT_OUTPUT_DIR" "" 2>/dev/null)
    local ddrescue_retries=$(config_get_value_conf "disk2iso" "DDRESCUE_RETRIES" "3" 2>/dev/null)
    local usb_attempts=$(config_get_value_conf "disk2iso" "USB_DRIVE_DETECTION_ATTEMPTS" "5" 2>/dev/null)
    local usb_delay=$(config_get_value_conf "disk2iso" "USB_DRIVE_DETECTION_DELAY" "10" 2>/dev/null)
    
    # Escape JSON special characters in strings
    output_dir=$(echo "$output_dir" | sed 's/\\/\\\\/g; s/"/\\"/g')
    
    # Erstelle JSON-Response (nur Core-Settings, Module lesen eigene INI-Dateien)
    echo "{\"success\": true, \"output_dir\": \"${output_dir}\", \"ddrescue_retries\": ${ddrescue_retries}, \"usb_detection_attempts\": ${usb_attempts}, \"usb_detection_delay\": ${usb_delay}}"
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
    
    config_validate_file || return 1
    
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
    # HINWEIS: MQTT/TMDB/MP3 werden über unified config API verwaltet
    declare -A config_mapping=(
        ["output_dir"]="DEFAULT_OUTPUT_DIR"
        ["ddrescue_retries"]="DDRESCUE_RETRIES"
        ["usb_detection_attempts"]="USB_DRIVE_DETECTION_ATTEMPTS"
        ["usb_detection_delay"]="USB_DRIVE_DETECTION_DELAY"
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

# ============================================================================
# END OF LIBCONFIG.SH
# ============================================================================
