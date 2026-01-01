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

# Ermittle Script-Verzeichnis (auch wenn via sudo ausgeführt)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Whiptail-Wrapper für bessere UX
use_whiptail() {
    command -v whiptail >/dev/null 2>&1
}

ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    
    if use_whiptail; then
        if [[ "$default" == "y" ]]; then
            whiptail --title "disk2iso Installation" --yesno "$question" 10 60 --defaultno
        else
            whiptail --title "disk2iso Installation" --yesno "$question" 10 60
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
    
    if dpkg -l 2>/dev/null | grep -q "^ii  $package "; then
        print_success "$description bereits installiert"
        return 0
    fi
    
    print_info "Installiere $description..."
    if apt-get install -y -qq "$package" >/dev/null 2>&1; then
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
    
    if ! use_whiptail; then
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
        echo "4. Audio-CD      - CD-Ripping mit MusicBrainz-Metadaten (optional)"
        echo "                   → cdparanoia: Fehlerkorrektur beim Rippen"
        echo "                   → lame: MP3-Encoding"
        echo "                   → cd-discid + curl + jq: MusicBrainz-Abfrage"
        echo ""
    fi
    
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
    
    # Audio-CD Ripping (optional)
    if ask_yes_no "Audio-CD Ripping installieren?" "n"; then
        install_package "genisoimage" "genisoimage (für ISO-Erstellung)" || true
        install_package "cdparanoia" "cdparanoia (CD-Ripper)"
        install_package "lame" "lame (MP3-Encoder)"
        install_package "cd-discid" "cd-discid (MusicBrainz Disc-ID)"
        install_package "curl" "curl (HTTP-Client)"
        install_package "jq" "jq (JSON-Parser)"
        install_package "eyed3" "eyeD3 (ID3-Tag Editor für Cover-Art)"
    fi
    
    # libdvdcss2 Konfiguration (nur wenn dvdbackup installiert)
    if $install_dvdbackup; then
        setup_libdvdcss2
    fi
}

# Setup für libdvdcss2 (über libdvd-pkg aus contrib)
setup_libdvdcss2() {
    print_header "LIBDVDCSS2 SETUP"
    
    echo "libdvdcss2 wird für die Entschlüsselung kommerzieller Video-DVDs benötigt."
    echo ""
    echo "Option 1: libdvd-pkg verwenden (empfohlen)"
    echo "          → Offizielles Debian contrib-Paket"
    echo "          → Kompiliert libdvdcss2 automatisch"
    echo "          → Benötigt 'contrib' in /etc/apt/sources.list"
    echo ""
    echo "Option 2: Nur ddrescue/dd verwenden (bereits installiert)"
    echo "          → Kopiert verschlüsselte ISOs"
    echo "          → Langsamer bei kopierschützten DVDs"
    echo "          → Keine zusätzlichen Repositories"
    echo ""
    
    if ask_yes_no "libdvd-pkg installieren (empfohlen)?"; then
        enable_contrib_repo
        install_libdvd_pkg
    else
        print_info "OK - dvdbackup funktioniert nur mit unverschlüsselten DVDs"
        print_info "Verschlüsselte DVDs werden mit ddrescue/dd kopiert (langsamer)"
    fi
}

# Aktiviere contrib Repository
enable_contrib_repo() {
    print_info "Prüfe contrib Repository..."
    
    # Prüfe ob contrib bereits aktiviert ist
    if grep -qE '^\s*deb\s+.*debian.*\bcontrib\b' /etc/apt/sources.list; then
        print_success "contrib Repository bereits aktiviert"
        return 0
    fi
    
    # Füge contrib zu allen Zeilen hinzu, die main enthalten
    print_info "Aktiviere contrib Repository..."
    sed -i 's/\(deb.*debian.*main\)\(\s\|$\)/\1 contrib\2/' /etc/apt/sources.list
    
    # Prüfe ob erfolgreich
    if grep -qE '^\s*deb\s+.*debian.*\bcontrib\b' /etc/apt/sources.list; then
        # Cache aktualisieren
        apt-get update -qq
        print_success "contrib Repository aktiviert"
        return 0
    else
        print_warning "Konnte contrib nicht automatisch aktivieren"
        print_info "Bitte fügen Sie 'contrib' manuell zu /etc/apt/sources.list hinzu"
        return 1
    fi
}

# Installiere libdvd-pkg
install_libdvd_pkg() {
    print_info "Installiere libdvd-pkg..."
    
    if install_package "libdvd-pkg" "libdvd-pkg"; then
        print_info "Konfiguriere libdvd-pkg (kompiliert libdvdcss2)..."
        
        # Konfiguriere libdvd-pkg automatisch
        DEBIAN_FRONTEND=noninteractive dpkg-reconfigure libdvd-pkg
        
        if [[ $? -eq 0 ]]; then
            print_success "libdvdcss2 erfolgreich kompiliert und installiert"
            print_info "Video-DVDs können nun entschlüsselt kopiert werden"
        else
            print_warning "libdvdcss2 Kompilierung fehlgeschlagen"
            print_info "Fallback auf ddrescue/dd für verschlüsselte DVDs"
        fi
    else
        print_warning "libdvd-pkg Installation fehlgeschlagen"
        print_info "Fallback auf ddrescue/dd für verschlüsselte DVDs"
    fi
}

# ============================================================================
# DISK2ISO INSTALLATION
# ============================================================================

install_disk2iso_files() {
    print_header "DISK2ISO INSTALLATION"
    
    # Prüfe ob Quell-Dateien existieren
    if [[ ! -f "$SCRIPT_DIR/disk2iso.sh" ]]; then
        print_error "disk2iso.sh nicht gefunden in $SCRIPT_DIR"
        exit 1
    fi
    
    if [[ ! -d "$SCRIPT_DIR/disk2iso-lib" ]]; then
        print_error "disk2iso-lib Verzeichnis nicht gefunden in $SCRIPT_DIR"
        exit 1
    fi
    
    # Erstelle Installationsverzeichnis
    print_info "Erstelle Verzeichnis $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    
    # Kopiere Haupt-Script
    print_info "Kopiere disk2iso Script..."
    cp -f "$SCRIPT_DIR/disk2iso.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/disk2iso.sh"
    
    # Kopiere Library
    print_info "Kopiere disk2iso Bibliothek..."
    cp -rf "$SCRIPT_DIR/disk2iso-lib" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR"/disk2iso-lib/*.sh
    
    # Erstelle Symlink
    print_info "Erstelle Symlink in /usr/local/bin..."
    ln -sf "$INSTALL_DIR/disk2iso.sh" "$BIN_LINK"
    
    print_success "disk2iso Dateien installiert nach $INSTALL_DIR"
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
