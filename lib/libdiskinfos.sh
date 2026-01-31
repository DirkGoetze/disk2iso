#!/bin/bash
# =============================================================================
# Disk Information Library
# =============================================================================
# Filepath: lib/libdiskinfos.sh
#
# Beschreibung:
#   Typ-Erkennung und Label-Extraktion für optische Medien
#   - Audio-CD, Video-DVD, Blu-ray, Daten-Discs
#   - UDF, ISO9660, Audio-TOC Erkennung
#   - get_disc_type(), extract_disc_label()
#   - Unterstützung für verschiedene Dateisysteme
#
# -----------------------------------------------------------------------------
# Dependencies: liblogging (für log_* Funktionen)
# -----------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.2.1
# Last Change: 2026-01-26 20:00
# =============================================================================

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

# ===========================================================================
# check_dependencies_diskinfos
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
check_dependencies_diskinfos() {
    local missing=()
    
    # Kritische Tools (müssen vorhanden sein)
    command -v mount >/dev/null 2>&1 || missing+=("mount")
    command -v umount >/dev/null 2>&1 || missing+=("umount")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Kritische Tools für Disk-Erkennung fehlen: ${missing[*]}"
        log_info "Installation: apt install mount"
        return 1
    fi
    
    # Optionale aber wichtige Tools
    local optional_missing=()
    command -v isoinfo >/dev/null 2>&1 || optional_missing+=("isoinfo")
    command -v blkid >/dev/null 2>&1 || optional_missing+=("blkid")
    command -v blockdev >/dev/null 2>&1 || optional_missing+=("blockdev")
    
    if [[ ${#optional_missing[@]} -gt 0 ]]; then
        log_warning "Optionale Tools für verbesserte Disk-Erkennung fehlen: ${optional_missing[*]}"
        log_info "Installation: apt install genisoimage util-linux"
        log_info "Disk-Erkennung verwendet Fallback-Methoden"
    fi
    
    return 0
}

# ===========================================================================
# Datenstruktur für Disc-Informationen
# ===========================================================================
# DISC_INFO: Metadaten der PHYSISCHEN Disc-Veröffentlichung
#   - Wann/Wo/Von wem wurde DIESE Disc veröffentlicht?
#   - Wichtig für regionale Releases (DE/GB/US) und Label-Zuordnung
#   - Beispiel: Deutsche DVD eines UK-Films → country="DE", aber production_country="GB"
#   - Beispiel: Sampler "Bravo Hits 2021" → release_date="2021-03", aber track.1.year="1989"
declare -A DISC_INFO=(
    # ========== Technische Basis-Informationen ==========
    ["disc_id"]=""         # Provider-ID: MusicBrainz DiscID (Audio-CD) / UUID (DVD/BD/Data)
    ["disc_identifier"]="" # Interne ID für Medium-Wechsel-Erkennung (UUID:LABEL:SIZE_MB)
    ["label"]=""           # Volume-Label (aus Dateisystem)
    ["type"]=""            # Disc-Typ: audio-cd, cd-rom, dvd-video, dvd-rom, bd-video, bd-rom, data
    ["size_sectors"]=0     # Größe in Sektoren (präzise)
    ["size_mb"]=0          # Größe in MB (gerundet)
    ["filesystem"]=""      # Dateisystem: iso9660, udf, mixed, unknown
    ["created_at"]=""      # ISO-Erstellungsdatum (YYYY-MM-DDTHH:MM:SSZ)
    
    # ========== Physische Disc-Veröffentlichung ==========
    ["title"]=""           # Disc-Titel (kann von Album/Film-Titel abweichen bei Compilations)
    ["release_date"]=""    # Veröffentlichungsdatum DIESER Disc (YYYY-MM-DD)
    ["country"]=""         # Veröffentlichungsland DIESER Disc (DE, GB, US, EU)
    ["publisher"]=""       # Publisher/Label DIESER Disc (z.B. Mercury Ltd., Warner Bros. Germany)
    
    # ========== Metadaten-Provider ==========
    ["provider"]=""        # Metadaten-Anbieter: musicbrainz, tmdb, manual, none
    ["provider_id"]=""     # ID des Mediums beim Metadaten-Anbieter
    ["cover_url"]=""       # URL zum Cover-Bild (für Audio-CD/DVD/Blu-ray)
    ["cover_path"]=""      # Lokaler Pfad zum Cover-Bild (für Audio-CD/DVD/Blu-ray)
    
    # ========== Dateinamen (generiert nach Metadata-Auswahl) ==========
    ["iso_filename"]=""    # Vollständiger Pfad zur ISO-Datei
    ["md5_filename"]=""    # Vollständiger Pfad zur MD5-Checksummen-Datei
    ["log_filename"]=""    # Vollständiger Pfad zur Log-Datei
    ["iso_basename"]=""    # Nur Dateiname der ISO (ohne Pfad)
    ["temp_pathname"]=""   # Temporäres Arbeitsverzeichnis für Copy-Vorgang
)

# DISC_DATA: Metadaten des KÜNSTLERISCHEN INHALTS
#   - Informationen über Album/Film/Serie (nicht über die physische Disc)
#   - Typ-spezifisch: Unterschiedliche Felder für Audio/Video/Data
#   - Beispiel: Sampler → album_year=2021, aber track.1.year=1989 (Original-Song-Jahr)
#   - Beispiel: Deutsche DVD → production_country="USA", aber DISC_INFO[country]="DE"
declare -A DISC_DATA=(
    # ========== AUDIO-CD ==========
    ["artist"]=""              # Haupt-Künstler / Album-Artist
    ["album"]=""               # Album-Name (kann von DISC_INFO[title] abweichen bei Compilations)
    ["year"]=""                # Original-Erscheinungsjahr des Albums (nicht der Disc!)
    ["original_release_date"]="" # Original-Veröffentlichungsdatum (YYYY-MM-DD)
    ["original_country"]=""    # Original-Produktionsland (kann von DISC_INFO[country] abweichen)
    ["original_label"]=""      # Original-Plattenlabel (z.B. "Apple Records")
    ["genre"]=""               # Musik-Genre
    ["track_count"]=0          # Anzahl Tracks
    ["duration"]=0             # Gesamtlaufzeit (Millisekunden)
    ["toc"]=""                 # Table of Contents (MusicBrainz DiscID-Berechnung)
    # ["track.1.title"]="..."  # Dynamisch: Track-Titel
    # ["track.1.artist"]="..." # Dynamisch: Artist des Tracks (bei Compilations unterschiedlich)
    # ["track.1.duration"]="..." # Dynamisch: Track-Laufzeit (Millisekunden)
    # ["track.1.year"]="..."   # Dynamisch: Original-Jahr des Tracks (wichtig bei Compilations!)
    
    # ========== VIDEO (DVD/Blu-ray) ==========
    ["movie_title"]=""         # Film-/Serien-Titel (lokalisiert oder Original)
    ["original_title"]=""      # Original-Titel (falls lokalisiert)
    ["movie_year"]=""          # Produktionsjahr des Films/Serie
    ["production_country"]=""  # Produktionsland (USA, GB, etc.)
    ["director"]=""            # Regisseur
    ["runtime"]=0              # Laufzeit (Minuten)
    ["overview"]=""            # Plot/Beschreibung
    ["media_type"]=""          # "movie" oder "tv"
    ["season"]=""              # Staffel-Nummer (nur bei TV-Serien)
    ["episode"]=""             # Episode (nur bei TV-Serien)
    ["rating"]=""              # Bewertung (z.B. "8.5")
    # ["genre.1"]="..."        # Dynamisch: Genre (mehrere möglich)
    # ["genre.2"]="..."
    
    # ========== DATA-DISC ==========
    ["description"]=""         # Freitext-Beschreibung des Inhalts
    ["backup_date"]=""         # Backup-Datum (YYYY-MM-DD)
)

# ============================================================================
# GETTER/SETTER FUNKTIONEN FÜR DISC_INFO
# ============================================================================

# ===========================================================================
# discinfo_init
# ---------------------------------------------------------------------------
# Funktion.: Initialisiere/Leere DISC_INFO Array
# Parameter: keine
# Rückgabe.: 0
# Beschr...: Setzt alle Felder auf Standardwerte zurück
# ===========================================================================
discinfo_init() {
    DISC_INFO[disc_id]=""
    DISC_INFO[disc_identifier]=""
    DISC_INFO[label]=""
    DISC_INFO[type]=""
    DISC_INFO[size_sectors]=0
    DISC_INFO[size_mb]=0
    DISC_INFO[block_size]=2048
    DISC_INFO[filesystem]=""
    DISC_INFO[created_at]=""
    DISC_INFO[title]=""
    DISC_INFO[release_date]=""
    DISC_INFO[country]=""
    DISC_INFO[publisher]=""
    DISC_INFO[provider]=""
    DISC_INFO[provider_id]=""
    DISC_INFO[cover_url]=""
    DISC_INFO[cover_path]=""
    DISC_INFO[iso_filename]=""
    DISC_INFO[md5_filename]=""
    DISC_INFO[log_filename]=""
    DISC_INFO[iso_basename]=""
    DISC_INFO[temp_pathname]=""
    
    log_debug "discinfo_init: DISC_INFO zurückgesetzt"
    return 0
}

# ===========================================================================
# discinfo_get_id
# ---------------------------------------------------------------------------
# Funktion.: Lese Disc-ID (Provider-spezifisch)
# Parameter: keine
# Ausgabe..: Disc-ID (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_id() {
    #-- Array Wert lesen ----------------------------------------------------
    local id="${DISC_INFO[disc_id]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$id" ]]; then
        log_debug "discinfo_get_id: '$id'"
        echo "$id"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "discinfo_get_id: Keine disc_id gesetzt"
    return 1
}

# ===========================================================================
# discinfo_set_id
# ---------------------------------------------------------------------------
# Funktion.: Setze Disc-ID 
# Parameter: $1 = disc_id (UUID oder MusicBrainz DiscID)
# Rückgabe.: 0 = Erfolg, 1 = Keine UUID verfügbar
# Beschr...: NICHT für interne Medium-Erkennung - siehe discinfo_get_identifier()
# ===========================================================================
discinfo_set_id() {
    #-- Parameter übernehmen ------------------------------------------------
    local uuid="$1"

    #-- Setze UUID (kann leer sein) -----------------------------------------
    DISC_INFO[disc_id]="$uuid"
    log_debug "discinfo_set_id: UUID = '$uuid'"
    
    if [[ -n "$uuid" ]]; then
        return 0
    fi
    
    return 1
}

# ===========================================================================
# discinfo_detect_id()
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt Disc-ID (Provider-spezifisch: UUID)
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Keine UUID verfügbar
# ===========================================================================
discinfo_detect_id() {
    #-- Ermittle erkannten Disc-Typ -----------------------------------------
    local disc_type=$(discinfo_get_type)
    log_debug "discinfo_detect_id: Ermittelter disc_type = '$disc_type'"
    
    #-- Audio-CDs: DiscID wird von copy_audio_cd() gesetzt (via cd-discid) --
    if [[ "$disc_type" == "audio-cd" ]]; then
        log_debug "discinfo_detect_id: Audio-CD - DiscID wird von copy_audio_cd() gesetzt"
        return 0
    fi
    
    #-- DVD/BD/Data: Ermittle UUID mit blkid --------------------------------
    local uuid=""
    
    #-- blkid kann unter /usr/sbin/ liegen ----------------------------------
    local blkid_cmd=""
    if command -v blkid >/dev/null 2>&1; then
        blkid_cmd="blkid"
    elif [[ -x /usr/sbin/blkid ]]; then
        blkid_cmd="/usr/sbin/blkid"
    fi
    
    if [[ -n "$blkid_cmd" ]]; then
        local blkid_output
        blkid_output=$($blkid_cmd -p "$CD_DEVICE" 2>/dev/null)
        
        if [[ -n "$blkid_output" ]]; then
            uuid=$(echo "$blkid_output" | grep -oP 'UUID="?\K[^"]+' 2>/dev/null || echo "")
        fi
    fi
    
    #-- Setze UUID ----------------------------------------------------------
    discinfo_set_id "$uuid"
    return $?
}

# ===========================================================================
# discinfo_get_identifier
# ---------------------------------------------------------------------------
# Funktion.: Liest interne Disc-Identifier (für Medium-Wechsel-Erkennung)
# Parameter: keine
# Rückgabe.: Disc-Identifier (stdout)
# Rückgabe.: 0
# ===========================================================================
discinfo_get_identifier() {    
    #-- Array Wert lesen ----------------------------------------------------
    local identifier="${DISC_INFO[disc_identifier]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$identifier" ]]; then
        log_debug "discinfo_get_identifier: '$identifier'"
        echo "$identifier"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "discinfo_get_identifier: Keine disc_identifier gesetzt"
    return 1
}

# ===========================================================================
# discinfo_set_identifier
# ---------------------------------------------------------------------------
# Funktion.: Setzt interne Disc-Identifier für Medium-Wechsel-Erkennung 
# .........  (Format: UUID:LABEL:SIZE_MB)
# Parameter: $1 = identifier (Format: UUID:LABEL:SIZE_MB)
# Rückgabe.: 0
# Beschr...: Setzt DISC_INFO[disc_identifier]
# ===========================================================================
discinfo_set_identifier() {
    #-- Parameter übernehmen ------------------------------------------------
    local identifier="$1"

    #-- Setze UUID (kann leer sein) -----------------------------------------
    DISC_INFO[disc_identifier]="$identifier"
    log_debug "discinfo_set_identifier: Identifier = '$identifier'"
    
    if [[ -n "$identifier" ]]; then
        return 0
    fi
    
    return 1
}

# ===========================================================================
# discinfo_detect_identifier
# ---------------------------------------------------------------------------
# Funktion.: Berechne interne Disc-Identifier für Medium-Wechsel-Erkennung 
# .........  aus den Werten DISC_INFO[disc_id], DISC_INFO[label] und 
# .........  DISC_INFO[size_mb] (Format: UUID:LABEL:SIZE_MB)
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
discinfo_detect_identifier() {
    #-- UUID aus DISC_INFO[disc_id] mit Getter lesen ------------------------
    local uuid=$(discinfo_get_id)
    
    #-- Label aus DISC_INFO[label] mit Getter lesen -------------------------
    local label=$(discinfo_get_label)
    
    #-- Disk-Größe aus DISC_INFO[size_mb] mit Getter lesen ------------------
    local size_mb=$(discinfo_get_size_mb)
    
    #-- Baue Identifier: UUID:LABEL:SIZE_MB ---------------------------------
    discinfo_set_identifier "${uuid}:${label}:${size_mb}"
    return $?
}

# ===========================================================================
# discinfo_get_label
# ---------------------------------------------------------------------------
# Funktion.: Lese Disc-Label
# Parameter: keine
# Ausgabe..: Disc-Label (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_label() {
    local label="${DISC_INFO[label]}"
    if [[ -n "$label" ]]; then
        echo "$label"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_label
# ---------------------------------------------------------------------------
# Funktion.: Setze Disc-Label mit Normalisierung
# Parameter: $1 = label
# Rückgabe.: 0
# Beschr...: Konvertiert zu Kleinbuchstaben und bereinigt Sonderzeichen
# ===========================================================================
discinfo_set_label() {
    local label="$1"
    
    if [[ -z "$label" ]]; then
        log_warning "discinfo_set_label: Leeres Label - verwende Fallback"
        label="disc_$(date '+%Y%m%d_%H%M%S')"
    fi
    
    # Normalisierung
    label=$(echo "$label" | tr '[:upper:]' '[:lower:]')
    label=$(sanitize_filename "$label")
    
    DISC_INFO[label]="$label"
    log_debug "discinfo_set_label: '$label'"
    return 0
}

# ===========================================================================
# discinfo_detect_label
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Volume-Label von Disc
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# ===========================================================================
discinfo_detect_label() {
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
    
    # Setze via Setter (mit Normalisierung)
    discinfo_set_label "$label"
    return $?
}

# ===========================================================================
# discinfo_get_type
# ---------------------------------------------------------------------------
# Funktion.: Lese Disc-Typ
# Parameter: keine
# Ausgabe..: Disc-Typ (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_type() {
    local type="${DISC_INFO[type]}"
    if [[ -n "$type" ]]; then
        echo "$type"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_type
# ---------------------------------------------------------------------------
# Funktion.: Setze Disc-Typ mit Validierung
# Parameter: $1 = disc_type
# Rückgabe.: 0 = Erfolg, 1 = Ungültiger Typ
# Beschr...: Erlaubte Werte: audio-cd, cd-rom, dvd-video, dvd-rom, 
#            bd-video, bd-rom, data, unknown
# ===========================================================================
discinfo_set_type() {
    local type="$1"
    
    # Validierung
    case "$type" in
        audio-cd|cd-rom|dvd-video|dvd-rom|bd-video|bd-rom|data|unknown)
            DISC_INFO[type]="$type"
            log_debug "discinfo_set_type: '$type'"
            return 0
            ;;
        *)
            log_error "discinfo_set_type: Ungültiger disc_type '$type'"
            return 1
            ;;
    esac
}

# ===========================================================================
# discinfo_detect_type
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Disc-Typ (Audio-CD, DVD-Video, BD-Video, etc.)
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# ===========================================================================
discinfo_detect_type() {
    local detected_type="unknown"
    
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
        discinfo_set_filesystem "$fs_type"
    fi
    
    # Wenn blkid fehlschlägt, versuche isoinfo
    if [[ -z "$blkid_output" ]]; then
        # Prüfe ob isoinfo verfügbar ist
        if ! command -v isoinfo >/dev/null 2>&1; then
            discinfo_set_type "data"
            return 0
        fi
        
        # Versuche ISO-Informationen zu lesen
        local iso_info
        iso_info=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null)
        
        # Wenn isoinfo fehlschlägt → Audio-CD (kein Dateisystem)
        if [[ -z "$iso_info" ]]; then
            discinfo_set_type "audio-cd"
            return 0
        fi
    fi
    
    # Prüfe Verzeichnisstruktur mit isoinfo (funktioniert auch bei verschlüsselten Discs)
    if command -v isoinfo >/dev/null 2>&1; then
        local iso_listing
        iso_listing=$(isoinfo -l -i "$CD_DEVICE" 2>/dev/null)
        
        # Prüfe auf Video-DVD (VIDEO_TS Verzeichnis)
        if echo "$iso_listing" | grep -q "Directory listing of /VIDEO_TS"; then
            discinfo_set_type "dvd-video"
            return 0
        fi
        
        # Prüfe auf Blu-ray (BDMV Verzeichnis)
        if echo "$iso_listing" | grep -q "Directory listing of /BDMV"; then
            discinfo_set_type "bd-video"
            return 0
        fi
    fi
    
    # Fallback: Mounte Disc temporär um Struktur zu prüfen (wenn isoinfo fehlschlägt)
    local mount_point=$(get_tmp_mount)
    
    if mount -o ro "$CD_DEVICE" "$mount_point" 2>/dev/null; then
        # Prüfe auf Video-DVD (VIDEO_TS Ordner)
        if [[ -d "$mount_point/VIDEO_TS" ]]; then
            discinfo_set_type "dvd-video"
            umount "$mount_point" 2>/dev/null
            rmdir "$mount_point" 2>/dev/null
            return 0
        fi
        
        # Prüfe auf Blu-ray (BDMV Ordner)
        if [[ -d "$mount_point/BDMV" ]]; then
            discinfo_set_type "bd-video"
            umount "$mount_point" 2>/dev/null
            rmdir "$mount_point" 2>/dev/null
            return 0
        fi
        
        umount "$mount_point" 2>/dev/null
        rmdir "$mount_point" 2>/dev/null
    fi
    
    # Fallback: Ermittle Disc-Größe für CD/DVD/BD Unterscheidung
    local volume_size="${DISC_INFO[size_sectors]}"
    
    # Wenn noch keine Größe gesetzt, versuche mit blockdev
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
                    discinfo_set_size "$volume_size" 2048
                fi
            fi
        fi
    fi
    
    if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
        local size_mb=$((volume_size * 2048 / 1024 / 1024))
        
        # CD: bis 900 MB, DVD: bis 9 GB, BD: darüber
        if [[ $size_mb -lt 900 ]]; then
            detected_type="cd-rom"
        elif [[ $size_mb -lt 9000 ]]; then
            detected_type="dvd-rom"
        else
            # Bei UDF und großer Disc → bd-video (kommerzielle Blu-rays sind immer UDF)
            if [[ "$fs_type" == "udf" ]]; then
                detected_type="bd-video"
            else
                detected_type="bd-rom"
            fi
        fi
    else
        detected_type="data"
    fi
    
    discinfo_set_type "$detected_type"
    return $?
}

# ===========================================================================
# discinfo_get_size_mb
# ---------------------------------------------------------------------------
# Funktion.: Lese Disc-Größe in MB
# Parameter: keine
# Ausgabe..: Größe in MB (stdout)
# Rückgabe.: 0
# ===========================================================================
discinfo_get_size_mb() {
    echo "${DISC_INFO[size_mb]}"
    return 0
}

# ===========================================================================
# discinfo_get_size_sectors
# ---------------------------------------------------------------------------
# Funktion.: Lese Disc-Größe in Sektoren
# Parameter: keine
# Ausgabe..: Anzahl Sektoren (stdout)
# Rückgabe.: 0
# ===========================================================================
discinfo_get_size_sectors() {
    echo "${DISC_INFO[size_sectors]}"
    return 0
}

# ===========================================================================
# discinfo_get_block_size
# ---------------------------------------------------------------------------
# Funktion.: Lese Block-Größe
# Parameter: keine
# Ausgabe..: Block-Größe in Bytes (stdout)
# Rückgabe.: 0
# ===========================================================================
discinfo_get_block_size() {
    echo "${DISC_INFO[block_size]}"
    return 0
}

# ===========================================================================
# discinfo_set_size
# ---------------------------------------------------------------------------
# Funktion.: Setze Disc-Größe (in Sektoren UND MB)
# Parameter: $1 = size_sectors (Anzahl Blöcke/Sektoren)
#            $2 = block_size (optional, default: 2048)
# Rückgabe.: 0
# Beschr...: Berechnet automatisch size_mb aus size_sectors * block_size
# ===========================================================================
discinfo_set_size() {
    local size_sectors="$1"
    local block_size="${2:-2048}"
    
    if [[ ! "$size_sectors" =~ ^[0-9]+$ ]]; then
        log_warning "discinfo_set_size: Ungültige Sektoren-Anzahl '$size_sectors'"
        DISC_INFO[size_sectors]=0
        DISC_INFO[size_mb]=0
        DISC_INFO[block_size]=2048
        return 1
    fi
    
    DISC_INFO[size_sectors]="$size_sectors"
    DISC_INFO[block_size]="$block_size"
    
    # Berechne MB (size_sectors * block_size / 1024 / 1024)
    local size_bytes=$((size_sectors * block_size))
    local size_mb=$((size_bytes / 1024 / 1024))
    DISC_INFO[size_mb]="$size_mb"
    
    log_debug "discinfo_set_size: $size_sectors sectors @ $block_size bytes = $size_mb MB"
    return 0
}

# ===========================================================================
# discinfo_detect_size
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Disc-Größe mit isoinfo
# Parameter: keine
# Rückgabe.: 0 = Größe ermittelt, 1 = Keine Größe verfügbar
# ===========================================================================
discinfo_detect_size() {
    local block_size=2048  # Fallback-Wert für optische Medien
    local volume_size=""
    
    if command -v isoinfo >/dev/null 2>&1; then
        local isoinfo_output
        isoinfo_output=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null)
        
        # Lese Block Size dynamisch aus (falls verfügbar)
        local detected_block_size
        detected_block_size=$(echo "$isoinfo_output" | grep -i "Logical block size is:" | awk '{print $5}')
        if [[ -n "$detected_block_size" ]] && [[ "$detected_block_size" =~ ^[0-9]+$ ]]; then
            block_size=$detected_block_size
        fi
        
        # Lese Volume Size aus
        volume_size=$(echo "$isoinfo_output" | grep "Volume size is:" | awk '{print $4}')
        if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
            # Setze Größe im DISC_INFO Array
            discinfo_set_size "$volume_size" "$block_size"
            
            # Setze alte globale Variablen (Rückwärtskompatibilität - DEPRECATED)
            disc_block_size="$block_size"
            disc_volume_size="$volume_size"
            total_bytes=$((volume_size * block_size))
            return 0
        fi
    fi
    
    # Keine Größe ermittelt
    discinfo_set_size 0 2048
    disc_volume_size=""
    total_bytes=0
    return 1
}

# ===========================================================================
# discinfo_get_filesystem
# ---------------------------------------------------------------------------
# Funktion.: Lese Dateisystem-Typ
# Parameter: keine
# Ausgabe..: Dateisystem (stdout)
# Rückgabe.: 0
# ===========================================================================
discinfo_get_filesystem() {
    echo "${DISC_INFO[filesystem]:-unknown}"
    return 0
}

# ===========================================================================
# discinfo_set_filesystem
# ---------------------------------------------------------------------------
# Funktion.: Setze Dateisystem-Typ
# Parameter: $1 = filesystem (z.B. iso9660, udf, mixed, unknown)
# Rückgabe.: 0
# ===========================================================================
discinfo_set_filesystem() {
    local fs="$1"
    DISC_INFO[filesystem]="$fs"
    log_debug "discinfo_set_filesystem: '$fs'"
    return 0
}

# ===========================================================================
# discinfo_detect_filesystem
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Dateisystem-Typ
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# Beschr...: Wird normalerweise von discinfo_detect_type() aufgerufen
# ===========================================================================
discinfo_detect_filesystem() {
    local fs_type="unknown"
    
    # blkid kann unter /usr/sbin/ liegen
    local blkid_cmd=""
    if command -v blkid >/dev/null 2>&1; then
        blkid_cmd="blkid"
    elif [[ -x /usr/sbin/blkid ]]; then
        blkid_cmd="/usr/sbin/blkid"
    fi
    
    if [[ -n "$blkid_cmd" ]]; then
        local blkid_output
        blkid_output=$($blkid_cmd "$CD_DEVICE" 2>/dev/null)
        if [[ -n "$blkid_output" ]]; then
            fs_type=$(echo "$blkid_output" | grep -o 'TYPE="[^"]*"' | cut -d'"' -f2)
        fi
    fi
    
    discinfo_set_filesystem "$fs_type"
    return $?
}

# ===========================================================================
# discinfo_get_created_at
# ---------------------------------------------------------------------------
# Funktion.: Lese Erstellungsdatum
# Parameter: keine
# Ausgabe..: ISO 8601 Timestamp (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_created_at() {
    local timestamp="${DISC_INFO[created_at]}"
    if [[ -n "$timestamp" ]]; then
        echo "$timestamp"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_created_at
# ---------------------------------------------------------------------------
# Funktion.: Setze Erstellungsdatum
# Parameter: $1 = timestamp (ISO 8601 Format: YYYY-MM-DDTHH:MM:SSZ)
# Rückgabe.: 0
# ===========================================================================
discinfo_set_created_at() {
    local timestamp="$1"
    DISC_INFO[created_at]="$timestamp"
    log_debug "discinfo_set_created_at: '$timestamp'"
    return 0
}

# ===========================================================================
# discinfo_detect_created_at
# ---------------------------------------------------------------------------
# Funktion.: Ermittle ISO-Erstellungsdatum
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# ===========================================================================
discinfo_detect_created_at() {
    local timestamp=""
    
    if command -v isoinfo >/dev/null 2>&1; then
        timestamp=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null | grep "Creation Date:" | sed 's/Creation Date: //' | xargs)
    fi
    
    # Fallback: Aktuelles Datum
    if [[ -z "$timestamp" ]]; then
        timestamp=$(date -Iseconds)
    fi
    
    discinfo_set_created_at "$timestamp"
    return $?
}

# ===========================================================================
# discinfo_get_title
# ---------------------------------------------------------------------------
# Funktion.: Lese Disc-Titel
# Parameter: keine
# Ausgabe..: Titel (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_title() {
    local title="${DISC_INFO[title]}"
    if [[ -n "$title" ]]; then
        echo "$title"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_title
# ---------------------------------------------------------------------------
# Funktion.: Setze Disc-Titel
# Parameter: $1 = title
# Rückgabe.: 0
# ===========================================================================
discinfo_set_title() {
    local title="$1"
    DISC_INFO[title]="$title"
    log_debug "discinfo_set_title: '$title'"
    return 0
}

# ===========================================================================
# discinfo_detect_title
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Disc-Titel
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# Beschr...: Wird normalerweise von Provider-Modulen gesetzt
# ===========================================================================
discinfo_detect_title() {
    # Fallback: Nutze Label als Titel
    local title
    title=$(discinfo_get_label)
    
    if [[ -z "$title" ]]; then
        title="Unknown Disc"
    fi
    
    discinfo_set_title "$title"
    return $?
}

# ===========================================================================
# discinfo_get_release_date
# ---------------------------------------------------------------------------
# Funktion.: Lese Veröffentlichungsdatum
# Parameter: keine
# Ausgabe..: Datum (YYYY-MM-DD) (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_release_date() {
    local date="${DISC_INFO[release_date]}"
    if [[ -n "$date" ]]; then
        echo "$date"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_release_date
# ---------------------------------------------------------------------------
# Funktion.: Setze Veröffentlichungsdatum
# Parameter: $1 = date (YYYY-MM-DD)
# Rückgabe.: 0
# ===========================================================================
discinfo_set_release_date() {
    local date="$1"
    DISC_INFO[release_date]="$date"
    log_debug "discinfo_set_release_date: '$date'"
    return 0
}

# ===========================================================================
# discinfo_detect_release_date
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Veröffentlichungsdatum
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# Beschr...: Wird normalerweise von Provider-Modulen gesetzt
#            Fallback 1: ISO-Erstellungsdatum (created_at)
#            Fallback 2: Aktuelles Datum
# ===========================================================================
discinfo_detect_release_date() {
    # Fallback: Nutze ISO-Erstellungsdatum (nur Datum, nicht Uhrzeit)
    local created_at
    created_at=$(discinfo_get_created_at)
    
    if [[ -n "$created_at" ]]; then
        # Extrahiere nur Datum (YYYY-MM-DD) aus ISO 8601 (YYYY-MM-DDTHH:MM:SSZ)
        local date="${created_at%%T*}"
        discinfo_set_release_date "$date"
    else
        # Letzter Fallback: Aktuelles Datum
        discinfo_set_release_date "$(date '+%Y-%m-%d')"
    fi
    return 0
}

# ===========================================================================
# discinfo_get_country
# ---------------------------------------------------------------------------
# Funktion.: Lese Veröffentlichungsland
# Parameter: keine
# Ausgabe..: Ländercode (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_country() {
    local country="${DISC_INFO[country]}"
    if [[ -n "$country" ]]; then
        echo "$country"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_country
# ---------------------------------------------------------------------------
# Funktion.: Setze Veröffentlichungsland
# Parameter: $1 = country (Ländercode: DE, GB, US, EU, etc.)
# Rückgabe.: 0
# ===========================================================================
discinfo_set_country() {
    local country="$1"
    DISC_INFO[country]="$country"
    log_debug "discinfo_set_country: '$country'"
    return 0
}

# ===========================================================================
# discinfo_detect_country
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Veröffentlichungsland
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# Beschr...: Wird normalerweise von Provider-Modulen gesetzt
# ===========================================================================
discinfo_detect_country() {
    # Fallback: Unknown
    discinfo_set_country "XX"
    return $?
}

# ===========================================================================
# discinfo_get_publisher
# ---------------------------------------------------------------------------
# Funktion.: Lese Publisher/Label
# Parameter: keine
# Ausgabe..: Publisher (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_publisher() {
    local publisher="${DISC_INFO[publisher]}"
    if [[ -n "$publisher" ]]; then
        echo "$publisher"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_publisher
# ---------------------------------------------------------------------------
# Funktion.: Setze Publisher/Label
# Parameter: $1 = publisher
# Rückgabe.: 0
# ===========================================================================
discinfo_set_publisher() {
    local publisher="$1"
    DISC_INFO[publisher]="$publisher"
    log_debug "discinfo_set_publisher: '$publisher'"
    return 0
}

# ===========================================================================
# discinfo_detect_publisher
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Publisher/Label
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# Beschr...: Wird normalerweise von Provider-Modulen gesetzt
# ===========================================================================
discinfo_detect_publisher() {
    # Fallback: Unknown
    discinfo_set_publisher "Unknown Publisher"
    return $?
}

# ===========================================================================
# discinfo_get_provider
# ---------------------------------------------------------------------------
# Funktion.: Lese Metadaten-Provider
# Parameter: keine
# Ausgabe..: Provider-Name (stdout)
# Rückgabe.: 0
# ===========================================================================
discinfo_get_provider() {
    echo "${DISC_INFO[provider]:-none}"
    return 0
}

# ===========================================================================
# discinfo_set_provider
# ---------------------------------------------------------------------------
# Funktion.: Setze Metadaten-Provider
# Parameter: $1 = provider (musicbrainz, tmdb, manual, none)
# Rückgabe.: 0
# ===========================================================================
discinfo_set_provider() {
    local provider="$1"
    DISC_INFO[provider]="$provider"
    log_debug "discinfo_set_provider: '$provider'"
    return 0
}

# ===========================================================================
# discinfo_detect_provider
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Metadaten-Provider
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# Beschr...: Basierend auf Disc-Typ wird Provider ausgewählt
# ===========================================================================
discinfo_detect_provider() {
    local disc_type
    disc_type=$(discinfo_get_type)
    
    local provider="none"
    case "$disc_type" in
        audio-cd)
            provider="musicbrainz"
            ;;
        dvd-video|bd-video)
            provider="tmdb"
            ;;
        *)
            provider="none"
            ;;
    esac
    
    discinfo_set_provider "$provider"
    return $?
}

# ===========================================================================
# discinfo_get_provider_id
# ---------------------------------------------------------------------------
# Funktion.: Lese Provider-ID
# Parameter: keine
# Ausgabe..: Provider-ID (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_provider_id() {
    local id="${DISC_INFO[provider_id]}"
    if [[ -n "$id" ]]; then
        echo "$id"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_provider_id
# ---------------------------------------------------------------------------
# Funktion.: Setze Provider-ID
# Parameter: $1 = provider_id
# Rückgabe.: 0
# ===========================================================================
discinfo_set_provider_id() {
    local id="$1"
    DISC_INFO[provider_id]="$id"
    log_debug "discinfo_set_provider_id: '$id'"
    return 0
}

# ===========================================================================
# discinfo_detect_provider_id
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Provider-ID
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# Beschr...: Wird normalerweise von Provider-Modulen gesetzt
# ===========================================================================
discinfo_detect_provider_id() {
    # Keine automatische Erkennung möglich
    discinfo_set_provider_id ""
    return $?
}

# ===========================================================================
# discinfo_get_cover_path
# ---------------------------------------------------------------------------
# Funktion.: Lese lokalen Cover-Pfad
# Parameter: keine
# Ausgabe..: Dateipfad (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_cover_path() {
    local path="${DISC_INFO[cover_path]}"
    if [[ -n "$path" ]]; then
        echo "$path"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_cover_path
# ---------------------------------------------------------------------------
# Funktion.: Setze lokalen Cover-Pfad
# Parameter: $1 = cover_path
# Rückgabe.: 0
# ===========================================================================
discinfo_set_cover_path() {
    local path="$1"
    DISC_INFO[cover_path]="$path"
    log_debug "discinfo_set_cover_path: '$path'"
    return 0
}

# ===========================================================================
# discinfo_detect_cover_path
# ---------------------------------------------------------------------------
# Funktion.: Ermittle lokalen Cover-Pfad
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# Beschr...: Wird normalerweise von Provider-Modulen gesetzt
# ===========================================================================
discinfo_detect_cover_path() {
    # Keine automatische Erkennung möglich
    discinfo_set_cover_path ""
    return $?
}

# ===========================================================================
# discinfo_get_cover_url
# ---------------------------------------------------------------------------
# Funktion.: Lese Cover-URL
# Parameter: keine
# Ausgabe..: URL (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_cover_url() {
    local url="${DISC_INFO[cover_url]}"
    if [[ -n "$url" ]]; then
        echo "$url"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_cover_url
# ---------------------------------------------------------------------------
# Funktion.: Setze Cover-URL
# Parameter: $1 = cover_url
# Rückgabe.: 0
# ===========================================================================
discinfo_set_cover_url() {
    local url="$1"
    DISC_INFO[cover_url]="$url"
    log_debug "discinfo_set_cover_url: '$url'"
    return 0
}

# ===========================================================================
# discinfo_detect_cover_url
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Cover-URL
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# Beschr...: Wird normalerweise von Provider-Modulen gesetzt
# ===========================================================================
discinfo_detect_cover_url() {
    # Keine automatische Erkennung möglich
    discinfo_set_cover_url ""
    return $?
}

# ===========================================================================
# Dateinamen-Getter/Setter (ohne Detect - werden von init_filenames() gesetzt)
# ===========================================================================

# ===========================================================================
# discinfo_get_iso_filename
# ---------------------------------------------------------------------------
# Funktion.: Setze ISO-Dateinamen
# Parameter: $1 = iso_filename (vollständiger Pfad)
# Rückgabe.: 0
# ===========================================================================
discinfo_set_iso_filename() {
    local filename="$1"
    DISC_INFO[iso_filename]="$filename"
    log_debug "discinfo_set_iso_filename: '$filename'"
    return 0
}

# ===========================================================================
# discinfo_get_iso_filename
# ---------------------------------------------------------------------------
# Funktion.: Lese ISO-Dateinamen
# Parameter: keine
# Ausgabe..: ISO-Dateiname (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_iso_filename() {
    local filename="${DISC_INFO[iso_filename]}"
    if [[ -n "$filename" ]]; then
        echo "$filename"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_md5_filename
# ---------------------------------------------------------------------------
# Funktion.: Setze MD5-Dateinamen
# Parameter: $1 = md5_filename (vollständiger Pfad)
# Rückgabe.: 0
# ===========================================================================
discinfo_set_md5_filename() {
    local filename="$1"
    DISC_INFO[md5_filename]="$filename"
    log_debug "discinfo_set_md5_filename: '$filename'"
    return 0
}

# ===========================================================================
# discinfo_get_md5_filename
# ---------------------------------------------------------------------------
# Funktion.: Lese MD5-Dateinamen
# Parameter: keine
# Ausgabe..: MD5-Dateiname (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_md5_filename() {
    local filename="${DISC_INFO[md5_filename]}"
    if [[ -n "$filename" ]]; then
        echo "$filename"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_log_filename
# ---------------------------------------------------------------------------
# Funktion.: Setze Log-Dateinamen
# Parameter: $1 = log_filename (vollständiger Pfad)
# Rückgabe.: 0
# ===========================================================================
discinfo_set_log_filename() {
    local filename="$1"
    DISC_INFO[log_filename]="$filename"
    log_debug "discinfo_set_log_filename: '$filename'"
    return 0
}

# ===========================================================================
# discinfo_get_log_filename
# ---------------------------------------------------------------------------
# Funktion.: Lese Log-Dateinamen
# Parameter: keine
# Ausgabe..: Log-Dateiname (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_log_filename() {
    local filename="${DISC_INFO[log_filename]}"
    if [[ -n "$filename" ]]; then
        echo "$filename"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_iso_basename
# ---------------------------------------------------------------------------
# Funktion.: Setze ISO-Basisnamen
# Parameter: $1 = iso_basename (nur Dateiname)
# Rückgabe.: 0
# ===========================================================================
discinfo_set_iso_basename() {
    local basename="$1"
    DISC_INFO[iso_basename]="$basename"
    log_debug "discinfo_set_iso_basename: '$basename'"
    return 0
}

# ===========================================================================
# discinfo_get_iso_basename
# ---------------------------------------------------------------------------
# Funktion.: Lese ISO-Basisnamen
# Parameter: keine
# Ausgabe..: ISO-Basisname (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_iso_basename() {
    local basename="${DISC_INFO[iso_basename]}"
    if [[ -n "$basename" ]]; then
        echo "$basename"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_set_temp_pathname
# ---------------------------------------------------------------------------
# Funktion.: Setze temporären Arbeitsordner
# Parameter: $1 = temp_pathname (vollständiger Pfad)
# Rückgabe.: 0
# ===========================================================================
discinfo_set_temp_pathname() {
    local pathname="$1"
    DISC_INFO[temp_pathname]="$pathname"
    log_debug "discinfo_set_temp_pathname: '$pathname'"
    return 0
}

# ===========================================================================
# discinfo_get_temp_pathname
# ---------------------------------------------------------------------------
# Funktion.: Lese temporären Arbeitsordner
# Parameter: keine
# Ausgabe..: Temp-Pathname (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_temp_pathname() {
    local pathname="${DISC_INFO[temp_pathname]}"
    if [[ -n "$pathname" ]]; then
        echo "$pathname"
        return 0
    fi
    return 1
}

# ===========================================================================
# discinfo_get_estimated_size_mb
# ---------------------------------------------------------------------------
# Funktion.: Lese geschätzte ISO-Größe (mit Overhead)
# Parameter: keine
# Ausgabe..: Geschätzte Größe in MB (stdout)
# Rückgabe.: 0
# ===========================================================================
discinfo_get_estimated_size_mb() {
    echo "${DISC_INFO[estimated_size_mb]:-0}"
    return 0
}

# ===========================================================================
# init_disc_info
# ---------------------------------------------------------------------------
# Funktion.: Initialisiert ALLE technischen Disc-Informationen
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beschr...: Orchestriert alle Analyse-Schritte in der richtigen Reihenfolge:
#            1. discinfo_detect_type() → type, filesystem
#            2. discinfo_detect_label() → label
#            3. discinfo_detect_size() → size_sectors, size_mb
#            4. discinfo_detect_created_at() → created_at
#            5. discinfo_detect_id() → disc_id (benötigt type)
#            6. discinfo_detect_identifier() → disc_identifier (benötigt id, label, size_mb)
#            7. discinfo_detect_title() → title (benötigt label)
#            8. discinfo_detect_release_date() → release_date (benötigt created_at)
#            9. discinfo_detect_provider() → provider (benötigt type)
#            10. init_filenames() → iso_filename, temp_pathname, ...
#            11. Berechne estimated_size_mb (Disc-Größe + 10% Overhead)
#            
#            Diese Funktion wird in STATE_ANALYZING aufgerufen und stellt
#            sicher dass ALLE Disc-Informationen verfügbar sind bevor
#            der Kopiervorgang startet.
# ===========================================================================
init_disc_info() {
    log_debug "init_disc_info: Starte Disc-Analyse..."
    
    # 1. Disc-Typ erkennen (Audio-CD, DVD-Video, BD-Video, Data)
    #    Setzt auch filesystem als Seiteneffekt
    if ! discinfo_detect_type; then
        log_error "init_disc_info: Disc-Typ konnte nicht erkannt werden"
        return 1
    fi
    log_debug "init_disc_info: Disc-Typ = $(discinfo_get_type), Filesystem = $(discinfo_get_filesystem)"
    
    # 2. Label extrahieren (außer für Audio-CDs - wird in copy_audio_cd() gesetzt)
    local disc_type
    disc_type=$(discinfo_get_type)
    if [[ "$disc_type" != "audio-cd" ]]; then
        if ! discinfo_detect_label; then
            log_error "init_disc_info: Disc-Label konnte nicht extrahiert werden"
            return 1
        fi
        log_debug "init_disc_info: Disc-Label = $(discinfo_get_label)"
    else
        log_debug "init_disc_info: Audio-CD - Label wird in copy_audio_cd() gesetzt"
    fi
    
    # 3. Größe ermitteln (kann 1 zurückgeben wenn keine Größe ermittelt wurde - das ist OK)
    discinfo_detect_size
    local size_mb
    size_mb=$(discinfo_get_size_mb)
    log_debug "init_disc_info: Disc-Größe = ${size_mb} MB ($(discinfo_get_size_sectors) Sektoren)"
    
    # 4. ISO-Erstellungsdatum ermitteln (für DVD/BD/Data)
    if [[ "$disc_type" != "audio-cd" ]]; then
        discinfo_detect_created_at
        log_debug "init_disc_info: ISO-Erstellungsdatum = $(discinfo_get_created_at)"
    fi
    
    # 5. Disc-ID ermitteln (UUID für DVD/BD/Data, wird für Audio-CD später gesetzt)
    if ! discinfo_detect_id; then
        log_debug "init_disc_info: Keine Disc-ID ermittelt (wird ggf. später gesetzt)"
    else
        log_debug "init_disc_info: Disc-ID = $(discinfo_get_id)"
    fi
    
    # 6. Interne Disc-Identifier berechnen (für Medium-Wechsel-Erkennung)
    #    Benötigt: disc_id, label, size_mb
    if ! discinfo_detect_identifier; then
        log_warning "init_disc_info: Disc-Identifier konnte nicht berechnet werden"
    else
        log_debug "init_disc_info: Disc-Identifier = $(discinfo_get_identifier)"
    fi
    
    # 7. Disc-Titel ermitteln (Fallback: Label)
    discinfo_detect_title
    log_debug "init_disc_info: Disc-Titel = $(discinfo_get_title)"
    
    # 8. Veröffentlichungsdatum ermitteln (Fallback: created_at oder aktuelles Datum)
    if [[ "$disc_type" != "audio-cd" ]]; then
        discinfo_detect_release_date
        log_debug "init_disc_info: Veröffentlichungsdatum = $(discinfo_get_release_date)"
    fi
    
    # 9. Metadaten-Provider ermitteln (basierend auf Disc-Typ)
    discinfo_detect_provider
    log_debug "init_disc_info: Metadaten-Provider = $(discinfo_get_provider)"
    
    # 10. Dateinamen generieren (nutzt type + label)
    # WICHTIG: Für Audio-CDs wird init_filenames() in copy_audio_cd() aufgerufen
    #          (nachdem Label von MusicBrainz geholt wurde)
    if [[ "$disc_type" != "audio-cd" ]]; then
        if ! init_filenames; then
            log_error "init_disc_info: Dateinamen konnten nicht generiert werden"
            return 1
        fi
        log_debug "init_disc_info: ISO-Dateiname = $(discinfo_get_iso_filename)"
    else
        log_debug "init_disc_info: Audio-CD - Dateinamen werden in copy_audio_cd() generiert"
    fi
    
    # 11. Geschätzte ISO-Größe berechnen (Disc-Größe + 10% Overhead)
    #     Overhead für: Cover-Bilder, NFO-Dateien, temporäre MP3s/WAVs,
    #                   ddrescue Mapfiles, Dateisystem-Metadaten
    local estimated_size=0
    if [[ $size_mb -gt 0 ]]; then
        estimated_size=$((size_mb + size_mb * 10 / 100))
    fi
    DISC_INFO[estimated_size_mb]=$estimated_size
    log_debug "init_disc_info: Geschätzte Größe (mit Overhead) = ${estimated_size} MB"
    
    # Setze Timestamp für Analyse-Abschluss
    DISC_INFO[analyzed_at]=$(date -Iseconds)
    
    log_debug "init_disc_info: Disc-Analyse erfolgreich abgeschlossen"
    return 0
}

# TODO: Ab hier ist das Modul noch nicht fertig implementiert!

# ===========================================================================
# DISC_DATA GETTER/SETTER - AUDIO-CD METADATA
# ===========================================================================

# Artist (Album-Artist / Haupt-Künstler)
discdata_get_artist() {
    echo "${DISC_DATA[artist]}"
}

discdata_set_artist() {
    DISC_DATA[artist]="$1"
    log_debug "discdata_set_artist: '$1'"
}

# Album-Name
discdata_get_album() {
    echo "${DISC_DATA[album]}"
}

discdata_set_album() {
    DISC_DATA[album]="$1"
    log_debug "discdata_set_album: '$1'"
}

# Original-Erscheinungsjahr
discdata_get_year() {
    echo "${DISC_DATA[year]}"
}

discdata_set_year() {
    DISC_DATA[year]="$1"
    log_debug "discdata_set_year: '$1'"
}

# Genre
discdata_get_genre() {
    echo "${DISC_DATA[genre]}"
}

discdata_set_genre() {
    DISC_DATA[genre]="$1"
    log_debug "discdata_set_genre: '$1'"
}

# Track-Anzahl
discdata_get_track_count() {
    echo "${DISC_DATA[track_count]}"
}

discdata_set_track_count() {
    DISC_DATA[track_count]="$1"
    log_debug "discdata_set_track_count: '$1'"
}

# Gesamtlaufzeit (Millisekunden)
discdata_get_duration() {
    echo "${DISC_DATA[duration]}"
}

discdata_set_duration() {
    DISC_DATA[duration]="$1"
    log_debug "discdata_set_duration: '$1'"
}

# Table of Contents (für MusicBrainz)
discdata_get_toc() {
    echo "${DISC_DATA[toc]}"
}

discdata_set_toc() {
    DISC_DATA[toc]="$1"
    log_debug "discdata_set_toc: '$1'"
}

# Original-Veröffentlichungsdatum
discdata_get_original_release_date() {
    echo "${DISC_DATA[original_release_date]}"
}

discdata_set_original_release_date() {
    DISC_DATA[original_release_date]="$1"
    log_debug "discdata_set_original_release_date: '$1'"
}

# Original-Produktionsland
discdata_get_original_country() {
    echo "${DISC_DATA[original_country]}"
}

discdata_set_original_country() {
    DISC_DATA[original_country]="$1"
    log_debug "discdata_set_original_country: '$1'"
}

# Original-Plattenlabel
discdata_get_original_label() {
    echo "${DISC_DATA[original_label]}"
}

discdata_set_original_label() {
    DISC_DATA[original_label]="$1"
    log_debug "discdata_set_original_label: '$1'"
}

# Composer (Album-Komponist)
discdata_get_composer() {
    echo "${DISC_DATA[composer]}"
}

discdata_set_composer() {
    DISC_DATA[composer]="$1"
    log_debug "discdata_set_composer: '$1'"
}

# Songwriter (Album-Texter)
discdata_get_songwriter() {
    echo "${DISC_DATA[songwriter]}"
}

discdata_set_songwriter() {
    DISC_DATA[songwriter]="$1"
    log_debug "discdata_set_songwriter: '$1'"
}

# Arranger (Album-Arrangeur)
discdata_get_arranger() {
    echo "${DISC_DATA[arranger]}"
}

discdata_set_arranger() {
    DISC_DATA[arranger]="$1"
    log_debug "discdata_set_arranger: '$1'"
}

# ============================================================================
# Alter Code für Rückwärtskompatibilität
# ============================================================================

# ===========================================================================
# get_disc_size
# ---------------------------------------------------------------------------
# Funktion.: DEPRECATED - Wrapper für discinfo_detect_size()
# Parameter: keine
# Rückgabe.: 0 = Größe ermittelt, 1 = Keine Größe verfügbar
# Beschr...: RÜCKWÄRTSKOMPATIBILITÄT - Bitte discinfo_detect_size() verwenden!
#            Ruft discinfo_detect_size() auf und setzt alte globale Variablen
# ===========================================================================
get_disc_size() {
    # Neue Funktion aufrufen
    local result
    discinfo_detect_size
    result=$?
    
    # Setze alte globale Variablen (DEPRECATED - nur für Rückwärtskompatibilität)
    disc_volume_size=$(discinfo_get_size_sectors)
    local size_mb=$(discinfo_get_size_mb)
    
    if [[ "$disc_volume_size" =~ ^[0-9]+$ ]] && [[ $disc_volume_size -gt 0 ]]; then
        disc_block_size=2048
        total_bytes=$((disc_volume_size * disc_block_size))
    else
        disc_block_size=""
        disc_volume_size=""
        total_bytes=0
    fi
    
    return $result
}

# ===========================================================================
# discinfo_get_container_type
# ---------------------------------------------------------------------------
# Funktion.: Lese Container-Typ
# Parameter: keine
# Ausgabe..: Container-Typ (stdout)
# Rückgabe.: 0
# Beschr...: Leitet Container-Typ aus globalen Variablen ab
# ===========================================================================
discinfo_get_container_type() {
    if [[ "${IS_CONTAINER:-false}" == "true" ]]; then
        echo "${CONTAINER_TYPE:-unknown}"
    else
        echo "none"
    fi
    return 0
}

# ===========================================================================
# discinfo_get_copy_method
# ---------------------------------------------------------------------------
# Funktion.: Lese Kopier-Methode
# Parameter: keine
# Ausgabe..: Kopier-Methode (stdout)
# Rückgabe.: 0
# ===========================================================================
discinfo_get_copy_method() {
    echo "${COPY_METHOD:-unknown}"
    return 0
}

# ===========================================================================
# detect_disc_type
# ---------------------------------------------------------------------------
# Funktion.: DEPRECATED - Wrapper für discinfo_detect_type()
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# Beschr...: RÜCKWÄRTSKOMPATIBILITÄT - Bitte discinfo_detect_type() verwenden!
#            Ruft discinfo_detect_type() auf
# ===========================================================================
detect_disc_type() {
    discinfo_detect_type
    return $?
}

# ===========================================================================
# get_volume_label
# ---------------------------------------------------------------------------
# Funktion.: DEPRECATED - Wrapper für discinfo_detect_label()
# Parameter: keine
# Ausgabe..: Label (stdout)
# Rückgabe.: 0
# Beschr...: RÜCKWÄRTSKOMPATIBILITÄT - Bitte discinfo_detect_label() verwenden!
#            Ruft discinfo_detect_label() auf und gibt Label zurück
# ===========================================================================
get_volume_label() {
    discinfo_detect_label
    discinfo_get_label
    return 0
}

# ===========================================================================
# get_disc_label
# ---------------------------------------------------------------------------
# Funktion.: DEPRECATED - Wrapper für discinfo_detect_label()
# Parameter: keine
# Rückgabe.: 0
# Beschr...: RÜCKWÄRTSKOMPATIBILITÄT - Bitte discinfo_detect_label() verwenden!
#            Ruft discinfo_detect_label() auf
# ===========================================================================
get_disc_label() {
    discinfo_detect_label
    return $?
}
