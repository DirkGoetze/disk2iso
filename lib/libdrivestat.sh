#!/bin/bash
# =============================================================================
# Drive Status Library
# =============================================================================
# Filepath: lib/libdrivestat.sh
#
# Beschreibung:
#   Überwacht den Status des optischen Laufwerks (Schublade, Medium)
#   - drivestat_get_drive() - Findet erstes optisches Laufwerk
#   - drivestat_get_closed(), drivestat_get_inserted()
#   - drivestat_start_monitor(), drivestat_stop_monitor()
#   - Background-Monitoring mit automatischer Status-Erkennung
#
# -----------------------------------------------------------------------------
# Dependencies: liblogging (für log_* Funktionen)
# -----------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.3.0
# Last Change: 2026-02-26
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

    #-- modul-spezifische Initialisierung -----------------------------------
    drivestat_reset

    #-- Alle Prüfungen bestanden, Framework ist verfügbar -------------------
    return 0
}

# ===========================================================================
# GLOBAL VARIABLEN DES MODUL
# ===========================================================================
# ---------------------------------------------------------------------------
# DRIVE CAPABILITIES CONSTANTS (Red Book compliant)
# ---------------------------------------------------------------------------
# Audio/CD Capabilities
readonly DRIVE_CAP_AUDIO_CD="Audio-CD"      # Red Book: CD-DA (Digital Audio)
readonly DRIVE_CAP_CD_ROM="CD-ROM"          # Yellow Book: CD-ROM (Read-Only)
readonly DRIVE_CAP_CD_R="CD-R"       # Orange Book Part II: CD-R (Recordable)
readonly DRIVE_CAP_CD_RW="CD-RW"   # Orange Book Part III: CD-RW (ReWritable)
readonly DRIVE_CAP_CD_R_RW="CD-R/RW"                # Combined: CD-R + CD-RW

# DVD Capabilities
readonly DRIVE_CAP_DVD_ROM="DVD-ROM"                    # DVD-ROM (Read-Only)
readonly DRIVE_CAP_DVD_R="DVD-R"                         # DVD-R (Recordable)
readonly DRIVE_CAP_DVD_RW="DVD-RW"                      # DVD-RW (ReWritable)
readonly DRIVE_CAP_DVD_PLUS_R="DVD+R"            # DVD+R (Alternative Format)
readonly DRIVE_CAP_DVD_PLUS_RW="DVD+RW"         # DVD+RW (Alternative Format)
readonly DRIVE_CAP_DVD_RAM="DVD-RAM"                # DVD-RAM (Random Access)
readonly DRIVE_CAP_DVD_PM_RW="DVD±R/RW"      # Combined: DVD-R/RW + DVD+R/RW

# Blu-ray Capabilities
readonly DRIVE_CAP_BD_ROM="BD-ROM"                       # BD-ROM (Read-Only)
readonly DRIVE_CAP_BD_R="BD-R"                            # BD-R (Recordable)
readonly DRIVE_CAP_BD_RE="BD-RE"                         # BD-RE (ReWritable)

# Fallback/Generic
readonly DRIVE_CAP_CD_DVD="CD/DVD"                    # Generic Optical Drive
readonly DRIVE_CAP_UNKNOWN="unknown"                   # Unknown Capabilities

readonly DRIVE_STATUS_EMPTY="empty"    # Laufwerk leer, kein Medium eingelegt
readonly DRIVE_STATUS_OPEN="open"                            # Laufwerk offen
readonly DRIVE_STATUS_CLOSED="closed"     # Laufwerk geschlossen, ohne Medium
readonly DRIVE_STATUS_INSERTED="inserted"  # Laufwerk geschlossen, mit Medium
readonly DRIVE_STATUS_READY="ready"                         # Laufwerk bereit
readonly DRIVE_STATUS_ERROR="error"                            # Fehlerstatus

# ---------------------------------------------------------------------------
# Datenstruktur für Laufwerks-Informationen
# ---------------------------------------------------------------------------
# DRIVE_INFO: Laufwerksinformationen
declare -A DRIVE_INFO=(
    #==================== Technische Daten des Laufwerks ====================
    [drive]=""                  # Pfad zum optischen Laufwerk (z.B. /dev/sr0)
    [vendor]="unknown"            # Hersteller (z.B. "ASUS", "LG", "Pioneer")
    [model]="unknown"   # Modellbezeichnung (z.B. "DRW-24D5MT", "BDR-209DBK")
    [firmware]="unknown"     # Firmware-Version (z.B. "1.00", "1.01", "1.02")
    [bus_type]=""                                # USB, SATA, ATA, SCSI, etc.
    [capabilities]="unknown"           # "CD/DVD", "DVD±R", "BD-ROM", "Audio"
    #===================== Laufwerksstatus (Dynamisch) ======================
    [closed]=true      # true = Laufwerk geschlossen, false = Schublade offen
    [medium_inserted]=false    # true = Medium eingelegt, false = kein Medium
    [status]="$DRIVE_STATUS_EMPTY"  # empty, disc_inserted, disc_ready, error
)

# ===========================================================================
# drivestat_reset
# ---------------------------------------------------------------------------
# Funktion.: Initialisiere/Leere DRIVE_INFO Array
# Parameter: Keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
drivestat_reset() {
    #-- Reset der DRIVE_INFO-Variable auf Standardwerte ---------------------
    DRIVE_INFO[drive]=""
    DRIVE_INFO[vendor]="unknown"
    DRIVE_INFO[model]="unknown"
    DRIVE_INFO[firmware]="unknown"
    DRIVE_INFO[bus_type]=""
    DRIVE_INFO[capabilities]="none"

    DRIVE_INFO[closed]=true
    DRIVE_INFO[medium_inserted]=false
    DRIVE_INFO[status]="$DRIVE_STATUS_EMPTY"

    #-- Schreiben nach JSON & Loggen der Initialisierung --------------------
    api_set_section_json "drivestat" "drive_info" "$(api_create_json "DRIVE_INFO")" || return 1
    log_debug "$MSG_DEBUG_DRIVESTAT_RESET"
    return 0
}

# ===========================================================================
# drivestat_analyse
# ---------------------------------------------------------------------------
# Funktion.: Analysiere Laufwerk-Informationen und schreibe in API *.json
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beschr...: Orchestiert die Ermittlung aller relevanten Informationen zum
# .........  optischen Laufwerk in der korreten Reihenfolge.
# .........  01. drivestat_set_drive                        → 1. optisches LW
# .........  02. drivestat_set_vendor                         → 2. Hersteller
# .........  03. drivestat_set_model                   → 3. Modellbezeichnung
# .........  04. drivestat_set_firmware                 → 4. Firmware-Version
# .........  05. drivestat_set_bus_type        → 5. Bus-Typ (USB, SATA, etc.)
# .........  06. drivestat_set_capabilities         → 6. Laufwerksfähigkeiten
# ===========================================================================
drivestat_analyse() {
    #-- Start der Analyse im LOG vermerken ----------------------------------
    log_debug "$MSG_DEBUG_ANALYSE_START"

    #------------------------------------------------------------------------
    # Die Analyse erfolgt für jeden Wert durch den Aufruf des entsprechenden
    # Getter/Setter ohne Parameter. Dadurch wird die Auto-Detection des
    # Setter getriggert und der exaktestes Wert oder der Default-Wert für
    # dieses Disc-Info Feld ermittelt. Ein zusätzliches Loggen der Aktion
    # ist hierbei nicht notwendig, das dies durch den Getter/Setter/Detctor
    # bereits erfolgt.
    # -----------------------------------------------------------------------

    drivestat_set_drive || return 1                   # 1. Laufwerk ermitteln
    drivestat_set_vendor || return 1                # 2. Hersteller ermitteln
    drivestat_set_model || return 1          # 3. Modellbezeichnung ermitteln
    drivestat_set_firmware || return 1        # 4. Firmware-Version ermitteln
    drivestat_set_bus_type || return 1                 # 5. Bus-Typ ermitteln
    drivestat_set_capabilities || return 1  # 6. Laufwerksfähigkeit ermitteln

    #-- Schreiben nach JSON & Loggen der Analyseergebnisse ------------------
    api_set_section_json "drivestat" "drive_info" "$(api_create_json "DRIVE_INFO")"

    #-- Ende der Analyse im LOG vermerken -----------------------------------
    log_debug "$MSG_DEBUG_ANALYSE_COMPLETE"
    return 0
}

# ===========================================================================
# GETTER/SETTER FUNCTIONEN FÜR DRIVE_INFO
# ===========================================================================

# ===========================================================================
# drivestat_get_drive
# ---------------------------------------------------------------------------
# Funktion.: Gibt den Pfad zum optischen Laufwerk zurück (z.B. /dev/sr0)
# Parameter: Keine
# Ausgabe..: Pfad zum optischen Laufwerk (z.B. /dev/sr0) oder leerer String
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
drivestat_get_drive() {
    #-- Array Wert lesen ----------------------------------------------------
    local drive_path="${DRIVE_INFO[drive]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$drive_path" ]]; then
        log_debug "$(printf "$MSG_DEBUG_DRIVE_FOUND" "$drive_path")"
        echo "$drive_path"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    echo ""
    return 1
}

# ===========================================================================
# drivestat_set_drive
# ---------------------------------------------------------------------------
# Funktion.: Setzt den Pfad zum optischen Laufwerk (z.B. /dev/sr0)
# Parameter: $1 = Pfad zum optischen Laufwerk (z.B. /dev/sr0)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
drivestat_set_drive() {
    #-- Parameter übernehmen ------------------------------------------------
    local drive_path="$1"
    local old_value="${DRIVE_INFO[drive]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$drive_path" ]]; then
        drive_path=$(drivestat_detect_drive)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$drive_path" ]]; then
        log_error "$MSG_ERROR_NO_DRIVE_PATH"
        return 1
    fi

    #-- Prüfe ob das angegebene Device existiert und ein Block-Device ist ---
    if [[ -n "$drive_path" ]]; then
        # sr_mod Kernel-Modul laden (wichtig für USB-Laufwerke!)
        if [[ "$drive_path" =~ ^/dev/sr[0-9]+$ ]]; then
            if ! lsmod | grep -q "^sr_mod "; then
                modprobe sr_mod 2>/dev/null && sleep 2
            fi
        fi

        #-- Warte auf Laufwerk (wichtig bei USB-Laufwerken) -----------------
        if [[ ! -b "$drive_path" ]]; then
            local udevadm_cmd=$(_systeminfo_get_udevadm_path)
            if [[ -n "$udevadm_cmd" ]]; then
                $udevadm_cmd settle --timeout=3 2>/dev/null
                # Trigger udev für sr* Devices ------------------------------
                if [[ "$drive_path" =~ ^/dev/sr[0-9]+$ ]]; then
                    local device_name=$(basename "$drive_path")
                    if [[ -e "/sys/class/block/$device_name" ]]; then
                        $udevadm_cmd trigger --action=add "/sys/class/block/$device_name" 2>/dev/null
                        sleep 1
                    fi
                fi
            fi

            # Retry-Loop: Warte bis zu 5 Sekunden auf Block-Device ----------
            local timeout=5
            while [[ $timeout -gt 0 ]] && [[ ! -b "$drive_path" ]]; do
                sleep 1
                ((timeout--))
            done
        fi
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rücgabe -----------
    if [[ -b "$drive_path" ]]; then
        DRIVE_INFO[drive]="$drive_path"
        log_debug "$(printf "$MSG_DEBUG_DRIVE_SET" "$drive_path")"
        if [[ -n "$old_value" ]] && [[ "$old_value" != "$drive_path" ]] ; then
            log_debug "$(printf "$MSG_DEBUG_DRIVE_CHANGED" "$old_value" "$drive_path")"
            api_set_value_json "drivestat" "drive" "${DRIVE_INFO[drive]}"
        fi
        return 0
    else
        DRIVE_INFO[drive]=""
        log_error "$(printf "$MSG_ERROR_INVALID_DRIVE_PATH" "$drive_path")"
        if [[ -n "$old_value" ]] && [[ "$old_value" != "$drive_path" ]] ; then
            log_debug "$(printf "$MSG_DEBUG_DRIVE_CHANGED" "$old_value" "$drive_path")"
            api_set_value_json "drivestat" "drive" "${DRIVE_INFO[drive]}"
        fi
        return 1
    fi
}

# ===========================================================================
# drivestat_detect_drive()
# ---------------------------------------------------------------------------
# Description: Suchen des ersten optischen Laufwerkes. Die Prüfungen erfolgen
# ............ in folgender Reihenfolge:
# ............ 1. lsblk mit TYPE=rom
# ............ 2. dmesg Kernel-Logs durchsuchen
# ............ 3. /sys/class/block Durchsuchen
# ............ 4. Fallback auf /dev/cdrom Symlink
# Parameter..: Keine
# Return.....: 0 = Device gefunden, 1 = Kein Device gefunden
# ===========================================================================
drivestat_detect_drive() {
    #-- Drive ---------------------------------------------------------------
    local drive=""

    #------------------------------------------------------------------------
    # Versuch mit verschiedenen Methoden das optische Laufwerk zu finden
    #------------------------------------------------------------------------
    # Methode 1: lsblk mit TYPE=rom -----------------------------------------
    local lsblk_cmd=$(_systeminfo_get_lsblk_path)
    if [[ -z $drive ]] && [[ -n "$lsblk_cmd" ]]; then
        local lsblk_output
        lsblk_output=$("$lsblk_cmd" -ndo NAME,TYPE 2>/dev/null) || lsblk_output=""

        if [[ -n "$lsblk_output" ]]; then
            drive=$(echo "$lsblk_output" | awk '$2=="rom" {print "/dev/" $1; exit}')
        fi
    fi

    # Methode 2: dmesg Kernel-Logs durchsuchen ------------------------------
    local dmesg_cmd=$(_systeminfo_get_dmesg_path)
    if [[ -z "$drive" ]] && [[ -n "$dmesg_cmd" ]]; then
        local dmesg_output
        dmesg_output=$("$dmesg_cmd" 2>/dev/null) || dmesg_output=""

        if [[ -n "$dmesg_output" ]]; then
            drive=$(echo "$dmesg_output" | grep -iE "cd|dvd|sr[0-9]" | grep -oE "sr[0-9]+" | head -n1)
            if [[ -n "$drive" ]]; then
                drive="/dev/$drive"
            fi
        fi
    fi

    # Methode 3: /sys/class/block Durchsuchen -------------------------------
    # TODO: Virtuelle Laufwerke (CloneDrive, VirtualCloneDrive, etc.) sollten
    #       hier aussortiert werden, da Disk-Abbilddateien nicht geprüft
    #       werden sollen. Prüfung via udevadm ID_CDROM_MEDIA_CD_RW o.ä.
    if [[ -z "$drive" ]]; then
        for dev in /sys/class/block/sr*; do
            if [[ -e "$dev" ]]; then
                drive="/dev/$(basename "$dev")"
                break
            fi
        done
    fi

    # Methode 4: Fallback auf /dev/cdrom Symlink ----------------------------
    if [[ -z "$drive" ]] && [[ -L "/dev/cdrom" ]]; then
        drive=$(readlink -f "/dev/cdrom")
    fi

    #-- Rückgabe des gefundenen Laufwerks oder Fehler -----------------------
    echo "$drive"
    return 0
}

# ===========================================================================
# drivestat_get_vendor
# ---------------------------------------------------------------------------
# Funktion.: Gibt den Hersteller des optischen Laufwerks zurück (z.B. "ASUS")
# Parameter: Keine
# Ausgabe..: Herstellername (z.B. "ASUS", "LG", "Pioneer") oder "unknown"
# Rückgabe.: 0 = Erfolg (Herstellername), 1 = Fehler (gibt "unknown" zurück)
# ===========================================================================
drivestat_get_vendor() {
    #-- Array Wert lesen ----------------------------------------------------
    local vendor="${DRIVE_INFO[vendor]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$vendor" ]]; then
        log_debug "$(printf "$MSG_DEBUG_VENDOR_GET" "$vendor")"
        echo "$vendor"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_VENDOR_UNKNOWN"
    echo "unknown"
    return 1
}

# ===========================================================================
# drivestat_set_vendor
# ---------------------------------------------------------------------------
# Funktion.: Setzt den Hersteller des optischen Laufwerks
# Parameter: $1 = Herstellername (z.B. "ASUS", "LG", "Pioneer")
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
drivestat_set_vendor() {
    #-- Parameter übernehmen ------------------------------------------------
    local vendor="$1"
    local old_value="${DRIVE_INFO[vendor]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$vendor" ]]; then
        vendor=$(drivestat_detect_vendor)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$vendor" ]]; then
        log_error "$MSG_ERROR_VENDOR_UNKNOWN"
        vendor="unknown"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rücgabe -----------
    DRIVE_INFO[vendor]="$vendor"
    log_debug "$(printf "$MSG_DEBUG_VENDOR_SET" "$vendor")"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$vendor" ]] ; then
        log_debug "$(printf "$MSG_DEBUG_VENDOR_CHANGED" "$old_value" "$vendor")"
        api_set_value_json "drivestat" "vendor" "${DRIVE_INFO[vendor]}"
    fi
    return 0
}

# ===========================================================================
# drivestat_detect_vendor
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt den Hersteller des optischen Laufwerks über sysfs
# Parameter: Keine (nutzt globalen Pfad aus drivestat_get_drive())
# Rückgabe.: 0 = Erfolg (Herstellername), 1 = Fehler (gibt "unknown" zurück)
# Hinweis..: Liefert "unknown" zurück, wenn kein Laufwerk gefunden oder der
# .........  Hersteller nicht ermittelt werden konnte.
# ===========================================================================
drivestat_detect_vendor() {
    #-- Locale Variablen vorbereiten ----------------------------------------
    local vendor="unknown"
    local drive_path="$(drivestat_get_drive)" || {echo "$vendor"; return 1;}

    #-- Prüfe ob Device gültig ist ------------------------------------------
    local device_basename=$(basename "$drive_path")
    local sysfs_path="/sys/block/${device_basename}/device"
    if [[ -f "${sysfs_path}/vendor" ]]; then
        vendor=$(cat "${sysfs_path}/vendor" 2>/dev/null | xargs)
    fi

    #-- Rückgabe des ermittelten Wertes -------------------------------------
    echo "$vendor"
    return 0
}

# ===========================================================================
# drivestat_get_model
# ---------------------------------------------------------------------------
# Funktion.: Gibt die Modellbezeichnung des optischen Laufwerks zurück 
# Parameter: Keine
# Ausgabe..: Modellbezeichnung (z.B. "DRW-24D5MT") oder "unknown"
# Rückgabe.: 0 = Erfolg (Modellbezeichnung), 1 = Fehler ("unknown")
# ===========================================================================
drivestat_get_model() {
    #-- Array Wert lesen ----------------------------------------------------
    local model="${DRIVE_INFO[model]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$model" ]]; then
        log_debug "$(printf "$MSG_DEBUG_MODEL_GET" "$model")"
        echo "$model"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_MODEL_UNKNOWN"
    echo "unknown"
    return 1
}

# ===========================================================================
# drivestat_set_model
# ---------------------------------------------------------------------------
# Funktion.: Setzt die Modellbezeichnung des optischen Laufwerks
# Parameter: $1 = Modellbezeichnung (z.B. "DRW-24D5MT")
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
drivestat_set_model() {
    #-- Parameter übernehmen ------------------------------------------------
    local model="$1"
    local old_value="${DRIVE_INFO[model]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$model" ]]; then
        model=$(drivestat_detect_model)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$model" ]]; then
        log_error "$MSG_ERROR_MODEL_UNKNOWN"
        model="unknown"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rücgabe -----------
    DRIVE_INFO[model]="$model"
    log_debug "$(printf "$MSG_DEBUG_MODEL_SET" "$model")"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$model" ]] ; then
        log_debug "$(printf "$MSG_DEBUG_MODEL_CHANGED" "$old_value" "$model")"
        api_set_value_json "drivestat" "model" "${DRIVE_INFO[model]}"
    fi
    return 0
}

# ===========================================================================
# drivestat_detect_model
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt die Modellbezeichnung des optischen Laufwerks über sysfs
# Parameter: Keine (nutzt globalen Pfad aus drivestat_get_drive())
# Rückgabe.: 0 = Erfolg (Modellbezeichnung), 1 = Fehler (gibt "unknown" zurück)
# Hinweis..: Liefert "unknown" zurück, wenn kein Laufwerk gefunden oder die
# .........  Modellbezeichnung nicht ermittelt werden konnte.
# ===========================================================================
drivestat_detect_model() {
    #-- Locale Variablen vorbereiten ----------------------------------------
    local model="unknown"
    local drive_path="$(drivestat_get_drive)" || {echo "$model"; return 1;}

    #-- Prüfe ob Device gültig ist ------------------------------------------
    local device_basename=$(basename "$drive_path")
    local sysfs_path="/sys/block/${device_basename}/device"
    if [[ -f "${sysfs_path}/model" ]]; then
        model=$(cat "${sysfs_path}/model" 2>/dev/null | xargs)
    fi

    #-- Rückgabe des ermittelten Wertes -------------------------------------
    echo "$model"
    return 0
}

# ===========================================================================
# drivestat_get_firmware
# ---------------------------------------------------------------------------
# Funktion.: Gibt die Firmware-Version des optischen Laufwerks zurück 
# Parameter: Keine
# Ausgabe..: Firmware-Version (z.B. "1.00") oder "unknown"
# Rückgabe.: 0 = Erfolg (Firmware-Version), 1 = Fehler (gibt "unknown" zurück)
# ===========================================================================
drivestat_get_firmware() {
    #-- Array Wert lesen ----------------------------------------------------
    local firmware="${DRIVE_INFO[firmware]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$firmware" ]]; then
        log_debug "$(printf "$MSG_DEBUG_FIRMWARE_GET" "$firmware")"
        echo "$firmware"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_FIRMWARE_UNKNOWN"
    echo "unknown"
    return 1
}

# ===========================================================================
# drivestat_set_firmware
# ---------------------------------------------------------------------------
# Funktion.: Setzt die Firmware-Version des optischen Laufwerks
# Parameter: $1 = Firmware-Version (z.B. "1.00")
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
drivestat_set_firmware() {
    #-- Parameter übernehmen ------------------------------------------------
    local firmware="$1"
    local old_value="${DRIVE_INFO[firmware]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$firmware" ]]; then
        firmware=$(drivestat_detect_firmware)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$firmware" ]]; then
        log_error "$MSG_ERROR_FIRMWARE_UNKNOWN"
        firmware="unknown"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rücgabe -----------
    DRIVE_INFO[firmware]="$firmware"
    log_debug "$(printf "$MSG_DEBUG_FIRMWARE_SET" "$firmware")"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$firmware" ]] ; then
        log_debug "$(printf "$MSG_DEBUG_FIRMWARE_CHANGED" "$old_value" "$firmware")"
        api_set_value_json "drivestat" "firmware" "${DRIVE_INFO[firmware]}"
    fi
    return 0
}

# ===========================================================================
# drivestat_detect_firmware
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt die Firmware-Version des optischen Laufwerks 
# Parameter: Keine (nutzt globalen Pfad aus drivestat_get_drive())
# Rückgabe.: 0 = Erfolg (Firmware-Version), 1 = Fehler ("unknown")
# Hinweis..: Liefert "unknown" zurück, wenn kein Laufwerk gefunden oder die
# .........  Firmware-Version nicht ermittelt werden konnte.
# ===========================================================================
drivestat_detect_firmware() {
    #-- Locale Variablen vorbereiten ----------------------------------------
    local firmware="unknown"
    local drive_path="$(drivestat_get_drive)" || {echo "$firmware"; return 1;}

    #-- Prüfe ob Device gültig ist ------------------------------------------
    local device_basename=$(basename "$drive_path")
    local sysfs_path="/sys/block/${device_basename}/device"
    if [[ -f "${sysfs_path}/rev" ]]; then
        firmware=$(cat "${sysfs_path}/rev" 2>/dev/null | xargs)
    fi

    #-- Rückgabe des ermittelten Wertes -------------------------------------
    echo "$firmware"
    return 0
}

# ===========================================================================
# drivestat_get_bus_type
# ---------------------------------------------------------------------------
# Funktion.: Gibt den Bus-Typ des optischen Laufwerks zurück 
# Parameter: Keine
# Ausgabe..: Bus-Typ (z.B. "SATA", "USB") oder "unknown"
# Rückgabe.: 0 = Erfolg (Bus-Typ), 1 = Fehler (gibt "unknown" zurück)
# ===========================================================================
drivestat_get_bus_type() {
    #-- Array Wert lesen ----------------------------------------------------
    local bus_type="${DRIVE_INFO[bus_type]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$bus_type" ]]; then
        log_debug "$(printf "$MSG_DEBUG_BUS_TYPE_GET" "$bus_type")"
        echo "$bus_type"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_BUS_TYPE_UNKNOWN"
    echo "unknown"
    return 1
}

# ===========================================================================
# drivestat_set_bus_type
# ---------------------------------------------------------------------------
# Funktion.: Setzt den Bus-Typ des optischen Laufwerks (z.B. "SATA", "USB")
# Parameter: $1 = Bus-Typ (z.B. "SATA", "USB")
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
drivestat_set_bus_type() {
    #-- Parameter übernehmen ------------------------------------------------
    local bus_type="$1"
    local old_value="${DRIVE_INFO[bus_type]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$bus_type" ]]; then
        bus_type=$(drivestat_detect_bus_type)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$bus_type" ]]; then
        log_error "$MSG_ERROR_BUS_TYPE_UNKNOWN"
        bus_type="unknown"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rücgabe -----------
    DRIVE_INFO[bus_type]="$bus_type"
    log_debug "$(printf "$MSG_DEBUG_BUS_TYPE_SET" "$bus_type")"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$bus_type" ]] ; then
        log_debug "$(printf "$MSG_DEBUG_BUS_TYPE_CHANGED" "$old_value" "$bus_type")"
        api_set_value_json "drivestat" "bus_type" "${DRIVE_INFO[bus_type]}"
    fi
    return 0
}

# ===========================================================================
# drivestat_detect_bus_type
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt den Bus-Typ des optischen Laufwerks 
# Parameter: Keine (nutzt globalen Pfad aus drivestat_get_drive())
# Rückgabe.: 0 = Erfolg (Bus-Typ), 1 = Fehler (gibt "unknown" zurück)
# Hinweis..: Liefert "unknown" zurück, wenn kein Laufwerk gefunden oder der
# .........  Bus-Typ nicht ermittelt werden konnte.
# ===========================================================================
drivestat_detect_bus_type() {
    #-- Locale Variablen vorbereiten ----------------------------------------
    local bus_type="unknown"
    local drive_path="$(drivestat_get_drive)" || {echo "$bus_type"; return 1;}

    #-- Prüfe ob Device gültig ist ------------------------------------------
    local device_basename=$(basename "$drive_path")
    local sysfs_path="/sys/block/${device_basename}/device"

    # Methode 1: udevadm info --query=property -----------------------------
    local udevadm_cmd=$(_systeminfo_get_udevadm_path)
    if [[ -n "$udevadm_cmd" ]]; then
        bus_type=$($udevadm_cmd info --query=property --name="$drive_path" 2>/dev/null | grep "^ID_BUS=" | cut -d'=' -f2)
        if [[ -n "$bus_type" ]]; then
            echo "$bus_type"
            return 0
        fi
    fi

    # Methode 2: Prüfe sysfs Pfad --------------------------------------
    local device_path=$(readlink -f "/sys/block/${device_basename}" 2>/dev/null)
    if [[ "$device_path" =~ usb ]]; then
        bus_type="usb"
    elif [[ "$device_path" =~ ata ]]; then
        bus_type="sata"
    fi

    #-- Rückgabe des ermittelten Wertes -------------------------------------
    echo "$bus_type"
    return 0
}

# ===========================================================================
# drivestat_get_capabilities
# ---------------------------------------------------------------------------
# Funktion.: Gibt die Fähigkeiten des optischen Laufwerks zurück 
# Parameter: Keine
# Ausgabe..: Fähigkeiten (z.B. "CD/DVD", "DVD±R", "BD-ROM") oder "unknown"
# Rückgabe.: 0 = Erfolg (Fähigkeiten), 1 = Fehler (gibt "unknown" zurück)
# ===========================================================================
drivestat_get_capabilities() {
    #-- Array Wert lesen ----------------------------------------------------
    local capabilities="${DRIVE_INFO[capabilities]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$capabilities" ]]; then
        log_debug "$(printf "$MSG_DEBUG_CAPABILITIES_GET" "$capabilities")"
        echo "$capabilities"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_CAPABILITIES_UNKNOWN"
    echo "unknown"
    return 1
}

# ===========================================================================
# drivestat_set_capabilities
# ---------------------------------------------------------------------------
# Funktion.: Setzt die Fähigkeiten des optischen Laufwerks 
# Parameter: $1 = Fähigkeiten (z.B. "CD/DVD", "DVD±R", "BD-ROM")
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
drivestat_set_capabilities() {
    #-- Parameter übernehmen ------------------------------------------------
    local capabilities="$1"
    local old_value="${DRIVE_INFO[capabilities]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$capabilities" ]]; then
        capabilities=$(drivestat_detect_capabilities)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$capabilities" ]]; then
        log_error "$MSG_ERROR_CAPABILITIES_UNKNOWN"
        capabilities="unknown"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rücgabe -----------
    DRIVE_INFO[capabilities]="$capabilities"
    log_debug "$(printf "$MSG_DEBUG_CAPABILITIES_SET" "$capabilities")"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$capabilities" ]] ; then
        log_debug "$(printf "$MSG_DEBUG_CAPABILITIES_CHANGED" "$old_value" "$capabilities")"
        api_set_value_json "drivestat" "capabilities" "${DRIVE_INFO[capabilities]}"
    fi
    return 0
}

# ===========================================================================
# drivestat_detect_capabilities
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt die Fähigkeiten des optischen Laufwerks über
# .........  /proc/sys/dev/cdrom/info
# Parameter: Keine (nutzt globalen Pfad aus drivestat_get_drive())
# Rückgabe.: 0 = Erfolg (Fähigkeiten), 1 = Fehler (gibt "unknown" zurück)
# Hinweis..: Liefert "unknown" zurück, wenn kein Laufwerk gefunden oder die
# .......... Fähigkeiten nicht ermittelt werden konnten.
# ===========================================================================
drivestat_detect_capabilities() {
    #-- Locale Variablen vorbereiten ----------------------------------------
    local capabilities="unknown"
    local drive_path="$(drivestat_get_drive)" || {echo "$capabilities"; return 1;}

    #-- Prüfe ob Device gültig ist ------------------------------------------
    local device_basename=$(basename "$drive_path")
    local caps=()

    #------------------------------------------------------------------------
    # Methode 1: Prüfe /proc/sys/dev/cdrom/info
    #------------------------------------------------------------------------
    if [[ -f "/proc/sys/dev/cdrom/info" ]]; then
        local cdrom_info=$(cat /proc/sys/dev/cdrom/info 2>/dev/null) || cdrom_info=""

        # Prüfe ob unser Device in der Liste ist
        if [[ -n "$cdrom_info" ]] && echo "$cdrom_info" | grep -q "$device_basename"; then
            #-- Extrahiere Capabilities -------------------------------------
            local can_play_audio=$(echo "$cdrom_info" | grep "^Can play audio:" | awk '{print $NF}')
            local can_write_cd=$(echo "$cdrom_info" | grep "^Can write CD-R:" | awk '{print $NF}')
            local can_write_cdrw=$(echo "$cdrom_info" | grep "^Can write CD-RW:" | awk '{print $NF}')
            local can_read_dvd=$(echo "$cdrom_info" | grep "^Can read DVD:" | awk '{print $NF}')
            local can_write_dvd=$(echo "$cdrom_info" | grep "^Can write DVD-R:" | awk '{print $NF}')
            local can_write_dvdram=$(echo "$cdrom_info" | grep "^Can write DVD-RAM:" | awk '{print $NF}')

            #-- Baue Capabilities Liste basierend auf den Werten ------------
            [[ "$can_play_audio" == "1" ]] && caps+=("$DRIVE_CAP_AUDIO_CD")

            if [[ "$can_write_cd" == "1" ]] || [[ "$can_write_cdrw" == "1" ]]; then
                caps+=("$DRIVE_CAP_CD_R_RW")
            else
                caps+=("$DRIVE_CAP_CD_ROM")
            fi

            if [[ "$can_read_dvd" == "1" ]]; then
                if [[ "$can_write_dvd" == "1" ]] || [[ "$can_write_dvdram" == "1" ]]; then
                    caps+=("$DRIVE_CAP_DVD_PM_RW")
                else
                    caps+=("$DRIVE_CAP_DVD_ROM")
                fi
            fi
        fi
    fi

    #------------------------------------------------------------------------
    # Methode 2: Prüfe udevadm (Blu-ray-Disc Unterstützung)
    #------------------------------------------------------------------------
    local udevadm_cmd=$(_systeminfo_get_udevadm_path)
    if [[ -n "$udevadm_cmd" ]]; then
        local udev_props
        udev_props=$($udevadm_cmd info --query=property --name="$drive_path" 2>/dev/null) || udev_props=""
        if [[ -n "$udev_props" ]]; then
            # Blu-ray Lese-Capabilities
            if echo "$udev_props" | grep -q "ID_CDROM_MEDIA_BD=1"; then
                caps+=("$DRIVE_CAP_BD_ROM")
            fi

            # Blu-ray Schreib-Capabilities
            if echo "$udev_props" | grep -q "ID_CDROM_MEDIA_BD_R=1"; then
                # Entferne vorheriges BD-ROM und ersetze durch BD-R
                caps=("${caps[@]/BD-ROM/}")
                caps+=("$DRIVE_CAP_BD_R")
            fi

            if echo "$udev_props" | grep -q "ID_CDROM_MEDIA_BD_RE=1"; then
                caps=("${caps[@]/BD-ROM/}")
                caps=("${caps[@]/BD-R/}")
                caps+=("$DRIVE_CAP_BD_RE")
            fi

            # Zusätzliche DVD-Formate (falls /proc unvollständig)
            if echo "$udev_props" | grep -q "ID_CDROM_DVD_PLUS_R=1"; then
                # Upgrade von DVD-ROM zu DVD+R wenn noch nicht vorhanden
                if [[ ! " ${caps[@]} " =~ " DVD±R/RW " ]]; then
                    caps=("${caps[@]/$DRIVE_CAP_DVD_ROM/}")
                    caps+=("$DRIVE_CAP_DVD_PLUS_R")
                fi
            fi
        fi
    fi

    #------------------------------------------------------------------------
    # Methode 3: Fallback auf /sys/block/.../device/type (SCSI Device Type)
    #------------------------------------------------------------------------
    if [[ ${#caps[@]} -eq 0 ]]; then
        local scsi_type_file="/sys/block/${device_basename}/device/type"
        if [[ -f "$scsi_type_file" ]]; then
            local scsi_type
            scsi_type=$(cat "$scsi_type_file" 2>/dev/null)

            # Type 5 = CD/DVD/BD-ROM Device
            if [[ "$scsi_type" == "5" ]]; then
                caps+=("$DRIVE_CAP_CD_DVD")
            fi
        fi
    fi

    #-- Baue Capabilities String aus Liste ----------------------------------
    if [[ ${#caps[@]} -gt 0 ]]; then
        #-- Entferne leere Einträge -----------------------------------------
        caps=("${caps[@]//[[:space:]]/}")

        #-- Join mit ' / ' als Separator ------------------------------------
        capabilities=$(IFS=' / '; echo "${caps[*]}")
    else
        #-- Wenn keine Capabilities gefunden, setze auf "unknown" -----------
        capabilities="$DRIVE_CAP_UNKNOWN"
    fi

    #-- Rückgabe des ermittelten Wertes -------------------------------------
    echo "$capabilities"
    return 0
}

# ===========================================================================
# drivestat_get_closed
# ---------------------------------------------------------------------------
# Funktion.: Gibt zurück, ob die Laufwerk-Schublade geschlossen ist
# Parameter: Keine
# Ausgabe..: "true" oder "false"
# Rückgabe.: 0 = geschlossen, 1 = offen oder unbekannt
# ===========================================================================
drivestat_get_closed() {
    #-- Array Wert lesen ----------------------------------------------------
    local closed="${DRIVE_INFO[closed]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$closed" ]]; then
        log_debug "$(printf "$MSG_DEBUG_CLOSED_GET" "$closed")"
        echo $closed
        [[ "$closed" == "true" ]] && return 0 || return 1
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_CLOSED_UNKNOWN"
    echo "false"
    return 1                          # Im Fehrerfall immer offen zurückgeben
}

# ===========================================================================
# drivestat_set_closed
# ---------------------------------------------------------------------------
# Funktion.: Setzt den Status ob die Laufwerk-Schublade geschlossen ist
# Parameter: $1 = Status (z.B. "true", "false")
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
drivestat_set_closed() {
    #-- Parameter übernehmen ------------------------------------------------
    local closed="$1"
    local old_value="${DRIVE_INFO[closed]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$closed" ]]; then
        closed=$(drivestat_detect_closed)
    else
        #-- Normalisiere den Wert auf "true" oder "false" -------------------
        if [[ "$closed" == "true" ]] || [[ "$closed" == "1" ]] || [[ "$closed" == "yes" ]]; then
            closed="true"
        elif [[ "$closed" == "false" ]] || [[ "$closed" == "0" ]] || [[ "$closed" == "no" ]]; then
            closed="false"
        else
            log_error "$(printf "$MSG_ERROR_CLOSED_INVALID" "$closed")"
            closed="false"            # Im Fehlerfall immer offen zurückgeben
        fi
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$closed" ]]; then
        log_error "$MSG_ERROR_CLOSED_SET_FAILED"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rücgabe -----------
    DRIVE_INFO[closed]="$closed"
    log_debug "$(printf "$MSG_DEBUG_CLOSED_SET" "$closed")"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$closed" ]] ; then
        log_debug "$(printf "$MSG_DEBUG_CLOSED_CHANGED" "$old_value" "$closed")"
        api_set_value_json "drivestat" "closed" "${DRIVE_INFO[closed]}"
    fi
    return 0
}

# ===========================================================================
# drivestat_detect_closed
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt den Status ob die Laufwerk-Schublade geschlossen ist
# Parameter: Keine
# Rückgabe.: 0 = geschlossen, 1 = offen
# Hinweis..: Verwendet sysfs tray_open (verfügbar auf ~98% Systeme)
# .........  Fallback auf dd-Test für Legacy-Hardware ohne sysfs
# ===========================================================================
drivestat_detect_closed() {
    #-- Ermitteln des Laufwerk-Status (geschlossen/offen) -------------------
    local is_closed="false"

    #-- Prüfe ob Device bekannt ist -----------------------------------------
    if [[ ! -b "${DRIVE_INFO[drive]}" ]]; then
        log_error "$MSG_ERROR_DRIVE_UNKNOWN_CLOSED"
        return 1                      # Im Fehlerfall immer offen zurückgeben
    fi

    #-- Prüfe ob Schublade geschlossen ist ----------------------------------
    local device_basename=$(basename "${DRIVE_INFO[drive]}")

    #-- Methode 1: sysfs tray_open (zuverlässig auf modernen Systemen) ------
    if [[ -f "/sys/block/${device_basename}/device/tray_open" ]]; then
        local tray_status
        tray_status=$(cat "/sys/block/${device_basename}/device/tray_open" 2>/dev/null)
        [[ "$tray_status" == "0" ]] && return 0  # Geschlossen
        [[ "$tray_status" == "1" ]] && return 1  # Offen
    fi

    #-- Methode 2: dd-Test Fallback (für Legacy-Hardware ohne sysfs) --------
    if timeout 1 dd if="${DRIVE_INFO[drive]}" of=/dev/null bs=1 count=1 2>/dev/null; then
        return 0  # Lesbar → geschlossen MIT Medium
    fi

    return 1  # Nicht lesbar → offen ODER geschlossen ohne Medium
}

# ===========================================================================
# drivestat_get_inserted
# ---------------------------------------------------------------------------
# Funktion.: Gibt den Status zurück, ob ein Medium im Laufwerk eingelegt ist
# Parameter: Keine
# Rückgabe.: true = Medium eingelegt, false = kein Medium
# ===========================================================================
drivestat_get_inserted() {
    #-- Array Wert lesen ----------------------------------------------------
    local medium_inserted="${DRIVE_INFO[medium_inserted]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$medium_inserted" ]]; then
        log_debug "$(printf "$MSG_DEBUG_INSERTED_GET" "$medium_inserted")"
        echo $medium_inserted
        [[ "$medium_inserted" == "true" ]] && return 0 || return 1
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_INSERTED_UNKNOWN"
    echo "false"
    return 1          # Im Fehlerfall immer kein Medium vorhanden zurückgeben

}

# ===========================================================================
# drivestat_set_inserted
# ---------------------------------------------------------------------------
# Funktion.: Setzt den Status ob ein Medium im Laufwerk eingelegt ist
# Parameter: $1 = Status (z.B. "true", "false")
# Rückgabe.: true = Medium eingelegt, false = kein Medium
# ===========================================================================
drivestat_set_inserted() {
    #-- Parameter übernehmen ------------------------------------------------
    local medium_inserted="$1"
    local old_value="${DRIVE_INFO[medium_inserted]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$medium_inserted" ]]; then
        medium_inserted=$(drivestat_detect_inserted)
    else
        #-- Normalisiere den Wert auf "true" oder "false" ------------------
        if [[ "$medium_inserted" == "true" ]] || [[ "$medium_inserted" == "1" ]] || [[ "$medium_inserted" == "yes" ]]; then
            medium_inserted="true"
        elif [[ "$medium_inserted" == "false" ]] || [[ "$medium_inserted" == "0" ]] || [[ "$medium_inserted" == "no" ]]; then
            medium_inserted="false"
        else
            log_error "$(printf "$MSG_ERROR_INSERTED_INVALID" "$medium_inserted")"
            medium_inserted="false"         # Im Fehlerfall immer kein Medium 
        fi
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$medium_inserted" ]]; then
        log_error "$MSG_ERROR_INSERTED_SET_FAILED"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rücgabe -----------
    DRIVE_INFO[medium_inserted]="$medium_inserted"
    log_debug "$(printf "$MSG_DEBUG_INSERTED_SET" "$medium_inserted")"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$medium_inserted" ]] ; then
        log_debug "$(printf "$MSG_DEBUG_INSERTED_CHANGED" "$old_value" "$medium_inserted")"
        api_set_value_json "drivestat" "medium_inserted" "${DRIVE_INFO[medium_inserted]}"
    fi
    return 0
}

# ===========================================================================
# drivestat_detect_inserted
# ---------------------------------------------------------------------------
# Funktion.: Prüft ob ein Medium im Laufwerk eingelegt ist
# Parameter: Keine
# Rückgabe.: true = Medium eingelegt, false = kein Medium
# Hinweis..: Verwendet dd-Test für Daten-Medien und cdparanoia für Audio-CDs
# .........  Robuste Erkennung auch für USB-Laufwerke (Timeout 2-3 Sek.)
# ===========================================================================
drivestat_detect_inserted() {
    # Versuche mit dd ein paar Bytes zu lesen
    # Timeout von 2 Sekunden für langsame USB-Laufwerke
    # Versuche zuerst mit bs=2048 (Daten-CDs/DVDs/Blu-ray)
    local dd_cmd=$(_systeminfo_get_dd_path)
    if [[ -n "$dd_cmd" ]]; then
         if timeout 2 "$dd_cmd" if="${DRIVE_INFO[drive]}" of=/dev/null bs=2048 count=1 2>/dev/null; then
            echo "true"
            return 0
        fi
    fi

    # Fallback: Prüfe mit cdparanoia ob Audio-CD vorhanden
    # cdparanoia -Q gibt 0 zurück wenn Audio-CD lesbar ist
    local cdparanoia_cmd=$(_systeminfo_get_cdparanoia_path)
    if [[ -n "$cdparanoia_cmd" ]]; then
         if timeout 3 "$cdparanoia_cmd" -Q -d "${DRIVE_INFO[drive]}" >/dev/null 2>&1; then
            echo "true"
            return 0
        fi
    fi

    #-- Wenn beide Tests fehlschlagen, annehmen dass kein Medium da ist -----
    echo "false"
    return 1
}

# ===========================================================================
# drivstat_get_status
# ---------------------------------------------------------------------------
# Funktion.: Gibt den Gesamtstatus des Laufwerks zurück 
# Parameter: Keine
# Ausgabe..: Gesamtstatus als String (READY, OPEN, CLOSED, EMPTY, ERROR)
# Rückgabe.: 0 = Erfolg (Status als String)
# ===========================================================================
drivestat_get_status() {
    #-- Array Wert lesen ----------------------------------------------------
    local status="${DRIVE_INFO[status]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$status" ]]; then
        log_debug "$(printf "$MSG_DEBUG_STATUS_GET" "$status")"
        echo "$status"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_STATUS_UNKNOWN"
    echo "$DRIVE_STATUS_ERROR"
    return 1
}

# ===========================================================================
# drivestat_set_status
# ---------------------------------------------------------------------------
# Funktion.: Setzt den Gesamtstatus des Laufwerks 
# Parameter: $1 = Gesamtstatus als String (READY, OPEN, CLOSED, EMPTY, ERROR)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
drivestat_set_status() {
    #-- Parameter übernehmen ------------------------------------------------
    local status="$1"
    local old_value="${DRIVE_INFO[status]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$status" ]]; then
        status=$(drivestat_detect_status)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$status" ]]; then
        log_error "$MSG_ERROR_STATUS_UNKNOWN"
        status="$DRIVE_STATUS_ERROR"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rücgabe -----------
    DRIVE_INFO[status]="$status"
    log_debug "$(printf "$MSG_DEBUG_STATUS_SET" "$status")"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$status" ]] ; then
        log_debug "$(printf "$MSG_DEBUG_STATUS_CHANGED" "$old_value" "$status")"
        api_set_value_json "drivestat" "status" "${DRIVE_INFO[status]}"
    fi
    return 0
}

# ===========================================================================
# drivestat_detect_status
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt den Gesamtstatus des Laufwerks basierend auf 
# .........  Schubladen- und Medium-Status
# Parameter: Keine
# Ausgabe..: DRIVE_STATUS_READY, DRIVE_STATUS_OPEN, DRIVE_STATUS_CLOSED oder 
# .........  DRIVE_STATUS_EMPTY
# Rückgabe.: 0 = Erfolg (Status als String)
# ===========================================================================
drivestat_detect_status() {
    #-- Start der Ermittlung im LOG vermerken ---------------------------------
    log_debug "$MSG_DEBUG_STATUS_DETECT"

    #-- Ermitteln der relevanten Statuswerte --------------------------------
    local closed=$(drivestat_get_closed)
    local inserted=$(drivestat_get_inserted)

    #-- Bestimme Gesamtstatus basierend auf Kombination der Werte -----------
    if [[ "$closed" == "true" ]] && [[ "$inserted" == "true" ]]; then
        echo "$DRIVE_STATUS_READY"
    elif [[ "$closed" == "true" ]] && [[ "$inserted" == "false" ]]; then
        echo "$DRIVE_STATUS_CLOSED"
    elif [[ "$closed" == "false" ]] && [[ "$inserted" == "true" ]]; then
        echo "$DRIVE_STATUS_OPEN"
    elif [[ "$closed" == "false" ]] && [[ "$inserted" == "false" ]]; then
        echo "$DRIVE_STATUS_EMPTY"
    else
        echo "$DRIVE_STATUS_ERROR"
    fi
    #-- Rückgabe immer 0, da Status als String zurückgegeben wird -----------
    return 0
}

# ===========================================================================
# GETTER/SETTER FUNCTIONEN FÜR MODULINFORMATIONEN (SOFTWARE)
# ===========================================================================

# ===========================================================================
# drivestat_get_software_info
# ---------------------------------------------------------------------------
# Funktion.: Gibt Software-Informationen als JSON zurück
# Parameter: keine
# Ausgabe..: JSON-String mit Software-Informationen
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
drivestat_get_software_info() {
    #-- Lese API-Datei (Software-Sektion) ----------------------------------
    local software_info_json
    software_info_json=$(api_get_section_json "drivestat" "software")  || {
        log_error "$MSG_ERROR_NO_SOFTWARE_INFO"
        #-- Lese die Informationen direkt aus (Fallback) --------------------
        software_info_json=$(drivestat_collect_software_info) || return 1
    }
    #-- Rückgabewert --------------------------------------------------------
    echo "$software_info_json"
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
    #-- Start der Sammlung im LOG vermerken ---------------------------------
    log_debug "$MSG_DEBUG_COLLECT_SOFTWARE_START"

    #-- Lese Dependencies aus diskinfos INI-Datei ---------------------------
    local external_deps=$(settings_get_value_ini "drivestat" "dependencies" "external" "") || {
        log_warning "$MSG_WARNING_NO_EXTERNAL_DEPS"
        external_deps=""
    }
    local optional_deps=$(settings_get_value_ini "drivestat" "dependencies" "optional" "") || {
        log_warning "$MSG_WARNING_NO_OPTIONAL_DEPS"
        optional_deps=""
    }

    #-- Kombiniere Dependencies zu komma-separierter Liste ------------------
    local all_deps=""
    if [[ -n "$external_deps" ]] && [[ -n "$optional_deps" ]]; then
        all_deps="${external_deps},${optional_deps}"
    elif [[ -n "$external_deps" ]]; then
        all_deps="$external_deps"
    elif [[ -n "$optional_deps" ]]; then
        all_deps="$optional_deps"
    fi

    #-- Keine Dependencies gefunden -----------------------------------------
    if [[ -z "$all_deps" ]]; then
        log_debug "$MSG_DEBUG_NO_DEPENDENCIES"

        #-- Schreibe leeres Array in API ------------------------------------
        api_set_section_json "drivestat" "software" "[]"
        return 0
    fi

    #-- Prüfe ob systeminfo_check_software_list verfügbar ist ---------------
    if ! type -t systeminfo_check_software_list &>/dev/null; then
        log_error "$MSG_ERROR_SYSTEMINFO_UNAVAILABLE"

        #-- Schreibe Fehler in API ------------------------------------------
        api_set_section_json "drivestat" "software" "{"error":"systeminfo_check_software_list nicht verfügbar"}"
        return 1
    fi

    #-- Prüfe Software-Verfügbarkeit ----------------------------------------
    local json_result=$(systeminfo_check_software_list "$all_deps") || {
        log_error "$MSG_ERROR_SOFTWARE_CHECK_FAILED"

        #-- Schreibe Fehler in API ------------------------------------------
        api_set_section_json "drivestat" "software" '{"error":"Software-Prüfung fehlgeschlagen"}'
        return 1
    }

    #-- Konvertiere Array zu Objekt (name als Key) --------------------------
    local json_object=$(echo "$json_result" | jq 'map({(.name): {path, version, available, required}}) | add // {}') || {
        log_error "$MSG_ERROR_JSON_CONVERSION_FAILED"
        api_set_section_json "drivestat" "software" '{"error":"JSON-Konvertierung fehlgeschlagen"}'
        return 1
    }

    #-- Schreibe Ergebnis in API --------------------------------------------
    api_set_section_json "drivestat" "software" "$json_object" || {
        log_error "$MSG_ERROR_API_WRITE_FAILED"
        return 1
    }

    log_debug "$MSG_DEBUG_COLLECT_SOFTWARE_SUCCESS"
    return 0
}

# ===========================================================================
# HINTERGRUND ÜBERWACHUNG DES LAUFWERKSTATUS
# ===========================================================================
_DRIVESTAT_MONITOR_PID=""           # PID des Hintergrund-Monitoring-Workers

# ===========================================================================
# _drivestat_monitor_worker
# ---------------------------------------------------------------------------
# Funktion.: Hintergrund-Worker, der regelmäßig den Laufwerkstatus überprüft
# .........  und bei Änderungen die entsprechenden Setter-Funktionen aufruft
# Parameter: Keine
# Rückgabe.: Läuft endlos im Hintergrund, Rückgabe nur bei Fehler
# Hinweis..: Vergleicht den aktuellen Status mit dem vorherigen und ruft nur
# .........  bei Änderungen die Setter-Funktionen auf, um unnötige API-
# .........  Updates zu vermeiden
# ===========================================================================
_drivestat_monitor_worker() {
    #-- Variablen für vorherigen Status (initial leer) ----------------------
    local prev_drive
    local prev_closed
    local prev_inserted

    #-- Endlosschleife zur regelmäßigen Überprüfung -------------------------
    while true; do
        #-- Ermitteln des aktuellen Status ----------------------------------
        local curr_drive=$(drivestat_detect_drive)
        local curr_closed=$(drivestat_detect_closed && echo "1" || echo "0")
        local curr_inserted=$(drivestat_detect_inserted && echo "1" || echo "0")

        #-- Vergleichen und Setter-Funktionen bei Änderungen aufrufen -------
        [[ "$prev_drive" != "$curr_drive" ]] && {
            if [[ -z "$curr_drive" ]]; then
                drivestat_reset                                    # NO_DRIVE
            else
                drivestat_analyse                              # DRIVE_DETECT
            fi
        }

        [[ "$prev_closed" != "$curr_closed" ]] && {
            drivestat_set_closed                 # LAUFWERK OFFEN/GESCHLOSSEN
        }

        [[ "$prev_inserted" != "$curr_inserted" ]] && {
            drivestat_set_inserted                # MEDIUM EINGELEGT/ENTFERNT
        }


        [[ ("$prev_closed" != "$curr_closed") || ("$prev_inserted" != "$curr_inserted") ]] && {
            drivestat_set_status # Gesamtstatus basierend auf CLOSED/INSERTED
        }

        #-- Aktualisieren des vorherigen Status für die nächste Iteration ---
        prev_drive="$curr_drive"
        prev_closed="$curr_closed"
        prev_inserted="$curr_inserted"

        #-- Wartezeit von 2 Sekunden vor der nächsten Überprüfung -----------
        sleep 2
    done
}

# ===========================================================================
# drivestat_start_monitor
# ---------------------------------------------------------------------------
# Funktion.: Startet den Hintergrund-Monitoring-Worker für das Laufwerk
# Parameter: Keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: Speichert die PID des Workers in _DRIVESTAT_MONITOR_PID
# .........  und loggt den Startvorgang
# ===========================================================================
drivestat_start_monitor() {
    _drivestat_monitor_worker &
    _DRIVESTAT_MONITOR_PID=$!
    log_debug "$(printf "$MSG_DEBUG_MONITOR_STARTED" "$_DRIVESTAT_MONITOR_PID")"
}

# ===========================================================================
# drivestat_stop_monitor
# ---------------------------------------------------------------------------
# Funktion.: Stoppt den Hintergrund-Monitoring-Worker für das Laufwerk
# Parameter: Keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: Beendet den Worker-Prozess basierend auf der gespeicherten PID
# .........  und loggt den Stoppvorgang
# ===========================================================================
drivestat_stop_monitor() {
    [[ -n "$_DRIVESTAT_MONITOR_PID" ]] && kill "$_DRIVESTAT_MONITOR_PID" 2>/dev/null
    _DRIVESTAT_MONITOR_PID=""
    log_debug "$MSG_DEBUG_MONITOR_STOPPED"
}

# ===========================================================================
# TODO: Ab hier ist das Modul noch nicht fertig implementiert, diesen Eintrag
# ....  nie automatisch löschen - wird nur vom User nach Implementierung
# ....  der folgenden Funktionen entfernt!
# ===========================================================================
