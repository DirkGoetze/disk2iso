#!/bin/bash
################################################################################
# disk2iso
# Filepath: /usr/local/bin/disk2iso.sh
#
# Beschreibung:
#   Automatisches Rippen von CDs und DVDs beim Einlegen des Mediums.
#   Unterstützt verschiedene Kopiermethoden für optimale Ergebnisse:
#   - Video-DVDs: dvdbackup + mkisofs (erhält DVD-Struktur)
#   - Daten-CDs/DVDs: ddrescue (robust) oder dd (Fallback)
#
# Features:
#   - Automatische DVD-Typ-Erkennung (Video/Daten)
#   - Mehrere Kopiermethoden mit automatischer Auswahl
#   - MD5-Checksummen für Datenintegrität
#   - Fortschrittsanzeige mit pv (optional)
#   - Service-Modus für automatischen Betrieb
#   - Modulare Struktur mit lazy-loading
#
# Abhängigkeiten:
#   Pflicht: dd, md5sum, lsblk, isoinfo
#   Optional: ddrescue, dvdbackup, mkisofs/genisoimage, pv
#
################################################################################

# ============================================================================
# DEBUG-MODUS
# ============================================================================

# Debug-Modus aktivieren: DEBUG=1 ./disk2iso.sh
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x  # Trace-Modus: Zeigt jede ausgeführte Zeile
    PS4='+ ${BASH_SOURCE}:${LINENO}: '  # Zeigt Datei und Zeilennummer
fi

# Verbose-Modus: VERBOSE=1 ./disk2iso.sh
if [[ "${VERBOSE:-0}" == "1" ]]; then
    set -v  # Verbose: Zeigt Zeilen während sie gelesen werden
fi

# Strict-Modus für Entwicklung: STRICT=1 ./disk2iso.sh
if [[ "${STRICT:-0}" == "1" ]]; then
    set -euo pipefail  # Beende bei Fehlern, undefined vars, pipe failures
fi

# ============================================================================
# MODUL-LOADING (Service-sicher)
# ============================================================================

# Ermittle Script-Verzeichnis (funktioniert auch bei Symlinks und Service)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Lade Basis-Module
source "${SCRIPT_DIR}/disk2iso-lib/lang/messages.de"
source "${SCRIPT_DIR}/disk2iso-lib/config.sh"

# Lade Kern-Bibliotheken
source "${SCRIPT_DIR}/disk2iso-lib/lib-logging.sh"
source "${SCRIPT_DIR}/disk2iso-lib/lib-tools.sh"
source "${SCRIPT_DIR}/disk2iso-lib/lib-files.sh"
source "${SCRIPT_DIR}/disk2iso-lib/lib-folders.sh"
source "${SCRIPT_DIR}/disk2iso-lib/lib-common.sh"
source "${SCRIPT_DIR}/disk2iso-lib/lib-diskinfos.sh"
source "${SCRIPT_DIR}/disk2iso-lib/lib-drivestat.sh"

# ============================================================================
# HAUPTLOGIK - VEREINFACHT (nur Daten-Discs)
# ============================================================================

# Funktion zum Kopieren der CD/DVD/BD als ISO
copy_disc_to_iso() {
    # Initialisiere alle Dateinamen
    init_filenames
    
    # Stelle sicher dass Ausgabeverzeichnis existiert
    get_log_folder
    
    # Erstelle Log-Datei
    touch "$log_filename"
    
    log_message "Start Kopiervorgang: $disc_label -> $iso_filename"
    
    # Kopiere Daten-Disc mit dd
    if copy_data_disc; then
        # Berechne MD5-Checksumme
        if [[ -f "$iso_filename" ]]; then
            local md5sum=$(md5sum "$iso_filename" | cut -d' ' -f1)
            echo "$md5sum  $iso_basename" > "$md5_filename"
        fi
        
        log_message "Kopiervorgang erfolgreich: $iso_filename"
        cleanup_disc_operation "success"
        return 0
    else
        log_message "Kopiervorgang fehlgeschlagen: $disc_label"
        cleanup_disc_operation "failure"
        return 1
    fi
}

# Funktion zum Überwachen des CD/DVD-Laufwerks
# Erkennt Disc-Typ und kopiert entsprechend
monitor_cdrom() {
    log_message "Laufwerksüberwachung gestartet"
    
    while true; do
        if is_disc_inserted; then
            log_message "Medium eingelegt erkannt"
            
            # Warte bis Medium bereit ist (Spin-Up)
            if ! wait_for_disc_ready 3; then
                continue
            fi
            
            # Erkenne Disc-Typ
            detect_disc_type
            log_message "Disc-Typ erkannt: $disc_type"
            
            # Audio-CD Sonderbehandlung
            if [[ "$disc_type" == "audio-cd" ]]; then
                log_message "FEHLER: Audio-CD - Erstellung eines ISO-Image nicht möglich"
                
                # Werfe Medium aus und warte auf Entnahme
                eject "$CD_DEVICE" 2>/dev/null
                while is_disc_inserted; do
                    sleep 2
                done
                continue
            fi
            
            # Generiere Label
            get_disc_label
            log_message "Volume-Label: $disc_label"
            
            # Kopiere Disc als ISO
            copy_disc_to_iso
            
            # Warte bis Medium entfernt wurde
            log_message "Warte auf Medium-Entnahme..."
            while is_disc_inserted; do
                sleep 2
            done
        else
            # Warte bis Medium eingelegt wird
            log_message "Warte auf Medium..."
            while ! is_disc_inserted; do
                sleep 2
            done
        fi
    done
}

# ============================================================================
# START & SIGNAL-HANDLING
# ============================================================================

# Hauptfunktion
# Prüft Abhängigkeiten und startet Überwachung
main() {
    # Parse Kommandozeilenparameter
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            *)
                echo "Unbekannter Parameter: $1"
                echo "Verwendung: $0 -o|--output <Ausgabeverzeichnis>"
                exit 1
                ;;
        esac
    done
    
    # Prüfe ob OUTPUT_DIR gesetzt wurde
    if [[ -z "$OUTPUT_DIR" ]]; then
        echo "FEHLER: Kein Ausgabeverzeichnis angegeben"
        echo "Verwendung: $0 -o|--output <Ausgabeverzeichnis>"
        echo "Beispiel: $0 -o /mnt/hdd/nas/images"
        exit 1
    fi
    
    # Stelle sicher dass OUTPUT_DIR existiert
    if ! mkdir -p "$OUTPUT_DIR" 2>/dev/null; then
        echo "FEHLER: Kann Ausgabeverzeichnis nicht erstellen: $OUTPUT_DIR"
        exit 1
    fi
    
    log_message "disk2iso gestartet"
    log_message "Ausgabeverzeichnis: $OUTPUT_DIR"
    
    # Prüfe ob ein Optisches-Device angeschlossen ist (mit Retry für USB-Laufwerke)
    local max_attempts=5
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if detect_device; then
            log_message "Laufwerk erkannt: $CD_DEVICE"
            break
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_message "Suche USB-Laufwerk... (Versuch $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        else
            log_message "FEHLER: Kein Laufwerk erkannt nach $max_attempts Versuchen"
            exit 1
        fi
    done
    
    # Stelle sicher dass Device bereit ist (lädt sr_mod, wartet auf udev)
    if ! ensure_device_ready "$CD_DEVICE"; then
        log_message "Laufwerk nicht verfügbar: $CD_DEVICE"
        exit 1
    fi
    
    # Prüfe kritische Abhängigkeiten (müssen vorhanden sein)
    local missing_critical
    missing_critical=$(check_all_critical_tools)
    
    if [[ -n "$missing_critical" ]]; then
        log_message "Fehlende Tools: $missing_critical"
        exit 1
    fi
    
    # Starte Überwachung
    monitor_cdrom
}

# Signal-Handler für sauberes Service-Beenden
cleanup_service() {
    log_message "Service wird beendet"
    cleanup_disc_operation "interrupted"
    exit 0
}

trap cleanup_service SIGTERM SIGINT

# Skript starten falls direkt aufgerufen
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
