#!/bin/bash
# =============================================================================
# Settings Management Library
# =============================================================================
# Filepath: lib/libsettings.sh
#
# Beschreibung:
#   Standalone Settings-Management für disk2iso Konfiguration
#   Verwaltet Settings in drei Formaten:
#   - .conf Files (disk2iso.conf) - Core-Settings im bash Key=Value Format
#   - .ini Files (Modul-Settings) - INI Format mit [sections]
#   - .json Files (API-Daten) - JSON Format für status.json, progress.json
#
#
# -----------------------------------------------------------------------------
# Dependencies: Keine (nutzt nur awk, sed, grep - POSIX-Standard)
# -----------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.3.0
# Last Change: 2026-02-07
# =============================================================================

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

# ===========================================================================
# settings_check_dependencies
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
settings_check_dependencies() {
    # Lade Sprachdatei für dieses Modul (libsettings)
    liblogging_load_language_file "settings"
    
    # Prüfe kritische Abhängigkeit: Existenz der Settings-Datei
    settings_validate_file || return 1
    
    # Settings-Modul nutzt POSIX-Standard-Tools (awk, sed, grep)
    # Diese sind auf jedem Linux-System verfügbar
    return 0
}

# ===========================================================================
# SETTINGS GETTER/SETTER FUNCTIONS 'disk2iso.conf'
# ===========================================================================
# Diese Funktionen lesen und schreiben Konfigurationswerte in der
# Datei disk2iso.conf im conf/ Verzeichnis.
# ---------------------------------------------------------------------------
# Globale Flags für Lazy Initialization -------------------------------------
_SETTINGS_FILE_VALIDATED=false                 # Settings-Datei wurde geprüft
_SETTINGS_DEPENDENCIES_VALIDATED=false         # Dependencies geprüft (get_module_ini_path verfügbar)
_SETTINGS_SAVE_DEFAULT_CONF=false              # Flag für rekursiven Default-Write (verhindert Endlosschleife)
_SETTINGS_SAVE_DEFAULT_INI=false               # Flag für rekursiven Default-Write (verhindert Endlosschleife)

# Globaler Pfad zur Konfigurations-Datei
CONFIG_FILE="${SCRIPT_DIR}/conf/disk2iso.conf"

# ===========================================================================
# settings_validate_file
# ---------------------------------------------------------------------------
# Funktion.: Prüft einmalig ob die disk2iso Konfigurationsdatei existiert
# Parameter: keine
# Rückgabe.: 0 = Datei existiert
# .........  1 = Datei fehlt (kritischer Fehler)
# Hinweis..: Nutzt Lazy Initialization - wird nur einmal pro Session geprüft
# .........  Wird automatisch von settings_check_dependencies() aufgerufen
# ===========================================================================
settings_validate_file() {
    #-- Lazy Initialization: Nur einmal pro Session prüfen ------------------
    if [[ "$_SETTINGS_FILE_VALIDATED" == false ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            log_error "$MSG_SETTINGS_CONFIG_FILE_NOT_FOUND: $settings_file"
            return 1
        fi
        _SETTINGS_FILE_VALIDATED=true
    fi
    return 0
}

# ===========================================================================
# settings_validate_dependencies
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
settings_validate_dependencies() {
    #-- Bereits validiert? --------------------------------------------------
    [[ "$_SETTINGS_DEPENDENCIES_VALIDATED" == "true" ]] && return 0
    
    #-- Prüfe ob folders_get_conf_dir() verfügbar ist (aus libfolders.sh) ---
    if ! type -t folders_get_conf_dir &>/dev/null; then
        log_error "$MSG_SETTINGS_MODULE_LIBFOLDERS_UNAVAILABLE"
        return 1
    fi

    #-- Prüfe ob get_module_ini_path() verfügbar ist (aus libfiles.sh) ------
    if ! type -t get_module_ini_path &>/dev/null; then
        log_error "$MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE"
        return 1
    fi
    
    #-- Dependencies OK -----------------------------------------------------
    _SETTINGS_DEPENDENCIES_VALIDATED=true
    return 0
}

# ===========================================================================
# settings_get_output_dir
# ---------------------------------------------------------------------------
# Funktion.: Lese OUTPUT_DIR aus disk2iso.conf oder verwende Fallback
# Parameter: keine
# Rückgabe.: OUTPUT_DIR Pfad (stdout, ohne trailing slash)
# .........  Return-Code: 0 = Erfolg, 1 = Fehler
# Beispiel.: output_dir=$(settings_get_output_dir)
# Hinweis..: - Besondere Bedeutung dieser Funktion, da OUTPUT_DIR essentiell
# .........  - für die Funktionsweise von disk2iso ist. Daher hier separat
# .........  - implementiert, um Abhängigkeiten zu minimieren.
# .........  - Liest DEFAULT_OUTPUT_DIR oder OUTPUT_DIR aus Konfiguration
# .........  - Entfernt trailing slash für konsistente Rückgabe
# ===========================================================================
settings_get_output_dir() {
    local output_dir=""
    
    #-- Stelle sicher dass Settings-Datei validiert wurde --------------------
    settings_validate_file || return 1
    
    #-- Lese OUTPUT_DIR aus Settings -----------------------------------------
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

# ===========================================================================
# settings_get_language
# ---------------------------------------------------------------------------
# Funktion.: Lese Web-Interface Sprache aus disk2iso.conf
# Parameter: keine
# Rückgabe.: Sprachcode (de, en, fr, es) auf stdout
# .........  Return-Code: 0 = Erfolg, 1 = Fehler (nutzt "de" als Fallback)
# Beispiel.: lang=$(settings_get_language)
# Hinweis..: Liest WEB_LANGUAGE aus conf/disk2iso.conf, Fallback auf "de"
# ===========================================================================
settings_get_language() {
    local language=""
    
    #-- Stelle sicher dass Settings-Datei validiert wurde --------------------
    settings_validate_file || return 1
    
    #-- Lese WEB_LANGUAGE aus Settings ---------------------------------------
    language=$(/usr/bin/grep -E '^WEB_LANGUAGE=' "$CONFIG_FILE" 2>/dev/null | /usr/bin/sed 's/^WEB_LANGUAGE=//;s/^"\(.*\)"$/\1/')
    
    #-- Fallback auf "de" wenn nicht gesetzt ---------------------------------
    if [[ -z "$language" ]]; then
        language="de"
        # Self-Healing: Schreibe Default
        settings_set_language "$language" 2>/dev/null
    fi
    
    #-- Validiere Sprache (muss de, en, fr oder es sein) --------------------
    case "$language" in
        de|en|fr|es)
            echo "$language"
            return 0
            ;;
        *)
            # Ungültige Sprache - Fallback
            echo "de"
            return 0
            ;;
    esac
}

# ===========================================================================
# settings_set_language
# ---------------------------------------------------------------------------
# Funktion.: Setze Web-Interface Sprache in disk2iso.conf
# Parameter: $1 = language (de, en, fr, es)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: settings_set_language "en"
# Hinweis..: Schreibt WEB_LANGUAGE in conf/disk2iso.conf
# .........  Validiert Eingabe (nur de, en, fr, es erlaubt)
# ===========================================================================
settings_set_language() {
    local language="$1"
    
    #-- Stelle sicher dass Settings-Datei validiert wurde --------------------
    settings_validate_file || return 1
    
    #-- Validiere Sprache -----------------------------------------------------
    case "$language" in
        de|en|fr|es)
            # OK
            ;;
        *)
            log_error "Invalid language: $language (must be de, en, fr, or es)" 2>/dev/null
            return 1
            ;;
    esac
    
    #-- Prüfe ob WEB_LANGUAGE bereits existiert -------------------------------
    if /usr/bin/grep -q '^WEB_LANGUAGE=' "$CONFIG_FILE" 2>/dev/null; then
        # Update existing value
        /usr/bin/sed -i "s|^WEB_LANGUAGE=.*|WEB_LANGUAGE=\"${language}\"|" "$CONFIG_FILE"
    else
        # Add new value nach LANGUAGE Zeile
        /usr/bin/sed -i "/^readonly LANGUAGE=/a WEB_LANGUAGE=\"${language}\"" "$CONFIG_FILE"
    fi
    
    return $?
}

# ============================================================================
# UNIFIED SETTINGS API - SINGLE VALUE OPERATIONS (.conf FORMAT)
# ============================================================================
# Format: .conf = Simple Key=Value (kein Section-Header)
# Beispiel: disk2iso.conf
#   OUTPUT_DIR="/media/iso"
#   MQTT_PORT=1883
#   MQTT_ENABLED=true

# ===========================================================================
# settings_get_value_conf
# ---------------------------------------------------------------------------
# Funktion.: Lese einzelnen Wert aus .conf Datei
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "disk2iso")
#            $2 = key (z.B. "OUTPUT_DIR")
#            $3 = default (optional, Fallback wenn Key nicht gefunden)
# Rückgabe.: 0 = Erfolg (Wert oder Default), 1 = Fehler (Key fehlt, kein Default)
# Ausgabe..: Value (stdout), Quotes werden automatisch entfernt
# Beispiel.: output_dir=$(settings_get_value_conf "disk2iso" "OUTPUT_DIR" "/opt/disk2iso/output")
# ===========================================================================
settings_get_value_conf() {
    #-- Parameter einlesen --------------------------------------------------
    local module="$1"
    local key="$2"
    local default="${3:-}"
    
    #-- Parameter-Validierung -----------------------------------------------
    if [[ -z "$module" ]]; then
        log_error "$MSG_SETTINGS_MODULE_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$key" ]]; then
        log_error "$MSG_SETTINGS_KEY_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_KEY_MISSING" >&2
        return 1
    fi
    
    #-- Pfad-Resolution über zentrale Funktion ------------------------------
    local filepath
    filepath=$(get_module_conf_path "$module") || {
        log_error "$MSG_SETTINGS_PATH_RESOLUTION_FAILED: $module" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_PATH_RESOLUTION_FAILED" >&2
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
        # Self-Healing: Default-Wert in Settings schreiben (falls nicht in Schleife)
        if [[ "$_SETTINGS_SAVE_DEFAULT_CONF" == false ]]; then
            _SETTINGS_SAVE_DEFAULT_CONF=true
            
            # Schreibe Default in Settings-Datei
            if settings_set_value_conf "$module" "$key" "$default" 2>/dev/null; then
                # Lese Wert erneut zur Bestätigung (rekursiver Aufruf)
                _SETTINGS_SAVE_DEFAULT_CONF=false
                settings_get_value_conf "$module" "$key" "$default"
                return $?
            else
                # Schreibfehler - gebe Default trotzdem zurück
                _SETTINGS_SAVE_DEFAULT_CONF=false
                log_warning "$MSG_SETTINGS_DEFAULT_SAVE_FAILED: ${module}.${key}=${default}" 2>/dev/null
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
# settings_set_value_conf
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
# Beispiel.: settings_set_value_conf "disk2iso" "MQTT_PORT" "1883"
#            → MQTT_PORT=1883
#            settings_set_value_conf "disk2iso" "MQTT_BROKER" "192.168.1.1"
#            → MQTT_BROKER="192.168.1.1"
# ===========================================================================
settings_set_value_conf() {
    local module="$1"
    local key="$2"
    local value="$3"
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "$MSG_SETTINGS_MODULE_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$key" ]]; then
        log_error "$MSG_SETTINGS_KEY_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_KEY_MISSING" >&2
        return 1
    fi
    
    # Pfad-Resolution über zentrale Funktion
    local filepath
    filepath=$(get_module_conf_path "$module") || {
        log_error "$MSG_SETTINGS_PATH_RESOLUTION_FAILED: $module" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_PATH_RESOLUTION_FAILED" >&2
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
# settings_del_value_conf
# ---------------------------------------------------------------------------
# Funktion.: Lösche einzelnen Wert aus .conf Datei
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "disk2iso")
#            $2 = key
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: settings_del_value_conf "disk2iso" "OLD_KEY"
# ===========================================================================
settings_del_value_conf() {
    local module="$1"
    local key="$2"
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "$MSG_SETTINGS_MODULE_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$key" ]]; then
        log_error "$MSG_SETTINGS_KEY_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_KEY_MISSING" >&2
        return 1
    fi
    
    # Pfad-Resolution über zentrale Funktion
    local filepath
    filepath=$(get_module_conf_path "$module") || {
        log_error "$MSG_SETTINGS_PATH_RESOLUTION_FAILED: $module" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_PATH_RESOLUTION_FAILED" >&2
        return 1
    }
    
    # Lösche Zeile mit sed (in-place)
    /usr/bin/sed -i "/^${key}=/d" "$filepath" 2>/dev/null
    return $?
}

# ============================================================================
# UNIFIED SETTINGS API - SINGLE VALUE OPERATIONS (.ini FORMAT)
# ============================================================================
# Format: .ini = Sectioned Key=Value
# Beispiel: libaudio.ini
#   [dependencies]
#   optional=cdparanoia,lame,genisoimage
#   [metadata]
#   version=1.2.0

# ===========================================================================
# settings_get_value_ini
# ---------------------------------------------------------------------------
# Funktion.: Lese einzelnen Wert aus .ini Datei (KERN-IMPLEMENTIERUNG)
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section (z.B. "dependencies")
#            $3 = key (z.B. "optional")
#            $4 = default (optional, Fallback wenn Key nicht gefunden)
# Rückgabe.: 0 = Erfolg (Wert oder Default), 1 = Fehler (Key fehlt, kein Default)
# Ausgabe..: Value (stdout)
# Beispiel.: tools=$(settings_get_value_ini "audio" "dependencies" "optional" "")
# ===========================================================================
settings_get_value_ini() {
    #-- Parameter einlesen --------------------------------------------------
    local module="$1"
    local section="$2"
    local key="$3"
    local default="${4:-}"
    
    #-- Validiere Dependencies ----------------------------------------------
    if ! type -t get_module_ini_path &>/dev/null; then
        log_error "$MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE" >&2
        return 1
    fi
    
    #-- Hole Pfad zur INI-Datei via get_module_ini_path() -------------------
    local filepath=$(get_module_ini_path "$module") || {
        if [[ -n "$default" ]]; then
            echo "$default"
            return 0
        fi
        log_error "$MSG_SETTINGS_MODULE_INI_NOT_FOUND: $module" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_INI_NOT_FOUND: $module" >&2
        return 1
    }
    
    #-- Validierung der Parameter -------------------------------------------
    if [[ -z "$module" ]]; then
        log_error "$MSG_SETTINGS_MODULE_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$section" ]]; then
        log_error "$MSG_SETTINGS_SECTION_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_SECTION_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$key" ]]; then
        log_error "$MSG_SETTINGS_KEY_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_KEY_MISSING" >&2
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
        if [[ "$_SETTINGS_SAVE_DEFAULT_INI" == false ]]; then
            _SETTINGS_SAVE_DEFAULT_INI=true
            
            # Schreibe Default in INI-Datei
            if settings_set_value_ini "$module" "$section" "$key" "$default" 2>/dev/null; then
                # Lese Wert erneut zur Bestätigung (rekursiver Aufruf)
                _SETTINGS_SAVE_DEFAULT_INI=false
                settings_get_value_ini "$module" "$section" "$key" "$default"
                return $?
            else
                # Schreibfehler - gebe Default trotzdem zurück
                _SETTINGS_SAVE_DEFAULT_INI=false
                log_warning "$MSG_SETTINGS_DEFAULT_SAVE_FAILED: ${module}.[${section}].${key}=${default}" 2>/dev/null
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
# settings_set_value_ini
# ---------------------------------------------------------------------------
# Funktion.: Schreibe/Aktualisiere einzelnen Wert in .ini Datei (KERN-IMPLEMENTIERUNG)
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section
#            $3 = key
#            $4 = value
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: INI-Format speichert immer als String, keine Type-Detection
# Beispiel.: settings_set_value_ini "audio" "dependencies" "optional" "cdparanoia,lame"
# ===========================================================================
settings_set_value_ini() {
    local module="$1"
    local section="$2"
    local key="$3"
    local value="$4"
    
    # Validiere Dependencies (Lazy Initialization)
    if ! type -t get_module_ini_path &>/dev/null; then
        log_error "$MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE" >&2
        return 1
    fi
    
    # Hole Pfad zur INI-Datei via get_module_ini_path()
    local filepath
    filepath=$(get_module_ini_path "$module") || {
        log_error "$MSG_SETTINGS_MODULE_INI_NOT_FOUND: $module" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_INI_NOT_FOUND: $module" >&2
        return 1
    }
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "$MSG_SETTINGS_MODULE_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$section" ]]; then
        log_error "$MSG_SETTINGS_SECTION_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_SECTION_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$key" ]]; then
        log_error "$MSG_SETTINGS_KEY_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_KEY_MISSING" >&2
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
# settings_del_value_ini
# ---------------------------------------------------------------------------
# Funktion.: Lösche einzelnen Key aus .ini Datei (KERN-IMPLEMENTIERUNG)
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section
#            $3 = key
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: settings_del_value_ini "audio" "dependencies" "old_key"
# ===========================================================================
settings_del_value_ini() {
    local module="$1"
    local section="$2"
    local key="$3"
    
    # Validiere Dependencies (Lazy Initialization)
    if ! type -t get_module_ini_path &>/dev/null; then
        log_error "$MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE" >&2
        return 1
    fi
    
    # Hole Pfad zur INI-Datei via get_module_ini_path()
    local filepath
    filepath=$(get_module_ini_path "$module") || {
        log_error "$MSG_SETTINGS_MODULE_INI_NOT_FOUND: $module" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_INI_NOT_FOUND: $module" >&2
        return 1
    }
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "$MSG_SETTINGS_MODULE_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$section" ]]; then
        log_error "$MSG_SETTINGS_SECTION_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_SECTION_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$key" ]]; then
        log_error "$MSG_SETTINGS_KEY_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_KEY_MISSING" >&2
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
# UNIFIED SETTINGS API - ARRAY OPERATIONS (.ini FORMAT)
# ============================================================================
# Arrays werden als komma-separierte Werte gespeichert
# Beispiel: tools=cdparanoia,lame,genisoimage

# ===========================================================================
# settings_get_array_ini
# ---------------------------------------------------------------------------
# Funktion.: Lese komma-separierte Liste aus .ini Datei als Bash-Array
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section (z.B. "dependencies")
#            $3 = key (z.B. "optional")
#            $4 = default (optional, komma-separiert wenn Key nicht gefunden)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Ausgabe..: Array-Elemente (eine Zeile pro Element)
# Beispiel.: mapfile -t tools < <(settings_get_array_ini "audio" "dependencies" "optional")
#            → tools=("cdparanoia" "lame" "genisoimage")
# Hinweis..: Nutzt settings_get_value_ini() intern
# ===========================================================================
settings_get_array_ini() {
    local module="$1"
    local section="$2"
    local key="$3"
    local default="${4:-}"
    
    # Lese komma-separierte Liste
    local value
    value=$(settings_get_value_ini "$module" "$section" "$key" "$default") || return 1
    
    if [[ -z "$value" ]]; then
        return 1
    fi
    
    # Split by Komma, trim Whitespace, ausgeben (eine Zeile pro Element)
    echo "$value" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
    return 0
}

# ===========================================================================
# settings_set_array_ini
# ---------------------------------------------------------------------------
# Funktion.: Schreibe Bash-Array als komma-separierte Liste in .ini Datei
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section
#            $3 = key
#            $4+ = values (alle weiteren Parameter werden als Array-Elemente behandelt)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: settings_set_array_ini "audio" "dependencies" "optional" "cdparanoia" "lame" "genisoimage"
#            → optional=cdparanoia,lame,genisoimage
#            
#            # Mit Array-Expansion:
#            tools=("cdparanoia" "lame" "genisoimage")
#            settings_set_array_ini "audio" "dependencies" "optional" "${tools[@]}"
# Hinweis..: Nutzt settings_set_value_ini() intern
# ===========================================================================
settings_set_array_ini() {
    local module="$1"
    local section="$2"
    local key="$3"
    shift 3
    
    # Validierung
    if [[ $# -eq 0 ]]; then
        log_error "$MSG_SETTINGS_NO_VALUES_PROVIDED" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_NO_VALUES_PROVIDED" >&2
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
    settings_set_value_ini "$module" "$section" "$key" "$value"
}

# ===========================================================================
# settings_del_array_ini
# ---------------------------------------------------------------------------
# Funktion.: Lösche Array-Key aus .ini Datei (Wrapper)
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section
#            $3 = key
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: settings_del_array_ini "audio" "dependencies" "optional"
# Hinweis..: Wrapper um settings_del_value_ini() - Arrays werden wie Werte gelöscht
# ===========================================================================
settings_del_array_ini() {
    local module="$1"
    local section="$2"
    local key="$3"
    
    settings_del_value_ini "$module" "$section" "$key"
}

# ============================================================================
# UNIFIED SETTINGS API - SECTION OPERATIONS (.ini FORMAT)
# ============================================================================
# Operationen auf ganzen INI-Sektionen

# ===========================================================================
# settings_get_section_ini
# ---------------------------------------------------------------------------
# Funktion.: Lese alle Key=Value Paare einer INI-Sektion
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section (z.B. "metadata")
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Ausgabe..: Key=Value Paare (eine Zeile pro Entry)
# Beispiel.: settings_get_section_ini "audio" "metadata"
#            → "name=Audio Ripper"
#            → "version=1.2.0"
# Hinweis..: Ignoriert Kommentare und Leerzeilen
# ===========================================================================
settings_get_section_ini() {
    local module="$1"
    local section="$2"
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "$MSG_SETTINGS_MODULE_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$section" ]]; then
        log_error "$MSG_SETTINGS_SECTION_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_SECTION_MISSING" >&2
        return 1
    fi
    
    # Validiere Dependencies
    if ! type -t get_module_ini_path &>/dev/null; then
        log_error "$MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE" >&2
        return 1
    fi
    
    # Hole Pfad zur INI-Datei
    local filepath
    filepath=$(get_module_ini_path "$module") || {
        log_error "$MSG_SETTINGS_MODULE_INI_NOT_FOUND: $module" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_INI_NOT_FOUND: $module" >&2
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
# settings_set_section_ini
# ---------------------------------------------------------------------------
# Funktion.: Erstelle/Überschreibe komplette INI-Sektion mit Key=Value Paaren
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section
#            $3+ = key=value Paare (alle weiteren Parameter)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: settings_set_section_ini "audio" "metadata" "name=Audio Ripper" "version=1.2.0"
# Hinweis..: Löscht existierende Sektion komplett und erstellt sie neu
# ===========================================================================
settings_set_section_ini() {
    local module="$1"
    local section="$2"
    shift 2
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "$MSG_SETTINGS_MODULE_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$section" ]]; then
        log_error "$MSG_SETTINGS_SECTION_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_SECTION_MISSING" >&2
        return 1
    fi
    
    if [[ $# -eq 0 ]]; then
        log_error "$MSG_SETTINGS_NO_KEYVALUE_PAIRS" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_NO_KEYVALUE_PAIRS" >&2
        return 1
    fi
    
    # Validiere Dependencies
    if ! type -t get_module_ini_path &>/dev/null; then
        log_error "$MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE" >&2
        return 1
    fi
    
    # Hole Pfad zur INI-Datei
    local filepath
    filepath=$(get_module_ini_path "$module") || {
        log_error "$MSG_SETTINGS_MODULE_INI_NOT_FOUND: $module" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_INI_NOT_FOUND: $module" >&2
        return 1
    }
    
    # Lösche existierende Sektion falls vorhanden
    settings_del_section_ini "$module" "$section" 2>/dev/null
    
    # Erstelle neue Sektion
    echo "" >> "$filepath"
    echo "[${section}]" >> "$filepath"
    
    # Füge alle Key=Value Paare hinzu
    for pair in "$@"; do
        # Validiere Format key=value
        if [[ "$pair" =~ ^[^=]+=.* ]]; then
            echo "$pair" >> "$filepath"
        else
            log_warning "$MSG_SETTINGS_INVALID_KEYVALUE_PAIR: $pair" 2>/dev/null
        fi
    done
    
    return 0
}

# ===========================================================================
# settings_del_section_ini
# ---------------------------------------------------------------------------
# Funktion.: Lösche komplette INI-Sektion inklusive aller Einträge
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: settings_del_section_ini "audio" "metadata"
# Hinweis..: Entfernt Section-Header und alle zugehörigen Key=Value Zeilen
# ===========================================================================
settings_del_section_ini() {
    local module="$1"
    local section="$2"
    
    # Validierung
    if [[ -z "$module" ]]; then
        log_error "$MSG_SETTINGS_MODULE_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$section" ]]; then
        log_error "$MSG_SETTINGS_SECTION_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_SECTION_MISSING" >&2
        return 1
    fi
    
    # Validiere Dependencies
    if ! type -t get_module_ini_path &>/dev/null; then
        log_error "$MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_GET_MODULE_INI_PATH_UNAVAILABLE" >&2
        return 1
    fi
    
    # Hole Pfad zur INI-Datei
    local filepath
    filepath=$(get_module_ini_path "$module") || {
        log_error "$MSG_SETTINGS_MODULE_INI_NOT_FOUND: $module" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_MODULE_INI_NOT_FOUND: $module" >&2
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
# settings_count_section_entries_ini
# ---------------------------------------------------------------------------
# Funktion.: Zähle Anzahl der Einträge in einer INI-Sektion
# Parameter: $1 = module (Modulname ohne Suffix, z.B. "audio")
#            $2 = section (z.B. "metadata")
# Rückgabe.: Anzahl der Einträge (0-N) via stdout
# Beispiel.: count=$(settings_count_section_entries_ini "audio" "dependencies")
#            → "3"
# Hinweis..: Zählt nur Key=Value Zeilen, keine Kommentare/Leerzeilen
# ===========================================================================
settings_count_section_entries_ini() {
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
# UNIFIED SETTINGS API - JSON OPERATIONS
# ============================================================================
# JSON-Dateien für API-Status und Metadaten (api/ Verzeichnis)
# Beispiel: api/status.json, api/progress.json

# ===========================================================================
# settings_get_value_json
# ---------------------------------------------------------------------------
# Funktion.: Lese einzelnen Wert aus JSON-Datei
# Parameter: $1 = json_file (Dateiname ohne Pfad, z.B. "status")
#            $2 = json_path (jq-kompatibel, z.B. ".disc_type" oder ".metadata.title")
#            $3 = default (optional, Fallback wenn Key nicht gefunden)
# Rückgabe.: 0 = Erfolg (Wert oder Default), 1 = Fehler (Key fehlt, kein Default)
# Ausgabe..: Value (stdout, als JSON-String)
# Beispiel.: disc_type=$(settings_get_value_json "status" ".disc_type" "unknown")
# Hinweis..: Benötigt jq (wird bei Dependency-Check validiert)
# ===========================================================================
settings_get_value_json() {
    local json_file="$1"
    local json_path="$2"
    local default="${3:-}"
    
    # Validierung
    if [[ -z "$json_file" ]]; then
        log_error "$MSG_SETTINGS_JSON_FILENAME_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_JSON_FILENAME_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$json_path" ]]; then
        log_error "$MSG_SETTINGS_JSON_PATH_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_JSON_PATH_MISSING" >&2
        return 1
    fi
    
    # Pfad-Resolution: api/${json_file}.json
    local filepath="${SCRIPT_DIR}/api/${json_file}.json"
    
    # Prüfe ob Datei existiert
    if [[ ! -f "$filepath" ]]; then
        if [[ -n "$default" ]]; then
            echo "$default"
            return 0
        fi
        log_error "$MSG_SETTINGS_JSON_FILE_NOT_FOUND: $filepath" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_JSON_FILE_NOT_FOUND" >&2
        return 1
    fi
    
    # Prüfe ob jq verfügbar ist
    if ! command -v jq &>/dev/null; then
        log_error "$MSG_SETTINGS_JQ_NOT_AVAILABLE" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_JQ_NOT_AVAILABLE" >&2
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
# settings_set_value_json
# ---------------------------------------------------------------------------
# Funktion.: Schreibe einzelnen Wert in JSON-Datei
# Parameter: $1 = json_file (Dateiname ohne Pfad, z.B. "status")
#            $2 = json_path (jq-kompatibel, z.B. ".disc_type" oder ".metadata.title")
#            $3 = value (String, Number oder Boolean)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: settings_set_value_json "status" ".disc_type" "audio-cd"
#            settings_set_value_json "progress" ".percentage" "75"
# Hinweis..: Erstellt Datei falls nicht vorhanden, erstellt verschachtelte Pfade
# ===========================================================================
settings_set_value_json() {
    local json_file="$1"
    local json_path="$2"
    local value="$3"
    
    # Validierung
    if [[ -z "$json_file" ]]; then
        log_error "$MSG_SETTINGS_JSON_FILENAME_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_JSON_FILENAME_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$json_path" ]]; then
        log_error "$MSG_SETTINGS_JSON_PATH_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_JSON_PATH_MISSING" >&2
        return 1
    fi
    
    # Pfad-Resolution: api/${json_file}.json
    local filepath="$${SCRIPT_DIR}/api/${json_file}.json"
    
    # Prüfe ob jq verfügbar ist
    if ! command -v jq &>/dev/null; then
        log_error "$MSG_SETTINGS_JQ_NOT_AVAILABLE" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_JQ_NOT_AVAILABLE" >&2
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
# settings_del_value_json
# ---------------------------------------------------------------------------
# Funktion.: Lösche einzelnen Key aus JSON-Datei
# Parameter: $1 = json_file (Dateiname ohne Pfad, z.B. "status")
#            $2 = json_path (jq-kompatibel, z.B. ".disc_type" oder ".metadata.title")
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beispiel.: settings_del_value_json "status" ".disc_type"
# ===========================================================================
settings_del_value_json() {
    local json_file="$1"
    local json_path="$2"
    
    # Validierung
    if [[ -z "$json_file" ]]; then
        log_error "$MSG_SETTINGS_JSON_FILENAME_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_JSON_FILENAME_MISSING" >&2
        return 1
    fi
    
    if [[ -z "$json_path" ]]; then
        log_error "$MSG_SETTINGS_JSON_PATH_MISSING" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_JSON_PATH_MISSING" >&2
        return 1
    fi
    
    # Pfad-Resolution: api/${json_file}.json
    local filepath="${SCRIPT_DIR}/api/${json_file}.json"
    
    # Prüfe ob Datei existiert
    if [[ ! -f "$filepath" ]]; then
        return 0
    fi
    
    # Prüfe ob jq verfügbar ist
    if ! command -v jq &>/dev/null; then
        log_error "$MSG_SETTINGS_JQ_NOT_AVAILABLE" 2>/dev/null || echo "ERROR: $MSG_SETTINGS_JQ_NOT_AVAILABLE" >&2
        return 1
    fi
    
    # Lösche Key mit jq (atomic write)
    jq "del(${json_path})" "$filepath" > "${filepath}.tmp" && mv "${filepath}.tmp" "$filepath"
    return $?
}

# ============================================================================
# END OF LIBSETTINGS.SH
# ============================================================================
