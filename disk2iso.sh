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
source "${SCRIPT_DIR}/lib/lib-config.sh"

# Setze OUTPUT_DIR bereits hier (wichtig für get_tmp_mount() in lib-diskinfos.sh)
# Verhindert dass Mount-Points im Root / landen wenn OUTPUT_DIR noch nicht gesetzt ist
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"

# Lade Kern-Bibliotheken (IMMER erforderlich)
source "${SCRIPT_DIR}/lib/lib-logging.sh"
source "${SCRIPT_DIR}/lib/lib-api.sh"
source "${SCRIPT_DIR}/lib/lib-files.sh"
source "${SCRIPT_DIR}/lib/lib-folders.sh"
source "${SCRIPT_DIR}/lib/lib-diskinfos.sh"
source "${SCRIPT_DIR}/lib/lib-drivestat.sh"
source "${SCRIPT_DIR}/lib/lib-systeminfo.sh"
source "${SCRIPT_DIR}/lib/lib-common.sh"

# Lade Sprachdateien für Hauptskript
load_module_language "disk2iso"

# Prüfe Kern-Abhängigkeiten (kritisch - Abbruch bei Fehler)
if ! check_common_dependencies; then
    log_error "$MSG_ABORT_CRITICAL_DEPENDENCIES"
    exit 1
fi

if ! check_systeminfo_dependencies; then
    log_error "$MSG_ABORT_SYSTEMINFO_DEPENDENCIES"
    exit 1
fi

log_info "$MSG_CORE_MODULES_LOADED"

# Erkenne Container-Umgebung (setzt IS_CONTAINER und CONTAINER_TYPE)
detect_container_environment

# ============================================================================
# OPTIONALE MODULE MIT DEPENDENCY-CHECKS
# ============================================================================

# Metadata Framework (sollte zuerst geladen werden, da andere Module davon abhängen können)
if [[ -f "${SCRIPT_DIR}/lib/lib-metadata.sh" ]]; then
    source "${SCRIPT_DIR}/lib/lib-metadata.sh"
    check_dependencies_metadata  # Setzt METADATA_SUPPORT=true bei Erfolg
    
    # Lade Provider nur wenn Framework verfügbar
    if [[ "$METADATA_SUPPORT" == "true" ]]; then
        # MusicBrainz Provider (optional)
        if [[ -f "${SCRIPT_DIR}/lib/lib-musicbrainz.sh" ]]; then
            source "${SCRIPT_DIR}/lib/lib-musicbrainz.sh"
            check_dependencies_musicbrainz  # Setzt MUSICBRAINZ_SUPPORT=true bei Erfolg
        fi
        
        # TMDB Provider (optional)
        if [[ -f "${SCRIPT_DIR}/lib/lib-tmdb.sh" ]]; then
            source "${SCRIPT_DIR}/lib/lib-tmdb.sh"
            check_dependencies_tmdb  # Setzt TMDB_SUPPORT=true bei Erfolg
        fi
    fi
fi

# Legacy-Variablen für bestehende Checks in Copy-Modulen
# TODO: Diese werden entfernt sobald alle Module auf METADATA_SUPPORT umgestellt sind
DVD_METADATA_SUPPORT=$METADATA_SUPPORT
AUDIO_METADATA_SUPPORT=$METADATA_SUPPORT

# Audio-CD Support (optional)
if [[ -f "${SCRIPT_DIR}/lib/lib-cd.sh" ]]; then
    source "${SCRIPT_DIR}/lib/lib-cd.sh"
    check_dependencies_cd  # Setzt AUDIO_CD_SUPPORT=true bei Erfolg
fi

# Video-DVD Support (optional)
if [[ -f "${SCRIPT_DIR}/lib/lib-dvd.sh" ]]; then
    source "${SCRIPT_DIR}/lib/lib-dvd.sh"
    check_dependencies_dvd  # Setzt VIDEO_DVD_SUPPORT=true bei Erfolg
fi

# Video-Bluray Support (optional)
if [[ -f "${SCRIPT_DIR}/lib/lib-bluray.sh" ]]; then
    source "${SCRIPT_DIR}/lib/lib-bluray.sh"
    check_dependencies_bluray  # Setzt BLURAY_SUPPORT=true bei Erfolg
fi

# MQTT Support (optional)
if [[ -f "${SCRIPT_DIR}/lib/lib-mqtt.sh" ]]; then
    source "${SCRIPT_DIR}/lib/lib-mqtt.sh"
    check_dependencies_mqtt  # Setzt MQTT_SUPPORT=true bei Erfolg
    
    # mqtt_init prüft selbst ob MQTT_ENABLED=true und MQTT_SUPPORT verfügbar
    if [[ "$MQTT_SUPPORT" == "true" ]]; then
        mqtt_init  # Initialisiert MQTT_AVAILABLE bei Erfolg
    fi
fi

# Initialisiere API (IMMER, unabhängig von MQTT)
api_init

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
            log_info "$MSG_WARNING_AUDIO_CD_NO_SUPPORT"
            log_info "$MSG_FALLBACK_DATA_DISC"
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
    
    # Für Blu-ray Video: ddrescue (Priorität 1) oder dd (Fallback)
    elif [[ "$disc_type" == "bd-video" ]]; then
        if [[ "$BLURAY_SUPPORT" == true ]]; then
            # Priorität 1: ddrescue (verschlüsselt/unverschlüsselt, robust, schnell)
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
    # Wähle Kopiermethode basierend auf Disc-Typ und verfügbaren Tools
    local method=$(select_copy_method "$disc_type")
    
    # Audio-CDs behandeln init_filenames selbst (wegen speziellem Workflow)
    if [[ "$method" == "audio-cd" ]]; then
        if [[ "$AUDIO_CD_SUPPORT" == true ]] && declare -f copy_audio_cd >/dev/null 2>&1; then
            if copy_audio_cd; then
                return 0
            else
                return 1
            fi
        else
            log_info "$MSG_ERROR_AUDIO_CD_NOT_AVAILABLE"
            return 1
        fi
    fi
    
    # Für alle anderen Medien: Standard-Workflow
    # Initialisiere alle Dateinamen
    init_filenames
    
    # Stelle sicher dass Ausgabeverzeichnis existiert
    get_log_folder
    
    # Erstelle Log-Datei
    touch "$log_filename"
    
    log_info "$MSG_START_COPY_PROCESS $disc_label -> $iso_filename"
    
    # Speichere Methode für MQTT-Attribute (MUSS vor api_update_status gesetzt werden!)
    COPY_METHOD="$method"
    
    # API: Status-Update (IMMER)
    api_update_status "copying" "$disc_label" "$disc_type"
    
    # MQTT: Kopiervorgang gestartet (optional)
    if [[ "$MQTT_SUPPORT" == "true" ]]; then
        mqtt_publish_state "copying" "$disc_label" "$disc_type"
    fi
    
    # Kopiere mit gewählter Methode (KEIN Fallback bei Fehler)
    local copy_success=false
    
    case "$method" in
        audio-cd)
            # Wird oben behandelt
            ;;
        dvdbackup)
            if [[ "$VIDEO_DVD_SUPPORT" == true ]] && declare -f copy_video_dvd >/dev/null 2>&1; then
                if copy_video_dvd; then
                    copy_success=true
                fi
            else
                log_info "$MSG_ERROR_VIDEO_DVD_NOT_AVAILABLE"
                return 1
            fi
            ;;
        bluray-ddrescue)
            if [[ "$BLURAY_SUPPORT" == true ]] && declare -f copy_bluray_ddrescue >/dev/null 2>&1; then
                if copy_bluray_ddrescue; then
                    copy_success=true
                fi
            else
                log_info "$MSG_ERROR_BLURAY_NOT_AVAILABLE"
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
        
        log_info "$MSG_COPY_SUCCESS_FINAL $iso_filename"
        
        # MQTT: Erfolgreich abgeschlossen
        if [[ "$MQTT_SUPPORT" == "true" ]]; then
            mqtt_publish_complete "$iso_basename"
        fi
        
        cleanup_disc_operation "success"
        return 0
    else
        log_info "$MSG_COPY_FAILED_FINAL $disc_label"
        
        # MQTT: Fehler
        if [[ "$MQTT_SUPPORT" == "true" ]]; then
            mqtt_publish_error "Kopiervorgang fehlgeschlagen"
        fi
        
        cleanup_disc_operation "failure"
        return 1
    fi
}

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
    
    # Update API status for state
    case "$new_state" in
        "$STATE_WAITING_FOR_DRIVE")
            api_update_status "waiting" "${MSG_STATUS_WAITING_DRIVE:-Waiting for drive...}" "unknown"
            ;;
        "$STATE_DRIVE_DETECTED")
            api_update_status "idle" "${MSG_STATUS_DRIVE_DETECTED:-Drive Ready}" "unknown"
            ;;
        "$STATE_WAITING_FOR_MEDIA")
            api_update_status "idle" "${MSG_STATUS_WAITING_MEDIA:-Waiting for Media}" "unknown"
            ;;
        "$STATE_ANALYZING")
            api_update_status "analyzing" "$disc_label" "$disc_type"
            ;;
        "$STATE_WAITING_FOR_METADATA")
            api_update_status "waiting_for_metadata" "$disc_label" "$disc_type"
            ;;
        "$STATE_COPYING")
            api_update_status "copying" "$disc_label" "$disc_type"
            ;;
        "$STATE_COMPLETED")
            api_update_status "completed" "$disc_label" "$disc_type"
            ;;
        "$STATE_ERROR")
            api_update_status "error" "${disc_label:-Unknown}" "${disc_type:-unknown}" "${msg:-Unknown error}"
            ;;
        "$STATE_WAITING_FOR_REMOVAL")
            api_update_status "waiting" "$disc_label" "$disc_type"
            ;;
        "$STATE_IDLE")
            api_update_status "idle"
            ;;
    esac
    
    # MQTT (optional)
    if [[ "$MQTT_SUPPORT" == "true" ]]; then
        case "$new_state" in
            "$STATE_WAITING_FOR_DRIVE"|"$STATE_DRIVE_DETECTED"|"$STATE_WAITING_FOR_MEDIA"|"$STATE_IDLE")
                mqtt_publish_state "idle"
                ;;
            "$STATE_ANALYZING")
                mqtt_publish_state "analyzing" "$disc_label" "$disc_type"
                ;;
            "$STATE_WAITING_FOR_METADATA")
                mqtt_publish_state "waiting" "$disc_label" "$disc_type"
                ;;
            "$STATE_COPYING")
                mqtt_publish_state "copying" "$disc_label" "$disc_type"
                ;;
            "$STATE_COMPLETED")
                mqtt_publish_state "completed" "$disc_label" "$disc_type"
                ;;
            "$STATE_ERROR")
                mqtt_publish_state "error" "${disc_label:-Unknown}" "${disc_type:-unknown}"
                ;;
            "$STATE_WAITING_FOR_REMOVAL")
                mqtt_publish_state "waiting"
                ;;
        esac
    fi
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
                # Erkenne Disc-Typ
                detect_disc_type
                log_info "$MSG_DISC_TYPE_DETECTED $disc_type"
                
                # Generiere Label (für Audio-CDs wird Label in copy_audio_cd() gesetzt)
                if [[ "$disc_type" != "audio-cd" ]]; then
                    get_disc_label
                    log_info "$MSG_VOLUME_LABEL $disc_label"
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
    
    # OUTPUT_DIR wurde bereits am Anfang des Scripts gesetzt (siehe Zeile 88)
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
    # Kern-Abhängigkeiten: check_common_dependencies()
    # Audio-CD: check_audio_cd_dependencies() (optional)
    # Video-DVD/BD: check_video_dvd_dependencies() (optional)
    
    # Starte State Machine (läuft endlos)
    # Die State Machine kümmert sich selbst um Laufwerk-Erkennung und Retry-Logik
    run_state_machine
}

# Signal-Handler für sauberes Service-Beenden
cleanup_service() {
    log_info "$MSG_SERVICE_STOPPING"
    
    # MQTT: Offline setzen
    if [[ "$MQTT_SUPPORT" == "true" ]]; then
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
