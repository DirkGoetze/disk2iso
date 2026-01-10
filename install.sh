#!/bin/bash
################################################################################
# disk2iso v1.2.0 - Installation Script
# Filepath: install.sh
#
# Beschreibung:
#   Wizard-basierte Installation von disk2iso
#   - 9-Seiten Installations-Wizard mit whiptail
#   - Modulare Paket-Installation (Audio-CD, Video-DVD, Video-BD)
#   - MQTT-Integration für Home Assistant
#   - Optionale systemd Service-Konfiguration
#
# Version: 1.2.0
# Datum: 06.01.2026
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

# Versions- und Update-Variablen
NEW_VERSION="1.2.0"  # Wird aus VERSION-Datei gelesen
INSTALLED_VERSION=""
IS_REPAIR=false
IS_UPDATE=false

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
    local version="unbekannt"
    if [[ -f "$INSTALL_DIR/VERSION" ]]; then
        version=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "unbekannt")
    elif [[ -f "$INSTALL_DIR/disk2iso.sh" ]]; then
        # Fallback für alte Installationen ohne VERSION-Datei
        version=$(grep -m1 "^# Version:" "$INSTALL_DIR/disk2iso.sh" 2>/dev/null | awk '{print $3}' || echo "unbekannt")
    fi
    
    INSTALLED_VERSION="$version"
    
    # Lese neue Version aus SOURCE
    if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
        NEW_VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "1.2.0")
    fi
    
    # Bestimme Aktion basierend auf Version
    local action_mode=""
    if [[ "$version" == "$NEW_VERSION" ]]; then
        action_mode="REPARATUR"
    else
        action_mode="UPDATE"
    fi
    
    if use_whiptail; then
        local info=""
        local yes_button=""
        
        if [[ "$action_mode" == "REPARATUR" ]]; then
            info="Eine bestehende disk2iso Installation wurde gefunden!

Installierter Pfad: $INSTALL_DIR
Installierte Version: ${version}
Neue Version: ${NEW_VERSION}

➜ GLEICHE VERSION ERKANNT

Wie möchten Sie fortfahren?

REPARATUR (Empfohlen):
• Überschreibt Programmdateien (disk2iso.sh, lib/*.sh)
• Behält ALLE Einstellungen bei (config.sh)
• Behält Service-Status bei (aktiviert/deaktiviert)
• Repariert beschädigte Installationen
• Keine Änderung an MQTT/Web-Server Konfiguration

NEUINSTALLATION:
• Führt vollständige Deinstallation durch
• Startet kompletten Installations-Wizard
• Einstellungen werden NICHT übernommen"
            yes_button="Reparatur"
        else
            info="Eine bestehende disk2iso Installation wurde gefunden!

Installierter Pfad: $INSTALL_DIR
Installierte Version: ${version}
Neue Version: ${NEW_VERSION}

➜ UPDATE VERFÜGBAR

Wie möchten Sie fortfahren?

UPDATE (Empfohlen):
• Aktualisiert Programmdateien auf Version ${NEW_VERSION}
• Behält ALLE Einstellungen bei (config.sh)
• Optionale Änderung der Service-Konfiguration
• MQTT/Web-Server Einstellungen bleiben erhalten
• Zeigt Installations-Fortschritt an

NEUINSTALLATION:
• Führt vollständige Deinstallation durch
• Startet kompletten Installations-Wizard
• Einstellungen werden NICHT übernommen"
            yes_button="Update"
        fi
        
        if whiptail --title "Bestehende Installation gefunden" \
            --yesno "$info" 30 75 \
            --yes-button "$yes_button" \
            --no-button "Neuinstallation"; then
            # UPDATE/REPARATUR gewählt
            if [[ "$action_mode" == "REPARATUR" ]]; then
                IS_REPAIR=true
                IS_UPDATE=false
            else
                IS_REPAIR=false
                IS_UPDATE=true
            fi
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

# Führe Reparatur durch (nur Programmdateien, keine config.sh-Änderung)
perform_repair() {
    print_header "REPARATUR INSTALLATION v$INSTALLED_VERSION"
    
    # Sichere aktuelle Konfiguration
    local config_backup="/tmp/disk2iso-config-backup-$(date +%s).sh"
    if [[ -f "$INSTALL_DIR/lib/config.sh" ]]; then
        cp "$INSTALL_DIR/lib/config.sh" "$config_backup"
        print_info "Konfiguration gesichert: $config_backup"
    fi
    
    # Stoppe laufende Services
    local service_was_active=false
    local web_service_was_active=false
    
    if systemctl is-active --quiet disk2iso; then
        systemctl stop disk2iso
        service_was_active=true
        print_info "Service disk2iso gestoppt"
    fi
    if systemctl is-active --quiet disk2iso-web; then
        systemctl stop disk2iso-web
        web_service_was_active=true
        print_info "Service disk2iso-web gestoppt"
    fi
    
    # Fortschrittsanzeige
    (
        echo "10" ; sleep 0.5
        echo "# Kopiere Haupt-Script..."
        cp -f "$SCRIPT_DIR/disk2iso.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/disk2iso.sh"
        
        echo "30" ; sleep 0.3
        echo "# Kopiere VERSION-Datei..."
        if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
            cp -f "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/"
        fi
        
        echo "50" ; sleep 0.3
        echo "# Kopiere Bibliotheken..."
        cp -rf "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR"/lib/*.sh
        
        echo "70" ; sleep 0.3
        echo "# Stelle Konfiguration wieder her..."
        if [[ -f "$config_backup" ]]; then
            cp "$config_backup" "$INSTALL_DIR/lib/config.sh"
            rm -f "$config_backup"
        fi
        
        echo "85" ; sleep 0.3
        echo "# Kopiere Dokumentation..."
        if [[ -d "$SCRIPT_DIR/doc" ]]; then
            cp -rf "$SCRIPT_DIR/doc" "$INSTALL_DIR/"
        fi
        if [[ -d "$SCRIPT_DIR/lang" ]]; then
            cp -rf "$SCRIPT_DIR/lang" "$INSTALL_DIR/"
        fi
        
        echo "100"
        echo "# Reparatur abgeschlossen!"
        sleep 0.5
    ) | whiptail --title "Reparatur läuft" --gauge "Starte Reparatur..." 10 70 0
    
    # Prüfe fehlende Komponenten und biete Installation an
    local missing_components=false
    local install_service_now=false
    local install_mqtt_now=false
    local install_web_now=false
    
    # Prüfe disk2iso.service
    if [[ ! -f "$SERVICE_FILE" ]]; then
        if use_whiptail; then
            if whiptail --title "Fehlende Komponente erkannt" \
                --yesno "Der disk2iso Service ist nicht installiert.\n\nMöchten Sie ihn jetzt einrichten?\n\nDies ermöglicht automatisches Starten beim Booten." \
                12 70; then
                install_service_now=true
                missing_components=true
            fi
        fi
    fi
    
    # Prüfe MQTT-Integration (mosquitto-clients)
    if ! command -v mosquitto_pub >/dev/null 2>&1; then
        if use_whiptail; then
            if whiptail --title "Optionale Komponente" \
                --yesno "MQTT-Integration ist nicht installiert.\n\nMQTT ermöglicht:\n• Status-Updates an Home Assistant\n• Fortschrittsanzeige in Echtzeit\n• Push-Benachrichtigungen\n\nMöchten Sie MQTT jetzt einrichten?" \
                14 70; then
                install_mqtt_now=true
                missing_components=true
            fi
        else
            print_info "MQTT-Integration ist nicht installiert"
            if ask_yes_no "MQTT jetzt einrichten?" "n"; then
                install_mqtt_now=true
                missing_components=true
            fi
        fi
    fi
    
    # Prüfe Web-Server (Python venv)
    if [[ ! -d "$INSTALL_DIR/venv" ]] || [[ ! -f "$INSTALL_DIR/venv/bin/flask" ]]; then
        if use_whiptail; then
            if whiptail --title "Optionale Komponente" \
                --yesno "Web-Server ist nicht installiert.\n\nWeb-Server bietet:\n• Status-Überwachung im Browser\n• Archiv-Verwaltung und Übersicht\n• Log-Viewer mit Live-Updates\n• Responsive Design\n\nMöchten Sie den Web-Server jetzt installieren?" \
                14 70; then
                install_web_now=true
                missing_components=true
            fi
        else
            print_info "Web-Server ist nicht installiert"
            if ask_yes_no "Web-Server jetzt installieren?" "n"; then
                install_web_now=true
                missing_components=true
            fi
        fi
    fi
    
    # Service jetzt installieren wenn gewünscht
    if [[ "$install_service_now" == "true" ]]; then
        # Frage Ausgabeverzeichnis
        local output_dir="/media/iso"
        if use_whiptail; then
            output_dir=$(whiptail --title "Ausgabeverzeichnis" \
                --inputbox "Ausgabeverzeichnis für ISOs:" \
                10 60 "/media/iso" 3>&1 1>&2 2>&3) || output_dir="/media/iso"
        fi
        
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
ExecStart=$INSTALL_DIR/disk2iso.sh -o $output_dir
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        # Aktualisiere config.sh
        if [[ -f "$INSTALL_DIR/lib/config.sh" ]]; then
            sed -i "s|DEFAULT_OUTPUT_DIR=.*|DEFAULT_OUTPUT_DIR=\"$output_dir\"|" "$INSTALL_DIR/lib/config.sh"
        fi
        
        # Erstelle Ausgabeverzeichnis mit Unterordnern
        mkdir -p "$output_dir"/{.log,.temp,audio,dvd,bd,data}
        chmod 755 "$output_dir"
        print_success "Ausgabeverzeichnis erstellt: $output_dir"
        
        systemctl daemon-reload
        systemctl enable disk2iso.service >/dev/null 2>&1
        systemctl start disk2iso.service >/dev/null 2>&1
        
        print_success "Service disk2iso installiert und gestartet"
    else
        # Service existiert bereits → Stelle sicher dass Ausgabeverzeichnis existiert
        if [[ -f "$SERVICE_FILE" ]]; then
            # Lese Ausgabeverzeichnis aus Service-Datei
            local output_dir=$(grep "ExecStart=" "$SERVICE_FILE" | sed -n 's/.*-o \([^ ]*\).*/\1/p')
            if [[ -z "$output_dir" ]]; then
                # Fallback: Lese aus config.sh
                output_dir=$(grep "DEFAULT_OUTPUT_DIR=" "$INSTALL_DIR/lib/config.sh" 2>/dev/null | cut -d'"' -f2)
            fi
            
            # Erstelle Verzeichnis falls es nicht existiert
            if [[ -n "$output_dir" ]] && [[ ! -d "$output_dir" ]]; then
                mkdir -p "$output_dir"/{.log,.temp,audio,dvd,bd,data}
                chmod 755 "$output_dir"
                print_success "Ausgabeverzeichnis erstellt: $output_dir"
            fi
        fi
        
        # Starte Services neu (falls vorher aktiv)
        if [[ "$service_was_active" == "true" ]]; then
            systemctl start disk2iso
            print_success "Service disk2iso neu gestartet"
        fi
        if [[ "$web_service_was_active" == "true" ]]; then
            systemctl start disk2iso-web
            print_success "Service disk2iso-web neu gestartet"
        fi
    fi
    
    # MQTT jetzt installieren wenn gewünscht
    if [[ "$install_mqtt_now" == "true" ]]; then
        if use_whiptail; then
            local mqtt_broker=$(whiptail --title "MQTT Konfiguration" \
                --inputbox "Geben Sie die IP-Adresse des MQTT Brokers ein:\n(z.B. 192.168.20.10)" \
                10 60 3>&1 1>&2 2>&3)
            
            if [[ -n "$mqtt_broker" ]]; then
                # Optionale Authentifizierung
                local mqtt_user=""
                local mqtt_password=""
                if whiptail --title "MQTT Authentifizierung" \
                    --yesno "Benötigt der MQTT Broker Authentifizierung?" \
                    8 60; then
                    mqtt_user=$(whiptail --title "MQTT Benutzer" \
                        --inputbox "Benutzername:" 8 60 3>&1 1>&2 2>&3)
                    mqtt_password=$(whiptail --title "MQTT Passwort" \
                        --passwordbox "Passwort:" 8 60 3>&1 1>&2 2>&3)
                fi
                
                # Installiere mosquitto-clients
                {
                    echo "10"
                    echo "XXX"
                    echo "Installiere mosquitto-clients..."
                    echo "XXX"
                    apt-get update >/dev/null 2>&1
                    echo "50"
                    apt-get install -y mosquitto-clients >/dev/null 2>&1
                    echo "90"
                    
                    # Aktualisiere config.sh
                    local escaped_broker=$(echo "$mqtt_broker" | sed 's/[\/&]/\\&/g')
                    sed -i "s|^MQTT_ENABLED=.*|MQTT_ENABLED=true|" "$INSTALL_DIR/lib/config.sh"
                    sed -i "s|^MQTT_BROKER=.*|MQTT_BROKER=\"$escaped_broker\"|" "$INSTALL_DIR/lib/config.sh"
                    
                    if [[ -n "$mqtt_user" ]]; then
                        local escaped_user=$(echo "$mqtt_user" | sed 's/[\/&]/\\&/g')
                        local escaped_password=$(echo "$mqtt_password" | sed 's/[\/&]/\\&/g')
                        sed -i "s|^MQTT_USER=.*|MQTT_USER=\"$escaped_user\"|" "$INSTALL_DIR/lib/config.sh"
                        sed -i "s|^MQTT_PASSWORD=.*|MQTT_PASSWORD=\"$escaped_password\"|" "$INSTALL_DIR/lib/config.sh"
                    fi
                    
                    echo "XXX"
                    echo "MQTT-Integration konfiguriert"
                    echo "XXX"
                    echo "100"
                    sleep 0.5
                } | whiptail --title "MQTT Installation" \
                    --gauge "Installiere MQTT-Unterstützung..." 8 70 0
                
                print_success "MQTT-Integration installiert: $mqtt_broker"
            fi
        else
            # Text-Modus
            read -p "MQTT Broker IP-Adresse: " mqtt_broker
            if [[ -n "$mqtt_broker" ]]; then
                local mqtt_user="" mqtt_password=""
                if ask_yes_no "Benötigt Authentifizierung?" "n"; then
                    read -p "Benutzername: " mqtt_user
                    read -sp "Passwort: " mqtt_password; echo ""
                fi
                print_info "Installiere mosquitto-clients..."
                apt-get update >/dev/null 2>&1
                apt-get install -y mosquitto-clients >/dev/null 2>&1
                sed -i "s|^MQTT_ENABLED=.*|MQTT_ENABLED=true|" "$INSTALL_DIR/lib/config.sh"
                sed -i "s|^MQTT_BROKER=.*|MQTT_BROKER=\"$(echo "$mqtt_broker" | sed 's/[\/&]/\\&/g')\"|" "$INSTALL_DIR/lib/config.sh"
                [[ -n "$mqtt_user" ]] && sed -i "s|^MQTT_USER=.*|MQTT_USER=\"$(echo "$mqtt_user" | sed 's/[\/&]/\\&/g')\"|" "$INSTALL_DIR/lib/config.sh"
                [[ -n "$mqtt_password" ]] && sed -i "s|^MQTT_PASSWORD=.*|MQTT_PASSWORD=\"$(echo "$mqtt_password" | sed 's/[\/&]/\\&/g')\"|" "$INSTALL_DIR/lib/config.sh"
                print_success "MQTT installiert: $mqtt_broker"
            fi
        fi
    fi
    
    # Web-Server jetzt installieren wenn gewünscht
    if [[ "$install_web_now" == "true" ]]; then
        INSTALL_WEB_SERVER=true
        
        # Führe Web-Server Installation aus (direkt inline für Repair-Modus)
        {
            echo "0"
            echo "XXX"
            echo "Prüfe Python-Abhängigkeiten..."
            echo "XXX"
            
            # Installiere Python3 falls nötig
            if ! command -v python3 >/dev/null 2>&1; then
                echo "20"
                echo "XXX"
                echo "Installiere Python3 und pip..."
                echo "XXX"
                apt-get update >/dev/null 2>&1
                apt-get install -y python3 python3-pip python3-venv >/dev/null 2>&1
            fi
            
            # Stelle sicher dass python3-venv installiert ist (Debian/Ubuntu brauchen separates Paket)
            if ! dpkg -l | grep -q python3.*-venv; then
                echo "25"
                echo "XXX"
                echo "Installiere python3-venv..."
                echo "XXX"
                apt-get install -y python3-venv >/dev/null 2>&1
            fi
            
            # Erstelle Virtual Environment
            echo "40"
            echo "XXX"
            echo "Erstelle Python Virtual Environment..."
            echo "XXX"
            python3 -m venv "$INSTALL_DIR/venv" >/dev/null 2>&1
            
            # Installiere Flask
            echo "60"
            echo "XXX"
            echo "Installiere Flask..."
            echo "XXX"
            "$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade pip >/dev/null 2>&1
            "$INSTALL_DIR/venv/bin/pip" install --quiet flask >/dev/null 2>&1
            
            # Erstelle Verzeichnisstruktur
            echo "80"
            echo "XXX"
            echo "Erstelle Verzeichnisstruktur..."
            echo "XXX"
            mkdir -p "$INSTALL_DIR/www/templates"
            mkdir -p "$INSTALL_DIR/www/static/css"
            mkdir -p "$INSTALL_DIR/www/static/js"
            mkdir -p "$INSTALL_DIR/www/logs"
            chmod -R 755 "$INSTALL_DIR/www" 2>/dev/null || true
            chmod -R 755 "$INSTALL_DIR/venv" 2>/dev/null || true
            
            # Erstelle requirements.txt
            cat > "$INSTALL_DIR/www/requirements.txt" <<'EOFREQ'
# disk2iso Web-Server Dependencies
flask>=2.0.0
EOFREQ
            
            echo "100"
            echo "XXX"
            echo "Web-Server installiert!"
            echo "XXX"
            sleep 0.5
        } | whiptail --title "Web-Server Installation" \
            --gauge "Installiere Web-Server-Komponenten..." 8 70 0
        
        print_success "Web-Server installiert (Python/Flask)"
        print_info "Hinweis: Flask app.py noch nicht vorhanden (Phase 2)"
    fi
    
    # Zeige Reparatur-Zusammenfassung
    if use_whiptail; then
        whiptail --title "Reparatur Abgeschlossen" --msgbox \
            "disk2iso wurde erfolgreich repariert!\n\nAlle Einstellungen wurden beibehalten.\nServices wurden neu gestartet (falls aktiviert).\n\nPfad: $INSTALL_DIR\nVersion: $NEW_VERSION" \
            14 70
    else
        print_header "REPARATUR ABGESCHLOSSEN"
        print_success "disk2iso wurde repariert"
        print_info "Alle Einstellungen wurden beibehalten"
        echo ""
    fi
    
    exit 0
}

# Führe Update durch (behält config.sh)
perform_update() {
    print_header "UPDATE INSTALLATION $INSTALLED_VERSION → $NEW_VERSION"
    
    # Sichere aktuelle Konfiguration
    local config_backup="/tmp/disk2iso-config-backup-$(date +%s).sh"
    if [[ -f "$INSTALL_DIR/lib/config.sh" ]]; then
        cp "$INSTALL_DIR/lib/config.sh" "$config_backup"
        print_info "Konfiguration gesichert: $config_backup"
    fi
    
    # Prüfe aktuellen Status
    local service_enabled=false
    local service_active=false
    local web_service_enabled=false
    local web_service_active=false
    
    if systemctl is-enabled --quiet disk2iso 2>/dev/null; then
        service_enabled=true
    fi
    if systemctl is-active --quiet disk2iso 2>/dev/null; then
        service_active=true
    fi
    if systemctl is-enabled --quiet disk2iso-web 2>/dev/null; then
        web_service_enabled=true
    fi
    if systemctl is-active --quiet disk2iso-web 2>/dev/null; then
        web_service_active=true
    fi
    
    # Frage ob Benutzer Einstellungen ändern möchte
    local reconfigure=false
    if use_whiptail; then
        if whiptail --title "Update-Optionen" \
            --yesno "Möchten Sie die Einstellungen während des Updates überprüfen/ändern?\n\nAktueller Status:\n  - disk2iso Service: $([ "$service_enabled" == "true" ] && echo "aktiviert" || echo "deaktiviert")\n  - disk2iso-web Service: $([ "$web_service_enabled" == "true" ] && echo "aktiviert" || echo "deaktiviert")\n\nJA: Einstellungen während Update anpassen\nNEIN: Nur Dateien aktualisieren (empfohlen)" \
            16 70 \
            --defaultno; then
            reconfigure=true
        fi
    fi
    
    # Stoppe laufende Services
    if [[ "$service_active" == "true" ]]; then
        systemctl stop disk2iso
        print_info "Service disk2iso gestoppt"
    fi
    if [[ "$web_service_active" == "true" ]]; then
        systemctl stop disk2iso-web
        print_info "Service disk2iso-web gestoppt"
    fi
    
    # Fortschrittsanzeige während Installation
    (
        echo "5" ; sleep 0.5
        echo "# Kopiere Haupt-Script..."
        cp -f "$SCRIPT_DIR/disk2iso.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/disk2iso.sh"
        
        echo "15" ; sleep 0.3
        echo "# Kopiere VERSION-Datei..."
        if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
            cp -f "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/"
        fi
        
        echo "30" ; sleep 0.3
        echo "# Aktualisiere Bibliotheken..."
        cp -rf "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR"/lib/*.sh
        
        echo "50" ; sleep 0.3
        echo "# Stelle Konfiguration wieder her..."
        if [[ -f "$config_backup" ]]; then
            cp "$config_backup" "$INSTALL_DIR/lib/config.sh"
        fi
        
        echo "65" ; sleep 0.3
        echo "# Aktualisiere Dokumentation..."
        if [[ -d "$SCRIPT_DIR/doc" ]]; then
            cp -rf "$SCRIPT_DIR/doc" "$INSTALL_DIR/"
        fi
        
        echo "75" ; sleep 0.3
        echo "# Aktualisiere Sprachdateien..."
        if [[ -d "$SCRIPT_DIR/lang" ]]; then
            cp -rf "$SCRIPT_DIR/lang" "$INSTALL_DIR/"
        fi
        
        echo "85" ; sleep 0.3
        echo "# Aktualisiere Service-Dateien..."
        if [[ -d "$SCRIPT_DIR/service" ]]; then
            cp -rf "$SCRIPT_DIR/service" "$INSTALL_DIR/"
        fi
        
        echo "90" ; sleep 0.3
        echo "# Kopiere Update-Skripte..."
        cp -f "$SCRIPT_DIR/install.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/install.sh"
        if [[ -f "$SCRIPT_DIR/uninstall.sh" ]]; then
            cp -f "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/"
            chmod +x "$INSTALL_DIR/uninstall.sh"
        fi
        
        echo "95"
        echo "# Räume auf..."
        rm -f "$config_backup"
        
        echo "100"
        echo "# Update abgeschlossen!"
        sleep 0.5
    ) | whiptail --title "Update wird durchgeführt" --gauge "Starte Update von v$INSTALLED_VERSION auf v$NEW_VERSION..." 10 70 0
    
    # Optional: Einstellungen anpassen
    if [[ "$reconfigure" == "true" ]]; then
        if use_whiptail; then
            # Service-Status ändern?
            if whiptail --title "Service-Konfiguration" \
                --yesno "disk2iso Service aktuell: $([ "$service_enabled" == "true" ] && echo "aktiviert" || echo "deaktiviert")\n\nMöchten Sie den Service-Status ändern?" \
                10 70; then
                
                if whiptail --title "Service aktivieren" \
                    --yesno "disk2iso Service aktivieren und starten?" \
                    8 50; then
                    systemctl enable disk2iso 2>/dev/null || true
                    systemctl start disk2iso 2>/dev/null || true
                    service_enabled=true
                    service_active=true
                    print_success "Service disk2iso aktiviert und gestartet"
                else
                    systemctl disable disk2iso 2>/dev/null || true
                    service_enabled=false
                    service_active=false
                    print_info "Service disk2iso deaktiviert"
                fi
            fi
        fi
    else
        # Starte Services mit altem Status neu
        if [[ "$service_enabled" == "true" ]] && [[ "$service_active" == "true" ]]; then
            systemctl start disk2iso
            print_success "Service disk2iso neu gestartet"
        fi
        if [[ "$web_service_enabled" == "true" ]] && [[ "$web_service_active" == "true" ]]; then
            systemctl start disk2iso-web
            print_success "Service disk2iso-web neu gestartet"
        fi
    fi
    
    # Prüfe fehlende Komponenten nach Update
    local missing_components=false
    local install_service_now=false
    local install_mqtt_now=false
    
    # Prüfe disk2iso.service
    if [[ ! -f "$SERVICE_FILE" ]]; then
        if use_whiptail; then
            if whiptail --title "Fehlende Komponente erkannt" \
                --yesno "Der disk2iso Service ist nicht installiert.\n\nMöchten Sie ihn jetzt einrichten?\n\nDies ermöglicht automatisches Starten beim Booten." \
                12 70; then
                install_service_now=true
                missing_components=true
            fi
        fi
    fi
    
    # Prüfe MQTT-Integration (mosquitto-clients)
    if ! command -v mosquitto_pub >/dev/null 2>&1; then
        if use_whiptail; then
            if whiptail --title "Optionale Komponente" \
                --yesno "MQTT-Integration ist nicht installiert.\n\nMQTT ermöglicht:\n• Status-Updates an Home Assistant\n• Fortschrittsanzeige in Echtzeit\n• Push-Benachrichtigungen\n\nMöchten Sie MQTT jetzt einrichten?" \
                14 70; then
                install_mqtt_now=true
                missing_components=true
            fi
        else
            print_info "MQTT-Integration ist nicht installiert"
            if ask_yes_no "MQTT jetzt einrichten?" "n"; then
                install_mqtt_now=true
                missing_components=true
            fi
        fi
    fi
    
    # Prüfe Web-Server (Python venv)
    if [[ ! -d "$INSTALL_DIR/venv" ]] || [[ ! -f "$INSTALL_DIR/venv/bin/flask" ]]; then
        if use_whiptail; then
            if whiptail --title "Optionale Komponente" \
                --yesno "Web-Server ist nicht installiert.\n\nWeb-Server bietet:\n• Status-Überwachung im Browser\n• Archiv-Verwaltung und Übersicht\n• Log-Viewer mit Live-Updates\n• Responsive Design\n\nMöchten Sie den Web-Server jetzt installieren?" \
                14 70; then
                install_web_now=true
                missing_components=true
            fi
        else
            print_info "Web-Server ist nicht installiert"
            if ask_yes_no "Web-Server jetzt installieren?" "n"; then
                install_web_now=true
                missing_components=true
            fi
        fi
    fi
    
    # Service jetzt installieren wenn gewünscht
    if [[ "$install_service_now" == "true" ]]; then
        # Frage Ausgabeverzeichnis
        local output_dir="/media/iso"
        if use_whiptail; then
            output_dir=$(whiptail --title "Ausgabeverzeichnis" \
                --inputbox "Ausgabeverzeichnis für ISOs:" \
                10 60 "/media/iso" 3>&1 1>&2 2>&3) || output_dir="/media/iso"
        fi
        
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
ExecStart=$INSTALL_DIR/disk2iso.sh -o $output_dir
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        # Aktualisiere config.sh
        if [[ -f "$INSTALL_DIR/lib/config.sh" ]]; then
            sed -i "s|DEFAULT_OUTPUT_DIR=.*|DEFAULT_OUTPUT_DIR=\"$output_dir\"|" "$INSTALL_DIR/lib/config.sh"
        fi
        
        # Erstelle Ausgabeverzeichnis mit Unterordnern
        mkdir -p "$output_dir"/{.log,.temp,audio,dvd,bd,data}
        chmod 755 "$output_dir"
        print_success "Ausgabeverzeichnis erstellt: $output_dir"
        
        systemctl daemon-reload
        systemctl enable disk2iso.service >/dev/null 2>&1
        systemctl start disk2iso.service >/dev/null 2>&1
        
        service_enabled=true
        service_active=true
        print_success "Service disk2iso installiert und gestartet"
    else
        # Service existiert bereits → Stelle sicher dass Ausgabeverzeichnis existiert
        if [[ -f "$SERVICE_FILE" ]]; then
            # Lese Ausgabeverzeichnis aus Service-Datei
            local output_dir=$(grep "ExecStart=" "$SERVICE_FILE" | sed -n 's/.*-o \([^ ]*\).*/\1/p')
            if [[ -z "$output_dir" ]]; then
                # Fallback: Lese aus config.sh
                output_dir=$(grep "DEFAULT_OUTPUT_DIR=" "$INSTALL_DIR/lib/config.sh" 2>/dev/null | cut -d'"' -f2)
            fi
            
            # Erstelle Verzeichnis falls es nicht existiert
            if [[ -n "$output_dir" ]] && [[ ! -d "$output_dir" ]]; then
                mkdir -p "$output_dir"/{.log,.temp,audio,dvd,bd,data}
                chmod 755 "$output_dir"
                print_success "Ausgabeverzeichnis erstellt: $output_dir"
            fi
        fi
    fi
    
    # MQTT jetzt installieren wenn gewünscht
    if [[ "$install_mqtt_now" == "true" ]]; then
        if use_whiptail; then
            local mqtt_broker=$(whiptail --title "MQTT Konfiguration" \
                --inputbox "Geben Sie die IP-Adresse des MQTT Brokers ein:\n(z.B. 192.168.20.10)" \
                10 60 3>&1 1>&2 2>&3)
            
            if [[ -n "$mqtt_broker" ]]; then
                # Optionale Authentifizierung
                local mqtt_user=""
                local mqtt_password=""
                if whiptail --title "MQTT Authentifizierung" \
                    --yesno "Benötigt der MQTT Broker Authentifizierung?" \
                    8 60; then
                    mqtt_user=$(whiptail --title "MQTT Benutzer" \
                        --inputbox "Benutzername:" 8 60 3>&1 1>&2 2>&3)
                    mqtt_password=$(whiptail --title "MQTT Passwort" \
                        --passwordbox "Passwort:" 8 60 3>&1 1>&2 2>&3)
                fi
                
                # Installiere mosquitto-clients
                {
                    echo "10"
                    echo "XXX"
                    echo "Installiere mosquitto-clients..."
                    echo "XXX"
                    apt-get update >/dev/null 2>&1
                    echo "50"
                    apt-get install -y mosquitto-clients >/dev/null 2>&1
                    echo "90"
                    
                    # Aktualisiere config.sh
                    local escaped_broker=$(echo "$mqtt_broker" | sed 's/[\/&]/\\&/g')
                    sed -i "s|^MQTT_ENABLED=.*|MQTT_ENABLED=true|" "$INSTALL_DIR/lib/config.sh"
                    sed -i "s|^MQTT_BROKER=.*|MQTT_BROKER=\"$escaped_broker\"|" "$INSTALL_DIR/lib/config.sh"
                    
                    if [[ -n "$mqtt_user" ]]; then
                        local escaped_user=$(echo "$mqtt_user" | sed 's/[\/&]/\\&/g')
                        local escaped_password=$(echo "$mqtt_password" | sed 's/[\/&]/\\&/g')
                        sed -i "s|^MQTT_USER=.*|MQTT_USER=\"$escaped_user\"|" "$INSTALL_DIR/lib/config.sh"
                        sed -i "s|^MQTT_PASSWORD=.*|MQTT_PASSWORD=\"$escaped_password\"|" "$INSTALL_DIR/lib/config.sh"
                    fi
                    
                    echo "XXX"
                    echo "MQTT-Integration konfiguriert"
                    echo "XXX"
                    echo "100"
                    sleep 0.5
                } | whiptail --title "MQTT Installation" \
                    --gauge "Installiere MQTT-Unterstützung..." 8 70 0
                
                print_success "MQTT-Integration installiert: $mqtt_broker"
            fi
        else
            # Text-Modus
            read -p "MQTT Broker IP-Adresse: " mqtt_broker
            if [[ -n "$mqtt_broker" ]]; then
                local mqtt_user="" mqtt_password=""
                if ask_yes_no "Benötigt Authentifizierung?" "n"; then
                    read -p "Benutzername: " mqtt_user
                    read -sp "Passwort: " mqtt_password; echo ""
                fi
                print_info "Installiere mosquitto-clients..."
                apt-get update >/dev/null 2>&1
                apt-get install -y mosquitto-clients >/dev/null 2>&1
                sed -i "s|^MQTT_ENABLED=.*|MQTT_ENABLED=true|" "$INSTALL_DIR/lib/config.sh"
                sed -i "s|^MQTT_BROKER=.*|MQTT_BROKER=\"$(echo "$mqtt_broker" | sed 's/[\/&]/\\&/g')\"|" "$INSTALL_DIR/lib/config.sh"
                [[ -n "$mqtt_user" ]] && sed -i "s|^MQTT_USER=.*|MQTT_USER=\"$(echo "$mqtt_user" | sed 's/[\/&]/\\&/g')\"|" "$INSTALL_DIR/lib/config.sh"
                [[ -n "$mqtt_password" ]] && sed -i "s|^MQTT_PASSWORD=.*|MQTT_PASSWORD=\"$(echo "$mqtt_password" | sed 's/[\/&]/\\&/g')\"|" "$INSTALL_DIR/lib/config.sh"
                print_success "MQTT installiert: $mqtt_broker"
            fi
        fi
    fi
    
    # Web-Server jetzt installieren wenn gewünscht
    if [[ "$install_web_now" == "true" ]]; then
        INSTALL_WEB_SERVER=true
        
        # Führe Web-Server Installation aus (direkt inline für Update-Modus)
        {
            echo "0"
            echo "XXX"
            echo "Prüfe Python-Abhängigkeiten..."
            echo "XXX"
            
            # Installiere Python3 falls nötig
            if ! command -v python3 >/dev/null 2>&1; then
                echo "20"
                echo "XXX"
                echo "Installiere Python3 und pip..."
                echo "XXX"
                apt-get update >/dev/null 2>&1
                apt-get install -y python3 python3-pip python3-venv >/dev/null 2>&1
            fi
            
            # Stelle sicher dass python3-venv installiert ist (Debian/Ubuntu brauchen separates Paket)
            if ! dpkg -l | grep -q python3.*-venv; then
                echo "25"
                echo "XXX"
                echo "Installiere python3-venv..."
                echo "XXX"
                apt-get install -y python3-venv >/dev/null 2>&1
            fi
            
            # Erstelle Virtual Environment
            echo "40"
            echo "XXX"
            echo "Erstelle Python Virtual Environment..."
            echo "XXX"
            python3 -m venv "$INSTALL_DIR/venv" >/dev/null 2>&1
            
            # Installiere Flask
            echo "60"
            echo "XXX"
            echo "Installiere Flask..."
            echo "XXX"
            "$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade pip >/dev/null 2>&1
            "$INSTALL_DIR/venv/bin/pip" install --quiet flask >/dev/null 2>&1
            
            # Erstelle Verzeichnisstruktur
            echo "80"
            echo "XXX"
            echo "Erstelle Verzeichnisstruktur..."
            echo "XXX"
            mkdir -p "$INSTALL_DIR/www/templates"
            mkdir -p "$INSTALL_DIR/www/static/css"
            mkdir -p "$INSTALL_DIR/www/static/js"
            mkdir -p "$INSTALL_DIR/www/logs"
            chmod -R 755 "$INSTALL_DIR/www" 2>/dev/null || true
            chmod -R 755 "$INSTALL_DIR/venv" 2>/dev/null || true
            
            # Erstelle requirements.txt
            cat > "$INSTALL_DIR/www/requirements.txt" <<'EOFREQ'
# disk2iso Web-Server Dependencies
flask>=2.0.0
EOFREQ
            
            echo "100"
            echo "XXX"
            echo "Web-Server installiert!"
            echo "XXX"
            sleep 0.5
        } | whiptail --title "Web-Server Installation" \
            --gauge "Installiere Web-Server-Komponenten..." 8 70 0
        
        print_success "Web-Server installiert (Python/Flask)"
        print_info "Hinweis: Flask app.py noch nicht vorhanden (Phase 2)"
    fi
    
    # Zeige Update-Zusammenfassung
    if use_whiptail; then
        local summary="disk2iso wurde erfolgreich aktualisiert!

Version: $INSTALLED_VERSION → $NEW_VERSION

Alle Einstellungen wurden beibehalten.

Service-Status:
  - disk2iso: $([ "$service_enabled" == "true" ] && echo "aktiviert" || echo "deaktiviert") $([ "$service_active" == "true" ] && echo "(läuft)" || echo "(gestoppt)") 
  - disk2iso-web: $([ "$web_service_enabled" == "true" ] && echo "aktiviert" || echo "deaktiviert") $([ "$web_service_active" == "true" ] && echo "(läuft)" || echo "(gestoppt)")

Pfad: $INSTALL_DIR

Hinweis: Überprüfen Sie die Dokumentation für neue Features!"
        whiptail --title "Update Abgeschlossen" --msgbox "$summary" 20 70
    else
        print_header "UPDATE ABGESCHLOSSEN"
        print_success "disk2iso wurde aktualisiert: $INSTALLED_VERSION → $NEW_VERSION"
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
    
    # Kopiere VERSION-Datei
    if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
        cp -f "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/"
    fi
    
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
    
    # Erstelle API-Verzeichnis für JSON-Daten (Live-Status)
    mkdir -p "$INSTALL_DIR/api"
    chmod 755 "$INSTALL_DIR/api"
    
    # Kopiere initiale JSON-Dateien falls vorhanden
    if [[ -d "$SCRIPT_DIR/api" ]] && [[ -n "$(ls -A "$SCRIPT_DIR/api" 2>/dev/null)" ]]; then
        cp -rf "$SCRIPT_DIR/api/"*.json "$INSTALL_DIR/api/" 2>/dev/null || true
        chmod 644 "$INSTALL_DIR/api/"*.json 2>/dev/null || true
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
            
            # Stelle sicher dass python3-venv installiert ist (Debian/Ubuntu)
            if ! dpkg -l | grep -q python3.*-venv; then
                echo "XXX"
                echo "Installiere python3-venv..."
                echo "XXX"
                echo "30"
                apt-get install -y -qq python3-venv >/dev/null 2>&1 || true
            fi
            
            # Erstelle virtuelles Environment
            echo "XXX"
            echo "Erstelle Python Virtual Environment..."
            echo "XXX"
            echo "40"
            
            python3 -m venv "$INSTALL_DIR/venv" >/dev/null 2>&1
            
            # Installiere Flask und Gunicorn
            echo "XXX"
            echo "Installiere Flask (kann 1-2 Minuten dauern)..."
            echo "XXX"
            echo "60"
            
            "$INSTALL_DIR/venv/bin/pip" install --upgrade pip --quiet >/dev/null 2>&1
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
    
    # Installiere Web-Server Service (disk2iso-web)
    if [[ -f "$INSTALL_DIR/service/disk2iso-web.service" ]]; then
        cp "$INSTALL_DIR/service/disk2iso-web.service" /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable disk2iso-web.service >/dev/null 2>&1
        systemctl start disk2iso-web.service >/dev/null 2>&1
        
        print_success "Web-Server Service installiert und gestartet"
        print_info "  Zugriff: http://$(hostname -I | awk '{print $1}'):8080"
    fi
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
        IS_REPAIR=false
    else
        # UPDATE oder REPARATUR gewählt
        if [[ "$IS_REPAIR" == "true" ]]; then
            perform_repair
            # perform_repair beendet das Script mit exit 0
        elif [[ "$IS_UPDATE" == "true" ]]; then
            perform_update
            # perform_update beendet das Script mit exit 0
        fi
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
