#!/bin/bash
################################################################################
# disk2iso v1.2.0 - Installation & Maintenance Library
# Filepath: lib/libinstall.sh
#
# Beschreibung:
#   Shared Funktionen für Installation, Update, Reparatur, Deinstallation
#   Wird verwendet von:
#   - install.sh
#   - uninstall.sh  
#   - Web-Interface (zukünftig: Update-Funktion)
#
# Version: 1.2.0
# Datum: 07.01.2026
################################################################################

# ============================================================================
# FARBEN FÜR CONSOLE OUTPUT
# ============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================================================
# OUTPUT FUNCTIONS
# ============================================================================

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# ============================================================================
# WHIPTAIL WRAPPER
# ============================================================================

# Prüfe ob whiptail verfügbar ist
use_whiptail() {
    command -v whiptail >/dev/null 2>&1
}

# Ja/Nein-Frage mit whiptail oder Fallback
ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    
    if use_whiptail; then
        if [[ "$default" == "y" ]]; then
            whiptail --title "disk2iso" --yesno "$question" 10 60 --defaultno
        else
            whiptail --title "disk2iso" --yesno "$question" 10 60
        fi
        return $?
    else
        # Fallback auf klassische Eingabe
        local answer
        if [[ "$default" == "y" ]]; then
            read -p "$question [J/n]: " answer
            answer=${answer:-j}
        else
            read -p "$question [j/N]: " answer
            answer=${answer:-n}
        fi
        [[ "$answer" =~ ^[jJyY]$ ]]
    fi
}

# Info-Nachricht anzeigen
show_info() {
    local title="$1"
    local message="$2"
    
    if use_whiptail; then
        whiptail --title "$title" --msgbox "$message" 20 70
    else
        echo -e "\n${BLUE}$title${NC}"
        echo "$message"
        read -p "Drücken Sie Enter zum Fortfahren..."
    fi
}

# ============================================================================
# SYSTEM CHECKS
# ============================================================================

# Prüfe ob Script als root ausgeführt wird
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Dieses Script muss als root ausgeführt werden"
        echo "Bitte verwenden Sie: sudo $0"
        exit 1
    fi
}

# Prüfe ob System Debian-basiert ist
check_debian() {
    if [[ ! -f /etc/debian_version ]]; then
        print_warning "Dieses Script wurde für Debian entwickelt"
        if ! ask_yes_no "Trotzdem fortfahren?"; then
            exit 1
        fi
    else
        print_success "Debian System erkannt: $(cat /etc/debian_version)"
    fi
}

# ============================================================================
# PACKAGE MANAGEMENT
# ============================================================================

# Installiere Paket falls nicht vorhanden
# Parameter: $1 = Paketname, $2 = Beschreibung (optional)
install_package() {
    local package="$1"
    local description="$2"
    
    if dpkg -l 2>/dev/null | grep -q "^ii  $package "; then
        return 0  # Bereits installiert
    fi
    
    apt-get install -y -qq "$package" >/dev/null 2>&1
    return $?
}

# ============================================================================
# ENDE DER INSTALLATION LIBRARY
# ============================================================================
