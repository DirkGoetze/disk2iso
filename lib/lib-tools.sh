#!/bin/bash
################################################################################
# disk2iso v1.2.0 - Tool Detection Library
# Filepath: lib/lib-tools.sh
#
# Beschreibung:
#   Prüfung von Debian-Standard-Tools:
#   - dd, md5sum, lsblk, eject
#
# Version: 1.2.0
# Datum: 06.01.2026
################################################################################

# Lade Sprachdatei
SCRIPT_DIR_TOOLS="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

# Prüfe ob dd verfügbar ist
check_dd() {
    command -v dd >/dev/null 2>&1
}

# Prüfe ob md5sum verfügbar ist
check_md5sum() {
    command -v md5sum >/dev/null 2>&1
}

# Prüfe ob lsblk verfügbar ist
check_lsblk() {
    command -v lsblk >/dev/null 2>&1
}

# Prüfe ob isoinfo verfügbar ist (optional, für optimierte ISO-Kopie)
check_isoinfo() {
    command -v isoinfo >/dev/null 2>&1
}

# Prüfe ob dvdbackup verfügbar ist (optional, für Video-DVD Entschlüsselung)
check_dvdbackup() {
    command -v dvdbackup >/dev/null 2>&1
}

# Prüfe ob genisoimage verfügbar ist (optional, für ISO-Erstellung)
check_genisoimage() {
    command -v genisoimage >/dev/null 2>&1
}

# Prüfe ob ddrescue verfügbar ist (optional, für schnelles Kopieren mit Fehlern)
check_ddrescue() {
    command -v ddrescue >/dev/null 2>&1
}

# Prüfe alle kritischen System-Tools
check_all_critical_tools() {
    local missing=()
    
    check_dd || missing+=("dd")
    check_md5sum || missing+=("md5sum")
    check_lsblk || missing+=("lsblk")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "${missing[@]}"
        return 1
    fi
    
    return 0
}

# Prüfe optionale Tools (für bessere Performance)
check_all_optional_tools() {
    local missing=()
    local available=()
    
    check_isoinfo && available+=("isoinfo") || missing+=("isoinfo (Paket: genisoimage)")
    check_dvdbackup && available+=("dvdbackup") || missing+=("dvdbackup (Paket: dvdbackup)")
    check_genisoimage && available+=("genisoimage") || missing+=("genisoimage (Paket: genisoimage)")
    check_ddrescue && available+=("ddrescue") || missing+=("ddrescue (Paket: gddrescue)")
    
    if [[ ${#available[@]} -gt 0 ]]; then
        log_message "$MSG_AVAILABLE_OPTIONAL_TOOLS ${available[*]}"
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_message "$MSG_MISSING_OPTIONAL_TOOLS ${missing[*]}"
        log_message "$MSG_VIDEO_DVD_OPTIONS"
        log_message "$MSG_DVD_OPTION_1"
        log_message "$MSG_DVD_OPTION_2"
        log_message "$MSG_DVD_OPTION_3"
        return 1
    fi
    
    return 0
}
