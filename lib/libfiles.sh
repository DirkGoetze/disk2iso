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

# Funktion zum Erstellen des ISO-Dateinamens
# Erstellt eindeutigen Dateinamen basierend auf Disc-Typ
# Setzt globale Variable: iso_filename
# Funktion zum Finden eines eindeutigen Dateinamens
# Args: Verzeichnis, Basis-Name (ohne .iso), [optionale existierende Datei]
# Return: Eindeutiger Pfad (mit _1, _2 etc. falls nötig)
get_unique_iso_path() {
    local target_dir="$1"
    local base_name="$2"
    local existing_file="${3:-}"  # Optional: Existierende Datei die umbenannt wird
    
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

get_iso_filename() {
    # Erstelle Typ-spezifischen Unterordner
    local target_dir
    target_dir=$(get_type_subfolder "$disc_type")
    
    # Nutze Hilfsfunktion für eindeutigen Dateinamen
    iso_filename=$(get_unique_iso_path "$target_dir" "$disc_label")
}

# Funktion zum Erstellen des MD5-Dateinamens
# Leitet MD5-Dateinamen vom ISO-Dateinamen ab
# Setzt globale Variable: md5_filename
get_md5_filename() {
    # Ersetze .iso durch .md5 (iso_filename enthält bereits OUTPUT_DIR)
    md5_filename="${iso_filename%.iso}.md5"
}

# Funktion zum Erstellen des LOG-Dateinamens
# Leitet LOG-Dateinamen vom ISO-Dateinamen ab
# Log-Dateien werden im separaten log/ Verzeichnis gespeichert
# Setzt globale Variable: log_filename
get_log_filename() {
    # Extrahiere nur den Dateinamen ohne Pfad
    local base_name=$(basename "${iso_filename%.iso}")
    
    # Erstelle Pfad im log/ Verzeichnis
    log_filename="$(get_path_log)/${base_name}.log"
}

# Funktion zum Extrahieren des ISO-Basisnamens
# Setzt globale Variable: iso_basename
get_iso_basename() {
    iso_basename=$(basename "$iso_filename")
}

# ============================================================================
# FILENAME INITIALIZATION
# ============================================================================

# Funktion zur Initialisierung aller Dateinamen
# Ruft alle Dateinamen-Generierungsfunktionen in der richtigen Reihenfolge auf
# Setzt globale Variablen: iso_filename, md5_filename, log_filename, iso_basename, temp_pathname
init_filenames() {
    get_iso_filename
    get_md5_filename
    get_log_filename
    get_iso_basename
    get_temp_pathname
}

# ============================================================================
# ENDE DER FILE MANAGEMENT LIBRARY
# ============================================================================
