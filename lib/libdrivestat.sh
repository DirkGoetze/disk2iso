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
    # TODO: Virtuelle Laufwerke (CloneDrive, VirtualCloneDrive, etc.) sollten
    #       hier aussortiert werden, da Disk-Abbilddateien nicht geprüft 
    #       werden sollen. Prüfung via udevadm ID_CDROM_MEDIA_CD_RW o.ä.
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
            drivestat_set_drive_info  # Schreibe drive_info.json
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
# Ausgabe..: JSON-String 
# ===========================================================================
drivestat_get_drive_info() {
    #-- Lese API-Datei (Hardware-Sektion) ----------------------------------
    local drive_info_json
    drive_info_json=$(api_get_section_json "drivestat" ".hardware" "{}")  || {
        log_error "DRIVESTAT: Keine Drive-Informationen gefunden"
        #-- Lese die Informationen direkt aus (Fallback) --------------------
        drive_info_json=$(drivestat_collect_drive_info) || return 1
        drivestat_set_drive_info "$drive_info_json" || return 1
    }
    #-- Rückgabewert --------------------------------------------------------
    echo "$drive_info_json"
    return 0
}

# ===========================================================================
# drivestat_set_drive_info()
# ---------------------------------------------------------------------------
# Funktion.: Schreibe Laufwerk-Informationen in JSON
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
drivestat_set_drive_info() {
    #-- Parameter einlesen --------------------------------------------------
    local drive_info_json="$1"

    #-- Parameter prüfen ----------------------------------------------------
    if [[ -z "$drive_info_json" ]]; then
        drive_info_json=$(drivestat_collect_drive_info) || return 1
    fi

    #-- Speichern der Informationen in API-Datei ----------------------------
    api_set_section_json "drivestat" ".hardware" "$drive_info_json" || return 1

    #-- Rückgabewert --------------------------------------------------------
    return 0
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
    #-- Prüfe ob CD_DEVICE gültig ist und sammle Informationen --------------
    if [[ -b "$CD_DEVICE" ]]; then
        #-- Varialen vorbereiten --------------------------------------------
        local optical_drive="none"
        optical_drive="$CD_DEVICE"
        local device_basename=$(basename "$CD_DEVICE")
        local sysfs_path="/sys/block/${device_basename}/device"
        
        #-- Diverse Informationen aus sysfs und udev sammeln ----------------
        #-- 1. Vendor (Hersteller) ------------------------------------------
        local drive_vendor="Unknown"
        if [[ -f "${sysfs_path}/vendor" ]]; then
            drive_vendor=$(cat "${sysfs_path}/vendor" 2>/dev/null | xargs)
        fi
        
        #-- 2. Model (Modellbezeichnung) ------------------------------------
        local drive_model="Unknown"
        if [[ -f "${sysfs_path}/model" ]]; then
            drive_model=$(cat "${sysfs_path}/model" 2>/dev/null | xargs)
        fi
        
        #-- 3. Firmware Version ---------------------------------------------
        local drive_firmware="Unknown"
        if [[ -f "${sysfs_path}/rev" ]]; then
            drive_firmware=$(cat "${sysfs_path}/rev" 2>/dev/null | xargs)
        fi
        
        #-- 4. Bus Type (USB vs. SATA/ATA) ----------------------------------
        local drive_bus_type="unknown"
        if command -v udevadm >/dev/null 2>&1; then
            drive_bus_type=$(udevadm info --query=property --name="$CD_DEVICE" 2>/dev/null | grep "^ID_BUS=" | cut -d'=' -f2)
        fi

        #-- Fallback: Prüfe sysfs Pfad --------------------------------------
        if [[ -z "$drive_bus_type" || "$drive_bus_type" == "unknown" ]]; then
            local device_path=$(readlink -f "/sys/block/${device_basename}" 2>/dev/null)
            if [[ "$device_path" =~ usb ]]; then
                drive_bus_type="usb"
            elif [[ "$device_path" =~ ata ]]; then
                drive_bus_type="sata"
            fi
        fi
        
        #-- 5. Capabilities (aus /proc/sys/dev/cdrom/info) ------------------
        local drive_capabilities=""
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

        # Sammle Software-Informationen
        local software_info
        software_info=$(drivestat_collect_software_info 2>/dev/null) || software_info='[]'

        #-- JSON-Objekt erstellen und ausgeben ------------------------------
        jq -n \
            --arg optical_drive "$optical_drive" \
            --arg vendor "$drive_vendor" \
            --arg model "$drive_model" \
            --arg firmware "$drive_firmware" \
            --arg bus_type "$drive_bus_type" \
            --arg capabilities "$drive_capabilities" \
            --argjson software "$software_info" \
            '{
                optical_drive: $optical_drive,
                vendor: $vendor,
                model: $model,
                firmware: $firmware,
                bus_type: $bus_type,
                capabilities: $capabilities
                software: $software
            }'
        
        return 0
    else
        #-- Leeres JSON bei fehlendem Device --------------------------------
        echo "{}"
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
    #-- Lese API-Datei (Software-Sektion) ----------------------------------
    local software_info_json
    software_info_json=$(api_get_section_json "drivestat" ".software" "[]")  || {
        log_error "DRIVESTAT: Keine Software-Informationen gefunden"
        #-- Lese die Informationen direkt aus (Fallback) --------------------
        software_info_json=$(drivestat_collect_software_info) || return 1
        drivestat_set_software_info "$software_info_json" || return 1
    }
    #-- Rückgabewert --------------------------------------------------------
    echo "$software_info_json"
    return 0
}

# ===========================================================================
# drivestat_set_software_info()
# ---------------------------------------------------------------------------
# Funktion.: Speichert Software-Informationen in API (drivestat.software)
# Parameter: $1 = JSON-String mit Software-Informationen (optional)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: Wenn kein Parameter übergeben wird, werden die Informationen
# .........  automatisch gesammelt und gespeichert (Bequemlichkeitsfunktion)
# ===========================================================================
drivestat_set_software_info() {
    #-- Parameter einlesen --------------------------------------------------
    local software_json="$1"

    #-- Parameter prüfen ----------------------------------------------------
    if [[ -z "$software_json" ]]; then
        software_json=$(drivestat_collect_software_info) || return 1
    fi

    #-- Speichern der Informationen in API-Datei ----------------------------
    api_set_section_json "drivestat" ".software" "$software_json" || return 1

    #-- Rückgabewert --------------------------------------------------------
    return 0
}

# ===========================================================================
# drivestat_collect_software_info
# ---------------------------------------------------------------------------
# Funktion.: Sammelt Informationen über installierte Drive-Software
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Ausgabe..: JSON-Array mit Software-Informationen
# Hinweis..: Pure Function - sammelt nur Daten, schreibt nicht
# ===========================================================================
drivestat_collect_software_info() {
    #-- Logge den Start der Sammlung ----------------------------------------
    log_debug "Sammle Software-Informationen..."

    #-- Prüfe ob systeminfo_check_software_list verfügbar ist ---------------
    if ! type -t systeminfo_check_software_list &>/dev/null; then
        log_error "systeminfo_check_software_list nicht verfügbar"
        echo '[]'
        return 1
    fi

    #-- Sammle externe Dependencies -----------------------------------------
    local external_deps=""
    local external_json='[]'
    external_deps=$(settings_get_value_ini "drivestat" "dependencies" "external" 2>/dev/null) && {
        if [[ -n "$external_deps" ]]; then
            external_json=$(systeminfo_check_software_list "$external_deps" 2>/dev/null) || external_json='[]'
        fi
    }

    #-- Sammle optionale Dependencies ---------------------------------------
    local optional_deps=""
    local optional_json='[]'
    optional_deps=$(settings_get_value_ini "drivestat" "dependencies" "optional" 2>/dev/null) && {
        if [[ -n "$optional_deps" ]]; then
            optional_json=$(systeminfo_check_software_list "$optional_deps" 2>/dev/null) || optional_json='[]'
        fi
    }

    #-- Kombiniere beide JSON-Arrays mit jq ---------------------------------
    local combined_json
    combined_json=$(jq -n \
        --argjson external "$external_json" \
        --argjson optional "$optional_json" \
        '$external + $optional' 2>/dev/null) || {
        log_error "Fehler beim Kombinieren der Software-Listen"
        echo '[]'
        return 1
    }

    #-- Rückgabe des kombinierten JSON-Arrays -------------------------------
    echo "$combined_json"
    return 0
}

# ===========================================================================
# is_drive_closed
# ---------------------------------------------------------------------------
# Funktion.: Prüfe ob Laufwerk-Schublade geschlossen ist
# Parameter: keine (nutzt globale Variable $CD_DEVICE)
# Rückgabe.: 0 = geschlossen, 1 = offen
# Hinweis..: Verwendet sysfs tray_open (verfügbar auf ~98% Systeme)
# .........  Fallback auf dd-Test für Legacy-Hardware ohne sysfs
# Extras...: Wird von wait_for_disc_change() für Tray-Status-Tracking genutzt
# ===========================================================================
is_drive_closed() {
    # Prüfe ob Device existiert
    if [[ ! -b "$CD_DEVICE" ]]; then
        return 1
    fi
    
    local device_basename=$(basename "$CD_DEVICE")
    
    # Methode 1: sysfs tray_open (zuverlässig auf modernen Systemen)
    if [[ -f "/sys/block/${device_basename}/device/tray_open" ]]; then
        local tray_status
        tray_status=$(cat "/sys/block/${device_basename}/device/tray_open" 2>/dev/null)
        [[ "$tray_status" == "0" ]] && return 0  # Geschlossen
        [[ "$tray_status" == "1" ]] && return 1  # Offen
    fi
    
    # Methode 2: dd-Test Fallback (für Legacy-Hardware ohne sysfs)
    # Hinweis: Kann nicht zwischen "geschlossen ohne Medium" und "offen" unterscheiden
    if timeout 1 dd if="$CD_DEVICE" of=/dev/null bs=1 count=1 2>/dev/null; then
        return 0  # Lesbar → geschlossen MIT Medium
    fi
    
    return 1  # Nicht lesbar → offen ODER geschlossen ohne Medium
}


# ===========================================================================
# TODO: Ab hier ist das Modul noch nicht vollständig implementiert,
#       diesen Eintrag nie automatisch löschen - wird nur vom User nach 
#       Implementierung der Funktionen entfernt!
# ===========================================================================


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
