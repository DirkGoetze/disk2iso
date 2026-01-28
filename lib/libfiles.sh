#!/bin/bash
# =============================================================================
# File Management Library
# =============================================================================
# Filepath: lib/libfiles.sh
#
# Beschreibung:
#   Verwaltung von Dateinamen und Datei-Operationen
#   - Dateinamen-Bereinigung (sanitize_filename)
#   - ISO-Dateinamen-Generierung
#   - MD5/LOG-Dateinamen-Ableitung
#   - Basename-Extraktion
#
# -----------------------------------------------------------------------------
# Dependencies: Keine (nutzt nur Bash-Funktionen)
# -----------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.2.1
# Last Change: 2026-01-26 20:00
# =============================================================================

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

# ===========================================================================
# check_dependencies_files
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
check_dependencies_files() {
    # Files-Modul benötigt keine externen Tools
    # Verwendet nur Bash-Funktionen (basename, sed)
    return 0
}

# ============================================================================
# FILENAME SANITIZATION
# ============================================================================

# Funktion zur Bereinigung des Dateinamens
# Entfernt ungültige Zeichen für Dateinamen
sanitize_filename() {
    local filename="$1"
    # Entferne ungültige Zeichen und ersetze sie durch Unterstriche
    echo "$filename" | sed 's/[<>:"/\\|?*]/_/g' | sed 's/[[:space:]]/_/g' | sed 's/__*/_/g'
}

# ============================================================================
# FILENAME GENERATION
# ============================================================================

# ===========================================================================
# get_unique_iso_path
# ---------------------------------------------------------------------------
# Funktion.: Finde eindeutigen Dateinamen mit Auto-Increment
# Parameter: $1 = target_dir (Zielverzeichnis)
#            $2 = base_name (Basis-Name ohne .iso)
#            $3 = existing_file (optional, existierende Datei die umbenannt wird)
# Rückgabe.: Eindeutiger Pfad (mit _1, _2 etc. falls nötig)
# ===========================================================================
get_unique_iso_path() {
    local target_dir="$1"
    local base_name="$2"
    local existing_file="${3:-}"
    
    local base_filename="${base_name}.iso"
    local full_path="${target_dir}/${base_filename}"
    
    # Prüfe ob Datei bereits existiert und füge Nummer hinzu
    local counter=1
    while [[ -f "$full_path" ]] && [[ "$full_path" != "$existing_file" ]]; do
        base_filename="${base_name}_${counter}.iso"
        full_path="${target_dir}/${base_filename}"
        ((counter++))
    done
    
    echo "$full_path"
}

# ============================================================================
# FILENAME INITIALIZATION
# ============================================================================

# ===========================================================================
# init_filenames
# ---------------------------------------------------------------------------
# Funktion.: Initialisiere alle Dateinamen basierend auf disc_label und disc_type
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beschr...: Setzt DISC_INFO Felder: iso_filename, md5_filename, log_filename,
#            iso_basename, temp_pathname
#            Nutzt discinfo_get_label() und discinfo_get_type()
#            WICHTIG: Muss NACH Metadata-Auswahl aufgerufen werden!
# ===========================================================================
init_filenames() {
    # Prüfe ob disc_label und disc_type bereits gesetzt sind
    local disc_label
    local disc_type
    
    if ! disc_label=$(discinfo_get_label); then
        log_error \"init_filenames: disc_label nicht gesetzt!\"
        return 1
    fi
    
    if ! disc_type=$(discinfo_get_type); then
        log_error \"init_filenames: disc_type nicht gesetzt!\"
        return 1
    fi
    
    # 1. ISO-Dateinamen generieren
    local target_dir
    target_dir=$(get_type_subfolder \"$disc_type\")
    local iso_path=$(get_unique_iso_path \"$target_dir\" \"$disc_label\")
    discinfo_set_iso_filename \"$iso_path\"
    
    # 2. MD5-Dateinamen ableiten
    local md5_path=\"${iso_path%.iso}.md5\"
    discinfo_set_md5_filename \"$md5_path\"
    
    # 3. Log-Dateinamen ableiten (im separaten log/ Verzeichnis)
    local base_name=$(basename \"${iso_path%.iso}\")
    local log_path=\"$(get_path_log)/${base_name}.log\"
    discinfo_set_log_filename \"$log_path\"
    
    # 4. ISO-Basisname extrahieren
    local iso_base=$(basename \"$iso_path\")
    discinfo_set_iso_basename \"$iso_base\"
    
    # 5. Temp-Pathname erstellen (falls nicht bereits vorhanden)
    local temp_path
    if ! temp_path=$(discinfo_get_temp_pathname); then
        temp_path=$(get_temp_pathname)
        discinfo_set_temp_pathname \"$temp_path\"
    fi
    
    # Setze alte globale Variablen für Rückwärtskompatibilität (DEPRECATED)
    iso_filename=\"$iso_path\"
    md5_filename=\"$md5_path\"
    log_filename=\"$log_path\"
    iso_basename=\"$iso_base\"
    temp_pathname=\"$temp_path\"
    
    log_debug \"init_filenames: ISO='$iso_path', MD5='$md5_path', LOG='$log_path', TEMP='$temp_path'\"
    return 0
}

# ============================================================================
# MODULE INI PATH HELPER
# ============================================================================

# ===========================================================================
# get_module_ini_path
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt vollständigen Pfad zur Modul-INI-Datei
# Parameter: $1 = module_name (z.B. "tmdb", "audio", "metadata")
# Rückgabe.: Vollständiger Pfad zur INI-Datei
# Beispiel.: get_module_ini_path "tmdb"
#            → "/opt/disk2iso/conf/libtmdb.ini"
# Nutzt....: get_conf_dir() aus libfolders.sh
# ===========================================================================
get_module_ini_path() {
    local module_name="$1"
    
    if [[ -z "$module_name" ]]; then
        return 1
    fi
    
    echo "$(get_conf_dir)/lib${module_name}.ini"
}

# ============================================================================
# ENDE DER FILE MANAGEMENT LIBRARY
# ============================================================================
