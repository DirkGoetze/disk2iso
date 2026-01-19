#!/bin/bash
################################################################################
# disk2iso v1.2.0 - DVD/Blu-ray Metadata Library
# Filepath: lib/lib-dvd-metadata.sh
#
# Beschreibung:
#   TMDB-Integration für automatische Film-Metadaten und Cover
#   - search_tmdb_movie() - Film in TMDB suchen
#   - search_tmdb_tv() - TV-Serie in TMDB suchen
#   - get_tmdb_movie_details() - Details zu Film abrufen
#   - get_tmdb_tv_season_details() - Details zu TV-Staffel abrufen
#   - download_tmdb_poster() - Poster herunterladen
#   - create_dvd_metadata() - .nfo und -thumb.jpg erstellen
#
# Version: 1.2.0
# Datum: 13.01.2026
################################################################################

# ============================================================================
# TMDB API CONFIGURATION
# ============================================================================
readonly TMDB_API_BASE_URL="https://api.themoviedb.org/3"
readonly TMDB_IMAGE_BASE_URL="https://image.tmdb.org/t/p/w500"
readonly TMDB_USER_AGENT="disk2iso/1.2.0"

# ============================================================================
# CONFIGURATIONS KONSTANTEN
# ============================================================================
readonly METADATA_TMP_DIR="tmdb"
readonly METADATA_THUMBS_DIR="thumbs"

# ============================================================================
# Globale Variablen 
# ============================================================================
TMDB_CACHE_DIR=""
TMDB_THUMBS_DIR=""

# ===========================================================================
# init_tmdb_cache_dirs
# ---------------------------------------------------------------------------
# Funktion: Initialisiere TMDB Cache-Verzeichnisse (Lazy Initialization)
# ......... Nutzt ensure_subfolder() aus lib-folders.sh für konsistente 
# ......... Verzeichnisverwaltung
# Parameter: Keine
# Rückgabe: 0 = Erfolg, 1 = Fehler
# ===========================================================================
init_tmdb_cache_dirs() {
    if [[ -z "$TMDB_CACHE_DIR" ]]; then
        # Prüfen ob ensure_subfolder Funktion geladen ist
        if ! declare -f ensure_subfolder >/dev/null 2>&1; then
            log_error "TMDB: Fehler - lib-folders.sh nicht geladen"
            return 1
        fi

        # Metadaten Cache-Verzeichnis erstellen (relativ zu OUTPUT_DIR)
        TMDB_CACHE_DIR=$(ensure_subfolder ".temp/${METADATA_TMP_DIR}") || return 1
        log_info "TMDB: Cache-Verzeichnis initialisiert: $TMDB_CACHE_DIR"

        # Metadaten Thumbnails Verzeichnis erstellen
        TMDB_THUMBS_DIR=$(ensure_subfolder ".temp/${METADATA_TMP_DIR}/${METADATA_THUMBS_DIR}") || return 1 
        if [[ ! -d "$TMDB_THUMBS_DIR" ]]; then
            log_info "TMDB: Thumbnail-Verzeichnis ungültig: $TMDB_THUMBS_DIR"
            return 1
        fi
        log_info "TMDB: Thumbnail-Verzeichnis initialisiert: $TMDB_THUMBS_DIR"
    fi
    return 0
}

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

# Funktion: Prüfe DVD/Blu-ray Metadata Abhängigkeiten
# Rückgabe: 0 = Alle kritischen Tools OK, 1 = Kritische Tools fehlen
check_dvd_metadata_dependencies() {
    local missing_critical=()
    local missing_optional=()
    
    # Kritische Tools für Metadata-Funktionen
    command -v jq >/dev/null 2>&1 || missing_critical+=("jq")
    command -v curl >/dev/null 2>&1 || missing_critical+=("curl")
    
    if [[ ${#missing_critical[@]} -gt 0 ]]; then
        log_error "TMDB: Metadata-Support nicht verfügbar - fehlende Tools: ${missing_critical[*]}"
        log_error "TMDB: Installieren Sie: apt-get install ${missing_critical[*]}"
        return 1
    fi
    
    # Prüfe ob TMDB_API_KEY konfiguriert ist
    if [[ -z "$TMDB_API_KEY" ]]; then
        log_info "TMDB: API-Key nicht konfiguriert - Metadata-Funktionen deaktiviert"
        log_info "TMDB: Konfigurieren Sie TMDB_API_KEY in disk2iso.conf"
        return 1
    fi
    
    log_info "TMDB: Metadata-Support verfügbar"
    return 0
}

# ============================================================================
# TMDB API FUNCTIONS - MOVIES
# ============================================================================

# Funktion: Suche Film in TMDB API
# Parameter: $1 = Suchbegriff (Film-Titel)
# Rückgabe: JSON mit Suchergebnissen oder leerer String bei Fehler
search_tmdb_movie() {
    local query="$1"
    
    # Prüfe ob API-Key konfiguriert ist
    if [[ -z "$TMDB_API_KEY" ]]; then
        log_info "TMDB: API-Key nicht konfiguriert"
        return 1
    fi
    
    # URL-Encode des Suchbegriffs (Leerzeichen → %20)
    local encoded_query=$(echo "$query" | sed 's/ /%20/g')
    
    # API-Anfrage (language=de-DE für deutsche Titel)
    local url="${TMDB_API_BASE_URL}/search/movie?api_key=${TMDB_API_KEY}&language=de-DE&query=${encoded_query}&page=1"
    
    local response=$(curl -s -f -H "User-Agent: ${TMDB_USER_AGENT}" "$url" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        echo "$response"
        return 0
    else
        log_error "TMDB: Fehler bei der Film-Suche nach '$query'"
        return 1
    fi
}

# Funktion: Hole Details zu einem Film
# Parameter: $1 = TMDB Movie-ID
# Rückgabe: JSON mit Film-Details oder leerer String bei Fehler
get_tmdb_movie_details() {
    local movie_id="$1"
    
    if [[ -z "$TMDB_API_KEY" ]]; then
        return 1
    fi
    
    # API-Anfrage mit Credits (für Director)
    local url="${TMDB_API_BASE_URL}/movie/${movie_id}?api_key=${TMDB_API_KEY}&language=de-DE&append_to_response=credits"
    
    local response=$(curl -s -f -H "User-Agent: ${TMDB_USER_AGENT}" "$url" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        echo "$response"
        return 0
    else
        log_error "TMDB: Fehler beim Abrufen der Details für Movie-ID $movie_id"
        return 1
    fi
}

# ============================================================================
# TMDB API FUNCTIONS - TV SHOWS
# ============================================================================

# Funktion: Suche TV-Serie in TMDB API
# Parameter: $1 = Suchbegriff (Serien-Titel)
# Rückgabe: JSON mit Suchergebnissen oder leerer String bei Fehler
search_tmdb_tv() {
    local query="$1"
    
    if [[ -z "$TMDB_API_KEY" ]]; then
        log_info "TMDB: API-Key nicht konfiguriert"
        return 1
    fi
    
    local encoded_query=$(echo "$query" | sed 's/ /%20/g')
    local url="${TMDB_API_BASE_URL}/search/tv?api_key=${TMDB_API_KEY}&language=de-DE&query=${encoded_query}&page=1"
    
    local response=$(curl -s -f -H "User-Agent: ${TMDB_USER_AGENT}" "$url" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        echo "$response"
        return 0
    else
        log_error "TMDB: Fehler bei der TV-Suche nach '$query'"
        return 1
    fi
}

# Funktion: Hole Details zu einer TV-Staffel
# Parameter: $1 = TMDB TV-ID
#            $2 = Season-Nummer
# Rückgabe: JSON mit Season-Details oder leerer String bei Fehler
get_tmdb_tv_season_details() {
    local tv_id="$1"
    local season_number="$2"
    
    if [[ -z "$TMDB_API_KEY" ]]; then
        return 1
    fi
    
    local url="${TMDB_API_BASE_URL}/tv/${tv_id}/season/${season_number}?api_key=${TMDB_API_KEY}&language=de-DE"
    
    local response=$(curl -s -f -H "User-Agent: ${TMDB_USER_AGENT}" "$url" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        echo "$response"
        return 0
    else
        log_error "TMDB: Fehler beim Abrufen von TV-ID $tv_id Season $season_number"
        return 1
    fi
}

# ============================================================================
# COMMON FUNCTIONS
# ============================================================================

# Funktion: Lade Poster von TMDB herunter
# Parameter: $1 = Poster-Pfad (z.B. "/abc123.jpg")
#            $2 = Ziel-Dateiname (vollständiger Pfad)
# Rückgabe: 0 = Erfolg, 1 = Fehler
download_tmdb_poster() {
    local poster_path="$1"
    local output_file="$2"
    
    # Prüfe ob Poster-Pfad vorhanden
    if [[ -z "$poster_path" ]] || [[ "$poster_path" == "null" ]]; then
        log_info "TMDB: Kein Poster verfügbar"
        return 1
    fi
    
    local poster_url="${TMDB_IMAGE_BASE_URL}${poster_path}"
    
    # Lade Poster herunter
    if curl -s -f -H "User-Agent: ${TMDB_USER_AGENT}" "$poster_url" -o "$output_file" 2>/dev/null; then
        log_info "TMDB: Poster heruntergeladen: $(basename "$output_file")"
        return 0
    else
        log_error "TMDB: Fehler beim Herunterladen des Posters"
        return 1
    fi
}

# ============================================================================
# WEB API WRAPPER FUNCTIONS (für Python Flask Integration)
# ============================================================================

# Funktion: TMDB Suche mit JSON-Return für Web-API
# Parameter: $1 = Suchbegriff (Film/Serien-Titel)
#            $2 = Media-Type ("movie" oder "tv")
# Rückgabe: JSON-String mit {"success": true/false, "results": [...]}
# Diese Funktion wird vom Python Web-Interface aufgerufen
search_tmdb_json() {
    local title="$1"
    local media_type="$2"
    
    # Validierung
    if [[ -z "$title" ]]; then
        echo '{"success": false, "message": "Titel erforderlich"}'
        return 1
    fi
    
    if [[ -z "$TMDB_API_KEY" ]]; then
        echo '{"success": false, "message": "TMDB API Key nicht konfiguriert"}'
        return 1
    fi
    
    # URL-Encode des Titels
    local encoded_title=$(echo "$title" | sed 's/ /%20/g' | sed 's/&/%26/g')
    
    # Wähle Endpoint basierend auf media_type
    local url
    if [[ "$media_type" == "tv" ]]; then
        url="${TMDB_API_BASE_URL}/search/tv?api_key=${TMDB_API_KEY}&language=de-DE&query=${encoded_title}&page=1"
    else
        url="${TMDB_API_BASE_URL}/search/movie?api_key=${TMDB_API_KEY}&language=de-DE&query=${encoded_title}&page=1"
    fi
    
    # API-Anfrage
    local response=$(curl -s -f -H "User-Agent: ${TMDB_USER_AGENT}" "$url" 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$response" ]]; then
        echo '{"success": false, "message": "TMDB-Suche fehlgeschlagen"}'
        return 1
    fi
    
    # Formatiere Ergebnisse mit jq (max 10 Treffer)
    local results=$(echo "$response" | jq -c '[.results[:10] | .[] | {
        id: .id,
        title: (if .title then .title else .name end),
        year: ((if .release_date then .release_date else .first_air_date end) // "" | split("-")[0]),
        overview: (.overview // ""),
        poster_path: (.poster_path // ""),
        poster_url: (if .poster_path then ("https://image.tmdb.org/t/p/w200" + .poster_path) else null end)
    }]' 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$results" ]]; then
        echo '{"success": false, "message": "JSON-Formatierung fehlgeschlagen"}'
        return 1
    fi
    
    # Baue finale JSON-Response
    echo "{\"success\": true, \"results\": $results}"
    return 0
}

# ============================================================================
# METADATA CREATION
# ============================================================================

# Funktion: Erstelle .nfo Datei für DVD/Blu-ray
# Parameter: $1 = Ziel .nfo Datei
#            $2 = TMDB Movie Details (JSON)
#            $3 = Disc-Typ (dvd-video oder bd-video)
create_movie_nfo() {
    local nfo_file="$1"
    local movie_json="$2"
    local disc_type="$3"
    
    # Extrahiere Felder aus JSON
    local title=$(echo "$movie_json" | jq -r '.title // empty')
    local year=$(echo "$movie_json" | jq -r '.release_date // empty' | cut -d'-' -f1)
    local runtime=$(echo "$movie_json" | jq -r '.runtime // empty')
    local genres=$(echo "$movie_json" | jq -r '[.genres[].name] | join(", ") // empty')
    local overview=$(echo "$movie_json" | jq -r '.overview // empty')
    local rating=$(echo "$movie_json" | jq -r '.vote_average // empty')
    
    # Extrahiere Regisseur (erster Director aus Credits)
    local director=$(echo "$movie_json" | jq -r '.credits.crew[] | select(.job == "Director") | .name' | head -n1)
    
    # Fallback-Werte
    [[ -z "$title" ]] && title="Unknown Movie"
    [[ -z "$year" ]] && year="0000"
    [[ -z "$runtime" ]] && runtime="0"
    [[ -z "$genres" ]] && genres="Unknown"
    [[ -z "$director" ]] && director="Unknown"
    [[ -z "$rating" ]] && rating="0.0"
    
    # Erstelle .nfo Datei (KEY=VALUE Format wie bei Audio-CDs)
    {
        echo "TITLE=$title"
        echo "YEAR=$year"
        echo "DIRECTOR=$director"
        echo "GENRE=$genres"
        echo "RUNTIME=$runtime"
        echo "RATING=$rating"
        echo "TYPE=$disc_type"
        [[ -n "$overview" ]] && echo "OVERVIEW=$overview"
    } > "$nfo_file"
    
    log_info "Metadaten erstellt: $(basename "$nfo_file")"
}

# Funktion: Interaktive Film-Auswahl aus TMDB-Suchergebnissen
# Parameter: $1 = TMDB Suchergebnisse (JSON)
# Rückgabe: Movie-ID des ausgewählten Films oder leer bei Abbruch
select_tmdb_movie() {
    local search_results="$1"
    
    # Prüfe ob Ergebnisse vorhanden
    local result_count=$(echo "$search_results" | jq -r '.results | length')
    
    if [[ "$result_count" -eq 0 ]]; then
        log_info "TMDB: Keine Ergebnisse gefunden"
        return 1
    fi
    
    # Speichere Ergebnisse in API-Datei für Web-Interface
    local api_dir="${OUTPUT_DIR}/../api"
    mkdir -p "$api_dir"
    
    echo "$search_results" | jq '.' > "${api_dir}/tmdb_results.json"
    
    # Zeige Auswahl-Optionen
    log_info "TMDB: $result_count Ergebnis(se) gefunden"
    log_info "Bitte wählen Sie einen Film im Web-Interface aus..."
    
    # Warte auf Benutzer-Auswahl (max 5 Minuten)
    local selection_file="${api_dir}/tmdb_selection.json"
    rm -f "$selection_file"
    
    local timeout=300
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if [[ -f "$selection_file" ]]; then
            local selected_index=$(jq -r '.selected_index // empty' "$selection_file")
            
            if [[ -n "$selected_index" ]]; then
                # Hole Movie-ID des ausgewählten Films
                local movie_id=$(echo "$search_results" | jq -r ".results[$selected_index].id // empty")
                
                if [[ -n "$movie_id" ]]; then
                    log_info "TMDB: Film ausgewählt (Index: $selected_index, ID: $movie_id)"
                    echo "$movie_id"
                    return 0
                fi
            fi
        fi
        
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    log_info "TMDB: Timeout - keine Auswahl getroffen"
    return 1
}

# Funktion: Erstelle Archive-Metadaten für DVD/Blu-ray
# Parameter: $1 = Suchbegriff (Film-/Serien-Titel, aus disc_label abgeleitet)
#            $2 = Disc-Typ (dvd-video oder bd-video)
# Verwendet globale Variablen: iso_filename, disc_label
create_dvd_archive_metadata() {
    local search_query="$1"
    local disc_type="$2"
    
    # Prüfe ob es sich um eine TV-Serie handelt (Season im Dateinamen)
    local season_number=""
    if [[ "$disc_label" =~ season[_[:space:]]*([0-9]+) ]]; then
        season_number="${BASH_REMATCH[1]}"
        log_info "TV-Serie erkannt: Season $season_number"
        
        # Entferne Season/Disc aus Suchbegriff für bessere Treffer
        search_query=$(echo "$search_query" | sed -E 's/[Ss]eason[[:space:]]*[0-9]+//g' | sed -E 's/[Dd]is[ck][[:space:]]*[0-9]+//g' | sed 's/  / /g' | xargs)
        
        # TV-Serie Workflow
        log_info "Suche TV-Serie: $search_query"
        local tv_results=$(search_tmdb_tv "$search_query")
        
        if [[ -z "$tv_results" ]]; then
            log_error "TMDB: TV-Suche fehlgeschlagen - keine Metadaten erstellt"
            return 1
        fi
        
        local result_count=$(echo "$tv_results" | jq -r '.results | length')
        
        if [[ "$result_count" -eq 0 ]]; then
            log_info "TMDB: Keine TV-Serie gefunden"
            return 1
        fi
        
        # Nehme erstes Ergebnis (meist beste Übereinstimmung)
        local tv_id=$(echo "$tv_results" | jq -r '.results[0].id')
        local tv_name=$(echo "$tv_results" | jq -r '.results[0].name')
        log_info "TMDB: TV-Serie gefunden: $tv_name (ID: $tv_id)"
        
        # Hole Season-Details
        local season_details=$(get_tmdb_tv_season_details "$tv_id" "$season_number")
        
        if [[ -z "$season_details" ]]; then
            log_error "TMDB: Fehler beim Abrufen der Season-Details"
            return 1
        fi
        
        # Erstelle .nfo für TV-Serie
        local nfo_file="${iso_filename%.iso}.nfo"
        local first_air_date=$(echo "$tv_results" | jq -r '.results[0].first_air_date' | cut -d'-' -f1)
        local genres=$(echo "$tv_results" | jq -r '.results[0].genre_ids[]' 2>/dev/null | head -3 | tr '\n' ',' | sed 's/,$//')
        local overview=$(echo "$tv_results" | jq -r '.results[0].overview // empty')
        local rating=$(echo "$tv_results" | jq -r '.results[0].vote_average // "0"')
        
        # Hole Creator (entspricht Director bei Filmen)
        local creator="Unknown Creator"
        local tv_full=$(curl -s -f -H "User-Agent: ${TMDB_USER_AGENT}" "${TMDB_API_BASE_URL}/tv/${tv_id}?api_key=${TMDB_API_KEY}&language=de-DE" 2>/dev/null)
        if [[ -n "$tv_full" ]]; then
            creator=$(echo "$tv_full" | jq -r '.created_by[0].name // "Unknown Creator"')
            # Genre-Namen statt IDs
            genres=$(echo "$tv_full" | jq -r '[.genres[].name] | join(", ") // "Unknown"')
        fi
        
        {
            echo "TITLE=$tv_name"
            echo "YEAR=$first_air_date"
            echo "DIRECTOR=$creator"
            echo "GENRE=$genres"
            echo "RUNTIME=42"
            echo "RATING=$rating"
            echo "TYPE=$disc_type"
            [[ -n "$overview" ]] && echo "OVERVIEW=$overview"
        } > "$nfo_file"
        
        log_info "TV-Metadaten erstellt: $(basename "$nfo_file")"
        
        # Lade Season-Poster
        local poster_path=$(echo "$season_details" | jq -r '.poster_path // empty')
        local thumb_file="${iso_filename%.iso}-thumb.jpg"
        
        if download_tmdb_poster "$poster_path" "$thumb_file"; then
            log_info "Season-Poster heruntergeladen"
            return 0
        else
            log_info "TV-Metadaten erstellt (ohne Poster)"
            return 0
        fi
        
    else
        # Film Workflow (wie bisher)
        log_info "Suche Film-Metadaten: $search_query"
        
        local search_results=$(search_tmdb_movie "$search_query")
        
        if [[ -z "$search_results" ]]; then
            log_error "TMDB: Suche fehlgeschlagen - keine Metadaten erstellt"
            return 1
        fi
        
        # Prüfe ob automatische Auswahl möglich (nur 1 Ergebnis)
        local result_count=$(echo "$search_results" | jq -r '.results | length')
        local movie_id=""
        
        if [[ "$result_count" -eq 1 ]]; then
            # Automatische Auswahl bei eindeutigem Ergebnis
            movie_id=$(echo "$search_results" | jq -r '.results[0].id')
            local movie_title=$(echo "$search_results" | jq -r '.results[0].title')
            log_info "TMDB: Eindeutiges Ergebnis gefunden: $movie_title"
        else
            # Mehrere Ergebnisse → Benutzer-Auswahl erforderlich
            movie_id=$(select_tmdb_movie "$search_results")
            
            if [[ -z "$movie_id" ]]; then
                log_info "TMDB: Keine Auswahl getroffen - keine Metadaten erstellt"
                return 1
            fi
        fi
        
        # Hole Details zum ausgewählten Film
        local movie_details=$(get_tmdb_movie_details "$movie_id")
        
        if [[ -z "$movie_details" ]]; then
            log_error "TMDB: Fehler beim Abrufen der Film-Details"
            return 1
        fi
        
        # Erstelle .nfo Datei
        local nfo_file="${iso_filename%.iso}.nfo"
        create_movie_nfo "$nfo_file" "$movie_details" "$disc_type"
        
        # Lade Poster herunter
        local poster_path=$(echo "$movie_details" | jq -r '.poster_path // empty')
        local thumb_file="${iso_filename%.iso}-thumb.jpg"
        
        if download_tmdb_poster "$poster_path" "$thumb_file"; then
            log_info "Film-Metadaten erfolgreich erstellt"
            return 0
        else
            log_info "Film-Metadaten erstellt (ohne Poster)"
            return 0
        fi
    fi
}

# ============================================================================
# TITLE EXTRACTION
# ============================================================================

# Funktion: Bereite Suchstring aus ISO-Dateinamen vor
# Parameter: $1 = ISO-Dateiname (z.B. "supernatural_season_10.iso")
# Rückgabe: Bereinigter Suchbegriff für TMDB
prepare_search_string() {
    local filename="$1"
    local basename="${filename%.iso}"
    
    log_info "TMDB-Prepare: Input = '$basename'" >&2
    
    # Entferne gängige Suffixe
    basename=$(echo "$basename" | sed -E 's/_disc_?[0-9]+$//i')
    basename=$(echo "$basename" | sed -E 's/_dvd$//i')
    basename=$(echo "$basename" | sed -E 's/_bluray$//i')
    basename=$(echo "$basename" | sed -E 's/_bd$//i')
    
    # Entferne Disc-Nummern (_d1, _d2, _disc1, etc.)
    basename=$(echo "$basename" | sed -E 's/_d[0-9]+$//i')
    basename=$(echo "$basename" | sed -E 's/_disc[0-9]+$//i')
    
    # Entferne Season-Informationen (für bessere TV-Suche)
    basename=$(echo "$basename" | sed -E 's/_season[_[:space:]]*[0-9]+//gi')
    basename=$(echo "$basename" | sed -E 's/_s[0-9]{2}//gi')
    
    # Entferne Jahr am Ende (4-stellig)
    basename=$(echo "$basename" | sed -E 's/_[0-9]{4}$//')
    
    # Ersetze Unterstriche durch Leerzeichen
    basename=$(echo "$basename" | tr '_' ' ')
    
    # Entferne mehrfache Leerzeichen
    basename=$(echo "$basename" | sed 's/  */ /g' | xargs)
    
    log_info "TMDB-Prepare: Output = '$basename'" >&2
    echo "$basename"
}

# Funktion: Extrahiere Filmtitel aus disc_label
# Parameter: $1 = disc_label (z.B. "the_matrix_1999" oder "MOVIE_TITLE")
# Rückgabe: Bereinigter Titel für TMDB-Suche
extract_movie_title() {
    local label="$1"
    
    # Entferne gängige Suffixe
    label=$(echo "$label" | sed -E 's/_disc_?[0-9]+$//i')
    label=$(echo "$label" | sed -E 's/_dvd$//i')
    label=$(echo "$label" | sed -E 's/_bluray$//i')
    label=$(echo "$label" | sed -E 's/_bd$//i')
    
    # Entferne Jahr am Ende (4-stellig)
    label=$(echo "$label" | sed -E 's/_[0-9]{4}$//')
    
    # Ersetze Unterstriche durch Leerzeichen
    label=$(echo "$label" | tr '_' ' ')
    
    # Großschreibung (erster Buchstabe jedes Wortes)
    label=$(echo "$label" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
    
    echo "$label"
}

# ============================================================================
# CACHING FUNCTIONS (NEW ARCHITECTURE)
# ============================================================================

# Funktion: Führe TMDB-Anfrage durch und speichere RAW Response
# Parameter: $1 = Suchbegriff (bereinigter Titel)
#            $2 = ISO-Basisname (ohne .iso, für Cache-Dateinamen)
#            $3 = Media-Type ("movie" oder "tv")
# Rückgabe: 0 bei Erfolg, 1 bei Fehler
# WICHTIG: Speichert nur die unverarbeitete TMDB-API Response
#          Python übernimmt die gesamte JSON-Verarbeitung und Poster-Downloads
fetch_tmdb_raw() {
    local search_term="$1"
    local iso_basename="$2"
    local media_type="$3"
    
    # Validierung
    if [[ -z "$TMDB_API_KEY" ]]; then
        log_info "TMDB-Request: API-Key nicht konfiguriert"
        return 1
    fi
    
    # Initialisiere Cache-Verzeichnisse (Lazy Initialization)
    init_tmdb_cache_dirs || return 1
    
    local cache_file="${TMDB_CACHE_DIR}/${iso_basename}_raw.json"
    
    log_info "TMDB-Request: Suche '$search_term' (Typ: $media_type)"
    
    # URL-Encode des Suchbegriffs
    local encoded_query=$(echo "$search_term" | sed 's/ /%20/g' | sed 's/&/%26/g')
    
    # Wähle API-Endpoint
    local url
    if [[ "$media_type" == "tv" ]]; then
        url="${TMDB_API_BASE_URL}/search/tv?api_key=${TMDB_API_KEY}&language=de-DE&query=${encoded_query}&page=1"
    else
        url="${TMDB_API_BASE_URL}/search/movie?api_key=${TMDB_API_KEY}&language=de-DE&query=${encoded_query}&page=1"
    fi
    
    # API-Anfrage - speichere direkt in Datei (vermeidet Bash String-Length-Limits)
    log_info "TMDB-Request: URL = $url" >&2
    
    if ! curl -s -f -H "User-Agent: ${TMDB_USER_AGENT}" "$url" -o "$cache_file" 2>/dev/null; then
        local curl_exit=$?
        log_error "TMDB-Request: API-Anfrage fehlgeschlagen (exit $curl_exit)" >&2
        echo '{"error": "API request failed"}' > "$cache_file"
        return 1
    fi
    
    # Prüfe ob Response JSON ist (mindestens '{}')
    if [[ ! -s "$cache_file" ]]; then
        log_info "TMDB-Request: Leere Response erhalten"
        echo '{"error": "Empty response"}' > "$cache_file"
        return 1
    fi
    
    log_info "TMDB-Request: Raw response gespeichert: $(basename "$cache_file")"
    return 0
}

# Funktion: Suche und Cache TMDB-Metadaten (Hauptfunktion)
# Parameter: $1 = ISO-Dateiname (z.B. "supernatural_season_10.iso")
# Rückgabe: 0 bei Erfolg, 1 bei Fehler
search_and_cache_tmdb() {
    local iso_filename="$1"
    local iso_basename="${iso_filename%.iso}"
    
    log_info "TMDB: Starte Suche für: $iso_filename"
    
    # Schritt 1: Suchbegriff vorbereiten
    local search_term=$(prepare_search_string "$iso_filename")
    
    if [[ -z "$search_term" ]]; then
        log_error "TMDB: Fehler bei Suchbegriff-Extraktion"
        return 1
    fi
    
    # Erkenne Media-Type (TV wenn Season im Dateinamen)
    local media_type="movie"
    if [[ "$iso_filename" =~ season[_[:space:]]*[0-9]+ ]] || [[ "$iso_filename" =~ _s[0-9]{2} ]]; then
        media_type="tv"
        log_info "TMDB: TV-Serie erkannt"
    fi
    
    # Schritt 2: TMDB-Anfrage durchführen (nur raw API call)
    if ! fetch_tmdb_raw "$search_term" "$iso_basename" "$media_type"; then
        log_error "TMDB: Anfrage fehlgeschlagen"
        return 1
    fi
    
    log_info "TMDB: Raw response bereit - Python übernimmt Verarbeitung"
    return 0
}

# ============================================================================
# RETROACTIVE METADATA FUNCTIONS
# ============================================================================

# Funktion: Füge TMDB-Metadaten zu existierender ISO hinzu
# Parameter: 
#   $1 = iso_path (vollständiger Pfad zur ISO-Datei)
#   $2 = title (Film- oder Serien-Titel für TMDB-Suche)
#   $3 = media_type ("movie" oder "tv")
#   $4 = tmdb_id (optional, wenn bereits bekannt)
# Rückgabe: 0 bei Erfolg, 1 bei Fehler
add_metadata_to_existing_iso() {
    local iso_path="$1"
    local title="$2"
    local media_type="$3"
    local tmdb_id="$4"
    
    # Validierung
    if [[ ! -f "$iso_path" ]]; then
        log_error "TMDB: ISO-Datei nicht gefunden: $iso_path"
        return 1
    fi
    
    if [[ -z "$TMDB_API_KEY" ]]; then
        log_info "TMDB: API-Key nicht konfiguriert"
        return 1
    fi
    
    # Extrahiere Basisnamen ohne .iso
    local base_path="${iso_path%.iso}"
    local nfo_file="${base_path}.nfo"
    local thumb_file="${base_path}-thumb.jpg"
    
    log_info "TMDB: Füge Metadaten hinzu für: $(basename "$iso_path")"
    
    # Wenn TMDB-ID bereits bekannt, hole Details direkt
    if [[ -n "$tmdb_id" ]]; then
        if [[ "$media_type" == "tv" ]]; then
            # Extrahiere Season-Nummer aus Dateinamen
            local season_num=""
            if [[ "$(basename "$iso_path")" =~ season[_[:space:]]*([0-9]+) ]]; then
                season_num="${BASH_REMATCH[1]}"
            fi
            
            if [[ -z "$season_num" ]]; then
                log_info "TMDB: Keine Season-Nummer im Dateinamen gefunden"
                return 1
            fi
            
            local tv_details=$(get_tmdb_tv_season_details "$tmdb_id" "$season_num")
            
            if [[ -z "$tv_details" ]]; then
                log_info "TMDB: Konnte TV-Details nicht abrufen"
                return 1
            fi
            
            # Extrahiere Metadaten
            local tv_name=$(echo "$tv_details" | jq -r '.name // empty')
            local first_air_date=$(echo "$tv_details" | jq -r '.first_air_date // empty')
            local year=$(echo "$first_air_date" | cut -d'-' -f1)
            local creator=$(echo "$tv_details" | jq -r '.created_by[0].name // "Unknown"')
            local genres=$(echo "$tv_details" | jq -r '[.genres[].name] | join(", ") // "Unknown"')
            local runtime=$(echo "$tv_details" | jq -r '.episode_run_time[0] // 0')
            local rating=$(echo "$tv_details" | jq -r '.vote_average // 0')
            local overview=$(echo "$tv_details" | jq -r '.overview // ""')
            local poster_path=$(echo "$tv_details" | jq -r '.seasons[] | select(.season_number == '"$season_num"') | .poster_path // empty')
            
            # Erstelle .nfo
            cat > "$nfo_file" <<EOF
TITLE=$tv_name
YEAR=$year
DIRECTOR=$creator
GENRE=$genres
RUNTIME=$runtime
RATING=$rating
TYPE=dvd-video
OVERVIEW=$overview
EOF
            
            # Lade Season-Poster
            if [[ -n "$poster_path" ]] && download_tmdb_poster "$poster_path" "$thumb_file"; then
                log_info "TMDB: TV-Metadaten erfolgreich hinzugefügt"
                return 0
            fi
            
        else
            # Movie
            local movie_details=$(get_tmdb_movie_details "$tmdb_id")
            
            if [[ -z "$movie_details" ]]; then
                log_info "TMDB: Konnte Film-Details nicht abrufen"
                return 1
            fi
            
            # Extrahiere Metadaten
            local movie_title=$(echo "$movie_details" | jq -r '.title // empty')
            local release_date=$(echo "$movie_details" | jq -r '.release_date // empty')
            local year=$(echo "$release_date" | cut -d'-' -f1)
            local director=$(echo "$movie_details" | jq -r '.credits.crew[] | select(.job == "Director") | .name' | head -n1)
            local genres=$(echo "$movie_details" | jq -r '[.genres[].name] | join(", ") // "Unknown"')
            local runtime=$(echo "$movie_details" | jq -r '.runtime // 0')
            local rating=$(echo "$movie_details" | jq -r '.vote_average // 0')
            local overview=$(echo "$movie_details" | jq -r '.overview // ""')
            local poster_path=$(echo "$movie_details" | jq -r '.poster_path // empty')
            
            # Ermittle Disc-Typ aus Pfad
            local disc_type="dvd-video"
            if [[ "$iso_path" =~ /bd/ ]]; then
                disc_type="bd-video"
            fi
            
            # Erstelle .nfo
            cat > "$nfo_file" <<EOF
TITLE=$movie_title
YEAR=$year
DIRECTOR=$director
GENRE=$genres
RUNTIME=$runtime
RATING=$rating
TYPE=$disc_type
OVERVIEW=$overview
EOF
            
            # Lade Poster
            if [[ -n "$poster_path" ]] && download_tmdb_poster "$poster_path" "$thumb_file"; then
                log_info "TMDB: Film-Metadaten erfolgreich hinzugefügt"
                return 0
            fi
        fi
        
        log_info "TMDB: Metadaten erstellt (ohne Poster)"
        return 0
    fi
    
    # Wenn keine TMDB-ID: Suche zuerst
    log_info "TMDB: Suche nach: $title ($media_type)"
    
    if [[ "$media_type" == "tv" ]]; then
        local search_results=$(search_tmdb_tv "$title")
    else
        local search_results=$(search_tmdb_movie "$title")
    fi
    
    if [[ -z "$search_results" ]]; then
        log_info "TMDB: Keine Suchergebnisse gefunden"
        return 1
    fi
    
    # Verwende ersten Treffer
    local first_id=$(echo "$search_results" | jq -r '.results[0].id // empty')
    
    if [[ -z "$first_id" ]]; then
        log_info "TMDB: Keine gültige ID in Suchergebnissen"
        return 1
    fi
    
    # Rekursiver Aufruf mit ID
    add_metadata_to_existing_iso "$iso_path" "$title" "$media_type" "$first_id"
}

# Funktion: Benenne ISO-Datei basierend auf TMDB-Titel um
# Parameter:
#   $1 = old_iso_path (aktueller Pfad)
#   $2 = new_title (neuer Titel, wird normalisiert)
# Rückgabe: Neuer Pfad oder alter Pfad bei Fehler
rename_iso_with_metadata() {
    local old_path="$1"
    local new_title="$2"
    
    if [[ ! -f "$old_path" ]]; then
        echo "$old_path"
        return 1
    fi
    
    # Normalisiere Titel (Kleinbuchstaben, Unterstriche)
    local normalized=$(echo "$new_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g')
    
    # Behalte Verzeichnis bei
    local dir=$(dirname "$old_path")
    local new_path="${dir}/${normalized}.iso"
    
    # Prüfe ob Datei bereits existiert
    if [[ -f "$new_path" ]] && [[ "$new_path" != "$old_path" ]]; then
        log_info "TMDB: Datei existiert bereits: $(basename "$new_path")"
        echo "$old_path"
        return 1
    fi
    
    # Benenne ISO + zugehörige Dateien um
    if mv "$old_path" "$new_path" 2>/dev/null; then
        # Benenne .md5 um (falls vorhanden)
        [[ -f "${old_path%.iso}.md5" ]] && mv "${old_path%.iso}.md5" "${new_path%.iso}.md5" 2>/dev/null
        
        # .nfo und -thumb.jpg werden mit neuem Namen erstellt
        log_info "TMDB: ISO umbenannt: $(basename "$old_path") → $(basename "$new_path")"
        echo "$new_path"
        return 0
    else
        log_error "TMDB: Umbenennung fehlgeschlagen"
        echo "$old_path"
        return 1
    fi
}

################################################################################
# ENDE lib-dvd-metadata.sh
################################################################################
