#!/bin/bash
################################################################################
# disk2iso v1.2.0 - MusicBrainz Metadata Provider
# Filepath: lib/libmusicbrainz.sh
#
# Beschreibung:
#   MusicBrainz-Provider für Audio-CD Metadata
#   - Registriert sich beim Metadata-Framework
#   - Implementiert Query/Parse/Apply für MusicBrainz API
#
# Version: 1.2.0
# Datum: 20.01.2026
################################################################################

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================
# Globale Variable für Modulname
readonly MODULE_NAME_MUSICBRAINZ="musicbrainz"
# Globale Variable für Verfügbarkeit
MUSICBRAINZ_SUPPORT=false

# ===========================================================================
# check_dependencies_musicbrainz
# ---------------------------------------------------------------------------
# Funktion.: Prüfe alle MusicBrainz Provider-Abhängigkeiten (Modul-Dateien, 
# .........  kritische und optionale Software), lädt bei erfolgreicher 
# .........  Prüfung die Sprachdatei für das Modul.
# Parameter: keine
# Rückgabe.: 0 = Verfügbar (Provider nutzbar)
# .........  1 = Nicht verfügbar (Provider deaktiviert)
# Extras...: Setzt MUSICBRAINZ_SUPPORT=true bei erfolgreicher Prüfung
# ===========================================================================
check_dependencies_musicbrainz() {

    #-- Alle Modul Abhängigkeiten prüfen -------------------------------------
    check_module_dependencies "$MODULE_NAME_MUSICBRAINZ" || return 1

    #-- Lade API-Konfiguration aus INI ---------------------------------------
    load_api_config_musicbrainz || return 1

    #-- Setze Verfügbarkeit -------------------------------------------------
    MUSICBRAINZ_SUPPORT=true
    
    #-- Abhängigkeiten erfüllt ----------------------------------------------
    log_info "$MSG_MUSICBRAINZ_SUPPORT_AVAILABLE"
    return 0
}

# ============================================================================
# MUSICBRAINZ API CONFIGURATION
# ============================================================================

# ===========================================================================
# load_api_config_musicbrainz
# ---------------------------------------------------------------------------
# Funktion.: Lade MusicBrainz API-Konfiguration aus libmusicbrainz.ini
# .........  [api] Sektion und setze Defaults falls INI-Werte fehlen
# Parameter: keine
# Rückgabe.: 0 = Erfolgreich geladen
# Setzt....: MUSICBRAINZ_API_BASE_URL, COVERART_API_BASE_URL,
# .........  MUSICBRAINZ_USER_AGENT, MUSICBRAINZ_TIMEOUT (global)
# Nutzt....: get_ini_value() aus libconfig.sh
# Hinweis..: Wird von check_dependencies_musicbrainz() aufgerufen, um Werte
# .........  zu initialisieren bevor das Modul verwendet wird
# ===========================================================================
load_api_config_musicbrainz() {
    local ini_file="${SCRIPT_DIR}/conf/libmusicbrainz.ini"
    
    # Lese API-Konfiguration mit get_ini_value() aus libconfig.sh (falls INI existiert)
    local base_url coverart_base_url user_agent timeout
    
    if [[ -f "$ini_file" ]]; then
        base_url=$(get_ini_value "$ini_file" "api" "base_url")
        coverart_base_url=$(get_ini_value "$ini_file" "api" "coverart_base_url")
        user_agent=$(get_ini_value "$ini_file" "api" "user_agent")
        timeout=$(get_ini_value "$ini_file" "api" "timeout")
    fi
    
    # Setze Variablen mit Defaults (INI-Werte überschreiben Defaults)
    MUSICBRAINZ_API_BASE_URL="${base_url:-https://musicbrainz.org/ws/2}"
    COVERART_API_BASE_URL="${coverart_base_url:-https://coverartarchive.org}"
    MUSICBRAINZ_USER_AGENT="${user_agent:-disk2iso/1.2.0}"
    MUSICBRAINZ_TIMEOUT="${timeout:-10}"
    
    log_info "MusicBrainz: API-Konfiguration geladen (Base: $MUSICBRAINZ_API_BASE_URL)"
    return 0
}

# ============================================================================
# CACHE MANAGEMENT
# ============================================================================

MUSICBRAINZ_CACHE_DIR=""
MUSICBRAINZ_COVERS_DIR=""

# Funktion: Initialisiere MusicBrainz Cache-Verzeichnisse
musicbrainz_init_cache() {
    if [[ -n "$MUSICBRAINZ_CACHE_DIR" ]]; then
        return 0  # Bereits initialisiert
    fi
    
    MUSICBRAINZ_CACHE_DIR=$(metadata_get_cache_dir "musicbrainz") || return 1
    MUSICBRAINZ_COVERS_DIR="${MUSICBRAINZ_CACHE_DIR}/covers"
    
    mkdir -p "$MUSICBRAINZ_COVERS_DIR" 2>/dev/null
    
    log_info "MusicBrainz: Cache initialisiert: $MUSICBRAINZ_CACHE_DIR"
    return 0
}

# ============================================================================
# PROVIDER IMPLEMENTATION - QUERY
# ============================================================================

# Funktion: MusicBrainz Query (für Metadata Framework)
# Parameter: $1 = disc_type ("audio-cd")
#            $2 = search_term (z.B. "Artist - Album")
#            $3 = disc_id (für Query-Datei)
#            $4 = toc (optional, CD Table of Contents)
# Rückgabe: 0 = Query erfolgreich, 1 = Fehler
musicbrainz_query() {
    local disc_type="$1"
    local search_term="$2"
    local disc_id="$3"
    local toc="${4:-}"
    
    musicbrainz_init_cache || return 1
    
    log_info "MusicBrainz: Suche nach '$search_term'"
    
    # Parse search_term (Format: "Artist - Album" oder nur "Album")
    local artist=""
    local album=""
    
    if [[ "$search_term" =~ ^(.+)[[:space:]]*-[[:space:]]*(.+)$ ]]; then
        artist="${BASH_REMATCH[1]}"
        album="${BASH_REMATCH[2]}"
    else
        album="$search_term"
    fi
    
    # Baue Query
    local query_parts=()
    [[ -n "$artist" ]] && query_parts+=("artist:${artist}")
    [[ -n "$album" ]] && query_parts+=("release:${album}")
    
    if [[ ${#query_parts[@]} -eq 0 ]]; then
        log_error "MusicBrainz: Keine Query-Parameter"
        return 1
    fi
    
    local query=$(IFS=' AND '; echo "${query_parts[*]}")
    local encoded_query=$(musicbrainz_url_encode "$query")
    
    # API-Anfrage
    local url="${MUSICBRAINZ_API_BASE_URL}/release/?query=${encoded_query}&fmt=json&limit=10&inc=artists+labels+recordings+media"
    
    log_info "MusicBrainz: API-Request..."
    
    local response=$(curl -s -f -m "${MUSICBRAINZ_TIMEOUT}" -H "User-Agent: ${MUSICBRAINZ_USER_AGENT}" "$url" 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        log_error "MusicBrainz: API-Request fehlgeschlagen"
        return 1
    fi
    
    # Prüfe Anzahl Ergebnisse
    local result_count=$(echo "$response" | jq -r '.releases | length' 2>/dev/null || echo "0")
    
    if [[ "$result_count" -eq 0 ]]; then
        log_info "MusicBrainz: Keine Treffer für '$search_term'"
        return 1
    fi
    
    log_info "MusicBrainz: $result_count Treffer gefunden"
    
    # Schreibe .mbquery Datei (für Frontend-API)
    local output_base
    output_base=$(get_type_subfolder "$disc_type" 2>/dev/null) || output_base="${OUTPUT_DIR}"
    
    local mbquery_file="${output_base}/${disc_id}_musicbrainz.mbquery"
    
    # Erweitere JSON mit Metadaten
    echo "$response" | jq -c "{
        provider: \"musicbrainz\",
        disc_type: \"$disc_type\",
        disc_id: \"$disc_id\",
        search_query: \"$search_term\",
        result_count: $result_count,
        releases: .releases
    }" > "$mbquery_file"
    
    chmod 644 "$mbquery_file" 2>/dev/null
    
    log_info "MusicBrainz: Query-Datei erstellt: $(basename "$mbquery_file")"
    
    # Befülle Cache mit .nfo Dateien
    musicbrainz_populate_cache "$response" "$disc_id"
    
    return 0
}

# ============================================================================
# PROVIDER IMPLEMENTATION - PARSE
# ============================================================================

# Funktion: Parse MusicBrainz Selection (für Metadata Framework)
# Parameter: $1 = selected_index (aus .mbselect)
#            $2 = query_file (.mbquery Datei)
#            $3 = select_file (.mbselect Datei)
# Rückgabe: 0 = Parse erfolgreich, setzt globale Variablen
# Setzt: cd_artist, cd_album, cd_year
musicbrainz_parse_selection() {
    local selected_index="$1"
    local query_file="$2"
    local select_file="$3"
    
    # Lese Query-Response
    local mb_json
    mb_json=$(jq -r '.releases' "$query_file" 2>/dev/null)
    
    if [[ -z "$mb_json" ]] || [[ "$mb_json" == "null" ]]; then
        log_error "MusicBrainz: Query-Datei ungültig"
        return 1
    fi
    
    # Extrahiere Metadata aus gewähltem Release
    local artist
    local album
    local year
    
    artist=$(echo "$mb_json" | jq -r ".[$selected_index][\"artist-credit\"][0].name // \"Unknown Artist\"" 2>/dev/null)
    album=$(echo "$mb_json" | jq -r ".[$selected_index].title // \"Unknown Album\"" 2>/dev/null)
    year=$(echo "$mb_json" | jq -r ".[$selected_index].date // \"\"" 2>/dev/null | cut -d- -f1)
    
    # Validierung
    if [[ -z "$artist" ]] || [[ "$artist" == "null" ]]; then
        artist="Unknown Artist"
    fi
    
    if [[ -z "$album" ]] || [[ "$album" == "null" ]]; then
        album="Unknown Album"
    fi
    
    if [[ -z "$year" ]] || [[ "$year" == "null" ]]; then
        year="0000"
    fi
    
    # Setze globale Variablen (für Audio-CD Workflow)
    cd_artist="$artist"
    cd_album="$album"
    cd_year="$year"
    
    log_info "MusicBrainz: Metadata ausgewählt: $cd_artist - $cd_album ($cd_year)"
    
    # Update disc_label
    musicbrainz_apply_selection "$artist" "$album" "$year"
    
    return 0
}

# ============================================================================
# PROVIDER IMPLEMENTATION - APPLY
# ============================================================================

# Funktion: Wende MusicBrainz-Auswahl auf disc_label an
# Parameter: $1 = artist
#            $2 = album
#            $3 = year
# Setzt: disc_label global
musicbrainz_apply_selection() {
    local artist="$1"
    local album="$2"
    local year="$3"
    
    # Sanitize
    local safe_artist=$(metadata_sanitize_filename "$artist")
    local safe_album=$(metadata_sanitize_filename "$album")
    
    # Update disc_label
    disc_label="${safe_artist}_${safe_album}_${year}"
    
    log_info "MusicBrainz: Neues disc_label: $disc_label"
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Funktion: URL-Encode String
# Parameter: $1 = String
# Rückgabe: URL-encoded String
musicbrainz_url_encode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for ((pos=0; pos<strlen; pos++)); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="$c" ;;
            * ) printf -v o '%%%02X' "'$c" ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Funktion: Befülle Cache mit .nfo Dateien
# Parameter: $1 = MusicBrainz Response (JSON)
#            $2 = disc_id (für Dateinamen)
musicbrainz_populate_cache() {
    local mb_json="$1"
    local disc_id="$2"
    
    musicbrainz_init_cache || return 1
    
    local release_count=$(echo "$mb_json" | jq -r '.releases | length' 2>/dev/null || echo "0")
    
    if [[ "$release_count" -eq 0 ]]; then
        return 0
    fi
    
    log_info "MusicBrainz: Cache $release_count Releases..."
    
    local cached=0
    for i in $(seq 0 $((release_count - 1))); do
        local release_id=$(echo "$mb_json" | jq -r ".releases[$i].id // \"unknown\"" 2>/dev/null)
        local title=$(echo "$mb_json" | jq -r ".releases[$i].title // \"Unknown\"" 2>/dev/null)
        local artist=$(echo "$mb_json" | jq -r ".releases[$i][\"artist-credit\"][0].name // \"Unknown\"" 2>/dev/null)
        local date=$(echo "$mb_json" | jq -r ".releases[$i].date // \"\"" 2>/dev/null)
        local country=$(echo "$mb_json" | jq -r ".releases[$i].country // \"\"" 2>/dev/null)
        
        # Erstelle .nfo Datei
        local nfo_file="${MUSICBRAINZ_CACHE_DIR}/${disc_id}_${i}_${release_id:0:8}.nfo"
        
        cat > "$nfo_file" <<EOF
SEARCH_RESULT_FOR=${disc_id}
RELEASE_ID=${release_id}
TITLE=${title}
ARTIST=${artist}
DATE=${date}
COUNTRY=${country}
TYPE=audio-cd
CACHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
CACHE_VERSION=1.0
EOF
        
        # Lade Cover-Thumbnail
        local cover_file="${MUSICBRAINZ_COVERS_DIR}/${disc_id}_${i}_${release_id:0:8}-thumb.jpg"
        local cover_url="${COVERART_API_BASE_URL}/release/${release_id}/front-250"
        
        if curl -s -f -L -m 5 -o "$cover_file" "$cover_url" 2>/dev/null; then
            chmod 644 "$cover_file" 2>/dev/null
        fi
        
        cached=$((cached + 1))
    done
    
    log_info "MusicBrainz: $cached von $release_count Releases gecacht"
}

# ============================================================================
# PROVIDER REGISTRATION
# ============================================================================

# Auto-Register beim Laden (wenn Metadata-Framework verfügbar)
if declare -f metadata_register_provider >/dev/null 2>&1; then
    metadata_register_provider "musicbrainz" "audio-cd" \
        "musicbrainz_query" \
        "musicbrainz_parse_selection" \
        "musicbrainz_apply_selection"
fi

################################################################################
# ENDE lib-musicbrainz.sh
################################################################################
