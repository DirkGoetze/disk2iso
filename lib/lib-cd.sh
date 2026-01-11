#!/bin/bash
################################################################################
# disk2iso v1.3.0 - Audio CD Library
# Filepath: lib/lib-cd.sh
#
# Beschreibung:
#   Funktionen für Audio-CD Ripping mit MusicBrainz-Metadaten
#   - MusicBrainz-Abfrage via cd-discid
#   - CD-Ripping mit cdparanoia
#   - MP3-Encoding mit lame (VBR V2)
#   - ISO-Erstellung mit gerippten MP3s
#
# Version: 1.3.0
# Datum: 06.01.2026
################################################################################

# ============================================================================
# PATH CONSTANTS
# ============================================================================

readonly AUDIO_DIR="audio"

# ============================================================================
# PATH GETTER
# ============================================================================

# Funktion: Ermittle Pfad für Audio-CDs
# Rückgabe: Vollständiger Pfad zu audio/ oder Fallback zu data/
# Nutzt ensure_subfolder aus lib-folders.sh für konsistente Ordner-Verwaltung
get_path_audio() {
    if [[ "$AUDIO_CD_SUPPORT" == true ]] && [[ -n "$AUDIO_DIR" ]]; then
        ensure_subfolder "$AUDIO_DIR"
    else
        # Fallback auf data/ wenn Audio-Modul nicht geladen
        ensure_subfolder "data"
    fi
}

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

# Lade Sprachdatei für dieses Modul
load_module_language "cd"

# Funktion: Prüfe Audio-CD Abhängigkeiten
# Rückgabe: 0 = Alle Tools OK, 1 = Kritische Tools fehlen
check_audio_cd_dependencies() {
    local missing=()
    local optional_missing=()
    
    # Kritische Tools für Audio-CD Ripping
    command -v cdparanoia >/dev/null 2>&1 || missing+=("cdparanoia")
    command -v lame >/dev/null 2>&1 || missing+=("lame")
    command -v genisoimage >/dev/null 2>&1 || missing+=("genisoimage")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_message "$MSG_AUDIO_SUPPORT_NOT_AVAILABLE ${missing[*]}"
        log_message "$MSG_INSTALL_AUDIO_TOOLS"
        return 1
    fi
    
    # Optionale Tools für Metadaten
    command -v cd-discid >/dev/null 2>&1 || optional_missing+=("cd-discid")
    command -v curl >/dev/null 2>&1 || optional_missing+=("curl")
    command -v jq >/dev/null 2>&1 || optional_missing+=("jq")
    command -v eyeD3 >/dev/null 2>&1 || optional_missing+=("eyeD3")
    
    # CD-TEXT Tools (Fallback wenn MusicBrainz nicht verfügbar)
    local cdtext_available=false
    command -v icedax >/dev/null 2>&1 && cdtext_available=true
    command -v cd-info >/dev/null 2>&1 && cdtext_available=true
    command -v cdda2wav >/dev/null 2>&1 && cdtext_available=true
    
    if [[ ${#optional_missing[@]} -gt 0 ]]; then
        log_message "$MSG_AUDIO_OPTIONAL_LIMITED ${optional_missing[*]}"
        log_message "$MSG_INSTALL_MUSICBRAINZ_TOOLS"
        
        if [[ "$cdtext_available" == "true" ]]; then
            log_message "$MSG_CDTEXT_FALLBACK_AVAILABLE"
        else
            log_message "$MSG_CDTEXT_FALLBACK_INSTALL_HINT"
        fi
    fi
    
    log_message "$MSG_AUDIO_SUPPORT_AVAILABLE"
    return 0
}

# ============================================================================
# CD-TEXT METADATA FALLBACK
# ============================================================================

# Funktion: CD-TEXT auslesen (Fallback wenn MusicBrainz nicht verfügbar)
# Benötigt: icedax oder cd-info (aus libcdio)
# Rückgabe: Setzt globale Variablen: cd_artist, cd_album
get_cdtext_metadata() {
    cd_artist=""
    cd_album=""
    
    log_message "$MSG_TRY_CDTEXT"
    
    # Methode 1: icedax (aus cdrtools/cdrkit)
    if command -v icedax >/dev/null 2>&1; then
        local cdtext_output
        cdtext_output=$(icedax -J -H -D "$CD_DEVICE" -g 2>&1 | grep -E "^Albumtitle:|^Performer:")
        
        if [[ -n "$cdtext_output" ]]; then
            cd_album=$(echo "$cdtext_output" | grep "^Albumtitle:" | cut -d':' -f2- | xargs)
            cd_artist=$(echo "$cdtext_output" | grep "^Performer:" | cut -d':' -f2- | xargs)
            
            if [[ -n "$cd_artist" ]] && [[ -n "$cd_album" ]]; then
                log_message "$MSG_CDTEXT_FOUND $cd_artist - $cd_album"
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
                log_message "$MSG_CDTEXT_FOUND $cd_artist - $cd_album"
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
                log_message "$MSG_CDTEXT_FOUND $cd_artist - $cd_album"
                return 0
            fi
        fi
    fi
    
    log_message "$MSG_NO_CDTEXT_FOUND"
    return 1
}

# ============================================================================
# MUSICBRAINZ METADATA ABFRAGE
# ============================================================================

# Funktion: MusicBrainz-Metadaten abrufen
# Benötigt: cd-discid, curl, jq
# Rückgabe: Setzt globale Variablen: cd_artist, cd_album, cd_year, cd_discid, mb_response
get_musicbrainz_metadata() {
    cd_artist=""
    cd_album=""
    cd_year=""
    cd_discid=""
    mb_response=""  # Speichere vollständige Antwort für Track-Infos
    
    log_message "$MSG_RETRIEVE_METADATA"
    
    # Prüfe benötigte Tools
    if ! command -v cd-discid >/dev/null 2>&1; then
        log_message "$MSG_WARNING_CDISCID_MISSING"
        return 1
    fi
    
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        log_message "$MSG_WARNING_CURL_JQ_MISSING"
        return 1
    fi
    
    # Disc-ID und TOC ermitteln
    local discid_output
    discid_output=$(cd-discid "$CD_DEVICE" 2>/dev/null)
    
    if [[ -z "$discid_output" ]]; then
        log_message "$MSG_ERROR_DISCID_FAILED"
        return 1
    fi
    
    # Parse cd-discid output: discid tracks offset1 offset2 ... offsetN total_seconds
    local discid_parts=($discid_output)
    cd_discid="${discid_parts[0]}"
    local track_count="${discid_parts[1]}"
    
    log_message "$MSG_DISCID: $cd_discid ($MSG_TRACKS: $track_count)"
    
    # Ermittle Leadout-Position (letzte Position + 150 für Pregap der ersten Track)
    # cdparanoia gibt TOTAL in Frames, das ist der Leadout
    local leadout
    leadout=$(cdparanoia -Q -d "$CD_DEVICE" 2>&1 | grep "TOTAL" | awk '{print $2}')
    
    if [[ -z "$leadout" ]]; then
        log_message "$MSG_WARNING_LEADOUT_FAILED"
        leadout="${discid_parts[-1]}"  # Fallback auf letzte Spalte
    fi
    
    # Leadout = TOTAL + 150 (Pregap)
    leadout=$((leadout + 150))
    
    # Baue TOC-String für MusicBrainz: 1+track_count+leadout+offset1+offset2+...
    local toc="1+${track_count}+${leadout}"
    for ((i=2; i<${#discid_parts[@]}-1; i++)); do
        toc="${toc}+${discid_parts[$i]}"
    done
    
    # MusicBrainz-Abfrage mit TOC statt nur Disc-ID
    local mb_url="https://musicbrainz.org/ws/2/discid/${cd_discid}?toc=${toc}&fmt=json&inc=artists+recordings"
    
    log_message "$MSG_QUERY_MUSICBRAINZ"
    mb_response=$(curl -s -A "disk2iso/1.0 (https://github.com/user/disk2iso)" "$mb_url" 2>/dev/null)
    
    if [[ -z "$mb_response" ]]; then
        log_message "$MSG_WARNING_MUSICBRAINZ_FAILED"
        return 1
    fi
    
    # Prüfe ob Release gefunden wurde
    local releases_count
    releases_count=$(echo "$mb_response" | jq -r '.releases | length' 2>/dev/null)
    
    if [[ -z "$releases_count" ]] || [[ "$releases_count" == "0" ]] || [[ "$releases_count" == "null" ]]; then
        log_message "$MSG_WARNING_NO_MUSICBRAINZ_ENTRY $cd_discid"
        return 1
    fi
    
    # Extrahiere ersten Release (meist korrekt)
    cd_album=$(echo "$mb_response" | jq -r '.releases[0].title' 2>/dev/null)
    cd_artist=$(echo "$mb_response" | jq -r '.releases[0]["artist-credit"][0].name' 2>/dev/null)
    cd_year=$(echo "$mb_response" | jq -r '.releases[0].date' 2>/dev/null | cut -d'-' -f1)
    
    # Bereinige null-Werte
    [[ "$cd_album" == "null" ]] && cd_album=""
    [[ "$cd_artist" == "null" ]] && cd_artist=""
    [[ "$cd_year" == "null" ]] && cd_year=""
    
    if [[ -n "$cd_artist" ]] && [[ -n "$cd_album" ]]; then
        log_message "$MSG_ALBUM: $cd_album"
        log_message "$MSG_ARTIST: $cd_artist"
        [[ -n "$cd_year" ]] && log_message "$MSG_YEAR: $cd_year"
        
        # Zähle Track-Anzahl
        local mb_track_count
        mb_track_count=$(echo "$mb_response" | jq -r '.releases[0].media[0].tracks | length' 2>/dev/null)
        if [[ -n "$mb_track_count" ]] && [[ "$mb_track_count" != "null" ]] && [[ "$mb_track_count" != "0" ]]; then
            log_message "$MSG_MUSICBRAINZ_TRACKS_FOUND $mb_track_count"
        fi
        
        # Prüfe Cover-Art Verfügbarkeit
        local has_cover
        has_cover=$(echo "$mb_response" | jq -r '.releases[0]["cover-art-archive"].front' 2>/dev/null)
        if [[ "$has_cover" == "true" ]]; then
            log_message "$MSG_COVER_AVAILABLE"
        fi
        
        return 0
    else
        log_message "$MSG_WARNING_INCOMPLETE_METADATA"
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
    local has_cover
    has_cover=$(echo "$mb_response" | jq -r '.releases[0]["cover-art-archive"].front' 2>/dev/null)
    
    if [[ "$has_cover" != "true" ]]; then
        return 1
    fi
    
    # Extrahiere Release-ID
    local release_id
    release_id=$(echo "$mb_response" | jq -r '.releases[0].id' 2>/dev/null)
    
    if [[ -z "$release_id" ]] || [[ "$release_id" == "null" ]]; then
        log_message "$MSG_WARNING_NO_RELEASE_ID"
        return 1
    fi
    
    # Download Cover (mit -L für Redirects) in Zielverzeichnis
    local cover_file="${target_dir}/disk2iso_cover_$$.jpg"
    local cover_url="https://coverartarchive.org/release/${release_id}/front"
    
    log_message "$MSG_DOWNLOAD_COVER" >&2
    
    if curl -L -s -f "$cover_url" -o "$cover_file" 2>/dev/null; then
        # Prüfe ob Datei gültig ist
        if [[ -f "$cover_file" ]] && [[ -s "$cover_file" ]]; then
            local cover_size=$(du -h "$cover_file" | awk '{print $1}')
            log_message "$MSG_COVER_DOWNLOADED: ${cover_size}" >&2
            echo "$cover_file"
            return 0
        fi
    fi
    
    log_message "$MSG_WARNING_COVER_DOWNLOAD_FAILED" >&2
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
    
    # Extrahiere Track-Titel (track_num ist 1-basiert, Array ist 0-basiert)
    local track_index=$((track_num - 1))
    local track_title
    track_title=$(echo "$mb_response" | jq -r ".releases[0].media[0].tracks[${track_index}].recording.title" 2>/dev/null)
    
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
        log_message "$MSG_INFO_NO_MUSICBRAINZ_NFO_SKIPPED"
        return 1
    fi
    
    log_message "$MSG_CREATE_ALBUM_NFO"
    
    # Extrahiere MusicBrainz IDs
    local release_id=$(echo "$mb_response" | jq -r '.releases[0].id' 2>/dev/null)
    local release_group_id=$(echo "$mb_response" | jq -r '.releases[0]["release-group"].id' 2>/dev/null)
    local artist_id=$(echo "$mb_response" | jq -r '.releases[0]["artist-credit"][0].artist.id' 2>/dev/null)
    
    # Berechne Gesamtlaufzeit in Minuten
    local total_duration_ms=0
    local track_count=$(echo "$mb_response" | jq -r '.releases[0].media[0].tracks | length' 2>/dev/null)
    
    for ((i=0; i<track_count; i++)); do
        local track_length=$(echo "$mb_response" | jq -r ".releases[0].media[0].tracks[$i].length" 2>/dev/null)
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
        local track_title=$(echo "$mb_response" | jq -r ".releases[0].media[0].tracks[$i].recording.title" 2>/dev/null)
        local track_length=$(echo "$mb_response" | jq -r ".releases[0].media[0].tracks[$i].length" 2>/dev/null)
        
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
    
    log_message "$MSG_NFO_FILE_CREATED"
    return 0
}

# ============================================================================
# AUDIO CD RIPPING
# ============================================================================

# Funktion: Audio-CD rippen und als ISO erstellen
# Workflow: MusicBrainz → cdparanoia → lame → genisoimage → ISO
copy_audio_cd() {
    log_message "$MSG_START_AUDIO_RIPPING"
    
    # Prüfe benötigte Tools
    if ! command -v cdparanoia >/dev/null 2>&1; then
        log_message "$MSG_ERROR_CDPARANOIA_MISSING"
        return 1
    fi
    
    if ! command -v lame >/dev/null 2>&1; then
        log_message "$MSG_ERROR_LAME_MISSING"
        return 1
    fi
    
    if ! command -v genisoimage >/dev/null 2>&1; then
        log_message "$MSG_ERROR_GENISOIMAGE_MISSING"
        return 1
    fi
    
    # Metadaten abrufen
    # 1. Versuch: MusicBrainz (bevorzugt - liefert Cover-Art, Track-Namen, Jahr)
    # 2. Fallback: CD-TEXT (wenn MusicBrainz fehlschlägt)
    if ! get_musicbrainz_metadata; then
        log_message "$MSG_CONTINUE_WITHOUT_METADATA"
        # Fallback: CD-TEXT versuchen
        if get_cdtext_metadata; then
            log_message "$MSG_USE_CDTEXT_METADATA"
        else
            log_message "$MSG_CONTINUE_NO_METADATA"
        fi
    fi
    
    # Nutze globales temp_pathname (wird von init_filenames erstellt)
    # Falls nicht vorhanden (standalone-Aufruf), erstelle eigenes Verzeichnis
    if [[ -z "$temp_pathname" ]]; then
        local temp_base
        temp_base=$(ensure_subfolder "temp") || return 1
        temp_pathname="${temp_base}/disk2iso_audio_$$"
        mkdir -p "$temp_pathname" || return 1
    fi
    
    # Lade Album-Cover falls verfügbar (nach temp_pathname Sicherstellung)
    local cover_file=""
    if command -v eyeD3 >/dev/null 2>&1; then
        cover_file=$(download_cover_art "$temp_pathname")
    else
        log_message "$MSG_INFO_EYED3_MISSING"
    fi
    
    # Erstelle Jellyfin-kompatible Verzeichnisstruktur: AlbumArtist/Album/
    local album_dir
    if [[ -n "$cd_album" ]] && [[ -n "$cd_artist" ]]; then
        # Behalte Originalnamen (nur gefährliche Zeichen entfernen)
        local safe_artist=$(echo "$cd_artist" | sed 's/[\/\\:*?"<>|]/_/g')
        local safe_album=$(echo "$cd_album" | sed 's/[\/\\:*?"<>|]/_/g')
        
        # Struktur: AlbumArtist/Album/
        album_dir="${temp_pathname}/${safe_artist}/${safe_album}"
        
        # Setze disc_label für ISO-Dateinamen (lowercase für Dateinamen)
        local label_artist=$(echo "$cd_artist" | sed 's/[^a-zA-Z0-9_-]/_/g' | tr '[:upper:]' '[:lower:]')
        local label_album=$(echo "$cd_album" | sed 's/[^a-zA-Z0-9_-]/_/g' | tr '[:upper:]' '[:lower:]')
        disc_label="${label_artist}_${label_album}"
    else
        # Fallback: Verwende Disc-ID oder generischen Namen
        if [[ -n "$cd_discid" ]]; then
            album_dir="${temp_pathname}/Unknown_Artist/audio_cd_${cd_discid}"
            disc_label="audio_cd_${cd_discid}"
        else
            local timestamp=$(date +%Y%m%d_%H%M%S)
            album_dir="${temp_pathname}/Unknown_Artist/audio_cd_${timestamp}"
            disc_label="audio_cd_${timestamp}"
        fi
    fi
    
    mkdir -p "$album_dir"
    log_message "$MSG_ALBUM_DIRECTORY: $album_dir"
    
    # API: Aktualisiere Attribute mit CD-Metadaten
    if declare -f api_update_status >/dev/null 2>&1; then
        # Erstelle readable Label für Anzeige
        local display_label=""
        if [[ -n "$cd_artist" ]] && [[ -n "$cd_album" ]]; then
            display_label="${cd_artist} - ${cd_album}"
        else
            display_label="$disc_label"
        fi
        api_update_status "copying" "$display_label" "audio-cd"
    fi
    
    # Ermittle Anzahl der Tracks
    local track_info
    track_info=$(cdparanoia -Q 2>&1 | grep -E "^\s+[0-9]+\.")
    local track_count=$(echo "$track_info" | wc -l)
    
    if [[ $track_count -eq 0 ]]; then
        log_message "$MSG_ERROR_NO_TRACKS"
        rm -rf "$temp_pathname"
        return 1
    fi
    
    log_message "$MSG_TRACKS_FOUND: $track_count"
    
    # Initialisiere Fortschritts-Tracking
    local total_tracks="$track_count"
    local processed_tracks=0
    
    # Rippe alle Tracks mit cdparanoia
    log_message "$MSG_START_CDPARANOIA_RIPPING"
    local track
    for track in $(seq 1 "$track_count"); do
        local track_num=$(printf "%02d" "$track")
        local wav_file="${temp_pathname}/track_${track_num}.wav"
        
        log_message "$MSG_RIPPING_TRACK $track / $track_count"
        
        if ! cdparanoia -d "$CD_DEVICE" "$track" "$wav_file" >>"$log_filename" 2>&1; then
            log_message "$MSG_ERROR_TRACK_RIP_FAILED $track"
            rm -rf "$temp_pathname"
            return 1
        fi
        
        # Konvertiere WAV zu MP3 mit lame
        # Dateiname: "Artist - Title.mp3" (Jellyfin-Format)
        local mp3_filename
        local track_title
        track_title=$(get_track_title "$track")
        
        if [[ -n "$track_title" ]] && [[ -n "$cd_artist" ]]; then
            # Jellyfin-Format: "Artist - Title.mp3"
            # Entferne nur gefährliche Zeichen, behalte Groß-/Kleinschreibung
            local safe_artist=$(echo "$cd_artist" | sed 's/[\/\\:*?"<>|]/_/g')
            local safe_title=$(echo "$track_title" | sed 's/[\/\\:*?"<>|]/_/g')
            mp3_filename="${safe_artist} - ${safe_title}.mp3"
            log_message "$MSG_ENCODING_TRACK_WITH_TITLE $track: $track_title"
        else
            # Fallback ohne MusicBrainz: "Track 01.mp3"
            mp3_filename="Track ${track_num}.mp3"
            log_message "$MSG_ENCODING_TRACK $track"
        fi
        
        local mp3_file="${album_dir}/${mp3_filename}"
        
        # lame Optionen: VBR Qualität aus Konfiguration, --quiet
        local lame_opts="-V${MP3_QUALITY} --quiet"
        
        # Füge ID3-Tags hinzu
        if [[ -n "$cd_artist" ]]; then
            lame_opts="$lame_opts --ta \"$cd_artist\""
        fi
        if [[ -n "$cd_album" ]]; then
            lame_opts="$lame_opts --tl \"$cd_album\""
        fi
        if [[ -n "$cd_year" ]]; then
            lame_opts="$lame_opts --ty \"$cd_year\""
        fi
        if [[ -n "$track_title" ]]; then
            lame_opts="$lame_opts --tt \"$track_title\""
        fi
        lame_opts="$lame_opts --tn \"$track/$track_count\""
        
        if ! eval lame $lame_opts \"$wav_file\" \"$mp3_file\" >>"$log_filename" 2>&1; then
            log_message "$MSG_ERROR_MP3_ENCODING_FAILED $track"
            rm -rf "$temp_pathname"
            [[ -n "$cover_file" ]] && rm -f "$cover_file"
            return 1
        fi
        
        # Bette Cover-Art ein (falls vorhanden und eyeD3 verfügbar)
        if [[ -n "$cover_file" ]] && [[ -f "$cover_file" ]]; then
            eyeD3 --quiet --add-image "${cover_file}:FRONT_COVER" "$mp3_file" >>"$log_filename" 2>&1
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
    done
    
    # Kopiere Cover als folder.jpg ins Album-Verzeichnis (Jellyfin-Standard)
    if [[ "${DEBUG:-0}" == "1" ]]; then
        log_message "${DBG_CHECKING_COVER_COPY/\%s/$cover_file}" | sed "s/%s/$album_dir/"
    fi
    if [[ -n "$cover_file" ]]; then
        if [[ -f "$cover_file" ]]; then
            [[ "${DEBUG:-0}" == "1" ]] && log_message "${DBG_COVER_FILE_EXISTS/\%s/$cover_file}"
            if cp "$cover_file" "${album_dir}/folder.jpg" 2>>/dev/stderr; then
                log_message "$MSG_COVER_SAVED_FOLDER_JPG"
            else
                log_message "$MSG_ERROR_COVER_COPY_FAILED"
            fi
        else
            log_message "$MSG_ERROR_COVER_FILE_NOT_FOUND $cover_file"
        fi
    else
        [[ "${DEBUG:-0}" == "1" ]] && log_message "$DBG_COVER_FILE_EMPTY"
    fi
    
    log_message "$MSG_RIPPING_COMPLETE_CREATE_ISO"
    
    # Erstelle album.nfo für Jellyfin
    create_album_nfo "$album_dir"
    
    # Sichere temp_pathname bevor init_filenames es überschreibt
    local audio_temp_path="$temp_pathname"
    
    # Initialisiere Dateinamen (verwendet disc_label)
    init_filenames
    
    # Prüfe Speicherplatz (MP3s sind ~10x kleiner als WAV, aber ISO braucht Overhead)
    local album_size_mb=$(du -sm "$album_dir" | awk '{print $1}')
    local required_mb=$((album_size_mb + album_size_mb / 10 + 50))  # +10% + 50MB Puffer
    
    if ! check_disk_space "$required_mb"; then
        log_message "$MSG_ERROR_INSUFFICIENT_SPACE_ISO"
        rm -rf "$audio_temp_path"
        return 1
    fi
    
    # Erstelle ISO mit genisoimage
    local volume_id
    if [[ -n "$cd_album" ]]; then
        # Volume-ID: max 32 Zeichen, nur A-Z0-9_
        volume_id=$(echo "$cd_album" | sed 's/[^A-Za-z0-9_]/_/g' | cut -c1-32 | tr '[:lower:]' '[:upper:]')
    else
        volume_id="AUDIO_CD"
    fi
    
    log_message "$MSG_CREATE_ISO: $iso_filename"
    log_message "$MSG_VOLUME_ID: $volume_id"
    
    # Erstelle ISO aus audio_temp_path (nicht album_dir!) um Ordnerstruktur zu erhalten
    # ISO enthält dann: AlbumArtist/Album/Tracks.mp3
    if ! genisoimage -R -J -joliet-long \
        -V "$volume_id" \
        -o "$iso_filename" \
        "$audio_temp_path" >>"$log_filename" 2>&1; then
        log_message "$MSG_ERROR_ISO_CREATION_FAILED"
        rm -rf "$audio_temp_path"
        return 1
    fi
    
    # Cleanup temp-Verzeichnis und Cover-Datei
    rm -rf "$audio_temp_path"
    [[ -n "$cover_file" ]] && rm -f "$cover_file"
    
    # Prüfe ISO-Größe
    if [[ ! -f "$iso_filename" ]]; then
        log_message "$MSG_ERROR_ISO_NOT_CREATED"
        return 1
    fi
    
    local iso_size_mb=$(du -m "$iso_filename" | awk '{print $1}')
    log_message "$MSG_ISO_CREATED: ${iso_size_mb} $MSG_PROGRESS_MB"
    
    # Erstelle MD5-Checksumme
    log_message "$MSG_CREATE_MD5"
    if ! md5sum "$iso_filename" > "$md5_filename" 2>>"$log_filename"; then
        log_message "$MSG_WARNING_MD5_FAILED"
    fi
    
    log_message "$MSG_AUDIO_CD_SUCCESS"
    return 0
}
