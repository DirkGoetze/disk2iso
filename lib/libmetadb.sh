#!/bin/bash
# =============================================================================
# Metadata In-Memory Database
# =============================================================================
# Filepath: lib/libmetadb.sh
#
# Beschreibung:
#   In-Memory Datenbank für Disc-Metadaten
#   - Verwaltet zwei assoziative Arrays: DISC_METADATA + DISC_DATA
#   - DISC_METADATA = Gemeinsame Felder (disc_id, disc_type, size_mb, etc.)
#   - DISC_DATA = Typ-spezifische Felder (artist/album für Audio, title/director für Video)
#   - CRUD-Operationen: init, set, get, clear
#   - Export: NFO (Jellyfin), JSON (API), Key-Value (Archiv)
#   - Namespacing für komplexe Strukturen (Tracks, Genres)
#
# -----------------------------------------------------------------------------
# Dependencies: liblogging (für log_* Funktionen)
# -----------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.0.0
# Last Change: 2026-01-27
# =============================================================================

# =============================================================================
# GLOBALE DATENSTRUKTUREN
# =============================================================================

# Array 1: Gemeinsame Disc-Metadaten (für ALLE Disc-Typen)
declare -A DISC_METADATA

# Array 2: Typ-spezifische Daten (je nach disc_type unterschiedlich befüllt)
declare -A DISC_DATA

# =============================================================================
# INITIALISIERUNG
# =============================================================================

# ===========================================================================
# metadb_init
# ---------------------------------------------------------------------------
# Funktion.: Initialisiere Metadaten-Datenbank für Disc-Typ
# Parameter: $1 = disc_type ("audio-cd", "dvd-video", "bd-video", "data-cd")
# Rückgabe.: 0 = Erfolg
# Setzt....: DISC_METADATA + DISC_DATA mit Default-Werten
# ===========================================================================
metadb_init() {
    local disc_type="$1"
    
    # Validierung
    if [[ -z "$disc_type" ]]; then
        log_error "metadb_init: disc_type fehlt"
        return 1
    fi
    
    # Leere beide Arrays
    DISC_METADATA=()
    DISC_DATA=()
    
    # -------------------------------------------------------------------------
    # DISC_METADATA: Gemeinsame Basis-Felder (für ALLE Typen)
    # -------------------------------------------------------------------------
    DISC_METADATA[disc_type]="$disc_type"
    DISC_METADATA[disc_id]=""
    DISC_METADATA[disc_label]=""
    DISC_METADATA[size_mb]=0
    DISC_METADATA[created_at]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    DISC_METADATA[provider]=""           # z.B. "musicbrainz", "tmdb", "manual"
    DISC_METADATA[provider_id]=""        # Externe ID (MusicBrainz Release-ID, TMDB ID)
    DISC_METADATA[cover_url]=""          # URL zum Cover/Poster
    DISC_METADATA[cover_file]=""         # Lokaler Pfad zum Cover
    
    # -------------------------------------------------------------------------
    # DISC_DATA: Typ-spezifische Felder initialisieren
    # -------------------------------------------------------------------------
    case "$disc_type" in
        audio-cd)
            # Audio-CD spezifisch
            DISC_DATA[artist]=""
            DISC_DATA[album]=""
            DISC_DATA[year]=""
            DISC_DATA[release_date]=""   # YYYY-MM-DD
            DISC_DATA[country]=""
            DISC_DATA[label]=""          # Plattenlabel (z.B. "Apple Records")
            DISC_DATA[track_count]=0
            DISC_DATA[duration]=0        # Millisekunden
            DISC_DATA[toc]=""            # Table of Contents (MusicBrainz)
            # Tracks werden via metadb_set_track() hinzugefügt: track.N.title, track.N.duration
            ;;
            
        dvd-video|bd-video)
            # Video spezifisch (DVD/Blu-ray)
            DISC_DATA[title]=""
            DISC_DATA[year]=""
            DISC_DATA[release_date]=""   # YYYY-MM-DD
            DISC_DATA[country]=""
            DISC_DATA[director]=""
            DISC_DATA[runtime]=0         # Minuten
            DISC_DATA[overview]=""       # Beschreibung/Plot
            DISC_DATA[media_type]=""     # "movie" oder "tv"
            DISC_DATA[season]=""         # Nur für TV-Serien
            DISC_DATA[episode]=""        # Nur für TV-Serien
            # Genres werden via metadb_add_genre() hinzugefügt: genre.N
            ;;
            
        data-cd|data-dvd)
            # Daten-Disc spezifisch (minimal)
            DISC_DATA[description]=""    # Freitext-Beschreibung des Inhalts
            DISC_DATA[backup_date]=""    # YYYY-MM-DD
            ;;
            
        *)
            log_warning "metadb_init: Unbekannter disc_type '$disc_type' - nur Basis-Felder initialisiert"
            ;;
    esac
    
    log_debug "metadb_init: Datenbank initialisiert für '$disc_type'"
    return 0
}

# =============================================================================
# CRUD OPERATIONEN - CREATE/UPDATE
# =============================================================================

# ===========================================================================
# metadb_set
# ---------------------------------------------------------------------------
# Funktion.: Setze Metadaten-Wert (DISC_METADATA oder DISC_DATA)
# Parameter: $1 = key (z.B. "disc_id", "artist", "title")
#            $2 = value
# Rückgabe.: 0 = Erfolg
# Hinweis..: Automatische Erkennung ob DISC_METADATA oder DISC_DATA
# ===========================================================================
metadb_set() {
    local key="$1"
    local value="$2"
    
    # Validierung
    if [[ -z "$key" ]]; then
        log_error "metadb_set: key fehlt"
        return 1
    fi
    
    # Prüfe ob Key in DISC_METADATA existiert
    if [[ -v "DISC_METADATA[$key]" ]]; then
        DISC_METADATA["$key"]="$value"
    else
        # Sonst in DISC_DATA speichern
        DISC_DATA["$key"]="$value"
    fi
    
    return 0
}

# ===========================================================================
# metadb_set_metadata
# ---------------------------------------------------------------------------
# Funktion.: Setze Wert explizit in DISC_METADATA
# Parameter: $1 = key
#            $2 = value
# Rückgabe.: 0 = Erfolg
# ===========================================================================
metadb_set_metadata() {
    local key="$1"
    local value="$2"
    DISC_METADATA["$key"]="$value"
}

# ===========================================================================
# metadb_set_data
# ---------------------------------------------------------------------------
# Funktion.: Setze Wert explizit in DISC_DATA
# Parameter: $1 = key
#            $2 = value
# Rückgabe.: 0 = Erfolg
# ===========================================================================
metadb_set_data() {
    local key="$1"
    local value="$2"
    DISC_DATA["$key"]="$value"
}

# =============================================================================
# CRUD OPERATIONEN - READ
# =============================================================================

# ===========================================================================
# metadb_get
# ---------------------------------------------------------------------------
# Funktion.: Lese Metadaten-Wert (DISC_METADATA oder DISC_DATA)
# Parameter: $1 = key
# Rückgabe.: Wert oder leerer String
# ===========================================================================
metadb_get() {
    local key="$1"
    
    # Prüfe DISC_METADATA zuerst
    if [[ -v "DISC_METADATA[$key]" ]]; then
        echo "${DISC_METADATA[$key]}"
        return 0
    fi
    
    # Dann DISC_DATA
    if [[ -v "DISC_DATA[$key]" ]]; then
        echo "${DISC_DATA[$key]}"
        return 0
    fi
    
    # Key nicht gefunden
    echo ""
    return 1
}

# ===========================================================================
# metadb_get_metadata
# ---------------------------------------------------------------------------
# Funktion.: Lese Wert explizit aus DISC_METADATA
# Parameter: $1 = key
# Rückgabe.: Wert oder leerer String
# ===========================================================================
metadb_get_metadata() {
    local key="$1"
    echo "${DISC_METADATA[$key]}"
}

# ===========================================================================
# metadb_get_data
# ---------------------------------------------------------------------------
# Funktion.: Lese Wert explizit aus DISC_DATA
# Parameter: $1 = key
# Rückgabe.: Wert oder leerer String
# ===========================================================================
metadb_get_data() {
    local key="$1"
    echo "${DISC_DATA[$key]}"
}

# =============================================================================
# CRUD OPERATIONEN - DELETE
# =============================================================================

# ===========================================================================
# metadb_clear
# ---------------------------------------------------------------------------
# Funktion.: Lösche alle Metadaten (beide Arrays)
# Parameter: keine
# Rückgabe.: 0 = Erfolg
# ===========================================================================
metadb_clear() {
    DISC_METADATA=()
    DISC_DATA=()
    log_debug "metadb_clear: Datenbank geleert"
    return 0
}

# =============================================================================
# SPEZIAL-FUNKTIONEN FÜR KOMPLEXE STRUKTUREN
# =============================================================================

# ===========================================================================
# metadb_set_track
# ---------------------------------------------------------------------------
# Funktion.: Setze Track-Informationen (für Audio-CDs)
# Parameter: $1 = track_number (1-basiert)
#            $2 = field ("title", "duration", "artist")
#            $3 = value
# Rückgabe.: 0 = Erfolg
# Hinweis..: Nutzt Namespacing: track.N.field
# ===========================================================================
metadb_set_track() {
    local track_num="$1"
    local field="$2"
    local value="$3"
    
    # Validierung
    if [[ ! "$track_num" =~ ^[0-9]+$ ]]; then
        log_error "metadb_set_track: Ungültige Track-Nummer '$track_num'"
        return 1
    fi
    
    DISC_DATA["track.${track_num}.${field}"]="$value"
    return 0
}

# ===========================================================================
# metadb_get_track
# ---------------------------------------------------------------------------
# Funktion.: Lese Track-Information
# Parameter: $1 = track_number
#            $2 = field
# Rückgabe.: Wert oder leerer String
# ===========================================================================
metadb_get_track() {
    local track_num="$1"
    local field="$2"
    echo "${DISC_DATA[track.${track_num}.${field}]}"
}

# ===========================================================================
# metadb_add_genre
# ---------------------------------------------------------------------------
# Funktion.: Füge Genre hinzu (für Video)
# Parameter: $1 = genre (z.B. "Sci-Fi", "Action")
# Rückgabe.: 0 = Erfolg
# Hinweis..: Nutzt Namespacing: genre.N
# ===========================================================================
metadb_add_genre() {
    local genre="$1"
    
    # Finde nächsten freien Index
    local index=1
    while [[ -v "DISC_DATA[genre.${index}]" ]]; do
        ((index++))
    done
    
    DISC_DATA["genre.${index}"]="$genre"
    return 0
}

# ===========================================================================
# metadb_get_genres
# ---------------------------------------------------------------------------
# Funktion.: Hole alle Genres als Array
# Rückgabe.: Komma-separierte Liste oder leerer String
# ===========================================================================
metadb_get_genres() {
    local genres=()
    local index=1
    
    while [[ -v "DISC_DATA[genre.${index}]" ]]; do
        genres+=("${DISC_DATA[genre.${index}]}")
        ((index++))
    done
    
    # Gebe komma-separiert zurück
    IFS=','
    echo "${genres[*]}"
}

# =============================================================================
# EXPORT - NFO DATEIEN (JELLYFIN FORMAT)
# =============================================================================

# ===========================================================================
# metadb_export_nfo
# ---------------------------------------------------------------------------
# Funktion.: Exportiere Metadaten als NFO-Datei (Jellyfin-Format)
# Parameter: $1 = nfo_file_path
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: Format abhängig von disc_type
# ===========================================================================
metadb_export_nfo() {
    local nfo_file="$1"
    local disc_type="${DISC_METADATA[disc_type]}"
    
    # Validierung
    if [[ -z "$nfo_file" ]]; then
        log_error "metadb_export_nfo: nfo_file fehlt"
        return 1
    fi
    
    case "$disc_type" in
        audio-cd)
            _metadb_export_audio_nfo "$nfo_file"
            ;;
        dvd-video|bd-video)
            _metadb_export_video_nfo "$nfo_file"
            ;;
        data-cd|data-dvd)
            _metadb_export_data_nfo "$nfo_file"
            ;;
        *)
            log_error "metadb_export_nfo: Unbekannter disc_type '$disc_type'"
            return 1
            ;;
    esac
    
    log_info "metadb_export_nfo: NFO erstellt: $(basename "$nfo_file")"
    return 0
}

# Interne Funktion: Audio-CD NFO (album.nfo)
_metadb_export_audio_nfo() {
    local nfo_file="$1"
    
    cat > "$nfo_file" <<EOF
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<album>
  <title>${DISC_DATA[album]}</title>
  <artist>${DISC_DATA[artist]}</artist>
  <year>${DISC_DATA[year]}</year>
  <runtime>$((DISC_DATA[duration] / 60000))</runtime>
  <musicbrainzalbumid>${DISC_METADATA[provider_id]}</musicbrainzalbumid>
  <albumartist>${DISC_DATA[artist]}</albumartist>
EOF
    
    # Track-Liste hinzufügen
    local track_count="${DISC_DATA[track_count]}"
    for ((i=1; i<=track_count; i++)); do
        local track_title="${DISC_DATA[track.$i.title]}"
        local track_duration="${DISC_DATA[track.$i.duration]}"
        
        if [[ -n "$track_title" ]]; then
            cat >> "$nfo_file" <<EOF
  <track>
    <position>$i</position>
    <title>${track_title}</title>
    <duration>${track_duration}</duration>
  </track>
EOF
        fi
    done
    
    echo "</album>" >> "$nfo_file"
}

# Interne Funktion: Video NFO (movie.nfo)
_metadb_export_video_nfo() {
    local nfo_file="$1"
    
    cat > "$nfo_file" <<EOF
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<movie>
  <title>${DISC_DATA[title]}</title>
  <year>${DISC_DATA[year]}</year>
  <director>${DISC_DATA[director]}</director>
  <runtime>${DISC_DATA[runtime]}</runtime>
  <plot>${DISC_DATA[overview]}</plot>
  <tmdbid>${DISC_METADATA[provider_id]}</tmdbid>
EOF
    
    # Genres hinzufügen
    local index=1
    while [[ -v "DISC_DATA[genre.${index}]" ]]; do
        echo "  <genre>${DISC_DATA[genre.${index}]}</genre>" >> "$nfo_file"
        ((index++))
    done
    
    echo "</movie>" >> "$nfo_file"
}

# Interne Funktion: Data-Disc NFO (einfaches Key-Value Format)
_metadb_export_data_nfo() {
    local nfo_file="$1"
    
    cat > "$nfo_file" <<EOF
DESCRIPTION=${DISC_DATA[description]}
BACKUP_DATE=${DISC_DATA[backup_date]}
CREATED=${DISC_METADATA[created_at]}
SIZE_MB=${DISC_METADATA[size_mb]}
TYPE=${DISC_METADATA[disc_type]}
EOF
}

# =============================================================================
# EXPORT - JSON (API FORMAT)
# =============================================================================

# ===========================================================================
# metadb_export_json
# ---------------------------------------------------------------------------
# Funktion.: Exportiere Metadaten als JSON
# Rückgabe.: JSON-String
# Hinweis..: Für API-Zugriff optimiert
# ===========================================================================
metadb_export_json() {
    local json="{"
    
    # DISC_METADATA zu JSON
    json+='"metadata":{'
    local first=true
    for key in "${!DISC_METADATA[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            json+=","
        fi
        json+="\"$key\":\"${DISC_METADATA[$key]}\""
    done
    json+='}'
    
    # DISC_DATA zu JSON
    json+=',"data":{'
    first=true
    for key in "${!DISC_DATA[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            json+=","
        fi
        json+="\"$key\":\"${DISC_DATA[$key]}\""
    done
    json+='}'
    
    json+="}"
    echo "$json"
}

# =============================================================================
# HELPER FUNKTIONEN
# =============================================================================

# ===========================================================================
# metadb_sanitize_filename
# ---------------------------------------------------------------------------
# Funktion.: Bereinige String für Dateinamen
# Parameter: $1 = input_string
# Rückgabe.: Sanitized String (lowercase, alphanumerisch + underscores)
# ===========================================================================
metadb_sanitize_filename() {
    local input="$1"
    echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//'
}

# ===========================================================================
# metadb_validate
# ---------------------------------------------------------------------------
# Funktion.: Validiere ob Pflichtfelder gesetzt sind
# Rückgabe.: 0 = Valid, 1 = Invalid
# ===========================================================================
metadb_validate() {
    local disc_type="${DISC_METADATA[disc_type]}"
    
    # Basis-Validierung
    if [[ -z "$disc_type" ]]; then
        log_error "metadb_validate: disc_type fehlt"
        return 1
    fi
    
    if [[ -z "${DISC_METADATA[disc_label]}" ]]; then
        log_warning "metadb_validate: disc_label fehlt"
    fi
    
    # Typ-spezifische Validierung
    case "$disc_type" in
        audio-cd)
            if [[ -z "${DISC_DATA[artist]}" ]] || [[ -z "${DISC_DATA[album]}" ]]; then
                log_warning "metadb_validate: Audio-CD ohne artist/album"
            fi
            ;;
        dvd-video|bd-video)
            if [[ -z "${DISC_DATA[title]}" ]]; then
                log_warning "metadb_validate: Video ohne title"
            fi
            ;;
    esac
    
    return 0
}

# ===========================================================================
# metadb_dump
# ---------------------------------------------------------------------------
# Funktion.: Debug-Ausgabe aller Metadaten
# Rückgabe.: Mehrzeilige String-Ausgabe
# ===========================================================================
metadb_dump() {
    echo "=== DISC_METADATA ==="
    for key in "${!DISC_METADATA[@]}"; do
        echo "  $key = ${DISC_METADATA[$key]}"
    done
    
    echo ""
    echo "=== DISC_DATA ==="
    for key in "${!DISC_DATA[@]}"; do
        echo "  $key = ${DISC_DATA[$key]}"
    done
}

################################################################################
# ENDE libmetadb.sh
################################################################################
