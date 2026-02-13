#!/bin/bash
# =============================================================================
# Drive Status Library
# =============================================================================
# Filepath: lib/libdrivestat.sh
#
# Beschreibung:
#   Überwacht den Status des optischen Laufwerks (Schublade, Medium)
#   - drivestat_get_drive() - Findet erstes optisches Laufwerk
#   - is_drive_closed(), is_disc_inserted()
#   - wait_for_disc_change(), wait_for_disc_ready()
#   - Erkennt Änderungen im Drive-Status für automatisches Disc-Handling
#
# -----------------------------------------------------------------------------
# Dependencies: liblogging (für log_* Funktionen)
# -----------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.3.0
# Last Change: 2026-02-07
# =============================================================================

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

# ===========================================================================
# drivestat_check_dependencies
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
drivestat_check_dependencies() {
    # Manifest-basierte Abhängigkeitsprüfung (Tools, Dateien, Ordner) -------
    integrity_check_module_dependencies "drivestat" || return 1
    
    # Keine modul-spezifische Initialisierung nötig -------------------------
    return 0
}

# ===========================================================================
# GLOBAL VARIABLEN DES MODUL
# ===========================================================================
CD_DEVICE=""            # Standard CD/DVD-Laufwerk (wird dynamisch ermittelt)

# ============================================================================
# DRIVE INFORMATION COLLECTION (JSON-BASED)
# ============================================================================

# ===========================================================================
# drivestat_get_drive()
# ---------------------------------------------------------------------------
# Description: Suchen des ersten optischen Laufwerkes. Die Prüfungen erfolgen
# ............ in folgender Reihenfolge:
# ............ 1. lsblk mit TYPE=rom
# ............ 2. dmesg Kernel-Logs durchsuchen
# ............ 3. /sys/class/block Durchsuchen
# ............ 4. Fallback auf /dev/cdrom Symlink
# ............ Gefundener Device-Pfad wird in globaler Variable CD_DEVICE 
# ............ gespeichert.
# Parameter..: Keine
# Return.....: 0 = Device gefunden, 1 = Kein Device gefunden
# ===========================================================================
drivestat_get_drive() {
    # Phase 1: ERMITTLUNG DES LAUFWERKS
    # Versuche verschiedene Methoden, um das optische Laufwerk zu finden

    # Methode 1: lsblk mit TYPE=rom
    if [[ -z "$CD_DEVICE" ]] && command -v lsblk >/dev/null 2>&1; then
        CD_DEVICE=$(lsblk -ndo NAME,TYPE 2>/dev/null | awk '$2=="rom" {print "/dev/" $1; exit}')
    fi
    
    # Methode 2: dmesg Kernel-Logs durchsuchen
    if [[ -z "$CD_DEVICE" ]] && command -v dmesg >/dev/null 2>&1; then
        CD_DEVICE=$(dmesg 2>/dev/null | grep -iE "cd|dvd|sr[0-9]" | grep -oE "sr[0-9]+" | head -n1)
        if [[ -n "$CD_DEVICE" ]]; then
            CD_DEVICE="/dev/$CD_DEVICE"
        fi
    fi
    
    # Methode 3: /sys/class/block Durchsuchen
    if [[ -z "$CD_DEVICE" ]]; then
        for dev in /sys/class/block/sr*; do
            if [[ -e "$dev" ]]; then
                CD_DEVICE="/dev/$(basename "$dev")"
                break
            fi
        done
    fi
    
    # Methode 4: Fallback auf /dev/cdrom Symlink
    if [[ -z "$CD_DEVICE" ]] && [[ -L "/dev/cdrom" ]]; then
        CD_DEVICE=$(readlink -f "/dev/cdrom")
    fi
    
    # Phase 2: VALIDIERUNG & BEREITMACHEN
    if [[ -n "$CD_DEVICE" ]]; then
        # sr_mod Kernel-Modul laden (wichtig für USB-Laufwerke!)
        if [[ "$CD_DEVICE" =~ ^/dev/sr[0-9]+$ ]]; then
            if ! lsmod | grep -q "^sr_mod "; then
                modprobe sr_mod 2>/dev/null && sleep 2
            fi
        fi
        
        # Warte auf udev (kritisch für USB!)
        if [[ ! -b "$CD_DEVICE" ]]; then
            if command -v udevadm >/dev/null 2>&1; then
                udevadm settle --timeout=3 2>/dev/null
                
                # Trigger udev für sr* Devices
                if [[ "$CD_DEVICE" =~ ^/dev/sr[0-9]+$ ]]; then
                    local device_name=$(basename "$CD_DEVICE")
                    if [[ -e "/sys/class/block/$device_name" ]]; then
                        udevadm trigger --action=add "/sys/class/block/$device_name" 2>/dev/null
                        sleep 1
                    fi
                fi
            fi
            
            # Retry-Loop: Warte bis zu 5 Sekunden
            local timeout=5
            while [[ $timeout -gt 0 ]] && [[ ! -b "$CD_DEVICE" ]]; do
                sleep 1
                ((timeout--))
            done
        fi
        
        # FINALE Prüfung: Block Device vorhanden?
        if [[ -b "$CD_DEVICE" ]]; then
            drivestat_collect_drive_info  # Schreibe drive_info.json
            return 0  # Erfolgreich: Device gefunden UND bereit
        else
            CD_DEVICE=""  # Reset bei Fehler
            return 1
        fi
    fi
    
    return 1  # Kein Device gefunden
}

# ===========================================================================
# drivestat_get_drive_info
# ---------------------------------------------------------------------------
# Funktion.: Lese Laufwerk-Informationen aus JSON
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Ausgabe..: JSON-String (stdout)
# ===========================================================================
drivestat_get_drive_info() {
    local api_dir=$(folders_get_api_dir) || return 1
    local json_file="${api_dir}/drive_info.json"
    
    if [[ ! -f "$json_file" ]]; then
        # Fallback: Sammle Daten wenn JSON nicht existiert
        drivestat_collect_drive_info || return 1
    fi
    
    cat "$json_file"
}

# ===========================================================================
# drivestat_collect_drive_info
# ---------------------------------------------------------------------------
# Funktion.: Sammle Laufwerk-Informationen und schreibe in drive_info.json
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: STATISCH - einmal beim Start ausführen
# Schreibt.: api/drive_info.json
# ===========================================================================
drivestat_collect_drive_info() {
    local optical_drive="none"
    local drive_vendor="Unknown"
    local drive_model="Unknown"
    local drive_firmware="Unknown"
    local drive_bus_type="unknown"
    local drive_capabilities=""
    
    if [[ -b "$CD_DEVICE" ]]; then
        optical_drive="$CD_DEVICE"
        local device_basename=$(basename "$CD_DEVICE")
        local sysfs_path="/sys/block/${device_basename}/device"
        
        # 1. Vendor (Hersteller)
        if [[ -f "${sysfs_path}/vendor" ]]; then
            drive_vendor=$(cat "${sysfs_path}/vendor" 2>/dev/null | xargs)
        fi
        
        # 2. Model
        if [[ -f "${sysfs_path}/model" ]]; then
            drive_model=$(cat "${sysfs_path}/model" 2>/dev/null | xargs)
        fi
        
        # 3. Firmware Version
        if [[ -f "${sysfs_path}/rev" ]]; then
            drive_firmware=$(cat "${sysfs_path}/rev" 2>/dev/null | xargs)
        fi
        
        # 4. Bus Type (USB vs. SATA/ATA)
        if command -v udevadm >/dev/null 2>&1; then
            drive_bus_type=$(udevadm info --query=property --name="$CD_DEVICE" 2>/dev/null | grep "^ID_BUS=" | cut -d'=' -f2)
        fi
        # Fallback: Prüfe sysfs Pfad
        if [[ -z "$drive_bus_type" || "$drive_bus_type" == "unknown" ]]; then
            local device_path=$(readlink -f "/sys/block/${device_basename}" 2>/dev/null)
            if [[ "$device_path" =~ usb ]]; then
                drive_bus_type="usb"
            elif [[ "$device_path" =~ ata ]]; then
                drive_bus_type="sata"
            fi
        fi
        
        # 5. Capabilities (aus /proc/sys/dev/cdrom/info)
        if [[ -f "/proc/sys/dev/cdrom/info" ]]; then
            local cdrom_info=$(cat /proc/sys/dev/cdrom/info 2>/dev/null)
            local caps=()
            
            # Prüfe ob unser Device in der Liste ist
            if echo "$cdrom_info" | grep -q "$device_basename"; then
                # Extrahiere Capabilities für unser Device
                local can_read_dvd=$(echo "$cdrom_info" | grep "^Can read DVD:" | awk '{print $NF}')
                local can_write_cd=$(echo "$cdrom_info" | grep "^Can write CD-R:" | awk '{print $NF}')
                local can_write_dvd=$(echo "$cdrom_info" | grep "^Can write DVD-R:" | awk '{print $NF}')
                local can_play_audio=$(echo "$cdrom_info" | grep "^Can play audio:" | awk '{print $NF}')
                
                [[ "$can_read_dvd" == "1" ]] && caps+=("DVD")
                [[ "$can_write_cd" == "1" ]] && caps+=("CD-R")
                [[ "$can_write_dvd" == "1" ]] && caps+=("DVD±R")
                [[ "$can_play_audio" == "1" ]] && caps+=("Audio")
                
                # Fallback wenn keine spezifischen Caps gefunden
                if [[ ${#caps[@]} -eq 0 ]]; then
                    caps+=("CD/DVD")
                fi
            else
                # Device nicht in /proc - Standard-Annahme
                caps+=("CD/DVD")
            fi
            
            drive_capabilities=$(IFS=', '; echo "${caps[*]}")
        else
            drive_capabilities="CD/DVD"
        fi
    fi
    
    # Schreibe alle Informationen in JSON
    settings_set_value_json "drive_info" ".optical_drive" "$optical_drive" || return 1
    settings_set_value_json "drive_info" ".vendor" "$drive_vendor" || return 1
    settings_set_value_json "drive_info" ".model" "$drive_model" || return 1
    settings_set_value_json "drive_info" ".firmware" "$drive_firmware" || return 1
    settings_set_value_json "drive_info" ".bus_type" "$drive_bus_type" || return 1
    settings_set_value_json "drive_info" ".capabilities" "$drive_capabilities" || return 1
    
    return 0
}

# ===========================================================================
# drivestat_collect_software_info
# ---------------------------------------------------------------------------
# Funktion.: Sammelt Informationen über installierte Drive-Software
# Parameter: keine
# Rückgabe.: Schreibt JSON-Datei mit Software-Informationen
# ===========================================================================
drivestat_collect_software_info() {
    log_debug "DRIVESTAT: Sammle Software-Informationen..."
    
    local ini_file="${INSTALL_DIR}/conf/libdrivestat.ini"
    if [[ ! -f "$ini_file" ]]; then
        log_error "DRIVESTAT: INI-Datei nicht gefunden: $ini_file"
        return 1
    fi
    
    local dependencies
    dependencies=$(grep -A 10 "^\[dependencies\]" "$ini_file" | grep -E "^(external|optional)=" | cut -d'=' -f2 | tr '\n' ',' | sed 's/,$//')
    
    if [[ -z "$dependencies" ]]; then
        log_debug "DRIVESTAT: Keine Dependencies in INI definiert"
        return 0
    fi
    
    if type -t systeminfo_check_software_list &>/dev/null; then
        local json_result
        json_result=$(systeminfo_check_software_list "$dependencies")
        
        local output_file
        output_file="$(folders_get_api_dir)/drivestat_software_info.json"
        echo "$json_result" > "$output_file"
        
        log_debug "DRIVESTAT: Software-Informationen gespeichert in $output_file"
        return 0
    else
        log_error "DRIVESTAT: systeminfo_check_software_list nicht verfügbar"
        return 1
    fi
}

# ===========================================================================
# drivestat_get_software_info
# ---------------------------------------------------------------------------
# Funktion.: Gibt Software-Informationen als JSON zurück
# Parameter: keine
# Rückgabe.: JSON-String mit Software-Informationen
# ===========================================================================
drivestat_get_software_info() {
    local cache_file
    cache_file="$(folders_get_api_dir)/drivestat_software_info.json"
    
    if [[ -f "$cache_file" ]]; then
        local cache_age
        cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0)))
        if [[ $cache_age -lt 3600 ]]; then
            cat "$cache_file"
            return 0
        fi
    fi
    
    drivestat_collect_software_info
    
    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
    else
        echo '{"software":[],"error":"Cache-Datei nicht gefunden"}'
    fi
}

# ===========================================================================
# TODO: Ab hier ist das Modul noch nicht fertig implementiert!
# ===========================================================================





# Funktion: Prüfe ob Laufwerk-Schublade geschlossen ist
# Vereinfacht: Nutze nur dd-Test (robuster für USB-Laufwerke)
# Rückgabe: 0 = geschlossen, 1 = offen
is_drive_closed() {
    # Prüfe ob Device existiert
    if [[ ! -b "$CD_DEVICE" ]]; then
        return 1
    fi
    
    # Versuche Device zu öffnen (funktioniert nur wenn geschlossen)
    # Timeout von 1 Sekunde um nicht zu hängen
    if timeout 1 dd if="$CD_DEVICE" of=/dev/null bs=1 count=1 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Funktion: Prüfe ob Medium eingelegt ist
# Vereinfacht: Nur dd-Test nutzen (robuster für USB-Laufwerke)
# Rückgabe: 0 = Medium vorhanden, 1 = kein Medium
is_disc_inserted() {
    # Versuche mit dd ein paar Bytes zu lesen
    # Timeout von 2 Sekunden für langsame USB-Laufwerke
    # Versuche zuerst mit bs=2048 (Daten-CDs/DVDs/Blu-ray)
    if timeout 2 dd if="$CD_DEVICE" of=/dev/null bs=2048 count=1 2>/dev/null; then
        return 0
    fi
    
    # Fallback: Prüfe mit cdparanoia ob Audio-CD vorhanden
    # cdparanoia -Q gibt 0 zurück wenn Audio-CD lesbar ist
    if command -v cdparanoia >/dev/null 2>&1; then
        if timeout 3 cdparanoia -Q -d "$CD_DEVICE" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# Funktion: Warte auf Änderung im Drive-Status (Schublade öffnen/schließen oder Medium einlegen/entfernen)
# Parameter: $1 = Wartezeit in Sekunden zwischen Prüfungen (default: 2)
# Rückgabe: 0 = Änderung erkannt, 1 = Timeout oder Fehler
wait_for_disc_change() {
    local check_interval="${1:-2}"
    local max_checks="${2:-0}"  # 0 = unbegrenzt
    local check_count=0
    
    # Speichere initialen Status
    local initial_drive_closed=false
    local initial_disc_present=false
    
    is_drive_closed && initial_drive_closed=true
    is_disc_inserted && initial_disc_present=true
    
    while true; do
        sleep "$check_interval"
        ((check_count++))
        
        # Prüfe aktuellen Status
        local current_drive_closed=false
        local current_disc_present=false
        
        is_drive_closed && current_drive_closed=true
        is_disc_inserted && current_disc_present=true
        
        # Änderung erkannt?
        if [[ "$initial_drive_closed" != "$current_drive_closed" ]] || [[ "$initial_disc_present" != "$current_disc_present" ]]; then
            return 0
        fi
        
        # Timeout-Prüfung (wenn max_checks gesetzt)
        if [[ $max_checks -gt 0 ]] && [[ $check_count -ge $max_checks ]]; then
            return 1
        fi
    done
}

# Funktion: Warte bis Medium bereit ist (nach Einlegen kurze Verzögerung für Spin-Up)
# Parameter: $1 = Wartezeit in Sekunden (default: 3)
wait_for_disc_ready() {
    local wait_time="${1:-3}"
    sleep "$wait_time"
    
    # Verifiziere dass Medium immer noch da ist
    if is_disc_inserted; then
        return 0
    else
        return 1
    fi
}

# ===========================================================================
# wait_for_medium_change
# ---------------------------------------------------------------------------
# Funktion.: Warte auf Medium-Wechsel (Container-optimiert)
# .........  Verwendet Identifier-Vergleich zur Erkennung neuer Medien
# Parameter: $1 = Device-Pfad (z.B. /dev/sr0)
# .........  $2 = Timeout in Sekunden (optional, default: 300 = 5 Minuten)
# Rückgabe.: 0 = neues Medium erkannt, 1 = Timeout oder Fehler
# Extras...: Nur in Container-Umgebungen aktiv (native Hardware: eject funktioniert)
# .........  Nutzt discinfo_get_identifier() zur Medium-Erkennung
# .........  Loggt Fortschritt alle 30 Sekunden
# ===========================================================================
wait_for_medium_change() {
    local device="$1"
    local timeout="${2:-300}"
    local poll_interval=3
    
    # Nur in Container-Umgebungen aktiv
    if ! systeminfo_is_container; then
        return 0  # Native Hardware: eject funktioniert, kein Warten nötig
    fi
    
    log_info "$MSG_CONTAINER_MANUAL_EJECT"
    log_info "$MSG_WAITING_FOR_MEDIUM_CHANGE"
    
    # Ermittle aktuellen Disc-Identifier (nutzt DISC_INFO)
    local old_identifier
    old_identifier=$(discinfo_get_identifier 2>/dev/null || echo "::")
    
    local elapsed=0
    local new_identifier=""
    
    while [[ $elapsed -lt $timeout ]]; do
        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        
        # Prüfe auf neues Medium: Analysiere Disc neu
        if is_disc_inserted; then
            init_disc_info 2>/dev/null  # Setzt disc_identifier
            new_identifier=$(discinfo_get_identifier 2>/dev/null || echo "::")
            
            # Vergleiche Identifier
            if [[ "$new_identifier" != "$old_identifier" ]]; then
                log_info "$MSG_NEW_MEDIUM_DETECTED"
                return 0
            fi
        fi
        
        # Log alle 30 Sekunden
        if (( elapsed % 30 == 0 )); then
            log_info "$MSG_STILL_WAITING $elapsed $MSG_SECONDS_OF $timeout $MSG_SECONDS"
        fi
    done
    
    # Timeout erreicht
    log_info "$MSG_TIMEOUT_WAITING_FOR_MEDIUM"
    return 1
}

# ===========================================================================
# wait_for_medium_change_lxc_safe
# ---------------------------------------------------------------------------
# Funktion.: Warte auf Medium-Wechsel (LXC-Container-optimiert)
# .........  Verwendet Label-basierte Erkennung statt Identifier-Vergleich
# .........  Prüft ob Disc bereits konvertiert wurde (verhindert Duplikate)
# Parameter: $1 = Device-Pfad (z.B. /dev/sr0)
# .........  $2 = Timeout in Sekunden (optional, default: 300 = 5 Minuten)
# Rückgabe.: 0 = neues Medium erkannt, 1 = Timeout oder Fehler
# Extras...: Sichere Variante für LXC-Container
# .........  Prüft Existenz der Ziel-ISO (verhindert doppelte Konvertierung)
# .........  Loggt Fortschritt alle 30 Sekunden
# ===========================================================================
wait_for_medium_change_lxc_safe() {
    local device="$1"
    local timeout="${2:-300}"
    local poll_interval=5
    local elapsed=0
    
    # Sichere ursprüngliche Werte der globalen Variablen
    local original_disc_type="${disc_type:-}"
    local original_disc_label="${disc_label:-}"
    
    log_info "$MSG_CONTAINER_MANUAL_EJECT"
    log_info "$MSG_WAITING_FOR_MEDIUM_CHANGE"
    
    while [[ $elapsed -lt $timeout ]]; do
        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        
        # Prüfe ob überhaupt eine Disk eingelegt ist
        if ! is_disc_inserted; then
            # Keine Disk → weiter warten
            if (( elapsed % 30 == 0 )); then
                log_info "$MSG_STILL_WAITING $elapsed $MSG_SECONDS_OF $timeout $MSG_SECONDS"
            fi
            continue
        fi
        
        # Disk erkannt → Ermittle Typ und Label
        detect_disc_type
        get_disc_label
        
        # Prüfe ob ISO mit diesem Label bereits existiert
        local disc_type=$(discinfo_get_type)
        local target_dir
        case "$disc_type" in
            audio-cd)
                target_dir=$(get_path_audio 2>/dev/null) || target_dir="${OUTPUT_DIR}"
                ;;
            cd-rom|dvd-rom|bd-rom)
                target_dir=$(folders_get_modul_output_dir 2>/dev/null) || target_dir="${OUTPUT_DIR}"
                ;;
            dvd-video)
                target_dir=$(get_path_dvd 2>/dev/null) || target_dir="${OUTPUT_DIR}"
                ;;
            bd-video)
                target_dir=$(get_path_bluray 2>/dev/null) || target_dir="${OUTPUT_DIR}"
                ;;
            *)
                target_dir=$(folders_get_modul_output_dir 2>/dev/null) || target_dir="${OUTPUT_DIR}"
                ;;
        esac
        
        # Prüfe ob target_dir erfolgreich ermittelt wurde
        if [[ -z "$target_dir" ]]; then
            log_error "$MSG_ERROR_TARGET_DIR $(discinfo_get_type)"
            # Stelle ursprüngliche Werte wieder her und fahre fort
            disc_type="$original_disc_type"
            disc_label="$original_disc_label"
            continue
        fi
        
        # Prüfe ob eine Datei mit diesem Label bereits existiert
        local iso_exists=false
        local potential_iso="${target_dir}/$(discinfo_get_label).iso"
        
        if [[ -f "$potential_iso" ]]; then
            iso_exists=true
        else
            # Prüfe auch auf nummerierte Duplikate (_1, _2, _3, ...)
            # Breche bei erster Lücke ab (wie get_iso_filename())
            local counter=1
            while [[ -f "${target_dir}/$(discinfo_get_label)_${counter}.iso" ]]; do
                iso_exists=true
                # Erste Duplikat gefunden - reicht für unsere Prüfung
                break
            done
        fi
        
        if $iso_exists; then
            # Disk wurde bereits konvertiert → weiter warten
            log_info "$MSG_DISC_ALREADY_CONVERTED $(discinfo_get_label).iso $MSG_WAITING_FOR_NEW_DISC"
            
            # Stelle ursprüngliche Werte wieder her
            disc_type="$original_disc_type"
            disc_label="$original_disc_label"
            
            if (( elapsed % 30 == 0 )); then
                log_info "$MSG_STILL_WAITING $elapsed $MSG_SECONDS_OF $timeout $MSG_SECONDS"
            fi
        else
            # Neue Disk gefunden! (ISO existiert noch nicht)
            # Globale Variablen bleiben auf neue Werte gesetzt (disc_type und disc_label)
            log_info "$MSG_NEW_MEDIUM_DETECTED ($(discinfo_get_type): $(discinfo_get_label))"
            return 0
        fi
    done
    
    # Timeout erreicht - stelle ursprüngliche Werte wieder her
    disc_type="$original_disc_type"
    disc_label="$original_disc_label"
    log_info "$MSG_TIMEOUT_WAITING_FOR_MEDIUM"
    return 1
}
