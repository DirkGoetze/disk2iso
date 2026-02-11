#!/bin/bash
# ===========================================================================
# System Information Library
# ===========================================================================
# Filepath: lib/libsysteminfo.sh
#
# Beschreibung:
#   System-Informationen und Container-Erkennung
#   - Container-Erkennung (LXC, Docker, Podman)
#   - Speicherplatz-Prüfung (systeminfo_check_disk_space)
#   - Medium-Wechsel-Erkennung für Container-Umgebungen
#   - System-Monitoring und Ressourcen-Überwachung
#
# ---------------------------------------------------------------------------
# Dependencies: liblogging (für log_* Funktionen)
# ---------------------------------------------------------------------------
# Author: D.Götze
# Version: 1.3.0
# Last Change: 2026-02-07
# ===========================================================================

# ===========================================================================
# DEPENDENCY CHECK
# ===========================================================================

# ===========================================================================
# systeminfo_check_dependencies
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
systeminfo_check_dependencies() {
    # Manifest-basierte Abhängigkeitsprüfung (Tools, Dateien, Ordner)
    integrity_check_module_dependencies "systeminfo" || return 1
    
    # Modul-spezifische Initialisierung
    # Erkenne Container-Umgebung
    systeminfo_detect_container_env
    
    return 0
}

# ============================================================================
# CONTAINER DETECTION
# ============================================================================
# Private Variablen für Container-Erkennung (nur über Getter zugreifen)
_SYSTEMINFO_IS_CONTAINER=false
_SYSTEMINFO_CONTAINER_TYPE=""

# ===========================================================================
# systeminfo_detect_container_lxc
# ---------------------------------------------------------------------------
# Funktion.: Erkenne LXC-Container
# Parameter: keine
# Rückgabe.: 0 = LXC erkannt, 1 = nicht erkannt
# ===========================================================================
systeminfo_detect_container_lxc() {
    # Methode 1: Prüfe /proc/1/environ auf container=lxc
    if [[ -f /proc/1/environ ]]; then
        local env_content=$(tr '\0' '\n' < /proc/1/environ 2>/dev/null)
        if echo "$env_content" | grep -q "^container=lxc$"; then
            return 0
        fi
    fi
    
    # Methode 2: Prüfe /proc/1/cgroup auf LXC-Spuren
    if [[ -f /proc/1/cgroup ]]; then
        if grep -q ":/lxc/" /proc/1/cgroup 2>/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

# ===========================================================================
# systeminfo_detect_container_docker
# ---------------------------------------------------------------------------
# Funktion.: Erkenne Docker-Container
# Parameter: keine
# Rückgabe.: 0 = Docker erkannt, 1 = nicht erkannt
# ===========================================================================
systeminfo_detect_container_docker() {
    # Methode 1: Prüfe /proc/1/environ auf container=docker
    if [[ -f /proc/1/environ ]]; then
        local env_content=$(tr '\0' '\n' < /proc/1/environ 2>/dev/null)
        if echo "$env_content" | grep -q "^container=docker$"; then
            return 0
        fi
    fi
    
    # Methode 2: Prüfe auf Docker-spezifische Datei
    if [[ -f /.dockerenv ]]; then
        return 0
    fi
    
    # Methode 3: Prüfe /proc/1/cgroup auf Docker-Spuren
    if [[ -f /proc/1/cgroup ]]; then
        if grep -q ":/docker/" /proc/1/cgroup 2>/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

# ===========================================================================
# systeminfo_detect_container_podman
# ---------------------------------------------------------------------------
# Funktion.: Erkenne Podman-Container
# Parameter: keine
# Rückgabe.: 0 = Podman erkannt, 1 = nicht erkannt
# ===========================================================================
systeminfo_detect_container_podman() {
    # Methode 1: Prüfe /proc/1/environ auf container=podman
    if [[ -f /proc/1/environ ]]; then
        local env_content=$(tr '\0' '\n' < /proc/1/environ 2>/dev/null)
        if echo "$env_content" | grep -q "^container=podman$"; then
            return 0
        fi
    fi
    
    return 1
}

# ===========================================================================
# systeminfo_detect_container_env
# ---------------------------------------------------------------------------
# Funktion.: Erkenne Container-Umgebung (koordiniert alle Erkennungsmethoden)
# Parameter: keine
# Rückgabe.: 0 = immer (setzt _SYSTEMINFO_IS_CONTAINER und _SYSTEMINFO_CONTAINER_TYPE)
# Setzt....: _SYSTEMINFO_IS_CONTAINER (true/false), _SYSTEMINFO_CONTAINER_TYPE (lxc/docker/podman/"")
# ===========================================================================
systeminfo_detect_container_env() {
    _SYSTEMINFO_IS_CONTAINER=false
    _SYSTEMINFO_CONTAINER_TYPE=""
    
    # Prüfe LXC
    if systeminfo_detect_container_lxc; then
        _SYSTEMINFO_IS_CONTAINER=true
        _SYSTEMINFO_CONTAINER_TYPE="lxc"
        log_info "$MSG_CONTAINER_DETECTED LXC"
        return 0
    fi
    
    # Prüfe Docker
    if systeminfo_detect_container_docker; then
        _SYSTEMINFO_IS_CONTAINER=true
        _SYSTEMINFO_CONTAINER_TYPE="docker"
        log_info "$MSG_CONTAINER_DETECTED Docker"
        return 0
    fi
    
    # Prüfe Podman
    if systeminfo_detect_container_podman; then
        _SYSTEMINFO_IS_CONTAINER=true
        _SYSTEMINFO_CONTAINER_TYPE="podman"
        log_info "$MSG_CONTAINER_DETECTED Podman"
        return 0
    fi
    
    # Keine Container-Umgebung erkannt
    log_info "$MSG_NATIVE_ENVIRONMENT_DETECTED"
    return 0
}

# ===========================================================================
# systeminfo_is_container
# ---------------------------------------------------------------------------
# Funktion.: Gibt zurück, ob das System in einem Container läuft
# Parameter: keine
# Rückgabe.: 0 = Container, 1 = kein Container
# ===========================================================================
systeminfo_is_container() {
    [[ "$_SYSTEMINFO_IS_CONTAINER" == "true" ]]
    return $?
}

# ===========================================================================
# systeminfo_get_container_type
# ---------------------------------------------------------------------------
# Funktion.: Gibt den Container-Typ zurück
# Parameter: keine
# Rückgabe.: String: "lxc", "docker", "podman" oder "" (wenn kein Container)
# ===========================================================================
systeminfo_get_container_type() {
    echo "$_SYSTEMINFO_CONTAINER_TYPE"
}


# ============================================================================
# DISK SPACE CHECK
# ============================================================================

# ===========================================================================
# systeminfo_check_disk_space
# ---------------------------------------------------------------------------
# Funktion.: Prüfung des verfügbaren Speicherplatzes
# Parameter: $1 = required_mb (benötigte MB - INKL. Overhead!)
# Hinweis..: init_disc_info() berechnet bereits estimated_size_mb
# .........  mit 10% Overhead. Diese Funktion prüft nur noch ob
# .........  genug Platz vorhanden ist.
# Rückgabe.: 0 = Ausreichend Platz, 1 = Nicht genug Platz
# ===========================================================================
systeminfo_check_disk_space() {
    #-- Parameter einlesen --------------------------------------------------
    local required_mb=$1
    
    #-- Validierung der Parameter -------------------------------------------
    if [[ -z "$required_mb" ]] || [[ ! "$required_mb" =~ ^[0-9]+$ ]]; then
        log_warning "Ungültiger Parameter '$required_mb' - überspringe Prüfung"
        return 0
    fi
    
    #-- Ermittle Ausgabe-Verzeichnis ----------------------------------------
    local output_dir=$(folders_get_output_dir) || {
        log_error "Ausgabe-Verzeichnis nicht verfügbar"
        return 0  # Fahre fort, wenn Prüfung fehlschlägt
    }
    
    #-- Ermittle verfügbaren Speicherplatz am Ausgabepfad -------------------
    local available_mb=$(df -BM "$output_dir" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/M//')
    
    #-- Validierung der Ermittlung ------------------------------------------
    if [[ -z "$available_mb" ]] || [[ ! "$available_mb" =~ ^[0-9]+$ ]]; then
        log_error "$MSG_WARNING_DISK_SPACE_CHECK_FAILED"
        return 0  # Fahre fort, wenn Prüfung fehlschlägt
    fi
    
    #-- Detailliertes Logging -----------------------------------------------
    log_info "Speicherplatz: ${available_mb} MB verfügbar, ${required_mb} MB benötigt"
    
    if [[ $available_mb -lt $required_mb ]]; then
        log_error "$MSG_ERROR_INSUFFICIENT_DISK_SPACE ${required_mb} MB benötigt, nur ${available_mb} MB verfügbar"
        
        #-- API: Fehler melden ----------------------------------------------
        if declare -f api_update_status >/dev/null 2>&1; then
            api_update_status "error" "" "" "Nicht genug Speicherplatz: ${available_mb}/${required_mb} MB"
        fi
        
        return 1
    fi
    
    #-- Genug Speicherplatz vorhanden ---------------------------------------
    log_info "$MSG_DISK_SPACE_SUFFICIENT"
    return 0
}

# ============================================================================
# SYSTEM INFORMATION COLLECTION (JSON-BASED)
# ============================================================================
# Neue Architektur: Einzelne Collector-Funktionen schreiben in JSON-Dateien
# Widget-Getter lesen JSON und geben an Middleware weiter
# Vorteile: Trennung statisch/flüchtig, Multi-Consumer, Performance-Caching

# ===========================================================================
# COLLECTOR FUNCTIONS - Schreiben Daten in JSON-Dateien
# ===========================================================================

# ===========================================================================
# systeminfo_collect_os_info
# ---------------------------------------------------------------------------
# Funktion.: Sammle OS-Informationen und schreibe in os_info.json
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: STATISCH - einmal beim Start ausführen
# Schreibt.: api/os_info.json
# ===========================================================================
systeminfo_collect_os_info() {
    local os_name="Unknown"
    local os_version="Unknown"
    local kernel_version=$(uname -r 2>/dev/null || echo "Unknown")
    local architecture=$(uname -m 2>/dev/null || echo "Unknown")
    local hostname_value=$(hostname 2>/dev/null || echo "Unknown")
    
    # Distribution erkennen
    if [[ -f /etc/os-release ]]; then
        os_name=$(grep "^NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
        os_version=$(grep "^VERSION=" /etc/os-release | cut -d= -f2 | tr -d '"')
    elif [[ -f /etc/debian_version ]]; then
        os_name="Debian"
        os_version=$(cat /etc/debian_version)
    fi
    
    # Schreibe in JSON
    settings_set_value_json "os_info" ".distribution" "$os_name" || return 1
    settings_set_value_json "os_info" ".version" "$os_version" || return 1
    settings_set_value_json "os_info" ".kernel" "$kernel_version" || return 1
    settings_set_value_json "os_info" ".architecture" "$architecture" || return 1
    settings_set_value_json "os_info" ".hostname" "$hostname_value" || return 1
    
    return 0
}

# ===========================================================================
# systeminfo_collect_uptime_info
# ---------------------------------------------------------------------------
# Funktion.: Sammle Uptime-Information und aktualisiere os_info.json
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: FLÜCHTIG - zyklisch ausführen (z.B. alle 30s)
# Aktualisiert: api/os_info.json (nur .uptime Feld)
# ===========================================================================
systeminfo_collect_uptime_info() {
    local uptime_value=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "Unknown")
    settings_set_value_json "os_info" ".uptime" "$uptime_value"
}

# ===========================================================================
# systeminfo_collect_container_info
# ---------------------------------------------------------------------------
# Funktion.: Sammle Container-Informationen und schreibe in container_info.json
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: STATISCH - einmal beim Start ausführen
# Schreibt.: api/container_info.json
# ===========================================================================
systeminfo_collect_container_info() {
    local is_container="false"
    local container_type="none"
    
    if systeminfo_is_container; then
        is_container="true"
        container_type="$(systeminfo_get_container_type)"
    fi
    
    # Schreibe in JSON
    settings_set_value_json "container_info" ".is_container" "$is_container" || return 1
    settings_set_value_json "container_info" ".type" "$container_type" || return 1
    
    return 0
}

# ===========================================================================
# systeminfo_collect_storage_info
# ---------------------------------------------------------------------------
# Funktion.: Sammle Speicherplatz-Informationen und schreibe in storage_info.json
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: FLÜCHTIG - zyklisch ausführen (z.B. alle 30s)
# Schreibt.: api/storage_info.json
# ===========================================================================
systeminfo_collect_storage_info() {
    local output_dir=$(folders_get_output_dir) || {
        log_error "Ausgabe-Verzeichnis nicht verfügbar"
        return 1
    }
    
    local output_dir_space="0"
    local output_dir_total="0"
    local output_dir_used_percent="0"
    
    if [[ -d "$output_dir" ]]; then
        local df_output=$(df -BG "$output_dir" 2>/dev/null | tail -1)
        if [[ -n "$df_output" ]]; then
            output_dir_total=$(echo "$df_output" | awk '{print $2}' | sed 's/G//')
            output_dir_space=$(echo "$df_output" | awk '{print $4}' | sed 's/G//')
            output_dir_used_percent=$(echo "$df_output" | awk '{print $5}' | sed 's/%//')
        fi
    fi
    
    # Schreibe in JSON (nur Speicherplatz-Metriken, nicht das Verzeichnis selbst)
    settings_set_value_json "storage_info" ".total_gb" "$output_dir_total" || return 1
    settings_set_value_json "storage_info" ".free_gb" "$output_dir_space" || return 1
    settings_set_value_json "storage_info" ".used_percent" "$output_dir_used_percent" || return 1
    
    return 0
}

# ===========================================================================
# systeminfo_collect_hardware_info (DEPRECATED - Wrapper)
# ---------------------------------------------------------------------------
# Funktion.: DEPRECATED - Wrapper für drivestat_collect_drive_info()
# .........  TODO: Entfernen in zukünftigen Versionen
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: Ruft drivestat_collect_drive_info() auf für Kompatibilität
# Migration: Verwende drivestat_collect_drive_info() direkt
# ===========================================================================
systeminfo_collect_hardware_info() {
    log_warning "systeminfo_collect_hardware_info() ist DEPRECATED"
    log_info "Nutze stattdessen: drivestat_collect_drive_info()"
    
    # Rufe neue Funktion aus libdrivestat.sh auf
    if declare -f drivestat_collect_drive_info >/dev/null 2>&1; then
        drivestat_collect_drive_info
        return $?
    else
        log_error "drivestat_collect_drive_info() nicht verfügbar - libdrivestat.sh geladen?"
        return 1
    fi
}

# ===========================================================================
# systeminfo_collect_software_info
# ---------------------------------------------------------------------------
# Funktion.: Sammle Software-Versionen und schreibe in software_info.json
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: STATISCH - einmal beim Start ausführen
# Schreibt.: api/software_info.json
# ===========================================================================
systeminfo_collect_software_info() {
    local cdparanoia_version="Not installed"
    local lame_version="Not installed"
    local dvdbackup_version="Not installed"
    local ddrescue_version="Not installed"
    local genisoimage_version="Not installed"
    local python_version="Not installed"
    local flask_version="Not installed"
    local mosquitto_version="Not installed"
    
    # Erkenne Versionen
    if command -v cdparanoia >/dev/null 2>&1; then
        cdparanoia_version=$(cdparanoia --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
    fi
    
    if command -v lame >/dev/null 2>&1; then
        lame_version=$(lame --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
    fi
    
    if command -v dvdbackup >/dev/null 2>&1; then
        dvdbackup_version=$(dvdbackup --version 2>&1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
    fi
    
    if command -v ddrescue >/dev/null 2>&1; then
        ddrescue_version=$(ddrescue --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
    fi
    
    if command -v genisoimage >/dev/null 2>&1; then
        genisoimage_version=$(genisoimage --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
    fi
    
    if command -v python3 >/dev/null 2>&1; then
        python_version=$(python3 --version 2>&1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
    fi

    if python3 -c "import flask" 2>/dev/null; then
        flask_version=$(python3 -c "import importlib.metadata; print(importlib.metadata.version('flask'))" 2>/dev/null || echo "installed")
    elif [[ -f "/opt/disk2iso/venv/bin/python3" ]]; then
        if /opt/disk2iso/venv/bin/python3 -c "import flask" 2>/dev/null; then
            flask_version=$(/opt/disk2iso/venv/bin/python3 -c "import importlib.metadata; print(importlib.metadata.version('flask'))" 2>/dev/null || echo "installed")
        fi
    fi

    if command -v mosquitto >/dev/null 2>&1; then
        mosquitto_version=$(mosquitto -h 2>&1 | grep -oP 'version \K\d+\.\d+(\.\d+)?' || echo "installed")
    fi
    
    # Schreibe in JSON
    settings_set_value_json "software_info" ".cdparanoia" "$cdparanoia_version" || return 1
    settings_set_value_json "software_info" ".lame" "$lame_version" || return 1
    settings_set_value_json "software_info" ".dvdbackup" "$dvdbackup_version" || return 1
    settings_set_value_json "software_info" ".ddrescue" "$ddrescue_version" || return 1
    settings_set_value_json "software_info" ".genisoimage" "$genisoimage_version" || return 1
    settings_set_value_json "software_info" ".python" "$python_version" || return 1
    settings_set_value_json "software_info" ".flask" "$flask_version" || return 1
    settings_set_value_json "software_info" ".mosquitto" "$mosquitto_version" || return 1
    
    return 0
}

# ============================================================================
# SOFTWARE VERSION DETECTION (Zentrale Hilfsfunktionen)
# ============================================================================

# ===========================================================================
# systeminfo_get_software_version
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Version einer installierten Software
# Parameter: $1 = Software-Name (z.B. "cdparanoia", "lame", "python3")
# Rückgabe.: 0 = gefunden, 1 = nicht gefunden
# Ausgabe..: Version-String oder "Not installed"
# Hinweis..: Zentrale Erkennungslogik für alle Module
# ===========================================================================
systeminfo_get_software_version() {
    local software_name="$1"
    local version="Not installed"
    
    # Prüfe ob Command existiert
    if ! command -v "$software_name" >/dev/null 2>&1; then
        # Spezialfall: Python-Module prüfen
        if [[ "$software_name" == "flask" ]] || [[ "$software_name" == "musicbrainzngs" ]] || [[ "$software_name" == "requests" ]]; then
            # Versuche mit System-Python
            if python3 -c "import ${software_name}" 2>/dev/null; then
                version=$(python3 -c "import importlib.metadata; print(importlib.metadata.version('${software_name}'))" 2>/dev/null || echo "installed")
            # Versuche mit venv-Python
            elif [[ -f "/opt/disk2iso/venv/bin/python3" ]]; then
                if /opt/disk2iso/venv/bin/python3 -c "import ${software_name}" 2>/dev/null; then
                    version=$(/opt/disk2iso/venv/bin/python3 -c "import importlib.metadata; print(importlib.metadata.version('${software_name}'))" 2>/dev/null || echo "installed")
                fi
            fi
        fi
        
        echo "$version"
        [[ "$version" != "Not installed" ]] && return 0 || return 1
    fi
    
    # Software-spezifische Version-Erkennung
    case "$software_name" in
        cdparanoia)
            version=$(cdparanoia --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
            ;;
        lame)
            version=$(lame --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
            ;;
        dvdbackup)
            version=$(dvdbackup --version 2>&1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
            ;;
        ddrescue)
            version=$(ddrescue --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
            ;;
        genisoimage)
            version=$(genisoimage --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
            ;;
        python3|python)
            version=$(python3 --version 2>&1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
            ;;
        mosquitto)
            version=$(mosquitto -h 2>&1 | grep -oP 'version \K\d+\.\d+(\.\d+)?' || echo "installed")
            ;;
        makemkvcon)
            version=$(makemkvcon --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
            ;;
        flac)
            version=$(flac --version 2>&1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
            ;;
        oggenc)
            version=$(oggenc --version 2>&1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
            ;;
        *)
            # Generischer Fallback: Versuche --version
            if "$software_name" --version >/dev/null 2>&1; then
                version=$("$software_name" --version 2>&1 | head -1 | grep -oP '\d+\.\d+(\.\d+)?' || echo "installed")
            else
                version="installed"
            fi
            ;;
    esac
    
    echo "$version"
    return 0
}

# ===========================================================================
# systeminfo_get_available_version
# ---------------------------------------------------------------------------
# Funktion.: Ermittle verfügbare Version einer Software (apt-cache)
# Parameter: $1 = Software-Name
# Rückgabe.: 0 = Erfolg
# Ausgabe..: Version-String oder "Unknown"
# ===========================================================================
systeminfo_get_available_version() {
    local software_name="$1"
    local available_version="Unknown"
    
    # Prüfe ob apt-cache verfügbar ist
    if command -v apt-cache >/dev/null 2>&1; then
        # Hole Candidate-Version (nächste installierbare Version)
        available_version=$(apt-cache policy "$software_name" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
        
        # Fallback: Prüfe ob überhaupt ein Paket existiert
        if [[ -z "$available_version" ]] || [[ "$available_version" == "(none)" ]]; then
            available_version="Unknown"
        fi
    fi
    
    echo "$available_version"
    return 0
}

# ===========================================================================
# systeminfo_check_software_list
# ---------------------------------------------------------------------------
# Funktion.: Zentrale Software-Versions-Prüfung mit Update-Check
# Parameter: $@ = Liste von Software-Namen (z.B. "cdparanoia lame ddrescue")
# Rückgabe.: 0 = Erfolg
# Ausgabe..: JSON-Array mit Software-Informationen (stdout)
# Format...: [{"name":"cdparanoia","installed":"10.2","available":"10.2",
#             "status":"current","update_available":false}]
# Nutzung..: Wird von Modulen aufgerufen für ihre Dependencies
# ===========================================================================
systeminfo_check_software_list() {
    local software_list=("$@")
    local json_array="["
    local first=true
    
    for software_name in "${software_list[@]}"; do
        # Komma zwischen Einträgen
        if [[ "$first" == "false" ]]; then
            json_array+=","
        fi
        first=false
        
        # 1. Installierte Version ermitteln
        local installed_version=$(systeminfo_get_software_version "$software_name")
        
        # 2. Verfügbare Version ermitteln (nur wenn installiert oder apt verfügbar)
        local available_version="Unknown"
        if [[ "$installed_version" != "Not installed" ]] || command -v apt-cache >/dev/null 2>&1; then
            available_version=$(systeminfo_get_available_version "$software_name")
        fi
        
        # 3. Status bestimmen
        local status="unknown"
        local update_available="false"
        
        if [[ "$installed_version" == "Not installed" ]]; then
            status="missing"
            update_available="false"
        elif [[ "$available_version" == "Unknown" ]]; then
            # Keine Info über verfügbare Version → Status "installed" (konservativ)
            status="installed"
            update_available="false"
        elif [[ "$installed_version" == "$available_version" ]] || [[ "$installed_version" == "installed" ]]; then
            # Versionen gleich oder keine genaue Version → Status "current"
            status="current"
            update_available="false"
        else
            # Versionen unterschiedlich → Update verfügbar
            status="outdated"
            update_available="true"
        fi
        
        # 4. JSON-Objekt bauen (escaping für JSON)
        json_array+="{\"name\":\"${software_name}\","
        json_array+="\"installed_version\":\"${installed_version}\","
        json_array+="\"available_version\":\"${available_version}\","
        json_array+="\"status\":\"${status}\","
        json_array+="\"update_available\":${update_available}}"
    done
    
    json_array+="]"
    echo "$json_array"
    return 0
}

# ===========================================================================
# systeminfo_install_software
# ---------------------------------------------------------------------------
# Funktion.: Installiere oder aktualisiere Software (für Widget-Buttons)
# Parameter: $1 = Software-Name
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Hinweis..: Benötigt sudo-Rechte, nutzt apt-get
# TODO.....: Für zukünftige Widget-Integration (Install/Update-Buttons)
# ===========================================================================
systeminfo_install_software() {
    local software_name="$1"
    
    # Validierung
    if [[ -z "$software_name" ]]; then
        log_error "Kein Software-Name angegeben"
        return 1
    fi
    
    # Prüfe ob apt-get verfügbar
    if ! command -v apt-get >/dev/null 2>&1; then
        log_error "apt-get nicht verfügbar - Installation nicht möglich"
        return 1
    fi
    
    log_info "Installiere/Aktualisiere Software: $software_name"
    
    # Installation/Update (non-interactive)
    if apt-get install -y "$software_name" 2>&1 | logger -t "disk2iso-software-install"; then
        log_info "Software $software_name erfolgreich installiert/aktualisiert"
        
        # Aktualisiere Software-Info nach Installation
        if declare -f "$(echo $software_name | cut -d- -f1)_collect_software_info" >/dev/null 2>&1; then
            "$(echo $software_name | cut -d- -f1)_collect_software_info" 2>/dev/null || true
        fi
        
        return 0
    else
        log_error "Fehler bei Installation von $software_name"
        return 1
    fi
}

# ===========================================================================
# WIDGET GETTER FUNCTIONS - Lesen JSON und geben an Middleware
# ===========================================================================

# ===========================================================================
# systeminfo_get_os_info
# ---------------------------------------------------------------------------
# Funktion.: Lese OS-Informationen aus JSON für Widget
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Ausgabe..: JSON-String (stdout)
# Für.....: widget_2x1_sysinfo
# ===========================================================================
systeminfo_get_os_info() {
    local api_dir=$(folders_get_api_dir) || return 1
    local json_file="${api_dir}/os_info.json"
    
    if [[ ! -f "$json_file" ]]; then
        # Fallback: Sammle Daten wenn JSON nicht existiert
        systeminfo_collect_os_info || return 1
        systeminfo_collect_uptime_info || return 1
    fi
    
    cat "$json_file"
}

# ===========================================================================
# systeminfo_get_storage_info
# ---------------------------------------------------------------------------
# Funktion.: Lese Speicher-Informationen aus JSON für Widget
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Ausgabe..: JSON-String (stdout)
# Für.....: widget_2x1_outputdir
# ===========================================================================
systeminfo_get_storage_info() {
    local api_dir=$(folders_get_api_dir) || return 1
    local json_file="${api_dir}/storage_info.json"
    
    if [[ ! -f "$json_file" ]]; then
        # Fallback: Sammle Daten wenn JSON nicht existiert
        systeminfo_collect_storage_info || return 1
    fi
    
    cat "$json_file"
}

# ===========================================================================
# systeminfo_get_archiv_info
# ---------------------------------------------------------------------------
# Funktion.: Lese Archiv-Informationen aus JSON für Widget
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Ausgabe..: JSON-String (stdout) - kombiniert Drive + Storage
# Für.....: widget_2x1_archiv
# ===========================================================================
systeminfo_get_archiv_info() {
    local api_dir=$(folders_get_api_dir) || return 1
    
    # Prüfe ob JSONs existieren
    if [[ ! -f "${api_dir}/drive_info.json" ]]; then
        # Rufe drivestat_collect_drive_info() auf wenn verfügbar
        if declare -f drivestat_collect_drive_info >/dev/null 2>&1; then
            drivestat_collect_drive_info || return 1
        else
            log_warning "drivestat_collect_drive_info() nicht verfügbar"
        fi
    fi
    
    if [[ ! -f "${api_dir}/storage_info.json" ]]; then
        systeminfo_collect_storage_info || return 1
    fi
    
    # Kombiniere Drive + Storage (manuell, um jq-Abhängigkeit zu vermeiden)
    local drive=$(cat "${api_dir}/drive_info.json" 2>/dev/null || echo '{}')
    local storage=$(cat "${api_dir}/storage_info.json")
    
    # Einfaches JSON-Merge (rudimentär, aber funktional)
    echo "{\"drive\":${drive},\"storage\":${storage}}"
}

# ===========================================================================
# systeminfo_get_software_info
# ---------------------------------------------------------------------------
# Funktion.: Lese Software-Informationen aus JSON für Widget
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Ausgabe..: JSON-String (stdout)
# Für.....: widget_4x1_dependencies
# ===========================================================================
systeminfo_get_software_info() {
    local api_dir=$(folders_get_api_dir) || return 1
    local json_file="${api_dir}/software_info.json"
    
    if [[ ! -f "$json_file" ]]; then
        # Fallback: Sammle Daten wenn JSON nicht existiert
        systeminfo_collect_software_info || return 1
    fi
    
    cat "$json_file"
}

# ============================================================================
# DEPRECATED FUNCTIONS
# ============================================================================

# ===========================================================================
# collect_system_information (DEPRECATED)
# ---------------------------------------------------------------------------
# Funktion.: DEPRECATED - Verwende stattdessen die neuen Collector-Funktionen
# Hinweis..: Diese Funktion wird in Zukunft entfernt
# Migration: systeminfo_collect_os_info()
#            systeminfo_collect_container_info()
#            systeminfo_collect_storage_info()
#            systeminfo_collect_hardware_info()
#            systeminfo_collect_software_info()
# ===========================================================================
collect_system_information() {
    log_warning "collect_system_information() ist DEPRECATED und wird bald entfernt"
    log_info "Nutze stattdessen: systeminfo_collect_*() Funktionen"
    
    # Rufe neue Collector-Funktionen auf (Kompatibilitätsmodus)
    systeminfo_collect_os_info
    systeminfo_collect_uptime_info
    systeminfo_collect_container_info
    systeminfo_collect_storage_info
    systeminfo_collect_software_info
    
    # Drive-Info via drivestat (wenn verfügbar)
    if declare -f drivestat_collect_drive_info >/dev/null 2>&1; then
        drivestat_collect_drive_info
    fi
    
    return 0
}
