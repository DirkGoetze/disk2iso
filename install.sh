#!/bin/bash
################################################################################
# disk2iso Installation Script
# Filepath: install.sh
#
# Beschreibung:
#   Interaktive Installation von disk2iso als Script oder systemd Service
#   - Prüft und installiert benötigte Software-Pakete
#   - Bietet optionale Pakete mit Benutzerabfrage an
#   - Konfiguriert systemd Service (optional)
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

# Standard-Installationspfade
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
# SYSTEM CHECKS
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Dieses Script muss als root ausgeführt werden"
        echo "Bitte verwenden Sie: sudo $0"
        exit 1
    fi
}

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

update_package_cache() {
    print_info "Aktualisiere Paket-Cache..."
    apt-get update -qq
    print_success "Paket-Cache aktualisiert"
}

install_package() {
    local package="$1"
    local description="$2"
    
    if dpkg -l | grep -q "^ii  $package "; then
        print_success "$description bereits installiert"
        return 0
    fi
    
    print_info "Installiere $description..."
    if apt-get install -y -qq "$package" 2>&1 | grep -v "^Selecting\|^Preparing\|^Unpacking"; then
        print_success "$description installiert"
        return 0
    else
        print_error "Installation von $description fehlgeschlagen"
        return 1
    fi
}

# Kritische Standard-Pakete (immer erforderlich)
install_critical_packages() {
    print_header "INSTALLATION KRITISCHER PAKETE"
    
    local packages=(
        "coreutils:Basis-Utilities (dd, md5sum)"
        "util-linux:System-Utilities (lsblk)"
        "eject:Disc-Auswurf"
        "mount:Mount-Tools"
    )
    
    for pkg_info in "${packages[@]}"; do
        IFS=':' read -r package description <<< "$pkg_info"
        install_package "$package" "$description" || exit 1
    done
}

# Optionale Pakete für erweiterte Funktionen
install_optional_packages() {
    print_header "OPTIONALE PAKETE"
    
    echo "disk2iso kann mit zusätzlichen Paketen erweitert werden:"
    echo ""
    echo "1. genisoimage   - ISO-Erstellung und isoinfo (empfohlen)"
    echo "                   → Ermöglicht exakte Volume-Größen-Erkennung"
    echo "                   → Schnelleres Kopieren durch gezielte Blockanzahl"
    echo ""
    echo "2. gddrescue     - Intelligentes Rettungs-Tool (empfohlen)"
    echo "                   → Deutlich schneller als dd bei Lesefehlern"
    echo "                   → Besseres Fehlerhandling"
    echo ""
    echo "3. dvdbackup     - DVD-Entschlüsselung (optional)"
    echo "                   → Entschlüsselt kommerzielle Video-DVDs"
    echo "                   → Benötigt libdvdcss2 (siehe nächster Schritt)"
    echo ""
    
    # genisoimage (sehr empfohlen)
    if ask_yes_no "genisoimage installieren?" "y"; then
        install_package "genisoimage" "genisoimage + isoinfo"
    fi
    
    # gddrescue (sehr empfohlen)
    if ask_yes_no "gddrescue installieren?" "y"; then
        install_package "gddrescue" "ddrescue (GNU)"
    fi
    
    # dvdbackup (optional, benötigt libdvdcss2)
    local install_dvdbackup=false
    if ask_yes_no "dvdbackup installieren?" "n"; then
        install_package "genisoimage" "genisoimage (Abhängigkeit)" || true
        install_package "dvdbackup" "dvdbackup"
        install_dvdbackup=true
    fi
    
    # libdvdcss2 Konfiguration (nur wenn dvdbackup installiert)
    if $install_dvdbackup; then
        setup_libdvdcss2
    fi
}

# Setup für libdvdcss2 (nicht in Debian Trixie main)
setup_libdvdcss2() {
    print_header "LIBDVDCSS2 SETUP"
    
    echo "libdvdcss2 ist NICHT in den Standard-Debian-Repositories verfügbar."
    echo "Für DVD-Entschlüsselung gibt es zwei Optionen:"
    echo ""
    echo "Option 1: deb-multimedia.org Repository hinzufügen"
    echo "          → Volle Entschlüsselungs-Unterstützung"
    echo "          → Schnellste Methode für Video-DVDs"
    echo "          → Benötigt Drittanbieter-Repository"
    echo ""
    echo "Option 2: Nur ddrescue/dd verwenden (bereits installiert)"
    echo "          → Kopiert verschlüsselte ISOs"
    echo "          → Langsamer bei kopierschützten DVDs"
    echo "          → Keine zusätzlichen Repositories"
    echo ""
    
    if ask_yes_no "deb-multimedia.org Repository hinzufügen?"; then
        add_deb_multimedia_repo
        install_libdvdcss2
    else
        print_info "OK - dvdbackup funktioniert nur mit unverschlüsselten DVDs"
        print_info "Verschlüsselte DVDs werden mit ddrescue/dd kopiert (langsamer)"
    fi
}

add_deb_multimedia_repo() {
    print_info "Füge deb-multimedia.org Repository hinzu..."
    
    # Prüfe ob bereits vorhanden
    if grep -q "deb-multimedia.org" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        print_success "deb-multimedia.org bereits konfiguriert"
        return 0
    fi
    
    # Debian Version ermitteln
    local debian_version=$(cat /etc/debian_version | cut -d. -f1)
    local debian_codename="trixie"  # Debian 13
    
    if [[ "$debian_version" == "12" ]]; then
        debian_codename="bookworm"
    elif [[ "$debian_version" == "11" ]]; then
        debian_codename="bullseye"
    fi
    
    # Repository hinzufügen
    echo "deb https://www.deb-multimedia.org ${debian_codename} main non-free" > /etc/apt/sources.list.d/deb-multimedia.list
    
    # Keyring installieren
    print_info "Installiere deb-multimedia Keyring..."
    apt-get update -qq -o Acquire::AllowInsecureRepositories=true
    apt-get install -y --allow-unauthenticated deb-multimedia-keyring
    
    # Cache neu laden
    apt-get update -qq
    
    print_success "deb-multimedia.org Repository hinzugefügt"
}

install_libdvdcss2() {
    print_info "Installiere libdvdcss2..."
    
    if install_package "libdvdcss2" "libdvdcss2"; then
        print_success "DVD-Entschlüsselung aktiviert"
        print_info "Video-DVDs können nun entschlüsselt kopiert werden"
    else
        print_warning "libdvdcss2 Installation fehlgeschlagen"
        print_info "Fallback auf ddrescue/dd für verschlüsselte DVDs"
    fi
}

# ============================================================================
# DISK2ISO INSTALLATION
# ============================================================================

install_disk2iso_files() {
    print_header "DISK2ISO INSTALLATION"
    
    # Erstelle Installationsverzeichnis
    print_info "Erstelle Verzeichnis $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    
    # Kopiere Haupt-Script
    print_info "Kopiere disk2iso Script..."
    cp -f disk2iso.sh "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/disk2iso.sh"
    
    # Kopiere Library
    print_info "Kopiere disk2iso Bibliothek..."
    cp -rf disk2iso-lib "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR"/disk2iso-lib/*.sh
    
    # Erstelle Symlink
    print_info "Erstelle Symlink in /usr/local/bin..."
    ln -sf "$INSTALL_DIR/disk2iso.sh" "$BIN_LINK"
    
    print_success "disk2iso Dateien installiert"
}

configure_service() {
    print_header "SYSTEMD SERVICE KONFIGURATION"
    
    if ! ask_yes_no "disk2iso als systemd Service installieren?"; then
        print_info "Service-Installation übersprungen"
        print_info "Sie können disk2iso manuell ausführen: disk2iso -o <output-dir>"
        return 0
    fi
    
    # Ausgabe-Verzeichnis abfragen
    local output_dir
    read -p "Ausgabe-Verzeichnis für ISOs [/srv/iso]: " output_dir
    output_dir=${output_dir:-/srv/iso}
    
    # Erstelle Ausgabe-Verzeichnis
    mkdir -p "$output_dir"
    chmod 755 "$output_dir"
    
    # Erstelle Service-Datei
    print_info "Erstelle Service-Datei..."
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=disk2iso - Automatische ISO Erstellung von optischen Medien
After=multi-user.target
Wants=systemd-udevd.service
After=systemd-udevd.service

[Service]
Type=notify
ExecStart=$INSTALL_DIR/disk2iso.sh -o $output_dir
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# Benötigt Zugriff auf optische Laufwerke
DevicePolicy=closed
DeviceAllow=/dev/sr0 rw
DeviceAllow=/dev/cdrom rw

# Sicherheits-Einschränkungen
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$output_dir

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Service-Datei erstellt: $SERVICE_FILE"
    
    # Service aktivieren
    if ask_yes_no "Service jetzt aktivieren und starten?" "y"; then
        systemctl daemon-reload
        systemctl enable disk2iso.service
        systemctl start disk2iso.service
        
        print_success "Service aktiviert und gestartet"
        print_info "Status prüfen: systemctl status disk2iso"
        print_info "Logs ansehen: journalctl -u disk2iso -f"
    else
        systemctl daemon-reload
        print_info "Service erstellt aber nicht gestartet"
        print_info "Manuell starten: systemctl start disk2iso"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    print_header "DISK2ISO INSTALLATION"
    
    echo "Willkommen zur disk2iso Installation!"
    echo "Dieses Script installiert disk2iso und alle benötigten Pakete."
    echo ""
    
    # System-Checks
    check_root
    check_debian
    
    # Paket-Installation
    update_package_cache
    install_critical_packages
    install_optional_packages
    
    # disk2iso Installation
    install_disk2iso_files
    configure_service
    
    # Abschluss
    print_header "INSTALLATION ABGESCHLOSSEN"
    print_success "disk2iso wurde erfolgreich installiert!"
    echo ""
    print_info "Manuelle Verwendung: disk2iso -o /pfad/zum/ausgabe/verzeichnis"
    
    if [[ -f "$SERVICE_FILE" ]]; then
        print_info "Service-Verwendung: systemctl status disk2iso"
    fi
    
    echo ""
    print_info "Dokumentation: README.md"
    print_info "Video-DVD Hinweise: INSTALL_VIDEO_DVD.md"
    echo ""
}

# Script ausführen
main "$@"
