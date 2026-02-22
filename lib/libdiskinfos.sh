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
# Version: 1.3.0
# Last Change: 2026-02-07
# =============================================================================

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

# ===========================================================================
# diskinfos_check_dependencies
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
diskinfos_check_dependencies() {
    # Manifest-basierte Abhängigkeitsprüfung (Tools, Dateien, Ordner)
    integrity_check_module_dependencies "diskinfos" || return 1
    
    # Keine modul-spezifische Initialisierung nötig
    
    return 0
}

# ===========================================================================
# Datenstruktur für Disc-Informationen
# ===========================================================================
# DISC TYPE CONSTANTS
readonly DISC_TYPE_AUDIO_CD="audio-cd"
readonly DISC_TYPE_CD_ROM="cd-rom"
readonly DISC_TYPE_DVD_VIDEO="dvd-video"
readonly DISC_TYPE_DVD_ROM="dvd-rom"
readonly DISC_TYPE_BD_VIDEO="bd-video"
readonly DISC_TYPE_BD_ROM="bd-rom"
readonly DISC_TYPE_DATA="data"
readonly DISC_TYPE_UNKNOWN="unknown"
# DISC_INFO: Metadaten der PHYSISCHEN Disc-Veröffentlichung
#   - Wann/Wo/Von wem wurde DIESE Disc veröffentlicht?
#   - Wichtig für regionale Releases (DE/GB/US) und Label-Zuordnung
#   - Beispiel: Deutsche DVD eines UK-Films → country="DE", aber production_country="GB"
#   - Beispiel: Sampler "Bravo Hits 2021" → release_date="2021-03", aber track.1.year="1989"
declare -A DISC_INFO=(
    # ========== Technische Basis-Informationen ==========
    ["disc_id"]=""          # Provider-ID: MusicBrainz DiscID (Audio-CD) / UUID (DVD/BD/Data)
    ["disc_identifier"]=""  # Interne ID für Medium-Wechsel-Erkennung (UUID:LABEL:SIZE_MB)
    ["label"]=""            # Volume-Label (aus Dateisystem)
    ["type"]=""             # Disc-Typ: audio-cd, cd-rom, dvd-video, dvd-rom, bd-video, bd-rom, data
    ["size_mb"]=0           # Größe in MB (gerundet)
    ["size_sectors"]=0      # Größe in Sektoren (präzise)
    ["block_size"]=2048     # Blockgröße in Bytes (Standard: 2048 für optische Medien)
    ["estimated_size_mb"]=0 # Geschätzte Größe in MB (für Audio-CDs basierend auf TOC)
    ["filesystem"]=""       # Dateisystem: iso9660, udf, mixed, unknown
    ["created_at"]=""       # ISO-Erstellungsdatum (YYYY-MM-DDTHH:MM:SSZ)
    ["copy_method"]=""      # Verwendete Kopiermethode: ddrescue, dd, cdparanoia, dvdbackup, makemkvcon
    
    # ========== Physische Disc-Veröffentlichung ==========
    ["title"]=""            # Disc-Titel (kann von Album/Film-Titel abweichen bei Compilations)
    ["release_date"]=""     # Veröffentlichungsdatum DIESER Disc (YYYY-MM-DD)
    ["country"]=""          # Veröffentlichungsland DIESER Disc (DE, GB, US, EU)
    ["publisher"]=""        # Publisher/Label DIESER Disc (z.B. Mercury Ltd., Warner Bros. Germany)
    
    # ========== Metadaten-Provider ==========
    ["provider"]=""         # Metadaten-Anbieter: musicbrainz, tmdb, manual, none
    ["provider_id"]=""      # ID des Mediums beim Metadaten-Anbieter
    ["cover_url"]=""        # URL zum Cover-Bild (für Audio-CD/DVD/Blu-ray)
    ["cover_path"]=""       # Lokaler Pfad zum Cover-Bild (für Audio-CD/DVD/Blu-ray)
    
    # ========== Dateinamen (generiert nach Metadata-Auswahl) ==========
    ["iso_basename"]=""     # Nur Dateiname der ISO (ohne Pfad)
    ["iso_filename"]=""     # Vollständiger Pfad zur ISO-Datei
    ["md5_filename"]=""     # Vollständiger Pfad zur MD5-Checksummen-Datei
    ["log_filename"]=""     # Vollständiger Pfad zur Log-Datei
    ["temp_pathname"]=""    # Temporäres Arbeitsverzeichnis für Copy-Vorgang
)

# DISC_DATA: Metadaten des INHALTS
#   - Informationen über Inhalt (nicht über die physische Disc)
declare -A DISC_DATA=(
    # ========== DATA-DISC ==========
    ["description"]=""         # Freitext-Beschreibung des Inhalts
    ["backup_date"]=""         # Backup-Datum (YYYY-MM-DD)
)

# ============================================================================
# GETTER/SETTER FUNKTIONEN FÜR DISC_INFO
# ============================================================================
# Private Variablen und Hilfsfunktionen für die Getter/Setter-Methoden
_DISCINFO_BLKID_PATH=""
_DISCINFO_ISOINFO_PATH=""
_DISCINFO_BLOCKDEV_PATH=""

# ===========================================================================
# _discinfo_create_json
# ---------------------------------------------------------------------------
# Funktion.: Hilfsfunktion zur Erstellung eines JSON-Objekts aus einem Array
# Parameter: $1 = Name des assoziativen Arrays (z.B. "DISC_INFO")
# .........  $2 = JSON-Pfad/Key (optional, z.B. "disc_info" für Zweig)
# Ausgabe..: JSON-String (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Array existiert nicht
# ===========================================================================
_discinfo_create_json() {
    #-- Parameter übernehmen ------------------------------------------------
    local array_name="$1"
    local json_key="${2:-}"
    local -n array_ref="$array_name"
    
    #-- Validierung: Prüfe ob Array existiert -------------------------------
    if [[ ! -v "$array_name" ]]; then
        log_error "_discinfo_create_json: Array '$array_name' existiert nicht"
        echo "{}"
        return 1
    fi

    #-- Baue JSON-String aus Array-Werten -----------------------------------    
    local json=""
    local first=true
    
    #-- Baue inneres Objekt -------------------------------------------------
    local inner_json="{"
    for key in "${!array_ref[@]}"; do
        local value="${array_ref[$key]}"
        
        # Komma vor jedem Element außer dem ersten
        [[ "$first" == false ]] && inner_json+="," || first=false
        
        # Prüfe ob Wert numerisch ist
        if [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
            inner_json+="\"$key\":$value"
        else
            # Escape Anführungszeichen und Backslashes
            value="${value//\\/\\\\}"
            value="${value//\"/\\\"}"
            inner_json+="\"$key\":\"$value\""
        fi
    done
    inner_json+="}"
    
    #-- Wrapper hinzufügen wenn Key angegeben -------------------------------
    if [[ -n "$json_key" ]]; then
        json="{\"$json_key\":$inner_json}"
    else
        json="$inner_json"
    fi
    
    #-- Rückgabe des JSON-Strings -------------------------------------------
    echo "$json"
    return 0
}

# ===========================================================================
# discinfo_reset
# ---------------------------------------------------------------------------
# Funktion.: Initialisiere/Leere DISC_INFO Array
# Parameter: keine
# Rückgabe.: 0
# Beschr...: Setzt alle Felder auf Standardwerte zurück
# ===========================================================================
discinfo_reset() {
    #-- Technische Basis-Informationen --------------------------------------
    DISC_INFO[disc_id]=""
    DISC_INFO[disc_identifier]=""
    DISC_INFO[label]=""
    DISC_INFO[type]=""
    DISC_INFO[size_mb]=0
    DISC_INFO[size_sectors]=0
    DISC_INFO[block_size]=2048
    DISC_INFO[estimated_size_mb]=0
    DISC_INFO[filesystem]=""
    DISC_INFO[created_at]=""
    DISC_INFO[copy_method]=""

    #-- Physische Disc-Veröffentlichung -------------------------------------
    DISC_INFO[title]=""
    DISC_INFO[release_date]=""
    DISC_INFO[country]=""
    DISC_INFO[publisher]=""

    #-- Metadaten-Provider --------------------------------------------------
    DISC_INFO[provider]=""
    DISC_INFO[provider_id]=""
    DISC_INFO[cover_url]=""
    DISC_INFO[cover_path]=""

    #-- Dateinamen (generiert nach Metadata-Auswahl) ------------------------
    DISC_INFO[iso_filename]=""
    DISC_INFO[md5_filename]=""
    DISC_INFO[log_filename]=""
    DISC_INFO[iso_basename]=""
    DISC_INFO[temp_pathname]=""
    
    #-- Schreiben nach JSON & Loggen der Initialisierung --------------------
    api_set_section_json "discinfos" ".disc_info" "$(_discinfo_create_json "DISC_INFO" "disc_info")"
    log_debug "discinfo_reset: $MSG_DEBUG_DISCINFO_INIT"
    return 0
}

# ===========================================================================
# discinfo_get_id
# ---------------------------------------------------------------------------
# Funktion.: Lese Disc-ID (UUID oder MusicBrainz DiscID)
# Parameter: keine
# Ausgabe..: Disc-ID
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_id() {
    #-- Array Wert lesen ----------------------------------------------------
    local uuid="${DISC_INFO[disc_id]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$uuid" ]]; then
        log_debug "$MSG_DEBUG_GET_ID: '$uuid'"
        echo "$uuid"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_ID: $MSG_DEBUG_GET_ID_EMPTY"
    echo ""
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
    local old_value="${DISC_INFO[disc_id]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$uuid" ]]; then
        uuid=$(discinfo_detect_id)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$uuid" ]]; then
        log_debug "$MSG_DEBUG_SET_ID_EMPTY"
        return 1
    fi
    
    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ------
    DISC_INFO[disc_id]="$uuid"
    log_debug "$MSG_DEBUG_SET_ID = '${DISC_INFO[disc_id]}'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$uuid" ]]; then
        log_debug "$MSG_DEBUG_SET_ID_CHANGED = '$old_value' → '$uuid'"
        api_set_value_json "discinfos" "disc_id" "${DISC_INFO[disc_id]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_detect_id()
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt Disc-ID (Provider-spezifisch: UUID)
# Parameter: keine
# Ausgabe..: UUID (stdout) oder leerer String
# Rückgabe.: 0 = Erfolg
# ===========================================================================
discinfo_detect_id() {
    #-- Ermittle erkannten Disc-Typ -----------------------------------------
    local disc_type=$(discinfo_get_type)
    log_debug "$MSG_DEBUG_DETECT_ID_TYPE = '$disc_type'"
    
    #-- Audio-CDs: DiscID wird von copy_audio_cd() gesetzt (via cd-discid) --
    if [[ "$disc_type" == "audio-cd" ]]; then
        log_debug "$MSG_DEBUG_DETECT_ID_AUDIO"
        return 0
    fi
    
    #-- DVD/BD/Data: Ermittle UUID mit blkid --------------------------------
    local uuid=""
    
    #-- blkid Pfad ermitteln und wenn vorhanden verwenden -------------------
    local blkid_cmd=$(_systeminfo_get_blkid_path)
    if [[ -n "$blkid_cmd" ]]; then
        local blkid_output
        blkid_output=$($blkid_cmd -p "$CD_DEVICE" 2>/dev/null)
        
        if [[ -n "$blkid_output" ]]; then
            uuid=$(echo "$blkid_output" | grep -oP 'UUID="?\K[^"]+' 2>/dev/null || echo "")
        fi
    fi
    
    #-- Setze UUID ----------------------------------------------------------
    echo "$uuid"
    return $?
}

# ===========================================================================
# discinfo_get_identifier
# ---------------------------------------------------------------------------
# Funktion.: Liest interne Disc-Identifier (für Medium-Wechsel-Erkennung)
# Parameter: keine
# Ausgabe..: Disc-Identifier (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_identifier() {    
    #-- Array Wert lesen ----------------------------------------------------
    local identifier="${DISC_INFO[disc_identifier]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$identifier" ]]; then
        log_debug "$MSG_DEBUG_GET_IDENTIFIER: '$identifier'"
        echo "$identifier"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_IDENTIFIER: $MSG_DEBUG_GET_IDENTIFIER_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_identifier
# ---------------------------------------------------------------------------
# Funktion.: Setzt interne Disc-Identifier für Medium-Wechsel-Erkennung 
# .........  (Format: UUID:LABEL:SIZE_MB)
# Parameter: $1 = identifier (Format: UUID:LABEL:SIZE_MB)
# Rückgabe.: 0 = Erfolg, 1 = Identifier leer
# Beschr...: Auto-Detection wenn kein Identifier übergeben wird,
# .........  Setzt DISC_INFO[disc_identifier]
# ===========================================================================
discinfo_set_identifier() {
    #-- Parameter übernehmen ------------------------------------------------
    local identifier="$1"
    local old_value="${DISC_INFO[disc_identifier]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$identifier" ]]; then
        identifier=$(discinfo_detect_identifier)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$identifier" ]]; then
        log_debug "$MSG_DEBUG_SET_IDENTIFIER_EMPTY"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[disc_identifier]="$identifier"
    log_debug "$MSG_DEBUG_SET_IDENTIFIER = '$identifier'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$identifier" ]]; then
        log_debug "$MSG_DEBUG_SET_IDENTIFIER_CHANGED = '$old_value' → '$identifier'"
        api_set_value_json "discinfos" "disc_identifier" "${DISC_INFO[disc_identifier]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_detect_identifier
# ---------------------------------------------------------------------------
# Funktion.: Berechne interne Disc-Identifier für Medium-Wechsel-Erkennung 
# .........  aus den Werten DISC_INFO[disc_id], DISC_INFO[label] und 
# .........  DISC_INFO[size_mb] (Format: UUID:LABEL:SIZE_MB)
# Parameter: keine
# Ausgabe..: Disc-Identifier (stdout) im Format UUID:LABEL:SIZE_MB
# Rückgabe.: 0 = Erfolg, 1 = Fehler (wenn Getter fehlschlagen)
# ===========================================================================
discinfo_detect_identifier() {
    #-- UUID aus DISC_INFO[disc_id] mit Getter lesen ------------------------
    local uuid=$(discinfo_get_id) || return 1
     
    #-- Label aus DISC_INFO[label] mit Getter lesen -------------------------
    local label=$(discinfo_get_label) || return 1
    
    #-- Disk-Größe aus DISC_INFO[size_mb] mit Getter lesen ------------------
    local size_mb=$(discinfo_get_size_mb) || return 1
    
    #-- Baue Identifier: UUID:LABEL:SIZE_MB ---------------------------------
    echo "${uuid}:${label}:${size_mb}"
    return 0
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
    #-- Array Wert lesen ----------------------------------------------------
    local label="${DISC_INFO[label]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$label" ]]; then
        echo "$label"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_LABEL: $MSG_DEBUG_GET_LABEL_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_label
# ---------------------------------------------------------------------------
# Funktion.: Setze Disc-Label mit Normalisierung
# Parameter: $1 = label
# Rückgabe.: 0 = Erfolg, 1 = Label ist leer
# Beschr...: Auto-Detection wenn kein Label übergeben wird
# ===========================================================================
discinfo_set_label() {
    #-- Parameter übernehmen ------------------------------------------------
    local label="$1"
    local old_value="${DISC_INFO[label]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$label" ]]; then
        label=$(discinfo_detect_label)
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$label" ]]; then
        log_warning "$MSG_WARNING_EMPTY_LABEL"
        return 1
    fi
    
    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[label]="$label"
    log_debug "$MSG_DEBUG_SET_LABEL: '$label'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$label" ]]; then
        log_debug "$MSG_DEBUG_SET_LABEL_CHANGED: '$old_value' → '$label'"
        api_set_value_json "discinfos" "label" "${DISC_INFO[label]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_detect_label
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Volume-Label von Disc
# Parameter: keine
# Ausgabe..: Label (stdout)
# Rückgabe.: 0 = Erfolg
# ===========================================================================
discinfo_detect_label() {
    #-- Ermittle Label mit blkid oder isoinfo -------------------------------
    local label=""
    
    #-- blkid Pfad ermitteln und wenn vorhanden verwenden -------------------
    local blkid_cmd=$(_systeminfo_get_blkid_path)
    if [[ -n "$blkid_cmd" ]]; then
        label=$($blkid_cmd "$CD_DEVICE" 2>/dev/null | grep -o 'LABEL="[^"]*"' | cut -d'"' -f2)
    fi
    
    #-- Fallback: Versuche Volume ID mit isoinfo zu lesen -------------------
    local isoinfo_cmd=$(_systeminfo_get_isoinfo_path)
    if [[ -n "$isoinfo_cmd" ]]; then
        label=$($isoinfo_cmd -d -i "$CD_DEVICE" 2>/dev/null | grep "Volume id:" | sed 's/Volume id: //' | xargs)
    fi

    #-- Fallback: Datum verwenden, wenn kein Label gefunden -----------------
    if [[ -z "$label" ]] || [[ "$label" =~ ^[[:space:]]*$ ]]; then
        label="Disc_$(date '+%Y%m%d_%H%M%S')"
    fi
    
    #-- Normalisierung ------------------------------------------------------
    label=$(echo "$label" | tr '[:upper:]' '[:lower:]')
    label=$(sanitize_filename "$label")
    
    #-- Rückgabe des ermittelten Labels -------------------------------------
    echo "$label"
    return 0
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
    #-- Array Wert lesen ----------------------------------------------------
    local type="${DISC_INFO[type]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$type" ]]; then
        log_debug "$MSG_DEBUG_GET_TYPE: '$type'"
        echo "$type"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_TYPE: $MSG_DEBUG_GET_TYPE_EMPTY"
    echo ""
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
    #-- Parameter übernehmen ------------------------------------------------
    local type="$1"
    local old_value="${DISC_INFO[type]}"
    
    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$type" ]]; then
        type=$(discinfo_detect_type)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$type" ]]; then
        log_debug "$MSG_DEBUG_SET_TYPE_EMPTY"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    case "$type" in
        "$DISC_TYPE_AUDIO_CD"|"$DISC_TYPE_CD_ROM"|"$DISC_TYPE_DVD_VIDEO"|\
        "$DISC_TYPE_DVD_ROM"|"$DISC_TYPE_BD_VIDEO"|"$DISC_TYPE_BD_ROM"|\
        "$DISC_TYPE_DATA")
            DISC_INFO[type]="$type"
            log_debug "$MSG_DEBUG_SET_TYPE: '$type'"
            if [[ -n "$old_value" ]] && [[ "$old_value" != "$type" ]]; then
                log_debug "$MSG_DEBUG_SET_TYPE_CHANGED: '$old_value' → '$type'"
                api_set_value_json "discinfos" "type" "${DISC_INFO[type]}"
            fi
            return 0
            ;;
        *)
            DISC_INFO[type]="$DISC_TYPE_UNKNOWN"
            api_set_value_json "discinfos" "type" "$DISC_TYPE_UNKNOWN"
            log_error "discinfo_set_type: $MSG_ERROR_INVALID_DISC_TYPE '$DISC_TYPE_UNKNOWN'"
            return 1
            ;;
    esac
}

# ===========================================================================
# discinfo_detect_type
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Disc-Typ (Audio-CD, DVD-Video, BD-Video, etc.)
# Parameter: keine
# Ausgabe..: Disc-Typ (stdout)
# Rückgabe.: 0 = Erfolg
# ===========================================================================
discinfo_detect_type() {
    local detected_type="$DISC_TYPE_UNKNOWN"
    local isoinfo_cmd=$(_systeminfo_get_isoinfo_path)

    #-- 1. SPEZIFISCHSTE Prüfung: Video-DVD (VIDEO_TS) ----------------------
    if [[ -n "$isoinfo_cmd" ]]; then
        local iso_listing
        iso_listing=$($isoinfo_cmd -l -i "$CD_DEVICE" 2>/dev/null)
        
        if echo "$iso_listing" | grep -q "Directory listing of /VIDEO_TS"; then
            echo "$DISC_TYPE_DVD_VIDEO"
            return 0
        fi
        
        if echo "$iso_listing" | grep -q "Directory listing of /BDMV"; then
            echo "$DISC_TYPE_BD_VIDEO"
            return 0
        fi
    fi

    #-- 2. Fallback: Audio-CD (kein Dateisystem) ----------------------------
    local iso_info=$($isoinfo_cmd -d -i "$CD_DEVICE" 2>/dev/null)
    if [[ -z "$iso_info" ]]; then
        echo "$DISC_TYPE_AUDIO_CD"
        return 0
    fi
    
    #-- 3. Fallback: Größenbasierte Erkennung -------------------------------
    local volume_size="${DISC_INFO[size_sectors]}"
    if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
        local size_mb=$((volume_size * 2048 / 1024 / 1024))
        
        if [[ $size_mb -lt 900 ]]; then
            detected_type="$DISC_TYPE_CD_ROM"
        elif [[ $size_mb -lt 9000 ]]; then
            detected_type="$DISC_TYPE_DVD_ROM"
        else
            #-- Für bd-video/bd-rom Unterscheidung: Filesystem separat prüfen
            local fs_type=$(discinfo_detect_filesystem)  
            if [[ "$fs_type" == "udf" ]]; then
                detected_type="$DISC_TYPE_BD_VIDEO"
            else
                detected_type="$DISC_TYPE_BD_ROM"
            fi
        fi
    else
        detected_type="$DISC_TYPE_DATA"
    fi
    
    #-- Rückgabe des ermittelten Typs ---------------------------------------
    echo "$detected_type"
    return 0
}

# ===========================================================================
# discinfo_get_size_mb
# ---------------------------------------------------------------------------
# Funktion.: Lese Disc-Größe in MB
# Parameter: keine
# Ausgabe..: Größe in MB 
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer oder ungültig
# ===========================================================================
discinfo_get_size_mb() {
    #-- Array Wert lesen ----------------------------------------------------
    local size_mb="${DISC_INFO[size_mb]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$size_mb" ]] && [[ "$size_mb" =~ ^[0-9]+$ ]]; then
        log_debug "$MSG_DEBUG_GET_SIZE_MB: '$size_mb MB'"
        echo "$size_mb"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_SIZE_MB: $MSG_DEBUG_GET_SIZE_MB_EMPTY"
    echo "0"
    return 1
}

# ===========================================================================
# discinfo_set_size_mb
# ---------------------------------------------------------------------------
# Funktion.: Setze Disc-Größe (in MB) direkt
# Parameter: $1 = size_mb (Größe in MB)
# Rückgabe.: 0 = Erfolg, 1 = Ungültige Größe
# ===========================================================================
discinfo_set_size_mb() {
    local size_mb="$1"
    local old_value="${DISC_INFO[size_mb]}"
    
    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$size_mb" ]]; then
        size_mb=$(discinfo_detect_size_mb)
    fi
    
    #-- Validierung ---------------------------------------------------------
    if [[ ! "$size_mb" =~ ^[0-9]+$ ]]; then
        log_warning "$MSG_WARNING_INVALID_SIZE_MB '$size_mb'"
        return 1
    fi
    
    #-- Wert setzen und loggen ----------------------------------------------
    DISC_INFO[size_mb]="$size_mb"
    log_debug "$MSG_DEBUG_SET_SIZE_MB = $size_mb MB"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$size_mb" ]]; then
        log_debug "$MSG_DEBUG_SET_SIZE_MB_CHANGED = '$old_value' → '$size_mb'"
        api_set_value_json "discinfos" "size_mb" "${DISC_INFO[size_mb]}"
    fi    
    return 0
}

# ===========================================================================
# discinfo_detect_size_mb
# ---------------------------------------------------------------------------
# Funktion.: Berechne Disc-Größe in MB aus size_sectors * block_size
# Parameter: keine
# Ausgabe..: Größe in MB (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler (keine gültigen Sektoren)
# Beschr...: Berechnet aus vorhandenen size_sectors und block_size
# ===========================================================================
discinfo_detect_size_mb() {
    local size_sectors="${DISC_INFO[size_sectors]}"
    local block_size="${DISC_INFO[block_size]:-2048}"
    
    #-- Validierung ---------------------------------------------------------
    if [[ ! "$size_sectors" =~ ^[0-9]+$ ]] || [[ $size_sectors -eq 0 ]]; then
        log_debug "keine gültigen Sektoren verfügbar"
        echo "0"
        return 1
    fi
    
    #-- Berechnung: (sectors * block_size) / 1024 / 1024 -------------------
    local size_bytes=$((size_sectors * block_size))
    local size_mb=$((size_bytes / 1024 / 1024))
    
    log_debug "$size_sectors sectors @ $block_size bytes = $size_mb MB"
    echo "$size_mb"
    return 0
}   

# ===========================================================================
# discinfo_get_size_sectors
# ---------------------------------------------------------------------------
# Funktion.: Lese Disc-Größe in Sektoren
# Parameter: keine
# Ausgabe..: Anzahl Sektoren
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer oder ungültig
# ===========================================================================
discinfo_get_size_sectors() {
    #-- Array Wert lesen ----------------------------------------------------
    local size_sectors="${DISC_INFO[size_sectors]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$size_sectors" ]] && [[ "$size_sectors" =~ ^[0-9]+$ ]]; then
        log_debug "$MSG_DEBUG_GET_SIZE_SECTORS: '$size_sectors sectors'"
        echo "$size_sectors"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_SIZE_SECTORS: $MSG_DEBUG_GET_SIZE_SECTORS_EMPTY"
    echo "0"
    return 1
}

# ===========================================================================
# discinfo_set_size_sectors
# ---------------------------------------------------------------------------
# Funktion.: Setze Disc-Größe (in Sektoren) und berechne size_mb
# Parameter: $1 = size_sectors (Anzahl Blöcke/Sektoren)
#            $2 = block_size (optional, default: aktueller Wert oder 2048)
# Rückgabe.: 0 = Erfolg, 1 = Ungültige Sektoren
# Beschr...: Setzt size_sectors und berechnet automatisch size_mb
# ===========================================================================
discinfo_set_size_sectors() {
    local size_sectors="$1"
    local block_size="${2:-${DISC_INFO[block_size]:-2048}}"
    local old_value_sectors="${DISC_INFO[size_sectors]}"
    local old_value_mb="${DISC_INFO[size_mb]}"
    
    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$size_sectors" ]]; then
        size_sectors=$(discinfo_detect_size_sectors)
    fi
    
    #-- Validierung ---------------------------------------------------------
    if [[ ! "$size_sectors" =~ ^[0-9]+$ ]]; then
        log_warning "discinfo_set_size_sectors: $MSG_WARNING_INVALID_SECTORS '$size_sectors'"
        return 1
    fi
    
    #-- Werte setzen --------------------------------------------------------
    DISC_INFO[size_sectors]="$size_sectors"
    DISC_INFO[block_size]="$block_size"
    
    #-- MB berechnen: (size_sectors * block_size) / 1024 / 1024 -------------
    local size_bytes=$((size_sectors * block_size))
    local size_mb=$((size_bytes / 1024 / 1024))
    DISC_INFO[size_mb]="$size_mb"
    
    #-- Logging -------------------------------------------------------------
    log_debug "$MSG_DEBUG_SET_SIZE_SECTORS: $size_sectors sectors @ $block_size bytes = $size_mb MB"
    
    if [[ -n "$old_value_sectors" ]] && [[ "$old_value_sectors" != "$size_sectors" ]]; then
        log_debug "$MSG_DEBUG_SET_SIZE_SECTORS_CHANGED: '$old_value_sectors' → '$size_sectors'"
        api_set_value_json "discinfos" "size_sectors" "${DISC_INFO[size_sectors]}"
        api_set_value_json "discinfos" "size_mb" "${DISC_INFO[size_mb]}"
    fi
    
    return 0
}

# ===========================================================================
# discinfo_detect_size_sectors
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Volume-Größe (in Sektoren) mit isoinfo
# Parameter: keine
# Ausgabe..: Anzahl Sektoren (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Nicht ermittelbar
# Beschr...: Liest "Volume size is: XXXXX" aus isoinfo -d Ausgabe
# ===========================================================================
discinfo_detect_size_sectors() {
    local volume_size=0
    
    #-- isoinfo Pfad ermitteln und wenn vorhanden verwenden -----------------
    local isoinfo_cmd=$(_systeminfo_get_isoinfo_path)
    if [[ -n "$isoinfo_cmd" ]]; then
        local isoinfo_output=$($isoinfo_cmd -d -i "$CD_DEVICE" 2>/dev/null)
        
        #-- Lese "Volume size is: XXXXX" ------------------------------------
        volume_size=$(echo "$isoinfo_output" | grep "Volume size is:" | awk '{print $4}')
        
        if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
            log_debug "$volume_size sectors"
            echo "$volume_size"
            return 0
        fi
    fi
    
    #-- Kein Wert gefunden --------------------------------------------------
    log_debug "keine Größe ermittelbar"
    echo "0"
    return 1
}

# ===========================================================================
# discinfo_get_block_size
# ---------------------------------------------------------------------------
# Funktion.: Lese Block-Größe
# Parameter: keine
# Ausgabe..: Block-Größe in Bytes (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer oder ungültig
# ===========================================================================
discinfo_get_block_size() {
    #-- Array Wert lesen ----------------------------------------------------
    local block_size="${DISC_INFO[block_size]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$block_size" ]] && [[ "$block_size" =~ ^[0-9]+$ ]]; then
        log_debug "$MSG_DEBUG_GET_BLOCK_SIZE: '$block_size bytes'"
        echo "$block_size"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_BLOCK_SIZE: $MSG_DEBUG_GET_BLOCK_SIZE_EMPTY"
    echo "2048"
    return 1
}

# ===========================================================================
# discinfo_set_block_size
# ---------------------------------------------------------------------------
# Funktion.: Setze Block-Größe und berechne size_mb neu
# Parameter: $1 = block_size (Blockgröße in Bytes, default: 2048)
# Rückgabe.: 0 = Erfolg, 1 = Ungültige Blockgröße
# Beschr...: Setzt block_size und berechnet size_mb aus size_sectors neu
# ===========================================================================
discinfo_set_block_size() {
    local block_size="${1:-2048}"
    local old_value="${DISC_INFO[block_size]}"
    
    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$block_size" ]]; then
        block_size=$(discinfo_detect_block_size)
    fi
    
    #-- Validierung ---------------------------------------------------------
    if [[ ! "$block_size" =~ ^[0-9]+$ ]]; then
        log_warning "ungültige Blockgröße '$block_size'"
        return 1
    fi
    
    #-- Wert setzen ---------------------------------------------------------
    DISC_INFO[block_size]="$block_size"
    
    #-- MB neu berechnen (falls size_sectors vorhanden) ---------------------
    local size_sectors="${DISC_INFO[size_sectors]}"
    if [[ -n "$size_sectors" ]] && [[ "$size_sectors" =~ ^[0-9]+$ ]] && [[ $size_sectors -gt 0 ]]; then
        local size_bytes=$((size_sectors * block_size))
        local size_mb=$((size_bytes / 1024 / 1024))
        DISC_INFO[size_mb]="$size_mb"
        log_debug "$MSG_DEBUG_SET_BLOCK_SIZE: $block_size bytes (size_mb neu berechnet: $size_mb MB)"
    else
        log_debug "$MSG_DEBUG_SET_BLOCK_SIZE: $block_size bytes"
    fi
    
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$block_size" ]]; then
        log_debug "$MSG_DEBUG_SET_BLOCK_SIZE_CHANGED: '$old_value' → '$block_size'"
        api_set_value_json "discinfos" "block_size" "${DISC_INFO[block_size]}"
    fi
    
    return 0
}

# ===========================================================================
# discinfo_detect_block_size
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Block-Größe mit isoinfo
# Parameter: keine
# Ausgabe..: Block-Größe in Bytes (stdout), default: 2048
# Rückgabe.: 0 = Erfolg
# Beschr...: Liest "Logical block size is: XXXX" aus isoinfo -d Ausgabe
# ===========================================================================
discinfo_detect_block_size() {
    local block_size=2048  # Fallback für optische Medien
    
    #-- isoinfo Pfad ermitteln und wenn vorhanden verwenden -----------------
    local isoinfo_cmd=$(_systeminfo_get_isoinfo_path)
    if [[ -n "$isoinfo_cmd" ]]; then
        local isoinfo_output=$($isoinfo_cmd -d -i "$CD_DEVICE" 2>/dev/null)
        
        #-- Lese "Logical block size is: XXXX" ------------------------------
        local detected_block_size
        detected_block_size=$(echo "$isoinfo_output" | grep -i "Logical block size is:" | awk '{print $5}')
        
        if [[ -n "$detected_block_size" ]] && [[ "$detected_block_size" =~ ^[0-9]+$ ]]; then
            block_size=$detected_block_size
            log_debug "discinfo_detect_block_size: $block_size bytes (erkannt)"
        else
            log_debug "discinfo_detect_block_size: $block_size bytes (Fallback)"
        fi
    else
        log_debug "discinfo_detect_block_size: $block_size bytes (Fallback, isoinfo nicht verfügbar)"
    fi
    
    echo "$block_size"
    return 0
}

# ===========================================================================
# discinfo_get_estimated_size_mb
# ---------------------------------------------------------------------------
# Funktion.: Lese geschätzte ISO-Größe (mit Overhead)
# Parameter: keine
# Ausgabe..: Geschätzte Größe in MB 
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer oder ungültig
# ===========================================================================
discinfo_get_estimated_size_mb() {
    #-- Array Wert lesen ----------------------------------------------------
    local estimated_size_mb="${DISC_INFO[estimated_size_mb]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$estimated_size_mb" ]] && [[ "$estimated_size_mb" =~ ^[0-9]+$ ]]; then
        log_debug "$MSG_DEBUG_GET_ESTIMATED_SIZE_MB: '$estimated_size_mb MB'"
        echo "$estimated_size_mb"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_ESTIMATED_SIZE_MB: $MSG_DEBUG_GET_ESTIMATED_SIZE_MB_EMPTY"
    echo "0"
    return 1
}

# ===========================================================================
# discinfo_set_estimated_size_mb
# ---------------------------------------------------------------------------
# Funktion.: Setze geschätzte ISO-Größe (mit Overhead)
# Parameter: $1 = estimated_size_mb (Größe in MB)
# Rückgabe.: 0 = Erfolg, 1 = Ungültige Größe
# ===========================================================================
discinfo_set_estimated_size_mb() {
    #-- Parameter übernehmen ------------------------------------------------
    local estimated_size_mb="$1"
    local old_value="${DISC_INFO[estimated_size_mb]}"
    
    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$estimated_size_mb" ]]; then
        estimated_size_mb=$(discinfo_detect_estimated_size_mb)
    fi
    
    #-- Validierung ---------------------------------------------------------
    if [[ ! "$estimated_size_mb" =~ ^[0-9]+$ ]]; then
        log_warning "$MSG_WARNING_INVALID_ESTIMATED_SIZE_MB '$estimated_size_mb'"
        return 1
    fi
    
    #-- Wert setzen und loggen ----------------------------------------------
    DISC_INFO[estimated_size_mb]="$estimated_size_mb"
    log_debug "$MSG_DEBUG_SET_ESTIMATED_SIZE_MB = $estimated_size_mb MB"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$estimated_size_mb" ]]; then
        log_debug "$MSG_DEBUG_SET_ESTIMATED_SIZE_MB_CHANGED = '$old_value' → '$estimated_size_mb'"
        api_set_value_json "discinfos" "estimated_size_mb" "${DISC_INFO[estimated_size_mb]}"
    fi    
    return 0

}

# ===========================================================================
# discinfo_detect_estimated_size_mb
# ---------------------------------------------------------------------------
# Funktion.: Berechne geschätzte ISO-Größe mit Overhead (size_mb + 10%)
# Parameter: keine
# Ausgabe..: Geschätzte Größe in MB (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler (size_mb nicht verfügbar)
# Beschr...: Berechnet als size_mb + 10% Overhead für ISO-Struktur
# ===========================================================================
discinfo_detect_estimated_size_mb() {
    #-- Lese size_mb mit Getter ---------------------------------------------
    local size_mb=$(discinfo_get_size_mb) || return 1

    #-- Berechnung: size_mb + 10% Overhead ----------------------------------
    local estimated_size_mb=$((size_mb + size_mb / 10))

    #-- Logging -------------------------------------------------------------
    log_debug "size_mb=$size_mb MB → estimated_size_mb=$estimated_size_mb MB (+10% Overhead)"
    echo "$estimated_size_mb"
    return 0
}

# ===========================================================================
# discinfo_get_filesystem
# ---------------------------------------------------------------------------
# Funktion.: Lese Dateisystem-Typ
# Parameter: keine
# Ausgabe..: Dateisystem (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_filesystem() {
    #-- Array Wert lesen ----------------------------------------------------
    local filesystem="${DISC_INFO[filesystem]:-unknown}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$filesystem" ]]; then
        log_debug "$MSG_DEBUG_GET_FILESYSTEM: '$filesystem'"
        echo "$filesystem"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_FILESYSTEM: $MSG_DEBUG_GET_FILESYSTEM_EMPTY"
    echo "unknown"
    return 1
}

# ===========================================================================
# discinfo_set_filesystem
# ---------------------------------------------------------------------------
# Funktion.: Setze Dateisystem-Typ
# Parameter: $1 = filesystem (z.B. iso9660, udf, mixed, unknown)
# Rückgabe.: 0 = Erfolg, 1 = Dateisystem leer
# Beschr...: Auto-Detection wenn kein Dateisystem übergeben wird
# ===========================================================================
discinfo_set_filesystem() {
    #-- Parameter übernehmen ------------------------------------------------
    local filesystem="$1"
    local old_value="${DISC_INFO[filesystem]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$filesystem" ]]; then
        filesystem=$(discinfo_detect_filesystem)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$filesystem" ]]; then
        log_debug "$MSG_DEBUG_SET_FILESYSTEM_EMPTY"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[filesystem]="$filesystem"
    log_debug "$MSG_DEBUG_SET_FILESYSTEM: '${DISC_INFO[filesystem]}'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$filesystem" ]]; then
        log_debug "$MSG_DEBUG_SET_FILESYSTEM_CHANGED: '$old_value' → '$filesystem'"
        api_set_value_json "discinfos" "filesystem" "${DISC_INFO[filesystem]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_detect_filesystem
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Dateisystem-Typ
# Parameter: keine
# Ausgabe..: Dateisystem-Typ (stdout)
# Rückgabe.: 0 = Erfolg
# ===========================================================================
discinfo_detect_filesystem() {
    #-- Standardwert für unbekanntes Dateisystem ----------------------------
    local fs_type="unknown"
    
    #-- blkid Pfad ermitteln und wenn vorhanden verwenden -------------------
    local blkid_cmd=$(_systeminfo_get_blkid_path)
    if [[ -n "$blkid_cmd" ]]; then
        local blkid_output=$($blkid_cmd "$CD_DEVICE" 2>/dev/null)
        if [[ -n "$blkid_output" ]]; then
            fs_type=$(echo "$blkid_output" | grep -o 'TYPE="[^"]*"' | cut -d'"' -f2)
        fi
    fi
    
    #-- Rückgabe des ermittelten Dateisystem-Typs ---------------------------
    echo "$fs_type"
    return 0
}

# ===========================================================================
# discinfo_get_copy_method
# ---------------------------------------------------------------------------
# Funktion.: Lese verwendete Kopiermethode
# Parameter: keine
# Ausgabe..: Methode - ddrescue, dd, cdparanoia, dvdbackup, makemkvcon
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_copy_method() {
    #-- Array Wert lesen ----------------------------------------------------
    local method="${DISC_INFO[copy_method]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$method" ]]; then
        echo "$method"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_COPY_METHOD: $MSG_DEBUG_GET_COPY_METHOD_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_copy_method
# ---------------------------------------------------------------------------
# Funktion.: Setze verwendete Kopiermethode
# Parameter: $1 = copy_method (ddrescue, dd, cdparanoia, dvdbackup, makemkvcon)
# Rückgabe.: 0 = Erfolg, 1 = Methode leer
# ===========================================================================
discinfo_set_copy_method() {
    #-- Parameter übernehmen ------------------------------------------------
    local method="$1"
    local old_value="${DISC_INFO[copy_method]}"

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$method" ]]; then
        log_debug "$MSG_DEBUG_SET_COPY_METHOD_EMPTY"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[copy_method]="$method"
    log_debug "$MSG_DEBUG_SET_COPY_METHOD: '$method'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$method" ]]; then
        log_debug "$MSG_DEBUG_SET_COPY_METHOD_CHANGED: '$old_value' → '$method'"
        api_set_value_json "discinfos" "copy_method" "${DISC_INFO[copy_method]}"
    fi
    return 0
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
    #-- Array Wert lesen ----------------------------------------------------
    local timestamp="${DISC_INFO[created_at]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$timestamp" ]]; then
        log_debug "$MSG_DEBUG_GET_CREATED_AT: '$timestamp'"
        echo "$timestamp"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_CREATED_AT: $MSG_DEBUG_GET_CREATED_AT_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_created_at
# ---------------------------------------------------------------------------
# Funktion.: Setze Erstellungsdatum
# Parameter: $1 = timestamp (ISO 8601 Format: YYYY-MM-DDTHH:MM:SSZ)
# Rückgabe.: 0 = Erfolg, 1 = Timestamp leer
# Beschr...: Auto-Detection wenn kein Timestamp übergeben wird
# ===========================================================================
discinfo_set_created_at() {
    #-- Parameter übernehmen ------------------------------------------------
    local timestamp="$1"
    local old_value="${DISC_INFO[created_at]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$timestamp" ]]; then
        timestamp=$(discinfo_detect_created_at)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$timestamp" ]]; then
        log_debug "$MSG_DEBUG_SET_CREATED_AT_EMPTY"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[created_at]="$timestamp"
    log_debug "$MSG_DEBUG_SET_CREATED_AT: '$timestamp'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$timestamp" ]]; then
        log_debug "$MSG_DEBUG_SET_CREATED_AT_CHANGED: '$old_value' → '$timestamp'"
        api_set_value_json "discinfos" "created_at" "${DISC_INFO[created_at]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_detect_created_at
# ---------------------------------------------------------------------------
# Funktion.: Ermittle ISO-Erstellungsdatum
# Parameter: keine
# Ausgabe..: ISO 8601 Timestamp (stdout)
# Rückgabe.: 0 = Erfolg
# ===========================================================================
discinfo_detect_created_at() {
    local timestamp=""
    
    #-- isoinfo Pfad ermitteln und wenn vorhanden verwenden -----------------
    local isoinfo_cmd=$(_systeminfo_get_isoinfo_path)
    if [[ -n "$isoinfo_cmd" ]]; then
        timestamp=$($isoinfo_cmd -d -i "$CD_DEVICE" 2>/dev/null | grep "Creation Date:" | sed 's/Creation Date: //' | xargs)
    fi
    
    #-- Fallback: Aktuelles Datum -------------------------------------------
    if [[ -z "$timestamp" ]]; then
        timestamp=$(date -Iseconds)
    fi
    
    #-- Rückgabe des ermittelten Timestamps ---------------------------------
    echo "$timestamp"
    return 0
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
    #-- Array Wert lesen ----------------------------------------------------
    local title="${DISC_INFO[title]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$title" ]]; then
        log_debug "$MSG_DEBUG_GET_TITLE: '$title'"
        echo "$title"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_TITLE: $MSG_DEBUG_GET_TITLE_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_title
# ---------------------------------------------------------------------------
# Funktion.: Setze Disc-Titel
# Parameter: $1 = title
# Rückgabe.: 0 = Erfolg, 1 = Ungültiger Titel
# ===========================================================================
discinfo_set_title() {
    #-- Parameter übernehmen ------------------------------------------------
    local title="$1"
    local old_value="${DISC_INFO[title]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$title" ]]; then
        title=$(discinfo_detect_title)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$title" ]]; then
        log_debug "$MSG_DEBUG_SET_TITLE_EMPTY"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[title]="$title"
    log_debug "$MSG_DEBUG_SET_TITLE: '$title'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$title" ]]; then
        log_debug "$MSG_DEBUG_SET_TITLE_CHANGED: '$old_value' → '$title'"
        api_set_value_json "discinfos" "title" "${DISC_INFO[title]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_detect_title
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Disc-Titel
# Parameter: keine
# Ausgabe..: Titel (stdout)
# Rückgabe.: 0 = Erfolg
# Beschr...: Wird normalerweise von Provider-Modulen gesetzt,
# .........  Fallback: Nutzt Volume-Label als Titel
# ===========================================================================
discinfo_detect_title() {
    #-- Fallback: Versuche Volume-Label als Titel zu verwenden --------------
    local title=$(discinfo_get_label)
    log_debug "Fallback auf Label als Titel: '$title'"

    #-- Rückgabe des ermittelten Titels -------------------------------------
    echo "$title"
    return 0
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
    #-- Array Wert lesen ----------------------------------------------------
    local date="${DISC_INFO[release_date]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$date" ]]; then
        log_debug "$MSG_DEBUG_GET_RELEASE_DATE: '$date'"
        echo "$date"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_RELEASE_DATE: $MSG_DEBUG_GET_RELEASE_DATE_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_release_date
# ---------------------------------------------------------------------------
# Funktion.: Setze Veröffentlichungsdatum
# Parameter: $1 = date (YYYY-MM-DD)
# Rückgabe.: 0 = Erfolg, 1 = Datum leer
# Beschr...: Auto-Detection wenn kein Datum übergeben wird
# ===========================================================================
discinfo_set_release_date() {
    #-- Parameter übernehmen ------------------------------------------------
    local date="$1"
    local old_value="${DISC_INFO[release_date]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$date" ]]; then
        date=$(discinfo_detect_release_date)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$date" ]]; then
        log_debug "$MSG_DEBUG_SET_RELEASE_DATE_EMPTY"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[release_date]="$date"
    log_debug "$MSG_DEBUG_SET_RELEASE_DATE: '$date'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$date" ]]; then
        log_debug "$MSG_DEBUG_SET_RELEASE_DATE_CHANGED: '$old_value' → '$date'"
        api_set_value_json "discinfos" "release_date" "${DISC_INFO[release_date]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_detect_release_date
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Veröffentlichungsdatum
# Parameter: keine
# Ausgabe..: Datum (YYYY-MM-DD) (stdout)
# Rückgabe.: 0 = Erfolg
# Beschr...: Wird normalerweise von Provider-Modulen gesetzt
# .........  Fallback 1: ISO-Erstellungsdatum (created_at)
# .........  Fallback 2: Aktuelles Datum
# ===========================================================================
discinfo_detect_release_date() {
    #-- Fallback: Nutze ISO-Erstellungsdatum (nur Datum, nicht Uhrzeit) -----
    local created_at
    created_at=$(discinfo_get_created_at)
    
    if [[ -n "$created_at" ]]; then
        #-- Extrahiere nur Datum (YYYY-MM-DD) aus ISO 8601 (YYYY-MM-DDTHH:MM:SSZ)
        local date="${created_at%%T*}"
        echo "$date"
        return 0
    fi

    #-- Letzter Fallback: Aktuelles Datum -----------------------------------
    echo "$(date '+%Y-%m-%d')"
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
    #-- Array Wert lesen ----------------------------------------------------
    local country="${DISC_INFO[country]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$country" ]]; then
        log_debug "$MSG_DEBUG_GET_COUNTRY: '$country'"
        echo "$country"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_COUNTRY: $MSG_DEBUG_GET_COUNTRY_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_country
# ---------------------------------------------------------------------------
# Funktion.: Setze Veröffentlichungsland
# Parameter: $1 = country (Ländercode: DE, GB, US, EU, etc.)
# Rückgabe.: 0 = Erfolg, 1 = Ländercode leer
# Beschr...: Auto-Detection wenn kein Ländercode übergeben wird
# ===========================================================================
discinfo_set_country() {
    #-- Parameter übernehmen ------------------------------------------------
    local country="$1"
    local old_value="${DISC_INFO[country]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$country" ]]; then
        country=$(discinfo_detect_country)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$country" ]]; then
        log_debug "$MSG_DEBUG_SET_COUNTRY_EMPTY"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[country]="$country"
    log_debug "$MSG_DEBUG_SET_COUNTRY: '$country'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$country" ]]; then
        log_debug "$MSG_DEBUG_SET_COUNTRY_CHANGED: '$old_value' → '$country'"
        api_set_value_json "discinfos" "country" "${DISC_INFO[country]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_detect_country
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Veröffentlichungsland
# Parameter: keine
# Ausgabe..: Ländercode (stdout)
# Rückgabe.: 0 = Erfolg
# Beschr...: Fallback: "XX" (Unknown)
# ===========================================================================
discinfo_detect_country() {
    # TODO: Welche Quellen für den Ländercode git es? 
    #       (isoinfo, blkid, externe Provider, etc.)
    #-- Fallback: Unknown ---------------------------------------------------
    echo "XX"
    return 0
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
    #-- Array Wert lesen ----------------------------------------------------
    local publisher="${DISC_INFO[publisher]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$publisher" ]]; then
        log_debug "$MSG_DEBUG_GET_PUBLISHER: '$publisher'"
        echo "$publisher"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_PUBLISHER: $MSG_DEBUG_GET_PUBLISHER_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_publisher
# ---------------------------------------------------------------------------
# Funktion.: Setze Publisher/Label
# Parameter: $1 = publisher
# Rückgabe.: 0 = Erfolg, 1 = Publisher leer
# Beschr...: Auto-Detection wenn kein Publisher übergeben wird
# ===========================================================================
discinfo_set_publisher() {
    #-- Parameter übernehmen ------------------------------------------------
    local publisher="$1"
    local old_value="${DISC_INFO[publisher]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$publisher" ]]; then
        publisher=$(discinfo_detect_publisher)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$publisher" ]]; then
        log_debug "$MSG_DEBUG_SET_PUBLISHER_EMPTY"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[publisher]="$publisher"
    log_debug "$MSG_DEBUG_SET_PUBLISHER: '$publisher'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$publisher" ]]; then
        log_debug "$MSG_DEBUG_SET_PUBLISHER_CHANGED: '$old_value' → '$publisher'"
        api_set_value_json "discinfos" "publisher" "${DISC_INFO[publisher]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_detect_publisher
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Publisher
# Parameter: keine
# Ausgabe..: Publisher (stdout) oder leerer String
# Rückgabe.: 0 = Erfolg
# Beschr...: Wird normalerweise von Provider-Modulen gesetzt
# ===========================================================================
discinfo_detect_publisher() {
    #-- Fallback: Unknown ---------------------------------------------------
    echo  ""
    return 0
}

# ===========================================================================
# discinfo_get_provider
# ---------------------------------------------------------------------------
# Funktion.: Lese Metadaten-Provider
# Parameter: keine
# Ausgabe..: Provider-Name (stdout)
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_provider() {
    #-- Array Wert lesen ----------------------------------------------------
    local provider="${DISC_INFO[provider]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$provider" ]]; then
        log_debug "$MSG_DEBUG_GET_PROVIDER: '$provider'"
        echo "$provider"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_PROVIDER: $MSG_DEBUG_GET_PROVIDER_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_provider
# ---------------------------------------------------------------------------
# Funktion.: Setze Metadaten-Provider
# Parameter: $1 = provider (musicbrainz, tmdb, manual, none)
# Rückgabe.: 0 = Erfolg, 1 = Provider leer
# Beschr...: Auto-Detection wenn kein Provider übergeben wird
# ===========================================================================
discinfo_set_provider() {
    #-- Parameter übernehmen ------------------------------------------------
    local provider="$1"
    local old_value="${DISC_INFO[provider]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$provider" ]]; then
        provider=$(discinfo_detect_provider)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$provider" ]]; then
        log_debug "$MSG_DEBUG_SET_PROVIDER_EMPTY"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[provider]="$provider"
    log_debug "$MSG_DEBUG_SET_PROVIDER: '$provider'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$provider" ]]; then
        log_debug "$MSG_DEBUG_SET_PROVIDER_CHANGED: '$old_value' → '$provider'"
        api_set_value_json "discinfos" "provider" "${DISC_INFO[provider]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_detect_provider
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Metadaten-Provider
# Parameter: keine
# Ausgabe..: Provider-Name (stdout)
# Rückgabe.: 0 = Erfolg
# Beschr...: Fallback: "none"
# ===========================================================================
discinfo_detect_provider() {
    # TODO: Welche Kriterien für die Erkennung des Providers gibt es?
    #       (Disc-Typ, Dateisystem, vorhandene Dateien, etc.)
    #-- Fallback: None ------------------------------------------------------
    echo "none"
    return 0
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
    #-- Array Wert lesen ----------------------------------------------------
    local id="${DISC_INFO[provider_id]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$id" ]]; then
        log_debug "$MSG_DEBUG_GET_PROVIDER_ID: '$id'"
        echo "$id"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_PROVIDER_ID: $MSG_DEBUG_GET_PROVIDER_ID_EMPTY"
    echo "0"
    return 1
}

# ===========================================================================
# discinfo_set_provider_id
# ---------------------------------------------------------------------------
# Funktion.: Setze Provider-ID
# Parameter: $1 = provider_id
# Rückgabe.: 0 = Erfolg, 1 = ID leer
# Beschr...: Auto-Detection wenn keine ID übergeben wird
# ===========================================================================
discinfo_set_provider_id() {
    #-- Parameter übernehmen ------------------------------------------------
    local id="$1"
    local old_value="${DISC_INFO[provider_id]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$id" ]]; then
        id=$(discinfo_detect_provider_id)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$id" ]]; then
        log_debug "$MSG_DEBUG_SET_PROVIDER_ID_EMPTY"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[provider_id]="$id"
    log_debug "$MSG_DEBUG_SET_PROVIDER_ID: '$id'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$id" ]]; then
        log_debug "$MSG_DEBUG_SET_PROVIDER_ID_CHANGED: '$old_value' → '$id'"
        api_set_value_json "discinfos" "provider_id" "${DISC_INFO[provider_id]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_detect_provider_id
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Provider-ID
# Parameter: keine
# Ausgabe..: Provider-ID (stdout) oder leerer String
# Rückgabe.: 0 = Erfolg
# Beschr...: Keine automatische Erkennung möglich, gibt leeren String zurück
# ===========================================================================
discinfo_detect_provider_id() {
    # TODO: Welche Kriterien für die Erkennung der Provider-ID gibt es?
    #       (Disc-Typ, Dateisystem, vorhandene Dateien, etc.)
    #-- Keine automatische Erkennung möglich --------------------------------
    echo ""
    return 0
}

# ===========================================================================
# URL/Dateinamen Getter/Setter 
# ===========================================================================
# Diese Funktionen ermöglichen das Setzen und Abrufen von Dateinamen/URLs, 
# die während des Kopiervorgangs verwendet werden. Sie bieten eine zentrale 
# Stelle für die Verwaltung dieser Informationen und erleichtern die Inte-
# gration mit anderen Modulen, die diese Werte benötigen.
# Eine automatische Erkennung ist hier nicht möglich, da die Dateinamen/URLs 
# von externen Faktoren abhängen (z.B. Benutzereingaben, Konfiguration, 
# Provider-Module)

# ===========================================================================
# discinfo_get_cover_path
# ---------------------------------------------------------------------------
# Funktion.: Lese lokalen Cover-Pfad
# Parameter: keine
# Ausgabe..: Dateipfad 
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_cover_path() {
    #-- Array Wert lesen ----------------------------------------------------
    local path="${DISC_INFO[cover_path]}"
    
    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$path" ]]; then
        log_debug "$MSG_DEBUG_GET_COVER_PATH: '$path'"
        echo "$path"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_COVER_PATH: $MSG_DEBUG_GET_COVER_PATH_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_cover_path
# ---------------------------------------------------------------------------
# Funktion.: Setze lokalen Cover-Pfad
# Parameter: $1 = cover_path
# Rückgabe.: 0 = Erfolg, 1 = Pfad leer
# ===========================================================================
discinfo_set_cover_path() {
    #-- Parameter übernehmen ------------------------------------------------
    local path="$1"
    local old_value="${DISC_INFO[cover_path]}"

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$path" ]]; then
        log_debug "$MSG_DEBUG_SET_COVER_PATH_EMPTY"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[cover_path]="$path"
    log_debug "$MSG_DEBUG_SET_COVER_PATH: '$path'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$path" ]]; then
        log_debug "$MSG_DEBUG_SET_COVER_PATH_CHANGED: '$old_value' → '$path'"
        api_set_value_json "discinfos" "cover_path" "${DISC_INFO[cover_path]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_get_cover_url
# ---------------------------------------------------------------------------
# Funktion.: Lese Cover-URL
# Parameter: keine
# Ausgabe..: URL 
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_cover_url() {
    #-- Array Wert lesen ----------------------------------------------------
    local url="${DISC_INFO[cover_url]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$url" ]]; then
        echo "$url"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_COVER_URL: $MSG_DEBUG_GET_COVER_URL_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_cover_url
# ---------------------------------------------------------------------------
# Funktion.: Setze Cover-URL
# Parameter: $1 = cover_url
# Rückgabe.: 0 = Erfolg, 1 = URL leer
# ===========================================================================
discinfo_set_cover_url() {
    local url="$1"
    local old_value="${DISC_INFO[cover_url]}"

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$url" ]]; then
        log_debug "$MSG_DEBUG_SET_COVER_URL_EMPTY"
        return 1
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[cover_url]="$url"
    log_debug "$MSG_DEBUG_SET_COVER_URL: '$url'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$url" ]]; then
        log_debug "$MSG_DEBUG_SET_COVER_URL_CHANGED: '$old_value' → '$url'"
        api_set_value_json "discinfos" "cover_url" "${DISC_INFO[cover_url]}"
    fi
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
    #-- Array Wert lesen ----------------------------------------------------
    local basename="${DISC_INFO[iso_basename]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$basename" ]]; then
        echo "$basename"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_ISO_BASENAME: $MSG_DEBUG_GET_ISO_BASENAME_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_iso_basename
# ---------------------------------------------------------------------------
# Funktion.: Setze ISO-Basisnamen
# Parameter: $1 = iso_basename (nur Dateiname)
# Rückgabe.: 0 = Erfolg, 1 = Basisname leer
# Beschr...: Entfernt automatisch Dateiendungen falls vorhanden
# ===========================================================================
discinfo_set_iso_basename() {
    #-- Parameter übernehmen ------------------------------------------------
    local basename="$1"
    local old_value="${DISC_INFO[iso_basename]}"

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$basename" ]]; then
        log_debug "$MSG_DEBUG_SET_ISO_BASENAME_EMPTY"
        return 1
    fi

    #-- Prüfen ob eine Dateiendung übergeben wurde und ggf. entfernen -------
    if [[ "$basename" == *.* ]]; then
        basename="${basename%.*}"
        log_debug "$MSG_DEBUG_SET_ISO_BASENAME_EXTENSION_REMOVED: '$basename'"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[iso_basename]="$basename"
    log_debug "$MSG_DEBUG_SET_ISO_BASENAME: '$basename'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$basename" ]]; then
        log_debug "$MSG_DEBUG_SET_ISO_BASENAME_CHANGED: '$old_value' → '$basename'"
        api_set_value_json "discinfos" "iso_basename" "${DISC_INFO[iso_basename]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_get_iso_filename
# ---------------------------------------------------------------------------
# Funktion.: Lese ISO-Dateinamen
# Parameter: keine
# Ausgabe..: ISO-Dateiname
# Rückgabe.: 0 = Wert vorhanden, 1 = Leer
# ===========================================================================
discinfo_get_iso_filename() {
    #-- Array Wert lesen ----------------------------------------------------
    local filename="${DISC_INFO[iso_filename]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$filename" ]]; then
        log_debug "$MSG_DEBUG_GET_ISO_FILENAME: '$filename'"
        echo "$filename"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_ISO_FILENAME: $MSG_DEBUG_GET_ISO_FILENAME_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_iso_filename
# ---------------------------------------------------------------------------
# Funktion.: Setze ISO-Dateinamen
# Parameter: $1 = iso_filename (vollständiger Pfad)
# Rückgabe.: 0 = Erfolg, 1 = Dateiname leer
# Beschr...: Ergänzt .iso-Endung und Pfad automatisch falls nicht vorhanden
# ===========================================================================
discinfo_set_iso_filename() {
    #-- Parameter übernehmen ------------------------------------------------
    local filename="$1"
    local old_value="${DISC_INFO[iso_filename]}"

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$filename" ]]; then
        log_debug "$MSG_DEBUG_SET_ISO_FILENAME_EMPTY"
        return 1
    fi

    #-- Dateiendung prüfen (sollte .iso sein) und ggf. ergänzen -------------
    if [[ "$filename" != *.iso ]]; then
        filename="${filename}.iso"
        log_debug "$MSG_DEBUG_SET_ISO_FILENAME_EXTENSION_ADDED: '$filename'"
    fi

    #-- Enthält der übergebene Pfad Angaben? Wenn nicht Auto-Detect ---------
    if [[ "$filename" != */* ]]; then
        local missed_path="${folders_get_output_dir}"
        if [[ -n "$missed_path" ]]; then
            filename="${missed_path}/${filename}"
            log_debug "$MSG_DEBUG_SET_ISO_FILENAME_AUTO_PATH: '$filename'"
        fi
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[iso_filename]="$filename"
    log_debug "$MSG_DEBUG_SET_ISO_FILENAME: '$filename'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$filename" ]]; then
        log_debug "$MSG_DEBUG_SET_ISO_FILENAME_CHANGED: '$old_value' → '$filename'"
        api_set_value_json "discinfos" "iso_filename" "${DISC_INFO[iso_filename]}"
    fi
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
    #-- Array Wert lesen ----------------------------------------------------
    local filename="${DISC_INFO[md5_filename]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$filename" ]]; then
        echo "$filename"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_MD5_FILENAME: $MSG_DEBUG_GET_MD5_FILENAME_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_md5_filename
# ---------------------------------------------------------------------------
# Funktion.: Setze MD5-Dateinamen
# Parameter: $1 = md5_filename (vollständiger Pfad)
# Rückgabe.: 0 = Erfolg, 1 = Ungültiger Pfad
# ===========================================================================
discinfo_set_md5_filename() {
    #-- Parameter übernehmen ------------------------------------------------
    local filename="$1"
    local old_value="${DISC_INFO[md5_filename]}"

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$filename" ]]; then
        log_debug "$MSG_DEBUG_SET_MD5_FILENAME_EMPTY"
        return 1
    fi

    #-- Dateiendung prüfen (sollte .md5 sein) und ggf. ergänzen -------------
    if [[ "$filename" != *.md5 ]]; then
        filename="${filename}.md5"
        log_debug "$MSG_DEBUG_SET_MD5_FILENAME_EXTENSION_ADDED: '$filename'"
    fi

    #-- Enthält der übergebene Pfad Angaben? Wenn nicht Auto-Detect ---------
    if [[ "$filename" != */* ]]; then
        local missed_path="${folders_get_output_dir}"
        if [[ -n "$missed_path" ]]; then
            filename="${missed_path}/${filename}"
            log_debug "$MSG_DEBUG_SET_MD5_FILENAME_AUTO_PATH: '$filename'"
        fi
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[md5_filename]="$filename"
    log_debug "$MSG_DEBUG_SET_MD5_FILENAME: '$filename'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$filename" ]]; then
        log_debug "$MSG_DEBUG_SET_MD5_FILENAME_CHANGED: '$old_value' → '$filename'"
        api_set_value_json "discinfos" "md5_filename" "${DISC_INFO[md5_filename]}"
    fi
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
    #-- Array Wert lesen ----------------------------------------------------
    local filename="${DISC_INFO[log_filename]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$filename" ]]; then
        log_debug "$MSG_DEBUG_GET_LOG_FILENAME: '$filename'"
        echo "$filename"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_LOG_FILENAME: $MSG_DEBUG_GET_LOG_FILENAME_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_log_filename
# ---------------------------------------------------------------------------
# Funktion.: Setze Log-Dateinamen
# Parameter: $1 = log_filename (vollständiger Pfad)
# Rückgabe.: 0 = Erfolg, 1 = Ungültiger Pfad
# ===========================================================================
discinfo_set_log_filename() {
    #-- Parameter übernehmen ------------------------------------------------
    local filename="$1"
    local old_value="${DISC_INFO[log_filename]}"

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$filename" ]]; then
        log_debug "$MSG_DEBUG_SET_LOG_FILENAME_EMPTY"
        return 1
    fi

    #-- Dateiendung prüfen (sollte .log sein) und ggf. ergänzen -------------
    if [[ "$filename" != *.log ]]; then
        filename="${filename}.log"
        log_debug "$MSG_DEBUG_SET_LOG_FILENAME_EXTENSION_ADDED: '$filename'"
    fi

    #-- Enthält der übergebene Pfad Angaben? Wenn nicht Auto-Detect ---------
    if [[ "$filename" != */* ]]; then
        local missed_path="${folders_get_log_dir}"
        if [[ -n "$missed_path" ]]; then
            filename="${missed_path}/${filename}"
            log_debug "$MSG_DEBUG_SET_LOG_FILENAME_AUTO_PATH: '$filename'"
        fi
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[log_filename]="$filename"
    log_debug "$MSG_DEBUG_SET_LOG_FILENAME: '$filename'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$filename" ]]; then
        log_debug "$MSG_DEBUG_SET_LOG_FILENAME_CHANGED: '$old_value' → '$filename'"
        api_set_value_json "discinfos" "log_filename" "${DISC_INFO[log_filename]}"
    fi
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
    #-- Array Wert lesen ----------------------------------------------------
    local pathname="${DISC_INFO[temp_pathname]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$pathname" ]]; then
        log_debug "$MSG_DEBUG_GET_TEMP_PATHNAME: '$pathname'"
        echo "$pathname"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_debug "$MSG_DEBUG_GET_TEMP_PATHNAME: $MSG_DEBUG_GET_TEMP_PATHNAME_EMPTY"
    echo ""
    return 1
}

# ===========================================================================
# discinfo_set_temp_pathname
# ---------------------------------------------------------------------------
# Funktion.: Setze temporären Arbeitsordner
# Parameter: $1 = temp_pathname (vollständiger Pfad)
# Rückgabe.: 0 = Erfolg, 1 = Pfad leer
# Beschr...: Ergänzt .tmp-Endung und Pfad automatisch falls nicht vorhanden
# ===========================================================================
discinfo_set_temp_pathname() {
    #-- Parameter übernehmen ------------------------------------------------
    local pathname="$1"
    local old_value="${DISC_INFO[temp_pathname]}"

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$pathname" ]]; then
        log_debug "$MSG_DEBUG_SET_TEMP_PATHNAME_EMPTY"
        return 1
    fi

    #-- Dateiendung prüfen (sollte .tmp sein) und ggf. ergänzen -------------
    if [[ "$pathname" != *.tmp ]]; then
        pathname="${pathname}.tmp"
        log_debug "$MSG_DEBUG_SET_TMP_FILENAME_EXTENSION_ADDED: '$pathname'"
    fi

    #-- Enthält der übergebene Pfad Angaben? Wenn nicht Auto-Detect ---------
    if [[ "$pathname" != */* ]]; then
        local missed_path="${folders_get_temp_dir}"
        if [[ -n "$missed_path" ]]; then
            pathname="${missed_path}/${pathname}"
            log_debug "$MSG_DEBUG_SET_TMP_FILENAME_AUTO_PATH: '$pathname'"
        fi
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    DISC_INFO[temp_pathname]="$pathname"
    log_debug "$MSG_DEBUG_SET_TEMP_PATHNAME: '$pathname'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$pathname" ]]; then
        log_debug "$MSG_DEBUG_SET_TEMP_PATHNAME_CHANGED: '$old_value' → '$pathname'"
        api_set_value_json "discinfos" "temp_pathname" "${DISC_INFO[temp_pathname]}"
    fi
    return 0
}

# ===========================================================================
# discinfo_analyze
# ---------------------------------------------------------------------------
# Funktion.: Analyse der Disc-Info's für die aktuell eingelegte Disc
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beschr...: Orchestriert alle Analyse-Schritte in der richtigen Reihenfolge
#            01. drivestat_get_drive & drivestat_disc_insert     → Disc in LW
#            02. discinfo_set_type                                → Disc Type
#            03. discinfo_set_filesystem                   → Disc-Dateisystem
#            04. discinfo_set_label                              → Disc-Label
#            05. discinfo_set_size_sectors            → Disc-Größe (Sektoren)
#            06. discinfo_set_block_size            → Disc-Größe (Blockgröße)
#            07. discinfo_set_size_mb                       → Disc-Größe (MB)
#            08. discinfo_set_estimated_size_mb → (Disc-Größe + 10% Overhead)
#            09. discinfo_set_created_at        → Erstellungsdatum (ISO 8601)
#            10. discinfo_set_id                                    → Disc-ID 
#            11. discinfo_set_identifier                    → Disc-Identifier
#            12. discinfo_set_title                              → Disc-Titel
#            13. discinfo_set_release_date                → Erscheinungsdatum
#            14. init_filenames                                → iso_filename
#                                                              → md5_filename
#                                                              → log_filename
#                                                              → tmp_filename
#                                                              → iso_basename
#            
#            Diese Funktion wird in STATE_ANALYZING aufgerufen und stellt
#            sicher dass ALLE Disc-Informationen verfügbar sind bevor
#            der Kopiervorgang startet.
# ===========================================================================
discinfo_analyze() {
    #-- Start der Analyse im LOG vermerken ----------------------------------
    log_debug "$MSG_DEBUG_ANALYSE_START"
    
    #------------------------------------------------------------------------
    # Die Analyse erfolgt für jeden Wert durch den Aufruf des Getter ohne 
    # Parameter. Dadurch wird die Auto-Detection des Setter getriggert und 
    # der exaktestes Wert oder der Default-Wert für dieses Disc-Info Feld 
    # ermittelt. Ein zusätzliches Loggen der Aktion ist hierbei nicht not-
    # wendig, das dies durch den Setter/Detctor bereits erfolgt.
    # -----------------------------------------------------------------------

    #-- Step 1: Prüfung ob überhaupt eine Disk erkannt wurde ----------------
    if ! (drivestat_get_drive && drivestat_disc_insert); then
        log_error "$MSG_ERROR_NO_DISC"
        return 1
    fi

    #-- Step 2: Disc-Typ erkennen -------------------------------------------
    if ! (discinfo_set_type ""); then
        log_error "$MSG_ERROR_ANALYSE_FAILED"
        return 1
    fi

    #-- Step 3: Dateisystem erkennen ----------------------------------------
    if ! (discinfo_set_filesystem ""); then
        log_error "$MSG_ERROR_ANALYSE_FAILED"
        return 1
    fi

    #-- Step 4: Label extrahieren -------------------------------------------
    if ! (discinfo_set_label ""); then
        log_error "$MSG_ERROR_ANALYSE_FAILED"
        return 1
    fi

    #-- Step 5: Größe ermitteln (Sektoren) ----------------------------------
    if ! (discinfo_set_size_sectors ""); then
        log_error "$MSG_ERROR_ANALYSE_FAILED"
        return 1
    fi

    #-- Step 6: Größe ermitteln (Blockgröße) --------------------------------
    if ! (discinfo_set_block_size ""); then
        log_error "$MSG_ERROR_ANALYSE_FAILED"
        return 1
    fi

    #-- Step 7: Größe ermitteln (MB) ----------------------------------------
    if ! (discinfo_set_size_mb ""); then
        log_error "$MSG_ERROR_ANALYSE_FAILED"
        return 1
    fi

    #-- Step 8: Geschätzte Größe ermitteln (MB) -----------------------------
    if ! (discinfo_set_estimated_size_mb ""); then
        log_error "$MSG_ERROR_ANALYSE_FAILED"
        return 1
    fi

    #-- Step 9: Erstellungsdatum ermitteln ----------------------------------
    if ! (discinfo_set_created_at ""); then
        log_error "$MSG_ERROR_ANALYSE_FAILED"
        return 1
    fi

    #-- Step 10: Disc-ID ermitteln ------------------------------------------
    if ! (discinfo_set_id ""); then
        log_error "$MSG_ERROR_ANALYSE_FAILED"
        return 1
    fi

    #-- Step 11: Interne Disc-Identifier berechnen --------------------------
    if ! (discinfo_set_identifier ""); then
        log_error "$MSG_ERROR_ANALYSE_FAILED"
        return 1
    fi

    #-- Step 12: Titel ermitteln ---------------------------------------------
    if ! (discinfo_set_title ""); then
        log_error "$MSG_ERROR_ANALYSE_FAILED"
        return 1
    fi

    #-- Step 13: Erscheinungsdatum ermitteln --------------------------------
    if ! (discinfo_set_release_date ""); then
        log_error "$MSG_ERROR_ANALYSE_FAILED"
        return 1
    fi

    #--Step 14: Dateinamen generieren ---------------------------------------
    if ! (init_filenames); then
        log_error "$MSG_ERROR_ANALYSE_FAILED"
        return 1
    fi

    #-- Schreiben nach JSON & Loggen der Initialisierung --------------------
    api_set_section_json "discinfos" ".disc_info" "$(_discinfo_create_json "DISC_INFO" "disc_info")"

    #-- Ende der Analyse im LOG vermerken --------------------------------------    
    log_debug "$MSG_DEBUG_INIT_SUCCESS"
    return 0
}

# ===========================================================================
# diskinfos_collect_software_info
# ---------------------------------------------------------------------------
# Funktion.: Sammelt Informationen über installierte Disk-Info-Software
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beschr...: Schreibt JSON-Daten mit Software-Informationen in API
# ===========================================================================
diskinfos_collect_software_info() {
    #-- Start der Sammlung im LOG vermerken ---------------------------------
    log_debug "$MSG_DEBUG_COLLECT_SOFTWARE_START"
    
    #-- Lese Dependencies aus diskinfos INI-Datei ---------------------------
    local external_deps=$(settings_get_value_ini "diskinfos" "dependencies" "external" "") || {
        log_warning "$MSG_WARNING_NO_EXTERNAL_DEPS"
        external_deps=""
    }
    local optional_deps=$(settings_get_value_ini "diskinfos" "dependencies" "optional" "") || {
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
        api_set_section_json "diskinfos" ".software" "[]"
        return 0
    fi
    
    #-- Prüfe ob systeminfo_check_software_list verfügbar ist ---------------
    if ! type -t systeminfo_check_software_list &>/dev/null; then
        log_error "$MSG_ERROR_SYSTEMINFO_UNAVAILABLE"
        
        #-- Schreibe Fehler in API ------------------------------------------
        api_set_section_json "diskinfos" ".software" '{"error":"systeminfo_check_software_list nicht verfügbar"}'
        return 1
    fi
    
    #-- Prüfe Software-Verfügbarkeit ----------------------------------------
    local json_result
    json_result=$(systeminfo_check_software_list "$all_deps") || {
        log_error "$MSG_ERROR_SOFTWARE_CHECK_FAILED"
        
        #-- Schreibe Fehler in API ------------------------------------------
        api_set_section_json "diskinfos" ".software" '{"error":"Software-Prüfung fehlgeschlagen"}'
        return 1
    }
    
    #-- Schreibe Ergebnis in API --------------------------------------------
    api_set_section_json "diskinfos" ".software" "$json_result" || {
        log_error "$MSG_ERROR_API_WRITE_FAILED"
        return 1
    }
    
    log_debug "$MSG_DEBUG_COLLECT_SOFTWARE_SUCCESS"
    return 0
}

# ===========================================================================
# diskinfos_get_software_info
# ---------------------------------------------------------------------------
# Funktion.: Gibt Software-Informationen als JSON zurück
# Parameter: keine
# Ausgabe..: JSON-String mit Software-Informationen (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
diskinfos_get_software_info() {
    diskinfos_collect_software_info
    local software_json
    software_json=$(api_get_section_json "diskinfos" "software") || {
        log_error "$MSG_ERROR_API_READ_FAILED"
        echo '{"error":"API-Auslese fehlgeschlagen"}'
        return 1
    }
    echo "$software_json"
    return 0
}
