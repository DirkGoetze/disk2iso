#!/bin/bash
# =============================================================================
# Common Functions Library
# =============================================================================
# Filepath: lib/libcommon.sh
#
# Beschreibung:
#   Gemeinsame Kern-Funktionen für alle Module
#   - common_copy_data_disc(), common_copy_data_disc_ddrescue()
#   - common_cleanup_disc_operation(), common_monitor_copy_progress()
#   - Fehler-Tracking: common_register_disc_failure(), common_clear_disc_failures()
#   
#   Hinweis: systeminfo_check_disk_space() ist in libsysteminfo.sh
#            init_copy_log(), finish_copy_log() sind in liblogging.sh
#
# -----------------------------------------------------------------------------
# Dependencies: liblogging, libfolders (für Core-Funktionen)
# -----------------------------------------------------------------------------
# Author: D.Gütze
# Version: 1.3.0
# Last Change: 2026-02-07
# =============================================================================

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

# ===========================================================================
# common_check_dependencies
# ---------------------------------------------------------------------------
# Funktion.: Prüfe alle Framework Abhängigkeiten (Modul-Dateien, die Modul
# .........  Ausgabe Ordner, kritische und optionale Software für die
# .........  Ausführung des Tool), lädt bei erfolgreicher Prüfung die
# .........  Sprachdatei für das Modul.
# Parameter: keine
# Rückgabe.: 0 = verfügbar (Framework nutzbar)
# .........  1 = Nicht verfügbar (Framework deaktiviert)
# Extras...: Sollte so früh wie möglich nach dem Start geprüft werden, da
# .........  andere Module ggf. auf dieses Framework angewiesen sind. Am
# .........  besten direkt im Hauptskript (disk2iso) nach dem
# .........  Laden der libcommon.sh.
# ===========================================================================
common_check_dependencies() {
    # Manifest-basierte Abhängigkeitsprüfung (Tools, Dateien, Ordner)
    integrity_check_module_dependencies "common" || return 1
    
    # Modul-spezifische Initialisierung
    # Prüfe/Erstelle Ausgabe-Ordner für Daten-Discs
    if declare -f folders_get_modul_output_dir >/dev/null 2>&1; then
        if ! folders_get_modul_output_dir "data" >/dev/null 2>&1; then
            log_error "$MSG_ERROR_OUTPUT_DIR_NOT_EXISTS $(folders_get_output_dir 2>/dev/null || echo '<unknown>')"
            return 1
        fi
    fi
    
    return 0
}

# ===========================================================================
# DATEN DISK KOPIEREN
# ===========================================================================

# ===========================================================================
# common_copy_data_disc
# ---------------------------------------------------------------------------
# Funktion.: Kopiert Daten-Discs oder alle anderen Disc-Tpen ohne eigenes 
# .........  Kopiermodul (Audio-CD, DVD-Video, Blu-ray Video). Wühlt die 
# .........  beste verfügbare Methode basierend auf Fehler-Historie.
# Parameter: keine (nutzt globale Variablen: disc_label, disc_type, iso_filename)
# Rückgabe.: 0 = Erfolg
# .........  1 = Fehler
# Extras...: Nutzt common_copy_data_disc_ddrescue() und common_copy_data_disc_dd()
# ===========================================================================
common_copy_data_disc() {
    #-- Prüfe Disc-Typ: Audio-CDs können nicht als ISO kopiert werden -------
    local disc_type="$(discinfo_get_type)"
    if [[ "$disc_type" == "audio-cd" ]]; then
        log_error "$MSG_ERROR_AUDIO_CD_AS_DATA"
        log_error "$MSG_ERROR_AUDIO_MODULE_NOT_INSTALLED"
        log_info "$MSG_INFO_INSTALL_AUDIO_MODULE"
        return 1
    fi
    
    #-- Prüfe ob diese Disc bereits fehlgeschlagen ist ----------------------
    local failure_count=$(common_get_disc_failure_count)
    
    #-- Prüfe ob ddrescue vorhanden, es ist optional ------------------------
    if command -v ddrescue >/dev/null 2>&1 && [[ $failure_count -eq 0 ]]; then
        log_info "$MSG_INFO_COPY_WITH_DDRESCUE"
        #-- 1. Versuch: ddrescue verwenden ----------------------------------
        if common_copy_data_disc_ddrescue; then
            return 0
        else
            #-- Kopiervorgang fehlgeschlagen - registriere Fehler -----------
            common_register_disc_failure
            log_warning "$MSG_WARNING_DDRESCUE_FALLBACK"
        fi
    fi
    
    #-- 2. Versuch: dd verwenden --------------------------------------------
    log_info "$MSG_INFO_COPY_WITH_DD"
    if common_copy_data_disc_dd; then
        #-- Erfolg - lüsche Fehler-Historie falls vorhanden -----------------
        [[ $failure_count -gt 0 ]] && common_clear_disc_failures
        return 0
    else
        #-- Kopiervorgang fehlgeschlagen - registriere Fehler ---------------
        log_error "$MSG_ERROR_DD_COPY_FAILED"
        common_register_disc_failure
        return 1
    fi
}

# ===========================================================================
# common_copy_data_disc_ddrescue
# ---------------------------------------------------------------------------
# Funktion.: Kopiert Daten-Discs mit ddrescue (robust, mit Fehlerkorrektur)
# .........  Nutzt vorberechnete DISC_INFO-Werte und zeitgesteuertes
# .........  Fortschritts-Monitoring (alle 60 Sekunden).
# Parameter: keine (nutzt DISC_INFO Array)
# Rückgabe.: 0 = Erfolg
# .........  1 = Fehler (Speicherplatz, Kopiervorgang fehlgeschlagen)
# Extras...: Schneller und robuster als dd, erfordert ddrescue-Installation
# .........  Erstellt Map-Datei für Wiederherstellung bei Abbruch
# .........  Sendet Fortschritt via API, MQTT und systemd-notify
# ===========================================================================
common_copy_data_disc_ddrescue() {
    #-- Initialisiere Kopiervorgang-Log -------------------------------------
    init_copy_log "$(discinfo_get_label)" "data"
    log_copying "$MSG_METHOD_DDRESCUE"
    
    #-- Setze verwendete Kopiermethode --------------------------------------
    discinfo_set_copy_method "ddrescue"
    
    #-- Lese aus DISC_INFO Array die benütigten Werte -----------------------
    local iso_filename=$(discinfo_get_iso_filename)
    local temp_pathname=$(discinfo_get_temp_pathname)
    local copy_log_filename=$(discinfo_get_log_filename)
    local size_mb=$(discinfo_get_size_mb)
    local block_size=$(discinfo_get_block_size)
    local total_bytes=$((size_mb * 1024 * 1024))
    
    #-- ddrescue benütigt Map-Datei (im .temp Ordner, wird auto-gelüscht) ---
    local mapfile="${temp_pathname}/$(basename "${iso_filename}").mapfile"
    
    #-- Speicherplatz Prüfung (falls Größe bekannt) -------------------------    
    if [[ $size_mb -gt 0 ]]; then
        #-- Logge erkannte Disc-Größe ---------------------------------------
        log_copying "$MSG_ISO_VOLUME_DETECTED $(discinfo_get_size_sectors) $MSG_ISO_BLOCKS_SIZE 2048 $MSG_ISO_BYTES (${size_mb} $MSG_PROGRESS_MB)"
        
        #-- Prüfe Speicherplatz mit vorberechneter Größe (inkl. Overhead) ---
        if ! systeminfo_check_disk_space "$(discinfo_get_estimated_size_mb)"; then
            return 1
        fi
    fi
    
    #-- Starte ddrescue im Hintergrund (mit oder ohne Größenbeschränkung) ---
    if [[ $total_bytes -gt 0 ]]; then
        ddrescue -b "${block_size:-2048}" -r "$DDRESCUE_RETRIES" -s "$total_bytes" "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$copy_log_filename" &
    else
        ddrescue -b "${block_size:-2048}" -r "$DDRESCUE_RETRIES" "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$copy_log_filename" &
    fi
    local ddrescue_pid=$!
    
    #-- überwache Fortschritt (alle 60 Sekunden) ----------------------------
    common_monitor_copy_progress "$ddrescue_pid" "$total_bytes" "$iso_filename"
    
    #-- Warte auf ddrescue Prozess-Ende und hole Exit-Code ------------------
    wait "$ddrescue_pid"
    local ddrescue_exit=$?
    
    #-- Prüfe Ergebnis ------------------------------------------------------
    if [[ $ddrescue_exit -eq 0 ]]; then
        log_copying "$MSG_DATA_DISC_SUCCESS_DDRESCUE"
        finish_copy_log
        return 0
    else
        log_error "$MSG_ERROR_DDRESCUE_FAILED"
        finish_copy_log
        return 1
    fi
}

# ===========================================================================
# common_copy_data_disc_dd
# ---------------------------------------------------------------------------
# Funktion.: Kopiert Daten-Discs mit dd (Fallback-Methode, immer verfügbar)
# .........  Nutzt vorberechnete DISC_INFO-Werte und zeitgesteuertes
# .........  Fortschritts-Monitoring (alle 60 Sekunden).
# Parameter: keine (nutzt DISC_INFO Array)
# Rückgabe.: 0 = Erfolg
# .........  1 = Fehler (Speicherplatz, Kopiervorgang fehlgeschlagen)
# Extras...: Langsamste Methode, aber immer verfügbar (keine Abhängigkeiten)
# .........  Unterstützt Kopieren mit/ohne Größenangabe
# .........  Sendet Fortschritt via API, MQTT und systemd-notify
# ===========================================================================
common_copy_data_disc_dd() {
    #-- Initialisiere Kopiervorgang-Log -------------------------------------
    init_copy_log "$(discinfo_get_label)" "data"    
    log_copying "$MSG_METHOD_DD"

    #-- Setze verwendete Kopiermethode --------------------------------------
    discinfo_set_copy_method "dd"

    #-- Lese aus DISC_INFO Array die benütigten Werte -----------------------
    local iso_filename=$(discinfo_get_iso_filename)
    local copy_log_filename=$(discinfo_get_log_filename)
    local size_mb=$(discinfo_get_size_mb)
    local volume_size=$(discinfo_get_size_sectors)
    local block_size=$(discinfo_get_block_size)
    local total_bytes=$((size_mb * 1024 * 1024))

    #-- Speicherplatz Prüfung (falls Größe bekannt) -------------------------    
    if [[ $size_mb -gt 0 ]]; then
        #-- Logge erkannte Disc-Größe ---------------------------------------
        log_copying "$MSG_ISO_VOLUME_DETECTED $volume_size $MSG_ISO_BLOCKS_SIZE $block_size $MSG_ISO_BYTES (${size_mb} $MSG_PROGRESS_MB)"
        
        #-- Prüfe Speicherplatz mit vorberechneter Größe (inkl. Overhead) ---
        if ! systeminfo_check_disk_space "$(discinfo_get_estimated_size_mb)"; then
            return 1
        fi
    fi
    
    #-- Starte dd im Hintergrund (mit oder ohne count-Parameter) ------------
    if [[ $volume_size -gt 0 ]]; then
        dd if="$CD_DEVICE" of="$iso_filename" bs="$block_size" count="$volume_size" conv=noerror,sync status=progress 2>>"$copy_log_filename" &
    else
        dd if="$CD_DEVICE" of="$iso_filename" bs="$block_size" conv=noerror,sync status=progress 2>>"$copy_log_filename" &
    fi
    local dd_pid=$!
    
    #-- überwache Fortschritt (alle 60 Sekunden) ----------------------------
    common_monitor_copy_progress "$dd_pid" "$total_bytes" "$iso_filename"
    
    #-- Warte auf dd Prozess-Ende und hole Exit-Code ------------------------
    wait "$dd_pid"
    local dd_exit=$?
    
    #-- Prüfe Ergebnis ------------------------------------------------------
    if [[ $dd_exit -eq 0 ]]; then
        finish_copy_log
        return 0
    else
        finish_copy_log
        return 1
    fi
}


# ============================================================================
# FEHLER-TRACKING SYSTEM (für alle Disc-Typen)
# ============================================================================

# ===========================================================================
# common_get_disc_failure_count
# ---------------------------------------------------------------------------
# Funktion.: Prüft ob Disc bereits fehlgeschlagen ist und gibt die Anzahl
# .........  der bisherigen Fehlversuche zurück.
# Parameter: $1 = Disc-Identifier (deprecaded, nutzt discinfo_get_identifier())
# Rückgabe.: Anzahl der Fehlversuche (0-N) via echo
# .........  Return-Code: 0 = Erfolg (Anzahl ermittelt)
# .........  ............ 1 = Fehler (Datei nicht verfügbar, Fallback auf 0)
# Extras...: Nutzt INI-Format mit disc_type als Section ([data], [audio], etc.)
# .........  Format: UUID:LABEL:SIZE_MB=timestamp|method|retry_count
# ===========================================================================
common_get_disc_failure_count() {
    #-- Debug-Log Eintrag ---------------------------------------------------
    log_debug "$MSG_DEBUG_FAILURE_COUNT_START"

    #-- Pfad zur Ausgabes-Datei ermitteln -----------------------------------
    local failed_file
    failed_file=$(get_failed_disc_path) || {
        echo 0  # Fallback: Keine Fehler bekannt
        return 1
    }

    #-- Alle notwendigen Werte ermitteln ------------------------------------
    local identifier=$(discinfo_get_identifier)
    local disc_type=$(discinfo_get_type)
    
    #-- Lese Wert aus INI (Format: timestamp|method|retry_count) ------------
    local value=$(config_get_value_ini "failed_discs" "$disc_type" "$identifier")
    
    #-- Prüfe ob Eintrag vorhanden ist --------------------------------------
    if [[ -n "$value" ]]; then
        #-- Extrahiere retry_count (3. Feld) --------------------------------
        echo "$value" | cut -d'|' -f3
        return 0
    else
        #-- Kein Eintrag = Keine Fehler -------------------------------------
        echo 0
        return 0
    fi
}

# ===========================================================================
# common_register_disc_failure
# ---------------------------------------------------------------------------
# Funktion.: Registriert einen Disc-Fehlschlag im INI-basierten Error-
# .........  Tracking-System und inkrementiert automatisch den retry_count.
# Parameter: $1 = Disc-Identifier (deprecaded, nutzt discinfo_get_identifier())
# Rückgabe.: 0 = Erfolg (Fehler registriert)
# .........  1 = Fehler (Datei nicht verfügbar)
# Extras...: Format: UUID:LABEL:SIZE_MB=timestamp|method|retry_count
# .........  Methode wird aus DISC_INFO[copy_method] gelesen
# .........  Nutzt INI-Format mit disc_type als Section 
# ===========================================================================
common_register_disc_failure() {
    #-- Debug-Log Eintrag ---------------------------------------------------
    log_debug "$MSG_DEBUG_REGISTER_FAILURE_START"

    #-- Pfad zur Ausgabes-Datei ermitteln -----------------------------------
    local failed_file=$(get_failed_disc_path) || return 1

    #-- Alle notwendigen Werte ermitteln ------------------------------------
    local identifier=$(discinfo_get_identifier)
    local method=$(discinfo_get_copy_method)
    local disc_type=$(discinfo_get_type)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    #-- Lese aktuellen retry_count und inkrementiere ------------------------
    local retry_count=$(common_get_disc_failure_count)
    retry_count=$((retry_count + 1))
    
    #-- Schreibe/Aktualisiere Eintrag: timestamp|method|retry_count ---------
    config_set_value_ini "failed_discs" "$disc_type" "$identifier" "${timestamp}|${method}|${retry_count}"
    log_warning "$MSG_WARNING_DISC_FAILURE_REGISTERED $identifier ($method, Versuch #${retry_count})"
}

# ===========================================================================
# common_clear_disc_failures
# ---------------------------------------------------------------------------
# Funktion.: Entfernt Disc-Fehlschlag aus dem Error-Tracking-System nach
# .........  erfolgreichem Kopieren.
# Parameter: keine (nutzt DISC_INFO Array)
# Rückgabe.: 0 = Erfolg (Eintrag gelüscht oder nicht vorhanden)
# .........  1 = Fehler (Datei nicht verfügbar)
# Extras...: Loggt nur wenn tatsüchlich ein Eintrag gelüscht wurde
# .........  Nutzt get_ini_value zur Existenzprüfung vor dem löschen
# ===========================================================================
common_clear_disc_failures() {
    #-- Debug-Log Eintrag ---------------------------------------------------
    log_debug "$MSG_DEBUG_CLEAR_FAILURES_START"

    #-- Pfad zur Ausgabes-Datei ermitteln -----------------------------------
    local failed_file=$(get_failed_disc_path) || return 1

    #-- Alle notwendigen Werte ermitteln ------------------------------------
    local identifier=$(discinfo_get_identifier)
    local disc_type=$(discinfo_get_type)
    
    #-- Prüfe ob Eintrag existiert ------------------------------------------
    local value=$(config_get_value_ini "failed_discs" "$disc_type" "$identifier")
    
    if [[ -n "$value" ]]; then
        #-- Lüsche existierenden Eintrag ------------------------------------
        config_del_value_ini "failed_discs" "$disc_type" "$identifier"
        log_info "$MSG_INFO_FAILURE_HISTORY_CLEARED $identifier"
        return 0
    else
        #-- Kein Eintrag vorhanden - nichts zu tun --------------------------
        log_debug "$MSG_DEBUG_NO_FAILURE_HISTORY $identifier vorhanden"
        return 0
    fi
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# ===========================================================================
# common_calculate_and_log_progress
# ---------------------------------------------------------------------------
# Funktion.: Berechnet und loggt Kopierfortschritt (zentral für alle Methoden)
# .........  Sendet Updates an API, MQTT und systemd-notify
# Parameter: $1 = Aktuell kopierte Bytes
# .........  $2 = GesamtGröße in Bytes (0 = unbekannt)
# .........  $3 = Start-Zeit (Unix-Timestamp)
# .........  $4 = Log-Prüfix (z.B. "DATA", "DVD", "BLURAY")
# Rückgabe.: keine (setzt globale Variablen $percent und $eta)
# Extras...: Berechnet ETA basierend auf bisheriger Geschwindigkeit
# .........  Loggt alle erforderlichen Informationen (Prozent, MB, ETA)
# .........  API/MQTT/systemd Updates erfolgen automatisch
# ===========================================================================
common_calculate_and_log_progress() {
    local current_bytes=$1
    local total_bytes=$2
    local start_time=$3
    local log_prefix=$4
    
    # Konvertiere zu MB für Anzeige
    local current_mb=$((current_bytes / 1024 / 1024))
    local total_mb=$((total_bytes / 1024 / 1024))
    
    # Initialisiere Ausgabewerte
    percent=0
    eta="--:--:--"
    
    # Berechne Prozent und ETA wenn müglich
    if [[ $total_bytes -gt 0 ]] && [[ $current_bytes -gt 0 ]]; then
        percent=$((current_bytes * 100 / total_bytes))
        if [[ $percent -gt 100 ]]; then percent=100; fi
        
        # Berechne geschützte Restzeit
        local current_time=$(date +%s)
        local total_elapsed=$((current_time - start_time))
        if [[ $percent -gt 0 ]]; then
            local estimated_total=$((total_elapsed * 100 / percent))
            local remaining=$((estimated_total - total_elapsed))
            local hours=$((remaining / 3600))
            local minutes=$(((remaining % 3600) / 60))
            local seconds=$((remaining % 60))
            eta=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
        fi
        
        # Log-Nachricht mit Prüfix
        log_info "${log_prefix} $MSG_PROGRESS: ${current_mb} $MSG_PROGRESS_MB $MSG_PROGRESS_OF ${total_mb} $MSG_PROGRESS_MB (${percent}%) - $MSG_REMAINING: ${eta}"
        
        # API: Fortschritt senden (IMMER)
        if declare -f api_update_progress >/dev/null 2>&1; then
            api_update_progress "$percent" "$current_mb" "$total_mb" "$eta"
        fi
        
        # MQTT: Fortschritt senden (optional)
        if is_mqtt_ready && declare -f mqtt_publish_progress >/dev/null 2>&1; then
            mqtt_publish_progress "$percent" "$current_mb" "$total_mb" "$eta"
        fi
        
        # systemd-notify: Status aktualisieren (wenn verfügbar)
        if command -v systemd-notify >/dev/null 2>&1; then
            systemd-notify --status="${log_prefix}: ${current_mb} MB / ${total_mb} MB (${percent}%)" 2>/dev/null
        fi
    else
        # Fallback: Nur kopierte Größe
        log_info "${log_prefix} $MSG_PROGRESS: ${current_mb} $MSG_PROGRESS_MB $MSG_COPIED"
    fi
}

# ===========================================================================
# common_monitor_copy_progress
# ---------------------------------------------------------------------------
# Funktion.: überwacht Kopierfortschritt für dd/ddrescue im Hintergrund
# .........  Nutzt zeitgesteuertes Monitoring (alle 60 Sekunden)
# Parameter: $1 = PID des Kopierprozesses
# .........  $2 = GesamtGröße in Bytes (für Prozentberechnung)
# .........  $3 = ISO-Dateiname (zur Größenermittlung via stat)
# Rückgabe.: keine (blockiert bis Prozess beendet ist)
# Extras...: Nutzt common_calculate_and_log_progress() für Fortschrittsberechnung
# .........  Konsistent mit Web-UI (60 Sekunden Intervall)
# .........  Macht KEIN wait - aufrufende Funktion muss wait ausführen!
# ===========================================================================
common_monitor_copy_progress() {
    local copy_pid=$1
    local total_bytes=$2
    local iso_file=$3
    local start_time=$(date +%s)
    local last_log_time=$start_time
    
    while kill -0 "$copy_pid" 2>/dev/null; do
        sleep 30
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - last_log_time))
        
        # Log alle 60 Sekunden
        if [[ $elapsed -ge 60 ]]; then
            local current_bytes=0
            if [[ -f "$iso_file" ]]; then
                current_bytes=$(stat -c %s "$iso_file" 2>/dev/null || echo 0)
            fi
            
            # Nutze zentrale Fortschrittsberechnung
            common_calculate_and_log_progress "$current_bytes" "$total_bytes" "$start_time" "$MSG_DATA_PROGRESS"
            
            last_log_time=$current_time
        fi
    done
    
    # Abschluss-Status
    if command -v systemd-notify >/dev/null 2>&1; then
        systemd-notify --status="Kopiervorgang abgeschlossen" 2>/dev/null
    fi
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# ===========================================================================
# common_eject_and_wait
# ---------------------------------------------------------------------------
# Funktion.: Wirft Disc aus und wartet optional auf Medium-Wechsel
# .........  (Container-aware mit LXC-Unterstützung)
# Parameter: $1 = wait_for_new_media (optional: "true"/"false", default: "false")
# .........  Falls true, wartet Funktion auf neues Medium (nur bei Erfolg)
# Rückgabe.: 0 = Erfolg (Disc ausgeworfen)
# .........  1 = Fehler (Device nicht verfügbar oder Eject fehlgeschlagen)
# Extras...: Nutzt wait_for_medium_change() für Container-Umgebungen
# .........  Bei Success wartet Funktion bis neues Medium eingelegt wurde
# ===========================================================================
common_eject_and_wait() {
    local wait_for_new="${1:-false}"
    local device
    
    device=$(discinfo_get_device)
    
    # Prüfe ob Device verfügbar ist
    if [[ ! -b "$device" ]]; then
        log_debug "$MSG_DEBUG_NO_DEVICE_TO_EJECT $device"
        return 1
    fi
    
    # Versuche Disc auszuwerfen
    if eject "$device" 2>/dev/null; then
        log_info "$MSG_DISC_EJECTED"
    else
        log_error "$MSG_EJECT_FAILED"
        return 1
    fi
    
    # Optional: Warte auf Medium-Wechsel (nur bei Success)
    if [[ "$wait_for_new" == "true" ]]; then
        # Nutze LXC-sichere Methode wenn in Container
        if $IS_CONTAINER; then
            wait_for_medium_change_lxc_safe "$device" 300  # 5 Minuten Timeout
        else
            wait_for_medium_change "$device" 300  # 5 Minuten Timeout
        fi
    fi
    
    return 0
}

# ===========================================================================
# common_cleanup_disc_operation
# ---------------------------------------------------------------------------
# Funktion.: Rüumt Ressourcen nach Disc-Operation auf (Temp-Verzeichnis,
# .........  unvollständige ISO-Dateien, DISC_INFO Reset)
# Parameter: $1 = Status (optional: "success", "failure", "unknown", "interrupted")
# .........  Falls nicht übergeben, wird Status aus Fehler-Tracking ermittelt
# Rückgabe.: keine
# Extras...: Wirft Disc NICHT aus (siehe common_eject_and_wait)
# .........  Unmountet Temp-Verzeichnisse automatisch
# .........  Lüscht ISO-Dateien nur bei Status "failure"
# Hinweis..: ISO-Existenz ist KEIN Erfolgsindikator (unvollständige Dateien!)
# ===========================================================================
common_cleanup_disc_operation() {
    local status="${1}"
    local temp_dir iso_file
    
    # Ermittle Status automatisch wenn nicht übergeben
    if [[ -z "$status" ]]; then
        if [[ $(common_get_disc_failure_count) -gt 0 ]]; then
            status="failure"
            log_debug "$MSG_DEBUG_STATUS_AUTO_FAILURE"
        else
            status="unknown"
            log_debug "$MSG_DEBUG_STATUS_AUTO_UNKNOWN"
        fi
    fi
    
    # 1. Temp-Verzeichnis aufrüumen (falls vorhanden)
    temp_dir=$(discinfo_get_temp_pathname)
    if [[ -n "$temp_dir" ]] && [[ -d "$temp_dir" ]]; then
        # Unmount alle eventuellen Mountpoints im Temp-Verzeichnis
        if command -v findmnt >/dev/null 2>&1; then
            # Finde und unmounte alle Mountpoints unterhalb von temp_pathname
            findmnt -R -n -o TARGET "$temp_dir" 2>/dev/null | sort -r | while read -r mountpoint; do
                umount "$mountpoint" 2>/dev/null || umount -l "$mountpoint" 2>/dev/null
            done
        else
            # Fallback: Versuche bekannte Mountpoints zu unmounten
            find "$temp_dir" -type d 2>/dev/null | while read -r dir; do
                umount "$dir" 2>/dev/null || true
            done
        fi
        
        # Gib dem System kurz Zeit zum Unmounten
        sleep 1
        
        # Lüsche Temp-Verzeichnis (mit force)
        rm -rf "$temp_dir" 2>/dev/null || {
            # Fallback: Versuche mit sudo falls Permission-Fehler
            log_error "$MSG_WARNING_TEMP_DIR_DELETE_FAILED"
            sudo rm -rf "$temp_dir" 2>/dev/null || true
        }
    fi
    
    # 2. unvollständige ISO-Datei löschen (nur bei Fehler)
    if [[ "$status" == "failure" ]]; then
        iso_file=$(discinfo_get_iso_filename)
        [[ -n "$iso_file" ]] && [[ -f "$iso_file" ]] && rm -f "$iso_file"
    fi
    
    # 3. Variablen zurücksetzen (immer)
    discinfo_init
}

# ===========================================================================
# common_collect_software_info
# ---------------------------------------------------------------------------
# Funktion.: Sammelt Informationen über installierte Core-Software
# Parameter: keine
# Rückgabe.: Schreibt JSON-Datei mit Software-Informationen
# ===========================================================================
common_collect_software_info() {
    log_debug "COMMON: Sammle Software-Informationen..."
    
    # Lade INI-Datei um Dependencies zu lesen
    local ini_file="${INSTALL_DIR}/conf/libcommon.ini"
    if [[ ! -f "$ini_file" ]]; then
        log_error "COMMON: INI-Datei nicht gefunden: $ini_file"
        return 1
    fi
    
    # Lese Dependencies aus INI
    local dependencies
    dependencies=$(grep -A 10 "^\[dependencies\]" "$ini_file" | grep -E "^(external|optional)=" | cut -d'=' -f2 | tr '\n' ',' | sed 's/,$//')
    
    if [[ -z "$dependencies" ]]; then
        log_debug "COMMON: Keine Dependencies in INI definiert"
        return 0
    fi
    
    # Nutze zentrale Funktion aus libsysteminfo.sh
    if type -t systeminfo_check_software_list &>/dev/null; then
        local json_result
        json_result=$(systeminfo_check_software_list "$dependencies")
        
        # Speichere in api/common_software_info.json
        local output_file
        output_file="$(folders_get_api_dir)/common_software_info.json"
        echo "$json_result" > "$output_file"
        
        log_debug "COMMON: Software-Informationen gespeichert in $output_file"
        return 0
    else
        log_error "COMMON: systeminfo_check_software_list nicht verfügbar"
        return 1
    fi
}

# ===========================================================================
# common_get_software_info
# ---------------------------------------------------------------------------
# Funktion.: Gibt Software-Informationen als JSON zurück
# Parameter: keine
# Rückgabe.: JSON-String mit Software-Informationen
# ===========================================================================
common_get_software_info() {
    local cache_file
    cache_file="$(folders_get_api_dir)/common_software_info.json"
    
    # Wenn Cache existiert und < 1 Stunde alt, verwende ihn
    if [[ -f "$cache_file" ]]; then
        local cache_age
        cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
        if [[ $cache_age -lt 3600 ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    # Sonst neu sammeln
    common_collect_software_info
    
    # Ausgabe
    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
    else
        echo '{"software":[],"error":"Cache-Datei nicht gefunden"}'
    fi
}
