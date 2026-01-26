#!/bin/bash
################################################################################
# disk2iso v1.2.0 - Metadata Framework (Core)
# Filepath: lib/libmetadata.sh
#
# Beschreibung:
#   Zentrales Metadata-Framework für alle Disc-Typen
#   - Provider-Registrierungs-System (MusicBrainz, TMDB, Discogs, etc.)
#   - Generic Query/Wait/Apply Workflow
#   - Cache-Management
#   - State-Machine Integration
#
# Version: 1.2.1
# Datum: 20.01.2026
################################################################################

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================
# Globale Variable für Modulname
readonly MODULE_NAME_METADATA="metadata"
# Globale Variable für Verfügbarkeit
METADATA_SUPPORT=false

# ===========================================================================
# check_dependencies_metadata
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
check_dependencies_metadata() {

    #-- Alle Modul Abhängikeiten prüfen -------------------------------------
    check_module_dependencies "$MODULE_NAME_METADATA" || return 1

    #-- Setze Verfügbarkeit -------------------------------------------------
    METADATA_SUPPORT=true
    
    #-- Abhängigkeiten erfüllt ----------------------------------------------
    log_info "$MSG_METADATA_SUPPORT_AVAILABLE"
    return 0
}


# ============================================================================
# GLOBALE VARIABLEN
# ============================================================================

# Assoziative Arrays für Provider-Registrierung
declare -A METADATA_PROVIDERS          # Provider-Name → Disc-Types
declare -A METADATA_QUERY_FUNCS        # Provider-Name → Query-Funktion
declare -A METADATA_PARSE_FUNCS        # Provider-Name → Parse-Funktion
declare -A METADATA_APPLY_FUNCS        # Provider-Name → Apply-Funktion

# Provider-Konfiguration pro Disc-Type
declare -A METADATA_DISC_PROVIDERS     # Disc-Type → Provider-Name

# Cache-Verzeichnisse
METADATA_CACHE_BASE=""

# ===========================================================================
# PATH CONSTANTS / GETTER
# ===========================================================================

readonly METADATA_DIR="metadata"               # Basisverzeichnis für Metadata




# ============================================================================
# PROVIDER REGISTRATION SYSTEM
# ============================================================================

# Funktion: Registriere Metadata-Provider
# Parameter: $1 = provider_name (z.B. "musicbrainz", "tmdb")
#            $2 = disc_types (komma-separiert: "audio-cd" oder "dvd-video,bd-video")
#            $3 = query_function (Name der Query-Funktion)
#            $4 = parse_function (Name der Parse-Funktion)
#            $5 = apply_function (Name der Apply-Funktion, optional)
# Rückgabe: 0 = Erfolg, 1 = Fehler
metadata_register_provider() {
    local provider="$1"
    local disc_types="$2"
    local query_func="$3"
    local parse_func="$4"
    local apply_func="${5:-metadata_default_apply}"
    
    # Validierung
    if [[ -z "$provider" ]] || [[ -z "$disc_types" ]] || [[ -z "$query_func" ]] || [[ -z "$parse_func" ]]; then
        log_error "Metadata: Provider-Registrierung fehlgeschlagen - unvollständige Parameter"
        return 1
    fi
    
    # Prüfe ob Funktionen existieren
    if ! declare -f "$query_func" >/dev/null 2>&1; then
        log_error "Metadata: Query-Funktion '$query_func' nicht gefunden"
        return 1
    fi
    
    if ! declare -f "$parse_func" >/dev/null 2>&1; then
        log_error "Metadata: Parse-Funktion '$parse_func' nicht gefunden"
        return 1
    fi
    
    # Registriere Provider
    METADATA_PROVIDERS["$provider"]="$disc_types"
    METADATA_QUERY_FUNCS["$provider"]="$query_func"
    METADATA_PARSE_FUNCS["$provider"]="$parse_func"
    METADATA_APPLY_FUNCS["$provider"]="$apply_func"
    
    # Registriere Provider für jeden Disc-Type
    IFS=',' read -ra types <<< "$disc_types"
    for disc_type in "${types[@]}"; do
        disc_type=$(echo "$disc_type" | xargs)  # Trim whitespace
        METADATA_DISC_PROVIDERS["$disc_type"]="$provider"
    done
    
    log_info "Metadata: Provider '$provider' registriert für: $disc_types"
    return 0
}

# Funktion: Hole Provider für Disc-Type
# Parameter: $1 = disc_type (z.B. "audio-cd", "dvd-video")
# Rückgabe: Provider-Name oder leer bei Fehler
metadata_get_provider() {
    local disc_type="$1"
    
    # Prüfe Konfiguration (User-Override)
    local config_var="METADATA_${disc_type^^}_PROVIDER"
    config_var="${config_var//-/_}"  # Ersetze - durch _
    local configured_provider="${!config_var}"
    
    if [[ -n "$configured_provider" ]]; then
        echo "$configured_provider"
        return 0
    fi
    
    # Fallback: Registrierter Provider
    local provider="${METADATA_DISC_PROVIDERS[$disc_type]}"
    if [[ -n "$provider" ]]; then
        echo "$provider"
        return 0
    fi
    
    return 1
}

# Funktion: Liste alle registrierten Provider
# Rückgabe: JSON-Array mit Provider-Info
metadata_list_providers() {
    local providers_json="["
    local first=true
    
    for provider in "${!METADATA_PROVIDERS[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            providers_json+=","
        fi
        
        local disc_types="${METADATA_PROVIDERS[$provider]}"
        providers_json+="{\"name\":\"$provider\",\"disc_types\":\"$disc_types\"}"
    done
    
    providers_json+="]"
    echo "$providers_json"
}

# ============================================================================
# CACHE MANAGEMENT
# ============================================================================

# Funktion: Initialisiere Metadata Cache-Verzeichnisse
# Parameter: Keine
# Rückgabe: 0 = Erfolg, 1 = Fehler
metadata_init_cache() {
    if [[ -n "$METADATA_CACHE_BASE" ]]; then
        return 0  # Bereits initialisiert
    fi
    
    # Nutze ensure_subfolder() falls verfügbar
    if declare -f ensure_subfolder >/dev/null 2>&1; then
        METADATA_CACHE_BASE=$(ensure_subfolder "metadata")
    else
        # Fallback
        METADATA_CACHE_BASE="${OUTPUT_DIR}/../metadata"
        mkdir -p "$METADATA_CACHE_BASE" 2>/dev/null
    fi
    
    if [[ ! -d "$METADATA_CACHE_BASE" ]]; then
        log_error "Metadata: Cache-Verzeichnis konnte nicht erstellt werden: $METADATA_CACHE_BASE"
        return 1
    fi
    
    log_info "Metadata: Cache initialisiert: $METADATA_CACHE_BASE"
    return 0
}

# Funktion: Hole Cache-Pfad für Provider
# Parameter: $1 = provider_name
# Rückgabe: Pfad zum Provider-Cache-Verzeichnis
metadata_get_cache_dir() {
    local provider="$1"
    
    metadata_init_cache || return 1
    
    local cache_dir="${METADATA_CACHE_BASE}/${provider}"
    mkdir -p "$cache_dir" 2>/dev/null
    
    echo "$cache_dir"
}

# ============================================================================
# QUERY WORKFLOW
# ============================================================================

# Funktion: Query Metadata von Provider (BEFORE Copy)
# Parameter: $1 = disc_type (z.B. "audio-cd", "dvd-video")
#            $2 = search_term (z.B. "Artist - Album" oder "Movie Title")
#            $3 = disc_id (für Query-Datei)
#            $4+ = Provider-spezifische Parameter (optional)
# Rückgabe: 0 = Query erfolgreich, 1 = Fehler
metadata_query_before_copy() {
    local disc_type="$1"
    local search_term="$2"
    local disc_id="$3"
    shift 3
    local extra_params=("$@")
    
    # Hole konfigurierten Provider
    local provider
    provider=$(metadata_get_provider "$disc_type")
    
    if [[ -z "$provider" ]]; then
        log_warning "Metadata: Kein Provider für '$disc_type' konfiguriert"
        return 1
    fi
    
    # Hole Query-Funktion
    local query_func="${METADATA_QUERY_FUNCS[$provider]}"
    
    if [[ -z "$query_func" ]]; then
        log_error "Metadata: Query-Funktion für Provider '$provider' nicht registriert"
        return 1
    fi
    
    log_info "Metadata: Query via Provider '$provider' für '$search_term'"
    
    # Rufe Provider-spezifische Query-Funktion auf
    # Übergebe: disc_type, search_term, disc_id, extra_params
    "$query_func" "$disc_type" "$search_term" "$disc_id" "${extra_params[@]}"
    
    return $?
}

# ============================================================================
# WAIT FOR SELECTION WORKFLOW
# ============================================================================

# Funktion: Warte auf User-Metadata-Auswahl (Generic)
# Parameter: $1 = disc_type
#            $2 = disc_id
#            $3 = provider (optional, auto-detect wenn leer)
# Rückgabe: 0 = Auswahl getroffen, 1 = Timeout/Skip
# Setzt globale Variablen je nach Provider (z.B. cd_artist, dvd_title)
metadata_wait_for_selection() {
    local disc_type="$1"
    local disc_id="$2"
    local provider="${3:-}"
    
    # Auto-detect Provider falls nicht übergeben
    if [[ -z "$provider" ]]; then
        provider=$(metadata_get_provider "$disc_type")
        
        if [[ -z "$provider" ]]; then
            log_error "Metadata: Kein Provider für '$disc_type' gefunden"
            return 1
        fi
    fi
    
    # Bestimme Query-Datei-Pattern basierend auf Provider
    local output_base
    output_base=$(get_type_subfolder "$disc_type" 2>/dev/null) || output_base="${OUTPUT_DIR}"
    
    local query_file="${output_base}/${disc_id}_${provider}.${provider}query"
    local select_file="${output_base}/${disc_id}_${provider}.${provider}select"
    
    # Prüfe ob Query-Datei existiert
    if [[ ! -f "$query_file" ]]; then
        log_warning "Metadata: Query-Datei nicht gefunden: $(basename "$query_file")"
        return 1
    fi
    
    # Warte auf Selection-Datei
    local timeout="${METADATA_SELECTION_TIMEOUT:-60}"
    local elapsed=0
    local check_interval=1
    
    log_info "Metadata: Warte auf $provider Metadata-Auswahl (Timeout: ${timeout}s)..."
    
    # State: waiting_for_metadata
    if declare -f transition_to_state >/dev/null 2>&1; then
        transition_to_state "$STATE_WAITING_FOR_METADATA" "Warte auf $provider Metadata-Auswahl"
    fi
    
    while [[ $elapsed -lt $timeout ]]; do
        # Prüfe ob Selection-Datei existiert
        if [[ -f "$select_file" ]]; then
            log_info "Metadata: Auswahl erhalten nach ${elapsed}s"
            
            # Lese Auswahl
            local selected_index
            selected_index=$(jq -r '.selected_index' "$select_file" 2>/dev/null || echo "-1")
            
            # Skip?
            if [[ "$selected_index" == "-1" ]] || [[ "$selected_index" == "skip" ]]; then
                log_info "Metadata: Auswahl übersprungen - verwende generische Namen"
                rm -f "$query_file" "$select_file" 2>/dev/null
                return 1
            fi
            
            # Rufe Provider-spezifische Parse-Funktion auf
            local parse_func="${METADATA_PARSE_FUNCS[$provider]}"
            
            if [[ -z "$parse_func" ]]; then
                log_error "Metadata: Parse-Funktion für Provider '$provider' nicht registriert"
                rm -f "$query_file" "$select_file" 2>/dev/null
                return 1
            fi
            
            # Parse Selection (setzt globale Variablen)
            if "$parse_func" "$selected_index" "$query_file" "$select_file"; then
                log_info "Metadata: Auswahl erfolgreich geparst"
                rm -f "$query_file" "$select_file" 2>/dev/null
                return 0
            else
                log_error "Metadata: Parse fehlgeschlagen"
                rm -f "$query_file" "$select_file" 2>/dev/null
                return 1
            fi
        fi
        
        sleep "$check_interval"
        ((elapsed += check_interval))
        
        # Progress-Log alle 10 Sekunden
        if (( elapsed % 10 == 0 )); then
            log_info "Metadata: Warte auf Auswahl... (${elapsed}/${timeout}s)"
        fi
    done
    
    # Timeout erreicht
    log_warning "Metadata: Auswahl Timeout nach ${timeout}s - verwende generische Namen"
    rm -f "$query_file" "$select_file" 2>/dev/null
    return 1
}

# ============================================================================
# APPLY SELECTION WORKFLOW
# ============================================================================

# Funktion: Wende Metadata-Auswahl auf disc_label an (Default Implementation)
# Parameter: $1 = provider
#            $2 = metadata (JSON oder Key-Value)
# Rückgabe: 0 = Erfolg
# Setzt: disc_label global
metadata_default_apply() {
    local provider="$1"
    local metadata="$2"
    
    log_info "Metadata: Default-Apply für Provider '$provider'"
    
    # Default: Keine Änderung an disc_label
    # Provider-spezifische Apply-Funktionen überschreiben dies
    
    return 0
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Funktion: Bereinige Metadata-Query/Select-Dateien
# Parameter: $1 = disc_id
#            $2 = disc_type
#            $3 = provider (optional)
metadata_cleanup() {
    local disc_id="$1"
    local disc_type="$2"
    local provider="${3:-}"
    
    local output_base
    output_base=$(get_type_subfolder "$disc_type" 2>/dev/null) || output_base="${OUTPUT_DIR}"
    
    if [[ -n "$provider" ]]; then
        # Cleanup für spezifischen Provider
        rm -f "${output_base}/${disc_id}_${provider}."* 2>/dev/null
    else
        # Cleanup für alle Provider
        rm -f "${output_base}/${disc_id}_"*.{mbquery,mbselect,tmdbquery,tmdbselect,discogsquery,discogsselect} 2>/dev/null
    fi
    
    log_info "Metadata: Cleanup abgeschlossen für disc_id '$disc_id'"
}

# Funktion: Sanitize String für Dateinamen
# Parameter: $1 = Input-String
# Rückgabe: Sanitized String
metadata_sanitize_filename() {
    local input="$1"
    
    # Lowercase + nur Alphanumerisch + Underscores
    echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//'
}

# ============================================================================
# CONFIGURATION
# ============================================================================

# Funktion: Lade Metadata-Konfiguration aus Config-Datei
# Liest: METADATA_AUDIO_PROVIDER, METADATA_VIDEO_PROVIDER, etc.
metadata_load_config() {
    # Diese Funktion wird von libconfig.sh aufgerufen
    # Config-Variablen sind bereits geladen
    
    log_info "Metadata: Konfiguration geladen"
    
    # Debug: Zeige konfigurierte Provider
    if [[ -n "${METADATA_AUDIO_PROVIDER:-}" ]]; then
        log_info "Metadata: Audio-Provider = $METADATA_AUDIO_PROVIDER"
    fi
    
    if [[ -n "${METADATA_VIDEO_PROVIDER:-}" ]]; then
        log_info "Metadata: Video-Provider = $METADATA_VIDEO_PROVIDER"
    fi
    
    return 0
}

################################################################################
# ENDE libmetadata.sh
################################################################################
