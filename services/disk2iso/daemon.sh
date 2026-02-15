#!/bin/bash
################################################################################
# disk2iso v1.3.0 - Service Daemon
# Filepath: services/disk2iso/daemon.sh
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
# Definiere alle möglichen States der State Machine als Konstanten -----------
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

# Polling-Intervalle (Sekunden) ---------------------------------------------
readonly POLL_DRIVE_INTERVAL=20
readonly POLL_MEDIA_INTERVAL=2
readonly POLL_REMOVAL_INTERVAL=5

# Globale State Status-Variable (initialisiert mit INITIALIZING) -------------
CURRENT_STATE="$STATE_INITIALIZING"

# ============================================================================
# DEBUG-MODUS
# ============================================================================

# Debug-Modus aktivieren: DEBUG=1 ./daemon.sh
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x  # Trace-Modus: Zeigt jede ausgeführte Zeile
    PS4='+ ${BASH_SOURCE}:${LINENO}: '  # Zeigt Datei und Zeilennummer
fi

# Verbose-Modus: VERBOSE=1 ./daemon.sh
if [[ "${VERBOSE:-0}" == "1" ]]; then
    set -v  # Verbose: Zeigt Zeilen während sie gelesen werden
fi

# Strict-Modus für Entwicklung: STRICT=1 ./daemon.sh
if [[ "${STRICT:-0}" == "1" ]]; then
    set -euo pipefail  # Beende bei Fehlern, undefined vars, pipe failures
fi

# ============================================================================
# MODUL-LOADING 
# ============================================================================

# ===========================================================================
# daemon_load_modules()
# ---------------------------------------------------------------------------
# Funktion.: Lädt alle Core-Module in optimierter Reihenfolge (abhängigkeits-
# .........  basierte Reihenfolge) und prüft deren Abhängigkeiten. Beendet 
# .........  Script bei kritischen Fehlern (fehlende Kern-Module oder 
# .........  zirkuläre Abhängikeiten).
# Parameter: keine
# Rückgabe.: keine (beendet Script bei Fehlern)
# Extras...: 1. Ermittle Script-Verzeichnis (funktioniert auch bei Symlinks)
# .........  2. Lade Core-Module in optimierter Reihenfolge
# .........  3. Prüfe Abhängigkeiten jedes Moduls (return 1 → exit 1)
# .........  4. Lade optionale Module automatisch via integrity_load_modules()
# .........  5. Logge Erfolg oder Fehler beim Laden der Module
# ===========================================================================
daemon_load_modules() {

    # Ermittle Script-Verzeichnis (funktioniert auch bei Symlinks und Service)
    # Löse Symlinks auf, um den echten Pfad zu bekommen
    SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
    SCRIPT_SERVICE_DIR="$(dirname "$SCRIPT_PATH")"
    # Hauptverzeichnis ist zwei Ebenen höher (von services/disk2iso/ nach root)
    SCRIPT_DIR="$(dirname "$(dirname "$SCRIPT_SERVICE_DIR")")"

    # =======================================================================
    # LOAD-CORE-SETTINGS
    # =======================================================================
    # Lade Einstellungen für den Deamon und die Core-Module -----------------
    source "${SCRIPT_DIR}/conf/disk2iso.conf"

    # =======================================================================
    # CHECK_DEPENDENCIES & LOAD MODULES
    # =======================================================================
    # Alle Core-Module werden nacheinander geladen und müssen ihre Abhängig-keiten 
    # keiten erfüllen, sonst kann disk2iso nicht funktionieren. 
    # 
    # Lade-Reihenfolge (abhängikeits-optimiert): ----------------------------
    # 1. liblogging.sh - Logging (nur Bash-Built-ins) -----------------------
    # 1.1. Prüfe ob Datei ladbar ist ----------------------------------------
    if ! source "${SCRIPT_DIR}/lib/liblogging.sh"; then
        echo "FEHLER: liblogging.sh konnte nicht geladen werden" >&2
        exit 1
    fi
    # 1.2. Prüfe ob Dependencies erfüllt sind -------------------------------
    if ! logging_check_dependencies; then
        log_error "Logging-Modul Abhängigkeiten nicht erfüllt" >&2
        exit 1
    fi
    # 1.3. Ab hier können die Sprachdateien genutzt werden ------------------
    logging_load_language_file "disk2iso"

    # 2. libsettings.sh - Settings-Management (nutzt liblogging) ------------
    # 2.1. Prüfe ob Datei ladbar ist ----------------------------------------
    if ! source "${SCRIPT_DIR}/lib/libsettings.sh"; then
        log_error "libsettings.sh konnte nicht geladen werden" >&2
        exit 1
    fi
    # 2.2. Prüfe ob Dependencies erfüllt sind -------------------------------
    if ! settings_check_dependencies; then
        log_error "Config-Modul Abhängigkeiten nicht erfüllt"
        exit 1
    fi

    # 3. libfolders.sh - Ordner-Management (nutzt liblogging) ---------------
    # 3.1. Prüfe ob Datei ladbar ist ----------------------------------------
    if ! source "${SCRIPT_DIR}/lib/libfolders.sh"; then
        log_error "libfolders.sh konnte nicht geladen werden" >&2
        exit 1
    fi
    # 3.2. Prüfe ob Dependencies erfüllt sind -------------------------------
    if ! folders_check_dependencies; then
        log_error "Folders-Modul Abhängigkeiten nicht erfüllt"
        exit 1
    fi

    # 4. libfiles.sh - Datei-Management (nutzt libfolders + liblogging) -----
    # 4.1. Prüfe ob Datei ladbar ist ----------------------------------------
    if ! source "${SCRIPT_DIR}/lib/libfiles.sh"; then
        log_error "libfiles.sh konnte nicht geladen werden" >&2
        exit 1
    fi
    # 4.2. Prüfe ob Dependencies erfüllt sind -------------------------------
    if ! files_check_dependencies; then
        log_error "Files-Modul Abhängigkeiten nicht erfüllt"
        exit 1
    fi

    # 5. libintegrity.sh - Integritäts-Checks -------------------------------
    # 5.1. Prüfe ob Datei ladbar ist ----------------------------------------
    if ! source "${SCRIPT_DIR}/lib/libintegrity.sh"; then
        log_error "libintegrity.sh konnte nicht geladen werden" >&2
        exit 1
    fi
    # 5.2. Prüfe ob Dependencies erfüllt sind -------------------------------
    if ! integrity_check_dependencies; then
        log_error "Integrity-Modul Abhängigkeiten nicht erfüllt"
        exit 1
    fi

    # =======================================================================
    # LADE WEITERE CORE-MODULE (automatisch via INI-Discovery)
    # =======================================================================
    # Ab hier übernimmt integrity_load_modules() das automatische Laden aller
    # optionalen Core-Module (api, systeminfo, drivestat, diskinfos, common).
    # Module mit fehlenden Dependencies werden übersprungen (return 0).
    # Bei kritischen Fehlern (z.B. zirkuläre Dependencies) → return 1 → exit 1

    if ! integrity_load_modules; then
        log_error "Kritischer Fehler beim Laden der Core-Module"
        log_error "Service kann nicht gestartet werden"
        exit 1
    fi

    log_info "$MSG_CORE_MODULES_LOADED"
}

# ===========================================================================
# HAUPTLOGIK - DELEGIERT AN KOPIER-MODULE
# ===========================================================================

# ===========================================================================
# copy_disc_to_iso()
# ---------------------------------------------------------------------------
# Funktion.: Kopiert die eingelegte CD/DVD/BD in ein ISO-Image. Delegiert
# .........  an spezialisierte Module basierend auf erkanntem Disc-Typ:
# .........  Audio-CD → libaudio.sh, Video-DVD → libdvd.sh,
# .........  Blu-ray → libbluray.sh, Daten-Disc → libcommon.sh
# Parameter: keine (nutzt DISC_INFO Array)
# Rückgabe.: 0 = Erfolg
# .........  1 = Fehler (Modul nicht verfügbar oder Kopiervorgang fehlgeschlagen)
# Extras...: Wählt automatisch beste verfügbare Kopiermethode
# .........  Nutzt Getter für DISC_INFO-Zugriff (discinfo_get_type)
# .........  Ruft common_cleanup_disc_operation() mit explizitem Status auf
# ===========================================================================
copy_disc_to_iso() {
    #-- Ermittle Disc-Typ ---------------------------------------------------
    local disc_type="$(discinfo_get_type)"
    local exit_code=0
    
    #-- Audio-CD: Delegiere an libaudio.sh ----------------------------------
    if [[ "$disc_type" == "audio-cd" ]] && is_audio_ready; then
        copy_audio_cd
        exit_code=$?
    #-- Video-DVD: Delegiere an libdvd.sh -----------------------------------
    elif [[ "$disc_type" == "dvd-video" ]] && is_dvd_ready; then
        copy_video_dvd
        exit_code=$?
    #-- Blu-ray: Delegiere an libbluray.sh ----------------------------------
    elif [[ "$disc_type" == "bd-video" ]] && is_bluray_ready; then
        copy_bluray_disk
        exit_code=$?
    #-- Daten-Disc oder kein passendes Kopiermodul aktiv -------------------
    else
        common_copy_data_disc
        exit_code=$?
    fi
    
    #-- Cleanup mit explizitem Status (Success/Failure basierend auf Return-Code)
    if [[ $exit_code -eq 0 ]]; then
        common_cleanup_disc_operation "success"
    else
        common_cleanup_disc_operation "failure"
    fi
    
    return $exit_code
}

# ============================================================================
# STATE MACHINE
# ============================================================================

# ===========================================================================
# transition_to_state()
# ---------------------------------------------------------------------------
# Funktion.: State Machine Transition Handler - Wechselt State und
# .........  aktualisiert API/MQTT Status automatisch (Observer Pattern)
# Parameter: $1 = new_state (z.B. STATE_COPYING, STATE_COMPLETED)
# .........  $2 = msg (optionale Statusmeldung, default: leer)
# Rückgabe.: keine
# Extras...: Triggert api_update_from_state() für automatische Status-Updates
# .........  MQTT-Updates erfolgen transparent via Observer Pattern
# .........  Loggt State-Wechsel mit optionaler Nachricht
# ===========================================================================
transition_to_state() {
    local new_state="$1"
    local msg="${2:-}"
    
    CURRENT_STATE="$new_state"
    
    # Log state change
    if [[ -n "$msg" ]]; then
        log_info "$msg"
    fi
    
    # Update API status via helper function 
    api_update_from_state "$new_state" "${msg:-}"
}

# ===========================================================================
# run_state_machine()
# ---------------------------------------------------------------------------
# Funktion.: State Machine Hauptschleife - Überwacht Laufwerk und Medium,
# .........  führt kompletten Workflow aus (Erkennung → Analyse → Kopie)
# Parameter: keine
# Rückgabe.: läuft endlos (Exit nur via Signal SIGTERM/SIGINT)
# Extras...: 11 States: INITIALIZING, WAITING_FOR_DRIVE, DRIVE_DETECTED,
# .........  WAITING_FOR_MEDIA, MEDIA_DETECTED, ANALYZING, COPYING,
# .........  COMPLETED, ERROR, WAITING_FOR_REMOVAL, IDLE
# .........  Polling-Intervalle: Drive=20s, Media=2s, Removal=5s
# .........  Auto-Recovery bei Fehlern (Device-Loss, Lesefehler)
# ===========================================================================
run_state_machine() {
    log_info "$MSG_STATE_MACHINE_STARTED"
    
    transition_to_state "$STATE_INITIALIZING" "Initialisiere Service..."
    
    # Hauptschleife - läuft endlos
    while true; do
        case "$CURRENT_STATE" in
            "$STATE_INITIALIZING")
                daemon_load_modules
                # Initialisierung abgeschlossen, suche nach Laufwerk
                transition_to_state "$STATE_WAITING_FOR_DRIVE" "Suche nach optischem Laufwerk..."
                ;;
                
            "$STATE_WAITING_FOR_DRIVE")
                # Prüfe ob Laufwerk verfügbar ist
                if drivestat_get_drive; then
                    transition_to_state "$STATE_WAITING_FOR_MEDIA" "$MSG_DRIVE_DETECTED $CD_DEVICE"
                else
                    # Kein Laufwerk gefunden - warte und versuche erneut
                    sleep "$POLL_DRIVE_INTERVAL"
                fi
                ;;
                
            "$STATE_WAITING_FOR_MEDIA")
                # Prüfe ob Medium eingelegt ist
                if drivestat_disc_insert; then
                    transition_to_state "$STATE_MEDIA_DETECTED" "$MSG_MEDIUM_DETECTED"
                else
                    # Prüfe ob Laufwerk noch da ist
                    if ! drivestat_get_drive; then
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
                # Wirf Disc aus und wechsle zu WAITING_FOR_REMOVAL
                common_eject_and_wait "false"
                transition_to_state "$STATE_WAITING_FOR_REMOVAL" "$MSG_WAITING_FOR_REMOVAL"
                ;;
                
            "$STATE_WAITING_FOR_REMOVAL")
                # Warte bis Medium entfernt wurde
                if ! drivestat_disc_insert; then
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

# ===========================================================================
# main()
# ---------------------------------------------------------------------------
# Funktion.: Hauptfunktion - Prüft Service-Modus, Abhängigkeiten und
# .........  startet State Machine (nur als systemd-Service erlaubt)
# Parameter: $@ = Kommandozeilenparameter (--help, --status)
# Rückgabe.: 0 = Service beendet (nur bei SIGTERM/SIGINT)
# .........  1 = Fehler (manuelle Ausführung, fehlende Abhängigkeiten)
# Extras...: Verhindert manuelle Ausführung (nur systemd-Service)
# .........  Validiert OUTPUT_DIR Existenz und Schreibrechte
# .........  Alle Module bereits geladen (Zeile 74-184)
# .........  Startet endlose State Machine Loop
# ===========================================================================
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

    # Starte State Machine (läuft endlos)
    # Die State Machine kümmert sich selbst um Laufwerk-Erkennung und Retry-Logik
    run_state_machine
}

# ===========================================================================
# cleanup_service()
# ---------------------------------------------------------------------------
# Funktion.: Signal-Handler für sauberes Service-Beenden (SIGTERM/SIGINT)
# .........  Stoppt laufende Kopierprozesse und räumt Ressourcen auf
# Parameter: keine (wird von trap aufgerufen)
# Rückgabe.: exit 0 (beendet Script)
# Extras...: Setzt MQTT Offline-Status (falls aktiviert)
# .........  Tötet Child-Prozesse (ddrescue, dd, dvdbackup, etc.)
# .........  Ruft common_cleanup_disc_operation("interrupted") auf
# .........  Registriert via: trap cleanup_service SIGTERM SIGINT
# ===========================================================================
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
    common_cleanup_disc_operation "interrupted"
    exit 0
}

trap cleanup_service SIGTERM SIGINT

# Skript starten falls direkt aufgerufen
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
