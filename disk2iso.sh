#!/bin/bash
################################################################################
# disk2iso v1.2.0
# Filepath: /usr/local/bin/disk2iso.sh
#
# Beschreibung:
#   Automatisches Archivieren optischer Medien als ISO-Images.
#   Unterstützt verschiedene Kopiermethoden für optimale Ergebnisse:
#   - Audio-CDs: cdparanoia + lame (MP3 mit MusicBrainz)
#   - Video-DVDs: dvdbackup + genisoimage (entschlüsselt)
#   - Blu-rays: ddrescue (robust) oder dd (Fallback)
#   - Daten-Discs: ddrescue (robust) oder dd (Fallback)
#
# Features:
#   - Automatische DVD-Typ-Erkennung (Video/Daten)
#   - Mehrere Kopiermethoden mit automatischer Auswahl
#   - MD5-Checksummen für Datenintegrität
#   - Fortschrittsanzeige mit pv (optional)
#   - Service-Modus für automatischen Betrieb
#   - Modulare Struktur mit lazy-loading

# ============================================================================
# STATE MACHINE CONSTANTS
# ============================================================================

readonly STATE_INITIALIZING="initializing"
readonly STATE_WAITING_FOR_DRIVE="waiting_for_drive"
readonly STATE_DRIVE_DETECTED="drive_detected"
readonly STATE_WAITING_FOR_MEDIA="waiting_for_media"
readonly STATE_MEDIA_DETECTED="media_detected"
readonly STATE_ANALYZING="analyzing"
readonly STATE_WAITING_FOR_METADATA="waiting_for_metadata"
readonly STATE_COPYING="copying"
readonly STATE_COMPLETED="completed"
readonly STATE_ERROR="error"
readonly STATE_WAITING_FOR_REMOVAL="waiting_for_removal"
readonly STATE_IDLE="idle"

# Polling-Intervalle (Sekunden)
readonly POLL_DRIVE_INTERVAL=20
readonly POLL_MEDIA_INTERVAL=2
readonly POLL_REMOVAL_INTERVAL=5

# Globale State-Variable
CURRENT_STATE="$STATE_INITIALIZING"

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
source "${SCRIPT_DIR}/conf/disk2iso.conf"
source "${SCRIPT_DIR}/lib/libconfig.sh"

# Setze OUTPUT_DIR bereits hier (wichtig für get_tmp_mount() in libdiskinfos.sh)
# Verhindert dass Mount-Points im Root / landen wenn OUTPUT_DIR noch nicht gesetzt ist
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"


# Lade Sprachdateien für Hauptskript
load_module_language "disk2iso"

# ============================================================================
# PRÜFE KERN-ABHÄNGIGKEITEN (kritisch - Abbruch bei Fehler)
# ============================================================================
# Alle Core-Module werden nach einander geladen und müssen ihre Abhängigkeiten 
# erfüllen, sonst kann disk2iso nicht funktionieren. 

source "${SCRIPT_DIR}/lib/libconfig.sh"
if ! check_dependencies_config; then
    echo "FEHLER: Config-Modul Abhängigkeiten nicht erfüllt" >&2
    exit 1
fi

source "${SCRIPT_DIR}/lib/libfiles.sh"
if ! check_dependencies_files; then
    echo "FEHLER: Files-Modul Abhängigkeiten nicht erfüllt" >&2
    exit 1
fi

source "${SCRIPT_DIR}/lib/liblogging.sh"
if ! check_dependencies_logging; then
    echo "FEHLER: Logging-Modul Abhängigkeiten nicht erfüllt" >&2
    exit 1
fi

source "${SCRIPT_DIR}/lib/libfolders.sh"
if ! check_dependencies_folders; then
    log_error "Folders-Modul Abhängigkeiten nicht erfüllt"
    exit 1
fi

source "${SCRIPT_DIR}/lib/libapi.sh"
if ! check_dependencies_api; then
    log_error "API-Modul Abhängigkeiten nicht erfüllt"
    exit 1
fi

source "${SCRIPT_DIR}/lib/libintegrity.sh"
if ! check_dependencies_integrity; then
    log_error "Integrity-Modul Abhängigkeiten nicht erfüllt"
    exit 1
fi

source "${SCRIPT_DIR}/lib/libdiskinfos.sh"
if ! check_dependencies_diskinfos; then
    log_error "Disk-Information-Modul Abhängigkeiten nicht erfüllt"
    exit 1
fi

source "${SCRIPT_DIR}/lib/libdrivestat.sh"
if ! check_dependencies_drivestat; then
    log_error "Drive-Status-Modul Abhängigkeiten nicht erfüllt"
    exit 1
fi

source "${SCRIPT_DIR}/lib/libsysteminfo.sh"
if ! check_dependencies_systeminfo; then
    log_error "$MSG_ABORT_SYSTEMINFO_DEPENDENCIES"
    exit 1
fi

source "${SCRIPT_DIR}/lib/libcommon.sh"
if ! check_dependencies_common; then
    log_error "$MSG_ABORT_CRITICAL_DEPENDENCIES"
    exit 1
fi

log_info "$MSG_CORE_MODULES_LOADED"

# ============================================================================
# OPTIONALE MODULE MIT DEPENDENCY-CHECKS
# ============================================================================
# Audio-CD Support (optional)
if [[ -f "${SCRIPT_DIR}/lib/libaudio.sh" ]]; then
    source "${SCRIPT_DIR}/lib/libaudio.sh"
    check_dependencies_audio  # Setzt SUPPORT_AUDIO=true bei Erfolg
fi

# Video-DVD Support (optional)
if [[ -f "${SCRIPT_DIR}/lib/libdvd.sh" ]]; then
    source "${SCRIPT_DIR}/lib/libdvd.sh"
    check_dependencies_dvd  # Setzt SUPPORT_DVD=true bei Erfolg
fi

# Video-Bluray Support (optional)
if [[ -f "${SCRIPT_DIR}/lib/libbluray.sh" ]]; then
    source "${SCRIPT_DIR}/lib/libbluray.sh"
    check_dependencies_bluray  # Setzt SUPPORT_BLURAY=true bei Erfolg
fi

# Metadata Framework nur laden wenn mindestens ein Disc-Type unterstützt wird
if is_audio_ready || is_dvd_ready || is_bluray_ready; then
    
    if [[ -f "${SCRIPT_DIR}/lib/libmetadata.sh" ]]; then
        source "${SCRIPT_DIR}/lib/libmetadata.sh"
        check_dependencies_metadata  # Setzt SUPPORT_METADATA=true bei Erfolg
        
        # Lade Provider nur wenn Framework verfügbar
        if [[ "$SUPPORT_METADATA" == "true" ]]; then
            # MusicBrainz Provider nur wenn Audio-CD Support vorhanden
            if is_audio_ready && 
               [[ -f "${SCRIPT_DIR}/lib/libmusicbrainz.sh" ]]; then
                source "${SCRIPT_DIR}/lib/libmusicbrainz.sh"
                check_dependencies_musicbrainz  # Setzt SUPPORT_MUSICBRAINZ=true bei Erfolg
            fi
            
            # TMDB Provider nur wenn DVD/BD Support vorhanden
            if { is_dvd_ready || is_bluray_ready; } && 
               [[ -f "${SCRIPT_DIR}/lib/libtmdb.sh" ]]; then
                source "${SCRIPT_DIR}/lib/libtmdb.sh"
                check_dependencies_tmdb  # Setzt SUPPORT_TMDB=true bei Erfolg
            fi
        fi
    fi
fi

# MQTT Support (externes Plugin - siehe: https://github.com/DirkGoetze/disk2iso-mqtt)
if [[ -f "${SCRIPT_DIR}/lib/libmqtt.sh" ]]; then
    source "${SCRIPT_DIR}/lib/libmqtt.sh"
    check_dependencies_mqtt  # Setzt SUPPORT_MQTT=true bei Erfolg
    
    # mqtt_init_connection prüft selbst ob MQTT bereit ist (Support + Aktiviert + Initialisiert)
    if is_mqtt_ready; then
        mqtt_init_connection  # Sendet Initial-Messages wenn Broker erreichbar
    fi
fi

# ============================================================================
# HAUPTLOGIK - DELEGIERT AN KOPIER-MODULE
# ============================================================================

# ===========================================================================
# copy_disc_to_iso()
# ---------------------------------------------------------------------------
# Funktion.: Kopiert die eingelegte CD/DVD/BD in ein ISO-Image. Dazu wird
# .........  zunächst versucht basierend auf dem erkannten Disc-Typ an 
# .........  eines der spezialisierte Module zu delegieren (Audio-CD, 
# .........  Video-DVD, Blu-ray). Wenn kein spezialisierter Typ erkannt
# .........  wurde, wird die Disc als Daten-Disc mit dd kopiert.
# Parameter.: Keine
# Rückgabe.: 0 bei Erfolg, sonst Fehlercode
# ===========================================================================
copy_disc_to_iso() {
    #-- Ermittle Disc-Typ ---------------------------------------------------
    local disc_type="$(discinfo_get_type)"
    
    #-- Audio-CD: Delegiere an libaudio.sh ----------------------------------
    if [[ "$disc_type" == "audio-cd" ]] && is_audio_ready; then
        copy_audio_cd
        return $?
    fi
    
    #-- Video-DVD: Delegiere an libdvd.sh -----------------------------------
    if [[ "$disc_type" == "dvd-video" ]] && is_dvd_ready; then
        copy_video_dvd
        return $?
    fi
    
    #-- Blu-ray: Delegiere an libbluray.sh ----------------------------------
    if [[ "$disc_type" == "bd-video" ]] && is_bluray_ready; then
        copy_bluray_disk
        return $?
    fi
    
    #-- Daten-Disc oder kein passendes Kopiermodul aktiv -------------------
    #-- libcommon.sh wählt beste Methode (ddrescue oder dd) ----------------
    copy_data_disc
    return $?
}

# TODO: Ab hier ist das Modul noch nicht fertig implementiert!


# Funktion zum Überwachen des CD/DVD-Laufwerks
# Erkennt Disc-Typ und kopiert entsprechend
# State transition handler
transition_to_state() {
    local new_state="$1"
    local msg="${2:-}"
    
    CURRENT_STATE="$new_state"
    
    # Log state change
    if [[ -n "$msg" ]]; then
        log_info "$msg"
    fi
    
    # Update API status via helper function (delegiert State→Status Mapping)
    # Observer Pattern: api_update_from_state() triggert automatisch MQTT-Updates
    local disc_label="$(discinfo_get_label 2>/dev/null || echo '')"
    local disc_type="$(discinfo_get_type 2>/dev/null || echo '')"
    api_update_from_state "$new_state" "$disc_label" "$disc_type" "${msg:-}"
}

# State Machine Main Loop
run_state_machine() {
    log_info "$MSG_STATE_MACHINE_STARTED"
    
    transition_to_state "$STATE_INITIALIZING" "Initialisiere Service..."
    
    # Sammle initiale System-Informationen
    if declare -f collect_system_information >/dev/null 2>&1; then
        collect_system_information
    fi
    
    # Hauptschleife - läuft endlos
    while true; do
        case "$CURRENT_STATE" in
            "$STATE_INITIALIZING")
                # Initialisierung abgeschlossen, suche nach Laufwerk
                transition_to_state "$STATE_WAITING_FOR_DRIVE" "Suche nach optischem Laufwerk..."
                ;;
                
            "$STATE_WAITING_FOR_DRIVE")
                # Prüfe ob Laufwerk verfügbar ist
                if detect_device; then
                    transition_to_state "$STATE_DRIVE_DETECTED" "$MSG_DRIVE_DETECTED $CD_DEVICE"
                else
                    # Kein Laufwerk gefunden - warte und versuche erneut
                    sleep "$POLL_DRIVE_INTERVAL"
                fi
                ;;
                
            "$STATE_DRIVE_DETECTED")
                # Laufwerk gefunden - stelle sicher dass es bereit ist
                if ensure_device_ready "$CD_DEVICE"; then
                    # Aktualisiere System-Info mit Laufwerk-Informationen
                    if declare -f collect_system_information >/dev/null 2>&1; then
                        collect_system_information
                    fi
                    transition_to_state "$STATE_WAITING_FOR_MEDIA" "$MSG_DRIVE_MONITORING_STARTED"
                else
                    # Device nicht bereit - zurück zum Suchen
                    transition_to_state "$STATE_WAITING_FOR_DRIVE" "$MSG_DRIVE_NOT_AVAILABLE $CD_DEVICE"
                    sleep "$POLL_DRIVE_INTERVAL"
                fi
                ;;
                
            "$STATE_WAITING_FOR_MEDIA")
                # Prüfe ob Medium eingelegt ist
                if is_disc_inserted; then
                    transition_to_state "$STATE_MEDIA_DETECTED" "$MSG_MEDIUM_DETECTED"
                else
                    # Prüfe ob Laufwerk noch da ist
                    if ! detect_device; then
                        transition_to_state "$STATE_WAITING_FOR_DRIVE" "Laufwerk nicht mehr verfügbar"
                    fi
                    sleep "$POLL_MEDIA_INTERVAL"
                fi
                ;;
                
            "$STATE_MEDIA_DETECTED")
                # Medium erkannt - warte bis es bereit ist (Spin-Up)
                if wait_for_disc_ready 3; then
                    transition_to_state "$STATE_ANALYZING" "Analysiere Medium..."
                else
                    # Medium nicht lesbar - zurück zum Warten
                    transition_to_state "$STATE_WAITING_FOR_MEDIA" "Medium nicht lesbar"
                    sleep "$POLL_MEDIA_INTERVAL"
                fi
                ;;
                
            "$STATE_ANALYZING")
                # Initialisiere ALLE Disc-Informationen (Typ, Label, Größe, Dateinamen)
                if ! init_disc_info; then
                    transition_to_state "$STATE_ERROR" "Disc-Analyse fehlgeschlagen"
                    sleep 3
                    continue
                fi
                
                log_info "$MSG_DISC_TYPE_DETECTED $(discinfo_get_type)"
                if [[ "$(discinfo_get_type)" != "audio-cd" ]]; then
                    log_info "$MSG_VOLUME_LABEL $(discinfo_get_label)"
                fi
                
                # Unmounte Disc falls sie auto-gemountet wurde
                if mount | grep -q "$CD_DEVICE"; then
                    log_info "$MSG_UNMOUNTING_DISC"
                    umount "$CD_DEVICE" 2>/dev/null || sudo umount "$CD_DEVICE" 2>/dev/null
                    sleep 1
                fi
                
                # Starte Kopiervorgang
                transition_to_state "$STATE_COPYING"
                ;;
                
            "$STATE_COPYING")
                # Kopiere Disc als ISO
                if copy_disc_to_iso; then
                    transition_to_state "$STATE_COMPLETED" "Kopiervorgang erfolgreich abgeschlossen"
                    sleep 3  # Kurze Pause damit Status sichtbar wird
                else
                    transition_to_state "$STATE_ERROR" "Kopiervorgang fehlgeschlagen"
                    sleep 3
                fi
                ;;
                
            "$STATE_COMPLETED"|"$STATE_ERROR")
                # Warte auf Medium-Entfernung
                transition_to_state "$STATE_WAITING_FOR_REMOVAL" "$MSG_WAITING_FOR_REMOVAL"
                ;;
                
            "$STATE_WAITING_FOR_REMOVAL")
                # Warte bis Medium entfernt wurde
                if ! is_disc_inserted; then
                    # Medium entfernt - zurück zum Warten auf neues Medium
                    transition_to_state "$STATE_IDLE" "Medium entfernt"
                else
                    sleep "$POLL_REMOVAL_INTERVAL"
                fi
                ;;
                
            "$STATE_IDLE")
                # Kurze Pause, dann zurück zum Warten auf Medium
                sleep 1
                transition_to_state "$STATE_WAITING_FOR_MEDIA" "$MSG_WAITING_FOR_MEDIUM"
                ;;
                
            *)
                # Unbekannter State - zurück zum Anfang
                log_info "$MSG_ERROR_UNKNOWN_STATE $CURRENT_STATE"
                transition_to_state "$STATE_INITIALIZING"
                ;;
        esac
    done
}

# ============================================================================
# START & SIGNAL-HANDLING
# ============================================================================

# Hauptfunktion
# Prüft Abhängigkeiten und startet Überwachung
main() {
    # Prüfe ob als systemd-Service gestartet
    local is_service=false
    if [[ -n "${INVOCATION_ID:-}" ]] || [[ "$PPID" == "1" ]] || systemctl is-active --quiet disk2iso 2>/dev/null; then
        is_service=true
    fi
    
    # Parse Kommandozeilenparameter
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                echo "disk2iso - Automatische ISO-Erstellung von optischen Medien"
                echo ""
                echo "HINWEIS: disk2iso läuft ausschließlich als systemd-Service!"
                echo ""
                echo "Verwendung:"
                echo "  sudo systemctl start disk2iso     - Service starten"
                echo "  sudo systemctl stop disk2iso      - Service stoppen"
                echo "  sudo systemctl status disk2iso    - Service-Status anzeigen"
                echo "  sudo journalctl -u disk2iso -f   - Live-Logs anzeigen"
                echo ""
                echo "Konfiguration: /opt/disk2iso/lib/config.sh"
                echo "Ausgabeverzeichnis: Siehe config.sh (DEFAULT_OUTPUT_DIR)"
                echo ""
                exit 0
                ;;
            --status)
                echo "disk2iso Service Status:"
                systemctl status disk2iso --no-pager 2>/dev/null || echo "Service nicht installiert oder läuft nicht"
                exit 0
                ;;
            *)
                echo "FEHLER: Unbekannter Parameter: $1"
                echo "Verwendung: $0 [--help | --status]"
                echo ""
                echo "HINWEIS: disk2iso läuft nur als systemd-Service!"
                echo "Starten mit: sudo systemctl start disk2iso"
                exit 1
                ;;
        esac
    done
    
    # Verhindere manuelle Ausführung (außer als Service)
    if [[ "$is_service" == "false" ]]; then
        echo "==============================================================================="
        echo "  FEHLER: disk2iso kann nicht manuell ausgeführt werden!"
        echo "==============================================================================="
        echo ""
        echo "disk2iso läuft ausschließlich als systemd-Service."
        echo ""
        echo "Service starten:"
        echo "  sudo systemctl start disk2iso"
        echo ""
        echo "Service-Status prüfen:"
        echo "  sudo systemctl status disk2iso"
        echo ""
        echo "Live-Logs anzeigen:"
        echo "  sudo journalctl -u disk2iso -f"
        echo ""
        echo "Web-Interface (falls installiert):"
        echo "  http://localhost:5000"
        echo ""
        echo "Konfiguration ändern:"
        echo "  sudo nano /opt/disk2iso/lib/config.sh"
        echo ""
        echo "==============================================================================="
        exit 1
    fi
    
    # Ab hier: Nur noch Service-Modus
    
    # ========================================================================
    # DEPENDENCY-CHECK ARCHITEKTUR
    # ========================================================================
    # Alle Module (Core + Optional) implementieren check_dependencies_<modul>()
    # 
    # Core-Module (Zeile 100-144):
    #   - Hardcodierte Prüfung (kein INI-Manifest)
    #   - Return 1 → Script-Abbruch (exit 1)
    #   - Beispiele: liblogging, libapi, libdiskinfos, libdrivestat
    # 
    # Optionale Module (Zeile 148-184):
    #   - INI-Manifest-basierte Prüfung via check_module_dependencies()
    #   - Return 1 → Feature deaktiviert (Script läuft weiter)
    #   - Setzen Feature-Flag (*_SUPPORT=true)
    #   - Beispiele: libcd, libdvd, libbluray
    #   - Externe Plugins: libmqtt (https://github.com/DirkGoetze/disk2iso-mqtt)
    # ========================================================================
    
    # OUTPUT_DIR wurde bereits am Anfang des Scripts gesetzt (siehe Zeile 83)
    # Dies verhindert dass Mount-Points im Root / landen
    
    # Prüfe ob OUTPUT_DIR existiert
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log_info "$MSG_ERROR_OUTPUT_DIR_NOT_EXIST_MAIN $OUTPUT_DIR"
        log_info "$MSG_CONFIG_OUTPUT_DIR"
        exit 1
    fi
    
    # Prüfe Schreibrechte
    if [[ ! -w "$OUTPUT_DIR" ]]; then
        log_info "$MSG_ERROR_NO_WRITE_PERMISSION $OUTPUT_DIR"
        log_info "$MSG_FIX_PERMISSIONS $OUTPUT_DIR"
        exit 1
    fi
    
    log_info "$MSG_DISK2ISO_STARTED"
    log_info "$MSG_OUTPUT_DIRECTORY $OUTPUT_DIR"
    
    # Abhängigkeiten wurden bereits beim Modul-Loading geprüft
    # Kern-Abhängigkeiten: check_dependencies_common()
    # Audio-CD: check_dependencies_cd() (optional)
    # Video-DVD/BD: check_dependencies_dvd(), check_dependencies_bluray() (optional)
    
    # Starte State Machine (läuft endlos)
    # Die State Machine kümmert sich selbst um Laufwerk-Erkennung und Retry-Logik
    run_state_machine
}

# Signal-Handler für sauberes Service-Beenden
cleanup_service() {
    log_info "$MSG_SERVICE_STOPPING"
    
    # MQTT: Offline setzen
    if [[ "$SUPPORT_MQTT" == "true" ]]; then
        mqtt_cleanup
    fi
    
    # Töte alle laufenden Kopierprozesse (dvdbackup, ddrescue, etc.)
    pkill -P $$ 2>/dev/null  # Töte alle Child-Prozesse
    sleep 2  # Warte bis Prozesse beendet sind
    
    # Jetzt cleanup durchführen
    cleanup_disc_operation "interrupted"
    exit 0
}

trap cleanup_service SIGTERM SIGINT

# Skript starten falls direkt aufgerufen
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
