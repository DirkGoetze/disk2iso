#!/bin/bash
# ===========================================================================
# Metadata Framework
# ===========================================================================
# Filepath: lib/libmetadata.sh
#
# Beschreibung:
#   Zentrales Metadata-Framework für alle Disc-Typen
#   - Provider-Registrierungs-System (MusicBrainz, TMDB, Discogs, etc.)
#   - Generic Query/Wait/Apply Workflow
#   - Cache-Management
#   - State-Machine Integration
#
# ---------------------------------------------------------------------------
# Dependencies: liblogging, libapi (provider modules are optional)
# ---------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.2.1
# Last Change: 2026-01-26 20:00
# ===========================================================================

# ===========================================================================
# MODULE NAME
# ===========================================================================
readonly MODULE_NAME_METADATA="metadata"     # Globale Variable für Modulname

# ===========================================================================
# DEPENDENCY CHECK
# ===========================================================================
SUPPORT_METADATA=false                                # Globales Support Flag
INITIALIZED_METADATA=false                  # Initialisierung war erfolgreich

# ===========================================================================
# check_dependencies_metadata
# ---------------------------------------------------------------------------
# Funktion.: Prüfe alle Modul-Abhängigkeiten (Modul-Dateien, Ausgabe-Ordner, 
# .........  kritische und optionale Software für die Ausführung des Modul),
# .........  lädt nach erfolgreicher Prüfung die Sprachdatei für das Modul.
# Parameter: keine
# Rückgabe.: 0 = Verfügbar (Module nutzbar)
# .........  1 = Nicht verfügbar (Modul deaktiviert)
# Extras...: Setzt SUPPORT_METADATA=true/false
# ===========================================================================
check_dependencies_metadata() {
    log_debug "$MSG_DEBUG_METADATA_CHECK_START"

    #-- Alle Modul Abhängikeiten prüfen -------------------------------------
    check_module_dependencies "$MODULE_NAME_METADATA" || return 1

    #-- Lade METADATA Konfiguration -----------------------------------------
    load_metadata_config || return 1
    log_debug "$MSG_DEBUG_METADATA_CONFIG_LOADED"

    #-- Lade registrierte Provider ------------------------------------------
    metadata_load_registered_providers
    # HINWEIS: Provider laden ist optional (return code wird ignoriert)
    # Framework ist auch ohne Provider funktionsfähig

    #-- Setze Verfügbarkeit -------------------------------------------------
    SUPPORT_METADATA=true
    log_debug "$MSG_DEBUG_METADATA_CHECK_COMPLETE"
    
    #-- Abhängigkeiten erfüllt ----------------------------------------------
    log_info "$MSG_METADATA_SUPPORT_AVAILABLE"
    return 0
}

# ===========================================================================
# is_metadata_ready
# ---------------------------------------------------------------------------
# Funktion.: Prüfe ob METADATA Modul supported wird und initialisiert wurde 
# .........  Wenn true ist alles bereit ist für die Nutzung.
# Parameter: keine
# Rückgabe.: 0 = Bereit, 1 = Nicht bereit
# ===========================================================================
is_metadata_ready() {
    #-- Prüfe Support (Abhängikeiten erfüllt) -------------------------------
    if [[ "$SUPPORT_METADATA" != "true" ]]; then
        log_debug "$MSG_DEBUG_METADATA_NOT_SUPPORTED"
        return 1
    fi
    
    #-- Prüfe Initialisierung (Konfiguration geladen) -----------------------
    if [[ "$INITIALIZED_METADATA" != "true" ]]; then
        log_debug "$MSG_DEBUG_METADATA_NOT_INITIALIZED"
        return 1
    fi
    
    #-- Alles bereit --------------------------------------------------------
    log_debug "$MSG_DEBUG_METADATA_READY"
    return 0
}

# ===========================================================================
# PATH GETTER
# ===========================================================================

# ===========================================================================
# get_path_metadata
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Ausgabepfad des Modul für die Verwendung in anderen
# .........  abhängigen Modulen
# Parameter: keine
# Rückgabe.: Vollständiger Pfad zum Modul Verzeichnis
# Hinweis..: Ordner wird bereits in check_module_dependencies() erstellt
# .........  Provider legen hier ihre Unterordner an (musicbrainz/, tmdb/)
# ===========================================================================
get_path_metadata() {
    #-- Bestimme Ausgabeordner des Moduls -----------------------------------
    local metadata_dir="${OUTPUT_DIR}/${MODULE_NAME_METADATA}"

    #-- Debug Meldung und Rückgabe ------------------------------------------
    log_debug "$MSG_DEBUG_METADATA_PATH ${metadata_dir}"
    echo "${metadata_dir}"
    return 0
}

# ===========================================================================
# METADATA CONFIGURATION / INITIALIZATION
# ===========================================================================

# ===========================================================================
# _metadata_get_defaults
# ---------------------------------------------------------------------------
# Funktion.: Liefert die Standardwerte für Metadata Konfigurationsvariablen
# Parameter: $1 = Key (z.B. METADATA_SELECTION_TIMEOUT)
# Rückgabe.: Standardwert für den Key oder leer wenn nicht definiert
# Hinweis..: Private Funktion (Präfix _)
# ===========================================================================
_metadata_get_defaults() {
    local key="$1"

    case "$key" in
        METADATA_SELECTION_TIMEOUT) echo "60" ;;
        METADATA_CACHE_ENABLED) echo "true" ;;
        METADATA_CHECK_INTERVAL) echo "1" ;;
        METADATA_DEFAULT_APPLY_FUNC) echo "metadata_default_apply" ;;
        *) echo "" ;;
    esac
}

# ===========================================================================
# load_metadata_config
# ---------------------------------------------------------------------------
# Funktion.: Lädt die Metadata Konfiguration und setzt Standardwerte
# .........  für nicht definierte Variablen.
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
load_metadata_config() {
    #-- Lokale Variablen ----------------------------------------------------
    local selection_timeout cache_enabled check_interval default_apply_func

    #-- Ermittle Pfad zur Modul INI -----------------------------------------
    local ini_file=$(get_module_ini_path "$MODULE_NAME_METADATA")

    #-- Lese METADATA-Konfiguration aus INI (falls existiert) ---------------
    if [[ -f "$ini_file" ]]; then
        selection_timeout=$(get_ini_value "$ini_file" "framework" "selection_timeout")
        cache_enabled=$(get_ini_value "$ini_file" "framework" "cache_enabled")
        check_interval=$(get_ini_value "$ini_file" "framework" "check_interval")
        default_apply_func=$(get_ini_value "$ini_file" "framework" "default_apply_func")
    else
        log_warning "$MSG_METADATA_INI_NOT_FOUND: $ini_file"
    fi

    #-- Setze Variablen mit Defaults (INI-Werte überschreiben Defaults) -----
    #-- Prüfe zuerst ob Wert bereits aus disk2iso.conf gesetzt wurde --------
    #-- Nutzt _metadata_get_defaults() für konsistente Defaults -------------
    METADATA_SELECTION_TIMEOUT="${METADATA_SELECTION_TIMEOUT:-${selection_timeout:-$(_metadata_get_defaults "METADATA_SELECTION_TIMEOUT")}}"
    METADATA_CACHE_ENABLED="${METADATA_CACHE_ENABLED:-${cache_enabled:-$(_metadata_get_defaults "METADATA_CACHE_ENABLED")}}"
    METADATA_CHECK_INTERVAL="${METADATA_CHECK_INTERVAL:-${check_interval:-$(_metadata_get_defaults "METADATA_CHECK_INTERVAL")}}"
    METADATA_DEFAULT_APPLY_FUNC="${METADATA_DEFAULT_APPLY_FUNC:-${default_apply_func:-$(_metadata_get_defaults "METADATA_DEFAULT_APPLY_FUNC")}}"

    #-- Setze Initialisierungs-Flag -----------------------------------------
    INITIALIZED_METADATA=true

    #-- Log und Rückgabe ----------------------------------------------------
    log_info "$MSG_METADATA_CONFIG_LOADED"
    return 0
}

# ===========================================================================
# metadata_load_registered_providers
# ---------------------------------------------------------------------------
# Funktion.: Lädt alle in libmetadata.ini registrierten Provider-Module
# .........  Provider entscheiden selbst ob sie sich aktivieren (eigene INI)
# Parameter: keine
# Rückgabe.: 0 = Mindestens ein Provider geladen, 1 = Keine Provider
# Hinweis..: Wird von check_dependencies_metadata() aufgerufen
# .........  Return-Code wird ignoriert (Framework funktioniert ohne Provider)
# ===========================================================================
metadata_load_registered_providers() {
    local ini_file=$(get_module_ini_path "$MODULE_NAME_METADATA")
    local providers_loaded=0
    
    #-- Prüfe ob INI existiert ----------------------------------------------
    if [[ ! -f "$ini_file" ]]; then
        log_debug "Metadata: Keine Provider-Konfiguration gefunden: $ini_file"
        return 1
    fi
    
    #-- Lese alle Provider aus [providers] Sektion -------------------------
    local provider_keys=$(get_ini_section_keys "$ini_file" "providers")
    
    if [[ -z "$provider_keys" ]]; then
        log_info "Metadata: Keine Provider installiert"
        return 1
    fi
    
    log_debug "Metadata: Gefundene Provider in INI: $provider_keys"
    
    #-- Lade jeden installierten Provider ----------------------------------
    for provider_name in $provider_keys; do
        local is_installed=$(get_ini_value "$ini_file" "providers" "$provider_name")
        
        #-- Prüfe Installation-Status (nur true/false) ----------------------
        if [[ "$is_installed" != "true" ]]; then
            log_debug "Metadata: Provider '$provider_name' nicht installiert (Wert: $is_installed) - überspringe"
            continue
        fi
        
        #-- Lade Provider-Modul ---------------------------------------------
        local provider_file="${SCRIPT_DIR}/lib/lib${provider_name}.sh"
        
        if [[ ! -f "$provider_file" ]]; then
            log_warning "Metadata: Provider-Datei nicht gefunden: $provider_file"
            continue
        fi
        
        log_debug "Metadata: Lade Provider-Modul: $provider_name"
        
        #-- Source Provider-Modul (Fehler werden nicht abgefangen) ----------
        if ! source "$provider_file" 2>/dev/null; then
            log_error "Metadata: Fehler beim Laden von $provider_file"
            continue
        fi
        
        #-- Rufe standardisierte Init-Funktion auf -------------------------
        # Provider entscheidet selbst ob er sich registriert (prüft eigene INI)
        # Naming-Convention: init_<provider>_provider()
        local init_func="init_${provider_name}_provider"
        
        if declare -f "$init_func" >/dev/null 2>&1; then
            log_debug "Metadata: Rufe Init-Funktion auf: $init_func"
            
            #-- Führe Provider-Init aus -------------------------------------
            if "$init_func"; then
                ((providers_loaded++))
                log_info "Metadata: Provider erfolgreich initialisiert: $provider_name"
            else
                #-- Provider hat sich nicht registriert (z.B. deaktiviert) --
                log_debug "Metadata: Provider nicht aktiviert: $provider_name"
            fi
        else
            log_warning "Metadata: Init-Funktion nicht gefunden: $init_func (Provider: $provider_name)"
        fi
    done
    
    #-- Rückgabe ------------------------------------------------------------
    if [[ $providers_loaded -gt 0 ]]; then
        log_info "Metadata: $providers_loaded Provider erfolgreich geladen"
        return 0
    else
        log_info "Metadata: Keine Provider aktiv (Framework läuft ohne Provider-Support)"
        return 1
    fi
}

# ===========================================================================
# PROVIDER VERWALTUNG
# ===========================================================================

# Assoziative Arrays für Provider-Registrierung
declare -A METADATA_PROVIDERS          # Provider-Name → Disc-Types
declare -A METADATA_QUERY_FUNCS        # Provider-Name → Query-Funktion
declare -A METADATA_PARSE_FUNCS        # Provider-Name → Parse-Funktion
declare -A METADATA_APPLY_FUNCS        # Provider-Name → Apply-Funktion
declare -A METADATA_DISC_PROVIDERS     # Disc-Type → Provider-Name

# ===========================================================================
# metadata_register_provider
# ---------------------------------------------------------------------------
# Funktion.: Registriere Metadata-Provider
# Parameter: $1 = provider_name (z.B. "musicbrainz", "tmdb")
# .........  $2 = disc_types (komma-separiert: "audio-cd" oder "dvd-video,bd-video")
# .........  $3 = query_function (Name der Query-Funktion)
# .........  $4 = parse_function (Name der Parse-Funktion)
# .........  $5 = apply_function (Name der Apply-Funktion, optional)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
metadata_register_provider() {
    #-- Lokale Variablen ----------------------------------------------------
    local provider="$1"
    local disc_types="$2"
    local query_func="$3"
    local parse_func="$4"
    local apply_func="${5:-metadata_default_apply}"
    
    #-- Debug Start ---------------------------------------------------------
    log_debug "Metadata: Registriere Provider '$provider' (types='$disc_types', query='$query_func', parse='$parse_func', apply='$apply_func')"
    
    #-- Validierung der Parameter -------------------------------------------
    if [[ -z "$provider" ]] || [[ -z "$disc_types" ]] || [[ -z "$query_func" ]] || [[ -z "$parse_func" ]]; then
        log_error "Metadata: Provider-Registrierung fehlgeschlagen - unvollständige Parameter"
        return 1
    fi
    
    #-- Prüfe ob Provider bereits registriert -------------------------------
    if [[ -v "METADATA_PROVIDERS[$provider]" ]]; then
        log_warning "Metadata: Provider '$provider' wird überschrieben (vorher: ${METADATA_PROVIDERS[$provider]})"
    fi
    
    #-- Prüfe ob Funktionen existieren --------------------------------------
    if ! declare -f "$query_func" >/dev/null 2>&1; then
        log_error "Metadata: Query-Funktion '$query_func' nicht gefunden"
        return 1
    fi
    log_debug "Metadata: Query-Funktion '$query_func' gefunden"
    
    if ! declare -f "$parse_func" >/dev/null 2>&1; then
        log_error "Metadata: Parse-Funktion '$parse_func' nicht gefunden"
        return 1
    fi
    log_debug "Metadata: Parse-Funktion '$parse_func' gefunden"
    
    #-- Prüfe Apply-Funktion (falls nicht default) --------------------------
    if [[ "$apply_func" != "metadata_default_apply" ]] && ! declare -f "$apply_func" >/dev/null 2>&1; then
        log_warning "Metadata: Apply-Funktion '$apply_func' nicht gefunden - verwende Default"
        apply_func="metadata_default_apply"
    fi
    log_debug "Metadata: Apply-Funktion '$apply_func' registriert"
    
    #-- Registriere Provider ------------------------------------------------
    METADATA_PROVIDERS["$provider"]="$disc_types"
    METADATA_QUERY_FUNCS["$provider"]="$query_func"
    METADATA_PARSE_FUNCS["$provider"]="$parse_func"
    METADATA_APPLY_FUNCS["$provider"]="$apply_func"
    log_debug "Metadata: Provider-Funktionen registriert"
    
    #-- Registriere Provider für jeden Disc-Type ---------------------------- 
    IFS=',' read -ra types <<< "$disc_types"
    for disc_type in "${types[@]}"; do
        disc_type=$(echo "$disc_type" | xargs)  # Trim whitespace
        
        # Prüfe ob Provider für diesen Disc-Type bereits existiert
        if [[ -v "METADATA_DISC_PROVIDERS[$disc_type]" ]]; then
            local existing_providers="${METADATA_DISC_PROVIDERS[$disc_type]}"
            
            # Prüfe ob Provider bereits in Liste
            if [[ ",$existing_providers," == *",$provider,"* ]]; then
                log_warning "Metadata: Provider '$provider' bereits für Disc-Type '$disc_type' registriert - überspringe"
                continue
            fi
            
            # Füge Provider zur Liste hinzu
            METADATA_DISC_PROVIDERS["$disc_type"]="${existing_providers},${provider}"
            log_debug "Metadata: Disc-Type '$disc_type' → Provider-Liste erweitert: ${METADATA_DISC_PROVIDERS[$disc_type]}"
        else
            # Erster Provider für diesen Disc-Type
            METADATA_DISC_PROVIDERS["$disc_type"]="$provider"
            log_debug "Metadata: Disc-Type '$disc_type' → Provider '$provider' (erster)"
        fi
    done

    #-- Log und Rückgabe ----------------------------------------------------    
    log_info "Metadata: Provider '$provider' registriert für: $disc_types"
    return 0
}

# ===========================================================================
# metadata_can_register_provider
# ---------------------------------------------------------------------------
# Funktion.: Prüfe ob Provider-Registrierung möglich ist
# Parameter: keine
# Rückgabe.: 0 = Registrierung möglich, 1 = Framework nicht bereit
# Hinweis..: Provider-Module sollten dies prüfen bevor sie sich registrieren
# ===========================================================================
metadata_can_register_provider() {
    #-- Prüfe ob Framework bereit ist ---------------------------------------
    if ! is_metadata_ready; then
        log_debug "Metadata: Framework nicht bereit - Provider-Registrierung nicht möglich"
        return 1
    fi
    
    log_debug "Metadata: Framework bereit - Provider-Registrierung möglich"
    return 0
}

# ===========================================================================
# metadata_get_provider
# ---------------------------------------------------------------------------
# Funktion.: Hole Provider für Disc-Type
# Parameter: $1 = disc_type (z.B. "audio-cd", "dvd-video")
# Rückgabe.: Provider-Name (stdout) + Return-Code (0 = gefunden, 1 = nicht gefunden)
# Hinweis..: Gibt ersten Provider aus Liste zurück (oder konfigurierten)
# .........  Priorität: 1) Config-Override, 2) Erster registrierter Provider
# ===========================================================================
metadata_get_provider() {
    local disc_type="$1"
    
    #-- Validierung ---------------------------------------------------------
    if [[ -z "$disc_type" ]]; then
        log_error "Metadata: metadata_get_provider() benötigt disc_type Parameter"
        return 1
    fi
    
    #-- Prüfe ob Framework bereit ist ---------------------------------------
    if ! is_metadata_ready; then
        log_debug "Metadata: Framework nicht bereit"
        return 1
    fi
    
    #-- Prüfe Konfiguration (User-Override - höchste Priorität) -------------
    local config_var="METADATA_${disc_type^^}_PROVIDER"
    config_var="${config_var//-/_}"  # Ersetze - durch _
    local configured_provider="${!config_var}"
    
    if [[ -n "$configured_provider" ]]; then
        log_debug "Metadata: Verwende konfigurierten Provider '$configured_provider' für '$disc_type'"
        echo "$configured_provider"
        return 0
    fi
    
    #-- Fallback: Registrierte Provider-Liste -------------------------------
    local provider_list="${METADATA_DISC_PROVIDERS[$disc_type]}"
    if [[ -n "$provider_list" ]]; then
        # Nimm ersten Provider aus komma-separierter Liste
        local first_provider="${provider_list%%,*}"
        log_debug "Metadata: Verwende ersten Provider '$first_provider' für '$disc_type' (verfügbar: $provider_list)"
        echo "$first_provider"
        return 0
    fi
    
    #-- Kein Provider gefunden ----------------------------------------------
    log_debug "Metadata: Kein Provider für Disc-Type '$disc_type' gefunden"
    return 1
}


# TODO: Nächste Schritte:
# metadata_get_provider_for_type()    # disk2iso holt Provider-Namen
# metadata_list_providers()           # Debug/Info-Funktion

# TODO: Ab hier ist das Modul noch nicht fertig implementiert!

# ============================================================================
# GLOBALE VARIABLEN
# ============================================================================


# Cache-Verzeichnisse
METADATA_CACHE_BASE=""

# ============================================================================
# PROVIDER REGISTRATION SYSTEM
# ============================================================================



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
    provider=$(metadata_get_provider "$(discinfo_get_type)")
    
    if [[ -z "$provider" ]]; then
        log_warning "Metadata: Kein Provider für '$(discinfo_get_type)' konfiguriert"
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
    "$query_func" "$(discinfo_get_type)" "$search_term" "$disc_id" "${extra_params[@]}"
    
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
# Setzt Metadaten via metadb_set() statt globaler Variablen
metadata_wait_for_selection() {
    local disc_type="$1"
    local disc_id="$2"
    local provider="${3:-}"
    
    # Auto-detect Provider falls nicht übergeben
    if [[ -z "$provider" ]]; then
        provider=$(metadata_get_provider "$(discinfo_get_type)")
        
        if [[ -z "$provider" ]]; then
            log_error "Metadata: Kein Provider für '$(discinfo_get_type)' gefunden"
            return 1
        fi
    fi
    
    # Bestimme Query-Datei-Pattern basierend auf Provider
    local output_base
    output_base=$(get_type_subfolder "$(discinfo_get_type)" 2>/dev/null) || output_base="${OUTPUT_DIR}"
    
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
            
            # Parse Selection (setzt Metadaten via metadb_set())
            # HINWEIS: Provider-Parse-Funktionen müssen metadb_set() verwenden
            if "$parse_func" "$selected_index" "$query_file" "$select_file"; then
                log_info "Metadata: Auswahl erfolgreich geparst"
                
                # Validiere Metadaten
                if metadb_validate; then
                    log_info "Metadata: Metadaten validiert"
                fi
                
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
    output_base=$(get_type_subfolder "$(discinfo_get_type)" 2>/dev/null) || output_base="${OUTPUT_DIR}"
    
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


# ============================================================================
# NFO EXPORT - JELLYFIN FORMAT
# ============================================================================

# ===========================================================================
# metadata_export_nfo
# ---------------------------------------------------------------------------
# Funktion.: Exportiere Metadaten als NFO-Datei (Jellyfin-Format)
# Parameter: $1 = nfo_file_path
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: Format abhängig von disc_type, nutzt DISC_INFO/DISC_DATA Arrays
# ===========================================================================
metadata_export_nfo() {
    local nfo_file="$1"
    local disc_type
    disc_type=$(discinfo_get_type)
    
    # Validierung
    if [[ -z "$nfo_file" ]]; then
        log_error "metadata_export_nfo: nfo_file fehlt"
        return 1
    fi
    
    case "$disc_type" in
        audio-cd)
            _metadata_export_audio_nfo "$nfo_file"
            ;;
        dvd-video|bd-video)
            _metadata_export_video_nfo "$nfo_file"
            ;;
        data|data-cd|data-dvd)
            _metadata_export_data_nfo "$nfo_file"
            ;;
        *)
            log_error "metadata_export_nfo: Unbekannter disc_type '$disc_type'"
            return 1
            ;;
    esac
    
    log_info "Metadata: NFO erstellt: $(basename "$nfo_file")"
    return 0
}

# Interne Funktion: Audio-CD NFO (album.nfo)
_metadata_export_audio_nfo() {
    local nfo_file="$1"
    
    cat > "$nfo_file" <<EOF
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<album>
  <title>${DISC_DATA[album]}</title>
  <artist>${DISC_DATA[artist]}</artist>
  <year>${DISC_DATA[year]}</year>
  <runtime>$((DISC_DATA[duration] / 60000))</runtime>
  <musicbrainzalbumid>${DISC_INFO[provider_id]}</musicbrainzalbumid>
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
_metadata_export_video_nfo() {
    local nfo_file="$1"
    
    cat > "$nfo_file" <<EOF
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<movie>
  <title>${DISC_DATA[title]}</title>
  <year>${DISC_DATA[year]}</year>
  <director>${DISC_DATA[director]}</director>
  <runtime>${DISC_DATA[runtime]}</runtime>
  <plot>${DISC_DATA[overview]}</plot>
  <tmdbid>${DISC_INFO[provider_id]}</tmdbid>
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
_metadata_export_data_nfo() {
    local nfo_file="$1"
    
    cat > "$nfo_file" <<EOF
DESCRIPTION=${DISC_DATA[description]}
BACKUP_DATE=${DISC_DATA[backup_date]}
CREATED=${DISC_INFO[created_at]}
SIZE_MB=${DISC_INFO[size_mb]}
TYPE=${DISC_INFO[type]}
EOF
}

################################################################################
# ENDE libmetadata.sh
################################################################################
