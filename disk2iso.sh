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
# Löse Symlinks auf, um den echten Pfad zu bekommen
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Lade Basis-Module
source "${SCRIPT_DIR}/disk2iso-lib/config.sh"

# Lade Kern-Bibliotheken (IMMER erforderlich)
source "${SCRIPT_DIR}/disk2iso-lib/lib-logging.sh"
source "${SCRIPT_DIR}/disk2iso-lib/lib-files.sh"
source "${SCRIPT_DIR}/disk2iso-lib/lib-folders.sh"
source "${SCRIPT_DIR}/disk2iso-lib/lib-diskinfos.sh"
source "${SCRIPT_DIR}/disk2iso-lib/lib-drivestat.sh"
source "${SCRIPT_DIR}/disk2iso-lib/lib-common.sh"

# Prüfe Kern-Abhängigkeiten (kritisch - Abbruch bei Fehler)
if ! check_common_dependencies; then
    echo "ABBRUCH: Kritische Abhängigkeiten fehlen"
    exit 1
fi

log_message "Kern-Module geladen und geprüft"

# ============================================================================
# OPTIONALE MODULE MIT DEPENDENCY-CHECKS
# ============================================================================

# Audio-CD Support (optional)
AUDIO_CD_SUPPORT=false
if [[ -f "${SCRIPT_DIR}/disk2iso-lib/lib-cd.sh" ]]; then
    source "${SCRIPT_DIR}/disk2iso-lib/lib-cd.sh"
    
    if check_audio_cd_dependencies; then
        AUDIO_CD_SUPPORT=true
        log_message "✓ Audio-CD Support aktiviert"
    else
        log_message "✗ Audio-CD Support deaktiviert (fehlende Tools)"
    fi
else
    log_message "✗ Audio-CD Support nicht installiert (lib-cd.sh fehlt)"
fi

# Video-DVD Support (optional)
VIDEO_DVD_SUPPORT=false
if [[ -f "${SCRIPT_DIR}/disk2iso-lib/lib-dvd.sh" ]]; then
    source "${SCRIPT_DIR}/disk2iso-lib/lib-dvd.sh"
    
    if check_video_dvd_dependencies; then
        VIDEO_DVD_SUPPORT=true
        log_message "✓ Video-DVD Support aktiviert"
    else
        log_message "✗ Video-DVD Support deaktiviert (fehlende Tools)"
    fi
else
    log_message "✗ Video-DVD Support nicht installiert (lib-dvd.sh fehlt)"
fi

# Blu-ray Support (optional)
BLURAY_SUPPORT=false
if [[ -f "${SCRIPT_DIR}/disk2iso-lib/lib-bluray.sh" ]]; then
    source "${SCRIPT_DIR}/disk2iso-lib/lib-bluray.sh"
    
    if check_bluray_dependencies; then
        BLURAY_SUPPORT=true
        log_message "✓ Blu-ray Support aktiviert"
    else
        log_message "✗ Blu-ray Support deaktiviert (fehlende Tools)"
    fi
else
    log_message "✗ Blu-ray Support nicht installiert (lib-bluray.sh fehlt)"
fi

# ============================================================================
# HAUPTLOGIK - VEREINFACHT (nur Daten-Discs)
# ============================================================================

# Funktion zum Auswählen der besten Kopiermethode
# Gibt Methodennamen zurück: "audio-cd", "dvdbackup", "ddrescue" oder "dd"
select_copy_method() {
    local disc_type="$1"
    
    # Für Audio-CDs
    if [[ "$disc_type" == "audio-cd" ]]; then
        if [[ "$AUDIO_CD_SUPPORT" == true ]]; then
            echo "audio-cd"
            return 0
        else
            log_message "WARNUNG: Audio-CD erkannt, aber kein Audio-CD Support installiert"
            log_message "Fallback: Kopiere als Daten-Disc mit dd (kein Audio-Ripping)"
            echo "dd"
            return 0
        fi
    fi
    
    # Für Video-DVDs
    if [[ "$disc_type" == "dvd-video" ]]; then
        if [[ "$VIDEO_DVD_SUPPORT" == true ]]; then
            # Priorität 1: dvdbackup (entschlüsselt, schnell)
            if command -v dvdbackup >/dev/null 2>&1 && command -v genisoimage >/dev/null 2>&1; then
                echo "dvdbackup"
                return 0
            fi
        fi
        
        # Priorität 2: ddrescue (verschlüsselt, mittelschnell)
        if command -v ddrescue >/dev/null 2>&1; then
            echo "ddrescue"
            return 0
        fi
        
        # Priorität 3: dd (verschlüsselt, langsam)
        echo "dd"
        return 0
    
    # Für Blu-ray Video: MakeMKV (entschlüsselt) oder ddrescue/dd (verschlüsselt)
    elif [[ "$disc_type" == "bd-video" ]]; then
        if [[ "$BLURAY_SUPPORT" == true ]]; then
            # Priorität 1: MakeMKV (entschlüsselt, langsam)
            if command -v makemkvcon >/dev/null 2>&1 && command -v genisoimage >/dev/null 2>&1; then
                echo "makemkv"
                return 0
            fi
            
            # Priorität 2: ddrescue (verschlüsselt, schneller)
            if command -v ddrescue >/dev/null 2>&1; then
                echo "bluray-ddrescue"
                return 0
            fi
        else
            # Ohne Blu-ray Support: Nutze Standard-Methoden
            if command -v ddrescue >/dev/null 2>&1; then
                echo "ddrescue"
                return 0
            fi
        fi
        
        # Priorität 3: dd (verschlüsselt, langsam)
        echo "dd"
        return 0
    
    # Für Daten-Discs: ddrescue oder dd
    else
        if command -v ddrescue >/dev/null 2>&1; then
            echo "ddrescue"
            return 0
        else
            echo "dd"
            return 0
        fi
    fi
}

# Funktion zum Kopieren der CD/DVD/BD als ISO
copy_disc_to_iso() {
    # Initialisiere alle Dateinamen
    init_filenames
    
    # Stelle sicher dass Ausgabeverzeichnis existiert
    get_log_folder
    
    # Erstelle Log-Datei
    touch "$log_filename"
    
    log_message "Start Kopiervorgang: $disc_label -> $iso_filename"
    
    # Wähle Kopiermethode basierend auf Disc-Typ und verfügbaren Tools
    local method=$(select_copy_method "$disc_type")
    
    # Logge gewählte Methode
    case "$method" in
        audio-cd) log_message "Gewählte Methode: Audio-CD Ripping (cdparanoia + lame)" ;;
        dvdbackup) log_message "Gewählte Methode: dvdbackup (entschlüsselt)" ;;
        makemkv) log_message "Gewählte Methode: MakeMKV (Blu-ray entschlüsselt)" ;;
        bluray-ddrescue) log_message "Gewählte Methode: ddrescue (Blu-ray verschlüsselt, robust)" ;;
        ddrescue) log_message "Gewählte Methode: ddrescue (robust)" ;;
        dd) log_message "Gewählte Methode: dd (Basis-Methode)" ;;
    esac
    
    # Kopiere mit gewählter Methode (KEIN Fallback bei Fehler)
    local copy_success=false
    
    case "$method" in
        audio-cd)
            if [[ "$AUDIO_CD_SUPPORT" == true ]] && declare -f copy_audio_cd >/dev/null 2>&1; then
                if copy_audio_cd; then
                    copy_success=true
                fi
            else
                log_message "FEHLER: Audio-CD Support nicht verfügbar"
                return 1
            fi
            ;;
        dvdbackup)
            if [[ "$VIDEO_DVD_SUPPORT" == true ]] && declare -f copy_video_dvd >/dev/null 2>&1; then
                if copy_video_dvd; then
                    copy_success=true
                fi
            else
                log_message "FEHLER: Video-DVD Support nicht verfügbar"
                return 1
            fi
            ;;
        makemkv)
            if [[ "$BLURAY_SUPPORT" == true ]] && declare -f copy_bluray_makemkv >/dev/null 2>&1; then
                if copy_bluray_makemkv; then
                    copy_success=true
                fi
            else
                log_message "FEHLER: Blu-ray Support (MakeMKV) nicht verfügbar"
                return 1
            fi
            ;;
        bluray-ddrescue)
            if [[ "$BLURAY_SUPPORT" == true ]] && declare -f copy_bluray_ddrescue >/dev/null 2>&1; then
                if copy_bluray_ddrescue; then
                    copy_success=true
                fi
            else
                log_message "FEHLER: Blu-ray Support (ddrescue) nicht verfügbar"
                return 1
            fi
            ;;
        ddrescue)
            if [[ "$disc_type" == "dvd-video" ]] || [[ "$disc_type" == "bd-video" ]]; then
                if copy_video_dvd_ddrescue; then
                    copy_success=true
                fi
            else
                if copy_data_disc_ddrescue; then
                    copy_success=true
                fi
            fi
            ;;
        dd)
            if copy_data_disc; then
                copy_success=true
            fi
            ;;
    esac
    
    # Verarbeite Ergebnis
    if $copy_success; then
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
            
            # Generiere Label (für Audio-CDs wird Label in copy_audio_cd() gesetzt)
            if [[ "$disc_type" != "audio-cd" ]]; then
                get_disc_label
                log_message "Volume-Label: $disc_label"
            fi
            
            # Kopiere Disc als ISO
            copy_disc_to_iso
            
            # Warte bis Medium entfernt wurde (OHNE ständig zu prüfen während Kopiervorgang läuft)
            log_message "Warte auf Medium-Entnahme..."
            sleep 5  # Kurze Pause vor erster Prüfung
            while is_disc_inserted; do
                sleep 5  # Längere Pause zwischen Prüfungen (statt 2 Sekunden)
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
    
    # Abhängigkeiten wurden bereits beim Modul-Loading geprüft
    # Kern-Abhängigkeiten: check_common_dependencies()
    # Audio-CD: check_audio_cd_dependencies() (optional)
    # Video-DVD/BD: check_video_dvd_dependencies() (optional)
    
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
