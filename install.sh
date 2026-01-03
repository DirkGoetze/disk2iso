#!/bin/bash
################################################################################
# disk2iso v1.0.0 - Installation Script
# Filepath: install.sh
#
# Beschreibung:
#   Wizard-basierte Installation von disk2iso
#   - 9-Seiten Installations-Wizard mit whiptail
#   - Modulare Paket-Installation (Audio-CD, Video-DVD, Video-BD)
#   - MQTT-Integration für Home Assistant
#   - Optionale systemd Service-Konfiguration
#
# Version: 1.0.0
# Datum: 03.01.2026
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

# Wizard-Zustandsvariablen
INSTALL_AUDIO_CD=false
INSTALL_VIDEO_DVD=false
INSTALL_VIDEO_BD=true  # Standard: aktiviert
INSTALL_SERVICE=false
INSTALL_MQTT=false

# MQTT-Konfigurationsvariablen
MQTT_BROKER=""
MQTT_USER=""
MQTT_PASSWORD=""

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

install_package() {
    local package="$1"
    local description="$2"
    
    if dpkg -l 2>/dev/null | grep -q "^ii  $package "; then
        return 0
    fi
    
    apt-get install -y -qq "$package" >/dev/null 2>&1
    return $?
}

# ============================================================================
# WIZARD FUNCTIONS
# ============================================================================

# Seite 1: Willkommen
wizard_page_welcome() {
    local info="Willkommen zur disk2iso Installation!

disk2iso ist ein Tool zur automatischen Erstellung von ISO-Images von optischen Medien (CD, DVD, Blu-ray).

Funktionen:
• Automatische Erkennung eingelegter Discs
• Unterstützung für Audio-CDs, Video-DVDs und Blu-rays
• MusicBrainz-Integration für Audio-CD Metadaten
• MQTT-Integration für Home Assistant
• Optional als systemd-Service für Autostart

Der Wizard führt Sie durch die Installation in 9 einfachen Schritten.

Möchten Sie fortfahren?"

    if use_whiptail; then
        if whiptail --title "disk2iso Installation - Seite 1/9" \
            --yesno "$info" 20 70 \
            --yes-button "Installation" \
            --no-button "Abbrechen"; then
            return 0
        else
            return 1
        fi
    else
        echo "$info"
        ask_yes_no "Fortfahren?"
    fi
}

# Seite 2: Basis-Pakete installieren
wizard_page_base_packages() {
    local packages=(
        "coreutils:Basis-Utilities"
        "util-linux:System-Utilities"
        "eject:Disc-Auswurf"
        "mount:Mount-Tools"
        "genisoimage:ISO-Erstellung"
        "gddrescue:ddrescue (robust)"
    )
    
    local total=${#packages[@]}
    local current=0
    
    if use_whiptail; then
        {
            for pkg_info in "${packages[@]}"; do
                IFS=':' read -r package description <<< "$pkg_info"
                current=$((current + 1))
                percent=$((current * 100 / total))
                
                echo "$percent"
                echo "XXX"
                echo "Installiere $description ($current/$total)..."
                echo "XXX"
                
                if ! dpkg -l 2>/dev/null | grep -q "^ii  $package "; then
                    apt-get install -y -qq "$package" >/dev/null 2>&1 || true
                fi
                sleep 0.5
            done
            echo "100"
        } | whiptail --title "disk2iso Installation - Seite 4/9" \
            --gauge "Installiere Audio-CD Modul..." 8 70 0
    else
        print_header "INSTALLATION BASIS-PAKETE"
        for pkg_info in "${packages[@]}"; do
            IFS=':' read -r package description <<< "$pkg_info"
            install_package "$package" "$description" || true
        done
    fi
}

# Seite 3: Modulauswahl
wizard_page_module_selection() {
    if use_whiptail; then
        local choices
        choices=$(whiptail --title "disk2iso Installation - Seite 3/9" \
            --checklist "Welche Module möchten Sie installieren?\n\nNavigieren: ↑/↓  Auswählen: Leertaste  Weiter: Enter" \
            18 70 3 \
            "AUDIO_CD" "Audio-CD Ripping (cdparanoia, lame, MusicBrainz)" ON \
            "VIDEO_DVD" "Video-DVD Support (dvdbackup, libdvdcss2)" ON \
            "VIDEO_BD" "Video-Blu-ray Support (nur ddrescue)" OFF \
            3>&1 1>&2 2>&3)
        
        if [[ $? -ne 0 ]]; then
            return 1  # Abbruch
        fi
        
        # Auswertung
        INSTALL_AUDIO_CD=false
        INSTALL_VIDEO_DVD=false
        INSTALL_VIDEO_BD=false
        
        if echo "$choices" | grep -q "AUDIO_CD"; then
            INSTALL_AUDIO_CD=true
        fi
        if echo "$choices" | grep -q "VIDEO_DVD"; then
            INSTALL_VIDEO_DVD=true
        fi
        if echo "$choices" | grep -q "VIDEO_BD"; then
            INSTALL_VIDEO_BD=true
        fi
    else
        print_header "MODULAUSWAHL"
        ask_yes_no "Audio-CD Modul installieren?" "n" && INSTALL_AUDIO_CD=true
        ask_yes_no "Video-DVD Modul installieren?" "n" && INSTALL_VIDEO_DVD=true
        ask_yes_no "Video-Blu-ray Modul installieren?" "y" && INSTALL_VIDEO_BD=true
    fi
    
    return 0
}

# Seite 4: Audio-CD Modul
wizard_page_install_audio_cd() {
    if ! $INSTALL_AUDIO_CD; then
        return 0
    fi
    
    local packages=(
        "cdparanoia:CD-Ripper mit Fehlerkorrektur"
        "lame:MP3-Encoder"
        "cd-discid:MusicBrainz Disc-ID"
        "curl:HTTP-Client"
        "jq:JSON-Parser"
        "eyed3:ID3-Tag Editor"
    )
    
    local total=${#packages[@]}
    local current=0
    
    if use_whiptail; then
        {
            for pkg_info in "${packages[@]}"; do
                IFS=':' read -r package description <<< "$pkg_info"
                current=$((current + 1))
                percent=$((current * 100 / total))
                
                echo "$percent"
                echo "XXX"
                echo "Installiere $description ($current/$total)..."
                echo "XXX"
                
                if ! dpkg -l 2>/dev/null | grep -q "^ii  $package "; then
                    apt-get install -y -qq "$package" >/dev/null 2>&1 || true
                fi
                sleep 0.3
            done
            echo "100"
        } | whiptail --title "disk2iso Installation - Seite 4/8" \
            --gauge "Installiere Audio-CD Modul..." 8 70 0
    else
        print_header "AUDIO-CD MODUL"
        for pkg_info in "${packages[@]}"; do
            IFS=':' read -r package description <<< "$pkg_info"
            install_package "$package" "$description" || true
        done
    fi
}

# Seite 5: Video-DVD Modul
wizard_page_install_video_dvd() {
    if ! $INSTALL_VIDEO_DVD; then
        return 0
    fi
    
    local packages=(
        "dvdbackup:DVD-Backup-Tool"
    )
    
    if use_whiptail; then
        {
            echo "50"
            echo "XXX"
            echo "Installiere dvdbackup..."
            echo "XXX"
            
            if ! dpkg -l 2>/dev/null | grep -q "^ii  dvdbackup "; then
                apt-get install -y -qq dvdbackup >/dev/null 2>&1 || true
            fi
            
            sleep 0.5
            echo "100"
        } | whiptail --title "disk2iso Installation - Seite 5/9" \
            --gauge "Installiere Video-DVD Modul..." 8 70 0
        
        # libdvdcss2 Setup
        local info="Video-DVD Modul installiert.

Für die Entschlüsselung kommerzieller DVDs wird libdvdcss2 benötigt.

Option 1: libdvd-pkg verwenden (empfohlen)
→ Offizielles Debian contrib-Paket
→ Kompiliert libdvdcss2 automatisch
→ Benötigt 'contrib' Repository

Option 2: Nur ddrescue verwenden
→ Kopiert verschlüsselte ISOs (langsamer)
→ Keine zusätzlichen Repositories

Möchten Sie libdvd-pkg jetzt installieren?"

        if whiptail --title "libdvdcss2 Setup" --yesno "$info" 20 70 --yes-button "Ja, installieren" --no-button "Nein, überspringen"; then
            wizard_install_libdvdcss2
        fi
    else
        print_header "VIDEO-DVD MODUL"
        install_package "dvdbackup" "DVD-Backup-Tool" || true
        
        if ask_yes_no "libdvd-pkg für DVD-Entschlüsselung installieren?" "y"; then
            wizard_install_libdvdcss2
        fi
    fi
}

# libdvdcss2 Installation (Helper)
wizard_install_libdvdcss2() {
    # Aktiviere contrib (prüfe sowohl sources.list als auch sources.list.d/)
    local needs_contrib=true
    
    # Prüfe alte sources.list
    if [[ -f /etc/apt/sources.list ]] && grep -qE '^\s*deb\s+.*debian.*\bcontrib\b' /etc/apt/sources.list; then
        needs_contrib=false
    fi
    
    # Prüfe neue sources.list.d/ Dateien
    if [[ -d /etc/apt/sources.list.d ]] && grep -qrE '^\s*deb\s+.*debian.*\bcontrib\b' /etc/apt/sources.list.d/; then
        needs_contrib=false
    fi
    
    # Füge contrib hinzu falls notwendig
    if $needs_contrib; then
        if [[ -f /etc/apt/sources.list ]] && [[ -s /etc/apt/sources.list ]]; then
            # Alte Methode: /etc/apt/sources.list bearbeiten
            sed -i 's/\(deb.*debian.*main\)\(\s\|$\)/\1 contrib\2/' /etc/apt/sources.list
        elif [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
            # Neue DEB822-Format (Debian 12+)
            if ! grep -q "Components:.*contrib" /etc/apt/sources.list.d/debian.sources; then
                sed -i 's/Components: main/Components: main contrib/' /etc/apt/sources.list.d/debian.sources
            fi
        else
            print_warning "Konnte contrib nicht aktivieren - bitte manuell hinzufügen"
        fi
        apt-get update -qq
    fi
    
    # Installiere libdvd-pkg (nicht-interaktiv)
    if use_whiptail; then
        {
            echo "50"
            echo "XXX"
            echo "Installiere libdvd-pkg..."
            echo "XXX"
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libdvd-pkg >/dev/null 2>&1 || true
            
            echo "80"
            echo "XXX"
            echo "Konfiguriere libdvdcss2..."
            echo "XXX"
            DEBIAN_FRONTEND=noninteractive dpkg-reconfigure libdvd-pkg >/dev/null 2>&1 || true
            
            sleep 0.5
            echo "100"
        } | whiptail --title "libdvdcss2 Installation" \
            --gauge "Installiere und konfiguriere libdvdcss2..." 8 70 0
    else
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libdvd-pkg >/dev/null 2>&1 || true
        DEBIAN_FRONTEND=noninteractive dpkg-reconfigure libdvd-pkg >/dev/null 2>&1 || true
    fi
}

# Seite 6: Video-Blu-ray Modul
wizard_page_install_video_bd() {
    if ! $INSTALL_VIDEO_BD; then
        return 0
    fi
    
    # Blu-ray nutzt bereits installiertes ddrescue und genisoimage
    if use_whiptail; then
        {
            echo "50"
            echo "XXX"
            echo "Prüfe Blu-ray Dependencies..."
            echo "XXX"
            sleep 0.5
            
            echo "100"
            echo "XXX"
            echo "Blu-ray Modul konfiguriert (nutzt ddrescue)"
            echo "XXX"
            sleep 0.5
        } | whiptail --title "disk2iso Installation - Seite 6/9" \
            --gauge "Konfiguriere Video-Blu-ray Modul..." 8 70 0
    else
        print_header "VIDEO-BLU-RAY MODUL"
        print_info "Blu-ray Support verwendet ddrescue (bereits installiert)"
    fi
}

# Seite 7: MQTT-Integration
wizard_page_mqtt_setup() {
    if use_whiptail; then
        local info="Möchten Sie MQTT-Integration für Home Assistant aktivieren?

MQTT ermöglicht:
• Status-Updates an Home Assistant
• Fortschrittsanzeige in Echtzeit
• Push-Benachrichtigungen bei Abschluss
• Integration in Automatisierungen

Voraussetzungen:
• Home Assistant mit MQTT Broker (Mosquitto)
• Netzwerkverbindung zum MQTT Broker

Hinweis: Kann später in /opt/disk2iso/disk2iso-lib/config.sh aktiviert werden."

        if whiptail --title "disk2iso Installation - Seite 7/9" \
            --yesno "$info" 20 70 \
            --yes-button "Aktivieren" \
            --no-button "Überspringen" \
            --defaultno; then
            INSTALL_MQTT=true
            
            # Broker IP-Adresse abfragen
            MQTT_BROKER=$(whiptail --title "MQTT Konfiguration" \
                --inputbox "Geben Sie die IP-Adresse des MQTT Brokers ein:\n(z.B. 192.168.20.10)" \
                12 70 "" 3>&1 1>&2 2>&3)
            
            if [ -z "$MQTT_BROKER" ]; then
                whiptail --title "Fehler" --msgbox "Keine Broker-Adresse angegeben. MQTT wird deaktiviert." 8 60
                INSTALL_MQTT=false
                return 0
            fi
            
            # Optional: Authentifizierung
            if whiptail --title "MQTT Authentifizierung" \
                --yesno "Benötigt der MQTT Broker Authentifizierung?" \
                10 60 \
                --defaultno; then
                
                MQTT_USER=$(whiptail --title "MQTT Benutzer" \
                    --inputbox "Benutzername:" \
                    10 60 "disk2iso" 3>&1 1>&2 2>&3)
                
                MQTT_PASSWORD=$(whiptail --title "MQTT Passwort" \
                    --passwordbox "Passwort:" \
                    10 60 3>&1 1>&2 2>&3)
            fi
            
            # mosquitto-clients installieren
            {
                echo "50"
                echo "XXX"
                echo "Installiere mosquitto-clients..."
                echo "XXX"
                apt-get install -y -qq mosquitto-clients >/dev/null 2>&1 || true
                
                echo "100"
                echo "XXX"
                echo "MQTT-Integration konfiguriert"
                echo "XXX"
                sleep 0.5
            } | whiptail --title "MQTT Installation" \
                --gauge "Installiere MQTT-Unterstützung..." 8 70 0
            
        else
            INSTALL_MQTT=false
        fi
    else
        # Text-basierter Dialog
        print_header "MQTT-INTEGRATION"
        echo "MQTT ermöglicht Status-Updates an Home Assistant:"
        echo "  • Fortschrittsanzeige in Echtzeit"
        echo "  • Push-Benachrichtigungen"
        echo "  • Integration in Automatisierungen"
        echo ""
        
        if ask_yes_no "MQTT-Integration aktivieren?" "n"; then
            INSTALL_MQTT=true
            
            read -p "MQTT Broker IP-Adresse (z.B. 192.168.20.10): " MQTT_BROKER
            
            if [ -z "$MQTT_BROKER" ]; then
                print_warning "Keine Broker-Adresse angegeben. MQTT wird deaktiviert."
                INSTALL_MQTT=false
                return 0
            fi
            
            if ask_yes_no "Benötigt der Broker Authentifizierung?" "n"; then
                read -p "Benutzername: " MQTT_USER
                read -sp "Passwort: " MQTT_PASSWORD
                echo ""
            fi
            
            print_info "Installiere mosquitto-clients..."
            apt-get install -y -qq mosquitto-clients >/dev/null 2>&1 || true
            print_success "MQTT-Integration konfiguriert"
        else
            INSTALL_MQTT=false
        fi
    fi
}

# Seite 8: Service-Installation
wizard_page_service_setup() {
    if use_whiptail; then
        local info="Möchten Sie disk2iso als systemd-Service installieren?

Als Service:
• Startet automatisch beim Booten
• Überwacht Laufwerk kontinuierlich
• Erstellt automatisch ISOs bei eingelegten Discs
• Konfiguration über systemd

Ohne Service:
• Manuelle Ausführung über Kommandozeile
• disk2iso -o <ausgabe-verzeichnis>
• Mehr Kontrolle über Zeitpunkt der Ausführung"

        if whiptail --title "disk2iso Installation - Seite 8/9" \
            --yesno "$info" 20 70 \
            --yes-button "Installieren" \
            --no-button "Überspringen" \
            --defaultno; then
            INSTALL_SERVICE=true
        else
            INSTALL_SERVICE=false
        fi
    else
        INSTALL_SERVICE=false
        ask_yes_no "disk2iso als systemd Service installieren?" "n" && INSTALL_SERVICE=true
    fi
}

# Seite 9: Abschluss
wizard_page_complete() {
    local manual_usage="disk2iso -o /pfad/zum/ausgabe/verzeichnis"
    local service_usage="systemctl status disk2iso"
    
    if $INSTALL_SERVICE; then
        local info="Installation erfolgreich abgeschlossen!

disk2iso wurde als systemd-Service installiert.

Service-Befehle:
• Status prüfen: systemctl status disk2iso
• Logs ansehen: journalctl -u disk2iso -f
• Neustarten: systemctl restart disk2iso
• Stoppen: systemctl stop disk2iso

Der Service überwacht automatisch das Laufwerk und erstellt ISOs.

Möchten Sie den Service jetzt starten?"

        if use_whiptail; then
            if whiptail --title "disk2iso Installation - Seite 9/9" \
                --yesno "$info" 20 70 \
                --yes-button "Starten" \
                --no-button "Beenden"; then
                systemctl start disk2iso.service
                whiptail --title "Service gestartet" --msgbox "disk2iso Service wurde gestartet.\n\nStatus: systemctl status disk2iso" 10 60
            fi
        else
            echo "$info"
            if ask_yes_no "Service jetzt starten?" "y"; then
                systemctl start disk2iso.service
                print_success "Service gestartet"
            fi
        fi
    else
        local info="Installation erfolgreich abgeschlossen!

disk2iso wurde installiert und kann manuell ausgeführt werden.

Verwendung:
disk2iso -o /pfad/zum/ausgabe/verzeichnis

Beispiel:
disk2iso -o /srv/iso

Dokumentation:
• README.md im Projektverzeichnis
• Hilfe: disk2iso --help"

        if use_whiptail; then
            whiptail --title "disk2iso Installation - Seite 9/9" \
                --msgbox "$info" 18 70
        else
            echo "$info"
        fi
    fi
}

# ============================================================================
# DISK2ISO INSTALLATION
# ============================================================================

install_disk2iso_files() {
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
    mkdir -p "$INSTALL_DIR"
    
    # Kopiere Haupt-Script
    cp -f "$SCRIPT_DIR/disk2iso.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/disk2iso.sh"
    
    # Kopiere Library
    cp -rf "$SCRIPT_DIR/disk2iso-lib" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR"/disk2iso-lib/*.sh
    
    # Erstelle Symlink
    ln -sf "$INSTALL_DIR/disk2iso.sh" "$BIN_LINK"
}

configure_service() {
    if ! $INSTALL_SERVICE; then
        return 0
    fi
    
    # Ausgabe-Verzeichnis
    local output_dir="/srv/iso"
    
    if ! use_whiptail; then
        read -p "Ausgabe-Verzeichnis für ISOs [$output_dir]: " input_dir
        output_dir=${input_dir:-$output_dir}
    fi
    
    # Erstelle Ausgabe-Verzeichnis mit vollständiger Struktur
    print_success "Erstelle Verzeichnisstruktur in $output_dir..."
    mkdir -p "$output_dir"/{.log,.temp,audio,dvd,bd,data}
    
    # Setze Berechtigungen (777 für NFS-Kompatibilität)
    chmod -R 777 "$output_dir" 2>/dev/null || {
        print_warning "Konnte Berechtigungen nicht setzen (evtl. NFS-Mount)"
    }
    
    # Aktualisiere config.sh mit gewähltem Ausgabeverzeichnis
    sed -i "s|DEFAULT_OUTPUT_DIR=.*|DEFAULT_OUTPUT_DIR=\"$output_dir\"|" "$INSTALL_DIR/disk2iso-lib/config.sh"
    
    # Konfiguriere MQTT falls aktiviert
    configure_mqtt
    
    # Erstelle Service-Datei
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=disk2iso - Automatische ISO Erstellung von optischen Medien
After=multi-user.target
Wants=systemd-udevd.service
After=systemd-udevd.service

[Service]
Type=simple
User=root
Group=root
ExecStart=$INSTALL_DIR/disk2iso.sh
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# Nutzt DEFAULT_OUTPUT_DIR aus config.sh
# Ausgabeverzeichnis wurde bei Installation konfiguriert

[Install]
WantedBy=multi-user.target
EOF
    
    # Service aktivieren
    systemctl daemon-reload
    systemctl enable disk2iso.service >/dev/null 2>&1
}

configure_mqtt() {
    if ! $INSTALL_MQTT; then
        return 0
    fi
    
    print_success "Konfiguriere MQTT-Integration..."
    
    # Escape Sonderzeichen für sed
    local escaped_broker=$(echo "$MQTT_BROKER" | sed 's/[\/&]/\\&/g')
    local escaped_user=$(echo "$MQTT_USER" | sed 's/[\/&]/\\&/g')
    local escaped_password=$(echo "$MQTT_PASSWORD" | sed 's/[\/&]/\\&/g')
    
    # Aktualisiere config.sh
    sed -i "s|^MQTT_ENABLED=.*|MQTT_ENABLED=true|" "$INSTALL_DIR/disk2iso-lib/config.sh"
    sed -i "s|^MQTT_BROKER=.*|MQTT_BROKER=\"$escaped_broker\"|" "$INSTALL_DIR/disk2iso-lib/config.sh"
    sed -i "s|^MQTT_USER=.*|MQTT_USER=\"$escaped_user\"|" "$INSTALL_DIR/disk2iso-lib/config.sh"
    sed -i "s|^MQTT_PASSWORD=.*|MQTT_PASSWORD=\"$escaped_password\"|" "$INSTALL_DIR/disk2iso-lib/config.sh"
    
    # Kopiere Home Assistant Beispiel-Konfiguration
    if [[ -f "$INSTALL_DIR/disk2iso-lib/docu/homeassistant-configuration.yaml" ]]; then
        # Ermittle Zielverzeichnis (Service-Output oder /tmp)
        local config_dest
        if $INSTALL_SERVICE && [[ -n "${output_dir:-}" ]]; then
            config_dest="$output_dir/homeassistant-configuration.yaml"
        else
            config_dest="/tmp/homeassistant-configuration.yaml"
        fi
        
        cp "$INSTALL_DIR/disk2iso-lib/docu/homeassistant-configuration.yaml" "$config_dest"
        chmod 644 "$config_dest"
        
        print_success "Home Assistant Beispiel-Konfiguration erstellt:"
        print_info "  $config_dest"
        print_info "  Kopiere den Inhalt in deine configuration.yaml"
    fi
}

# ============================================================================
# MAIN - WIZARD MODE
# ============================================================================

main() {
    # System-Checks
    check_root
    check_debian
    
    # Aktualisiere Paket-Cache
    apt-get update -qq
    
    # Wizard Seite 1: Willkommen
    if ! wizard_page_welcome; then
        echo "Installation abgebrochen."
        exit 0
    fi
    
    # Wizard Seite 2: Basis-Pakete
    wizard_page_base_packages
    
    # Wizard Seite 3: Modulauswahl
    if ! wizard_page_module_selection; then
        echo "Installation abgebrochen."
        exit 0
    fi
    
    # Wizard Seite 4: Audio-CD Modul
    wizard_page_install_audio_cd
    
    # Wizard Seite 5: Video-DVD Modul
    wizard_page_install_video_dvd
    
    # Wizard Seite 6: Video-Blu-ray Modul
    wizard_page_install_video_bd
    
    # disk2iso Dateien installieren
    install_disk2iso_files
    
    # Wizard Seite 7: MQTT-Integration
    wizard_page_mqtt_setup
    
    # Wizard Seite 8: Service Setup
    wizard_page_service_setup
    configure_service
    
    # Wizard Seite 9: Abschluss
    wizard_page_complete
}

# Script ausführen
main "$@"
