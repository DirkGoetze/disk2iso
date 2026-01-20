#!/bin/bash
################################################################################
# disk2iso v1.2.0 - DVD/Blu-ray Metadata BEFORE Copy
# Filepath: lib/lib-dvd-metadata-before.sh
#
# Beschreibung:
#   TMDB-Integration für Metadata-Auswahl VOR dem Kopiervorgang
#   Analog zu lib-cd.sh wait_for_metadata_selection() für Audio-CDs
#
# Version: 1.2.0
# Datum: 20.01.2026
################################################################################

# ============================================================================
# TMDB METADATA BEFORE COPY - QUERY
# ============================================================================

# Funktion: TMDB Query und Speicherung (BEFORE Copy)
# Parameter: $1 = movie_title (aus disc_label extrahiert)
#            $2 = disc_type (dvd-video oder bd-video)
#            $3 = disc_id (für Dateinamen)
# Rückgabe: 0 = Query erfolgreich, 1 = Fehler
query_tmdb_before_copy() {
    local movie_title="$1"
    local disc_type="$2"
    local disc_id="${3:-${disc_label}}"
    
    if [[ -z "$TMDB_API_KEY" ]]; then
        log_info "TMDB: API-Key nicht konfiguriert - überspringe Metadata-Query"
        return 1
    fi
    
    log_info "TMDB: Suche nach '$movie_title'..."
    
    # Bestimme Media-Type (movie oder tv)
    local media_type="movie"
    if [[ "$disc_label" =~ season|staffel|s[0-9]{2} ]]; then
        media_type="tv"
        log_info "TMDB: Erkannt als TV-Serie"
    fi
    
    # TMDB-Suche
    local tmdb_response
    if [[ "$media_type" == "tv" ]]; then
        tmdb_response=$(search_tmdb_tv "$movie_title")
    else
        tmdb_response=$(search_tmdb_movie "$movie_title")
    fi
    
    if [[ $? -ne 0 ]] || [[ -z "$tmdb_response" ]]; then
        log_warning "TMDB: Keine Ergebnisse für '$movie_title'"
        return 1
    fi
    
    # Prüfe Anzahl Ergebnisse
    local result_count=$(echo "$tmdb_response" | jq '.results | length' 2>/dev/null)
    
    if [[ -z "$result_count" ]] || [[ "$result_count" -eq 0 ]]; then
        log_info "TMDB: Keine Treffer für '$movie_title'"
        return 1
    fi
    
    log_info "TMDB: $result_count Treffer gefunden"
    
    # Schreibe .tmdbquery Datei (für Frontend-API)
    local output_base
    output_base=$(get_type_subfolder "$disc_type")
    local tmdbquery_file="${output_base}/${disc_id}_tmdb.tmdbquery"
    
    log_info "TMDB: Erstelle Query-Datei für User-Auswahl: $(basename "$tmdbquery_file")"
    
    # Erweitere JSON mit Metadaten
    echo "$tmdb_response" | jq -c "{
        media_type: \"$media_type\",
        disc_type: \"$disc_type\",
        disc_id: \"$disc_id\",
        search_query: \"$movie_title\",
        result_count: $result_count,
        results: .results
    }" > "$tmdbquery_file"
    
    chmod 644 "$tmdbquery_file" 2>/dev/null
    
    return 0
}

# ============================================================================
# TMDB METADATA BEFORE COPY - WAIT FOR SELECTION
# ============================================================================

# Funktion: Warte auf User-TMDB-Auswahl (BEFORE Copy)
# Parameter: $1 = disc_id
#            $2 = tmdb_response (JSON)
# Rückgabe: 0 = Auswahl getroffen, 1 = Timeout/Skip
# Setzt: dvd_title, dvd_year aus User-Auswahl
wait_for_tmdb_selection() {
    local disc_id="$1"
    local tmdb_json="$2"
    
    # Bestimme Output-Ordner basierend auf disc_type
    local output_base
    output_base=$(get_type_subfolder "${disc_type:-dvd-video}")
    
    local tmdbquery_file="${output_base}/${disc_id}_tmdb.tmdbquery"
    
    log_info "TMDB: Erstelle Metadata-Query für User-Auswahl: $(basename "$tmdbquery_file")"
    echo "$tmdb_json" > "$tmdbquery_file"
    chmod 644 "$tmdbquery_file" 2>/dev/null
    
    # Warte auf .tmdbselect Datei oder Timeout
    local tmdbselect_file="${output_base}/${disc_id}_tmdb.tmdbselect"
    local timeout="${METADATA_SELECTION_TIMEOUT:-60}"
    local elapsed=0
    local check_interval=1
    
    log_info "TMDB: Warte auf Metadata-Auswahl (Timeout: ${timeout}s)..."
    
    # State: waiting_for_metadata
    if declare -f transition_to_state >/dev/null 2>&1; then
        transition_to_state "$STATE_WAITING_FOR_METADATA" "Warte auf TMDB Metadata-Auswahl"
    fi
    
    while [[ $elapsed -lt $timeout ]]; do
        # Prüfe ob Selection-Datei existiert
        if [[ -f "$tmdbselect_file" ]]; then
            log_info "TMDB: Metadata-Auswahl erhalten nach ${elapsed}s"
            
            # Lese Auswahl
            local selected_index
            selected_index=$(jq -r '.selected_index' "$tmdbselect_file" 2>/dev/null || echo "-1")
            
            # Cleanup
            rm -f "$tmdbquery_file" "$tmdbselect_file" 2>/dev/null
            
            # Skip?
            if [[ "$selected_index" == "-1" ]] || [[ "$selected_index" == "skip" ]]; then
                log_info "TMDB: Metadata-Auswahl übersprungen - verwende generische Namen"
                return 1
            fi
            
            # Extrahiere Metadata aus gewähltem Result
            local title
            local year
            
            # TMDB hat unterschiedliche Felder für movies/tv
            title=$(echo "$tmdb_json" | jq -r ".results[$selected_index].title // .results[$selected_index].name" 2>/dev/null)
            year=$(echo "$tmdb_json" | jq -r ".results[$selected_index].release_date // .results[$selected_index].first_air_date" 2>/dev/null | cut -d- -f1)
            
            if [[ -n "$title" ]]; then
                # Setze globale Variablen (analog zu cd_artist, cd_album)
                dvd_title="$title"
                dvd_year="${year:-0000}"
                
                log_info "TMDB: Metadata ausgewählt: $dvd_title ($dvd_year)"
                
                # Update disc_label mit TMDB-Daten
                local sanitized_title=$(echo "$dvd_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')
                disc_label="${sanitized_title}_${dvd_year}"
                
                log_info "TMDB: Neues disc_label: $disc_label"
                return 0
            else
                log_warning "TMDB: Metadata-Extraktion fehlgeschlagen - verwende generische Namen"
                return 1
            fi
        fi
        
        sleep "$check_interval"
        ((elapsed += check_interval))
        
        # Progress-Log alle 10 Sekunden
        if (( elapsed % 10 == 0 )); then
            log_info "TMDB: Warte auf Auswahl... (${elapsed}/${timeout}s)"
        fi
    done
    
    # Timeout erreicht
    log_warning "TMDB: Metadata-Auswahl Timeout nach ${timeout}s - verwende generische Namen"
    rm -f "$tmdbquery_file" "$tmdbselect_file" 2>/dev/null
    return 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Funktion: Extrahiere Film-Titel aus disc_label
# Parameter: $1 = disc_label (z.B. "mission_impossible_2023")
# Rückgabe: Suchbarer Titel (z.B. "Mission Impossible")
extract_movie_title_from_label() {
    local label="$1"
    
    # Entferne Jahr am Ende (4 Ziffern)
    label=$(echo "$label" | sed 's/_[0-9]\{4\}$//')
    
    # Ersetze Underscores durch Leerzeichen
    label=$(echo "$label" | tr '_' ' ')
    
    # Erste Buchstaben groß (Title Case)
    label=$(echo "$label" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
    
    echo "$label"
}
