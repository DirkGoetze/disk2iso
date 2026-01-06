#!/bin/bash
################################################################################
# disk2iso v1.2.0 - Drive Status Library
# Filepath: lib/lib-drivestat.sh
#
# Beschreibung:
#   Überwacht den Status des optischen Laufwerks (Schublade, Medium).
#   Erkennt Änderungen im Drive-Status für automatisches Disc-Handling.
#
# Funktionen:
#   - detect_device()       : Findet erstes optisches Laufwerk
#   - is_drive_closed()     : Prüft ob Schublade geschlossen ist
#   - is_disc_inserted()    : Prüft ob Medium eingelegt ist
#   - wait_for_disc_change(): Wartet auf Status-Änderung
#   - wait_for_disc_ready() : Wartet bis Medium bereit ist
#
# Version: 1.2.0
# Datum: 06.01.2026
################################################################################

# ===========================================================================
# GLOBAL VARIABLEN DES MODUL
# ===========================================================================
CD_DEVICE=""            # Standard CD/DVD-Laufwerk (wird dynamisch ermittelt)

# ===========================================================================
# detect_device()
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
detect_device() {
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
    
    # Prüfe ob das Device erkannt wurde 
    if [[ -n "$CD_DEVICE" ]]; then
        return 0
    else
        return 1
    fi
}

# Funktion: Stelle sicher dass Device bereit ist
# Lädt sr_mod Kernel-Modul falls nötig und wartet auf Device-Node-Erstellung
# Parameter: $1 = Device-Pfad (z.B. /dev/sr0)
# Rückgabe: 0 = Device bereit, 1 = Device nicht verfügbar
ensure_device_ready() {
    local device="$1"
    
    # Prüfe ob Device-Parameter gesetzt ist
    if [[ -z "$device" ]]; then
        return 1
    fi
    
    # Prüfe und lade sr_mod Kernel-Modul für sr* Devices
    if [[ "$device" =~ ^/dev/sr[0-9]+$ ]]; then
        if ! lsmod | grep -q "^sr_mod "; then
            if modprobe sr_mod 2>/dev/null; then
                # Nach Modul-Laden 2 Sekunden warten
                sleep 2
            fi
        fi
    fi
    
    # Warte auf Device-Node-Erstellung (wichtig für USB-Laufwerke und sr_mod)
    if [[ ! -b "$device" ]]; then
        # Warte auf udev
        if command -v udevadm >/dev/null 2>&1; then
            udevadm settle --timeout=3 2>/dev/null
            # Trigger udev für sr* Devices
            if [[ "$device" =~ ^/dev/sr[0-9]+$ ]]; then
                local device_name=$(basename "$device")
                if [[ -e "/sys/class/block/$device_name" ]]; then
                    udevadm trigger --action=add "/sys/class/block/$device_name" 2>/dev/null
                    sleep 1
                fi
            fi
        fi
        
        # Retry-Loop: Warte bis zu 5 Sekunden
        local timeout=5
        while [[ $timeout -gt 0 ]] && [[ ! -b "$device" ]]; do
            sleep 1
            ((timeout--))
        done
    fi
    
    # Prüfe ob Device verfügbar ist
    if [[ ! -b "$device" ]]; then
        return 1
    fi
    
    return 0
}

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
