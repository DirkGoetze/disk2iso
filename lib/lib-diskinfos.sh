#!/bin/bash
################################################################################
# disk2iso v1.2.0 - Disk Information Library
# Filepath: lib/lib-diskinfos.sh
#
# Beschreibung:
#   Typ-Erkennung und Label-Extraktion für optische Medien:
#   - Audio-CD, Video-DVD, Blu-ray, Daten-Discs
#   - UDF, ISO9660, Audio-TOC Erkennung
#
# Version: 1.2.0
# Datum: 06.01.2026
################################################################################

# ============================================================================
# DISC TYPE DETECTION
# ============================================================================

# Funktion zur Erkennung des Disc-Typs
# Rückgabe: audio-cd, cd-rom, dvd-video, dvd-rom, bd-video, bd-rom
detect_disc_type() {
    disc_type="unknown"
    
    # blkid kann unter /usr/sbin/ liegen
    local blkid_cmd=""
    if command -v blkid >/dev/null 2>&1; then
        blkid_cmd="blkid"
    elif [[ -x /usr/sbin/blkid ]]; then
        blkid_cmd="/usr/sbin/blkid"
    fi
    
    # Prüfe zuerst mit blkid (funktioniert besser für UDF/Blu-ray)
    local blkid_output=""
    if [[ -n "$blkid_cmd" ]]; then
        blkid_output=$($blkid_cmd "$CD_DEVICE" 2>/dev/null)
    fi
    
    # Extrahiere Dateisystem-Typ aus blkid
    local fs_type=""
    if [[ -n "$blkid_output" ]]; then
        fs_type=$(echo "$blkid_output" | grep -o 'TYPE="[^"]*"' | cut -d'"' -f2)
    fi
    
    # Wenn blkid fehlschlägt, versuche isoinfo
    if [[ -z "$blkid_output" ]]; then
        # Prüfe ob isoinfo verfügbar ist
        if ! command -v isoinfo >/dev/null 2>&1; then
            disc_type="data"
            return 0
        fi
        
        # Versuche ISO-Informationen zu lesen
        local iso_info
        iso_info=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null)
        
        # Wenn isoinfo fehlschlägt → Audio-CD (kein Dateisystem)
        if [[ -z "$iso_info" ]]; then
            disc_type="audio-cd"
            return 0
        fi
    fi
    
    # Prüfe Verzeichnisstruktur mit isoinfo (funktioniert auch bei verschlüsselten Discs)
    if command -v isoinfo >/dev/null 2>&1; then
        local iso_listing
        iso_listing=$(isoinfo -l -i "$CD_DEVICE" 2>/dev/null)
        
        # Prüfe auf Video-DVD (VIDEO_TS Verzeichnis)
        if echo "$iso_listing" | grep -q "Directory listing of /VIDEO_TS"; then
            disc_type="dvd-video"
            return 0
        fi
        
        # Prüfe auf Blu-ray (BDMV Verzeichnis)
        if echo "$iso_listing" | grep -q "Directory listing of /BDMV"; then
            disc_type="bd-video"
            return 0
        fi
    fi
    
    # Fallback: Mounte Disc temporär um Struktur zu prüfen (wenn isoinfo fehlschlägt)
    local mount_point=$(get_tmp_mount)
    
    if mount -o ro "$CD_DEVICE" "$mount_point" 2>/dev/null; then
        # Prüfe auf Video-DVD (VIDEO_TS Ordner)
        if [[ -d "$mount_point/VIDEO_TS" ]]; then
            disc_type="dvd-video"
            umount "$mount_point" 2>/dev/null
            rmdir "$mount_point" 2>/dev/null
            return 0
        fi
        
        # Prüfe auf Blu-ray (BDMV Ordner)
        if [[ -d "$mount_point/BDMV" ]]; then
            disc_type="bd-video"
            umount "$mount_point" 2>/dev/null
            rmdir "$mount_point" 2>/dev/null
            return 0
        fi
        
        umount "$mount_point" 2>/dev/null
        rmdir "$mount_point" 2>/dev/null
    fi
    
    # Fallback: Ermittle Disc-Größe für CD/DVD/BD Unterscheidung
    local volume_size=""
    
    if command -v isoinfo >/dev/null 2>&1; then
        volume_size=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null | grep "Volume size is:" | awk '{print $4}')
    fi
    
    # Wenn isoinfo keine Größe liefert (z.B. bei UDF), versuche Blockgerät-Größe
    if [[ -z "$volume_size" ]] || [[ ! "$volume_size" =~ ^[0-9]+$ ]]; then
        if [[ -b "$CD_DEVICE" ]]; then
            # blockdev kann unter /usr/sbin/ liegen
            local blockdev_cmd=""
            if command -v blockdev >/dev/null 2>&1; then
                blockdev_cmd="blockdev"
            elif [[ -x /usr/sbin/blockdev ]]; then
                blockdev_cmd="/usr/sbin/blockdev"
            fi
            
            if [[ -n "$blockdev_cmd" ]]; then
                local device_size=$($blockdev_cmd --getsize64 "$CD_DEVICE" 2>/dev/null)
                if [[ -n "$device_size" ]] && [[ "$device_size" =~ ^[0-9]+$ ]]; then
                    volume_size=$((device_size / 2048))
                fi
            fi
        fi
    fi
    
    if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
        local size_mb=$((volume_size * 2048 / 1024 / 1024))
        
        # CD: bis 900 MB, DVD: bis 9 GB, BD: darüber
        if [[ $size_mb -lt 900 ]]; then
            disc_type="cd-rom"
        elif [[ $size_mb -lt 9000 ]]; then
            disc_type="dvd-rom"
        else
            # Bei UDF und großer Disc → bd-video (kommerzielle Blu-rays sind immer UDF)
            if [[ "$fs_type" == "udf" ]]; then
                disc_type="bd-video"
            else
                disc_type="bd-rom"
            fi
        fi
    else
        disc_type="data"
    fi
    
    return 0
}

# ============================================================================
# LABEL EXTRACTION
# ============================================================================

# Funktion zum Extrahieren des Volume-Labels
# Fallback: Datum
get_volume_label() {
    local label=""
    
    # blkid kann unter /usr/sbin/ liegen
    local blkid_cmd=""
    if command -v blkid >/dev/null 2>&1; then
        blkid_cmd="blkid"
    elif [[ -x /usr/sbin/blkid ]]; then
        blkid_cmd="/usr/sbin/blkid"
    fi
    
    # Versuche zuerst mit blkid (funktioniert besser für UDF/Blu-ray)
    if [[ -n "$blkid_cmd" ]]; then
        label=$($blkid_cmd "$CD_DEVICE" 2>/dev/null | grep -o 'LABEL="[^"]*"' | cut -d'"' -f2)
    fi
    
    # Fallback: Versuche Volume ID mit isoinfo zu lesen
    if [[ -z "$label" ]] && command -v isoinfo >/dev/null 2>&1; then
        label=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null | grep "Volume id:" | sed 's/Volume id: //' | xargs)
    fi
    
    # Fallback: Datum
    if [[ -z "$label" ]] || [[ "$label" =~ ^[[:space:]]*$ ]]; then
        label="Disc_$(date '+%Y%m%d_%H%M%S')"
    fi
    
    # Konvertiere in Kleinbuchstaben
    label=$(echo "$label" | tr '[:upper:]' '[:lower:]')
    
    # Bereinige Label (entferne Sonderzeichen)
    label=$(sanitize_filename "$label")
    
    echo "$label"
}

# Funktion zum Ermitteln des Disc-Labels basierend auf Typ
get_disc_label() {
    local label
    label=$(get_volume_label)
    
    # Setze disc_label global
    disc_label="$label"
}
