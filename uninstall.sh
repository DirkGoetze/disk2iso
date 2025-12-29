#!/bin/bash
################################################################################
# disk2iso Deinstallations-Script
# Filepath: uninstall.sh
#
# Beschreibung:
#   Entfernt disk2iso Installation komplett
#   - Stoppt und deaktiviert Service
#   - Entfernt Dateien und Verzeichnisse
#   - Optional: Entfernt installierte Pakete
#
# Erstellt: 29.12.2025
################################################################################

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installationspfade
INSTALL_DIR="/opt/disk2iso"
SERVICE_FILE="/etc/systemd/system/disk2iso.service"
BIN_LINK="/usr/local/bin/disk2iso"

# ============================================================================
# UTILITY FUNCTIONS
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

ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local answer
    
    if [[ "$default" == "y" ]]; then
        read -p "$question [J/n]: " answer
        answer=${answer:-j}
    else
        read -p "$question [j/N]: " answer
        answer=${answer:-n}
    fi
    
    [[ "$answer" =~ ^[jJyY]$ ]]
}

# ============================================================================
# CHECKS
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Dieses Script muss als root ausgeführt werden"
        echo "Bitte verwenden Sie: sudo $0"
        exit 1
    fi
}

# ============================================================================
# DEINSTALLATION
# ============================================================================

stop_service() {
    print_header "SYSTEMD SERVICE DEINSTALLATION"
    
    if [[ ! -f "$SERVICE_FILE" ]]; then
        print_info "Kein Service installiert"
        return 0
    fi
    
    print_info "Stoppe disk2iso Service..."
    systemctl stop disk2iso.service 2>/dev/null || true
    
    print_info "Deaktiviere disk2iso Service..."
    systemctl disable disk2iso.service 2>/dev/null || true
    
    print_info "Entferne Service-Datei..."
    rm -f "$SERVICE_FILE"
    
    systemctl daemon-reload
    
    print_success "Service deinstalliert"
}

remove_files() {
    print_header "DATEI-ENTFERNUNG"
    
    # Entferne Symlink
    if [[ -L "$BIN_LINK" ]]; then
        print_info "Entferne Symlink $BIN_LINK..."
        rm -f "$BIN_LINK"
        print_success "Symlink entfernt"
    fi
    
    # Entferne Installationsverzeichnis
    if [[ -d "$INSTALL_DIR" ]]; then
        print_info "Entferne Installationsverzeichnis $INSTALL_DIR..."
        rm -rf "$INSTALL_DIR"
        print_success "Installationsverzeichnis entfernt"
    fi
}

remove_packages() {
    print_header "PAKET-ENTFERNUNG (OPTIONAL)"
    
    echo "Möchten Sie auch die installierten optionalen Pakete entfernen?"
    echo ""
    print_warning "Dies entfernt: genisoimage, gddrescue, dvdbackup, libdvdcss2"
    print_warning "Andere Programme könnten diese Pakete ebenfalls benötigen!"
    echo ""
    
    if ! ask_yes_no "Optionale Pakete entfernen?"; then
        print_info "Pakete bleiben installiert"
        return 0
    fi
    
    local packages=(
        "dvdbackup"
        "libdvdcss2"
        "gddrescue"
        "genisoimage"
    )
    
    for package in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii  $package "; then
            print_info "Entferne $package..."
            apt-get remove -y -qq "$package" 2>/dev/null || true
            print_success "$package entfernt"
        fi
    done
    
    # Aufräumen
    print_info "Räume Paket-Cache auf..."
    apt-get autoremove -y -qq 2>/dev/null || true
    print_success "Aufgeräumt"
}

remove_deb_multimedia() {
    if [[ ! -f /etc/apt/sources.list.d/deb-multimedia.list ]]; then
        return 0
    fi
    
    print_header "DEB-MULTIMEDIA REPOSITORY (OPTIONAL)"
    
    echo "Das deb-multimedia.org Repository ist installiert."
    echo ""
    
    if ask_yes_no "deb-multimedia.org Repository entfernen?"; then
        print_info "Entferne Repository-Konfiguration..."
        rm -f /etc/apt/sources.list.d/deb-multimedia.list
        
        print_info "Aktualisiere Paket-Cache..."
        apt-get update -qq
        
        print_success "deb-multimedia.org Repository entfernt"
    else
        print_info "Repository bleibt konfiguriert"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    print_header "DISK2ISO DEINSTALLATION"
    
    echo "Dieses Script entfernt disk2iso komplett vom System."
    echo ""
    
    if ! ask_yes_no "Wirklich fortfahren?"; then
        echo "Abbruch."
        exit 0
    fi
    
    # Root-Check
    check_root
    
    # Deinstallation
    stop_service
    remove_files
    remove_packages
    remove_deb_multimedia
    
    # Abschluss
    print_header "DEINSTALLATION ABGESCHLOSSEN"
    print_success "disk2iso wurde erfolgreich entfernt"
    echo ""
}

# Script ausführen
main "$@"
