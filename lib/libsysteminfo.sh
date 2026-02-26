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
    systeminfo_reset || return 1
    systeminfo_analyse || return 1
    systeminfo_reset_tool_cache || return 1
    
    return 0
}

# ===========================================================================
# GLOBAL VARIABLEN DES MODUL
# ===========================================================================
# ---------------------------------------------------------------------------
# Datenstruktur für System-Informationen
# ---------------------------------------------------------------------------
# SYSTEM_INFO: Systeminformationen
declare -A SYSTEM_INFO=(
    # ========== Betriebssystem ==========
    [os_distribution]=""        # z.B. "Debian", "Ubuntu"
    [os_version]=""             # z.B. "12.5", "22.04 LTS"
    [os_kernel]=""              # z.B. "6.1.0-18-amd64"
    [os_architecture]=""        # z.B. "x86_64", "aarch64"
    [os_hostname]=""            # z.B. "disk2iso-server"
    [os_uptime]=""              # z.B. "5 days, 3 hours"
    
    # ========== Container ==========
    [container_activ]=false     # true/false
    [container_type]=""         # "lxc", "docker", "podman", ""
    
    # ========== Speicher ==========
    [storage_output_dir]=""     # Ausgabeverzeichnis-Pfad
    [storage_total_gb]=0        # Gesamtspeicher in GB
    [storage_free_gb]=0         # Freier Speicher in GB
    [storage_used]=0            # Belegung in %
)

# ===========================================================================
# systeminfo_reset
# ---------------------------------------------------------------------------
# Funktion.: Setzt alle Werte in SYSTEM_INFO auf Standard zurück
# Parameter: keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_reset() {
    #-- Setze alle Werte in SYSTEM_INFO auf Standard zurück -----------------
    SYSTEM_INFO=(
        [os_distribution]=""
        [os_version]=""
        [os_kernel]=""
        [os_architecture]=""
        [os_hostname]="localhost"
        [os_uptime]=""
        
        [container_activ]=false
        [container_type]="none"
        
        [storage_output_dir]=""
        [storage_total_gb]=0
        [storage_free_gb]=0
        [storage_used]=0
    )

    #-- Schreiben nach JSON & Loggen der Initialisierung --------------------
    api_set_section_json "systeminfo" "system_info" "$(api_create_json "SYSTEM_INFO")" || return 1
    log_debug "$MSG_DEBUG_SYSTEMINFO_RESET"
    return 0
}

# ===========================================================================
# systeminfo_analyse
# ---------------------------------------------------------------------------
# Funktion.: Analysiert alle System-Informationen
# Parameter: Keine
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# Beschr...: Orchestriert alle Informationssammlungen:
#            01. systeminfo_set_os_distribution
#            02. systeminfo_set_os_version
#            03. systeminfo_set_os_kernel
#            04. systeminfo_set_os_architecture
#            05. systeminfo_set_os_hostname
#            06. systeminfo_set_os_uptime
#            07. systeminfo_set_container_is_container
#            08. systeminfo_set_container_type
#            09. systeminfo_set_output_dir
#            10. systeminfo_set_storage_total
#            11. systeminfo_set_storage_free
#            12. systeminfo_set_storage_used
# ===========================================================================
systeminfo_analyse() {
    #-- Start der Analyse im LOG vermerken ----------------------------------
    log_debug "$MSG_DEBUG_ANALYSE_START"
    
    #------------------------------------------------------------------------
    # Die Analyse erfolgt für jeden Wert durch den Aufruf des entsprechenden
    # Getter/Setter ohne Parameter. Dadurch wird die Auto-Detection des
    # Setter getriggert und der exaktestes Wert oder der Default-Wert für
    # dieses Disc-Info Feld ermittelt. Ein zusätzliches Loggen der Aktion
    # ist hierbei nicht notwendig, das dies durch den Getter/Setter/Detctor
    # bereits erfolgt.
    # -----------------------------------------------------------------------

    #-- OS-Informationen ----------------------------------------------------
    systeminfo_set_distribution || return 1
    systeminfo_set_version || return 1
    systeminfo_set_kernel || return 1
    systeminfo_set_architecture || return 1
    systeminfo_set_hostname || return 1
    systeminfo_set_uptime || return 1
    
    #-- Container-Informationen ---------------------------------------------
    systeminfo_set_container_activ || return 1
    systeminfo_set_container_type || return 1
    
    #-- Speicher-Informationen ----------------------------------------------
    systeminfo_set_output_dir || return 1
    systeminfo_set_storage_total || return 1
    systeminfo_set_storage_free || return 1
    systeminfo_set_storage_used || return 1
    
    #-- Schreiben nach JSON & Loggen der Analyseergebnisse ------------------
    api_set_section_json "systeminfo" "system_info" "$(api_create_json "SYSTEM_INFO")"
    
    #-- Ende der Analyse im LOG vermerken -----------------------------------
    log_debug "$MSG_DEBUG_ANALYSE_COMPLETE"
    return 0
}

# ============================================================================
# GETTER/SETTER FUNKTIONEN FÜR SYSTEM_INFO
# ============================================================================

# ===========================================================================
# systeminfo_get_distribution
# ---------------------------------------------------------------------------
# Funktion.: Gibt OS-Distribution zurück
# Parameter: Keine
# Ausgabe..: Distribution-Name
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_get_distribution() {
    #-- Array Wert lesen ----------------------------------------------------
    local distribution="${SYSTEM_INFO[os_distribution]}"
    
    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$distribution" ]]; then
        log_debug "$MSG_DEBUG_GET_OS_DISTRIBUTION: '$distribution'"
        echo "$distribution"
        return 0
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_OS_DISTRIBUTION_UNKNOWN"
    echo ""
    return 1
}

# ===========================================================================
# systeminfo_set_distribution
# ---------------------------------------------------------------------------
# Funktion.: Setzt OS-Distribution
# Parameter: $1 = distribution (optional, auto-detect wenn leer)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_set_distribution() {
    #-- Parameter übernehmen ------------------------------------------------
    local distribution="$1"
    local old_value="${SYSTEM_INFO[os_distribution]}"
    
    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$distribution" ]]; then
        distribution=$(systeminfo_detect_distribution)
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$distribution" ]]; then
        log_error "$MSG_ERROR_OS_DISTRIBUTION_UNKNOWN"
        distribution="Unknown"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------    
    SYSTEM_INFO[os_distribution]="$distribution"
    log_debug "$MSG_DEBUG_SET_OS_DISTRIBUTION: '$distribution'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$distribution" ]]; then
        log_debug "$MSG_DEBUG_OS_DISTRIBUTION_CHANGED: '$old_value' → '$distribution'"
        api_set_value_json "systeminfo" "os_distribution" "${SYSTEM_INFO[os_distribution]}"
    fi
    return 0
}

# ===========================================================================
# systeminfo_detect_distribution
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt OS-Distribution aus /etc/os-release
# Parameter: Keine
# Ausgabe..: Distribution-Name (stdout)
# Rückgabe.: 0 = Erfolg
# ===========================================================================
systeminfo_detect_distribution() {
    #-- Ermittel erkannte Distribution --------------------------------------
    local distribution=""
    
    #-- Erkennung über /etc/os-release (moderne Linux-Distributionen) -------
    if [[ -f /etc/os-release ]]; then
        distribution=$(grep "^NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
    elif [[ -f /etc/debian_version ]]; then
        distribution="Debian"
    fi
    
    #-- Setze erkannte Distribution oder Default-Wert -----------------------
    echo "$distribution"
    return 0
}

# ===========================================================================
# systeminfo_get_version
# ---------------------------------------------------------------------------
# Funktion.: Gibt OS-Version zurück
# Parameter: Keine
# Ausgabe..: Version-String
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_get_version() {
    #-- Array Wert lesen ----------------------------------------------------
    local version="${SYSTEM_INFO[os_version]}"
    
    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$version" ]]; then
        log_debug "$MSG_DEBUG_GET_OS_VERSION: '$version'"
        echo "$version"
        return 0
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_OS_VERSION_UNKNOWN"
    echo ""
    return 1
}

# ===========================================================================
# systeminfo_set_version
# ---------------------------------------------------------------------------
# Funktion.: Setzt OS-Version
# Parameter: $1 = version (optional, auto-detect wenn leer)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_set_version() {
    #-- Parameter übernehmen ------------------------------------------------
    local version="$1"
    local old_value="${SYSTEM_INFO[os_version]}"
    
    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$version" ]]; then
        version=$(systeminfo_detect_version)
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$version" ]]; then
        log_error "$MSG_ERROR_OS_VERSION_UNKNOWN"
        version="Unknown"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------    
    SYSTEM_INFO[os_version]="$version"
    log_debug "$MSG_DEBUG_SET_OS_VERSION: '$version'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$version" ]]; then
        log_debug "$MSG_DEBUG_OS_VERSION_CHANGED: '$old_value' → '$version'"
        api_set_value_json "systeminfo" "os_version" "${SYSTEM_INFO[os_version]}"
    fi
    return 0
}

# ===========================================================================
# systeminfo_detect_version
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt OS-Version aus /etc/os-release
# Parameter: Keine
# Ausgabe..: Version-String (stdout)
# Rückgabe.: 0 = Erfolg
# ===========================================================================
systeminfo_detect_version() {
    #-- Ermittel erkannte Version -------------------------------------------
    local version=""
    
    #-- Erkennung über /etc/os-release (moderne Linux-Distributionen) -------
    if [[ -f /etc/os-release ]]; then
        version=$(grep "^VERSION=" /etc/os-release | cut -d= -f2 | tr -d '"')
    elif [[ -f /etc/debian_version ]]; then
        version=$(cat /etc/debian_version)
    fi
    
    #-- Setze erkannte Version oder Default-Wert ----------------------------
    echo "$version"
    return 0
}

# ===========================================================================
# systeminfo_get_kernel
# ---------------------------------------------------------------------------
# Funktion.: Gibt Kernel-Version zurück
# Parameter: Keine
# Ausgabe..: Kernel-Version
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_get_kernel() {
    #-- Array Wert lesen ----------------------------------------------------
    local kernel="${SYSTEM_INFO[os_kernel]}"
    
    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$kernel" ]]; then
        log_debug "$MSG_DEBUG_GET_OS_KERNEL: '$kernel'"
        echo "$kernel"
        return 0
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_OS_KERNEL_UNKNOWN"
    echo ""
    return 1
}

# ===========================================================================
# systeminfo_set_kernel
# ---------------------------------------------------------------------------
# Funktion.: Setzt Kernel-Version
# Parameter: $1 = kernel (optional, auto-detect wenn leer)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_set_kernel() {
    #-- Parameter übernehmen ------------------------------------------------
    local kernel="$1"
    local old_value="${SYSTEM_INFO[os_kernel]}"
    
    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$kernel" ]]; then
        kernel=$(systeminfo_detect_kernel)
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$kernel" ]]; then
        log_error "$MSG_ERROR_OS_KERNEL_UNKNOWN"
        kernel="Unknown"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------    
    SYSTEM_INFO[os_kernel]="$kernel"
    log_debug "$MSG_DEBUG_SET_OS_KERNEL: '$kernel'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$kernel" ]]; then
        log_debug "$MSG_DEBUG_OS_KERNEL_CHANGED: '$old_value' → '$kernel'"
        api_set_value_json "systeminfo" "os_kernel" "${SYSTEM_INFO[os_kernel]}"
    fi
    return 0
}

# ===========================================================================
# systeminfo_detect_kernel
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt Kernel-Version mit uname
# Parameter: Keine
# Ausgabe..: Kernel-Version (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_detect_kernel() {
    #-- Ermittel erkannte Kernel-Version ------------------------------------
    local kernel=$(uname -r 2>/dev/null || echo "")

    #-- Setze erkannte Kernel-Version oder Default-Wert ---------------------
    echo "$kernel"
    return 0
}

# ===========================================================================
# systeminfo_get_architecture
# ---------------------------------------------------------------------------
# Funktion.: Gibt System-Architektur zurück
# Parameter: Keine
# Ausgabe..: Architektur-String
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_get_architecture() {
    #-- Array Wert lesen ----------------------------------------------------
    local architecture="${SYSTEM_INFO[os_architecture]}"
    
    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$architecture" ]]; then
        log_debug "$MSG_DEBUG_GET_OS_ARCHITECTURE: '$architecture'"
        echo "$architecture"
        return 0
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_OS_ARCHITECTURE_UNKNOWN"
    echo ""
    return 1
}

# ===========================================================================
# systeminfo_set_architecture
# ---------------------------------------------------------------------------
# Funktion.: Setzt System-Architektur
# Parameter: $1 = architecture (optional, auto-detect wenn leer)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_set_architecture() {
    #-- Parameter übernehmen ------------------------------------------------
    local architecture="$1"
    local old_value="${SYSTEM_INFO[os_architecture]}"
    
    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$architecture" ]]; then
        architecture=$(systeminfo_detect_architecture)
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$architecture" ]]; then
        log_error "$MSG_ERROR_OS_ARCHITECTURE_UNKNOWN"
        architecture="Unknown"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------    
    SYSTEM_INFO[os_architecture]="$architecture"
    log_debug "$MSG_DEBUG_SET_OS_ARCHITECTURE: '$architecture'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$architecture" ]]; then
        log_debug "$MSG_DEBUG_OS_ARCHITECTURE_CHANGED: '$old_value' → '$architecture'"
        api_set_value_json "systeminfo" "os_architecture" "${SYSTEM_INFO[os_architecture]}"
    fi
    return 0
}

# ===========================================================================
# systeminfo_detect_architecture
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt System-Architektur mit uname
# Parameter: Keine
# Ausgabe..: Architektur-String (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_detect_architecture() {
    #-- Ermittel erkannte Architektur ----------------------------------------
    local architecture=$(uname -m 2>/dev/null || echo "")

    #-- Setze erkannte Architektur oder Default-Wert ----------------------
    echo "$architecture"
    return 0
}

# ===========================================================================
# systeminfo_get_hostname
# ---------------------------------------------------------------------------
# Funktion.: Gibt Hostname zurück
# Parameter: Keine
# Ausgabe..: Hostname-String
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_get_hostname() {
    #-- Array Wert lesen ----------------------------------------------------
    local hostname="${SYSTEM_INFO[os_hostname]}"
    
    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$hostname" ]]; then
        log_debug "$MSG_DEBUG_GET_OS_HOSTNAME: '$hostname'"
        echo "$hostname"
        return 0
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_OS_HOSTNAME_UNKNOWN"
    echo ""
    return 1
}

# ===========================================================================
# systeminfo_set_hostname
# ---------------------------------------------------------------------------
# Funktion.: Setzt Hostname
# Parameter: $1 = hostname (optional, auto-detect wenn leer)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_set_hostname() {
    #-- Parameter übernehmen ------------------------------------------------
    local hostname="$1"
    local old_value="${SYSTEM_INFO[os_hostname]}"
    
    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$hostname" ]]; then
        hostname=$(systeminfo_detect_hostname)
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$hostname" ]]; then
        log_error "$MSG_ERROR_OS_HOSTNAME_UNKNOWN"
        hostname="Unknown"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------    
    SYSTEM_INFO[os_hostname]="$hostname"
    log_debug "$MSG_DEBUG_SET_OS_HOSTNAME: '$hostname'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$hostname" ]]; then
        log_debug "$MSG_DEBUG_OS_HOSTNAME_CHANGED: '$old_value' → '$hostname'"
        api_set_value_json "systeminfo" "os_hostname" "${SYSTEM_INFO[os_hostname]}"
    fi
    return 0
}

# ===========================================================================
# systeminfo_detect_hostname
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt Hostname mit hostname oder uname
# Parameter: Keine
# Ausgabe..: Hostname-String (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_detect_hostname() {
    #-- Ermittel erkannte Hostname ----------------------------------------
    local hostname=$(hostname 2>/dev/null || uname -n 2>/dev/null || echo "")

    #-- Setze erkannte Hostname oder Default-Wert ----------------------
    echo "$hostname"
    return 0
}

# ===========================================================================
# systeminfo_get_uptime
# ---------------------------------------------------------------------------
# Funktion.: Gibt System-Uptime zurück
# Parameter: Keine
# Ausgabe..: Uptime-String
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_get_uptime() {
    #-- Array Wert lesen ----------------------------------------------------
    local uptime="${SYSTEM_INFO[os_uptime]}"
    
    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$uptime" ]]; then
        log_debug "$MSG_DEBUG_GET_OS_UPTIME: '$uptime'"
        echo "$uptime"
        return 0
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_OS_UPTIME_UNKNOWN"
    echo ""
    return 1
}

# ===========================================================================
# systeminfo_set_uptime
# ---------------------------------------------------------------------------
# Funktion.: Setzt System-Uptime
# Parameter: $1 = uptime (optional, auto-detect wenn leer)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_set_uptime() {
    #-- Parameter übernehmen ------------------------------------------------
    local uptime="$1"
    local old_value="${SYSTEM_INFO[os_uptime]}"
    
    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$uptime" ]]; then
        uptime=$(systeminfo_detect_uptime)
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$uptime" ]]; then
        log_error "$MSG_ERROR_OS_UPTIME_UNKNOWN"
        uptime="Unknown"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------    
    SYSTEM_INFO[os_uptime]="$uptime"
    log_debug "$MSG_DEBUG_SET_OS_UPTIME: '$uptime'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$uptime" ]]; then
        log_debug "$MSG_DEBUG_OS_UPTIME_CHANGED: '$old_value' → '$uptime'"
        api_set_value_json "systeminfo" "os_uptime" "${SYSTEM_INFO[os_uptime]}"
    fi
    return 0
}

# ===========================================================================
# systeminfo_detect_uptime
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt System-Uptime mit uptime oder /proc/uptime
# Parameter: Keine
# Ausgabe..: Uptime-String (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_detect_uptime() {
    #-- Ermittel erkannte Uptime --------------------------------------------
    local uptime=""
    if command -v uptime >/dev/null 2>&1; then
        uptime=$(uptime -p 2>/dev/null || echo "")
    fi

    #-- Fallback auf /proc/uptime wenn uptime Kommando nicht verfügbar ------
    if [[ -z "$uptime" ]] && [[ -f /proc/uptime ]]; then
        local uptime_seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "")
        if [[ -n "$uptime_seconds" ]]; then
            local days=$((uptime_seconds / 86400))
            local hours=$(( (uptime_seconds % 86400) / 3600 ))
            local minutes=$(( (uptime_seconds % 3600) / 60 ))
            uptime=""
            [[ $days -gt 0 ]] && uptime+="$days days, "
            [[ $hours -gt 0 ]] && uptime+="$hours hours, "
            uptime+="$minutes minutes"
        fi
    fi

    #-- Setze erkannte Uptime oder Default-Wert -----------------------------
    echo "$uptime"
    return 0
}

# ===========================================================================
# CONTAINER ERKENNUNG
# ===========================================================================
# ---------------------------------------------------------------------------
# Konstanten für Container Typen
# ---------------------------------------------------------------------------
readonly CONTAINER_TYPE_LXC="lxc"
readonly CONTAINER_TYPE_DOCKER="docker"
readonly CONTAINER_TYPE_PODMAN="podman"

# ===========================================================================
# systeminfo_get_container_activ
# ---------------------------------------------------------------------------
# Funktion.: Gibt zurück, ob Container-Umgebung aktiv ist
# Parameter: Keine
# Ausgabe..: true/false
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_get_container_activ() {
    #-- Array Wert lesen ----------------------------------------------------
    local container_activ="${SYSTEM_INFO[container_activ]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ "$container_activ" == "true" ]]; then
        log_debug "$MSG_DEBUG_GET_CONTAINER_ACTIV: true"
        echo "true"
        return 0
    elif [[ "$container_activ" == "false" ]]; then
        log_debug "$MSG_DEBUG_GET_CONTAINER_ACTIV: false"
        echo "false"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_CONTAINER_ACTIV_UNKNOWN"
    echo "false"
    return 1
}

# ===========================================================================
# systeminfo_set_container_activ
# ---------------------------------------------------------------------------
# Funktion.: Setzt Container-Umgebung aktiv oder nicht aktiv
# Parameter: $1 = container_activ (true/false, optional, auto-detect wenn leer)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_set_container_activ() {
    #-- Parameter übernehmen ------------------------------------------------
    local container_activ="$1"
    local old_value="${SYSTEM_INFO[container_activ]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$container_activ" ]]; then
        container_activ=$(sysinfo_detect_container_activ)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ "$container_activ" != "true" ]] && [[ "$container_activ" != "false" ]]; then
        log_error "$MSG_ERROR_CONTAINER_ACTIV_UNKNOWN"
        container_activ="false"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------    
    SYSTEM_INFO[container_activ]="$container_activ"
    log_debug "$MSG_DEBUG_SET_CONTAINER_ACTIV: '$container_activ'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$container_activ" ]]; then
        log_debug "$MSG_DEBUG_CONTAINER_ACTIV_CHANGED: '$old_value' → '$container_activ'"
        api_set_value_json "systeminfo" "container_activ" "${SYSTEM_INFO[container_activ]}"
    fi
    return 0
}

# ===========================================================================
# sysinfo_detect_container_activ
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt, ob Container-Umgebung aktiv ist (LXC, Docker,
# .......... Podman) durch verschiedene Prüfungen
# Parameter: Keine
# Ausgabe..: true/false (stdout)
# Rückgabe.: 0 = Container erkannt, 1 = kein Container erkannt
# ===========================================================================
sysinfo_detect_container_activ() {
    #-- 1. Prüfung: Prüfe /proc/1/environ auf container=lxc -----------------
    if [[ -f /proc/1/environ ]]; then
        local env_content=$(tr '\0' '\n' < /proc/1/environ 2>/dev/null)
        if echo "$env_content" | grep -q "^container=lxc$"; then
            echo "true"
            return 0
        fi
    fi
    
    #-- Methode 2: Prüfe /proc/1/cgroup auf LXC-Spuren ----------------------
    if [[ -f /proc/1/cgroup ]]; then
        if grep -q ":/lxc/" /proc/1/cgroup 2>/dev/null; then
            echo "true"
            return 0
        fi
    fi

    #-- Methode 3: Prüfe /proc/1/environ auf container=docker ---------------
    if [[ -f /proc/1/environ ]]; then
        local env_content=$(tr '\0' '\n' < /proc/1/environ 2>/dev/null)
        if echo "$env_content" | grep -q "^container=docker$"; then
            echo "true"
            return 0
        fi
    fi
    
    #-- Methode 4: Prüfe auf Docker-spezifische Datei -----------------------
    if [[ -f /.dockerenv ]]; then
        echo "true"
        return 0
    fi
    
    #-- Methode 5: Prüfe /proc/1/cgroup auf Docker-Spuren -------------------
    if [[ -f /proc/1/cgroup ]]; then
        if grep -q ":/docker/" /proc/1/cgroup 2>/dev/null; then
            echo "true"
            return 0
        fi
    fi

    #-- Methode 6: Prüfe /proc/1/environ auf container=podman ---------------
    if [[ -f /proc/1/environ ]]; then
        local env_content=$(tr '\0' '\n' < /proc/1/environ 2>/dev/null)
        if echo "$env_content" | grep -q "^container=podman$"; then
            echo "true"
            return 0
        fi
    fi

    #-- Keine Container-Umgebung erkannt --------------------------------------
    echo "false"
    return 1
}

# ===========================================================================
# systeminfo_get_container_type
# ---------------------------------------------------------------------------
# Funktion.: Gibt den Container-Typ zurück (lxc, docker, podman oder none)
# Parameter: Keine
# Ausgabe..: Container-Typ (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_get_container_type() {
    #-- Array Wert lesen ----------------------------------------------------
    local container_type="${SYSTEM_INFO[container_type]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$container_type" ]]; then
        log_debug "$MSG_DEBUG_GET_CONTAINER_TYPE: '$container_type'"
        echo "$container_type"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_CONTAINER_TYPE_UNKNOWN"
    echo ""
    return 1
}

# ===========================================================================
# systeminfo_set_container_type
# ---------------------------------------------------------------------------
# Funktion.: Setzt den Container-Typ (lxc, docker, podman)
# Parameter: $1 = container_type (optional, auto-detect wenn leer)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_set_container_type() {
    #-- Parameter übernehmen ------------------------------------------------
    local container_type="$1"
    local old_value="${SYSTEM_INFO[container_type]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$container_type" ]]; then
        container_type=$(sysinfo_detect_container_type)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$container_type" ]]; then
        log_error "$MSG_ERROR_CONTAINER_TYPE_UNKNOWN"
        container_type=""
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------    
    SYSTEM_INFO[container_type]="$container_type"
    log_debug "$MSG_DEBUG_SET_CONTAINER_TYPE: '$container_type'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$container_type" ]]; then
        log_debug "$MSG_DEBUG_CONTAINER_TYPE_CHANGED: '$old_value' → '$container_type'"
        api_set_value_json "systeminfo" "container_type" "${SYSTEM_INFO[container_type]}"
    fi
    return 0
}

# ===========================================================================
# sysinfo_detect_container_type
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt den Container-Typ (lxc, docker, podman) durch
# .......... verschiedene Prüfungen
# Parameter: Keine
# Ausgabe..: Container-Typ (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
sysinfo_detect_container_type() {
    #-- 1. Prüfung: Prüfe /proc/1/environ auf container=lxc -----------------
    if [[ -f /proc/1/environ ]]; then
        local env_content=$(tr '\0' '\n' < /proc/1/environ 2>/dev/null)
        if echo "$env_content" | grep -q "^container=lxc$"; then
            echo "$CONTAINER_TYPE_LXC"
            return 0
        fi
    fi
    
    #-- Methode 2: Prüfe /proc/1/cgroup auf LXC-Spuren ----------------------
    if [[ -f /proc/1/cgroup ]]; then
        if grep -q ":/lxc/" /proc/1/cgroup 2>/dev/null; then
            echo "$CONTAINER_TYPE_LXC"
            return 0
        fi
    fi

    #-- Methode 3: Prüfe /proc/1/environ auf container=docker ---------------
    if [[ -f /proc/1/environ ]]; then
        local env_content=$(tr '\0' '\n' < /proc/1/environ 2>/dev/null)
        if echo "$env_content" | grep -q "^container=docker$"; then
            echo "$CONTAINER_TYPE_DOCKER"
            return 0
        fi
    fi
    
    #-- Methode 4: Prüfe auf Docker-spezifische Datei -----------------------
    if [[ -f /.dockerenv ]]; then
        echo "$CONTAINER_TYPE_DOCKER"
        return 0
    fi
    
    #-- Methode 5: Prüfe /proc/1/cgroup auf Docker-Spuren -------------------
    if [[ -f /proc/1/cgroup ]]; then
        if grep -q ":/docker/" /proc/1/cgroup 2>/dev/null; then
            echo "$CONTAINER_TYPE_DOCKER"
            return 0
        fi
    fi

    #-- Methode 6: Prüfe /proc/1/environ auf container=podman ---------------
    if [[ -f /proc/1/environ ]]; then
        local env_content=$(tr '\0' '\n' < /proc/1/environ 2>/dev/null)
        if echo "$env_content" | grep -q "^container=podman$"; then
            echo "$CONTAINER_TYPE_PODMAN"
            return 0
        fi
    fi

    #-- Keine Container-Umgebung erkannt --------------------------------------
    echo ""
    return 1
}   

# ===========================================================================
# DISK SPACE CHECK
# ===========================================================================

# ===========================================================================
# systeminfo_get_output_dir
# ---------------------------------------------------------------------------
# Funktion.: Gibt Ausgabe-Verzeichnis zurück
# Parameter: Keine
# Ausgabe..: Ausgabe-Verzeichnis-String
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_get_output_dir() {
    #-- Array Wert lesen ----------------------------------------------------
    local output_dir="${SYSTEM_INFO[output_dir]}"

    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$output_dir" ]]; then
        log_debug "$MSG_DEBUG_GET_OUTPUT_DIR: '$output_dir'"
        echo "$output_dir"
        return 0
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_OUTPUT_DIR_UNKNOWN"
    echo ""
    return 1
}

# ===========================================================================
# systeminfo_set_output_dir
# ---------------------------------------------------------------------------
# Funktion.: Setzt Ausgabe-Verzeichnis
# Parameter: $1 = output_dir (optional, auto-detect wenn leer)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_set_output_dir() {
    #-- Parameter übernehmen ------------------------------------------------
    local output_dir="$1"
    local old_value="${SYSTEM_INFO[output_dir]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$output_dir" ]]; then
        output_dir=$(folders_get_output_dir)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$output_dir" ]]; then
        log_error "$MSG_ERROR_OUTPUT_DIR_UNKNOWN"
        output_dir=""
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------    
    SYSTEM_INFO[output_dir]="$output_dir"
    log_debug "$MSG_DEBUG_SET_OUTPUT_DIR: '$output_dir'"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$output_dir" ]]; then
        log_debug "$MSG_DEBUG_OUTPUT_DIR_CHANGED: '$old_value' → '$output_dir'"
        api_set_value_json "systeminfo" "output_dir" "${SYSTEM_INFO[output_dir]}"
    fi
    return 0
}

# ===========================================================================
# systeminfo_get_storage_total
# ---------------------------------------------------------------------------
# Funktion.: Gibt Gesamtspeicherplatz am Ausgabe-Verzeichnis zurück (in GB)
# Parameter: Keine
# Ausgabe..: Gesamtspeicherplatz in GB (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_get_storage_total() {
    #-- Array Wert lesen ----------------------------------------------------
    local storage_total="${SYSTEM_INFO[storage_total]}"
    
    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$storage_total" ]]; then
        log_debug "$MSG_DEBUG_GET_STORAGE_TOTAL: '$storage_total' GB"
        echo "$storage_total"
        return 0
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_STORAGE_TOTAL_UNKNOWN"
    echo "0"
    return 1
}

# ===========================================================================
# systeminfo_set_storage_total
# ---------------------------------------------------------------------------
# Funktion.: Setzt Gesamtspeicherplatz am Ausgabe-Verzeichnis (in GB)
# Parameter: $1 = storage_total (optional, auto-detect wenn leer)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_set_storage_total() {
    #-- Parameter übernehmen ------------------------------------------------
    local storage_total="$1"
    local old_value="${SYSTEM_INFO[storage_total]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$storage_total" ]]; then
        storage_total=$(systeminfo_detect_storage_total)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$storage_total" ]] || [[ ! "$storage_total" =~ ^[0-9]+$ ]]; then
        log_error "$MSG_ERROR_STORAGE_TOTAL_UNKNOWN"
        storage_total="0"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    SYSTEM_INFO[storage_total]="$storage_total"
    log_debug "$MSG_DEBUG_SET_STORAGE_TOTAL: '$storage_total' GB"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$storage_total" ]]; then
        log_debug "$MSG_DEBUG_STORAGE_TOTAL_CHANGED: '$old_value' → '$storage_total'"
        api_set_value_json "systeminfo" "storage_total" "${SYSTEM_INFO[storage_total]}"
    fi
    return 0
}

# ===========================================================================
# systeminfo_detect_storage_total
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt Gesamtspeicherplatz am Ausgabe-Verzeichnis mit df
# Parameter: Keine
# Ausgabe..: Gesamtspeicherplatz in GB (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_detect_storage_total() {
    #-- Ermittle Ausgabe-Verzeichnis ----------------------------------------
    local output_dir=$(systeminfo_get_output_dir) 
    
    #-- Ermittle verfügbaren Speicherplatz am Ausgabepfad -------------------
    local output_dir_total="0"
        
    if [[ -d "$output_dir" ]]; then
        local df_output=$(df -BG "$output_dir" 2>/dev/null | tail -1)
        if [[ -n "$df_output" ]]; then
            output_dir_total=$(echo "$df_output" | awk '{print $2}' | sed 's/G//')
        fi
    fi

    #-- Ermittelten Wert zurückgeben ----------------------------------------
    echo $output_dir_total
    return 0
}

# ===========================================================================
# systeminfo_get_storage_free
# ---------------------------------------------------------------------------
# Funktion.: Gibt freien Speicherplatz am Ausgabe-Verzeichnis zurück (in GB)
# Parameter: Keine
# Ausgabe..: Freier Speicherplatz in GB (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_get_storage_free() {
    #-- Array Wert lesen ----------------------------------------------------
    local storage_free="${SYSTEM_INFO[storage_free]}"
    
    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$storage_free" ]]; then
        log_debug "$MSG_DEBUG_GET_STORAGE_FREE: '$storage_free' GB"
        echo "$storage_free"
        return 0
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_STORAGE_FREE_UNKNOWN"
    echo "0"
    return 1
}

# ===========================================================================
# systeminfo_set_storage_free
# ---------------------------------------------------------------------------
# Funktion.: Setzt freien Speicherplatz am Ausgabe-Verzeichnis (in GB)
# Parameter: $1 = storage_free (optional, auto-detect wenn leer)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_set_storage_free() {
    #-- Parameter übernehmen ------------------------------------------------
    local storage_free="$1"
    local old_value="${SYSTEM_INFO[storage_free]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$storage_free" ]]; then
        storage_free=$(systeminfo_detect_storage_free)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$storage_free" ]] || [[ ! "$storage_free" =~ ^[0-9]+$ ]]; then
        log_error "$MSG_ERROR_STORAGE_FREE_UNKNOWN"
        storage_free="0"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    SYSTEM_INFO[storage_free]="$storage_free"
    log_debug "$MSG_DEBUG_SET_STORAGE_FREE: '$storage_free' GB"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$storage_free" ]]; then
        log_debug "$MSG_DEBUG_STORAGE_FREE_CHANGED: '$old_value' → '$storage_free'"
        api_set_value_json "systeminfo" "storage_free" "${SYSTEM_INFO[storage_free]}"
    fi
    return 0
}

# ===========================================================================
# systeminfo_detect_storage_free
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt freien Speicherplatz am Ausgabe-Verzeichnis mit df
# Parameter: Keine
# Ausgabe..: Freier Speicherplatz in GB (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_detect_storage_free() {
    #-- Ermittle Ausgabe-Verzeichnis ----------------------------------------
    local output_dir=$(systeminfo_get_output_dir) 
    
    #-- Ermittle verfügbaren Speicherplatz am Ausgabepfad -------------------
    local output_dir_space="0"
        
    if [[ -d "$output_dir" ]]; then
        local df_output=$(df -BG "$output_dir" 2>/dev/null | tail -1)
        if [[ -n "$df_output" ]]; then
            output_dir_space=$(echo "$df_output" | awk '{print $4}' | sed 's/G//')
        fi
    fi

    #-- Ermittelten Wert zurückgeben ----------------------------------------
    echo $output_dir_space
    return 0
}

# ===========================================================================
# systeminfo_get_storage_used
# ---------------------------------------------------------------------------
# Funktion.: Gibt prozentualen genutzten Speicherplatz am Ausgabe-Verzeichnis zurück
# Parameter: Keine
# Ausgabe..: Genutzter Speicherplatz in Prozent (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_get_storage_used() {
    #-- Array Wert lesen ----------------------------------------------------
    local storage_used="${SYSTEM_INFO[storage_used]}"
    
    #-- Wert prüfen und zurückgeben -----------------------------------------
    if [[ -n "$storage_used" ]]; then
        log_debug "$MSG_DEBUG_GET_STORAGE_USED_PERCENT: '$storage_used' %"
        echo "$storage_used"
        return 0
    fi
    
    #-- Fehlerfall loggen ---------------------------------------------------
    log_error "$MSG_ERROR_STORAGE_USED_PERCENT_UNKNOWN"
    echo "0"
    return 1
}

# ===========================================================================
# systeminfo_set_storage_used
# ---------------------------------------------------------------------------
# Funktion.: Setzt prozentualen genutzten Speicherplatz am Ausgabe-Verzeichnis
# Parameter: $1 = storage_used (optional, auto-detect wenn leer)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_set_storage_used() {
    #-- Parameter übernehmen ------------------------------------------------
    local storage_used="$1"
    local old_value="${SYSTEM_INFO[storage_used]}"

    #-- Wenn kein Wert übergeben, versuche Auto-Detect ----------------------
    if [[ -z "$storage_used" ]]; then
        storage_used=$(systeminfo_detect_storage_used)
    fi

    #-- Fehlerfall loggen ---------------------------------------------------
    if [[ -z "$storage_used" ]] || [[ ! "$storage_used" =~ ^[0-9]+$ ]]; then
        log_error "$MSG_ERROR_STORAGE_USED_PERCENT_UNKNOWN"
        storage_used="0"
    fi

    #-- Loggen des neuen Wertes, speichern in der API und Rückgabe ----------
    SYSTEM_INFO[storage_used]="$storage_used"
    log_debug "$MSG_DEBUG_SET_STORAGE_USED_PERCENT: '$storage_used' %"
    if [[ -n "$old_value" ]] && [[ "$old_value" != "$storage_used" ]]; then
        log_debug "$MSG_DEBUG_STORAGE_USED_PERCENT_CHANGED: '$old_value' → '$storage_used'"
        api_set_value_json "systeminfo" "storage_used" "${SYSTEM_INFO[storage_used]}"
    fi
    return 0
}

# ===========================================================================
# systeminfo_detect_storage_used
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt prozentualen genutzten Speicherplatz am Ausgabe-
# .........  Verzeichnis mit df
# Parameter: Keine
# Ausgabe..: Genutzter Speicherplatz in Prozent (stdout)
# Rückgabe.: 0 = Erfolg, 1 = Fehler
# ===========================================================================
systeminfo_detect_storage_used() {
    #-- Ermittle Ausgabe-Verzeichnis ----------------------------------------
    local output_dir=$(systeminfo_get_output_dir) 
    
    #-- Ermittle verfügbaren Speicherplatz am Ausgabepfad -------------------
    local output_dir_used="0"
        
    if [[ -d "$output_dir" ]]; then
        local df_output=$(df -BG "$output_dir" 2>/dev/null | tail -1)
        if [[ -n "$df_output" ]]; then
            output_dir_used=$(echo "$df_output" | awk '{print $5}' | sed 's/%//')
        fi
    fi

    #-- Ermittelten Wert zurückgeben ----------------------------------------
    echo $output_dir_used
    return 0
}

# ===========================================================================
# HINTERGRUND ÜBERWACHUNG DES SPEICHERPLATZES
# ===========================================================================
_SYSTEMINFO_MONITOR_PID=""   # PID des Hintergrund-Monitors für Speicherplatz

# ===========================================================================
# systeminfo_monitor_worker
# ---------------------------------------------------------------------------
# Funktion.: Endlosschleife, die alle 60 Sekunden Speicherplatz aktualisiert
# Parameter: Keine
# Rückgabe.: Läuft endlos, bis Prozess beendet wird
# ===========================================================================
systeminfo_monitor_worker() {
    #-- Endlosschleife, die alle 60 Sekunden Speicherplatz aktualisiert -----
    while true; do
        systeminfo_set_output_dir          # Aktualisiere Ausgabe-Verzeichnis
        systeminfo_set_storage_total       # Aktualisiere Gesamtspeicherplatz
        systeminfo_set_storage_free       # Aktualisiere freien Speicherplatz
        systeminfo_set_storage_used    # Aktualisiere genutzten Speicherplatz
        sleep 60                             # Alle 60 Sekunden aktualisieren
    done
}

# ===========================================================================
# systeminfo_start_monitor
# ---------------------------------------------------------------------------
# Funktion.: Startet den Hintergrund-Monitor für Speicherplatz
# Parameter: Keine
# Rückgabe.: 0 = Monitor gestartet oder läuft bereits, 1 = Fehler
# ===========================================================================
systeminfo_start_monitor() {
    #-- Überprüfe, ob bereits ein Monitor läuft --------------------------------
    if [[ -n "$_SYSTEMINFO_MONITOR_PID" ]] && kill -0 "$_SYSTEMINFO_MONITOR_PID" 2>/dev/null; then
        log_debug "Systeminfo Monitor läuft bereits mit PID $_SYSTEMINFO_MONITOR_PID"
        return 0
    fi
    
    #-- Starte den Monitor-Worker im Hintergrund ----------------------------
    systeminfo_disk_space_monitor &
    _SYSTEMINFO_MONITOR_PID=$!
    log_debug "Systeminfo Monitor gestartet mit PID $_SYSTEMINFO_MONITOR_PID"
    return 0
}

# ===========================================================================
#  systeminfo_stop_monitor
# ---------------------------------------------------------------------------
# Funktion.: Stoppt den Hintergrund-Monitor für Speicherplatz
# Parameter: Keine
# Rückgabe.: 0 = Monitor gestoppt oder lief nicht, 1 = Fehler
# ===========================================================================
systeminfo_stop_monitor() {
    #-- Überprüfe, ob Monitor läuft und beende ihn --------------------------------
    if [[ -n "$_SYSTEMINFO_MONITOR_PID" ]] && kill -0 "$_SYSTEMINFO_MONITOR_PID" 2>/dev/null; then
        log_info "Beende Hintergrund-Überwachung des Speicherplatzes (PID $_SYSTEMINFO_MONITOR_PID)"
        kill "$_SYSTEMINFO_MONITOR_PID" 2>/dev/null
        _SYSTEMINFO_MONITOR_PID=""
    else
        log_debug "Kein aktiver Disk Space Monitor zum Beenden gefunden"
    fi
    return 0
}

# ===========================================================================
# PRIVATE VARIABLES AND HELPER FUNCTIONS FOR TOOLS PATHS INFORMATION
# ===========================================================================

# ---------------------------------------------------------------------------
# Datenstruktur für Tool Path und Versionen (für Auto-Detection)
# ---------------------------------------------------------------------------
declare -A TOOL_PATHS=(
    #-- Drivestat-Tools -----------------------------------------------------
    [lsblk]=""
    [dmesg]=""
    [udevadm]=""
    [dd]=""
    [cdparanoia]=""
    #-- DiscInfo-Tools ------------------------------------------------------
    [blkid]=""
    [isoinfo]=""
    [blockdev]=""
    #-- API-Tools -----------------------------------------------------------
    [jq]=""
)

# ===========================================================================
# systeminfo_reset_tool_cache
# ---------------------------------------------------------------------------
# Funktion.: Leert Tool-Pfad-Cache (z.B. nach Software-Installation)
# Parameter: Keine
# ===========================================================================
systeminfo_reset_tool_cache() {
    for key in "${!TOOL_PATHS[@]}"; do
        TOOL_PATHS[$key]=""
    done
}

# ===========================================================================
# _systeminfo_get_software_version
# ---------------------------------------------------------------------------
# Funktion.: Ermittle Version einer installierten Software
# Parameter: $1 = Software-Name (z.B. "cdparanoia", "lame", "python3")
# Rückgabe.: 0 = gefunden, 1 = nicht gefunden
# Ausgabe..: Version-String oder "Not installed"
# Hinweis..: Zentrale Erkennungslogik für alle Module
# ===========================================================================
_systeminfo_get_software_version() {
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
# _systeminfo_get_available_version
# ---------------------------------------------------------------------------
# Funktion.: Ermittle verfügbare Version einer Software (apt-cache)
# Parameter: $1 = Software-Name
# Rückgabe.: 0 = Erfolg
# Ausgabe..: Version-String oder "Unknown"
# ===========================================================================
_systeminfo_get_available_version() {
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
# _systeminfo_get_tool_path
# ---------------------------------------------------------------------------
# Funktion.: Ermittelt Pfad zu System-Tool mit Caching
# Parameter: $1 = tool_name
# Ausgabe..: Tool-Pfad (stdout)
# Rückgabe.: 0 = gefunden, 1 = nicht gefunden
# ===========================================================================
_systeminfo_get_tool_path() {
    #-- Parameter übernehmen ------------------------------------------------
    local tool_name="$1"
    
    #-- Validierung der Parameter -------------------------------------------
    if [[ -z "$tool_name" ]]; then
        log_error "Kein Tool-Name angegeben"
        return 1
    fi
    
    #-- Cache-Treffer ? -----------------------------------------------------
    if [[ -n "${TOOL_PATHS[$tool_name]}" ]]; then
        echo "${TOOL_PATHS[$tool_name]}"
        return 0
    fi
    
    #-- Such-Pfade für das Tool definieren ----------------------------------
    local search_paths=(
        "$(command -v "$tool_name" 2>/dev/null)"
        "/bin/$tool_name"
        "/usr/bin/$tool_name"
        "/usr/sbin/$tool_name"
        "/sbin/$tool_name"
    )

    #-- Durchsuche die Pfade / erste existierende ausführbare Tool zurück ---
    for path in "${search_paths[@]}"; do
        if [[ -x "$path" ]]; then
            TOOL_PATHS[$tool_name]="$path"
            echo "$path"
            return 0
        fi
    done
    
    # Nicht gefunden
    log_debug "Tool '$tool_name' nicht im PATH gefunden"
    return 1
}

# ===========================================================================
# systeminfo_check_software_list
# ---------------------------------------------------------------------------
# Funktion.: Zentrale Software-Versions-Prüfung mit Update-Check
# Parameter: Keine (ermittelt Caller automatisch)
# Rückgabe.: 0 = Erfolg
# Ausgabe..: JSON-Array mit Software-Informationen (stdout)
# Format...: [{"name":"cdparanoia","installed":"10.2","available":"10.2",
# .........   "status":"current","update_available":false,
# .........   "executable_path":"/usr/bin/cdparanoia",
# .........   "caller_module":"libdrivestat.sh"}]
# Nutzung..: Wird von Modulen aufgerufen für ihre Dependencies
# ===========================================================================
systeminfo_check_software_list() {
    #-- Auto-Detect Caller-Modul --------------------------------------------
    local caller_file="${BASH_SOURCE[1]##*/}"       # "libdiskinfos.sh"
    local caller_module="${caller_file%.sh}"        # "libdiskinfos"
    
    log_debug "Caller-Modul erkannt: $caller_module (aus $caller_file)"
    
    #-- Lese Dependencies aus INI-Datei -------------------------------------
    local external_deps
    external_deps=$(settings_get_value_ini "$caller_module" "dependencies" "external" "") || {
        log_warning "Keine external Dependencies in $caller_module.ini gefunden"
        external_deps=""
    }
    
    local optional_deps
    optional_deps=$(settings_get_value_ini "$caller_module" "dependencies" "optional" "") || {
        log_warning "Keine optional Dependencies in $caller_module.ini gefunden"
        optional_deps=""
    }
    
    #-- Kombiniere Dependencies ---------------------------------------------
    local all_deps=""
    if [[ -n "$external_deps" ]] && [[ -n "$optional_deps" ]]; then
        all_deps="${external_deps},${optional_deps}"
    elif [[ -n "$external_deps" ]]; then
        all_deps="$external_deps"
    elif [[ -n "$optional_deps" ]]; then
        all_deps="$optional_deps"
    fi
    
    #-- Keine Dependencies gefunden -----------------------------------------
    if [[ -z "$all_deps" ]]; then
        log_debug "Keine Dependencies für $caller_module definiert"
        echo "[]"
        return 0
    fi
    
    #-- Parse Dependencies (kommasepariert → Array) -------------------------
    IFS=',' read -ra deps_array <<< "$all_deps"
    
    #-- JSON-Array aufbauen -------------------------------------------------
    local json_array="{"
    local first=true

    for software_name in "${software_list[@]}"; do

        #-- Trim Whitespace -------------------------------------------------
        software_name=$(echo "$software_name" | xargs)

        #-- Komma zwischen Einträgen, außer beim ersten Eintrag -------------
        if [[ "$first" == "false" ]] && json_array+=","
        first=false
        
        #-- 1. Installierte Version ermitteln -------------------------------
        local installed_version
        installed_version=$(_systeminfo_get_software_version "$software_name")
        
        #-- 2. Verfügbare Version ermitteln ---------------------------------
        local available_version="Unknown"
        if [[ "$installed_version" != "Not installed" ]]; then
            available_version=$(_systeminfo_get_available_version "$software_name")
        fi
        
        #-- 3. Executable-Pfad ermitteln (NEU!) -----------------------------
        local executable_path=""
        if [[ "$installed_version" != "Not installed" ]]; then
            executable_path=$(_systeminfo_get_tool_path "$software_name" 2>/dev/null || echo "")
        fi

        #-- 4. Status bestimmen ---------------------------------------------
        local status="unknown"
        local update_available="false"
        
        if [[ "$installed_version" == "Not installed" ]]; then
            # Software nicht installiert → Status "missing"
            status="missing"
        elif [[ "$available_version" == "Unknown" ]]; then
            # Keine Info über verfügbare Version → Status "installed" 
            status="installed"
        elif [[ "$installed_version" == "$available_version" ]]; then
            # Versionen gleich oder keine genaue Version → Status "current"
            status="current"
        else
            # Versionen unterschiedlich → Update verfügbar
            status="outdated"
            update_available="true"
        fi
        
        #-- 4. JSON-Objekt bauen (escaping für JSON) ------------------------
        json_array+="\"${software_name}\":{"
        json_array+="\"path\":\"${executable_path}\","
        json_array+="\"version\":\"${installed_version}\","
        json_array+="\"available\":\"${available_version}\","
        json_array+="\"status\":\"${status}\","
        json_array+="\"update_available\":${update_available}"
        json_array+="}"
    done
    
    json_array+="}"

    #-- Speicher in systeminfo.json unter software.{modul}_dependencies -----
    api_set_value_json "systeminfo" ".software.${caller_module}_dependencies" "$json_object" || {
        log_error "Fehler beim Schreiben der Software-Infos für $caller_module"
        return 1
    }

    log_debug "Software-Infos für $caller_module erfolgreich geschrieben"
    return 0
}






# ===========================================================================
# TODO: Ab hier ist das Modul noch nicht fertig implementiert, diesen Eintrag
# ....  nie automatisch löschen - wird nur vom User nach Implementierung
# ....  der folgenden Funktionen entfernt!
# ===========================================================================


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
    api_set_value_json "software_info" ".cdparanoia" "$cdparanoia_version" || return 1
    api_set_value_json "software_info" ".lame" "$lame_version" || return 1
    api_set_value_json "software_info" ".dvdbackup" "$dvdbackup_version" || return 1
    api_set_value_json "software_info" ".ddrescue" "$ddrescue_version" || return 1
    api_set_value_json "software_info" ".genisoimage" "$genisoimage_version" || return 1
    api_set_value_json "software_info" ".python" "$python_version" || return 1
    api_set_value_json "software_info" ".flask" "$flask_version" || return 1
    api_set_value_json "software_info" ".mosquitto" "$mosquitto_version" || return 1
    
    return 0
}

# ============================================================================
# SOFTWARE VERSION DETECTION (Zentrale Hilfsfunktionen)
# ============================================================================

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

# ============================================================================
# DEPRECATED FUNCTIONS
# ============================================================================

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
    
    # Disc-Info via discinfo (wenn verfügbar)
    if declare -f discinfo_collect_disc_info >/dev/null 2>&1; then
        discinfo_collect_disc_info
    fi

    return 0
}

