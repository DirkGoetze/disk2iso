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
    
    # Prüfe auf Video-DVD (VIDEO_TS Ordner)
    if isoinfo -f -i "$CD_DEVICE" 2>/dev/null | grep -qi "VIDEO_TS"; then
        disc_type="dvd-video"
        return 0
    fi
    
    # Prüfe auf Blu-ray (BDMV Ordner)
    if isoinfo -f -i "$CD_DEVICE" 2>/dev/null | grep -qi "BDMV"; then
        disc_type="bd-video"
        return 0
    fi
    
    # Ermittle Disc-Größe für CD/DVD/BD Unterscheidung
    local volume_size
    volume_size=$(echo "$iso_info" | grep "Volume size is:" | awk '{print $4}')
    
    if [[ -n "$volume_size" ]]; then
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
    
    # Versuche Volume ID mit isoinfo zu lesen
    if command -v isoinfo >/dev/null 2>&1; then
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
