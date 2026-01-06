#!/bin/bash
################################################################################
# disk2iso v1.1.0 - Installation Script
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
INSTALL_WEB_SERVER=false

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

# Prüfe auf bestehende Installation
check_existing_installation() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        return 0  # Keine Installation vorhanden
    fi
    
    # Bestehende Installation gefunden
    local version=""
    if [[ -f "$INSTALL_DIR/disk2iso.sh" ]]; then
        version=$(grep -m1 "^# Version:" "$INSTALL_DIR/disk2iso.sh" | awk '{print $3}' || echo "unbekannt")
    fi
    
    if use_whiptail; then
        local info="Eine bestehende disk2iso Installation wurde gefunden!

Installierter Pfad: $INSTALL_DIR
Version: ${version:-unbekannt}

Wie möchten Sie fortfahren?

UPDATE (Empfohlen):
• Aktualisiert Programmdateien auf neue Version
• Behält ALLE Einstellungen bei (config.sh)
• Behält Service-Konfiguration bei
• MQTT/Web-Server Einstellungen bleiben erhalten

NEUINSTALLATION:
• Führt vollständige Deinstallation durch
• Entfernt alte Programmdateien
• Startet kompletten Installations-Wizard
• Einstellungen werden NICHT übernommen"
        
        if whiptail --title "Bestehende Installation gefunden" \
            --yesno "$info" 28 75 \
            --yes-button "Update" \
            --no-button "Neuinstallation"; then
            # UPDATE gewählt
            return 1
        else
            # NEUINSTALLATION gewählt
            if whiptail --title "Neuinstallation bestätigen" \
                --yesno "WARNUNG: Alle Einstellungen gehen verloren!\n\nSind Sie sicher, dass Sie eine komplette Neuinstallation durchführen möchten?\n\nDies kann NICHT rückgängig gemacht werden!" \
                14 60 \
                --defaultno; then
                
                print_info "Führe Deinstallation durch..."
                if [[ -f "$INSTALL_DIR/uninstall.sh" ]]; then
                    "$INSTALL_DIR/uninstall.sh" --silent
                else
                    # Fallback: Manuelle Deinstallation
                    systemctl stop disk2iso 2>/dev/null || true
                    systemctl disable disk2iso 2>/dev/null || true
                    systemctl stop disk2iso-web 2>/dev/null || true
                    systemctl disable disk2iso-web 2>/dev/null || true
                    rm -rf "$INSTALL_DIR"
                    rm -f "$SERVICE_FILE"
                    rm -f "/etc/systemd/system/disk2iso-web.service"
                    rm -f "$BIN_LINK"
                    systemctl daemon-reload
                fi
                print_success "Deinstallation abgeschlossen"
                return 0  # Fortfahren mit kompletter Installation
            else
                print_info "Installation abgebrochen"
                exit 0
            fi
        fi
    else
        # Text-basierter Dialog
        print_warning "Bestehende Installation gefunden: $INSTALL_DIR"
        if [[ -n "$version" ]]; then
            echo "  Version: $version"
        fi
        echo ""
        echo "Optionen:"
        echo "  1) Update (Einstellungen beibehalten)"
        echo "  2) Neuinstallation (Einstellungen löschen)"
        echo "  3) Abbrechen"
        echo ""
        read -p "Auswahl [1]: " choice
        choice=${choice:-1}
        
        case $choice in
            1)
                return 1  # UPDATE
                ;;
            2)
                read -p "WARNUNG: Alle Einstellungen gehen verloren! Fortfahren? [j/N]: " confirm
                if [[ "$confirm" =~ ^[jJyY]$ ]]; then
                    if [[ -f "$INSTALL_DIR/uninstall.sh" ]]; then
                        "$INSTALL_DIR/uninstall.sh" --silent
                    else
                        rm -rf "$INSTALL_DIR"
                        rm -f "$SERVICE_FILE"
                        rm -f "/etc/systemd/system/disk2iso-web.service"
                        rm -f "$BIN_LINK"
                    fi
                    return 0  # NEUINSTALLATION
                else
                    exit 0
                fi
                ;;
            *)
                exit 0
                ;;
        esac
    fi
}

# Führe Update durch (behält config.sh)
perform_update() {
    print_header "UPDATE INSTALLATION"
    
    # Sichere aktuelle Konfiguration
    local config_backup="/tmp/disk2iso-config-backup-$(date +%s).sh"
    if [[ -f "$INSTALL_DIR/lib/config.sh" ]]; then
        cp "$INSTALL_DIR/lib/config.sh" "$config_backup"
        print_success "Konfiguration gesichert: $config_backup"
    fi
    
    # Stoppe laufende Services
    if systemctl is-active --quiet disk2iso; then
        systemctl stop disk2iso
        print_info "Service disk2iso gestoppt"
    fi
    if systemctl is-active --quiet disk2iso-web; then
        systemctl stop disk2iso-web
        print_info "Service disk2iso-web gestoppt"
    fi
    
    # Installiere neue Dateien (überschreibt alte)
    install_disk2iso_files
    
    # Stelle Konfiguration wieder her
    if [[ -f "$config_backup" ]]; then
        cp "$config_backup" "$INSTALL_DIR/lib/config.sh"
        print_success "Konfiguration wiederhergestellt"
        rm -f "$config_backup"
    fi
    
    # Starte Services neu
    if systemctl is-enabled --quiet disk2iso 2>/dev/null; then
        systemctl start disk2iso
        print_success "Service disk2iso neu gestartet"
    fi
    if systemctl is-enabled --quiet disk2iso-web 2>/dev/null; then
        systemctl start disk2iso-web
        print_success "Service disk2iso-web neu gestartet"
    fi
    
    # Zeige Update-Zusammenfassung
    if use_whiptail; then
        whiptail --title "Update Abgeschlossen" --msgbox \
            "disk2iso wurde erfolgreich aktualisiert!\n\nAlle Einstellungen wurden beibehalten.\nServices wurden neu gestartet (falls aktiviert).\n\nPfad: $INSTALL_DIR\n\nHinweis: Überprüfen Sie die Dokumentation für neue Features!" \
            16 70
    else
        print_header "UPDATE ABGESCHLOSSEN"
        print_success "disk2iso wurde aktualisiert"
        print_info "Alle Einstellungen wurden beibehalten"
        echo ""
    fi
    
    exit 0
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
        if whiptail --title "disk2iso Installation - Seite 1/10" \
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
            echo "0"
            for pkg_info in "${packages[@]}"; do
                IFS=':' read -r package description <<< "$pkg_info"
                current=$((current + 1))
                percent=$((current * 100 / total))
                
                echo "XXX"
                echo "Installiere $description ($current/$total)..."
                echo "XXX"
                echo "$percent"
                
                if ! dpkg -l 2>/dev/null | grep -q "^ii  $package "; then
                    apt-get install -y -qq "$package" >/dev/null 2>&1 || true
                fi
                sleep 0.5
            done
        } | whiptail --title "disk2iso Installation - Seite 2/10" \
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
        choices=$(whiptail --title "disk2iso Installation - Seite 3/10" \
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
            echo "0"
            for pkg_info in "${packages[@]}"; do
                IFS=':' read -r package description <<< "$pkg_info"
                current=$((current + 1))
                percent=$((current * 100 / total))
                
                echo "XXX"
                echo "Installiere $description ($current/$total)..."
                echo "XXX"
                echo "$percent"
                
                if ! dpkg -l 2>/dev/null | grep -q "^ii  $package "; then
                    apt-get install -y -qq "$package" >/dev/null 2>&1 || true
                fi
                sleep 0.3
            done
        } | whiptail --title "disk2iso Installation - Seite 4/10" \
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
            echo "0"
            echo "XXX"
            echo "Installiere dvdbackup..."
            echo "XXX"
            echo "50"
            
            if ! dpkg -l 2>/dev/null | grep -q "^ii  dvdbackup "; then
                apt-get install -y -qq dvdbackup >/dev/null 2>&1 || true
            fi
            
            sleep 0.5
            echo "100"
        } | whiptail --title "disk2iso Installation - Seite 5/10" \
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
            echo "0"
            echo "XXX"
            echo "Installiere libdvd-pkg..."
            echo "XXX"
            echo "50"
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libdvd-pkg >/dev/null 2>&1 || true
            
            echo "XXX"
            echo "Konfiguriere libdvdcss2..."
            echo "XXX"
            echo "80"
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
            echo "0"
            echo "XXX"
            echo "Prüfe Blu-ray Dependencies..."
            echo "XXX"
            echo "50"
            sleep 0.5
            
            echo "XXX"
            echo "Blu-ray Modul konfiguriert (nutzt ddrescue)"
            echo "XXX"
            echo "100"
            sleep 0.5
        } | whiptail --title "disk2iso Installation - Seite 6/10" \
            --gauge "Konfiguriere Video-Blu-ray Modul..." 8 70 0
    else
        print_header "VIDEO-BLU-RAY MODUL"
        print_info "Blu-ray Support verwendet ddrescue (bereits installiert)"
    fi
}

# Seite 7: Service-Installation
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

        if whiptail --title "disk2iso Installation - Seite 7/10" \
            --yesno "$info" 20 70 \
            --yes-button "Installieren" \
            --no-button "Überspringen" \
            --defaultno; then
            INSTALL_SERVICE=true
            
            # Ausgabeverzeichnis abfragen
            SERVICE_OUTPUT_DIR=$(whiptail --title "Ausgabeverzeichnis für ISOs" \
                --inputbox "Geben Sie das Verzeichnis ein, in dem die ISOs gespeichert werden sollen:\n\nHinweis: Es werden automatisch Unterordner erstellt:\n  • audio/   (Audio-CDs)\n  • dvd/     (Video-DVDs)\n  • bd/      (Blu-rays)\n  • data/    (Daten-Discs)\n  • .log/    (Log-Dateien)\n  • .temp/   (Temporäre Dateien)" \
                18 70 "/media/iso" 3>&1 1>&2 2>&3)
            
            if [ -z "$SERVICE_OUTPUT_DIR" ]; then
                SERVICE_OUTPUT_DIR="/media/iso"
            fi
        else
            INSTALL_SERVICE=false
        fi
    else
        INSTALL_SERVICE=false
        if ask_yes_no "disk2iso als systemd Service installieren?" "n"; then
            INSTALL_SERVICE=true
            read -p "Ausgabe-Verzeichnis für ISOs [/media/iso]: " input_dir
            SERVICE_OUTPUT_DIR=${input_dir:-/media/iso}
        fi
    fi
}

# Seite 8: MQTT-Integration
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

Hinweis: Kann später in /opt/disk2iso/lib/config.sh aktiviert werden."

        if whiptail --title "disk2iso Installation - Seite 8/10" \
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
                echo "0"
                echo "XXX"
                echo "Installiere mosquitto-clients..."
                echo "XXX"
                echo "50"
                apt-get install -y -qq mosquitto-clients >/dev/null 2>&1 || true
                
                echo "XXX"
                echo "MQTT-Integration konfiguriert"
                echo "XXX"
                echo "100"
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

# Seite 9: Web-Server Installation
wizard_page_web_server() {
    if use_whiptail; then
        local info="Möchten Sie den disk2iso Web-Server installieren?

Der Web-Server bietet:
• Status-Überwachung in Echtzeit (Browser)
• Archiv-Verwaltung und Übersicht
• Log-Viewer mit Live-Updates
• Responsive Design für Mobile/Desktop

Technologie:
• Flask (Python Web-Framework)
• Eingebauter Flask-Server
• Port: 8080 (Standard)

Voraussetzungen:
• Python 3.7+
• Ca. 50 MB Speicherplatz

Hinweis: Der Web-Server wird als separater systemd-Service installiert."

        if whiptail --title "disk2iso Installation - Seite 9/10" \
            --yesno "$info" 22 70 \
            --yes-button "Installieren" \
            --no-button "Überspringen" \
            --defaultno; then
            INSTALL_WEB_SERVER=true
        else
            INSTALL_WEB_SERVER=false
        fi
    else
        # Text-basierter Dialog
        print_header "WEB-SERVER INSTALLATION"
        echo "Der Web-Server bietet Status-Überwachung über den Browser:"
        echo "  • Echtzeit-Status-Anzeige"
        echo "  • Archiv-Verwaltung"
        echo "  • Log-Viewer"
        echo ""
        
        if ask_yes_no "Web-Server installieren?" "n"; then
            INSTALL_WEB_SERVER=true
        else
            INSTALL_WEB_SERVER=false
        fi
    fi
}

# Seite 10: Abschluss
wizard_page_complete() {
    local manual_usage="disk2iso -o /pfad/zum/ausgabe/verzeichnis"
    local service_usage="systemctl status disk2iso"
    local web_info=""
    
    if $INSTALL_WEB_SERVER; then
        web_info="

Web-Server:
• Zugriff: http://$(hostname -I | awk '{print $1}'):8080
• Service: systemctl status disk2iso-web"
    fi
    
    if $INSTALL_SERVICE; then
        local info="Installation erfolgreich abgeschlossen!

disk2iso wurde als systemd-Service installiert.

Service-Befehle:
• Status prüfen: systemctl status disk2iso
• Logs ansehen: journalctl -u disk2iso -f
• Neustarten: systemctl restart disk2iso
• Stoppen: systemctl stop disk2iso${web_info}

Wartung:
• Update: sudo /opt/disk2iso/install.sh
• Deinstallation: sudo /opt/disk2iso/uninstall.sh

Der Service überwacht automatisch das Laufwerk und erstellt ISOs.

Möchten Sie den Service jetzt starten?"

        if use_whiptail; then
            if whiptail --title "disk2iso Installation - Seite 10/10" \
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

Wartung:
• Update: sudo /opt/disk2iso/install.sh
• Deinstallation: sudo /opt/disk2iso/uninstall.sh${web_info}

Dokumentation:
• README.md im Projektverzeichnis
• Hilfe: disk2iso --help"

        if use_whiptail; then
            whiptail --title "disk2iso Installation - Seite 10/10" \
                --msgbox "$info" 20 70
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
    
    if [[ ! -d "$SCRIPT_DIR/lib" ]]; then
        print_error "lib Verzeichnis nicht gefunden in $SCRIPT_DIR"
        exit 1
    fi
    
    # Erstelle Installationsverzeichnis
    mkdir -p "$INSTALL_DIR"
    
    # Kopiere Haupt-Script
    cp -f "$SCRIPT_DIR/disk2iso.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/disk2iso.sh"
    
    # Kopiere Library
    cp -rf "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR"/lib/*.sh
    
    # Kopiere Dokumentation (falls vorhanden)
    if [[ -d "$SCRIPT_DIR/doc" ]]; then
        cp -rf "$SCRIPT_DIR/doc" "$INSTALL_DIR/"
    fi
    
    # Kopiere Sprachdateien (falls vorhanden)
    if [[ -d "$SCRIPT_DIR/lang" ]]; then
        cp -rf "$SCRIPT_DIR/lang" "$INSTALL_DIR/"
    fi
    
    # Kopiere Service-Dateien (falls vorhanden)
    if [[ -d "$SCRIPT_DIR/service" ]]; then
        cp -rf "$SCRIPT_DIR/service" "$INSTALL_DIR/"
    fi
    
    # Kopiere Installations- und Deinstallations-Skripte (für Updates und Deinstallation)
    if [[ -f "$SCRIPT_DIR/install.sh" ]]; then
        cp -f "$SCRIPT_DIR/install.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/install.sh"
    fi
    
    if [[ -f "$SCRIPT_DIR/uninstall.sh" ]]; then
        cp -f "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/uninstall.sh"
    fi
    
    # Kopiere README für installierte Version
    if [[ -f "$SCRIPT_DIR/INSTALLED-README.md" ]]; then
        cp -f "$SCRIPT_DIR/INSTALLED-README.md" "$INSTALL_DIR/README-INSTALLED.md"
    fi
    
    # Erstelle www-Verzeichnis für Web-Server (vorbereitet für zukünftige Nutzung)
    mkdir -p "$INSTALL_DIR/www"
    
    # Kopiere www-Dateien falls vorhanden (für Web-Server)
    if [[ -d "$SCRIPT_DIR/www" ]] && [[ -n "$(ls -A "$SCRIPT_DIR/www" 2>/dev/null)" ]]; then
        cp -rf "$SCRIPT_DIR/www/"* "$INSTALL_DIR/www/" 2>/dev/null || true
    fi
    
    # Erstelle Symlink
    ln -sf "$INSTALL_DIR/disk2iso.sh" "$BIN_LINK"
}

configure_service() {
    if ! $INSTALL_SERVICE; then
        return 0
    fi
    
    # Verwende das in wizard_page_service_setup() abgefragte Verzeichnis
    local output_dir="${SERVICE_OUTPUT_DIR:-/media/iso}"
    
    # Erstelle Ausgabe-Verzeichnis mit vollständiger Struktur
    print_success "Erstelle Verzeichnisstruktur in $output_dir..."
    mkdir -p "$output_dir"/{.log,.temp,audio,dvd,bd,data}
    
    # Setze Berechtigungen (777 für NFS-Kompatibilität)
    chmod -R 777 "$output_dir" 2>/dev/null || {
        print_warning "Konnte Berechtigungen nicht setzen (evtl. NFS-Mount)"
    }
    
    # Aktualisiere config.sh mit gewähltem Ausgabeverzeichnis
    sed -i "s|DEFAULT_OUTPUT_DIR=.*|DEFAULT_OUTPUT_DIR=\"$output_dir\"|" "$INSTALL_DIR/lib/config.sh"
    
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
    
    # Aktualisiere config.sh
    sed -i "s|^MQTT_ENABLED=.*|MQTT_ENABLED=true|" "$INSTALL_DIR/lib/config.sh"
    sed -i "s|^MQTT_BROKER=.*|MQTT_BROKER=\"$escaped_broker\"|" "$INSTALL_DIR/lib/config.sh"
    
    # Nur Username/Passwort setzen wenn auch angegeben
    if [[ -n "${MQTT_USER:-}" ]] && [[ -n "${MQTT_PASSWORD:-}" ]]; then
        local escaped_user=$(echo "$MQTT_USER" | sed 's/[\/&]/\\&/g')
        local escaped_password=$(echo "$MQTT_PASSWORD" | sed 's/[\/&]/\\&/g')
        sed -i "s|^MQTT_USER=.*|MQTT_USER=\"$escaped_user\"|" "$INSTALL_DIR/lib/config.sh"
        sed -i "s|^MQTT_PASSWORD=.*|MQTT_PASSWORD=\"$escaped_password\"|" "$INSTALL_DIR/lib/config.sh"
    else
        # Explizit leer lassen für keine Authentifizierung
        sed -i "s|^MQTT_USER=.*|MQTT_USER=\"\"|" "$INSTALL_DIR/lib/config.sh"
        sed -i "s|^MQTT_PASSWORD=.*|MQTT_PASSWORD=\"\"|" "$INSTALL_DIR/lib/config.sh"
    fi
    
    # Kopiere Home Assistant Beispiel-Konfiguration
    if [[ -f "$INSTALL_DIR/doc/homeassistant-configuration.yaml" ]]; then
        # Ermittle Zielverzeichnis (Service-Output oder /tmp)
        local config_dest
        if $INSTALL_SERVICE && [[ -n "${output_dir:-}" ]]; then
            config_dest="$output_dir/homeassistant-configuration.yaml"
        else
            config_dest="/tmp/homeassistant-configuration.yaml"
        fi
        
        cp "$INSTALL_DIR/doc/homeassistant-configuration.yaml" "$config_dest"
        chmod 644 "$config_dest"
        
        print_success "Home Assistant Beispiel-Konfiguration erstellt:"
        print_info "  $config_dest"
        print_info "  Kopiere den Inhalt in deine configuration.yaml"
    fi
}

# Installiere Web-Server Komponenten
install_web_server() {
    if ! $INSTALL_WEB_SERVER; then
        return 0
    fi
    
    print_success "Installiere Web-Server-Komponenten..."
    
    # Prüfe Python3 und pip
    local python_installed=false
    local pip_installed=false
    
    if command -v python3 >/dev/null 2>&1; then
        python_installed=true
        print_success "Python3 bereits installiert: $(python3 --version)"
    fi
    
    if command -v pip3 >/dev/null 2>&1; then
        pip_installed=true
        print_success "pip3 bereits installiert"
    fi
    
    # Installiere Python3 und pip falls nötig
    if use_whiptail; then
        {
            echo "0"
            
            if ! $python_installed || ! $pip_installed; then
                echo "XXX"
                echo "Installiere Python3 und pip..."
                echo "XXX"
                echo "20"
                
                apt-get install -y -qq python3 python3-pip python3-venv >/dev/null 2>&1 || true
            fi
            
            # Erstelle virtuelles Environment
            echo "XXX"
            echo "Erstelle Python Virtual Environment..."
            echo "XXX"
            echo "40"
            
            python3 -m venv "$INSTALL_DIR/venv" >/dev/null 2>&1
            
            # Installiere Flask und Gunicorn
            echo "XXX"
            echo "Installiere Flask..."
            echo "XXX"
            echo "60"
            
            "$INSTALL_DIR/venv/bin/pip" install --upgrade pip >/dev/null 2>&1
            "$INSTALL_DIR/venv/bin/pip" install flask >/dev/null 2>&1
            
            # Erstelle Web-Verzeichnisstruktur
            echo "XXX"
            echo "Erstelle Verzeichnisstruktur..."
            echo "XXX"
            echo "80"
            
            mkdir -p "$INSTALL_DIR/www/templates"
            mkdir -p "$INSTALL_DIR/www/static/css"
            mkdir -p "$INSTALL_DIR/www/static/js"
            mkdir -p "$INSTALL_DIR/www/logs"
            
            # Setze Berechtigungen
            chmod -R 755 "$INSTALL_DIR/www"
            chmod -R 755 "$INSTALL_DIR/venv"
            
            echo "100"
        } | whiptail --title "Web-Server Installation" \
            --gauge "Installiere Web-Server-Komponenten..." 8 70 0
    else
        # Text-basierter Modus
        if ! $python_installed || ! $pip_installed; then
            print_info "Installiere Python3 und pip..."
            apt-get install -y -qq python3 python3-pip python3-venv >/dev/null 2>&1 || true
        fi
        
        print_info "Erstelle Python Virtual Environment..."
        python3 -m venv "$INSTALL_DIR/venv" >/dev/null 2>&1
        
        print_info "Installiere Flask..."
        "$INSTALL_DIR/venv/bin/pip" install --upgrade pip >/dev/null 2>&1
        "$INSTALL_DIR/venv/bin/pip" install flask >/dev/null 2>&1
        
        print_info "Erstelle Verzeichnisstruktur..."
        mkdir -p "$INSTALL_DIR/www/templates"
        mkdir -p "$INSTALL_DIR/www/static/css"
        mkdir -p "$INSTALL_DIR/www/static/js"
        mkdir -p "$INSTALL_DIR/www/logs"
        
        chmod -R 755 "$INSTALL_DIR/www"
        chmod -R 755 "$INSTALL_DIR/venv"
    fi
    
    # Erstelle requirements.txt für spätere Updates
    cat > "$INSTALL_DIR/www/requirements.txt" <<EOF
# disk2iso Web-Server Dependencies
# Install: /opt/disk2iso/venv/bin/pip install -r requirements.txt

flask>=2.0.0
EOF
    
    print_success "Web-Server-Komponenten erfolgreich installiert!"
}

# ============================================================================
# MAIN - WIZARD MODE
# ============================================================================

main() {
    # System-Checks
    check_root
    check_debian
    
    # Prüfe auf bestehende Installation
    if check_existing_installation; then
        # Keine Installation oder Neuinstallation → Wizard starten
        IS_UPDATE=false
    else
        # UPDATE gewählt → Nur Dateien aktualisieren
        IS_UPDATE=true
        perform_update
        # perform_update beendet das Script mit exit 0
    fi
    
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
    
    # Wizard Seite 7: Service Setup
    wizard_page_service_setup
    configure_service
    
    # Wizard Seite 8: MQTT-Integration
    wizard_page_mqtt_setup
    
    # Wizard Seite 9: Web-Server
    wizard_page_web_server
    install_web_server
    
    # Wizard Seite 10: Abschluss
    wizard_page_complete
}

# Script ausführen
main "$@"
