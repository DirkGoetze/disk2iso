#!/bin/bash
################################################################################
# disk2iso - DVD Library
# Filepath: disk2iso-lib/lib-dvd.sh
#
# Beschreibung:
#   Funktionen für DVD-Ripping und -Konvertierung
#   - copy_video_dvd() - Video-DVD mit dvdbackup + genisoimage (entschlüsselt)
#   - copy_video_dvd_ddrescue() - Video-DVD/BD mit ddrescue (verschlüsselt)
#
# Erstellt: 30.12.2025
################################################################################

# ============================================================================
# PATH CONSTANTS
# ============================================================================

readonly DVD_DIR="dvd"

# ============================================================================
# PATH GETTER
# ============================================================================

# Funktion: Ermittle Pfad für Video-DVDs
# Rückgabe: Vollständiger Pfad zu dvd/ oder Fallback zu data/
get_path_dvd() {
    if [[ "$VIDEO_DVD_SUPPORT" == true ]] && [[ -n "$DVD_DIR" ]]; then
        echo "${OUTPUT_DIR}/${DVD_DIR}"
    else
        # Fallback auf data/ wenn DVD-Modul nicht geladen
        echo "${OUTPUT_DIR}/data"
    fi
}

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

# Lade Sprachdatei für dieses Modul
load_module_language "dvd"

# Funktion: Prüfe Video-DVD/BD Abhängigkeiten
# Rückgabe: 0 = Mindestens eine Methode verfügbar, 1 = Keine Methode verfügbar
check_video_dvd_dependencies() {
    local available_methods=()
    local missing_methods=()
    
    # Methode 1: dvdbackup (Entschlüsselung)
    if command -v dvdbackup >/dev/null 2>&1 && command -v genisoimage >/dev/null 2>&1; then
        available_methods+=("dvdbackup (entschlüsselt)")
    else
        missing_methods+=("dvdbackup+genisoimage")
    fi
    
    # Methode 2: ddrescue (robust)
    if command -v ddrescue >/dev/null 2>&1; then
        available_methods+=("ddrescue (verschlüsselt, robust)")
    else
        missing_methods+=("ddrescue")
    fi
    
    # Methode 3: dd (immer verfügbar, bereits in lib-common geprüft)
    available_methods+=("dd (verschlüsselt, langsam)")
    
    # Logging
    if [[ ${#available_methods[@]} -gt 0 ]]; then
        log_message "Video-DVD/BD Support verfügbar mit: ${available_methods[*]}"
        
        if [[ ${#missing_methods[@]} -gt 0 ]]; then
            log_message "Erweiterte Methoden verfügbar nach Installation: ${missing_methods[*]}"
            log_message "Installation: apt-get install dvdbackup genisoimage gddrescue libdvdcss2"
        fi
        
        return 0
    else
        log_message "FEHLER: Keine Video-DVD/BD Methode verfügbar"
        return 1
    fi
}

# ============================================================================
# VIDEO DVD COPY - DVDBACKUP + GENISOIMAGE (Methode 1 - Schnellste)
# ============================================================================

# Funktion zum Kopieren von Video-DVDs mit Entschlüsselung
# Nutzt dvdbackup (mit libdvdcss) + genisoimage
# KEIN Fallback - Methode wird zu Beginn gewählt
copy_video_dvd() {
    log_message "Methode: dvdbackup (entschlüsselt)"
    
    # Erstelle temporäres Verzeichnis für DVD-Struktur
    local temp_dvd="${temp_pathname}/dvd_rip"
    mkdir -p "$temp_dvd"
    
    # Ermittle DVD-Größe für Fortschrittsanzeige
    local dvd_size_mb=0
    if command -v isoinfo >/dev/null 2>&1; then
        local volume_blocks
        volume_blocks=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null | grep "Volume size is:" | awk '{print $4}')
        if [[ -n "$volume_blocks" ]] && [[ "$volume_blocks" =~ ^[0-9]+$ ]]; then
            dvd_size_mb=$((volume_blocks * 2048 / 1024 / 1024))
            log_message "DVD-Größe: ${dvd_size_mb} MB"
        fi
    fi
    
    # Prüfe Speicherplatz (DVD-Größe + 5% Puffer)
    if [[ $dvd_size_mb -gt 0 ]]; then
        local required_mb=$((dvd_size_mb + dvd_size_mb * 5 / 100))
        if ! check_disk_space "$required_mb"; then
            rm -rf "$temp_dvd"
            return 1
        fi
    fi
    
    # Starte dvdbackup im Hintergrund mit Fortschrittsanzeige
    log_message "Extrahiere DVD-Struktur..."
    dvdbackup -M -i "$CD_DEVICE" -o "$temp_dvd" >>"$log_filename" 2>&1 &
    local dvdbackup_pid=$!
    
    # Überwache Fortschritt (alle 60 Sekunden)
    local start_time=$(date +%s)
    local last_log_time=$start_time
    
    while kill -0 "$dvdbackup_pid" 2>/dev/null; do
        sleep 5
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - last_log_time))
        
        # Log alle 60 Sekunden
        if [[ $elapsed -ge 60 ]]; then
            local copied_mb=0
            if [[ -d "$temp_dvd" ]]; then
                copied_mb=$(du -sm "$temp_dvd" 2>/dev/null | awk '{print $1}')
            fi
            
            local percent=0
            local eta="--:--:--"
            
            if [[ $dvd_size_mb -gt 0 ]] && [[ $copied_mb -gt 0 ]]; then
                percent=$((copied_mb * 100 / dvd_size_mb))
                if [[ $percent -gt 100 ]]; then percent=100; fi
                
                # Berechne geschätzte Restzeit
                local total_elapsed=$((current_time - start_time))
                if [[ $percent -gt 0 ]]; then
                    local estimated_total=$((total_elapsed * 100 / percent))
                    local remaining=$((estimated_total - total_elapsed))
                    local hours=$((remaining / 3600))
                    local minutes=$(((remaining % 3600) / 60))
                    local seconds=$((remaining % 60))
                    eta=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
                fi
            fi
            
            # Formatierte Ausgabe mit tatsächlichen Werten
            if [[ $dvd_size_mb -gt 0 ]]; then
                log_message "Fortschritt: ${copied_mb} MB von ${dvd_size_mb} MB (${percent}%) - verbleibend: ${eta}"
            else
                log_message "Fortschritt: ${copied_mb} MB kopiert - verbleibend: ${eta}"
            fi
            
            last_log_time=$current_time
        fi
    done
    
    # Warte auf dvdbackup Prozess-Ende
    wait "$dvdbackup_pid"
    local dvdbackup_exit=$?
    
    # Prüfe Ergebnis
    if [[ $dvdbackup_exit -ne 0 ]]; then
        log_message "FEHLER: dvdbackup fehlgeschlagen (Exit-Code: $dvdbackup_exit)"
        rm -rf "$temp_dvd"
        return 1
    fi
    
    log_message "✓ DVD-Struktur extrahiert (100%)"
    
    # Finde VIDEO_TS Ordner (dvdbackup erstellt Unterordner mit Titel)
    local video_ts_dir
    video_ts_dir=$(find "$temp_dvd" -type d -name "VIDEO_TS" | head -1)
    
    if [[ -z "$video_ts_dir" ]]; then
        log_message "FEHLER: Kein VIDEO_TS Ordner gefunden"
        rm -rf "$temp_dvd"
        return 1
    fi
    
    # Erstelle ISO aus VIDEO_TS Struktur
    log_message "Erstelle entschlüsselte ISO aus VIDEO_TS..."
    if genisoimage -dvd-video -V "$disc_label" -o "$iso_filename" "$(dirname "$video_ts_dir")" 2>>"$log_filename"; then
        log_message "✓ Entschlüsselte Video-DVD ISO erfolgreich erstellt"
        rm -rf "$temp_dvd"
        return 0
    else
        log_message "FEHLER: genisoimage fehlgeschlagen"
        rm -rf "$temp_dvd"
        return 1
    fi
}

# ============================================================================
# VIDEO DVD COPY - DDRESCUE (Methode 2 - Mittelschnell)
# ============================================================================

# Funktion zum Kopieren von Video-DVDs mit ddrescue
# Schneller als dd bei Lesefehlern, ISO bleibt verschlüsselt
# KEIN Fallback - Methode wird zu Beginn gewählt
copy_video_dvd_ddrescue() {
    log_message "Methode: ddrescue (verschlüsselt, robust)"
    
    # ddrescue benötigt Map-Datei
    local mapfile="${iso_filename}.mapfile"
    
    # Ermittle Disc-Größe mit isoinfo
    local volume_size=""
    local total_bytes=0
    
    if command -v isoinfo >/dev/null 2>&1; then
        volume_size=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null | grep "Volume size is:" | awk '{print $4}')
        if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
            total_bytes=$((volume_size * 2048))
            log_message "ISO-Volume erkannt: $volume_size Blöcke ($(( total_bytes / 1024 / 1024 )) MB)"
        fi
    fi
    
    # Prüfe Speicherplatz (ISO-Größe + 5% Puffer)
    if [[ $total_bytes -gt 0 ]]; then
        local size_mb=$((total_bytes / 1024 / 1024))
        local required_mb=$((size_mb + size_mb * 5 / 100))
        if ! check_disk_space "$required_mb"; then
            rm -f "$mapfile"
            return 1
        fi
    fi
    
    # Kopiere mit ddrescue
    if [[ $total_bytes -gt 0 ]]; then
        # Mit bekannter Größe
        if ddrescue -b 2048 -s "$total_bytes" -n "$CD_DEVICE" "$iso_filename" "$mapfile" 2>>"$log_filename"; then
            log_message "✓ Video-DVD mit ddrescue erfolgreich kopiert"
            rm -f "$mapfile"
            return 0
        else
            log_message "FEHLER: ddrescue fehlgeschlagen"
            rm -f "$mapfile"
            return 1
        fi
    else
        # Ohne bekannte Größe (kopiert bis Ende)
        if ddrescue -b 2048 -n "$CD_DEVICE" "$iso_filename" "$mapfile" 2>>"$log_filename"; then
            log_message "✓ Video-DVD mit ddrescue erfolgreich kopiert"
            rm -f "$mapfile"
            return 0
        else
            log_message "FEHLER: ddrescue fehlgeschlagen"
            rm -f "$mapfile"
            return 1
        fi
    fi
}
