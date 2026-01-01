#!/bin/bash
################################################################################
# disk2iso - Blu-ray Library
# Filepath: disk2iso-lib/lib-bluray.sh
#
# Beschreibung:
#   Funktionen für Blu-ray-Ripping und -Konvertierung
#   - copy_bluray_makemkv() - Blu-ray mit MakeMKV (entschlüsselt)
#   - copy_bluray_ddrescue() - Blu-ray mit ddrescue (verschlüsselt, robust)
#
# Erstellt: 30.12.2025
################################################################################

# ============================================================================
# PATH CONSTANTS
# ============================================================================

readonly BD_DIR="bd"

# ============================================================================
# PATH GETTER
# ============================================================================

# Funktion: Ermittle Pfad für Blu-ray Videos
# Rückgabe: Vollständiger Pfad zu bd/ oder Fallback zu data/
get_path_bd() {
    if [[ "$BLURAY_SUPPORT" == true ]] && [[ -n "$BD_DIR" ]]; then
        echo "${OUTPUT_DIR}/${BD_DIR}"
    else
        # Fallback auf data/ wenn Blu-ray-Modul nicht geladen
        echo "${OUTPUT_DIR}/data"
    fi
}

# ============================================================================
# DEPENDENCY CHECK
# ============================================================================

# Lade Sprachdatei für dieses Modul
load_module_language "bluray"

# Funktion: Prüfe Blu-ray Abhängigkeiten
# Rückgabe: 0 = Mindestens eine Methode verfügbar, 1 = Keine Methode verfügbar
check_bluray_dependencies() {
    local available_methods=()
    local missing_methods=()
    
    # Methode 1: MakeMKV (Entschlüsselung)
    if command -v makemkvcon >/dev/null 2>&1; then
        available_methods+=("MakeMKV (entschlüsselt, Backup-Modus)")
    else
        missing_methods+=("makemkvcon")
    fi
    
    # Methode 2: genisoimage (für ISO-Erstellung aus MakeMKV Backup)
    if ! command -v genisoimage >/dev/null 2>&1; then
        log_message "WARNUNG: genisoimage fehlt - MakeMKV Backup kann nicht zu ISO konvertiert werden"
    fi
    
    # Methode 3: ddrescue (robust)
    if command -v ddrescue >/dev/null 2>&1; then
        available_methods+=("ddrescue (verschlüsselt, robust)")
    else
        missing_methods+=("ddrescue")
    fi
    
    # Methode 4: dd (immer verfügbar, bereits in lib-common geprüft)
    available_methods+=("dd (verschlüsselt, langsam)")
    
    # Logging
    if [[ ${#available_methods[@]} -gt 0 ]]; then
        log_message "Blu-ray Support verfügbar mit: ${available_methods[*]}"
        
        if [[ ${#missing_methods[@]} -gt 0 ]]; then
            log_message "Erweiterte Methoden verfügbar nach Installation: ${missing_methods[*]}"
            log_message "MakeMKV Download: https://www.makemkv.com/download/"
            log_message "ddrescue: apt-get install gddrescue"
            log_message "genisoimage: apt-get install genisoimage"
        fi
        
        return 0
    else
        log_message "FEHLER: Keine Blu-ray Methode verfügbar"
        return 1
    fi
}

# ============================================================================
# MAKEMKV HELPER FUNCTIONS
# ============================================================================

# Funktion: Prüfe MakeMKV Installation und Lizenz-Status
# Rückgabe: 0 = OK, 1 = Fehler/abgelaufen
check_makemkv_status() {
    # Prüfe ob makemkvcon verfügbar ist
    if ! command -v makemkvcon >/dev/null 2>&1; then
        return 1
    fi
    
    # Teste mit einfachem Befehl ob Lizenz gültig ist
    local test_output
    test_output=$(makemkvcon -r --robot info dev:/dev/sr0 2>&1)
    
    # Prüfe auf Lizenz-Fehler
    if echo "$test_output" | grep -qi "evaluation period.*expired\|registration.*required\|invalid.*key"; then
        return 2  # Beta abgelaufen
    fi
    
    return 0  # Alles OK
}

# Funktion: Zeige Benachrichtigung für MakeMKV Beta-Key Update
notify_makemkv_beta_expired() {
    local beta_key_url="https://forum.makemkv.com/forum/viewtopic.php?f=5&t=1053"
    local purchase_url="https://www.makemkv.com/buy/"
    
    log_message "WARNUNG: MakeMKV Beta-Key abgelaufen oder ungültig"
    log_message "Option 1: Beta-Key aktualisieren - $beta_key_url"
    log_message "Option 2: Vollversion erwerben (\$60 USD) - $purchase_url"
    
    # Desktop-Benachrichtigung (falls verfügbar)
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "disk2iso - MakeMKV Beta abgelaufen" \
            "Testphase verlängern: Neuen Beta-Key holen\nVollversion: \$60 USD einmalig" \
            -u critical -t 30000 2>/dev/null &
    fi
    
    # Interaktiver Dialog (falls zenity verfügbar)
    if command -v zenity >/dev/null 2>&1 && [[ -n "$DISPLAY" ]]; then
        zenity --question \
            --title="disk2iso - MakeMKV Lizenz" \
            --text="MakeMKV Beta-Key ist abgelaufen.\n\nWas möchten Sie tun?" \
            --ok-label="Beta verlängern (kostenlos)" \
            --cancel-label="Vollversion kaufen (\$60)" \
            --width=400 2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            # Beta-Key holen
            xdg-open "$beta_key_url" 2>/dev/null &
            log_message "Browser geöffnet: $beta_key_url"
        else
            # Vollversion kaufen
            xdg-open "$purchase_url" 2>/dev/null &
            log_message "Browser geöffnet: $purchase_url"
        fi
    fi
}

# ============================================================================
# BLURAY COPY - MAKEMKV (Methode 1 - Entschlüsselt)
# ============================================================================

# Funktion zum Kopieren von Blu-rays mit MakeMKV
# Nutzt MakeMKV Backup-Modus + genisoimage für ISO-Erstellung
# KEIN Fallback - Methode wird zu Beginn gewählt
copy_bluray_makemkv() {
    log_message "$MSG_METHOD_MAKEMKV"
    
    # Prüfe MakeMKV-Status
    local makemkv_status
    check_makemkv_status
    makemkv_status=$?
    
    if [[ $makemkv_status -eq 1 ]]; then
        log_message "FEHLER: MakeMKV ist nicht installiert"
        return 1
    elif [[ $makemkv_status -eq 2 ]]; then
        notify_makemkv_beta_expired
        log_message "FEHLER: MakeMKV Lizenz abgelaufen - Blu-ray-Backup nicht möglich"
        return 1
    fi
    
    # Erstelle temporäres Verzeichnis für BD-Struktur
    local temp_bd="${temp_pathname}/bluray_backup"
    mkdir -p "$temp_bd"
    
    # Analysiere Blu-ray-Struktur
    log_message "$MSG_ANALYZE_BLURAY"
    
    # Ermittle Disc-Info (Titel-Anzahl, Größe)
    local info_output
    info_output=$(makemkvcon -r info "disc:0" 2>/dev/null)
    
    if [[ -z "$info_output" ]]; then
        log_message "$MSG_ERROR_MAKEMKV_NO_DISC"
        rm -rf "$temp_bd"
        return 1
    fi
    
    # Extrahiere Titel-Anzahl
    local title_count
    title_count=$(echo "$info_output" | grep "^TCOUNT:" | cut -d: -f2)
    
    if [[ -z "$title_count" ]] || [[ $title_count -eq 0 ]]; then
        log_message "$MSG_ERROR_NO_BLURAY_TITLES"
        rm -rf "$temp_bd"
        return 1
    fi
    
    log_message "$MSG_BLURAY_TITLES_FOUND: $title_count"
    
    # Extrahiere Disc-Name falls verfügbar
    local disc_name
    disc_name=$(echo "$info_output" | grep "^CINFO:2," | cut -d, -f3 | tr -d '"')
    if [[ -n "$disc_name" ]]; then
        log_message "$MSG_DISC_NAME: $disc_name"
    fi
    
    # Ermittle Gesamtgröße (optional, für Fortschritt)
    local total_size_mb=0
    local size_line
    size_line=$(echo "$info_output" | grep "^CINFO:32," | cut -d, -f3 | tr -d '"')
    if [[ -n "$size_line" ]]; then
        # Konvertiere Bytes zu MB (falls verfügbar)
        total_size_mb=$((size_line / 1024 / 1024))
        log_message "$MSG_BLURAY_SIZE: ${total_size_mb} $MSG_PROGRESS_MB"
    fi
    
    # Prüfe Speicherplatz (BD-Größe + 10% Puffer)
    if [[ $total_size_mb -gt 0 ]]; then
        local required_mb=$((total_size_mb + total_size_mb * 10 / 100))
        if ! check_disk_space "$required_mb"; then
            rm -rf "$temp_bd"
            return 1
        fi
    fi
    
    # Starte MakeMKV Backup im Hintergrund
    log_message "$MSG_START_MAKEMKV_BACKUP"
    log_message "$MSG_MAKEMKV_DURATION"
    
    # MakeMKV Backup-Modus: --decrypt sichert entschlüsselte BDMV-Struktur
    makemkvcon backup --decrypt --noscan -r --progress=-same "disc:0" "$temp_bd" >>"$log_filename" 2>&1 &
    local makemkv_pid=$!
    
    # Überwache Fortschritt (alle 60 Sekunden)
    local start_time=$(date +%s)
    local last_log_time=$start_time
    
    while kill -0 "$makemkv_pid" 2>/dev/null; do
        sleep 10
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - last_log_time))
        
        # Log alle 60 Sekunden
        if [[ $elapsed -ge 60 ]]; then
            local copied_mb=0
            if [[ -d "$temp_bd" ]]; then
                copied_mb=$(du -sm "$temp_bd" 2>/dev/null | awk '{print $1}')
            fi
            
            local percent=0
            local eta="--:--:--"
            
            if [[ $total_size_mb -gt 0 ]] && [[ $copied_mb -gt 0 ]]; then
                percent=$((copied_mb * 100 / total_size_mb))
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
            
            # Formatierte Ausgabe
            if [[ $total_size_mb -gt 0 ]]; then
                log_message "$MSG_MAKEMKV_PROGRESS: ${copied_mb} $MSG_PROGRESS_MB / ${total_size_mb} $MSG_PROGRESS_MB (${percent}%) - $MSG_REMAINING: ${eta}"
            else
                log_message "$MSG_MAKEMKV_PROGRESS: ${copied_mb} $MSG_PROGRESS_MB $MSG_COPIED"
            fi
            
            last_log_time=$current_time
        fi
    done
    
    # Warte auf MakeMKV Prozess-Ende
    wait "$makemkv_pid"
    local makemkv_exit=$?
    
    # Prüfe Ergebnis
    if [[ $makemkv_exit -ne 0 ]]; then
        log_message "$MSG_ERROR_MAKEMKV_FAILED (Exit-Code: $makemkv_exit)"
        rm -rf "$temp_bd"
        return 1
    fi
    
    log_message "$MSG_MAKEMKV_SUCCESS"
    
    # Prüfe ob BDMV Ordner existiert
    local bdmv_dir
    bdmv_dir=$(find "$temp_bd" -type d -name "BDMV" | head -1)
    
    if [[ -z "$bdmv_dir" ]]; then
        log_message "$MSG_ERROR_NO_BDMV"
        rm -rf "$temp_bd"
        return 1
    fi
    
    log_message "$MSG_BDMV_FOUND: $bdmv_dir"
    
    # Erstelle ISO aus entschlüsselter BDMV-Struktur
    log_message "$MSG_CREATE_DECRYPTED_ISO_BDMV"
    
    # UDF Dateisystem für Blu-ray Kompatibilität
    if genisoimage -udf -allow-limited-size -V "$disc_label" -o "$iso_filename" "$(dirname "$bdmv_dir")" 2>>"$log_filename"; then
        log_message "$MSG_DECRYPTED_BLURAY_SUCCESS"
        rm -rf "$temp_bd"
        return 0
    else
        log_message "$MSG_ERROR_GENISOIMAGE_FAILED"
        rm -rf "$temp_bd"
        return 1
    fi
}

# ============================================================================
# BLURAY COPY - DDRESCUE (Methode 2 - Verschlüsselt, Robust)
# ============================================================================

# Funktion zum Kopieren von Blu-rays mit ddrescue
# Schneller als dd bei Lesefehlern, ISO bleibt verschlüsselt
# KEIN Fallback - Methode wird zu Beginn gewählt
copy_bluray_ddrescue() {
    log_message "$MSG_METHOD_DDRESCUE_ENCRYPTED"
    
    # ddrescue benötigt Map-Datei
    local mapfile="${iso_filename}.mapfile"
    
    # Ermittle Disc-Größe mit isoinfo (falls verfügbar)
    local volume_size=""
    local total_bytes=0
    
    if command -v isoinfo >/dev/null 2>&1; then
        volume_size=$(isoinfo -d -i "$CD_DEVICE" 2>/dev/null | grep "Volume size is:" | awk '{print $4}')
        if [[ -n "$volume_size" ]] && [[ "$volume_size" =~ ^[0-9]+$ ]]; then
            total_bytes=$((volume_size * 2048))
            log_message "$MSG_ISO_VOLUME_DETECTED $volume_size $MSG_ISO_BLOCKS ($(( total_bytes / 1024 / 1024 )) $MSG_PROGRESS_MB)"
        fi
    fi
    
    # Fallback: Bei UDF-Blu-rays liefert isoinfo keine Größe - verwende blockdev
    if [[ $total_bytes -eq 0 ]]; then
        local blockdev_cmd=""
        if command -v blockdev >/dev/null 2>&1; then
            blockdev_cmd="blockdev"
        elif [[ -x /usr/sbin/blockdev ]]; then
            blockdev_cmd="/usr/sbin/blockdev"
        fi
        
        if [[ -n "$blockdev_cmd" ]] && [[ -b "$CD_DEVICE" ]]; then
            local device_size=$($blockdev_cmd --getsize64 "$CD_DEVICE" 2>/dev/null)
            if [[ -n "$device_size" ]] && [[ "$device_size" =~ ^[0-9]+$ ]]; then
                total_bytes=$device_size
                volume_size=$((device_size / 2048))
                log_message "Disc-Größe ermittelt: $(( total_bytes / 1024 / 1024 )) MB (via blockdev)"
            fi
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
    log_message "$MSG_START_DDRESCUE_BLURAY"
    
    # ddrescue Parameter:
    # -b 2048: Blockgröße für optische Medien
    # -r 1: Max 1 Retry bei Lesefehlern (verhindert wildes Hin-und-Her-Springen)
    # -s: Größe begrenzen (falls bekannt)
    
    # Verhindere konkurrierende Zugriffe durch udisks/automount während ddrescue läuft
    # Öffne das Device mit flock (exklusives Lock) falls verfügbar
    local use_flock=false
    if command -v flock >/dev/null 2>&1; then
        use_flock=true
    fi
    
    # Starte ddrescue im Hintergrund (mit oder ohne flock)
    if $use_flock; then
        if [[ $total_bytes -gt 0 ]]; then
            flock -x "$CD_DEVICE" ddrescue -b 2048 -r 1 -s "$total_bytes" "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$log_filename" &
        else
            flock -x "$CD_DEVICE" ddrescue -b 2048 -r 1 "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$log_filename" &
        fi
    else
        if [[ $total_bytes -gt 0 ]]; then
            ddrescue -b 2048 -r 1 -s "$total_bytes" "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$log_filename" &
        else
            ddrescue -b 2048 -r 1 "$CD_DEVICE" "$iso_filename" "$mapfile" &>>"$log_filename" &
        fi
    fi
    local ddrescue_pid=$!
    
    # Warte auf ddrescue Prozess-Ende (blockiert bis ddrescue fertig ist)
    # WICHTIG: Kein is_disc_inserted() Check während ddrescue läuft!
    wait "$ddrescue_pid"
    local ddrescue_exit=$?
    
    # Prüfe Ergebnis
    if [[ $ddrescue_exit -eq 0 ]]; then
        log_message "$MSG_BLURAY_DDRESCUE_SUCCESS"
        rm -f "$mapfile"
        return 0
    else
        log_message "$MSG_ERROR_DDRESCUE_FAILED"
        rm -f "$mapfile"
        return 1
    fi
}
