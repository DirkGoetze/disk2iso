#!/bin/bash
################################################################################
# File Management Library
# Filepath: disk2iso-lib/lib-files.sh
#
# Beschreibung:
#   Sammlung aller Funktionen zur Verwaltung von Dateinamen:
#   - Dateinamen-Bereinigung
#   - ISO-Dateinamen-Generierung
#   - MD5-Dateinamen-Ableitung
#   - LOG-Dateinamen-Ableitung
#   - Basename-Extraktion
#
# Quellen:
#   - functions.sh (sanitize_filename)
#   - lib-diskinfos.sh (get_iso_filename, get_md5_filename, get_log_filename, get_iso_basename)
#
# Konsolidiert: 13.12.2025
################################################################################

# ============================================================================
# FILENAME SANITIZATION
# Quelle: functions.sh
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
# Quelle: lib-diskinfos.sh
# ============================================================================

# Funktion zum Erstellen des ISO-Dateinamens
# Erstellt eindeutigen Dateinamen basierend auf Disc-Typ
# Setzt globale Variable: iso_filename
get_iso_filename() {
    # Erstelle Typ-spezifischen Unterordner
    local target_dir
    target_dir=$(get_type_subfolder "$disc_type")
    
    # Erstelle eindeutigen Dateinamen (disc_label bereits bereinigt)
    local base_filename="${disc_label}.iso"
    local full_path="${target_dir}/${base_filename}"
    
    # Prüfe ob Datei bereits existiert und füge Nummer hinzu
    local counter=1
    while [[ -f "$full_path" ]]; do
        base_filename="${disc_label}_${counter}.iso"
        full_path="${target_dir}/${base_filename}"
        ((counter++))
    done
    
    # Setze globale Variable
    iso_filename="$full_path"
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
# Setzt globale Variable: log_filename
get_log_filename() {
    # Ersetze .iso durch .log (iso_filename enthält bereits OUTPUT_DIR)
    log_filename="${iso_filename%.iso}.log"
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
