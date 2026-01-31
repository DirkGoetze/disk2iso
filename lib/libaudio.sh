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
INITIALIZED_AUDIO=false                     # Initialisierung war erfolgreich
ACTIVATED_AUDIO=false                            # In Konfiguration aktiviert

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

    #-- Lade Modul-Konfiguration --------------------------------------------
    load_config_audio || return 1

    #-- Setze Verfügbarkeit -------------------------------------------------
    SUPPORT_AUDIO=true
    log_debug "$MSG_DEBUG_AUDIO_CHECK_COMPLETE"
    
    #-- Abhängigkeiten erfüllt ----------------------------------------------
    log_info "$MSG_AUDIO_SUPPORT_AVAILABLE"
    return 0
}

# ===========================================================================
# load_config_audio
# ---------------------------------------------------------------------------
# Funktion.: Lade Audio-Modul Konfiguration und setze Initialisierung
# Parameter: keine
# Rückgabe.: 0 = Erfolgreich geladen
# Setzt....: INITIALIZED_AUDIO=true, ACTIVATED_AUDIO=true
# Hinweis..: Audio-Modul hat keine API-Config, daher nur Flags setzen
# .........  Modul ist immer aktiviert wenn Support vorhanden
# ===========================================================================
load_config_audio() {
    # Audio-CD ist immer aktiviert wenn Support verfügbar (keine Runtime-Deaktivierung)
    ACTIVATED_AUDIO=true
    
    # Setze Initialisierungs-Flag
    INITIALIZED_AUDIO=true
    
    log_info "Audio-CD: Konfiguration geladen"
    return 0
}

# ===========================================================================
# is_audio_ready
# ---------------------------------------------------------------------------
# Funktion.: Prüfe ob Audio-Modul supported wird, initialisiert wurde und
# .........  aktiviert ist. Wenn true ist alles bereit für die Nutzung.
# Parameter: keine
# Rückgabe.: 0 = Bereit, 1 = Nicht bereit
# ===========================================================================
is_audio_ready() {
    [[ "$SUPPORT_AUDIO" == "true" ]] && \
    [[ "$INITIALIZED_AUDIO" == "true" ]] && \
    [[ "$ACTIVATED_AUDIO" == "true" ]]
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

# ===========================================================================
# get_cdtext_metadata
# ---------------------------------------------------------------------------
# Funktion.: CD-TEXT auslesen (Fallback wenn MusicBrainz nicht verfügbar)
# Benötigt.: icedax oder cd-info (aus libcdio)
# Rückgabe.: 0 = Metadaten gefunden, 1 = Keine CD-TEXT Daten
# Setzt....: DISC_DATA[artist], DISC_DATA[album], DISC_DATA[track_count]
#            DISC_DATA[track.N.title], DISC_DATA[track.N.artist] (falls vorhanden)
#            + globale Variablen cd_artist, cd_album (DEPRECATED)
# Provider.: none (CD-TEXT ist in der Disc eingebettet)
# Hinweis..: CD-TEXT nach Red Book Standard unterstützt pro Track:
#            TITLE, PERFORMER, SONGWRITER, COMPOSER, ARRANGER, MESSAGE
# ===========================================================================
get_cdtext_metadata() {
    local artist=""
    local album=""
    local track_count=0
    local found_tracks=false
    
    log_info "$MSG_TRY_CDTEXT"
    
    # Methode 1: cd-info (aus libcdio-utils) - BESTE Methode für Track-Details
    if command -v cd-info >/dev/null 2>&1; then
        local cdtext_output
        cdtext_output=$(cd-info --no-header --no-device-info --cdtext-only "$CD_DEVICE" 2>/dev/null)
        
        if [[ -n "$cdtext_output" ]]; then
            # Extrahiere Album-Level Daten (erste TITLE/PERFORMER Einträge)
            album=$(echo "$cdtext_output" | grep -i "TITLE" | head -1 | cut -d':' -f2- | xargs)
            artist=$(echo "$cdtext_output" | grep -i "PERFORMER" | head -1 | cut -d':' -f2- | xargs)
            
            # Extrahiere Track-Level Daten (cd-info Format: "CD-TEXT for Track N:")
            local current_track=0
            local in_track_section=false
            
            while IFS= read -r line; do
                # Erkenne Track-Sektion: "CD-TEXT for Track 1:"
                if [[ "$line" =~ ^CD-TEXT\ for\ Track\ ([0-9]+): ]]; then
                    current_track="${BASH_REMATCH[1]}"
                    in_track_section=true
                    ((track_count++))
                    continue
                fi
                
                # Erkenne Disc-Sektion (Ende der Track-Daten)
                if [[ "$line" =~ ^CD-TEXT\ for\ Disc: ]]; then
                    in_track_section=false
                    continue
                fi
                
                # Lese Track-Daten
                if [[ "$in_track_section" == true ]] && [[ $current_track -gt 0 ]]; then
                    if [[ "$line" =~ ^[[:space:]]*TITLE:[[:space:]]*(.*) ]]; then
                        local track_title="${BASH_REMATCH[1]}"
                        if [[ -n "$track_title" ]]; then
                            DISC_DATA["track.${current_track}.title"]="$track_title"
                            found_tracks=true
                        fi
                    elif [[ "$line" =~ ^[[:space:]]*PERFORMER:[[:space:]]*(.*) ]]; then
                        local track_artist="${BASH_REMATCH[1]}"
                        if [[ -n "$track_artist" ]]; then
                            DISC_DATA["track.${current_track}.artist"]="$track_artist"
                        fi
                    elif [[ "$line" =~ ^[[:space:]]*COMPOSER:[[:space:]]*(.*) ]]; then
                        local track_composer="${BASH_REMATCH[1]}"
                        if [[ -n "$track_composer" ]]; then
                            DISC_DATA["track.${current_track}.composer"]="$track_composer"
                        fi
                    elif [[ "$line" =~ ^[[:space:]]*SONGWRITER:[[:space:]]*(.*) ]]; then
                        local track_songwriter="${BASH_REMATCH[1]}"
                        if [[ -n "$track_songwriter" ]]; then
                            DISC_DATA["track.${current_track}.songwriter"]="$track_songwriter"
                        fi
                    elif [[ "$line" =~ ^[[:space:]]*ARRANGER:[[:space:]]*(.*) ]]; then
                        local track_arranger="${BASH_REMATCH[1]}"
                        if [[ -n "$track_arranger" ]]; then
                            DISC_DATA["track.${current_track}.arranger"]="$track_arranger"
                        fi
                    fi
                fi
            done <<< "$cdtext_output"
            
            if [[ -n "$artist" ]] && [[ -n "$album" ]]; then
                # Setze DISC_DATA Array
                discdata_set_artist "$artist"
                discdata_set_album "$album"
                [[ $track_count -gt 0 ]] && discdata_set_track_count "$track_count"
                
                # Setze Provider auf "none" (CD-TEXT ist kein externer Provider)
                discinfo_set_provider "none"
                
                # Backward compatibility (DEPRECATED)
                cd_artist="$artist"
                cd_album="$album"
                
                if [[ "$found_tracks" == true ]]; then
                    log_info "$MSG_CDTEXT_FOUND $artist - $album ($track_count Tracks mit Titeln)"
                else
                    log_info "$MSG_CDTEXT_FOUND $artist - $album"
                fi
                return 0
            fi
        fi
    fi
    
    # Methode 2: icedax (aus cdrtools/cdrkit) - Vollständige Ausgabe mit -v
    if command -v icedax >/dev/null 2>&1; then
        local cdtext_output
        cdtext_output=$(icedax -J -H -D "$CD_DEVICE" -v all 2>&1)
        
        if [[ -n "$cdtext_output" ]]; then
            # Extrahiere Album-Daten
            album=$(echo "$cdtext_output" | grep "^Albumtitle:" | head -1 | cut -d':' -f2- | xargs)
            artist=$(echo "$cdtext_output" | grep "^Performer:" | head -1 | cut -d':' -f2- | xargs)
            
            # Extrahiere Track-Daten (icedax Format: "Tracktitle[N]: ...")
            local max_track=0
            while IFS= read -r line; do
                if [[ "$line" =~ ^Tracktitle\[([0-9]+)\]:[[:space:]]*(.*) ]]; then
                    local track_num="${BASH_REMATCH[1]}"
                    local track_title="${BASH_REMATCH[2]}"
                    if [[ -n "$track_title" ]]; then
                        DISC_DATA["track.${track_num}.title"]="$track_title"
                        found_tracks=true
                        [[ $track_num -gt $max_track ]] && max_track=$track_num
                    fi
                elif [[ "$line" =~ ^Trackperformer\[([0-9]+)\]:[[:space:]]*(.*) ]]; then
                    local track_num="${BASH_REMATCH[1]}"
                    local track_artist="${BASH_REMATCH[2]}"
                    if [[ -n "$track_artist" ]]; then
                        DISC_DATA["track.${track_num}.artist"]="$track_artist"
                    fi
                elif [[ "$line" =~ ^Trackcomposer\[([0-9]+)\]:[[:space:]]*(.*) ]]; then
                    local track_num="${BASH_REMATCH[1]}"
                    local track_composer="${BASH_REMATCH[2]}"
                    if [[ -n "$track_composer" ]]; then
                        DISC_DATA["track.${track_num}.composer"]="$track_composer"
                    fi
                elif [[ "$line" =~ ^Tracksongwriter\[([0-9]+)\]:[[:space:]]*(.*) ]]; then
                    local track_num="${BASH_REMATCH[1]}"
                    local track_songwriter="${BASH_REMATCH[2]}"
                    if [[ -n "$track_songwriter" ]]; then
                        DISC_DATA["track.${track_num}.songwriter"]="$track_songwriter"
                    fi
                elif [[ "$line" =~ ^Trackarranger\[([0-9]+)\]:[[:space:]]*(.*) ]]; then
                    local track_num="${BASH_REMATCH[1]}"
                    local track_arranger="${BASH_REMATCH[2]}"
                    if [[ -n "$track_arranger" ]]; then
                        DISC_DATA["track.${track_num}.arranger"]="$track_arranger"
                    fi
                fi
            done <<< "$cdtext_output"
            
            [[ $max_track -gt $track_count ]] && track_count=$max_track
            
            if [[ -n "$artist" ]] && [[ -n "$album" ]]; then
                # Setze DISC_DATA Array
                discdata_set_artist "$artist"
                discdata_set_album "$album"
                [[ $track_count -gt 0 ]] && discdata_set_track_count "$track_count"
                
                # Setze Provider auf "none"
                discinfo_set_provider "none"
                
                # Backward compatibility (DEPRECATED)
                cd_artist="$artist"
                cd_album="$album"
                
                if [[ "$found_tracks" == true ]]; then
                    log_info "$MSG_CDTEXT_FOUND $artist - $album ($track_count Tracks mit Titeln)"
                else
                    log_info "$MSG_CDTEXT_FOUND $artist - $album"
                fi
                return 0
            fi
        fi
    fi
    
    # Methode 3: cdda2wav (aus cdrtools) - Ähnlich wie icedax
    if command -v cdda2wav >/dev/null 2>&1; then
        local cdtext_output
        cdtext_output=$(cdda2wav -J -H -D "$CD_DEVICE" -v all 2>&1)
        
        if [[ -n "$cdtext_output" ]]; then
            # Extrahiere Album-Daten
            album=$(echo "$cdtext_output" | grep "^Albumtitle:" | head -1 | cut -d':' -f2- | xargs)
            artist=$(echo "$cdtext_output" | grep "^Performer:" | head -1 | cut -d':' -f2- | xargs)
            
            # Extrahiere Track-Daten
            local max_track=0
            while IFS= read -r line; do
                if [[ "$line" =~ ^Tracktitle\[([0-9]+)\]:[[:space:]]*(.*) ]]; then
                    local track_num="${BASH_REMATCH[1]}"
                    local track_title="${BASH_REMATCH[2]}"
                    if [[ -n "$track_title" ]]; then
                        DISC_DATA["track.${track_num}.title"]="$track_title"
                        found_tracks=true
                        [[ $track_num -gt $max_track ]] && max_track=$track_num
                    fi
                elif [[ "$line" =~ ^Trackperformer\[([0-9]+)\]:[[:space:]]*(.*) ]]; then
                    local track_num="${BASH_REMATCH[1]}"
                    local track_artist="${BASH_REMATCH[2]}"
                    if [[ -n "$track_artist" ]]; then
                        DISC_DATA["track.${track_num}.artist"]="$track_artist"
                    fi
                elif [[ "$line" =~ ^Trackcomposer\[([0-9]+)\]:[[:space:]]*(.*) ]]; then
                    local track_num="${BASH_REMATCH[1]}"
                    local track_composer="${BASH_REMATCH[2]}"
                    if [[ -n "$track_composer" ]]; then
                        DISC_DATA["track.${track_num}.composer"]="$track_composer"
                    fi
                elif [[ "$line" =~ ^Tracksongwriter\[([0-9]+)\]:[[:space:]]*(.*) ]]; then
                    local track_num="${BASH_REMATCH[1]}"
                    local track_songwriter="${BASH_REMATCH[2]}"
                    if [[ -n "$track_songwriter" ]]; then
                        DISC_DATA["track.${track_num}.songwriter"]="$track_songwriter"
                    fi
                elif [[ "$line" =~ ^Trackarranger\[([0-9]+)\]:[[:space:]]*(.*) ]]; then
                    local track_num="${BASH_REMATCH[1]}"
                    local track_arranger="${BASH_REMATCH[2]}"
                    if [[ -n "$track_arranger" ]]; then
                        DISC_DATA["track.${track_num}.arranger"]="$track_arranger"
                    fi
                fi
            done <<< "$cdtext_output"
            
            [[ $max_track -gt $track_count ]] && track_count=$max_track
            
            if [[ -n "$artist" ]] && [[ -n "$album" ]]; then
                # Setze DISC_DATA Array
                discdata_set_artist "$artist"
                discdata_set_album "$album"
                [[ $track_count -gt 0 ]] && discdata_set_track_count "$track_count"
                
                # Setze Provider auf "none"
                discinfo_set_provider "none"
                
                # Backward compatibility (DEPRECATED)
                cd_artist="$artist"
                cd_album="$album"
                
                if [[ "$found_tracks" == true ]]; then
                    log_info "$MSG_CDTEXT_FOUND $artist - $album ($track_count Tracks mit Titeln)"
                else
                    log_info "$MSG_CDTEXT_FOUND $artist - $album"
                fi
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

# ===========================================================================
# get_musicbrainz_metadata
# ---------------------------------------------------------------------------
# Funktion.: MusicBrainz-Metadaten abrufen
# Benötigt.: cd-discid, curl, jq
# Rückgabe.: 0 = Metadaten gefunden, 1 = Fehler/Nicht gefunden
# Setzt....: DISC_INFO[disc_id], DISC_INFO[provider], DISC_INFO[provider_id]
#            DISC_DATA[artist], DISC_DATA[album], DISC_DATA[year],
#            DISC_DATA[track_count], DISC_DATA[toc]
#            + globale Variablen (DEPRECATED): cd_artist, cd_album, cd_year,
#            cd_discid, mb_response, best_release_index, toc, track_count
# Provider.: musicbrainz
# ===========================================================================
# DEPRECATED: Diese Funktion wird durch das neue Metadata-Framework ersetzt.
# Verwende stattdessen:
#   - metadata_query_before_copy() aus libmetadata.sh
#   - metadata_wait_for_selection() aus libmetadata.sh
#   - Provider-Module: libmusicbrainz.sh
# Wird in v1.3.0 entfernt.
# ===========================================================================
get_musicbrainz_metadata() {
    local artist=""
    local album=""
    local year=""
    local disc_id=""
    mb_response=""  # Speichere vollständige Antwort für Track-Infos
    best_release_index=0  # Index des gewählten Release (bei mehreren Treffern)
    local toc_str=""  # TOC-String für MusicBrainz
    local tracks=""  # Anzahl der Tracks
    
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
    disc_id="${discid_parts[0]}"
    tracks="${discid_parts[1]}"
    
    log_info "$MSG_DISCID: $disc_id ($MSG_TRACKS: $tracks)"
    
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
    toc_str="1+${tracks}+${leadout}"
    for ((i=2; i<${#discid_parts[@]}-1; i++)); do
        toc_str="${toc_str}+${discid_parts[$i]}"
    done
    
    # MusicBrainz-Abfrage mit TOC statt nur Disc-ID
    local mb_url="https://musicbrainz.org/ws/2/discid/${disc_id}?toc=${toc_str}&fmt=json&inc=artists+recordings"
    
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
        log_warning "$MSG_WARNING_NO_MUSICBRAINZ_ENTRY $disc_id"
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
            local releases_json="{\"disc_id\":\"$disc_id\",\"track_count\":$tracks,\"releases\":$releases_array}"
            
            api_write_json "musicbrainz_releases.json" "$releases_json"
        fi
        
        # Automatische Auswahl nach Score (kann vom User überschrieben werden)
        local best_score=0
        
        for ((i=0; i<releases_count; i++)); do
            local score=0
            
            # Prüfe Track-Anzahl-Übereinstimmung (wichtigster Faktor)
            local release_tracks
            release_tracks=$(echo "$mb_response" | jq -r ".releases[$i].media[0].tracks | length" 2>/dev/null)
            
            if [[ "$release_tracks" == "$tracks" ]]; then
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
        
        # API-Update: Benutzereingriff erforderlich (triggert automatisch MQTT)
        if declare -f api_update_status >/dev/null 2>&1; then
            api_update_status "waiting" "MusicBrainz: $releases_count Alben gefunden" "CD"
        fi
        
        # Markiere, dass User-Input benötigt wird
        export MUSICBRAINZ_NEEDS_CONFIRMATION=true
    fi
    
    # Extrahiere gewähltes Release
    album=$(echo "$mb_response" | jq -r ".releases[$best_release_index].title" 2>/dev/null)
    artist=$(echo "$mb_response" | jq -r ".releases[$best_release_index][\"artist-credit\"][0].name" 2>/dev/null)
    year=$(echo "$mb_response" | jq -r ".releases[$best_release_index].date" 2>/dev/null | cut -d'-' -f1)
    local release_id=$(echo "$mb_response" | jq -r ".releases[$best_release_index].id" 2>/dev/null)
    
    # Bereinige null-Werte
    [[ "$album" == "null" ]] && album=""
    [[ "$artist" == "null" ]] && artist=""
    [[ "$year" == "null" ]] && year=""
    [[ "$release_id" == "null" ]] && release_id=""
    
    if [[ -n "$artist" ]] && [[ -n "$album" ]]; then
        # Setze DISC_INFO Felder
        discinfo_set_disc_id "$disc_id"
        discinfo_set_provider "musicbrainz"
        [[ -n "$release_id" ]] && discinfo_set_provider_id "$release_id"
        
        # Setze DISC_DATA Felder
        discdata_set_artist "$artist"
        discdata_set_album "$album"
        [[ -n "$year" ]] && discdata_set_year "$year"
        discdata_set_track_count "$tracks"
        discdata_set_toc "$toc_str"
        
        # Backward compatibility (DEPRECATED)
        cd_artist="$artist"
        cd_album="$album"
        cd_year="$year"
        cd_discid="$disc_id"
        toc="$toc_str"
        track_count="$tracks"
        
        log_info "$MSG_ALBUM: $album"
        log_info "$MSG_ARTIST: $artist"
        [[ -n "$year" ]] && log_info "$MSG_YEAR: $year"
        
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

# Funktion: Hole Track-Titel aus MusicBrainz-Antwort oder DISC_DATA (CD-TEXT)
# Parameter: $1 = Track-Nummer (1-basiert)
# Rückgabe: Track-Titel oder leer
get_track_title() {
    local track_num="$1"
    local track_title=""
    
    # Methode 1: DISC_DATA (für CD-TEXT oder andere Provider)
    track_title="${DISC_DATA[track.${track_num}.title]}"
    if [[ -n "$track_title" ]]; then
        echo "$track_title"
        return 0
    fi
    
    # Methode 2: MusicBrainz mb_response
    if [[ -n "$mb_response" ]]; then
        local release_idx="${best_release_index:-0}"
        local track_index=$((track_num - 1))
        
        track_title=$(echo "$mb_response" | jq -r ".releases[$release_idx].media[0].tracks[${track_index}].recording.title" 2>/dev/null)
        
        if [[ -n "$track_title" ]] && [[ "$track_title" != "null" ]]; then
            echo "$track_title"
            return 0
        fi
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
# ============================================================================
# DEPRECATED: Diese Funktion wird durch das neue Metadata-Framework ersetzt.
# Verwende stattdessen:
#   - metadata_wait_for_selection() aus libmetadata.sh
# Wird in v1.3.0 entfernt.
# ============================================================================
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
    # METADATA BEFORE COPY - Neue Strategie
    # ========================================================================
    # Metadaten VOR dem Rippen abfragen und auf User-Auswahl warten
    
    cd_artist=""
    cd_album=""
    cd_year=""
    cd_discid=""
    mb_response=""
    local skip_metadata="${SKIP_METADATA:-false}"
    
    # ==================== METADATA-ABFRAGE (NEUES FRAMEWORK) ====================
    # Nutzt libmetadata.sh + Provider-Module (libmusicbrainz.sh)
    # - Provider registrieren sich automatisch via metadata_load_registered_providers()
    # - DISC_DATA[] dient als zentraler State-Container
    # - Metadaten werden via API bereitgestellt BEVOR der Kopiervorgang startet
    
    # Variablen aus DISC_DATA extrahieren (falls bereits gesetzt)
    local cd_artist="${DISC_DATA[artist]}"
    local cd_album="${DISC_DATA[album]}"
    cd_year="${DISC_DATA[year]}"
    local cd_genre="${DISC_DATA[genre]}"
    
    # MusicBrainz-Variablen (für NFO/Cover-Download)
    local mb_release_id="${DISC_DATA[musicbrainz_release_id]}"
    local mb_artist_id="${DISC_DATA[musicbrainz_artist_id]}"
    mb_response="${DISC_DATA[musicbrainz_response]}"
    
    # Cover-Art Variablen
    local cover_url="${DISC_DATA[coverart_url]}"
    local cover_file=""
    
    # Metadata-Abfrage nur wenn nicht übersprungen UND Framework bereit
    if [[ "$skip_metadata" == "false" ]] && is_metadata_ready && metadata_has_provider_for_type "audio-cd"; then
        log_info "$MSG_QUERY_MUSICBRAINZ"
        
        # Provider-Name holen (z.B. "musicbrainz")
        local provider
        provider=$(metadata_get_provider "audio-cd")
        
        # Framework-Call: Query auslösen (lädt Ergebnisse in API)
        if metadata_query_before_copy "audio-cd" "$cd_discid" "$cd_discid"; then
            # Warte auf Browser-Auswahl über API
            if metadata_wait_for_selection "audio-cd" "$cd_discid" "$provider"; then
                # Variablen aus DISC_DATA neu laden (wurden von Browser via API gesetzt)
                cd_artist="${DISC_DATA[artist]}"
                cd_album="${DISC_DATA[album]}"
                cd_year="${DISC_DATA[year]}"
                cd_genre="${DISC_DATA[genre]}"
                mb_release_id="${DISC_DATA[musicbrainz_release_id]}"
                mb_artist_id="${DISC_DATA[musicbrainz_artist_id]}"
                mb_response="${DISC_DATA[musicbrainz_response]}"
                cover_url="${DISC_DATA[coverart_url]}"
            else
                log_warning "$MSG_WARNING_METADATA_TIMEOUT"
                skip_metadata=true
            fi
        else
            # Fallback: MusicBrainz fehlgeschlagen → Versuche CD-TEXT
            log_info "MusicBrainz nicht verfügbar - versuche CD-TEXT Fallback"
            if get_cdtext_metadata; then
                # CD-TEXT erfolgreich - verwende diese Metadaten
                cd_artist="${DISC_DATA[artist]}"
                cd_album="${DISC_DATA[album]}"
                cd_year="${DISC_DATA[year]}"
                skip_metadata=false
            else
                log_info "$MSG_CONTINUE_WITHOUT_METADATA"
                skip_metadata=true
            fi
        fi
    elif [[ "$skip_metadata" == "false" ]]; then
        # Framework nicht bereit → Fallback zu CD-TEXT
        log_info "Metadata-Framework nicht bereit - versuche CD-TEXT Fallback"
        if get_cdtext_metadata; then
            cd_artist="${DISC_DATA[artist]}"
            cd_album="${DISC_DATA[album]}"
            cd_year="${DISC_DATA[year]}"
            skip_metadata=false
        else
            log_info "$MSG_CONTINUE_WITHOUT_METADATA"
            skip_metadata=true
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
        local new_label="${label_artist}_${label_album}"
        discinfo_set_label "$new_label"
    else
        # Keine Metadaten - einfache DiskID-Struktur
        if [[ -n "$cd_discid" ]]; then
            album_dir="${temp_pathname}/audio_cd_${cd_discid}"
            discinfo_set_label "audio_cd_${cd_discid}"
        else
            local timestamp=$(date +%Y%m%d_%H%M%S)
            album_dir="${temp_pathname}/audio_cd_${timestamp}"
            discinfo_set_label "audio_cd_${timestamp}"
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
    
    # Initialisiere alle Dateinamen zentral (jetzt wo Label bekannt ist)
    init_filenames
    
    # Initialisiere Kopiervorgang-Log (NEUES SYSTEM)
    init_copy_log "$(discinfo_get_label)" "audio-cd"
    
    log_copying "$MSG_TRACKS_FOUND: $track_count"
    log_copying "$MSG_ALBUM_DIRECTORY: $album_dir"
    
    # Log Metadata (BEFORE strategy - jetzt schon bekannt!)
    if [[ "$skip_metadata" == "false" ]] && [[ -n "$cd_artist" ]] && [[ -n "$cd_album" ]]; then
        log_copying "Album: $cd_artist - $cd_album"
        [[ -n "$cd_year" ]] && log_copying "Jahr: $cd_year"
        log_info "Rippe Album: $cd_artist - $cd_album ($track_count Tracks)"
    else
        log_copying "Disc-ID: ${cd_discid:-unbekannt}"
        log_info "Rippe Audio-CD: $(discinfo_get_label) ($track_count Tracks)"
    fi
    
    # API: Aktualisiere Status (triggert automatisch MQTT via Observer Pattern)
    if declare -f api_update_status >/dev/null 2>&1; then
        api_update_status "copying" "$(discinfo_get_label)" "audio-cd"
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
        
        # Progress-Message mit Tracktitel (falls verfügbar aus MusicBrainz oder CD-TEXT)
        if [[ "$skip_metadata" == "false" ]]; then
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
        # Dateiname abhängig von verfügbaren Metadaten (MusicBrainz oder CD-TEXT)
        local mp3_filename
        local mp3_file
        
        if [[ "$skip_metadata" == "false" ]]; then
            # Metadaten verfügbar - nutze Track-Titel aus MusicBrainz oder CD-TEXT
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
            
            # Composer aus CD-TEXT oder DISC_DATA (für Jellyfin ID3-Tag TCOM)
            local track_composer="${DISC_DATA[track.${track}.composer]}"
            if [[ -n "$track_composer" ]]; then
                lame_opts+=("--tc" "$track_composer")
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
        
        # API: Fortschritt senden (triggert automatisch MQTT via Observer Pattern)
        if declare -f api_update_progress >/dev/null 2>&1; then
            # Schätze verbleibende Zeit (ca. 4 Minuten pro Track als Durchschnitt)
            local remaining_tracks=$((total_tracks - processed_tracks))
            local eta_minutes=$((remaining_tracks * 4))
            local eta=$(printf "%02d:%02d:00" $((eta_minutes / 60)) $((eta_minutes % 60)))
            
            api_update_progress "$percent" "$processed_tracks" "$total_tracks" "$eta"
        fi
    done
    
    # Kopiere Cover als folder.jpg (falls vorhanden)
    if [[ "$skip_metadata" == "false" ]] && [[ -n "$cover_file" ]] && [[ -f "$cover_file" ]]; then
        cp "$cover_file" "${album_dir}/folder.jpg" 2>/dev/null && \
            log_info "$MSG_COVER_SAVED_FOLDER_JPG"
    fi
    
    log_copying "$MSG_RIPPING_COMPLETE_CREATE_ISO"
    
    # Erstelle album.nfo für Jellyfin (falls Metadaten verfügbar)
    # HINWEIS: Nutzt metadata_export_nfo() aus libmetadata.sh
    if [[ "$skip_metadata" == "false" ]] && declare -f metadata_export_nfo >/dev/null 2>&1; then
        local nfo_file="${album_dir}/album.nfo"
        metadata_export_nfo "$nfo_file" && log_info "$MSG_NFO_FILE_CREATED" || log_warning "$MSG_INFO_NO_MUSICBRAINZ_NFO_SKIPPED"
    fi
    
    # Sichere temp_pathname bevor check_disk_space es braucht
    local audio_temp_path="$temp_pathname"
    
    # Prüfe Speicherplatz (Overhead wird automatisch berechnet)
    local album_size_mb=$(du -sm "$album_dir" | awk '{print $1}')
    
    if ! check_disk_space "$album_size_mb"; then
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
