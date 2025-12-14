#!/bin/bash
#############################################################################
# Disk Information Library
#############################################################################
# Filepath: disk2iso-lib/lib-diskinfos.sh
#
# Beschreibung:
#   Sammlung aller Funktionen zur Ermittlung von Disk-Informationen
#   - Disk-Label/Volume-Namen 
#   - Dateisystem-Informationen (Blockgröße, Volume-Größe)
#   - Disk-Größe in Bytes
#
# Abhängigkeiten:
#   - lib-files.sh (sanitize_filename)
#
################################################################################

# ============================================================================
# DISK LABEL DETECTION
# Quelle: detection/disklabel.sh
# ============================================================================

# Funktion zum Ermitteln des Disk-Labels basierend auf Disk-Typ
# Parameter: $1 = disc_type (audio-cd, cd-rom, dvd-rom, video-dvd, data-bluray, video-bluray)
# Setzt globale Variable: disc_label
get_disc_label() {
    local detected_type="$1"
    local label=""
    
    log_message "[DiskLabel] Ermittle Label für Typ: $detected_type"
    
    case "$detected_type" in
        audio-cd)
            # Audio-CDs: Versuche CD-TEXT oder generiere Namen
            if command -v cd-discid >/dev/null 2>&1; then
                label=$(cd-discid "$CD_DEVICE" 2>/dev/null | awk '{print $NF}')
                log_message "[DiskLabel] CD-TEXT Versuch: $label"
            fi
            
            # Fallback: Generiere Label mit Datum
            if [[ -z "$label" ]] || [[ "$label" == "unknown" ]]; then
                label="AudioCD_$(date '+%Y%m%d_%H%M%S')"
                log_message "[DiskLabel] Fallback AudioCD Name generiert"
            fi
            ;;
            
        cd-rom|dvd-rom|video-dvd)
            # Daten-CDs/DVDs und Video-DVDs: blkid LABEL
            if command -v blkid >/dev/null 2>&1; then
                label=$(blkid -s LABEL -o value "$CD_DEVICE" 2>/dev/null)
                log_message "[DiskLabel] blkid LABEL: $label"
            fi
            
            # Fallback via isoinfo
            if [[ -z "$label" ]] && command -v isoinfo >/dev/null 2>&1; then
                label=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null | grep "Volume id:" | sed 's/Volume id: //' | xargs)
                log_message "[DiskLabel] isoinfo Volume ID: $label"
            fi
            
            # Fallback: Typ-spezifischer Name mit Datum
            if [[ -z "$label" ]]; then
                case "$detected_type" in
                    cd-rom) label="CD_$(date '+%Y%m%d_%H%M%S')" ;;
                    dvd-rom) label="DVD_$(date '+%Y%m%d_%H%M%S')" ;;
                    video-dvd) label="VideoDVD_$(date '+%Y%m%d_%H%M%S')" ;;
                esac
                log_message "[DiskLabel] Fallback Name generiert: $label"
            fi
            ;;
            
        data-bluray|video-bluray)
            # Blu-rays: Versuche UDF Label via blkid
            if command -v blkid >/dev/null 2>&1; then
                label=$(blkid -s LABEL -o value "$CD_DEVICE" 2>/dev/null)
                log_message "[DiskLabel] blkid LABEL (UDF): $label"
            fi
            
            # Fallback: Mount und prüfe Label
            if [[ -z "$label" ]]; then
                local temp_mount=$(get_tmp_mount)
                
                if mount -o ro "$CD_DEVICE" "$temp_mount" 2>/dev/null; then
                    # Versuche Label aus Mount-Info zu extrahieren
                    label=$(findmnt -n -o LABEL "$temp_mount" 2>/dev/null)
                    umount "$temp_mount" 2>/dev/null
                    log_message "[DiskLabel] Mount LABEL: $label"
                fi
                
                rmdir "$temp_mount" 2>/dev/null
            fi
            
            # Fallback: Typ-spezifischer Name mit Datum
            if [[ -z "$label" ]]; then
                case "$detected_type" in
                    data-bluray) label="Bluray_$(date '+%Y%m%d_%H%M%S')" ;;
                    video-bluray) label="VideoBluray_$(date '+%Y%m%d_%H%M%S')" ;;
                esac
                log_message "[DiskLabel] Fallback Name generiert: $label"
            fi
            ;;
            
        *)
            # Unbekannter Typ: Generischer Name
            label="Disc_$(date '+%Y%m%d_%H%M%S')"
            log_message "[DiskLabel] Unbekannter Typ, generischer Name: $label"
            ;;
    esac
    
    # Normalisiere Dateinamen (entferne ungültige Zeichen)
    disc_label=$(sanitize_filename "$label")
    log_message "[DiskLabel] Finales Label: $disc_label"
}

# ============================================================================
# DISK BLOCK & SIZE INFORMATION
# Quelle: unused.sh (reaktiviert für lib-Module)
# ============================================================================

# Funktion zum Ermitteln von Block Size und Volume Size
# Nutzt isoinfo für präzise Werte, cached Ergebnis in globalen Variablen
# Rückgabe: Gibt "$block_size $volume_size" zurück
get_disc_block_info() {
    # Wenn bereits ermittelt, nutze Cache
    if [[ -n "$disc_block_size" ]] && [[ -n "$disc_volume_size" ]]; then
        echo "$disc_block_size $disc_volume_size"
        return 0
    fi
    
    local block_size=2048
    local volume_size=0
    
    if isoinfo -d -i "$CD_DEVICE" >/dev/null 2>&1; then
        local iso_info=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null)
        
        # Extrahiere Block Size
        local extracted_bs=$(echo "$iso_info" | grep -i "Logical block size" | grep -oE '[0-9]+')
        if [[ -n "$extracted_bs" ]]; then
            block_size=$extracted_bs
            log_message "Block Size ermittelt: $block_size" >&2
        fi
        
        # Extrahiere Volume Size
        local extracted_vs=$(echo "$iso_info" | grep -i "Volume size" | grep -oE '[0-9]+')
        if [[ -n "$extracted_vs" ]]; then
            volume_size=$extracted_vs
            log_message "Volume Size ermittelt: $volume_size Blöcke" >&2
        fi
    else
        log_message "Warnung: isoinfo konnte Medium nicht lesen, verwende Standardwerte" >&2
    fi
    
    # Cache in globalen Variablen
    disc_block_size=$block_size
    disc_volume_size=$volume_size
    
    echo "$block_size $volume_size"
}

# Funktion zum Ermitteln der CD/DVD/BD-Größe
# Gibt die Größe in Bytes zurück für pv-Fortschrittsanzeige
# Rückgabe: Größe in Bytes
get_disc_size() {
    local size=0
    
    # Versuche Größe mit blockdev zu ermitteln
    if command -v blockdev >/dev/null 2>&1; then
        size=$(blockdev --getsize64 "$CD_DEVICE" 2>/dev/null)
    fi
    
    # Fallback: Versuche mit isosize
    if [[ $size -eq 0 ]] && command -v isosize >/dev/null 2>&1; then
        size=$(isosize "$CD_DEVICE" 2>/dev/null)
    fi
    
    # Fallback: Schätze basierend auf Medium-Typ
    if [[ $size -eq 0 ]]; then
        # Standard-DVD: 4.7GB
        size=4700372992
    fi
    
    echo "$size"
}

# ============================================================================
# ENDE DER DISK INFORMATION LIBRARY
# ============================================================================
