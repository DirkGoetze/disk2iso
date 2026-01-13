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
# Datum: 13.01.2026
################################################################################

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
        log_message "Audio-Remaster: ISO-Datei nicht gefunden: $iso_path"
        return 1
    fi
    
    if [[ -z "$mb_release_id" ]]; then
        log_message "Audio-Remaster: Keine MusicBrainz Release-ID angegeben"
        return 1
    fi
    
    log_message "Audio-Remaster: Starte ISO-Remaster für: $(basename "$iso_path")"
    
    # Erstelle temporäre Verzeichnisse in .temp (gleicher Parent wie ISO)
    local iso_dir=$(dirname "$iso_path")
    local iso_parent=$(dirname "$iso_dir")
    local temp_base="${iso_parent}/.temp"
    
    local temp_extract="${temp_base}/disk2iso_remaster_$$"
    local temp_tagged="${temp_base}/disk2iso_tagged_$$"
    
    mkdir -p "$temp_extract" "$temp_tagged"
    
    # Schritt 1: ISO extrahieren/mounten
    log_message "Audio-Remaster: [1/4] Extrahiere ISO..."
    if ! extract_iso_to_temp "$iso_path" "$temp_extract"; then
        cleanup_remaster_temp "$temp_extract" "$temp_tagged"
        return 1
    fi
    
    # Schritt 2: MusicBrainz-Metadaten abrufen
    log_message "Audio-Remaster: [2/4] Hole MusicBrainz-Metadaten..."
    local mb_data=$(get_musicbrainz_release_details "$mb_release_id")
    
    if [[ -z "$mb_data" ]]; then
        log_message "Audio-Remaster: Konnte MusicBrainz-Daten nicht abrufen"
        cleanup_remaster_temp "$temp_extract" "$temp_tagged"
        return 1
    fi
    
    # Extrahiere Album-Metadaten
    local artist=$(echo "$mb_data" | jq -r '."artist-credit"[0].name // "Unknown Artist"')
    local album=$(echo "$mb_data" | jq -r '.title // "Unknown Album"')
    local year=$(echo "$mb_data" | jq -r '.date // "" | split("-")[0]')
    local cover_url=$(echo "$mb_data" | jq -r '.["cover-art-archive"].front // empty')
    
    log_message "Audio-Remaster: Album: $artist - $album ($year)"
    
    # Lade Cover von Cover Art Archive
    local cover_file=""
    local cover_url="https://coverartarchive.org/release/${mb_release_id}/front-500"
    
    cover_file="${temp_extract}/cover.jpg"
    if curl -s -f "$cover_url" -o "$cover_file" 2>/dev/null; then
        log_message "Audio-Remaster: Cover heruntergeladen"
    else
        log_message "Audio-Remaster: Cover-Download fehlgeschlagen (kein Cover verfügbar)"
        cover_file=""
    fi
    
    # Schritt 3: MP3-Tags aktualisieren
    log_message "Audio-Remaster: [3/4] Aktualisiere MP3-Tags..."
    if ! update_mp3_tags_from_musicbrainz "$temp_extract" "$temp_tagged" "$mb_data" "$cover_file"; then
        cleanup_remaster_temp "$temp_extract" "$temp_tagged"
        return 1
    fi
    
    # Schritt 4: Neue ISO erstellen
    log_message "Audio-Remaster: [4/4] Erstelle neue ISO..."
    
    # Nutze .temp Verzeichnis im gleichen Parent wie die ISO
    local iso_dir=$(dirname "$iso_path")
    local iso_parent=$(dirname "$iso_dir")
    local temp_iso="${iso_parent}/.temp/disk2iso_new_$$.iso"
    
    if ! rebuild_audio_iso "$temp_tagged" "$temp_iso"; then
        cleanup_remaster_temp "$temp_extract" "$temp_tagged"
        return 1
    fi
    
    # Ersetze alte ISO
    if mv -f "$temp_iso" "$iso_path"; then
        log_message "Audio-Remaster: ISO erfolgreich aktualisiert"
        
        # Erstelle .nfo mit Metadaten
        create_audio_nfo "$iso_path" "$artist" "$album" "$year" "$cover_file"
        
        # Benenne ISO nach Artist - Album Schema um
        local clean_artist=$(echo "$artist" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')
        local clean_album=$(echo "$album" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//')
        local new_name="${clean_artist}_${clean_album}.iso"
        local new_path="${iso_dir}/${new_name}"
        
        # Benenne um wenn Name anders ist
        if [[ "$iso_path" != "$new_path" ]]; then
            if mv -f "$iso_path" "$new_path"; then
                log_message "Audio-Remaster: ISO umbenannt: $(basename "$new_path")"
                
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
                
                # MD5 neu berechnen für umbenannte ISO
                if command -v md5sum >/dev/null 2>&1; then
                    md5sum "$new_path" | cut -d' ' -f1 > "$new_md5"
                    log_message "Audio-Remaster: MD5 aktualisiert"
                fi
            else
                log_message "Audio-Remaster: Warnung - ISO-Umbenennung fehlgeschlagen"
            fi
        else
            # Nur MD5 neu berechnen
            local md5_file="${iso_path%.iso}.md5"
            if command -v md5sum >/dev/null 2>&1; then
                md5sum "$iso_path" | cut -d' ' -f1 > "$md5_file"
                log_message "Audio-Remaster: MD5 aktualisiert"
            fi
        fi
        
        cleanup_remaster_temp "$temp_extract" "$temp_tagged"
        return 0
    else
        log_message "Audio-Remaster: Fehler beim Ersetzen der ISO"
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
    
    # Versuche 7z (bevorzugt, funktioniert ohne Mount)
    if command -v 7z >/dev/null 2>&1; then
        if 7z x "$iso_path" -o"$temp_dir" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    # Fallback: Loop-Mount
    local mount_point="${temp_dir}_mount"
    mkdir -p "$mount_point"
    
    if mount -o loop,ro "$iso_path" "$mount_point" 2>/dev/null; then
        cp -r "$mount_point"/* "$temp_dir/" 2>/dev/null
        umount "$mount_point"
        rmdir "$mount_point"
        return 0
    fi
    
    log_message "Audio-Remaster: ISO-Extraktion fehlgeschlagen"
    return 1
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
        log_message "Audio-Remaster: Kein ID3-Tagging-Tool gefunden (eyeD3/id3v2)"
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
        log_message "Audio-Remaster: Keine MP3-Dateien in ISO gefunden"
        return 1
    fi
    
    log_message "Audio-Remaster: Gefunden: $mp3_count MP3s, MusicBrainz: $track_count Tracks"
    
    # Tagge jede MP3
    local track_num=1
    for mp3_file in "${mp3_files[@]}"; do
        local filename=$(basename "$mp3_file")
        local target_file="$target_dir/$filename"
        
        # Kopiere MP3
        cp "$mp3_file" "$target_file"
        
        # Hole Track-Titel aus MusicBrainz
        local track_title=""
        if [[ $track_num -le $track_count ]]; then
            track_title=$(echo "$tracks" | jq -r ".[$(($track_num - 1))].title // \"Track $track_num\"")
        else
            track_title="Track $track_num"
        fi
        
        # Tagge mit eyeD3 oder id3v2
        if [[ "$tag_tool" == "eyeD3" ]]; then
            eyeD3 --quiet \
                --artist "$artist" \
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
            # id3v2
            id3v2 \
                --artist "$artist" \
                --album "$album" \
                --song "$track_title" \
                --track "$track_num" \
                ${year:+--year "$year"} \
                "$target_file" >/dev/null 2>&1
        fi
        
        log_message "Audio-Remaster: Getaggt: $track_num. $track_title"
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
        log_message "Audio-Remaster: Kein ISO-Tool gefunden (genisoimage/mkisofs)"
        return 1
    fi
    
    # Prüfe ob Quellverzeichnis Dateien enthält
    if [[ -z "$(ls -A "$source_dir" 2>/dev/null)" ]]; then
        log_message "Audio-Remaster: Quellverzeichnis ist leer: $source_dir"
        return 1
    fi
    
    # Erstelle ISO mit UDF + Joliet (maximale Kompatibilität)
    local iso_errors=$(mktemp)
    if $iso_tool -r -J -o "$output_iso" "$source_dir" 2>"$iso_errors"; then
        log_message "Audio-Remaster: ISO erfolgreich erstellt: $(basename "$output_iso")"
        rm -f "$iso_errors"
        return 0
    else
        log_message "Audio-Remaster: ISO-Erstellung fehlgeschlagen: $(cat "$iso_errors")"
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
#   $5 = cover_file (optional)
create_audio_nfo() {
    local iso_path="$1"
    local artist="$2"
    local album="$3"
    local year="$4"
    local cover_file="$5"
    
    local nfo_file="${iso_path%.iso}.nfo"
    local thumb_file="${iso_path%.iso}-thumb.jpg"
    
    # Erstelle .nfo (mit Feldern die das Frontend erwartet)
    cat > "$nfo_file" <<EOF
ARTIST=$artist
ALBUM=$album
TITLE=$album
DATE=$year
YEAR=$year
TYPE=audio-cd
EOF
    
    # Kopiere Cover
    if [[ -n "$cover_file" ]] && [[ -f "$cover_file" ]]; then
        cp "$cover_file" "$thumb_file"
    fi
    
    log_message "Audio-Remaster: .nfo erstellt"
}

# Funktion: Hole MusicBrainz Release-Details
# Parameter: $1 = release_id
# Rückgabe: JSON mit Release-Details
get_musicbrainz_release_details() {
    local release_id="$1"
    
    local url="https://musicbrainz.org/ws/2/release/${release_id}?fmt=json&inc=artists+recordings+artist-credits"
    
    local response=$(curl -s -f "$url" 2>/dev/null)
    
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
