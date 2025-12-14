#!/bin/bash
################################################################################
# Drive Status Library
# Filepath: disk2iso-lib/lib-drivestat.sh
#
# Beschreibung:
#   Überwacht den Status des optischen Laufwerks (Schublade, Medium).
#   Erkennt Änderungen im Drive-Status für automatisches Disc-Handling.
#
# Funktionen:
#   - find_optical_device() : Findet erstes optisches Laufwerk
#   - is_drive_closed()     : Prüft ob Schublade geschlossen ist
#   - is_disc_inserted()    : Prüft ob Medium eingelegt ist
#   - wait_for_disc_change(): Wartet auf Status-Änderung (Schublade/Medium)
#   - wait_for_disc_ready() : Wartet bis Medium bereit ist (Spin-Up)
#
# Verschoben: 13.12.2025 (detection/drivestatus.sh → lib-drivestat.sh)
################################################################################

# Funktion zum Finden des ersten optischen Laufwerks
# Gibt Device-Pfad zurück (/dev/sr0, /dev/sr1, etc.) oder leeren String
find_optical_device() {
    local device=""
    
    # Methode 1: lsblk mit TYPE=rom
    if command -v lsblk >/dev/null 2>&1; then
        device=$(lsblk -ndo NAME,TYPE 2>/dev/null | awk '$2=="rom" {print "/dev/" $1; exit}')
    fi
    
    # Methode 2: /sys/class/block Durchsuchen
    if [[ -z "$device" ]]; then
        for dev in /sys/class/block/sr*; do
            if [[ -e "$dev" ]]; then
                device="/dev/$(basename "$dev")"
                break
            fi
        done
    fi
    
    # Methode 3: Fallback auf /dev/cdrom Symlink
    if [[ -z "$device" ]] && [[ -L "/dev/cdrom" ]]; then
        device=$(readlink -f "/dev/cdrom")
    fi
    
    echo "$device"
}

# Funktion: Stelle sicher dass Device bereit ist
# Lädt sr_mod Kernel-Modul falls nötig und wartet auf Device-Node-Erstellung
# Parameter: $1 = Device-Pfad (z.B. /dev/sr0)
# Rückgabe: 0 = Device bereit, 1 = Device nicht verfügbar
ensure_device_ready() {
    local device="$1"
    
    if [[ -z "$device" ]]; then
        log_message "[DriveStatus] Fehler: Kein Device angegeben"
        return 1
    fi
    
    # Erkenne Container-Umgebung
    local is_container=false
    local virt_type="none"
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        virt_type=$(systemd-detect-virt 2>/dev/null || echo "none")
        if [[ "$virt_type" != "none" ]]; then
            is_container=true
            log_message "[DriveStatus] Container erkannt: $virt_type"
        fi
    fi
    
    # Prüfe und lade sr_mod Kernel-Modul für sr* Devices (NUR auf echten Systemen)
    if [[ "$device" =~ ^/dev/sr[0-9]+$ ]]; then
        if [[ "$is_container" == false ]]; then
            # Normale System-Umgebung: Lade sr_mod falls nötig
            if ! lsmod | grep -q "^sr_mod "; then
                log_message "$MSG_KERNEL_MODULE_LOAD"
                if modprobe sr_mod 2>/dev/null; then
                    log_message "[DriveStatus] ✓ sr_mod erfolgreich geladen"
                    # Nach Modul-Laden 2 Sekunden warten
                    sleep 2
                else
                    log_message "$MSG_KERNEL_MODULE_FAILED"
                fi
            fi
        else
            # Container-Umgebung: Überspringe modprobe
            log_message "[DriveStatus] Container-Modus: Überspringe sr_mod-Laden (muss auf Host geladen sein)"
            
            # Prüfe ob sr_mod auf Host geladen ist
            if ! lsmod | grep -q "^sr_mod "; then
                log_message "[DriveStatus] Warnung: sr_mod nicht im Host geladen!"
                log_message "[DriveStatus] Auf Proxmox Host ausführen: modprobe sr_mod"
            fi
        fi
    fi
    
    # Warte auf Device-Node-Erstellung (wichtig für USB-Laufwerke und sr_mod)
    if [[ ! -b "$device" ]]; then
        log_message "$MSG_DEVICE_WAIT"
        
        # In normaler Umgebung: Warte auf udev
        if [[ "$is_container" == false ]]; then
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
        fi
        
        # Retry-Loop: Warte bis zu 5 Sekunden
        local timeout=5
        while [[ $timeout -gt 0 ]] && [[ ! -b "$device" ]]; do
            sleep 1
            ((timeout--))
        done
    fi
    
    # Prüfe ob Device jetzt verfügbar ist
    if [[ ! -b "$device" ]]; then
        # Erweiterte Diagnose
        log_message "[DriveStatus] Device nicht verfügbar: $device"
        
        # Prüfe ob Device im Kernel bekannt ist
        if [[ "$device" =~ ^/dev/sr[0-9]+$ ]]; then
            local device_name=$(basename "$device")
            if [[ -e "/sys/class/block/$device_name" ]]; then
                log_message "[DriveStatus] Device existiert in /sys/class/block/$device_name"
                log_message "[DriveStatus] Aber /dev/$device_name wurde nicht erstellt"
                
                # Container-spezifische Diagnose
                if [[ "$is_container" == true ]]; then
                    log_message "[DriveStatus] Container-Modus: Device muss vom Host durchgereicht werden"
                    log_message "[DriveStatus] Proxmox Host-Anweisungen:"
                    log_message "[DriveStatus]   WICHTIG: Für CD/DVD-Zugriff muss Container PRIVILEGIERT sein!"
                    log_message "[DriveStatus]   1. pct stop <CTID>"
                    log_message "[DriveStatus]   2. modprobe sr_mod"
                    log_message "[DriveStatus]   3. In /etc/pve/lxc/<CTID>.conf anpassen:"
                    log_message "[DriveStatus]      unprivileged: 0              # Privilegierter Container!"
                    log_message "[DriveStatus]      lxc.cgroup2.devices.allow: b 11:0 rwm"
                    log_message "[DriveStatus]      lxc.mount.entry: /dev/sr0 dev/sr0 none bind,optional,create=file"
                    log_message "[DriveStatus]      lxc.apparmor.profile: unconfined  # Für CD/DVD-Ioctls"
                    log_message "[DriveStatus]   4. pct start <CTID>"
                    log_message "[DriveStatus]   Alternative: Container als privilegiert neu erstellen"
                fi
                
                # Versuche Device-Node manuell zu erstellen (als letzter Ausweg)
                if [[ -r "/sys/class/block/$device_name/dev" ]]; then
                    local major_minor=$(cat "/sys/class/block/$device_name/dev" 2>/dev/null)
                    if [[ -n "$major_minor" ]]; then
                        log_message "[DriveStatus] Versuche Device-Node manuell zu erstellen (Major:Minor = $major_minor)"
                        local major=$(echo "$major_minor" | cut -d: -f1)
                        local minor=$(echo "$major_minor" | cut -d: -f2)
                        if mknod "$device" b "$major" "$minor" 2>/dev/null; then
                            chmod 660 "$device" 2>/dev/null
                            log_message "[DriveStatus] ✓ Device-Node manuell erstellt"
                            sleep 1
                            # Erneute Prüfung
                            if [[ -b "$device" ]]; then
                                log_message "[DriveStatus] ✓ Device bereit: $device"
                                return 0
                            fi
                        else
                            log_message "[DriveStatus] mknod fehlgeschlagen (möglicherweise keine Berechtigung)"
                        fi
                    fi
                fi
            else
                log_message "[DriveStatus] Device existiert nicht in /sys/class/block/"
                if [[ "$is_container" == true ]]; then
                    log_message "[DriveStatus] In Container: Host muss sr_mod laden und Device durchreichen"
                fi
            fi
        fi
        
        return 1
    fi
    
    log_message "[DriveStatus] ✓ Device bereit: $device"
    return 0
}

# Funktion: Prüfe ob Laufwerk-Schublade geschlossen ist
# Rückgabe: 0 = geschlossen, 1 = offen
is_drive_closed() {
    log_message "[DriveStatus] Prüfe Laufwerk-Status..."
    
    # Prüfe ob Device existiert
    if [[ ! -b "$CD_DEVICE" ]]; then
        log_message "[DriveStatus] Device $CD_DEVICE existiert nicht"
        return 1
    fi
    
    # Methode 1: Prüfe /proc/sys/dev/cdrom/info (Linux-spezifisch)
    if [[ -f "/proc/sys/dev/cdrom/info" ]]; then
        local drive_status=$(grep "drive status:" /proc/sys/dev/cdrom/info 2>/dev/null | awk '{print $3}')
        if [[ "$drive_status" == "4" ]]; then
            log_message "[DriveStatus] /proc: Laufwerk geschlossen (Status: 4)"
            return 0
        elif [[ "$drive_status" == "1" ]]; then
            log_message "[DriveStatus] /proc: Laufwerk offen (Status: 1)"
            return 1
        fi
    fi
    
    # Methode 2: Versuche mit blockdev --getsize64 (funktioniert nur bei geschlossenem Laufwerk)
    if command -v blockdev >/dev/null 2>&1; then
        if blockdev --getsize64 "$CD_DEVICE" >/dev/null 2>&1; then
            log_message "[DriveStatus] blockdev: Laufwerk geschlossen (Größe lesbar)"
            return 0
        fi
    fi
    
    # Methode 3: Prüfe mit blkid (funktioniert nur bei geschlossenem Laufwerk mit Medium)
    local fs_type=$(blkid -s TYPE -o value "$CD_DEVICE" 2>/dev/null)
    if [[ -n "$fs_type" ]]; then
        log_message "[DriveStatus] blkid: Laufwerk geschlossen (Dateisystem erkannt: $fs_type)"
        return 0
    fi
    
    # Fallback: Konnte Status nicht eindeutig ermitteln
    log_message "[DriveStatus] Status unklar, nehme 'offen' an"
    return 1
}

# Funktion: Prüfe ob Medium eingelegt ist
# Rückgabe: 0 = Medium vorhanden, 1 = kein Medium
is_disc_inserted() {
    log_message "[DriveStatus] Prüfe auf eingelegtes Medium..."
    
    # Test 1: blkid - Erkennt Dateisysteme (CD-ROM, DVD-ROM, DVD-Video, BD-ROM)
    local fs_type=$(blkid -s TYPE -o value "$CD_DEVICE" 2>/dev/null)
    if [[ -n "$fs_type" ]]; then
        log_message "[DriveStatus] ✓ Medium erkannt via blkid (Typ: $fs_type)"
        return 0
    fi
    
    # Test 2: isoinfo - Erkennt ISO9660/UDF und Blu-rays
    if command -v isoinfo >/dev/null 2>&1; then
        local isoinfo_output=$(isoinfo -d -i "$CD_DEVICE" 2>&1)
        
        # ISO 9660 Format (DVD)
        if echo "$isoinfo_output" | grep -q "Volume id:"; then
            log_message "[DriveStatus] ✓ Medium erkannt via isoinfo (ISO9660)"
            return 0
        fi
        
        # "NOT in ISO 9660 format" (Blu-ray mit UDF)
        if echo "$isoinfo_output" | grep -qi "NOT in ISO 9660 format"; then
            log_message "[DriveStatus] ✓ Medium erkannt via isoinfo (UDF/Blu-ray)"
            return 0
        fi
        
        # "illegal mode for this track" (Audio-CD)
        if echo "$isoinfo_output" | grep -qi "illegal mode for this track"; then
            log_message "[DriveStatus] ✓ Medium erkannt via isoinfo (Audio-Track)"
            return 0
        fi
        
        # Explizit "medium not present"
        if echo "$isoinfo_output" | grep -qi "medium not present"; then
            log_message "[DriveStatus] ✗ Kein Medium (isoinfo: medium not present)"
            return 1
        fi
    fi
    
    # Test 3: cdparanoia - Spezifisch für Audio-CDs
    if command -v cdparanoia >/dev/null 2>&1; then
        local cdparanoia_output=$(cdparanoia -d "$CD_DEVICE" -Q 2>&1)
        
        # Echte Tracks haben Format: "  1.  12345 [02:44.20]"
        if echo "$cdparanoia_output" | grep -q "^[[:space:]]*[0-9]\+\."; then
            log_message "[DriveStatus] ✓ Medium erkannt via cdparanoia (Audio-Tracks)"
            return 0
        fi
    fi
    
    log_message "[DriveStatus] ✗ Kein Medium erkannt"
    return 1
}

# Funktion: Warte auf Änderung im Drive-Status (Schublade öffnen/schließen oder Medium einlegen/entfernen)
# Parameter: $1 = Wartezeit in Sekunden zwischen Prüfungen (default: 5)
# Rückgabe: 0 = Änderung erkannt, 1 = Timeout oder Fehler
wait_for_disc_change() {
    local check_interval="${1:-5}"
    local max_checks="${2:-0}"  # 0 = unbegrenzt
    local check_count=0
    
    # Speichere initialen Status
    local initial_drive_closed=false
    local initial_disc_present=false
    
    is_drive_closed && initial_drive_closed=true
    is_disc_inserted && initial_disc_present=true
    
    log_message "[DriveStatus] Initialer Status: Laufwerk=$(${initial_drive_closed} && echo 'geschlossen' || echo 'offen'), Medium=$(${initial_disc_present} && echo 'eingelegt' || echo 'nicht eingelegt')"
    log_message "[DriveStatus] Warte auf Statusänderung (Prüfung alle ${check_interval}s)..."
    
    while true; do
        sleep "$check_interval"
        ((check_count++))
        
        # Prüfe aktuellen Status
        local current_drive_closed=false
        local current_disc_present=false
        
        is_drive_closed && current_drive_closed=true
        is_disc_inserted && current_disc_present=true
        
        # Änderung im Laufwerk-Status?
        if [[ "$initial_drive_closed" != "$current_drive_closed" ]]; then
            if [[ "$current_drive_closed" == true ]]; then
                log_message "[DriveStatus] ✓ Statusänderung: Laufwerk wurde geschlossen"
            else
                log_message "[DriveStatus] ✓ Statusänderung: Laufwerk wurde geöffnet"
            fi
            return 0
        fi
        
        # Änderung im Medium-Status?
        if [[ "$initial_disc_present" != "$current_disc_present" ]]; then
            if [[ "$current_disc_present" == true ]]; then
                log_message "[DriveStatus] ✓ Statusänderung: Medium wurde eingelegt"
            else
                log_message "[DriveStatus] ✓ Statusänderung: Medium wurde entfernt"
            fi
            return 0
        fi
        
        # Timeout-Prüfung (wenn max_checks gesetzt)
        if [[ $max_checks -gt 0 ]] && [[ $check_count -ge $max_checks ]]; then
            log_message "[DriveStatus] Timeout: Keine Statusänderung nach $check_count Prüfungen"
            return 1
        fi
    done
}

# Funktion: Warte bis Medium bereit ist (nach Einlegen kurze Verzögerung für Spin-Up)
# Parameter: $1 = Wartezeit in Sekunden (default: 3)
wait_for_disc_ready() {
    local wait_time="${1:-3}"
    log_message "[DriveStatus] Warte ${wait_time}s bis Medium bereit ist..."
    sleep "$wait_time"
    
    # Verifiziere dass Medium immer noch da ist
    if is_disc_inserted; then
        log_message "[DriveStatus] ✓ Medium ist bereit"
        return 0
    else
        log_message "[DriveStatus] ✗ Medium wurde während Wartezeit entfernt"
        return 1
    fi
}
