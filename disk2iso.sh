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
# MODUL-LOADING (Service-sicher)
# ============================================================================

# Ermittle Script-Verzeichnis (funktioniert auch bei Symlinks und Service)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Lade Basis-Module
source "${SCRIPT_DIR}/lang/messages.de"
source "${SCRIPT_DIR}/config.sh"

# Lade Kern-Bibliotheken
source "${SCRIPT_DIR}/lib-logging.sh"
source "${SCRIPT_DIR}/lib-tools.sh"
source "${SCRIPT_DIR}/lib-files.sh"
source "${SCRIPT_DIR}/lib-folders.sh"
source "${SCRIPT_DIR}/lib-common.sh"
source "${SCRIPT_DIR}/lib-diskinfos.sh"
source "${SCRIPT_DIR}/lib-drivestat.sh"

# ============================================================================
# HAUPTLOGIK
# ============================================================================

# Funktion zum Kopieren der CD/DVD als ISO
# Wählt automatisch beste Kopiermethode basierend auf DVD-Typ
copy_disc_to_iso() {
    # Initialisiere alle Dateinamen
    init_filenames
    
    # Stelle sicher dass Ausgabeverzeichnis existiert
    get_log_folder
    
    # Erstelle Log-Datei
    touch "$log_filename"
    
    log_message "$MSG_COPY_START"
    log_message "$MSG_COPY_LABEL $disk_label"
    log_message "$MSG_COPY_TARGET $iso_filename"
    
    # Wähle Kopiermethode basierend auf Verfügbarkeit und Medium-Typ
    local copy_success=false
    
    log_message "$MSG_STEP_4"
    
    # Strategie 1: Audio-CDs (kein ISO, sondern MP3-Ripping)
    if [[ "$disc_type" == "audio-cd" ]] && command -v cdparanoia >/dev/null 2>&1 && command -v lame >/dev/null 2>&1; then
        # Lazy-Load Audio-CD Modul
        log_message "$MSG_MODULE_AUDIO"
        [[ -z "$(type -t copy_audio_cd)" ]] && source "${SCRIPT_DIR}/lib-cd.sh"
        
        log_message "$MSG_STEP_5"
        if copy_audio_cd; then
            copy_success=true
            
            # Optional: Benachrichtigung senden
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "CD/DVD Ripper" "Audio-CD erfolgreich gerippt: $disk_label"
            fi
        fi
    fi
    
    # Strategie 2: Für Video-Blu-rays nutze MakeMKV (ISO-Backup)
    if [[ "$disc_type" == "video-bluray" ]] && command -v makemkvcon >/dev/null 2>&1; then
        # Lazy-Load Blu-ray-Video Modul
        log_message "$MSG_MODULE_VIDEO_BLURAY"
        [[ -z "$(type -t copy_bluray_video)" ]] && source "${SCRIPT_DIR}/lib-bluray.sh"
        
        log_message "$MSG_STEP_5"
        if copy_bluray_video; then
            copy_success=true
        fi
    fi
    
    # Strategie 3: Für Video-DVDs bevorzuge dvdbackup + mkisofs
    if [[ "$disc_type" == "video-dvd" ]] && command -v dvdbackup >/dev/null 2>&1; then
        # Lazy-Load DVD-Video Modul
        log_message "$MSG_MODULE_VIDEO_DVD"
        [[ -z "$(type -t copy_dvd_video)" ]] && source "${SCRIPT_DIR}/lib-dvd.sh"
        
        log_message "$MSG_STEP_5"
        if copy_dvd_video; then
            copy_success=true
        fi
    fi
    
    # Strategie 4 & 5: Daten-Disc inkl. Daten-Blu-rays (nutzt ddrescue oder dd)
    if [[ "$copy_success" == false ]]; then
        # copy_with_ddrescue, copy_with_dd, copy_data_disc sind bereits in lib-common.sh geladen
        log_message "$MSG_MODULE_DATA"
        
        log_message "$MSG_STEP_5"
        if copy_data_disc; then
            copy_success=true
        fi
    fi
    
    # Ergebnis verarbeiten
    if [[ "$copy_success" == true ]]; then
        log_message "$MSG_STEP_6_SUCCESS"
        log_message "$MSG_COPY_COMPLETE $iso_filename"
        
        # Berechne MD5-Checksumme (nur wenn ISO-Datei existiert)
        if [[ -f "$iso_filename" ]]; then
            local md5sum=$(md5sum "$iso_filename" | cut -d' ' -f1)
            echo "$md5sum  $iso_basename" > "$md5_filename"
            log_message "$MSG_MD5_CREATED $md5sum"
        fi
        
        # Optional: Benachrichtigung senden (falls notify-send verfügbar)
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "$MSG_NOTIFY_TITLE" "$MSG_NOTIFY_DISC_SUCCESS $disk_label"
        fi
        
        log_message "$MSG_STEP_7"
        cleanup_disc_operation "success"
        log_message "$MSG_MONITOR_READY"
        
    else
        log_message "$MSG_STEP_6_FAILED"
        log_message "$MSG_COPY_ERROR $disk_label"
        
        log_message "$MSG_STEP_7"
        cleanup_disc_operation "failure"
        log_message "$MSG_MONITOR_READY"
        
        return 1
    fi
}

# Funktion zum Überwachen des CD/DVD-Laufwerks
# Implementiert automatischen Workflow: Erkennung → Kopieren → Auswerfen
monitor_cdrom() {
    log_message "$MSG_MONITOR_STARTED"
    
    while true; do
        log_message "$MSG_CHECK_DRIVE_STATUS"
        
        if is_disc_inserted; then
            log_message "$MSG_MEDIA_PROCESSING"
            
            # Warte bis Medium bereit ist (Spin-Up)
            if ! wait_for_disc_ready 5; then
                log_message "$MSG_MEDIA_NOT_READY"
                continue
            fi
            
            log_message "$MSG_START_DETECTION"
            
            # Lade Detection-Module (lazy loading)
            [[ -z "$(type -t detect_cd_audio)" ]] && source "${SCRIPT_DIR}/lib-cd.sh"
            [[ -z "$(type -t detect_dvd_video)" ]] && source "${SCRIPT_DIR}/lib-dvd.sh"
            [[ -z "$(type -t detect_bd_video)" ]] && source "${SCRIPT_DIR}/lib-bluray.sh"
            
            # Durchlaufe alle Detection-Funktionen
            local disc_detected=false
            for detect_func in detect_cd_audio detect_dvd_video detect_bd_video detect_cd_rom detect_dvd_rom detect_bd_rom; do
                if [[ "$(type -t $detect_func)" == "function" ]]; then
                    if $detect_func; then
                        log_message "$MSG_TYPE_DETECTED $disc_type (Label: $disc_label)"
                        disc_detected=true
                        break
                    fi
                fi
            done
            
            if [[ "$disc_detected" == false ]]; then
                log_message "$MSG_TYPE_UNKNOWN"
                log_message "$MSG_WAIT_STATUS_CHANGE"
                wait_for_disc_change 10
                continue
            fi
            
            log_message "$MSG_START_COPY_FOR_TYPE $disc_type..."
            
            if copy_disc_to_iso; then
                log_message "$MSG_COPY_SUCCESS_COMPLETE"
            else
                log_message "$MSG_COPY_FAILED_COMPLETE"
            fi
            
            log_message "$MSG_EJECT_DISC"
            if command -v eject >/dev/null 2>&1; then
                eject "$CD_DEVICE" 2>/dev/null && log_message "$MSG_DISC_EJECTED"
            fi
            
            # Warte auf Statusänderung (Medium entfernt oder Schublade geschlossen)
            log_message "$MSG_WAIT_STATUS_CHANGE"
            wait_for_disc_change 5
            
        else
            log_message "$MSG_NO_MEDIA_INSERTED"
            log_message "$MSG_WAIT_STATUS_TRAY"
            
            wait_for_disc_change 10
            
            # Wenn Laufwerk geschlossen wurde, kurz warten und dann neu prüfen
            if is_drive_closed; then
                log_message "$MSG_DRIVE_CLOSED_CHECK"
                sleep 2
            fi
        fi
        
        log_message "$MSG_NEW_CHECK"
    done
}

# ============================================================================
# START & SIGNAL-HANDLING
# ============================================================================

# Hauptfunktion
# Prüft Abhängigkeiten und startet Überwachung
main() {
    log_message "$MSG_STARTUP"
    
    # Dynamische Device-Erkennung
    log_message "$MSG_SEARCH_DRIVE"
    local detected_device=$(find_optical_device)
    
    # Prüfe ob Device gefunden wurde
    if [[ -z "$detected_device" ]]; then
        log_message "$MSG_DRIVE_NOT_FOUND"
        echo "$MSG_DRIVE_USB_TIP"
        exit 1
    fi
    
    # Setze globale Variable
    CD_DEVICE="$detected_device"
    log_message "$MSG_DRIVE_FOUND $CD_DEVICE"
    
    # Stelle sicher dass Device bereit ist (lädt sr_mod, wartet auf udev)
    if ! ensure_device_ready "$CD_DEVICE"; then
        log_message "$MSG_DRIVE_NOT_AVAILABLE $CD_DEVICE"
        exit 1
    fi
    
    # Prüfe kritische Abhängigkeiten (müssen vorhanden sein)
    local missing_critical
    missing_critical=$(check_all_critical_tools)
    
    if [[ -n "$missing_critical" ]]; then
        log_message "$MSG_DEPS_CRITICAL_MISSING $missing_critical"
        log_message "$MSG_DEPS_INSTALL_HINT"
        exit 1
    fi
    
    # Prüfe optionale Tools (nur loggen, keine Installation)
    local missing_optional
    missing_optional=$(check_all_optional_tools)
    
    if [[ -n "$missing_optional" ]]; then
        log_message "$MSG_DEPS_OPTIONAL_MISSING $missing_optional"
        log_message "$MSG_DEPS_OPTIONAL_HINT"
    fi
    
    # Starte Überwachung
    monitor_cdrom
}

# Signal-Handler für sauberes Service-Beenden
# Wird bei SIGTERM/SIGINT aufgerufen
cleanup_service() {
    log_message "$MSG_SERVICE_SHUTDOWN"
    
    # Falls gerade Kopiervorgang läuft, aufräumen
    cleanup_disc_operation "interrupted"
    
    log_message "$MSG_SERVICE_EXIT"
    exit 0
}

trap cleanup_service SIGTERM SIGINT

# Skript starten falls direkt aufgerufen
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
