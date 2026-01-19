#!/bin/bash
################################################################################
# disk2iso v1.2.0 - Audio CD Metadata Remaster Library
# Filepath: lib/lib-cd-metadata.sh
#
# Beschreibung:
#   Nachträgliche Metadaten-Erfassung für Audio-CDs
#   - remaster_audio_iso_with_metadata() - ISO mit korrekten Tags neu erstellen
#   - extract_iso_to_temp() - ISO mounten/extrahieren
#   - update_mp3_tags() - ID3-Tags aktualisieren
#   - rebuild_audio_iso() - Neue ISO mit korrekten Tags erstellen
#
# Version: 1.2.0
# Datum: 18.01.2026
################################################################################

# ============================================================================
# MUSICBRAINZ API CONFIGURATION
# ============================================================================
readonly MUSICBRAINZ_API_BASE_URL="https://musicbrainz.org/ws/2"
readonly COVERART_API_BASE_URL="https://coverartarchive.org"
readonly MUSICBRAINZ_USER_AGENT="disk2iso/1.2.0"

# ============================================================================
# CONFIGURATIONS KONSTANTEN
# ============================================================================
readonly MUSICBRAINZ_TMP_DIR="musicbrainz"
readonly MUSICBRAINZ_COVERS_DIR="covers"

# ============================================================================
# Globale Variablen 
# ============================================================================
MUSICBRAINZ_CACHE_DIR=""
MUSICBRAINZ_COVERS_DIR_PATH=""

# ===========================================================================
# init_musicbrainz_cache_dirs
# ---------------------------------------------------------------------------
# Funktion: Initialisiere MusicBrainz Cache-Verzeichnisse (Lazy Initialization)
# ......... Nutzt ensure_subfolder() aus lib-folders.sh für konsistente 
# ......... Verzeichnisverwaltung
# Parameter: Keine
# Rückgabe: 0 = Erfolg, 1 = Fehler
# ===========================================================================
init_musicbrainz_cache_dirs() {
    if [[ -z "$MUSICBRAINZ_CACHE_DIR" ]]; then
        # Prüfen ob ensure_subfolder Funktion geladen ist
        if ! declare -f ensure_subfolder >/dev/null 2>&1; then
            log_error "MusicBrainz: Fehler - lib-folders.sh nicht geladen" >&2
            return 1
        fi

        # MusicBrainz Cache-Verzeichnis erstellen (relativ zu OUTPUT_DIR)
        MUSICBRAINZ_CACHE_DIR=$(ensure_subfolder ".temp/${MUSICBRAINZ_TMP_DIR}") || return 1
        log_info "MusicBrainz: Cache-Verzeichnis initialisiert: $MUSICBRAINZ_CACHE_DIR" >&2

        # MusicBrainz Covers Verzeichnis erstellen
        MUSICBRAINZ_COVERS_DIR_PATH=$(ensure_subfolder ".temp/${MUSICBRAINZ_TMP_DIR}/${MUSICBRAINZ_COVERS_DIR}") || return 1
        log_info "MusicBrainz: Covers-Verzeichnis initialisiert: $MUSICBRAINZ_COVERS_DIR_PATH" >&2
    fi
    return 0
}

# ===========================================================================
# url_encode
# ---------------------------------------------------------------------------
# Funktion: URL-Encode String (ohne jq-Abhängigkeit)
# Parameter: $1 = String zum Encoden
# Rückgabe: URL-encoded String via stdout
# Hinweis: Implementiert RFC 3986 (außer -.~_ werden alle Zeichen encoded)
# ===========================================================================
url_encode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for ((pos=0; pos<strlen; pos++)); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02x' "'$c" ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# ===========================================================================
# populate_musicbrainz_cache
# ---------------------------------------------------------------------------
# Funktion: Erstelle .nfo + Thumbnail für jeden MusicBrainz-Treffer
# Parameter: $1 = RAW API Response (JSON)
#            $2 = Suchbegriff (z.B. "ronan_keating_ronan")
# Rückgabe: 0 = Erfolg, Anzahl gecachter Releases
# ===========================================================================
populate_musicbrainz_cache() {
    local raw_json="$1"
    local search_label="$2"
    
    # Initialisiere Cache
    init_musicbrainz_cache_dirs >&2 || return 1
    
    # Extrahiere Release-Count
    local release_count=$(echo "$raw_json" | jq -r '.releases | length')
    
    if [[ "$release_count" -eq 0 ]]; then
        log_info "MusicBrainz: Keine Releases zum Cachen" >&2
        return 0
    fi
    
    log_info "MusicBrainz: Cache $release_count Releases..." >&2
    
    local cached=0
    for i in $(seq 0 $((release_count - 1))); do
        # Extrahiere Metadaten
        local release_id=$(echo "$raw_json" | jq -r ".releases[$i].id")
        local title=$(echo "$raw_json" | jq -r ".releases[$i].title")
        local artist=$(echo "$raw_json" | jq -r ".releases[$i].\"artist-credit\"[0].name")
        local country=$(echo "$raw_json" | jq -r ".releases[$i].country // \"XX\"")
        local date=$(echo "$raw_json" | jq -r ".releases[$i].date // \"0000\"")
        local year=$(echo "$date" | cut -d'-' -f1)
        local tracks=$(echo "$raw_json" | jq -r ".releases[$i].media[0].\"track-count\" // 0")
        local label=$(echo "$raw_json" | jq -r ".releases[$i].\"label-info\"[0]?.label?.name // \"Unknown\"")
        local duration=$(echo "$raw_json" | jq -r "if .releases[$i].media[0].tracks then (.releases[$i].media[0].tracks | map(.length // 0) | add) else 0 end")
        
        # Cover-URL: Probiere CoverArt Archive direkt (MusicBrainz /release/ gibt oft null zurück)
        # curl wird 404 zurückgeben falls Cover nicht verfügbar
        local cover_url="https://coverartarchive.org/release/${release_id}/front-250"
        
        # Normalisiere für Dateinamen
        local safe_artist=$(echo "$artist" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_')
        local safe_title=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_')
        local safe_label=$(echo "$label" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_')
        local release_id_short="${release_id:0:8}"
        
        # Generiere Dateinamen
        local nfo_name="${safe_artist}_${safe_title}_${country}_${year}_${safe_label}_${tracks}tracks_${release_id_short}"
        local nfo_file="${MUSICBRAINZ_CACHE_DIR}/${nfo_name}.nfo"
        local thumb_file="${MUSICBRAINZ_CACHE_DIR}/covers/${nfo_name}-thumb.jpg"
        
        # Prüfe ob bereits gecacht
        if [[ -f "$nfo_file" ]]; then
            log_info "MusicBrainz: Cache-Hit - überspringe ${nfo_name:0:40}..." >&2
            continue
        fi
        
        # Erstelle .nfo
        cat > "$nfo_file" <<EOF
SEARCH_RESULT_FOR=${search_label}
RELEASE_ID=${release_id}
TITLE=${title}
ARTIST=${artist}
DATE=${date}
COUNTRY=${country}
TRACKS=${tracks}
LABEL=${label}
DURATION=${duration}
COVER_URL=${cover_url}
TYPE=audio-cd
CACHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
CACHE_VERSION=1.0
EOF
        
        # Lade Cover-Thumbnail (falls verfügbar, folge Redirects mit -L)
        if [[ -n "$cover_url" ]]; then
            if curl -L -s -f -m 5 -H "User-Agent: ${MUSICBRAINZ_USER_AGENT}" "$cover_url" -o "$thumb_file" 2>/dev/null; then
                log_info "MusicBrainz: Cover gecacht für ${nfo_name:0:40}..." >&2
            else
                log_error "MusicBrainz: Cover-Download fehlgeschlagen für ${nfo_name:0:40}..." >&2
            fi
        fi
        
        cached=$((cached + 1))
    done
    
    log_info "MusicBrainz: $cached von $release_count Releases neu gecacht" >&2
    return 0
}

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

# Funktion: Prüfe Audio-CD Metadata Abhängigkeiten
# Rückgabe: 0 = Alle kritischen Tools OK, 1 = Kritische Tools fehlen
check_audio_metadata_dependencies() {
    local missing_critical=()
    local missing_optional=()
    
    # Kritische Tools für Metadata-Funktionen
    command -v jq >/dev/null 2>&1 || missing_critical+=("jq")
    command -v curl >/dev/null 2>&1 || missing_critical+=("curl")
    
    if [[ ${#missing_critical[@]} -gt 0 ]]; then
        log_error "MusicBrainz: Metadata-Support nicht verfügbar - fehlende Tools: ${missing_critical[*]}"
        log_error "MusicBrainz: Installieren Sie: apt-get install ${missing_critical[*]}"
        return 1
    fi
    
    # Optionale Tools für erweiterte Funktionen
    command -v eyeD3 >/dev/null 2>&1 || missing_optional+=("eyeD3")
    command -v id3v2 >/dev/null 2>&1 || missing_optional+=("id3v2")
    command -v genisoimage >/dev/null 2>&1 || missing_optional+=("genisoimage")
    command -v mkisofs >/dev/null 2>&1 || missing_optional+=("mkisofs")
    
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        log_error "MusicBrainz: Erweiterte Funktionen eingeschränkt - optionale Tools fehlen: ${missing_optional[*]}"
        log_error "MusicBrainz: Für ISO-Remastering installieren Sie: apt-get install ${missing_optional[*]}"
    fi
    
    log_info "MusicBrainz: Metadata-Support verfügbar"
    return 0
}

# ============================================================================
# MUSICBRAINZ API FUNCTIONS - RAW REQUESTS (Cache-basiert)
# ============================================================================

# Funktion: Führe MusicBrainz-Anfrage durch und speichere RAW Response
# Parameter: $1 = artist (Künstler-Name)
#            $2 = album (Album-Titel)
#            $3 = iso_basename (ohne .iso, für Cache-Dateinamen)
# Rückgabe: 0 bei Erfolg, 1 bei Fehler
# WICHTIG: Speichert nur die unverarbeitete API Response im Cache
fetch_musicbrainz_raw() {
    local artist="$1"
    local album="$2"
    local iso_basename="$3"
    
    # Validierung
    if [[ -z "$artist" ]] && [[ -z "$album" ]]; then
        log_info "MusicBrainz-Request: Artist oder Album erforderlich"
        return 1
    fi
    
    # Initialisiere Cache-Verzeichnisse (Lazy Initialization)
    init_musicbrainz_cache_dirs || return 1
    
    local cache_file="${MUSICBRAINZ_CACHE_DIR}/${iso_basename}_raw.json"
    
    log_info "MusicBrainz-Request: Suche Artist='$artist', Album='$album'"
    
    # Baue Query
    local query_parts=()
    [[ -n "$artist" ]] && query_parts+=("artist:${artist}")
    [[ -n "$album" ]] && query_parts+=("release:${album}")
    
    local query=$(IFS=' AND '; echo "${query_parts[*]}")
    
    # URL-Encoding mit nativer Bash-Funktion (keine jq-Abhängigkeit)
    local encoded_query=$(url_encode "$query")
    
    local url="${MUSICBRAINZ_API_BASE_URL}/release/?query=${encoded_query}&fmt=json&limit=10&inc=artists+labels+recordings+media"
    
    log_info "MusicBrainz-Request: URL = $url" >&2
    
    # API-Anfrage - speichere direkt in Datei (vermeidet Bash String-Length-Limits)
    if ! curl -s -f -m 10 -H "User-Agent: ${MUSICBRAINZ_USER_AGENT}" "$url" -o "$cache_file" 2>/dev/null; then
        local curl_exit=$?
        log_error "MusicBrainz-Request: API-Anfrage fehlgeschlagen (exit $curl_exit)" >&2
        echo '{"error": "API request failed"}' > "$cache_file"
        return 1
    fi
    
    # Prüfe ob Response JSON ist (mindestens '{}')
    if [[ ! -s "$cache_file" ]]; then
        log_info "MusicBrainz-Request: Leere Response erhalten"
        echo '{"error": "Empty response"}' > "$cache_file"
        return 1
    fi
    
    log_info "MusicBrainz-Request: Raw response gespeichert: $(basename "$cache_file")"
    return 0
}

# Funktion: Lade Cover von CoverArtArchive mit Caching
# Parameter: $1 = Release-ID
# Rückgabe: Pfad zur Cover-Datei als JSON oder Fehler
# Nutzt globale Variable MUSICBRAINZ_COVERS_DIR_PATH (keine Parameter)
fetch_coverart() {
    local release_id="$1"
    
    if [[ -z "$release_id" ]]; then
        echo '{"success": false, "message": "Release-ID erforderlich"}'
        return 1
    fi
    
    # Initialisiere Cache-Verzeichnisse (oder fallback zu hartkodiertem Pfad)
    if ! init_musicbrainz_cache_dirs 2>/dev/null; then
        # Fallback: Verwende OUTPUT_DIR direkt (für Web-API Kontext)
        if [[ -n "$OUTPUT_DIR" ]]; then
            MUSICBRAINZ_COVERS_DIR_PATH="${OUTPUT_DIR}/.temp/musicbrainz/covers"
        else
            echo '{"success": false, "message": "Keine Cache-Verzeichnisse verfügbar"}'
            return 1
        fi
    fi
    
    # Suche zuerst in populate_musicbrainz_cache()-Thumbnails (Pattern: *_<release_id_short>-thumb.jpg)
    local release_id_short="${release_id:0:8}"
    local cached_thumb=$(find "$MUSICBRAINZ_COVERS_DIR_PATH" -name "*_${release_id_short}-thumb.jpg" 2>/dev/null | head -1)
    
    if [[ -n "$cached_thumb" && -f "$cached_thumb" ]]; then
        log_info "MusicBrainz: Cover aus populate_cache: $(basename "$cached_thumb")" >&2
        echo "{\"success\": true, \"path\": \"${cached_thumb}\", \"cached\": true}"
        return 0
    fi
    
    # Fallback: Legacy cover_<release_id>.jpg Format
    local cover_file="${MUSICBRAINZ_COVERS_DIR_PATH}/cover_${release_id}.jpg"
    
    if [[ -f "$cover_file" ]]; then
        log_info "MusicBrainz: Cover aus Legacy-Cache: $(basename "$cover_file")" >&2
        echo "{\"success\": true, \"path\": \"${cover_file}\", \"cached\": true}"
        return 0
    fi
    
    # Lade Cover von CoverArtArchive
    local cover_url="${COVERART_API_BASE_URL}/release/${release_id}/front-250"
    
    log_info "MusicBrainz: Lade Cover für Release-ID: $release_id"
    
    if curl -s -f -m 10 -o "$cover_file" "$cover_url" 2>/dev/null; then
        # Prüfe ob Download erfolgreich (Datei > 0 Bytes)
        if [[ -s "$cover_file" ]]; then
            log_info "MusicBrainz: Cover heruntergeladen: $(basename "$cover_file")"
            echo "{\"success\": true, \"path\": \"${cover_file}\", \"cached\": false}"
            return 0
        else
            rm -f "$cover_file"
            echo '{"success": false, "message": "Cover-Download leer"}'
            return 1
        fi
    else
        echo '{"success": false, "message": "Cover nicht verfügbar"}'
        return 1
    fi
}

# ============================================================================
# CACHING FUNCTIONS (Analog zu lib-dvd-metadata.sh)
# ============================================================================

# Funktion: Suche und Cache MusicBrainz-Metadaten (Hauptfunktion)
# Parameter: $1 = ISO-Dateiname (z.B. "artist_album.iso")
#            $2 = Artist (optional, wenn im Dateinamen nicht erkennbar)
#            $3 = Album (optional, wenn im Dateinamen nicht erkennbar)
# Rückgabe: 0 bei Erfolg, 1 bei Fehler
# WICHTIG: Diese Funktion speichert nur die raw API Response
#          Python übernimmt die JSON-Verarbeitung und Cover-Downloads
search_and_cache_musicbrainz() {
    local iso_filename="$1"
    local artist="${2:-}"
    local album="${3:-}"
    local iso_basename="${iso_filename%.iso}"
    
    log_info "MusicBrainz: Starte Suche für: $iso_filename"
    
    # Falls Artist/Album nicht übergeben, versuche aus Dateinamen zu extrahieren
    if [[ -z "$artist" ]] && [[ -z "$album" ]]; then
        # Einfache Extraktion: artist_album.iso → artist=artist, album=album
        if [[ "$iso_basename" =~ ^([^_]+)_(.+)$ ]]; then
            artist="${BASH_REMATCH[1]}"
            album="${BASH_REMATCH[2]}"
            log_info "MusicBrainz: Extrahiert aus Dateinamen - Artist: '$artist', Album: '$album'"
        else
            log_info "MusicBrainz: Kann Artist/Album nicht aus Dateinamen extrahieren"
            return 1
        fi
    fi
    
    # MusicBrainz-Anfrage durchführen (nur raw API call)
    if ! fetch_musicbrainz_raw "$artist" "$album" "$iso_basename"; then
        log_error "MusicBrainz: Anfrage fehlgeschlagen"
        return 1
    fi
    
    log_info "MusicBrainz: Raw response bereit - Python übernimmt Verarbeitung"
    return 0
}

# ============================================================================
# WEB API WRAPPER FUNCTIONS (für Python Flask Integration)
# ============================================================================

# Funktion: MusicBrainz Suche mit JSON-Return für Web-API (mit Caching)
# Parameter: $1 = Artist (optional bei .mbquery)
#            $2 = Album (optional bei .mbquery)
#            $3 = ISO-Pfad (optional, für .mbquery Lookup)
#            $4 = track_count (optional, für Filterung nach Track-Anzahl)
# Rückgabe: JSON-String mit {"success": true/false, "results": [...], "used_mbquery": true/false}
# WICHTIG: Speichert API-Response im Cache für spätere Nutzung durch Python
# Diese Funktion wird vom Python Web-Interface aufgerufen
search_musicbrainz_json() {
    local artist="$1"
    local album="$2"
    local iso_path="$3"
    local track_count="${4:-0}"  # Optional: 0 = keine Filterung
    
    local used_mbquery=false
    local mb_response=""
    
    # Initialisiere Cache-Verzeichnisse (Lazy Initialization)
    init_musicbrainz_cache_dirs >&2 || {
        echo '{"success": false, "message": "Cache-Initialisierung fehlgeschlagen"}'
        return 1
    }
    
    # Bestimme Cache-Dateinamen (basierend auf ISO-Pfad oder Artist+Album)
    local cache_file=""
    if [[ -n "$iso_path" ]]; then
        local iso_basename=$(basename "${iso_path%.iso}")
        cache_file="${MUSICBRAINZ_CACHE_DIR}/${iso_basename}_search.json"
    else
        local safe_name=$(echo "${artist}_${album}" | tr ' ' '_' | tr -cd 'a-zA-Z0-9_-')
        cache_file="${MUSICBRAINZ_CACHE_DIR}/${safe_name}_search.json"
    fi
    
    # Prüfe ob .mbquery Datei existiert
    if [[ -n "$iso_path" ]]; then
        local mbquery_file="${iso_path%.iso}.mbquery"
        
        if [[ -f "$mbquery_file" ]]; then
            # Lese Query-Daten
            local disc_id=""
            local toc=""
            
            while IFS='=' read -r key value; do
                case "$key" in
                    DISC_ID) disc_id="$value" ;;
                    TOC) toc="$value" ;;
                esac
            done < "$mbquery_file"
            
            if [[ -n "$disc_id" ]] && [[ -n "$toc" ]]; then
                # Nutze disc-id + TOC für exakte Suche
                local url="${MUSICBRAINZ_API_BASE_URL}/discid/${disc_id}?toc=${toc}&fmt=json&inc=artists+labels+recordings+media"
                
                # Speichere Response direkt in Cache-Datei
                if curl -s -f -m 10 -H "User-Agent: ${MUSICBRAINZ_USER_AGENT}" "$url" -o "$cache_file" 2>/dev/null; then
                    mb_response=$(cat "$cache_file")
                    used_mbquery=true
                else
                    # Fallback zu normaler Suche
                    mb_response=""
                fi
            fi
        fi
    fi
    
    # Normale Suche wenn keine .mbquery oder Fehler
    if [[ "$used_mbquery" == "false" ]]; then
        if [[ -z "$artist" ]] && [[ -z "$album" ]]; then
            echo '{"success": false, "message": "Artist oder Album erforderlich"}'
            return 1
        fi
        
        # Baue Query
        local query_parts=()
        [[ -n "$artist" ]] && query_parts+=("artist:${artist}")
        [[ -n "$album" ]] && query_parts+=("release:${album}")
        
        local query=$(IFS=' AND '; echo "${query_parts[*]}")
        
        # URL-Encoding mit nativer Bash-Funktion (keine jq-Abhängigkeit)
        local encoded_query=$(url_encode "$query")
        
        local url="${MUSICBRAINZ_API_BASE_URL}/release/?query=${encoded_query}&fmt=json&limit=10&inc=artists+labels+recordings+media"
        
        # Speichere Response direkt in Cache-Datei
        if ! curl -s -f -m 10 -H "User-Agent: ${MUSICBRAINZ_USER_AGENT}" "$url" -o "$cache_file" 2>/dev/null; then
            echo '{"success": false, "message": "MusicBrainz-Suche fehlgeschlagen"}'
            return 1
        fi
        
        mb_response=$(cat "$cache_file")
    fi
    
    # Prüfe ob Response vorhanden
    if [[ -z "$mb_response" ]]; then
        echo '{"success": false, "message": "Keine API-Response erhalten"}'
        return 1
    fi
    
    log_info "MusicBrainz: API-Response gespeichert in $(basename "$cache_file")" >&2
    
    # NEU: Befülle lokale .nfo-Cache-Datenbank
    if [[ -n "$iso_path" ]]; then
        local iso_basename=$(basename "${iso_path%.iso}")
        populate_musicbrainz_cache "$mb_response" "$iso_basename" >&2
    else
        local safe_name=$(echo "${artist}_${album}" | tr ' ' '_' | tr -cd 'a-z0-9_')
        populate_musicbrainz_cache "$mb_response" "$safe_name" >&2
    fi
    
    # Formatiere Ergebnisse mit jq
    # WICHTIG: cover_url wird nicht aus API gelesen (oft null), sondern auf unseren Endpoint gesetzt
    # fetch_coverart() sucht dann im Cache oder lädt bei Bedarf herunter
    # FILTERUNG: Wenn track_count > 0, filtere Ergebnisse nach Track-Anzahl (±1 Toleranz)
    local jq_filter='.releases[:10]'
    if [[ $track_count -gt 0 ]]; then
        local min_tracks=$((track_count - 1))
        local max_tracks=$((track_count + 1))
        jq_filter=".releases | [.[] | select(.media[0].\"track-count\" >= $min_tracks and .media[0].\"track-count\" <= $max_tracks)][:10]"
        log_info "MusicBrainz: Filtere nach $track_count Tracks (±1 Toleranz: ${min_tracks}-${max_tracks})" >&2
    fi
    
    # Bestimme bevorzugte Länder basierend auf User-Sprache
    local preferred_countries=""
    case "${LANGUAGE:-de}" in
        de) preferred_countries="DE|AT|CH|XE" ;;  # DACH + Europa-Release
        en) preferred_countries="GB|US|AU|CA|NZ|IE" ;;  # Englischsprachige Länder
        fr) preferred_countries="FR|BE|CH|CA" ;;  # Französischsprachige Länder
        es) preferred_countries="ES|MX|AR|CO|CL" ;;  # Spanischsprachige Länder
        *) preferred_countries="" ;;
    esac
    
    log_info "MusicBrainz: Bevorzugte Länder für Sprache '$LANGUAGE': $preferred_countries" >&2
    
    # Extrahiere und sortiere Ergebnisse
    # 1. Erst Releases aus bevorzugten Ländern
    # 2. Dann alle anderen
    local results=$(echo "$mb_response" | jq -c "[$jq_filter | .[] | {
        id: .id,
        title: (.title // \"Unknown Album\"),
        artist: (.\"artist-credit\"[0].name // \"Unknown\"),
        date: (.date // \"unknown\"),
        country: (.country // \"unknown\"),
        tracks: (.media[0].\"track-count\" // 0),
        label: (.\"label-info\"[0]?.label?.name // \"Unknown\"),
        duration: (if .media[0].tracks then (.media[0].tracks | map(.length // 0) | add) else 0 end),
        cover_url: .id,
        country_priority: (if (.country // \"unknown\") | test(\"$preferred_countries\") then 0 else 1 end)
    }] | sort_by(.country_priority, .date) | reverse" 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$results" ]]; then
        echo '{"success": false, "message": "JSON-Formatierung fehlgeschlagen"}'
        return 1
    fi
    
    # Baue finale Response
    echo "{\"success\": true, \"results\": $results, \"used_mbquery\": $used_mbquery}"
    return 0
}

# Funktion: MusicBrainz Cover-Art Download (Legacy Wrapper für Kompatibilität)
# Parameter: $1 = Release-ID
#            $2 = Cache-Verzeichnis (DEPRECATED - wird ignoriert)
# Rückgabe: Pfad zur Cover-Datei oder Fehler
# HINWEIS: Nutzt jetzt globale MUSICBRAINZ_COVERS_DIR_PATH statt Parameter
#          Parameter $2 wird aus Kompatibilitätsgründen akzeptiert aber ignoriert
get_musicbrainz_cover() {
    local release_id="$1"
    # local cache_dir="${2:-.temp}"  # DEPRECATED - Parameter wird ignoriert
    
    # Delegiere an neue Cache-basierte Funktion
    fetch_coverart "$release_id"
}

# ============================================================================
# RETROACTIVE METADATA FUNCTIONS
# ============================================================================

# Funktion: ISO mit korrekten MusicBrainz-Metadaten neu erstellen
# Parameter:
#   $1 = iso_path (vollständiger Pfad zur ISO-Datei)
#   $2 = musicbrainz_release_id (MusicBrainz Release-ID)
# Rückgabe: 0 bei Erfolg, 1 bei Fehler
remaster_audio_iso_with_metadata() {
    local iso_path="$1"
    local mb_release_id="$2"
    
    # Validierung
    if [[ ! -f "$iso_path" ]]; then
        log_error "Audio-Remaster: ISO-Datei nicht gefunden: $iso_path"
        return 1
    fi
    
    if [[ -z "$mb_release_id" ]]; then
        log_info "Audio-Remaster: Keine MusicBrainz Release-ID angegeben"
        return 1
    fi
    
    log_info "Audio-Remaster: Starte ISO-Remaster für: $(basename "$iso_path")"
    
    # Debug: Zeige ISO-Pfad
    log_info "Audio-Remaster: Vollständiger ISO-Pfad: $iso_path"
    
    # Erstelle temporäre Verzeichnisse in .temp (gleicher Parent wie ISO)
    # Verwende bash-interne String-Operationen statt dirname (robuster)
    local iso_dir="${iso_path%/*}"  # Entfernt den Dateinamen
    local iso_parent="${iso_dir%/*}"  # Entfernt das audio-Verzeichnis
    local temp_base="${iso_parent}/.temp"
    
    log_info "Audio-Remaster: iso_dir=$iso_dir, iso_parent=$iso_parent, temp_base=$temp_base"
    
    local temp_extract="${temp_base}/disk2iso_remaster_$$"
    local temp_tagged="${temp_base}/disk2iso_tagged_$$"
    
    mkdir -p "$temp_extract" "$temp_tagged"
    
    # Schritt 1: ISO extrahieren/mounten
    log_info "Audio-Remaster: [1/4] Extrahiere ISO..."
    if ! extract_iso_to_temp "$iso_path" "$temp_extract"; then
        cleanup_remaster_temp "$temp_extract" "$temp_tagged"
        return 1
    fi
    
    # Schritt 2: MusicBrainz-Metadaten abrufen
    log_info "Audio-Remaster: [2/4] Hole MusicBrainz-Metadaten..."
    local mb_data=$(get_musicbrainz_release_details "$mb_release_id")
    
    if [[ -z "$mb_data" ]]; then
        log_info "Audio-Remaster: Konnte MusicBrainz-Daten nicht abrufen"
        cleanup_remaster_temp "$temp_extract" "$temp_tagged"
        return 1
    fi
    
    # Extrahiere Album-Metadaten
    local artist=$(echo "$mb_data" | jq -r '."artist-credit"[0].name // "Unknown Artist"')
    local album=$(echo "$mb_data" | jq -r '.title // "Unknown Album"')
    local year=$(echo "$mb_data" | jq -r '.date // "" | split("-")[0]')
    local track_count=$(echo "$mb_data" | jq -r '.media[0]."track-count" // 0')
    local cover_url=$(echo "$mb_data" | jq -r '.["cover-art-archive"].front // empty')
    
    log_info "Audio-Remaster: Album: $artist - $album ($year)"
    
    # Lade Cover von Cover Art Archive (mit redirect-follow)
    local cover_file=""
    # Nutze API-Konstante statt hardcoded URL
    local cover_url="${COVERART_API_BASE_URL}/release/${mb_release_id}/front-500"
    
    cover_file="${temp_extract}/cover.jpg"
    if curl -L -s -f "$cover_url" -o "$cover_file" 2>/dev/null; then
        log_info "Audio-Remaster: Cover heruntergeladen"
    else
        log_error "Audio-Remaster: Cover-Download fehlgeschlagen (kein Cover verfügbar)"
        cover_file=""
    fi
    
    # Schritt 3: MP3-Tags aktualisieren
    log_info "Audio-Remaster: [3/4] Aktualisiere MP3-Tags..."
    if ! update_mp3_tags_from_musicbrainz "$temp_extract" "$temp_tagged" "$mb_data" "$cover_file"; then
        cleanup_remaster_temp "$temp_extract" "$temp_tagged"
        return 1
    fi
    
    # Schritt 4: Neue ISO erstellen
    log_info "Audio-Remaster: [4/4] Erstelle neue ISO..."
    
    # Nutze .temp Verzeichnis im gleichen Parent wie die ISO
    local iso_dir=$(dirname "$iso_path")
    local iso_parent=$(dirname "$iso_dir")
    local temp_iso="${iso_parent}/.temp/disk2iso_new_$$.iso"
    
    if ! rebuild_audio_iso "$temp_tagged" "$temp_iso"; then
        cleanup_remaster_temp "$temp_extract" "$temp_tagged"
        return 1
    fi
    
    # Ersetze alte ISO durch neue
    if mv -f "$temp_iso" "$iso_path"; then
        log_info "Audio-Remaster: ISO erfolgreich aktualisiert: $(basename "$iso_path")"
        
        # Erstelle .nfo mit Metadaten
        create_audio_nfo "$iso_path" "$artist" "$album" "$year" "$track_count" "$cover_file"
        
        # Benenne ISO nach Artist - Album Schema um
        local clean_artist=$(echo "$artist" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')
        local clean_album=$(echo "$album" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')
        local base_name="${clean_artist}_${clean_album}"
        
        # Nutze get_unique_iso_path für eindeutigen Namen (vermeidet Überschreiben)
        local new_path=$(get_unique_iso_path "$iso_dir" "$base_name" "$iso_path")
        
        # Benenne um wenn Name anders ist
        if [[ "$iso_path" != "$new_path" ]]; then
            if mv -f "$iso_path" "$new_path"; then
                log_info "Audio-Remaster: ISO umbenannt: $(basename "$new_path")"
                
                # Benenne auch .md5 und .nfo um
                local old_md5="${iso_path%.iso}.md5"
                local new_md5="${new_path%.iso}.md5"
                [[ -f "$old_md5" ]] && mv -f "$old_md5" "$new_md5"
                
                local old_nfo="${iso_path%.iso}.nfo"
                local new_nfo="${new_path%.iso}.nfo"
                [[ -f "$old_nfo" ]] && mv -f "$old_nfo" "$new_nfo"
                
                local old_thumb="${iso_path%.iso}-thumb.jpg"
                local new_thumb="${new_path%.iso}-thumb.jpg"
                [[ -f "$old_thumb" ]] && mv -f "$old_thumb" "$new_thumb"
                
                # Lösche .mbquery Datei (Query-Daten nicht mehr benötigt)
                local old_mbquery="${iso_path%.iso}.mbquery"
                [[ -f "$old_mbquery" ]] && rm -f "$old_mbquery"
                
                # MD5 neu berechnen für umbenannte ISO
                if command -v md5sum >/dev/null 2>&1; then
                    md5sum "$new_path" | cut -d' ' -f1 > "$new_md5"
                    log_info "Audio-Remaster: MD5 aktualisiert"
                fi
            else
                log_error "Audio-Remaster: Warnung - ISO-Umbenennung fehlgeschlagen"
            fi
        else
            # Nur MD5 neu berechnen und .mbquery löschen
            local md5_file="${iso_path%.iso}.md5"
            if command -v md5sum >/dev/null 2>&1; then
                md5sum "$iso_path" | cut -d' ' -f1 > "$md5_file"
                log_info "Audio-Remaster: MD5 aktualisiert"
            fi
            
            # Lösche .mbquery Datei
            local mbquery_file="${iso_path%.iso}.mbquery"
            [[ -f "$mbquery_file" ]] && rm -f "$mbquery_file"
        fi
        
        cleanup_remaster_temp "$temp_extract" "$temp_tagged"
        return 0
    else
        log_error "Audio-Remaster: Fehler beim Ersetzen der ISO"
        rm -f "$temp_iso"
        cleanup_remaster_temp "$temp_extract" "$temp_tagged"
        return 1
    fi
}

# Funktion: Extrahiere ISO zu temporärem Verzeichnis
# Parameter:
#   $1 = iso_path
#   $2 = temp_dir
# Rückgabe: 0 bei Erfolg
extract_iso_to_temp() {
    local iso_path="$1"
    local temp_dir="$2"
    
    log_info "Audio-Remaster: Extrahiere nach: $temp_dir"
    
    # Loop-Mount verwenden (Service läuft als root, mount sollte funktionieren)
    local mount_point="${temp_dir}_mount"
    mkdir -p "$mount_point"
    
    log_info "Audio-Remaster: Mounte ISO mit /bin/mount..."
    
    # Verwende absoluten Pfad zu mount und capture stderr
    local mount_output=$(/bin/mount -o loop,ro "$iso_path" "$mount_point" 2>&1)
    local mount_result=$?
    
    if [[ $mount_result -eq 0 ]]; then
        log_info "Audio-Remaster: ISO erfolgreich gemountet, kopiere Dateien..."
        
        # Kopiere alle Dateien
        local copy_output=$(cp -r "$mount_point"/* "$temp_dir/" 2>&1)
        local copy_result=$?
        
        if [[ $copy_result -eq 0 ]]; then
            /bin/umount "$mount_point"
            rmdir "$mount_point"
            log_info "Audio-Remaster: Extraktion erfolgreich ($(ls -1 "$temp_dir" | wc -l) Dateien kopiert)"
            return 0
        else
            log_error "Audio-Remaster: Fehler beim Kopieren: $copy_output"
            /bin/umount "$mount_point" 2>/dev/null
            rmdir "$mount_point" 2>/dev/null
            return 1
        fi
    else
        log_error "Audio-Remaster: Mount fehlgeschlagen (Exit: $mount_result): $mount_output"
        rmdir "$mount_point" 2>/dev/null
        return 1
    fi
}

# Funktion: Aktualisiere MP3-Tags aus MusicBrainz-Daten
# Parameter:
#   $1 = source_dir (MP3s aus ISO)
#   $2 = target_dir (Ziel für getaggte MP3s)
#   $3 = mb_data (MusicBrainz JSON)
#   $4 = cover_file (optional)
# Rückgabe: 0 bei Erfolg
update_mp3_tags_from_musicbrainz() {
    local source_dir="$1"
    local target_dir="$2"
    local mb_data="$3"
    local cover_file="$4"
    
    # Prüfe ob eyeD3 oder id3v2 verfügbar
    local tag_tool=""
    if command -v eyeD3 >/dev/null 2>&1; then
        tag_tool="eyeD3"
    elif command -v id3v2 >/dev/null 2>&1; then
        tag_tool="id3v2"
    else
        log_info "Audio-Remaster: Kein ID3-Tagging-Tool gefunden (eyeD3/id3v2)"
        return 1
    fi
    
    # Extrahiere Album-Metadaten
    local artist=$(echo "$mb_data" | jq -r '."artist-credit"[0].name // "Unknown Artist"')
    local album=$(echo "$mb_data" | jq -r '.title // "Unknown Album"')
    local year=$(echo "$mb_data" | jq -r '.date // "" | split("-")[0]')
    
    # Hole Track-Liste
    local tracks=$(echo "$mb_data" | jq -r '.media[0].tracks')
    local track_count=$(echo "$tracks" | jq 'length')
    
    # Finde alle MP3s (sortiert) - nutze readarray für korrekte Handhabung von Leerzeichen
    local mp3_files=()
    while IFS= read -r -d '' file; do
        mp3_files+=("$file")
    done < <(find "$source_dir" -name "*.mp3" -type f -print0 | sort -z)
    
    local mp3_count=${#mp3_files[@]}
    
    if [[ $mp3_count -eq 0 ]]; then
        log_info "Audio-Remaster: Keine MP3-Dateien in ISO gefunden"
        return 1
    fi
    
    log_info "Audio-Remaster: Gefunden: $mp3_count MP3s, MusicBrainz: $track_count Tracks"
    
    # Tagge jede MP3 und benenne um
    local track_num=1
    for mp3_file in "${mp3_files[@]}"; do
        # Hole Track-Titel aus MusicBrainz
        local track_title=""
        if [[ $track_num -le $track_count ]]; then
            track_title=$(echo "$tracks" | jq -r ".[$(($track_num - 1))].title // \"Track $track_num\"")
        else
            track_title="Track $track_num"
        fi
        
        # Erstelle sauberen Dateinamen: "Artist - Title.mp3"
        # Säubere BEIDE Komponenten (artist + title) für sichere Pfade
        local clean_artist=$(echo "$artist" | sed 's/[^a-zA-Z0-9 ()!_-]/_/g' | sed 's/  */ /g')
        local clean_title=$(echo "$track_title" | sed 's/[^a-zA-Z0-9 ()!_-]/_/g' | sed 's/  */ /g')
        local new_filename="${clean_artist} - ${clean_title}.mp3"
        local target_file="$target_dir/$new_filename"
        
        # Kopiere MP3
        cp "$mp3_file" "$target_file"
        
        # Tagge mit eyeD3 oder id3v2
        if [[ "$tag_tool" == "eyeD3" ]]; then
            eyeD3 --quiet \
                --artist "$artist" \
                --album-artist "$artist" \
                --album "$album" \
                --title "$track_title" \
                --track "$track_num" \
                --track-total "$track_count" \
                ${year:+--release-year "$year"} \
                "$target_file" >/dev/null 2>&1
            
            # Cover einbetten
            if [[ -n "$cover_file" ]] && [[ -f "$cover_file" ]]; then
                eyeD3 --quiet --add-image "${cover_file}:FRONT_COVER" "$target_file" >/dev/null 2>&1
            fi
        else
            # id3v2 (hat kein --album-artist, verwende --TPE2 für AlbumArtist)
            id3v2 \
                --artist "$artist" \
                --album "$album" \
                --song "$track_title" \
                --track "$track_num" \
                --TPE2 "$artist" \
                ${year:+--year "$year"} \
                "$target_file" >/dev/null 2>&1
        fi
        
        log_info "Audio-Remaster: Getaggt: $track_num. $track_title -> $new_filename"
        track_num=$((track_num + 1))
    done
    
    # Kopiere Cover als folder.jpg
    if [[ -n "$cover_file" ]] && [[ -f "$cover_file" ]]; then
        cp "$cover_file" "$target_dir/folder.jpg"
    fi
    
    return 0
}

# Funktion: Erstelle neue ISO aus getaggten MP3s
# Parameter:
#   $1 = source_dir (getaggte MP3s)
#   $2 = output_iso
# Rückgabe: 0 bei Erfolg
rebuild_audio_iso() {
    local source_dir="$1"
    local output_iso="$2"
    
    # Prüfe genisoimage oder mkisofs
    local iso_tool=""
    if command -v genisoimage >/dev/null 2>&1; then
        iso_tool="genisoimage"
    elif command -v mkisofs >/dev/null 2>&1; then
        iso_tool="mkisofs"
    else
        log_info "Audio-Remaster: Kein ISO-Tool gefunden (genisoimage/mkisofs)"
        return 1
    fi
    
    # Prüfe ob Quellverzeichnis Dateien enthält
    if [[ -z "$(ls -A "$source_dir" 2>/dev/null)" ]]; then
        log_info "Audio-Remaster: Quellverzeichnis ist leer: $source_dir"
        return 1
    fi
    
    # Erstelle ISO mit UDF + Joliet (maximale Kompatibilität)
    local iso_errors=$(mktemp)
    if $iso_tool -r -J -o "$output_iso" "$source_dir" 2>"$iso_errors"; then
        log_info "Audio-Remaster: ISO erfolgreich erstellt: $(basename "$output_iso")"
        rm -f "$iso_errors"
        return 0
    else
        log_error "Audio-Remaster: ISO-Erstellung fehlgeschlagen: $(cat "$iso_errors")"
        rm -f "$iso_errors"
        return 1
    fi
}

# Funktion: Erstelle .nfo für Audio-CD
# Parameter:
#   $1 = iso_path
#   $2 = artist
#   $3 = album
#   $4 = year
#   $5 = track_count
#   $6 = cover_file (optional)
create_audio_nfo() {
    local iso_path="$1"
    local artist="$2"
    local album="$3"
    local year="$4"
    local track_count="${5:-0}"
    local cover_file="$6"
    
    local nfo_file="${iso_path%.iso}.nfo"
    local thumb_file="${iso_path%.iso}-thumb.jpg"
    
    # Erstelle .nfo (mit Feldern die das Frontend erwartet)
    cat > "$nfo_file" <<EOF
ARTIST=$artist
ALBUM=$album
TITLE=$album
DATE=$year
YEAR=$year
TRACKS=$track_count
TYPE=audio-cd
EOF
    
    # Kopiere Cover
    if [[ -n "$cover_file" ]] && [[ -f "$cover_file" ]]; then
        cp "$cover_file" "$thumb_file"
    fi
    
    log_info "Audio-Remaster: .nfo erstellt"
}

# Funktion: Hole MusicBrainz Release-Details
# Parameter: $1 = release_id
# Rückgabe: JSON mit Release-Details
get_musicbrainz_release_details() {
    local release_id="$1"
    
    # Nutze API-Konstante statt hardcoded URL
    local url="${MUSICBRAINZ_API_BASE_URL}/release/${release_id}?fmt=json&inc=artists+recordings+artist-credits"
    
    # Füge User-Agent Header hinzu (MusicBrainz API-Richtlinie)
    local response=$(curl -s -f -m 10 -H "User-Agent: ${MUSICBRAINZ_USER_AGENT}" "$url" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        echo "$response"
        return 0
    else
        return 1
    fi
}

# Funktion: Cleanup temporäre Verzeichnisse
# Parameter: $1, $2 = temp_dirs
cleanup_remaster_temp() {
    local temp1="$1"
    local temp2="$2"
    
    [[ -d "$temp1" ]] && rm -rf "$temp1"
    [[ -d "$temp2" ]] && rm -rf "$temp2"
    
    # Cleanup Mount-Points (falls vorhanden)
    [[ -d "${temp1}_mount" ]] && rmdir "${temp1}_mount" 2>/dev/null
}

################################################################################
# ENDE lib-cd-metadata.sh
################################################################################
