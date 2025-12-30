#!/bin/bash
#############################################################################
# Disk Information Library - Mit Typ-Erkennung
# Filepath: disk2iso-lib/lib-diskinfos.sh
#
# Beschreibung:
#   Typ-Erkennung und Label-Extraktion mit isoinfo
#
# Erweitert: 24.12.2025
################################################################################

# ============================================================================
# DISC TYPE DETECTION
# ============================================================================

# Funktion zur Erkennung des Disc-Typs
# Rückgabe: audio-cd, cd-rom, dvd-video, dvd-rom, bd-video, bd-rom
detect_disc_type() {
    disc_type="unknown"
    
    # Prüfe zuerst mit blkid (funktioniert besser für UDF/Blu-ray)
    local blkid_output
    blkid_output=$(blkid "$CD_DEVICE" 2>/dev/null)
    
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
    
    # Mounte Disc temporär um Struktur zu prüfen
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
    
    if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
        local size_mb=$((volume_size * 2048 / 1024 / 1024))
        
        # CD: bis 900 MB, DVD: bis 9 GB, BD: darüber
        if [[ $size_mb -lt 900 ]]; then
            disc_type="cd-rom"
        elif [[ $size_mb -lt 9000 ]]; then
            disc_type="dvd-rom"
        else
            disc_type="bd-rom"
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
    
    # Versuche zuerst mit blkid (funktioniert besser für UDF/Blu-ray)
    label=$(blkid "$CD_DEVICE" 2>/dev/null | grep -o 'LABEL="[^"]*"' | cut -d'"' -f2)
    
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
