#!/bin/bash
################################################################################
# disk2iso v1.2.0 - TMDB Metadata Provider
# Filepath: lib/libtmdb.sh
#
# Beschreibung:
#   TMDB-Provider für DVD/Blu-ray Metadata
#   - Registriert sich beim Metadata-Framework
#   - Implementiert Query/Parse/Apply für TMDB API
#
# Version: 1.2.0
# Datum: 20.01.2026
################################################################################

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================
# Globale Variable für Modulname
readonly MODULE_NAME_TMDB="tmdb"
# Globale Variable für Verfügbarkeit
TMDB_SUPPORT=false

# ===========================================================================
# check_dependencies_tmdb
# ---------------------------------------------------------------------------
# Funktion.: Prüfe alle TMDB Provider-Abhängigkeiten (Modul-Dateien, 
# .........  kritische und optionale Software), lädt bei erfolgreicher 
# .........  Prüfung die Sprachdatei für das Modul.
# Parameter: keine
# Rückgabe.: 0 = Verfügbar (Provider nutzbar)
# .........  1 = Nicht verfügbar (Provider deaktiviert)
# Extras...: Setzt TMDB_SUPPORT=true bei erfolgreicher Prüfung
# ===========================================================================
check_dependencies_tmdb() {

    #-- Alle Modul Abhängigkeiten prüfen -------------------------------------
    check_module_dependencies "$MODULE_NAME_TMDB" || return 1

    #-- Lade API-Konfiguration aus INI ---------------------------------------
    load_api_config_tmdb || return 1

    #-- Setze Verfügbarkeit -------------------------------------------------
    TMDB_SUPPORT=true
    
    #-- Abhängigkeiten erfüllt ----------------------------------------------
    log_info "$MSG_TMDB_SUPPORT_AVAILABLE"
    return 0
}

# ============================================================================
# TMDB API CONFIGURATION
# ============================================================================

# ===========================================================================
# load_api_config_tmdb
# ---------------------------------------------------------------------------
# Funktion.: Lade TMDB API-Konfiguration aus libtmdb.ini [api] Sektion
# .........  und setze Defaults falls INI-Werte fehlen
# Parameter: keine
# Rückgabe.: 0 = Erfolgreich geladen
# Setzt....: TMDB_API_BASE_URL, TMDB_IMAGE_BASE_URL, TMDB_USER_AGENT,
# .........  TMDB_TIMEOUT, TMDB_LANGUAGE (global)
# Nutzt....: get_ini_value() aus libconfig.sh
# Hinweis..: Wird von check_dependencies_tmdb() aufgerufen, um Werte zu
# .........  initialisieren bevor das Modul verwendet wird
# ===========================================================================
load_api_config_tmdb() {
    local ini_file="${SCRIPT_DIR}/conf/libtmdb.ini"
    
    # Lese API-Konfiguration mit get_ini_value() aus libconfig.sh (falls INI existiert)
    local base_url image_base_url user_agent timeout language
    
    if [[ -f "$ini_file" ]]; then
        base_url=$(get_ini_value "$ini_file" "api" "base_url")
        image_base_url=$(get_ini_value "$ini_file" "api" "image_base_url")
        user_agent=$(get_ini_value "$ini_file" "api" "user_agent")
        timeout=$(get_ini_value "$ini_file" "api" "timeout")
        language=$(get_ini_value "$ini_file" "api" "language")
    fi
    
    # Setze Variablen mit Defaults (INI-Werte überschreiben Defaults)
    TMDB_API_BASE_URL="${base_url:-https://api.themoviedb.org/3}"
    TMDB_IMAGE_BASE_URL="${image_base_url:-https://image.tmdb.org/t/p/w500}"
    TMDB_USER_AGENT="${user_agent:-disk2iso/1.2.0}"
    TMDB_TIMEOUT="${timeout:-10}"
    TMDB_LANGUAGE="${language:-de-DE}"
    
    log_info "TMDB: API-Konfiguration geladen (Base: $TMDB_API_BASE_URL)"
    return 0
}

# ============================================================================
# CACHE MANAGEMENT
# ============================================================================

TMDB_CACHE_DIR=""
TMDB_THUMBS_DIR=""

# Funktion: Initialisiere TMDB Cache-Verzeichnisse
tmdb_init_cache() {
    if [[ -n "$TMDB_CACHE_DIR" ]]; then
        return 0  # Bereits initialisiert
    fi
    
    TMDB_CACHE_DIR=$(metadata_get_cache_dir "tmdb") || return 1
    TMDB_THUMBS_DIR="${TMDB_CACHE_DIR}/thumbs"
    
    mkdir -p "$TMDB_THUMBS_DIR" 2>/dev/null
    
    log_info "TMDB: Cache initialisiert: $TMDB_CACHE_DIR"
    return 0
}

# ============================================================================
# PROVIDER IMPLEMENTATION - QUERY
# ============================================================================

# Funktion: TMDB Query (für Metadata Framework)
# Parameter: $1 = disc_type ("dvd-video" oder "bd-video")
#            $2 = search_term (z.B. "Movie Title")
#            $3 = disc_id (für Query-Datei)
#            $4 = media_type (optional: "movie" oder "tv", auto-detect wenn leer)
# Rückgabe: 0 = Query erfolgreich, 1 = Fehler
tmdb_query() {
    local disc_type="$1"
    local search_term="$2"
    local disc_id="$3"
    local media_type="${4:-}"
    
    # Prüfe API-Key
    if [[ -z "$TMDB_API_KEY" ]]; then
        log_error "TMDB: API-Key nicht konfiguriert"
        return 1
    fi
    
    tmdb_init_cache || return 1
    
    log_info "TMDB: Suche nach '$search_term'"
    
    # Auto-detect Media-Type falls nicht übergeben
    if [[ -z "$media_type" ]]; then
        if [[ "$search_term" =~ season|staffel|s[0-9]{2} ]]; then
            media_type="tv"
            log_info "TMDB: Erkannt als TV-Serie"
        else
            media_type="movie"
            log_info "TMDB: Erkannt als Film"
        fi
    fi
    
    # URL-Encode des Suchbegriffs
    local encoded_query=$(tmdb_url_encode "$search_term")
    
    # API-Anfrage
    local url
    if [[ "$media_type" == "tv" ]]; then
        url="${TMDB_API_BASE_URL}/search/tv?api_key=${TMDB_API_KEY}&language=${TMDB_LANGUAGE}&query=${encoded_query}&page=1"
    else
        url="${TMDB_API_BASE_URL}/search/movie?api_key=${TMDB_API_KEY}&language=${TMDB_LANGUAGE}&query=${encoded_query}&page=1"
    fi
    
    log_info "TMDB: API-Request..."
    
    local response=$(curl -s -f -m "${TMDB_TIMEOUT}" -H "User-Agent: ${TMDB_USER_AGENT}" "$url" 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        log_error "TMDB: API-Request fehlgeschlagen"
        return 1
    fi
    
    # Prüfe Anzahl Ergebnisse
    local result_count=$(echo "$response" | jq -r '.results | length' 2>/dev/null || echo "0")
    
    if [[ "$result_count" -eq 0 ]]; then
        log_info "TMDB: Keine Treffer für '$search_term'"
        return 1
    fi
    
    log_info "TMDB: $result_count Treffer gefunden"
    
    # Schreibe .tmdbquery Datei (für Frontend-API)
    local output_base
    output_base=$(get_type_subfolder "$disc_type" 2>/dev/null) || output_base="${OUTPUT_DIR}"
    
    local tmdbquery_file="${output_base}/${disc_id}_tmdb.tmdbquery"
    
    # Erweitere JSON mit Metadaten
    echo "$response" | jq -c "{
        provider: \"tmdb\",
        media_type: \"$media_type\",
        disc_type: \"$disc_type\",
        disc_id: \"$disc_id\",
        search_query: \"$search_term\",
        result_count: $result_count,
        results: .results
    }" > "$tmdbquery_file"
    
    chmod 644 "$tmdbquery_file" 2>/dev/null
    
    log_info "TMDB: Query-Datei erstellt: $(basename "$tmdbquery_file")"
    
    # Befülle Cache mit .nfo Dateien
    tmdb_populate_cache "$response" "$disc_id" "$media_type"
    
    return 0
}

# ============================================================================
# PROVIDER IMPLEMENTATION - PARSE
# ============================================================================

# Funktion: Parse TMDB Selection (für Metadata Framework)
# Parameter: $1 = selected_index (aus .tmdbselect)
#            $2 = query_file (.tmdbquery Datei)
#            $3 = select_file (.tmdbselect Datei)
# Rückgabe: 0 = Parse erfolgreich, setzt globale Variablen
# Setzt: dvd_title, dvd_year
tmdb_parse_selection() {
    local selected_index="$1"
    local query_file="$2"
    local select_file="$3"
    
    # Lese Query-Response
    local tmdb_json
    local media_type
    
    tmdb_json=$(jq -r '.results' "$query_file" 2>/dev/null)
    media_type=$(jq -r '.media_type' "$query_file" 2>/dev/null)
    
    if [[ -z "$tmdb_json" ]] || [[ "$tmdb_json" == "null" ]]; then
        log_error "TMDB: Query-Datei ungültig"
        return 1
    fi
    
    # Extrahiere Metadata aus gewähltem Result
    local title
    local year
    
    # TMDB hat unterschiedliche Felder für movies/tv
    if [[ "$media_type" == "tv" ]]; then
        title=$(echo "$tmdb_json" | jq -r ".[$selected_index].name // \"Unknown Title\"" 2>/dev/null)
        year=$(echo "$tmdb_json" | jq -r ".[$selected_index].first_air_date // \"\"" 2>/dev/null | cut -d- -f1)
    else
        title=$(echo "$tmdb_json" | jq -r ".[$selected_index].title // \"Unknown Title\"" 2>/dev/null)
        year=$(echo "$tmdb_json" | jq -r ".[$selected_index].release_date // \"\"" 2>/dev/null | cut -d- -f1)
    fi
    
    # Validierung
    if [[ -z "$title" ]] || [[ "$title" == "null" ]]; then
        title="Unknown Title"
    fi
    
    if [[ -z "$year" ]] || [[ "$year" == "null" ]]; then
        year="0000"
    fi
    
    # Setze globale Variablen (für DVD/BD Workflow)
    dvd_title="$title"
    dvd_year="$year"
    
    log_info "TMDB: Metadata ausgewählt: $dvd_title ($dvd_year)"
    
    # Update disc_label
    tmdb_apply_selection "$title" "$year"
    
    return 0
}

# ============================================================================
# PROVIDER IMPLEMENTATION - APPLY
# ============================================================================

# Funktion: Wende TMDB-Auswahl auf disc_label an
# Parameter: $1 = title
#            $2 = year
# Setzt: disc_label global
tmdb_apply_selection() {
    local title="$1"
    local year="$2"
    
    # Sanitize
    local safe_title=$(metadata_sanitize_filename "$title")
    
    # Update disc_label
    disc_label="${safe_title}_${year}"
    
    log_info "TMDB: Neues disc_label: $disc_label"
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Funktion: URL-Encode String
# Parameter: $1 = String
# Rückgabe: URL-encoded String
tmdb_url_encode() {
    local string="$1"
    
    # Einfaches URL-Encoding (Leerzeichen → %20)
    echo "$string" | sed 's/ /%20/g' | sed 's/&/%26/g'
}

# Funktion: Extrahiere Filmtitel aus disc_label
# Parameter: $1 = disc_label (z.B. "mission_impossible_2023")
# Rückgabe: Suchbarer Titel (z.B. "Mission Impossible")
tmdb_extract_title_from_label() {
    local label="$1"
    
    # Entferne Jahr am Ende (4 Ziffern)
    label=$(echo "$label" | sed 's/_[0-9]\{4\}$//')
    
    # Ersetze Underscores durch Leerzeichen
    label=$(echo "$label" | tr '_' ' ')
    
    # Erste Buchstaben groß (Title Case)
    label=$(echo "$label" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
    
    echo "$label"
}

# Funktion: Befülle Cache mit .nfo Dateien
# Parameter: $1 = TMDB Response (JSON)
#            $2 = disc_id (für Dateinamen)
#            $3 = media_type ("movie" oder "tv")
tmdb_populate_cache() {
    local tmdb_json="$1"
    local disc_id="$2"
    local media_type="$3"
    
    tmdb_init_cache || return 1
    
    local result_count=$(echo "$tmdb_json" | jq -r '.results | length' 2>/dev/null || echo "0")
    
    if [[ "$result_count" -eq 0 ]]; then
        return 0
    fi
    
    log_info "TMDB: Cache $result_count Ergebnisse..."
    
    local cached=0
    for i in $(seq 0 $((result_count - 1))); do
        local tmdb_id=$(echo "$tmdb_json" | jq -r ".results[$i].id // \"unknown\"" 2>/dev/null)
        
        local title
        local date
        local poster_path
        
        if [[ "$media_type" == "tv" ]]; then
            title=$(echo "$tmdb_json" | jq -r ".results[$i].name // \"Unknown\"" 2>/dev/null)
            date=$(echo "$tmdb_json" | jq -r ".results[$i].first_air_date // \"\"" 2>/dev/null)
        else
            title=$(echo "$tmdb_json" | jq -r ".results[$i].title // \"Unknown\"" 2>/dev/null)
            date=$(echo "$tmdb_json" | jq -r ".results[$i].release_date // \"\"" 2>/dev/null)
        fi
        
        poster_path=$(echo "$tmdb_json" | jq -r ".results[$i].poster_path // \"\"" 2>/dev/null)
        local overview=$(echo "$tmdb_json" | jq -r ".results[$i].overview // \"\"" 2>/dev/null)
        
        # Erstelle .nfo Datei
        local nfo_file="${TMDB_CACHE_DIR}/${disc_id}_${i}_${tmdb_id}.nfo"
        
        cat > "$nfo_file" <<EOF
SEARCH_RESULT_FOR=${disc_id}
TMDB_ID=${tmdb_id}
MEDIA_TYPE=${media_type}
TITLE=${title}
DATE=${date}
POSTER_PATH=${poster_path}
OVERVIEW=${overview}
TYPE=video
CACHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
CACHE_VERSION=1.0
EOF
        
        # Lade Poster-Thumbnail
        if [[ -n "$poster_path" ]] && [[ "$poster_path" != "null" ]]; then
            local thumb_file="${TMDB_THUMBS_DIR}/${disc_id}_${i}_${tmdb_id}-thumb.jpg"
            local poster_url="${TMDB_IMAGE_BASE_URL}${poster_path}"
            
            if curl -s -f -L -m 5 -o "$thumb_file" "$poster_url" 2>/dev/null; then
                chmod 644 "$thumb_file" 2>/dev/null
            fi
        fi
        
        cached=$((cached + 1))
    done
    
    log_info "TMDB: $cached von $result_count Ergebnisse gecacht"
}

# ============================================================================
# PROVIDER REGISTRATION
# ============================================================================

# Auto-Register beim Laden (wenn Metadata-Framework verfügbar)
if declare -f metadata_register_provider >/dev/null 2>&1; then
    metadata_register_provider "tmdb" "dvd-video,bd-video" \
        "tmdb_query" \
        "tmdb_parse_selection" \
        "tmdb_apply_selection"
fi

################################################################################
# ENDE lib-tmdb.sh
################################################################################
