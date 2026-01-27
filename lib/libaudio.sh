#!/bin/bash
# ===========================================================================
# Audio CD Library
# ===========================================================================
# Filepath: lib/libaudio.sh
#
# Beschreibung:
#   Funktionen für Audio-CD Ripping mit MusicBrainz-Metadaten
#   - MusicBrainz-Abfrage via cd-discid
#   - CD-Ripping mit cdparanoia
#   - MP3-Encoding mit lame (VBR V2)
#   - ISO-Erstellung mit gerippten MP3s
#
# ---------------------------------------------------------------------------
# Dependencies: liblogging, libfolders, libcommon (optional: libmusicbrainz)
# ---------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.2.1
# Last Change: 2026-01-26 20:00
# ===========================================================================

# ===========================================================================
# DEPENDENCY CHECK
# ===========================================================================
readonly MODULE_NAME_AUDIO="audio"           # Globale Variable für Modulname
SUPPORT_AUDIO=false                                   # Globales Support Flag

# ===========================================================================
# check_dependencies_audio
# ---------------------------------------------------------------------------
# Funktion.: Prüfe alle Modul-Abhängigkeiten (Modul-Dateien, Ausgabe-Ordner, 
# .........  kritische und optionale Software für die Ausführung des Modul),
# .........  lädt nach erfolgreicher Prüfung die Sprachdatei für das Modul.
# Parameter: keine
# Rückgabe.: 0 = Verfügbar (Module nutzbar)
# .........  1 = Nicht verfügbar (Modul deaktiviert)
# Extras...: Setzt SUPPORT_AUDIO=true/false
# ===========================================================================
check_dependencies_audio() {
    log_debug "$MSG_DEBUG_AUDIO_CHECK_START"

    #-- Alle Modul Abhängigkeiten prüfen -------------------------------------
    check_module_dependencies "$MODULE_NAME_AUDIO" || return 1

    #-- Setze Verfügbarkeit -------------------------------------------------
    SUPPORT_AUDIO=true
    log_debug "$MSG_DEBUG_AUDIO_CHECK_COMPLETE"
    
    #-- Abhängigkeiten erfüllt ----------------------------------------------
    log_info "$MSG_AUDIO_SUPPORT_AVAILABLE"
    return 0
}

# ============================================================================
# PATH GETTER
# ============================================================================

# ===========================================================================
# get_path_audio
# ---------------------------------------------------------------------------
# Funktion.: Liefert den Ausgabepfad des Modul für die Verwendung in anderen
# .........  abhängigen Modulen
# Parameter: keine
# Rückgabe.: Vollständiger Pfad zum Modul Verzeichnis
# Hinweis: Ordner wird bereits in check_module_dependencies() erstellt
# ===========================================================================
get_path_audio() {
    echo "${OUTPUT_DIR}/${MODULE_NAME_AUDIO}"
}

# TODO: Ab hier ist das Modul noch nicht fertig implementiert!

# ============================================================================
# CD-TEXT METADATA FALLBACK
# ============================================================================

# Funktion: CD-TEXT auslesen (Fallback wenn MusicBrainz nicht verfügbar)
# Benötigt: icedax oder cd-info (aus libcdio)
# Rückgabe: Setzt globale Variablen: cd_artist, cd_album
get_cdtext_metadata() {
    cd_artist=""
    cd_album=""
    
    log_info "$MSG_TRY_CDTEXT"
    
    # Methode 1: icedax (aus cdrtools/cdrkit)
    if command -v icedax >/dev/null 2>&1; then
        local cdtext_output
        cdtext_output=$(icedax -J -H -D "$CD_DEVICE" -g 2>&1 | grep -E "^Albumtitle:|^Performer:")
        
        if [[ -n "$cdtext_output" ]]; then
            cd_album=$(echo "$cdtext_output" | grep "^Albumtitle:" | cut -d':' -f2- | xargs)
            cd_artist=$(echo "$cdtext_output" | grep "^Performer:" | cut -d':' -f2- | xargs)
            
            if [[ -n "$cd_artist" ]] && [[ -n "$cd_album" ]]; then
                log_info "$MSG_CDTEXT_FOUND $cd_artist - $cd_album"
                return 0
            fi
        fi
    fi
    
    # Methode 2: cd-info (aus libcdio-utils)
    if command -v cd-info >/dev/null 2>&1; then
        local cdtext_output
        cdtext_output=$(cd-info --no-header --no-device-info --cdtext-only "$CD_DEVICE" 2>/dev/null)
        
        if [[ -n "$cdtext_output" ]]; then
            # cd-info Format: TITLE, PERFORMER
            cd_album=$(echo "$cdtext_output" | grep -i "TITLE" | head -1 | cut -d':' -f2- | xargs)
            cd_artist=$(echo "$cdtext_output" | grep -i "PERFORMER" | head -1 | cut -d':' -f2- | xargs)
            
            if [[ -n "$cd_artist" ]] && [[ -n "$cd_album" ]]; then
                log_info "$MSG_CDTEXT_FOUND $cd_artist - $cd_album"
                return 0
            fi
        fi
    fi
    
    # Methode 3: cdda2wav (aus cdrtools)
    if command -v cdda2wav >/dev/null 2>&1; then
        local cdtext_output
        cdtext_output=$(cdda2wav -J -H -D "$CD_DEVICE" -g 2>&1 | grep -E "^Albumtitle:|^Performer:")
        
        if [[ -n "$cdtext_output" ]]; then
            cd_album=$(echo "$cdtext_output" | grep "^Albumtitle:" | cut -d':' -f2- | xargs)
            cd_artist=$(echo "$cdtext_output" | grep "^Performer:" | cut -d':' -f2- | xargs)
            
            if [[ -n "$cd_artist" ]] && [[ -n "$cd_album" ]]; then
                log_info "$MSG_CDTEXT_FOUND $cd_artist - $cd_album"
                return 0
            fi
        fi
    fi
    
    log_info "$MSG_NO_CDTEXT_FOUND"
    return 1
}

# ============================================================================
# MUSICBRAINZ METADATA ABFRAGE
# ============================================================================

# Funktion: MusicBrainz-Metadaten abrufen
# Benötigt: cd-discid, curl, jq
# Rückgabe: Setzt globale Variablen: cd_artist, cd_album, cd_year, cd_discid, mb_response, best_release_index, toc, track_count
get_musicbrainz_metadata() {
    cd_artist=""
    cd_album=""
    cd_year=""
    cd_discid=""
    mb_response=""  # Speichere vollständige Antwort für Track-Infos
    best_release_index=0  # Index des gewählten Release (bei mehreren Treffern)
    toc=""  # TOC-String für MusicBrainz
    track_count=""  # Anzahl der Tracks
    
    log_info "$MSG_RETRIEVE_METADATA"
    
    # Prüfe benötigte Tools
    if ! command -v cd-discid >/dev/null 2>&1; then
        log_warning "$MSG_WARNING_CDISCID_MISSING"
        return 1
    fi
    
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        log_warning "$MSG_WARNING_CURL_JQ_MISSING"
        return 1
    fi
    
    # Disc-ID und TOC ermitteln
    local discid_output
    discid_output=$(cd-discid "$CD_DEVICE" 2>/dev/null)
    
    if [[ -z "$discid_output" ]]; then
        log_error "$MSG_ERROR_DISCID_FAILED"
        return 1
    fi
    
    # Parse cd-discid output: discid tracks offset1 offset2 ... offsetN total_seconds
    local discid_parts=($discid_output)
    cd_discid="${discid_parts[0]}"
    track_count="${discid_parts[1]}"  # Global für spätere Verwendung
    
    log_info "$MSG_DISCID: $cd_discid ($MSG_TRACKS: $track_count)"
    
    # Ermittle Leadout-Position (letzte Position + 150 für Pregap der ersten Track)
    # cdparanoia gibt TOTAL in Frames, das ist der Leadout
    local leadout
    leadout=$(cdparanoia -Q -d "$CD_DEVICE" 2>&1 | grep "TOTAL" | awk '{print $2}')
    
    if [[ -z "$leadout" ]]; then
        log_warning "$MSG_WARNING_LEADOUT_FAILED"
        leadout="${discid_parts[-1]}"  # Fallback auf letzte Spalte
    fi
    
    # Leadout = TOTAL + 150 (Pregap)
    leadout=$((leadout + 150))
    
    # Baue TOC-String für MusicBrainz: 1+track_count+leadout+offset1+offset2+...
    toc="1+${track_count}+${leadout}"  # Global für spätere Verwendung
    for ((i=2; i<${#discid_parts[@]}-1; i++)); do
        toc="${toc}+${discid_parts[$i]}"
    done
    
    # MusicBrainz-Abfrage mit TOC statt nur Disc-ID
    local mb_url="https://musicbrainz.org/ws/2/discid/${cd_discid}?toc=${toc}&fmt=json&inc=artists+recordings"
    
    log_info "$MSG_QUERY_MUSICBRAINZ"
    mb_response=$(curl -s -A "disk2iso/1.0 (https://github.com/user/disk2iso)" "$mb_url" 2>/dev/null)
    
    if [[ -z "$mb_response" ]]; then
        log_warning "$MSG_WARNING_MUSICBRAINZ_FAILED"
        return 1
    fi
    
    # Prüfe ob Release gefunden wurde
    local releases_count
    releases_count=$(echo "$mb_response" | jq -r '.releases | length' 2>/dev/null)
    
    if [[ -z "$releases_count" ]] || [[ "$releases_count" == "0" ]] || [[ "$releases_count" == "null" ]]; then
        log_warning "$MSG_WARNING_NO_MUSICBRAINZ_ENTRY $cd_discid"
        return 1
    fi
    
    # Wähle bestes Release (falls mehrere vorhanden)
    best_release_index=0  # Global, wird auch in download_cover_art() und create_album_nfo() verwendet
    
    if [[ "$releases_count" -gt 1 ]]; then
        # Mehrere Releases gefunden - speichere für User-Auswahl
        log_warning "WARNUNG: $releases_count Releases gefunden - Benutzer-Auswahl erforderlich"
        
        # Speichere alle Releases in API-Datei für Web-Interface
        if declare -f api_write_json >/dev/null 2>&1; then
            # Extrahiere Releases-Array mit Release-ID, Cover-URL und Laufzeit
            local releases_array=$(echo "$mb_response" | jq -c '[.releases[] | {
              id: .id,
              title: .title,
              artist: (."artist-credit"[0].name // "Unknown"),
              date: (.date // "unknown"),
              country: (.country // "unknown"),
              tracks: (.media[0].tracks | length),
              label: (."label-info"[0]?.label?.name // "Unknown"),
              cover_url: (if (."cover-art-archive".front == true) then ("https://coverartarchive.org/release/" + .id + "/front-250") else null end),
              duration: (.media[0].tracks | map(.length // 0) | add)
            }]')
            
            # Baue finale JSON-Struktur
            local releases_json="{\"disc_id\":\"$cd_discid\",\"track_count\":$track_count,\"releases\":$releases_array}"
            
            api_write_json "musicbrainz_releases.json" "$releases_json"
        fi
        
        # Automatische Auswahl nach Score (kann vom User überschrieben werden)
        local best_score=0
        
        for ((i=0; i<releases_count; i++)); do
            local score=0
            
            # Prüfe Track-Anzahl-Übereinstimmung (wichtigster Faktor)
            local release_tracks
            release_tracks=$(echo "$mb_response" | jq -r ".releases[$i].media[0].tracks | length" 2>/dev/null)
            
            if [[ "$release_tracks" == "$track_count" ]]; then
                score=$((score + 100))  # Exakte Track-Anzahl = +100 Punkte
            fi
            
            # Bevorzuge neuere Releases (besseres Remastering, mehr Tracks)
            local release_year
            release_year=$(echo "$mb_response" | jq -r ".releases[$i].date" 2>/dev/null | cut -d'-' -f1)
            
            if [[ -n "$release_year" ]] && [[ "$release_year" != "null" ]]; then
                # Neuere Releases bekommen mehr Punkte (max +20 für 2020+)
                if [[ "$release_year" -ge 2000 ]]; then
                    score=$((score + (release_year - 2000)))
                fi
            fi
            
            # Bestes Release merken
            if [[ $score -gt $best_score ]]; then
                best_score=$score
                best_release_index=$i
            fi
        done
        
        if [[ "${DEBUG:-0}" == "1" ]]; then
            log_debug "$releases_count Releases gefunden, gewählt: Index $best_release_index (Score: $best_score)"
        fi
        
        # Bei mehreren Releases IMMER User-Input anfordern (auch wenn Score hoch)
        log_info "$releases_count Releases gefunden - Benutzer-Bestätigung wird angefordert"
        
        # Setze vorläufige Auswahl
        if declare -f api_write_json >/dev/null 2>&1; then
            api_write_json "musicbrainz_selection.json" "{\"status\":\"waiting_user_input\",\"selected_index\":$best_release_index,\"confidence\":\"medium\",\"message\":\"Mehrere Alben gefunden. Bitte wählen Sie das richtige Album aus.\"}"
        fi
        
        # MQTT-Benachrichtigung: Benutzereingriff erforderlich
        if declare -f mqtt_publish_state >/dev/null 2>&1; then
            mqtt_publish_state "waiting" "MusicBrainz: $releases_count Alben gefunden" "CD"
        fi
        
        # Markiere, dass User-Input benötigt wird
        export MUSICBRAINZ_NEEDS_CONFIRMATION=true
    fi
    
    # Extrahiere gewähltes Release
    cd_album=$(echo "$mb_response" | jq -r ".releases[$best_release_index].title" 2>/dev/null)
    cd_artist=$(echo "$mb_response" | jq -r ".releases[$best_release_index][\"artist-credit\"][0].name" 2>/dev/null)
    cd_year=$(echo "$mb_response" | jq -r ".releases[$best_release_index].date" 2>/dev/null | cut -d'-' -f1)
    
    # Bereinige null-Werte
    [[ "$cd_album" == "null" ]] && cd_album=""
    [[ "$cd_artist" == "null" ]] && cd_artist=""
    [[ "$cd_year" == "null" ]] && cd_year=""
    
    if [[ -n "$cd_artist" ]] && [[ -n "$cd_album" ]]; then
        log_info "$MSG_ALBUM: $cd_album"
        log_info "$MSG_ARTIST: $cd_artist"
        [[ -n "$cd_year" ]] && log_info "$MSG_YEAR: $cd_year"
        
        # Zähle Track-Anzahl (vom gewählten Release)
        local mb_track_count
        mb_track_count=$(echo "$mb_response" | jq -r ".releases[$best_release_index].media[0].tracks | length" 2>/dev/null)
        if [[ -n "$mb_track_count" ]] && [[ "$mb_track_count" != "null" ]] && [[ "$mb_track_count" != "0" ]]; then
            log_info "$MSG_MUSICBRAINZ_TRACKS_FOUND $mb_track_count"
        fi
        
        # Prüfe Cover-Art Verfügbarkeit (vom gewählten Release)
        local has_cover
        has_cover=$(echo "$mb_response" | jq -r ".releases[$best_release_index][\"cover-art-archive\"].front" 2>/dev/null)
        if [[ "$has_cover" == "true" ]]; then
            log_info "$MSG_COVER_AVAILABLE"
        fi
        
        return 0
    else
        log_warning "$MSG_WARNING_INCOMPLETE_METADATA"
        mb_response=""  # Leere Antwort bei Fehler
        return 1
    fi
}

# Funktion: Lade Album-Cover von Cover Art Archive
# Rückgabe: Pfad zur Cover-Datei oder leer
download_cover_art() {
    local target_dir="${1:-/tmp}"
    
    if [[ -z "$mb_response" ]]; then
        return 1
    fi
    
    # Prüfe ob Cover verfügbar ist
    # Nutze besten Release-Index (falls aus get_musicbrainz_metadata gesetzt)
    local release_idx="${best_release_index:-0}"
    
    local has_cover
    has_cover=$(echo "$mb_response" | jq -r ".releases[$release_idx][\"cover-art-archive\"].front" 2>/dev/null)
    
    if [[ "$has_cover" != "true" ]]; then
        return 1
    fi
    
    # Extrahiere Release-ID
    local release_id
    release_id=$(echo "$mb_response" | jq -r ".releases[$release_idx].id" 2>/dev/null)
    
    if [[ -z "$release_id" ]] || [[ "$release_id" == "null" ]]; then
        log_warning "$MSG_WARNING_NO_RELEASE_ID"
        return 1
    fi
    
    # Download Cover (mit -L für Redirects) in Zielverzeichnis
    local cover_file="${target_dir}/disk2iso_cover_$$.jpg"
    local cover_url="https://coverartarchive.org/release/${release_id}/front"
    
    log_info "$MSG_DOWNLOAD_COVER" >&2
    
    if curl -L -s -f "$cover_url" -o "$cover_file" 2>/dev/null; then
        # Prüfe ob Datei gültig ist
        if [[ -f "$cover_file" ]] && [[ -s "$cover_file" ]]; then
            local cover_size=$(du -h "$cover_file" | awk '{print $1}')
            log_info "$MSG_COVER_DOWNLOADED: ${cover_size}" >&2
            echo "$cover_file"
            return 0
        fi
    fi
    
    log_error "$MSG_WARNING_COVER_DOWNLOAD_FAILED" >&2
    rm -f "$cover_file" 2>/dev/null
    return 1
}

# Funktion: Hole Track-Titel aus MusicBrainz-Antwort
# Parameter: $1 = Track-Nummer (1-basiert)
# Rückgabe: Track-Titel oder leer
get_track_title() {
    local track_num="$1"
    
    if [[ -z "$mb_response" ]]; then
        echo ""
        return 1
    fi
    
    # Nutze gewählten Release-Index (nicht fest 0!)
    local release_idx="${best_release_index:-0}"
    
    # Extrahiere Track-Titel (track_num ist 1-basiert, Array ist 0-basiert)
    local track_index=$((track_num - 1))
    local track_title
    track_title=$(echo "$mb_response" | jq -r ".releases[$release_idx].media[0].tracks[${track_index}].recording.title" 2>/dev/null)
    
    if [[ -n "$track_title" ]] && [[ "$track_title" != "null" ]]; then
        echo "$track_title"
        return 0
    fi
    
    echo ""
    return 1
}

# Funktion: Erstelle album.nfo für Jellyfin
# Parameter: $1 = Pfad zum Album-Verzeichnis
# Benötigt: mb_response, cd_artist, cd_album, cd_year
create_album_nfo() {
    local album_dir="$1"
    local nfo_file="${album_dir}/album.nfo"
    
    if [[ -z "$mb_response" ]]; then
        log_warning "$MSG_INFO_NO_MUSICBRAINZ_NFO_SKIPPED"
        return 1
    fi
    
    log_info "$MSG_CREATE_ALBUM_NFO"
    
    # Nutze besten Release-Index (falls aus get_musicbrainz_metadata gesetzt)
    local release_idx="${best_release_index:-0}"
    
    # Extrahiere MusicBrainz IDs
    local release_id=$(echo "$mb_response" | jq -r ".releases[$release_idx].id" 2>/dev/null)
    local release_group_id=$(echo "$mb_response" | jq -r ".releases[$release_idx][\"release-group\"].id" 2>/dev/null)
    local artist_id=$(echo "$mb_response" | jq -r ".releases[$release_idx][\"artist-credit\"][0].artist.id" 2>/dev/null)
    
    # Berechne Gesamtlaufzeit in Minuten
    local total_duration_ms=0
    local track_count=$(echo "$mb_response" | jq -r ".releases[$release_idx].media[0].tracks | length" 2>/dev/null)
    
    for ((i=0; i<track_count; i++)); do
        local track_length=$(echo "$mb_response" | jq -r ".releases[$release_idx].media[0].tracks[$i].length" 2>/dev/null)
        if [[ -n "$track_length" ]] && [[ "$track_length" != "null" ]]; then
            total_duration_ms=$((total_duration_ms + track_length))
        fi
    done
    
    local runtime_minutes=$((total_duration_ms / 60000))
    
    # Erstelle album.nfo XML
    cat > "$nfo_file" <<EOF
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<album>
  <title>${cd_album}</title>
  <year>${cd_year}</year>
  <runtime>${runtime_minutes}</runtime>
  <musicbrainzalbumid>${release_id}</musicbrainzalbumid>
  <musicbrainzalbumartistid>${artist_id}</musicbrainzalbumartistid>
  <musicbrainzreleasegroupid>${release_group_id}</musicbrainzreleasegroupid>
  <actor>
    <name>${cd_artist}</name>
    <type>AlbumArtist</type>
  </actor>
  <actor>
    <name>${cd_artist}</name>
    <type>Artist</type>
  </actor>
  <artist>${cd_artist}</artist>
  <albumartist>${cd_artist}</albumartist>
EOF
    
    # Füge Track-Liste hinzu
    for ((i=0; i<track_count; i++)); do
        local position=$((i + 1))
        local track_title=$(echo "$mb_response" | jq -r ".releases[$release_idx].media[0].tracks[$i].recording.title" 2>/dev/null)
        local track_length=$(echo "$mb_response" | jq -r ".releases[$release_idx].media[0].tracks[$i].length" 2>/dev/null)
        
        # Konvertiere Millisekunden zu MM:SS
        if [[ -n "$track_length" ]] && [[ "$track_length" != "null" ]]; then
            local duration_sec=$((track_length / 1000))
            local minutes=$((duration_sec / 60))
            local seconds=$((duration_sec % 60))
            local duration=$(printf "%02d:%02d" $minutes $seconds)
        else
            local duration="00:00"
        fi
        
        cat >> "$nfo_file" <<EOF
  <track>
    <position>${position}</position>
    <title>${track_title}</title>
    <duration>${duration}</duration>
  </track>
EOF
    done
    
    # Schließe XML
    echo "</album>" >> "$nfo_file"
    
    log_info "$MSG_NFO_FILE_CREATED"
    return 0
}

# Funktion: Erstelle Archiv-Metadaten für Web-Interface
# Parameter: $1 = ISO-Pfad
# Erstellt: <iso>.nfo und <iso>-thumb.jpg für Archiv-Anzeige
# Speichere MusicBrainz Query-Daten für ISO (bei mehreren Treffern)
# Args: iso_path, disc_id, toc, track_count
save_mbquery_for_iso() {
    local iso_path="$1"
    local disc_id="$2"
    local toc_str="$3"
    local tracks="$4"
    local iso_base="${iso_path%.iso}"
    local mbquery_file="${iso_base}.mbquery"
    
    if [[ -z "$disc_id" ]] || [[ -z "$toc_str" ]]; then
        return 1
    fi
    
    # Speichere Query-Daten im einfachen Format
    cat > "$mbquery_file" <<EOF
DISC_ID=${disc_id}
TOC=${toc_str}
TRACK_COUNT=${tracks}
EOF
    
    log_info "MusicBrainz Query-Daten gespeichert: $(basename "$mbquery_file")"
}

# ============================================================================
# METADATA BEFORE COPY - WAIT FOR SELECTION
# ============================================================================

# Funktion: Warte auf User-Metadata-Auswahl (BEFORE Copy)
# Parameter: $1 = disc_id, $2 = mb_response (JSON)
# Rückgabe: 0 = Auswahl getroffen, 1 = Timeout/Skip
# Setzt: cd_artist, cd_album, cd_year aus User-Auswahl
wait_for_metadata_selection() {
    local disc_id="$1"
    local mb_json="$2"
    
    # Schreibe .mbquery Datei (für Frontend-API)
    local output_base
    output_base=$(get_type_subfolder "audio-cd")
    local mbquery_file="${output_base}/${disc_id}_mb.mbquery"
    
    log_info "Erstelle Metadata-Query für User-Auswahl: $(basename "$mbquery_file")"
    echo "$mb_json" > "$mbquery_file"
    chmod 644 "$mbquery_file" 2>/dev/null
    
    # Warte auf .mbselect Datei oder Timeout
    local mbselect_file="${output_base}/${disc_id}_mb.mbselect"
    local timeout="${METADATA_SELECTION_TIMEOUT:-60}"
    local elapsed=0
    local check_interval=1
    
    log_info "Warte auf Metadata-Auswahl (Timeout: ${timeout}s)..."
    
    # State: waiting_for_metadata
    if declare -f transition_to_state >/dev/null 2>&1; then
        transition_to_state "$STATE_WAITING_FOR_METADATA" "Warte auf Metadata-Auswahl"
    fi
    
    while [[ $elapsed -lt $timeout ]]; do
        # Prüfe ob Selection-Datei existiert
        if [[ -f "$mbselect_file" ]]; then
            log_info "Metadata-Auswahl erhalten nach ${elapsed}s"
            
            # Lese Auswahl
            local selected_index
            selected_index=$(jq -r '.selected_index' "$mbselect_file" 2>/dev/null || echo "-1")
            
            # Cleanup
            rm -f "$mbquery_file" "$mbselect_file" 2>/dev/null
            
            # Skip?
            if [[ "$selected_index" == "-1" ]] || [[ "$selected_index" == "skip" ]]; then
                log_info "Metadata-Auswahl übersprungen - verwende generische Namen"
                return 1
            fi
            
            # Extrahiere Metadata aus gewähltem Release
            cd_artist=$(echo "$mb_json" | jq -r ".releases[$selected_index][\"artist-credit\"][0].name" 2>/dev/null)
            cd_album=$(echo "$mb_json" | jq -r ".releases[$selected_index].title" 2>/dev/null)
            cd_year=$(echo "$mb_json" | jq -r ".releases[$selected_index].date" 2>/dev/null | cut -d- -f1)
            
            if [[ -n "$cd_artist" ]] && [[ -n "$cd_album" ]]; then
                log_info "Metadata ausgewählt: $cd_artist - $cd_album ($cd_year)"
                return 0
            else
                log_warning "Metadata-Extraktion fehlgeschlagen - verwende generische Namen"
                return 1
            fi
        fi
        
        sleep "$check_interval"
        ((elapsed += check_interval))
        
        # Progress-Log alle 10 Sekunden
        if (( elapsed % 10 == 0 )); then
            log_info "Warte auf Auswahl... (${elapsed}/${timeout}s)"
        fi
    done
    
    # Timeout erreicht
    log_warning "Metadata-Auswahl Timeout nach ${timeout}s - verwende generische Namen"
    rm -f "$mbquery_file" "$mbselect_file" 2>/dev/null
    return 1
}

create_archive_metadata() {
    local iso_path="$1"
    local iso_base="${iso_path%.iso}"
    local archive_nfo="${iso_base}.nfo"
    local archive_thumb="${iso_base}-thumb.jpg"
    
    if [[ -z "$mb_response" ]] || [[ -z "$cd_artist" ]] || [[ -z "$cd_album" ]]; then
        return 1
    fi
    
    # Nutze besten Release-Index
    local release_idx="${best_release_index:-0}"
    
    # Extrahiere Track-Anzahl und Laufzeit
    local track_count=$(echo "$mb_response" | jq -r ".releases[$release_idx].media[0].tracks | length" 2>/dev/null)
    local total_duration_ms=0
    
    for ((i=0; i<track_count; i++)); do
        local track_length=$(echo "$mb_response" | jq -r ".releases[$release_idx].media[0].tracks[$i].length" 2>/dev/null)
        if [[ -n "$track_length" ]] && [[ "$track_length" != "null" ]]; then
            total_duration_ms=$((total_duration_ms + track_length))
        fi
    done
    
    local duration_sec=$((total_duration_ms / 1000))
    local hours=$((duration_sec / 3600))
    local minutes=$(((duration_sec % 3600) / 60))
    local seconds=$((duration_sec % 60))
    
    if [[ $hours -gt 0 ]]; then
        local duration=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
    else
        local duration=$(printf "%02d:%02d" $minutes $seconds)
    fi
    
    # Hole Release-Datum (kann Jahr oder YYYY-MM-DD sein)
    local release_date=$(echo "$mb_response" | jq -r ".releases[$release_idx].date" 2>/dev/null)
    local release_country=$(echo "$mb_response" | jq -r ".releases[$release_idx].country" 2>/dev/null)
    
    # Erstelle Archiv-NFO (einfaches Format für schnelles Parsing)
    cat > "$archive_nfo" <<EOF
TITLE=${cd_album}
ARTIST=${cd_artist}
DATE=${release_date:-$cd_year}
COUNTRY=${release_country:-unknown}
TRACKS=${track_count}
DURATION=${duration}
TYPE=audio-cd
EOF
    
    # Kopiere Cover als Thumbnail (falls vorhanden)
    if [[ -n "$cover_file" ]] && [[ -f "$cover_file" ]]; then
        cp "$cover_file" "$archive_thumb" 2>/dev/null
    fi
    
    log_info "Archiv-Metadaten erstellt: $(basename "$archive_nfo")"
}

# ============================================================================
# AUDIO CD RIPPING
# ============================================================================

# Funktion: Audio-CD rippen und als ISO erstellen
# Workflow: MusicBrainz BEFORE → Wait for Selection → cdparanoia → lame → genisoimage → ISO
copy_audio_cd() {
    log_info "$MSG_START_AUDIO_RIPPING"
    
    # Prüfe benötigte Tools
    if ! command -v cdparanoia >/dev/null 2>&1; then
        log_error "$MSG_ERROR_CDPARANOIA_MISSING"
        return 1
    fi
    
    if ! command -v lame >/dev/null 2>&1; then
        log_error "$MSG_ERROR_LAME_MISSING"
        return 1
    fi
    
    if ! command -v genisoimage >/dev/null 2>&1; then
        log_error "$MSG_ERROR_GENISOIMAGE_MISSING"
        return 1
    fi
    
    # ========================================================================
    # METADATA DATABASE INITIALISIERUNG
    # ========================================================================
    # Initialisiere Metadaten-Datenbank für Audio-CD
    if declare -f metadb_init >/dev/null 2>&1; then
        metadb_init "audio-cd"
        log_debug "Metadaten-Datenbank für audio-cd initialisiert"
    else
        log_warning "libmetadb.sh nicht geladen - verwende Legacy-Variablen"
    fi
    
    # ========================================================================
    # METADATA BEFORE COPY - Neue Strategie
    # ========================================================================
    # Metadaten VOR dem Rippen abfragen und auf User-Auswahl warten
    
    cd_artist=""
    cd_album=""
    cd_year=""
    cd_discid=""
    mb_response=""
    local skip_metadata=false
    local releases_count=0
    
    # Hole MusicBrainz Metadaten
    if ! get_musicbrainz_metadata; then
        log_info "$MSG_CONTINUE_WITHOUT_METADATA"
        skip_metadata=true
    else
        # Zähle Releases
        releases_count=$(echo "$mb_response" | jq '.releases | length' 2>/dev/null || echo "0")
        
        if [[ $releases_count -eq 0 ]]; then
            # Keine Releases gefunden
            log_info "Keine MusicBrainz Releases gefunden - verwende generische Namen"
            skip_metadata=true
        elif [[ $releases_count -eq 1 ]]; then
            # Genau 1 Release - direkt verwenden (kein User-Input nötig)
            log_info "1 Release gefunden - verwende Metadaten direkt"
            cd_artist=$(echo "$mb_response" | jq -r '.releases[0]["artist-credit"][0].name' 2>/dev/null)
            cd_album=$(echo "$mb_response" | jq -r '.releases[0].title' 2>/dev/null)
            cd_year=$(echo "$mb_response" | jq -r '.releases[0].date' 2>/dev/null | cut -d- -f1)
            skip_metadata=false
        else
            # Mehrere Releases - warte auf User-Auswahl
            log_info "$releases_count Releases gefunden - warte auf User-Auswahl..."
            
            # Temporäres disc_label für .mbquery Datei
            local temp_disc_id="${cd_discid:-audio_cd_$(date +%s)}"
            
            # Warte auf Auswahl (mit Timeout)
            if wait_for_metadata_selection "$temp_disc_id" "$mb_response"; then
                # User hat gewählt - cd_artist, cd_album, cd_year sind gesetzt
                skip_metadata=false
            else
                # Timeout/Skip - verwende generische Namen
                log_info "Verwende generische Namen - Metadaten können später hinzugefügt werden"
                skip_metadata=true
                
                # Speichere Query-Daten für späteres Remastering
                SAVED_DISCID="$cd_discid"
                SAVED_TOC="$toc"
                SAVED_TRACK_COUNT="$track_count"
            fi
        fi
    fi
    
    # ========================================================================
    # TEMP DIRECTORY & FILENAMES
    # ========================================================================
    
    # Nutze globales temp_pathname (wird von init_filenames erstellt)
    # Falls nicht vorhanden (standalone-Aufruf), erstelle eigenes Verzeichnis
    if [[ -z "$temp_pathname" ]]; then
        local temp_base
        temp_base=$(ensure_subfolder "temp") || return 1
        temp_pathname="${temp_base}/disk2iso_audio_$$"
        mkdir -p "$temp_pathname" || return 1
    fi
    
    # Album-Cover laden (falls Metadaten verfügbar)
    local cover_file=""
    if [[ "$skip_metadata" == "false" ]] && [[ -n "$mb_response" ]]; then
        if command -v eyeD3 >/dev/null 2>&1; then
            cover_file=$(download_cover_art "$temp_pathname")
        else
            log_info "$MSG_INFO_EYED3_MISSING"
        fi
    fi
    
    # Erstelle Verzeichnisstruktur basierend auf verfügbaren Metadaten
    local album_dir
    if [[ "$skip_metadata" == "false" ]] && [[ -n "$cd_album" ]] && [[ -n "$cd_artist" ]]; then
        # Metadaten verfügbar - Jellyfin-Struktur: AlbumArtist/Album/
        local safe_artist=$(echo "$cd_artist" | sed 's/[\/\\:*?"<>|]/_/g')
        local safe_album=$(echo "$cd_album" | sed 's/[\/\\:*?"<>|]/_/g')
        
        album_dir="${temp_pathname}/${safe_artist}/${safe_album}"
        
        # ISO-Label (lowercase, human-readable!)
        local label_artist=$(echo "$cd_artist" | sed 's/[^a-zA-Z0-9_-]/_/g' | tr '[:upper:]' '[:lower:]')
        local label_album=$(echo "$cd_album" | sed 's/[^a-zA-Z0-9_-]/_/g' | tr '[:upper:]' '[:lower:]')
        disc_label="${label_artist}_${label_album}"
    else
        # Keine Metadaten - einfache DiskID-Struktur
        if [[ -n "$cd_discid" ]]; then
            album_dir="${temp_pathname}/audio_cd_${cd_discid}"
            disc_label="audio_cd_${cd_discid}"
        else
            local timestamp=$(date +%Y%m%d_%H%M%S)
            album_dir="${temp_pathname}/audio_cd_${timestamp}"
            disc_label="audio_cd_${timestamp}"
        fi
    fi
    
    mkdir -p "$album_dir"
    
    # Ermittle Anzahl der Tracks ZUERST (für korrekte Fortschrittsanzeige)
    local track_info
    track_info=$(cdparanoia -Q 2>&1 | grep -E "^\s+[0-9]+\.")
    local track_count=$(echo "$track_info" | wc -l)
    
    if [[ $track_count -eq 0 ]]; then
        log_error "$MSG_ERROR_NO_TRACKS"
        rm -rf "$temp_pathname"
        return 1
    fi
    
    # Initialisiere Kopiervorgang-Log (NEUES SYSTEM)
    init_copy_log "$disc_label" "audio-cd"
    
    # Setze ISO- und MD5-Dateinamen (früher von init_filenames())
    local target_dir="$(get_path_audio)"
    iso_filename="${target_dir}/${disc_label}.iso"
    md5_filename="${target_dir}/${disc_label}.md5"
    
    log_copying "$MSG_TRACKS_FOUND: $track_count"
    log_copying "$MSG_ALBUM_DIRECTORY: $album_dir"
    
    # Log Metadata (BEFORE strategy - jetzt schon bekannt!)
    if [[ "$skip_metadata" == "false" ]] && [[ -n "$cd_artist" ]] && [[ -n "$cd_album" ]]; then
        log_copying "Album: $cd_artist - $cd_album"
        [[ -n "$cd_year" ]] && log_copying "Jahr: $cd_year"
        log_info "Rippe Album: $cd_artist - $cd_album ($track_count Tracks)"
    else
        log_copying "Disc-ID: ${cd_discid:-unbekannt}"
        log_info "Rippe Audio-CD: $disc_label ($track_count Tracks)"
    fi
    
    # API: Aktualisiere Status
    if declare -f api_update_status >/dev/null 2>&1; then
        api_update_status "copying" "$disc_label" "audio-cd"
    fi
    
    # MQTT: Sende Update mit DiskID
    if [[ "$SUPPORT_MQTT" == "true" ]] && declare -f mqtt_publish_state >/dev/null 2>&1; then
        mqtt_publish_state "copying" "$disc_label" "audio-cd"
    fi
    
    # Initialisiere Fortschritt mit korrekter Track-Anzahl (0/24 statt 0/0)
    if declare -f api_update_progress >/dev/null 2>&1; then
        api_update_progress "0" "0" "$track_count" ""
    fi
    
    # Update attributes.json mit total_tracks für korrekte Anzeige
    local api_dir="${INSTALL_DIR:-/opt/disk2iso}/api"
    if [[ -f "${api_dir}/attributes.json" ]] && command -v jq >/dev/null 2>&1; then
        local updated=$(jq --arg tracks "$track_count" '.total_tracks = ($tracks | tonumber)' "${api_dir}/attributes.json" 2>/dev/null)
        if [[ -n "$updated" ]]; then
            echo "$updated" > "${api_dir}/attributes.json"
        fi
    fi
    
    # Initialisiere Fortschritts-Tracking
    local total_tracks="$track_count"
    local processed_tracks=0
    
    # Rippe alle Tracks mit cdparanoia
    log_copying "$MSG_START_CDPARANOIA_RIPPING"
    local track
    for track in $(seq 1 "$track_count"); do
        local track_num=$(printf "%02d" "$track")
        local wav_file="${temp_pathname}/track_${track_num}.wav"
        
        # Progress-Message mit Tracktitel (falls verfügbar)
        if [[ "$skip_metadata" == "false" ]] && [[ -n "$mb_response" ]]; then
            local track_title
            track_title=$(get_track_title "$track")
            if [[ -n "$track_title" ]]; then
                log_copying "Rippe Track $track/$track_count: $track_title"
                log_info "Rippe Track $track/$track_count: $track_title"
            else
                log_copying "$MSG_RIPPING_TRACK $track / $track_count"
            fi
        else
            log_copying "$MSG_RIPPING_TRACK $track / $track_count"
        fi
        
        if ! cdparanoia -d "$CD_DEVICE" "$track" "$wav_file" >>"$copy_log_filename" 2>&1; then
            log_error "$MSG_ERROR_TRACK_RIP_FAILED $track"
            rm -rf "$temp_pathname"
            finish_copy_log
            return 1
        fi
        
        # Konvertiere WAV zu MP3 mit lame
        # Dateiname abhängig von verfügbaren Metadaten
        local mp3_filename
        local mp3_file
        
        if [[ "$skip_metadata" == "false" ]] && [[ -n "$mb_response" ]]; then
            # Metadaten verfügbar - nutze Track-Titel
            local track_title
            track_title=$(get_track_title "$track")
            
            if [[ -n "$track_title" ]] && [[ -n "$cd_artist" ]]; then
                # Jellyfin-Format: "Artist - Title.mp3"
                local safe_artist=$(echo "$cd_artist" | sed 's/[\/\\:*?"<>|]/_/g')
                local safe_title=$(echo "$track_title" | sed 's/[\/\\:*?"<>|]/_/g')
                mp3_filename="${safe_artist} - ${safe_title}.mp3"
                log_copying "$MSG_ENCODING_TRACK_WITH_TITLE $track: $track_title"
            else
                mp3_filename="Track ${track_num}.mp3"
                log_copying "$MSG_ENCODING_TRACK $track"
            fi
        else
            # Keine Metadaten - einfacher Dateiname
            mp3_filename="Track ${track_num}.mp3"
            log_copying "$MSG_ENCODING_TRACK $track"
        fi
        
        mp3_file="${album_dir}/${mp3_filename}"
        
        # lame Optionen: VBR Qualität aus Konfiguration (Array für sauberes Quoting)
        local lame_opts=("-V${MP3_QUALITY}" "--quiet")
        
        # Füge ID3-Tags hinzu (falls Metadaten verfügbar)
        if [[ "$skip_metadata" == "false" ]]; then
            if [[ -n "$cd_artist" ]]; then
                lame_opts+=("--ta" "$cd_artist")
            fi
            if [[ -n "$cd_album" ]]; then
                lame_opts+=("--tl" "$cd_album")
            fi
            if [[ -n "$cd_year" ]]; then
                lame_opts+=("--ty" "$cd_year")
            fi
            if [[ -n "$track_title" ]]; then
                lame_opts+=("--tt" "$track_title")
            fi
        fi
        lame_opts+=("--tn" "$track/$track_count")
        
        if ! lame "${lame_opts[@]}" "$wav_file" "$mp3_file" >>"$copy_log_filename" 2>&1; then
            log_error "$MSG_ERROR_MP3_ENCODING_FAILED $track"
            rm -rf "$temp_pathname"
            [[ -n "$cover_file" ]] && rm -f "$cover_file"
            finish_copy_log
            return 1
        fi
        
        # Bette Cover-Art ein (falls vorhanden)
        if [[ "$skip_metadata" == "false" ]] && [[ -n "$cover_file" ]] && [[ -f "$cover_file" ]]; then
            if command -v eyeD3 >/dev/null 2>&1; then
                eyeD3 --quiet --add-image "${cover_file}:FRONT_COVER" "$mp3_file" >>"$copy_log_filename" 2>&1
            fi
        fi
        
        # Lösche WAV-Datei um Speicherplatz zu sparen
        rm -f "$wav_file"
        
        # Fortschritt aktualisieren (Track fertig)
        processed_tracks=$((processed_tracks + 1))
        local percent=$((processed_tracks * 100 / total_tracks))
        
        # API: Fortschritt senden
        if declare -f api_update_progress >/dev/null 2>&1; then
            # Schätze verbleibende Zeit (ca. 4 Minuten pro Track als Durchschnitt)
            local remaining_tracks=$((total_tracks - processed_tracks))
            local eta_minutes=$((remaining_tracks * 4))
            local eta=$(printf "%02d:%02d:00" $((eta_minutes / 60)) $((eta_minutes % 60)))
            
            api_update_progress "$percent" "$processed_tracks" "$total_tracks" "$eta"
        fi
        
        # MQTT: Fortschritt senden
        if [[ "$SUPPORT_MQTT" == "true" ]] && declare -f mqtt_publish_progress >/dev/null 2>&1; then
            local remaining_tracks=$((total_tracks - processed_tracks))
            local eta_minutes=$((remaining_tracks * 4))
            local eta=$(printf "%02d:%02d:00" $((eta_minutes / 60)) $((eta_minutes % 60)))
            
            # Für Audio-CDs: Sende Tracks statt MB
            mqtt_publish_progress "$percent" "$processed_tracks" "$total_tracks" "$eta"
        fi
    done
    
    # Kopiere Cover als folder.jpg (falls vorhanden)
    if [[ "$skip_metadata" == "false" ]] && [[ -n "$cover_file" ]] && [[ -f "$cover_file" ]]; then
        cp "$cover_file" "${album_dir}/folder.jpg" 2>/dev/null && \
            log_info "$MSG_COVER_SAVED_FOLDER_JPG"
    fi
    
    log_copying "$MSG_RIPPING_COMPLETE_CREATE_ISO"
    
    # Erstelle album.nfo für Jellyfin (falls Metadaten verfügbar)
    # HINWEIS: Nutzt metadb_export_nfo() aus libmetadb.sh
    if [[ "$skip_metadata" == "false" ]]; then
        local nfo_file="${album_dir}/album.nfo"
        
        # Validiere ob Metadaten gesetzt sind
        if metadb_validate 2>/dev/null; then
            metadb_export_nfo "$nfo_file"
            log_info "$MSG_NFO_FILE_CREATED"
        else
            log_warning "$MSG_INFO_NO_MUSICBRAINZ_NFO_SKIPPED"
        fi
    fi
    
    # Sichere temp_pathname bevor check_disk_space es braucht
    local audio_temp_path="$temp_pathname"
    
    # Prüfe Speicherplatz (MP3s sind ~10x kleiner als WAV, aber ISO braucht Overhead)
    local album_size_mb=$(du -sm "$album_dir" | awk '{print $1}')
    local required_mb=$((album_size_mb + album_size_mb / 10 + 50))  # +10% + 50MB Puffer
    
    if ! check_disk_space "$required_mb"; then
        log_error "$MSG_ERROR_INSUFFICIENT_SPACE_ISO"
        rm -rf "$audio_temp_path"
        finish_copy_log
        return 1
    fi
    
    # Erstelle ISO mit genisoimage
    local volume_id
    if [[ "$skip_metadata" == "false" ]] && [[ -n "$cd_album" ]]; then
        # Metadaten verfügbar - Album-Name als Volume-ID
        volume_id=$(echo "$cd_album" | sed 's/[^A-Za-z0-9_]/_/g' | cut -c1-32 | tr '[:lower:]' '[:upper:]')
    elif [[ -n "$cd_discid" ]]; then
        # Nur Disc-ID verfügbar
        volume_id="AUDIO_CD_${cd_discid}"
    else
        volume_id="AUDIO_CD"
    fi
    
    log_copying "$MSG_CREATE_ISO: $iso_filename"
    log_copying "$MSG_VOLUME_ID: $volume_id"
    
    # Erstelle ISO aus audio_temp_path
    # ISO-Struktur abhängig von Metadaten:
    # - Mit Metadaten: AlbumArtist/Album/Artist - Title.mp3
    # - Ohne Metadaten: audio_cd_<discid>/Track 01.mp3
    if ! genisoimage -R -J -joliet-long \
        -V "$volume_id" \
        -o "$iso_filename" \
        "$audio_temp_path" >>"$copy_log_filename" 2>&1; then
        log_error "$MSG_ERROR_ISO_CREATION_FAILED"
        rm -rf "$audio_temp_path"
        [[ -n "$cover_file" ]] && rm -f "$cover_file"
        finish_copy_log
        return 1
    fi
    
    # Cleanup temp-Verzeichnis und Cover
    rm -rf "$audio_temp_path"
    [[ -n "$cover_file" ]] && rm -f "$cover_file"
    
    # Prüfe ISO-Größe
    if [[ ! -f "$iso_filename" ]]; then
        log_error "$MSG_ERROR_ISO_NOT_CREATED"
        finish_copy_log
        return 1
    fi
    
    local iso_size_mb=$(du -m "$iso_filename" | awk '{print $1}')
    log_copying "$MSG_ISO_CREATED: ${iso_size_mb} $MSG_PROGRESS_MB"
    
    # Erstelle MD5-Checksumme
    log_copying "$MSG_CREATE_MD5"
    if ! md5sum "$iso_filename" > "$md5_filename" 2>>"$copy_log_filename"; then
        log_warning "$MSG_WARNING_MD5_FAILED"
    fi
    
    # Erstelle Archiv-Metadaten (falls Metadaten verfügbar)
    if [[ "$skip_metadata" == "false" ]] && [[ -n "$mb_response" ]]; then
        create_archive_metadata "$iso_filename"
    elif [[ "$skip_metadata" == "true" ]] && [[ -n "$SAVED_DISCID" ]]; then
        # Mehrere Releases - speichere Query-Daten für Browser
        save_mbquery_for_iso "$iso_filename" "$SAVED_DISCID" "$SAVED_TOC" "$SAVED_TRACK_COUNT"
    fi
    
    log_copying "$MSG_AUDIO_CD_SUCCESS"
    finish_copy_log
    return 0
}
