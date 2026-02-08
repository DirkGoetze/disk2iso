#!/bin/bash
################################################################################
# disk2iso v1.3.0 - Installation Script
# Filepath: install.sh
#
# Beschreibung:
#   Wizard-basierte Installation von disk2iso
#   - Installations-Wizard mit dialog
#   - Optionale systemd Service-Konfiguration
#
# Version: 1.3.0
# Datum: 07.02.2026
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
# Services werden immer installiert (nicht mehr optional)
SERVICE_OUTPUT_DIR="/media/iso"

# Versions- und Update-Variablen
NEW_VERSION="1.2.0"  # Wird aus VERSION-Datei gelesen
INSTALLED_VERSION=""
IS_REPAIR=false
IS_UPDATE=false

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================


################################################################################
# AUSGABEVERZEICHNIS - Helper Funktion
################################################################################

# Erstelle Ausgabeverzeichnis mit korrekten Berechtigungen
create_output_directory() {
    local output_dir="$1"
    [[ -z "$output_dir" ]] && return 1
    
    # Erstelle Basis-Verzeichnisstruktur
    # Hinweis: audio/, dvd/, bd/ werden zur Laufzeit von optionalen Modulen erstellt
    mkdir -p "$output_dir"/{.log,.temp/mountpoints,data} || return 1
    
    # Setze Berechtigungen
    chmod 755 "$output_dir"
    chmod 755 "$output_dir"/data 2>/dev/null
    chmod 777 "$output_dir"/.log 2>/dev/null
    chmod 777 "$output_dir"/.temp 2>/dev/null
    chmod 777 "$output_dir"/.temp/mountpoints 2>/dev/null
    
    return 0
}

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
use_dialog() {
    command -v dialog >/dev/null 2>&1
}

ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    
    if use_dialog; then
        if [[ "$default" == "n" ]]; then
            dialog --title "disk2iso Installation" --defaultno --yesno "$question" 10 60
        else
            dialog --title "disk2iso Installation" --yesno "$question" 10 60
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
    
    if use_dialog; then
        dialog --title "$title" --msgbox "$message" 20 70
    else
        echo -e "\n${BLUE}$title${NC}"
        echo "$message"
        read -p "Drücken Sie Enter zum Fortfahren..."
    fi
}

# ============================================================================
# CONFIG MERGE FUNCTION
# ============================================================================

# Intelligentes Merge von alter und neuer Konfiguration
# Parameter: $1 = Pfad zur alten Config, $2 = Pfad zur neuen Config (Template)
merge_config() {
    local old_config="$1"
    local new_config="$2"
    
    if [[ ! -f "$old_config" ]]; then
        print_info "Keine alte Konfiguration gefunden - nutze neue Template"
        return 0
    fi
    
    if [[ ! -f "$new_config" ]]; then
        print_error "Neue Config-Template nicht gefunden: $new_config"
        return 1
    fi
    
    print_info "Merge Konfigurationen: alt → neu"
    
    # Extrahiere alle Einstellungen aus alter Config (ignoriere Kommentare/Leerzeilen)
    local temp_values="/tmp/disk2iso-config-values-$$.tmp"
    grep -E '^[A-Z_]+=' "$old_config" | grep -v '^#' > "$temp_values" 2>/dev/null || true
    
    # Aktualisiere neue Config mit alten Werten
    while IFS='=' read -r key value; do
        [[ -z "$key" ]] && continue
        
        # Prüfe ob Key in neuer Config existiert
        if grep -q "^${key}=" "$new_config"; then
            # Ersetze Wert in neuer Config (behalte Quotes-Style)
            sed -i "s|^${key}=.*|${key}=${value}|" "$new_config"
            print_info "  ✓ Übernehme: $key"
        else
            print_warning "  ⚠ Überspringe veralteten Parameter: $key"
        fi
    done < "$temp_values"
    
    rm -f "$temp_values"
    
    # Zeige neue Einstellungen an
    print_info "Neue Einstellungen in dieser Version:"
    local new_keys=$(grep -E '^[A-Z_]+=' "$new_config" | cut -d'=' -f1)
    local found_new=false
    
    for key in $new_keys; do
        if ! grep -q "^${key}=" "$old_config" 2>/dev/null; then
            local value=$(grep "^${key}=" "$new_config" | cut -d'=' -f2-)
            print_info "  + $key=$value"
            found_new=true
        fi
    done
    
    [[ "$found_new" == "false" ]] && print_info "  (keine neuen Einstellungen)"
    
    return 0
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
    elif [[ -f "$INSTALL_DIR/services/disk2iso/daemon.sh" ]]; then
        # Fallback für alte Installationen ohne VERSION-Datei
        version=$(grep -m1 "^# disk2iso v" "$INSTALL_DIR/services/disk2iso/daemon.sh" 2>/dev/null | awk '{print $3}' | tr -d 'v' || echo "unbekannt")
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
    
    if use_dialog; then
        local info=""
        local action_label=""
        local menu_title=""
        
        if [[ "$action_mode" == "REPARATUR" ]]; then
            menu_title="Eine bestehende disk2iso Installation wurde gefunden!

Installierter Pfad: $INSTALL_DIR
Installierte Version: ${version}
Neue Version: ${NEW_VERSION}

➜ GLEICHE VERSION ERKANNT"
            action_label="Reparatur"
        else
            menu_title="Eine bestehende disk2iso Installation wurde gefunden!

Installierter Pfad: $INSTALL_DIR
Installierte Version: ${version}
Neue Version: ${NEW_VERSION}

➜ UPDATE VERFÜGBAR"
            action_label="Update"
        fi
        
        local choice
        choice=$(dialog --title "Bestehende Installation gefunden" \
            --menu "$menu_title" 22 75 2 \
            "1" "$action_label (Empfohlen)" \
            "2" "Neuinstallation" \
            2>&1 >/dev/tty)
        
        local exit_code=$?
        
        # Abbruch bei ESC oder Cancel
        if [[ $exit_code -ne 0 ]]; then
            return 0
        fi
        
        if [[ "$choice" == "1" ]]; then
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
            if dialog --title "Neuinstallation bestätigen" \
                --defaultno \
                --yesno "WARNUNG: Alle Einstellungen gehen verloren!\n\nSind Sie sicher, dass Sie eine komplette Neuinstallation durchführen möchten?\n\nDies kann NICHT rückgängig gemacht werden!" \
                14 60; then
                
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
    if [[ -f "$INSTALL_DIR/conf/disk2iso.conf" ]]; then
        cp "$INSTALL_DIR/conf/disk2iso.conf" "$config_backup"
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
        echo "# Kopiere VERSION-Datei..."
        if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
            cp -f "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/"
        fi
        
        echo "30" ; sleep 0.3
        
        echo "50" ; sleep 0.3
        echo "# Kopiere Bibliotheken..."
        cp -rf "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR"/lib/*.sh
        
        echo "60" ; sleep 0.3
        echo "# Kopiere Konfiguration..."
        mkdir -p "$INSTALL_DIR/conf"
        cp -f "$SCRIPT_DIR/conf/disk2iso.conf" "$INSTALL_DIR/conf/"
        cp -f "$SCRIPT_DIR/conf/"*.ini "$INSTALL_DIR/conf/" 2>/dev/null || true
        
        echo "70" ; sleep 0.3
        echo "# Merge Konfigurationen..."
        if [[ -f "$config_backup" ]]; then
            merge_config "$config_backup" "$INSTALL_DIR/conf/disk2iso.conf"
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
        if [[ -f "$SCRIPT_DIR/LICENSE" ]]; then
            cp -f "$SCRIPT_DIR/LICENSE" "$INSTALL_DIR/"
        fi
        
        echo "90" ; sleep 0.3
        echo "# Erstelle Dokumentations-Symlink..."
        if [[ -d "$INSTALL_DIR/doc" ]]; then
            mkdir -p "$INSTALL_DIR/services/disk2iso-web/static"`r`n            ln -sf "../../../doc" "$INSTALL_DIR/services/disk2iso-web/static/docs" 2>/dev/null || true
        fi
        
        echo "100"
        echo "# Reparatur abgeschlossen!"
        sleep 0.5
    ) | dialog --title "Reparatur läuft" --gauge "Starte Reparatur..." 10 70 0
    
    # Prüfe fehlende Komponenten und biete Installation an
    local missing_components=false
    local install_service_now=false
    local install_web_now=false
    
    # Prüfe disk2iso.service
    if [[ ! -f "$SERVICE_FILE" ]]; then
        if use_dialog; then
            if dialog --title "Fehlende Komponente erkannt" \
                --yesno "Der disk2iso Service ist nicht installiert.\n\nMöchten Sie ihn jetzt einrichten?\n\nDies ermöglicht automatisches Starten beim Booten." \
                12 70; then
                install_service_now=true
                missing_components=true
            fi
        fi
    fi
    
    # Prüfe Web-Server (Python venv)
    if [[ ! -d "$INSTALL_DIR/venv" ]] || [[ ! -f "$INSTALL_DIR/venv/bin/flask" ]]; then
        if use_dialog; then
            if dialog --title "Optionale Komponente" \
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
        if use_dialog; then
            output_dir=$(dialog --title "Ausgabeverzeichnis" \
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
ExecStart=$INSTALL_DIR/services/disk2iso/daemon.sh -o $output_dir
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        # Aktualisiere config.sh
        if [[ -f "$INSTALL_DIR/conf/disk2iso.conf" ]]; then
            sed -i "s|DEFAULT_OUTPUT_DIR=.*|DEFAULT_OUTPUT_DIR=\"$output_dir\"|" "$INSTALL_DIR/conf/disk2iso.conf"
        fi
        
        # Erstelle Ausgabeverzeichnis mit Unterordnern
        create_output_directory "$output_dir"
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
                output_dir=$(grep "DEFAULT_OUTPUT_DIR=" "$INSTALL_DIR/conf/disk2iso.conf" 2>/dev/null | cut -d'"' -f2)
            fi
            
            # Erstelle Verzeichnis falls es nicht existiert
            if [[ -n "$output_dir" ]] && [[ ! -d "$output_dir" ]]; then
                create_output_directory "$output_dir"
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
            mkdir -p "$INSTALL_DIR/services/disk2iso-web/templates"
            mkdir -p "$INSTALL_DIR/services/disk2iso-web/static/css"
            mkdir -p "$INSTALL_DIR/services/disk2iso-web/static/js"
            mkdir -p "$INSTALL_DIR/services/disk2iso-web/logs"
            chmod -R 755 "$INSTALL_DIR/services" 2>/dev/null || true
            chmod -R 755 "$INSTALL_DIR/venv" 2>/dev/null || true
            
            # Erstelle requirements.txt
            cat > "$INSTALL_DIR/services/disk2iso-web/requirements.txt" <<'EOFREQ'
# disk2iso Web-Server Dependencies
flask>=2.0.0
EOFREQ
            
            echo "100"
            echo "XXX"
            echo "Web-Server installiert!"
            echo "XXX"
            sleep 0.5
        } | dialog --title "Web-Server Installation" \
            --gauge "Installiere Web-Server-Komponenten..." 8 70 0
        
        print_success "Web-Server installiert (Python/Flask)"
        print_info "Hinweis: Flask app.py noch nicht vorhanden (Phase 2)"
    fi
    
    # Zeige Reparatur-Zusammenfassung
    if use_dialog; then
        dialog --title "Reparatur Abgeschlossen" --msgbox \
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
    if [[ -f "$INSTALL_DIR/conf/disk2iso.conf" ]]; then
        cp "$INSTALL_DIR/conf/disk2iso.conf" "$config_backup"
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
    if use_dialog; then
        if dialog --title "Update-Optionen" \
            --defaultno \
            --yesno "Möchten Sie die Einstellungen während des Updates überprüfen/ändern?\n\nAktueller Status:\n  - disk2iso Service: $([ "$service_enabled" == "true" ] && echo "aktiviert" || echo "deaktiviert")\n  - disk2iso-web Service: $([ "$web_service_enabled" == "true" ] && echo "aktiviert" || echo "deaktiviert")\n\nJA: Einstellungen während Update anpassen\nNEIN: Nur Dateien aktualisieren (empfohlen)" \
            16 70; then
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
        echo "# Kopiere VERSION-Datei..."
        if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
            cp -f "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/"
        fi
        
        echo "15" ; sleep 0.3
        
        echo "30" ; sleep 0.3
        echo "# Aktualisiere Bibliotheken..."
        cp -rf "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR"/lib/*.sh
        
        echo "40" ; sleep 0.3
        echo "# Kopiere neue Konfiguration..."
        mkdir -p "$INSTALL_DIR/conf"
        cp -f "$SCRIPT_DIR/conf/disk2iso.conf" "$INSTALL_DIR/conf/"
        cp -f "$SCRIPT_DIR/conf/"*.ini "$INSTALL_DIR/conf/" 2>/dev/null || true
        
        echo "50" ; sleep 0.3
        echo "# Merge Konfigurationen..."
        if [[ -f "$config_backup" ]]; then
            merge_config "$config_backup" "$INSTALL_DIR/conf/disk2iso.conf"
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
        if [[ -f "$SCRIPT_DIR/LICENSE" ]]; then
            cp -f "$SCRIPT_DIR/LICENSE" "$INSTALL_DIR/"
        fi
        
        echo "80" ; sleep 0.3
        echo "# Erstelle Dokumentations-Symlink..."
        if [[ -d "$INSTALL_DIR/doc" ]]; then
            mkdir -p "$INSTALL_DIR/services/disk2iso-web/static"
            ln -sf "../../../doc" "$INSTALL_DIR/services/disk2iso-web/static/docs" 2>/dev/null || true
        fi
        
        echo "85" ; sleep 0.3
        echo "# Aktualisiere Service-Dateien..."
        if [[ -d "$SCRIPT_DIR/services" ]]; then
            cp -rf "$SCRIPT_DIR/services" "$INSTALL_DIR/"
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
    ) | dialog --title "Update wird durchgeführt" --gauge "Starte Update von v$INSTALLED_VERSION auf v$NEW_VERSION..." 10 70 0
    
    # Optional: Einstellungen anpassen
    if [[ "$reconfigure" == "true" ]]; then
        if use_dialog; then
            # Service-Status ändern?
            if dialog --title "Service-Konfiguration" \
                --yesno "disk2iso Service aktuell: $([ "$service_enabled" == "true" ] && echo "aktiviert" || echo "deaktiviert")\n\nMöchten Sie den Service-Status ändern?" \
                10 70; then
                
                if dialog --title "Service aktivieren" \
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
    
    # Prüfe disk2iso.service
    if [[ ! -f "$SERVICE_FILE" ]]; then
        if use_dialog; then
            if dialog --title "Fehlende Komponente erkannt" \
                --yesno "Der disk2iso Service ist nicht installiert.\n\nMöchten Sie ihn jetzt einrichten?\n\nDies ermöglicht automatisches Starten beim Booten." \
                12 70; then
                install_service_now=true
                missing_components=true
            fi
        fi
    fi
    
    # Prüfe Web-Server (Python venv)
    if [[ ! -d "$INSTALL_DIR/venv" ]] || [[ ! -f "$INSTALL_DIR/venv/bin/flask" ]]; then
        if use_dialog; then
            if dialog --title "Optionale Komponente" \
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
        if use_dialog; then
            output_dir=$(dialog --title "Ausgabeverzeichnis" \
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
ExecStart=$INSTALL_DIR/services/disk2iso/daemon.sh -o $output_dir
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        # Aktualisiere config.sh
        if [[ -f "$INSTALL_DIR/conf/disk2iso.conf" ]]; then
            sed -i "s|DEFAULT_OUTPUT_DIR=.*|DEFAULT_OUTPUT_DIR=\"$output_dir\"|" "$INSTALL_DIR/conf/disk2iso.conf"
        fi
        
        # Erstelle Ausgabeverzeichnis mit Unterordnern
        create_output_directory "$output_dir"
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
                output_dir=$(grep "DEFAULT_OUTPUT_DIR=" "$INSTALL_DIR/conf/disk2iso.conf" 2>/dev/null | cut -d'"' -f2)
            fi
            
            # Erstelle Verzeichnis falls es nicht existiert
            if [[ -n "$output_dir" ]] && [[ ! -d "$output_dir" ]]; then
                create_output_directory "$output_dir"
                print_success "Ausgabeverzeichnis erstellt: $output_dir"
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
            mkdir -p "$INSTALL_DIR/services/disk2iso-web/templates"
            mkdir -p "$INSTALL_DIR/services/disk2iso-web/static/css"
            mkdir -p "$INSTALL_DIR/services/disk2iso-web/static/js"
            mkdir -p "$INSTALL_DIR/services/disk2iso-web/logs"
            chmod -R 755 "$INSTALL_DIR/services" 2>/dev/null || true
            chmod -R 755 "$INSTALL_DIR/venv" 2>/dev/null || true
            
            # Erstelle requirements.txt
            cat > "$INSTALL_DIR/services/disk2iso-web/requirements.txt" <<'EOFREQ'
# disk2iso Web-Server Dependencies
flask>=2.0.0
EOFREQ
            
            echo "100"
            echo "XXX"
            echo "Web-Server installiert!"
            echo "XXX"
            sleep 0.5
        } | dialog --title "Web-Server Installation" \
            --gauge "Installiere Web-Server-Komponenten..." 8 70 0
        
        print_success "Web-Server installiert (Python/Flask)"
        print_info "Hinweis: Flask app.py noch nicht vorhanden (Phase 2)"
    fi
    
    # Zeige Update-Zusammenfassung
    if use_dialog; then
        local summary="disk2iso wurde erfolgreich aktualisiert!

Version: $INSTALLED_VERSION → $NEW_VERSION

Alle Einstellungen wurden beibehalten.

Service-Status:
  - disk2iso: $([ "$service_enabled" == "true" ] && echo "aktiviert" || echo "deaktiviert") $([ "$service_active" == "true" ] && echo "(läuft)" || echo "(gestoppt)") 
  - disk2iso-web: $([ "$web_service_enabled" == "true" ] && echo "aktiviert" || echo "deaktiviert") $([ "$web_service_active" == "true" ] && echo "(läuft)" || echo "(gestoppt)")

Pfad: $INSTALL_DIR

Hinweis: Überprüfen Sie die Dokumentation für neue Features!"
        dialog --title "Update Abgeschlossen" --msgbox "$summary" 20 70
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

disk2iso ist ein Tool zur automatischen Erstellung von ISO-Images von optischen Medien.

Basis-Funktionen:
• Automatische Erkennung eingelegter Discs
• Kopieren als ISO-Image
• MD5-Checksummen für Datenintegrität
• Web-Interface zur Überwachung
• Optionale Autostart-Funktion

Der Wizard führt Sie durch die Installation in einfachen Schritten.

Möchten Sie fortfahren?"

    if use_dialog; then
        if dialog --title "disk2iso Installation - Seite 1/6" \
            --yesno "$info" 20 70; then
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
    
    if use_dialog; then
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
        } | dialog --title "disk2iso Installation - Seite 2/6" \
            --gauge "Vorbereite Installation..." 8 70 0
    else
        print_header "INSTALLATION BASIS-PAKETE"
        for pkg_info in "${packages[@]}"; do
            IFS=':' read -r package description <<< "$pkg_info"
            install_package "$package" "$description" || true
        done
    fi
}

# Seite 3: Service-Installation
wizard_page_service_setup() {
    if use_dialog; then
        # Ausgabeverzeichnis abfragen
        SERVICE_OUTPUT_DIR=$(dialog --title "disk2iso Installation - Seite 3/4" \
            --inputbox "Geben Sie das Verzeichnis ein, in dem die ISOs gespeichert werden sollen:\n\nHinweis: Es werden automatisch Unterordner erstellt:\n  • data/    (ISO-Images)\n  • .log/    (Log-Dateien)\n  • .temp/   (Temporäre Dateien)" \
            16 70 "/media/iso" 3>&1 1>&2 2>&3)
        
        if [ -z "$SERVICE_OUTPUT_DIR" ]; then
            SERVICE_OUTPUT_DIR="/media/iso"
        fi
    else
        read -p "Ausgabe-Verzeichnis für ISOs [/media/iso]: " input_dir
        SERVICE_OUTPUT_DIR=${input_dir:-/media/iso}
    fi
}

# Seite 4: Abschluss
wizard_page_complete() {
    local info="Installation erfolgreich abgeschlossen!

disk2iso läuft jetzt auf Ihrem System.

Web-Interface:
http://$(hostname -I | awk '{print $1}'):8080"

    if use_dialog; then
        dialog --title "disk2iso Installation - Seite 4/4" \
            --msgbox "$info" 12 70
    else
        echo "$info"
    fi
}

# ============================================================================
# DISK2ISO INSTALLATION
# ============================================================================

install_disk2iso_files() {
    # Prüfe ob Quell-Dateien existieren
    if [[ ! -f "$SCRIPT_DIR/services/disk2iso/daemon.sh" ]]; then
        print_error "services/disk2iso/daemon.sh nicht gefunden in $SCRIPT_DIR"
        exit 1
    fi
    
    if [[ ! -d "$SCRIPT_DIR/lib" ]]; then
        print_error "lib Verzeichnis nicht gefunden in $SCRIPT_DIR"
        exit 1
    fi
    
    # Erstelle Installationsverzeichnis
    mkdir -p "$INSTALL_DIR"
    
    # Kopiere VERSION-Datei
    if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
        cp -f "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/"
    fi
    
    # Kopiere Library
    cp -rf "$SCRIPT_DIR/lib" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR"/lib/*.sh
    
    # Kopiere Konfiguration
    mkdir -p "$INSTALL_DIR/conf"
    cp -f "$SCRIPT_DIR/conf/disk2iso.conf" "$INSTALL_DIR/conf/"
    cp -f "$SCRIPT_DIR/conf/"*.ini "$INSTALL_DIR/conf/" 2>/dev/null || true
    
    # Kopiere Dokumentation (falls vorhanden)
    if [[ -d "$SCRIPT_DIR/doc" ]]; then
        cp -rf "$SCRIPT_DIR/doc" "$INSTALL_DIR/"
    fi
    
    # Kopiere Sprachdateien (falls vorhanden)
    if [[ -d "$SCRIPT_DIR/lang" ]]; then
        cp -rf "$SCRIPT_DIR/lang" "$INSTALL_DIR/"
    fi
    
    # Kopiere LICENSE (falls vorhanden)
    if [[ -f "$SCRIPT_DIR/LICENSE" ]]; then
        cp -f "$SCRIPT_DIR/LICENSE" "$INSTALL_DIR/"
    fi
    
    # Kopiere Service-Dateien (falls vorhanden)
    if [[ -d "$SCRIPT_DIR/services" ]]; then
        cp -rf "$SCRIPT_DIR/services" "$INSTALL_DIR/"
        # Setze Ausführungsrechte für Service-Skripte
        chmod +x "$INSTALL_DIR/services/disk2iso/daemon.sh" 2>/dev/null || true
        chmod +x "$INSTALL_DIR/services/disk2iso-updater/updater.sh" 2>/dev/null || true
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
    
    # Erstelle Symlink für Dokumentation im Web-Interface
    # services/disk2iso-web/static/docs -> ../../../doc (zeigt auf /opt/disk2iso/doc)
    if [[ -d "$INSTALL_DIR/doc" ]]; then
        mkdir -p "$INSTALL_DIR/services/disk2iso-web/static"
        ln -sf "../../../doc" "$INSTALL_DIR/services/disk2iso-web/static/docs" 2>/dev/null || true
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
    ln -sf "$INSTALL_DIR/services/disk2iso/daemon.sh" "$BIN_LINK"
}

# Konfiguriere und installiere alle Services (disk2iso, disk2iso-web, disk2iso-updater)
configure_all_services() {
    local output_dir="${SERVICE_OUTPUT_DIR:-/media/iso}"
    
    if use_dialog; then
        {
            # Schritt 1: Ausgabeverzeichnis erstellen (17%)
            echo "0"
            echo "XXX"
            echo "Erstelle Ausgabeverzeichnis..."
            echo "XXX"
            create_output_directory "$output_dir"
            sed -i "s|DEFAULT_OUTPUT_DIR=.*|DEFAULT_OUTPUT_DIR=\"$output_dir\"|" "$INSTALL_DIR/conf/disk2iso.conf"
            sleep 0.3
            
            # Schritt 2: disk2iso Service einrichten (33%)
            echo "17"
            echo "XXX"
            echo "Richte disk2iso Service ein..."
            echo "XXX"
            cp -f "$SCRIPT_DIR/services/disk2iso.service" /etc/systemd/system/
            systemctl daemon-reload
            systemctl enable disk2iso.service >/dev/null 2>&1
            systemctl start disk2iso.service
            sleep 0.5
            
            # Schritt 3: Python/Flask vorbereiten (50%)
            echo "33"
            echo "XXX"
            echo "Installiere Web-Server Abhängigkeiten..."
            echo "XXX"
            
            # Python installieren falls nötig
            if ! command -v python3 >/dev/null 2>&1; then
                apt-get install -y -qq python3 python3-pip python3-venv >/dev/null 2>&1 || true
            fi
            
            # Erstelle venv falls nicht vorhanden
            if [[ ! -d "$INSTALL_DIR/venv" ]]; then
                python3 -m venv "$INSTALL_DIR/venv" >/dev/null 2>&1
                "$INSTALL_DIR/venv/bin/pip" install --upgrade pip --quiet >/dev/null 2>&1
                "$INSTALL_DIR/venv/bin/pip" install flask --quiet >/dev/null 2>&1
            fi
            sleep 0.3
            
            # Schritt 4: Web-Service einrichten (67%)
            echo "50"
            echo "XXX"
            echo "Richte Web-Server Service ein..."
            echo "XXX"
            cp -f "$SCRIPT_DIR/services/disk2iso-web.service" /etc/systemd/system/
            systemctl daemon-reload
            systemctl enable disk2iso-web.service >/dev/null 2>&1
            systemctl start disk2iso-web.service
            sleep 0.5
            
            # Schritt 5: Updater-Service einrichten (83%)
            echo "67"
            echo "XXX"
            echo "Richte API-Updater ein..."
            echo "XXX"
            cp -f "$SCRIPT_DIR/services/disk2iso-updater.service" /etc/systemd/system/
            cp -f "$SCRIPT_DIR/services/disk2iso-updater.timer" /etc/systemd/system/
            systemctl daemon-reload
            systemctl enable disk2iso-updater.timer >/dev/null 2>&1
            sleep 0.3
            
            # Schritt 6: Updater-Timer starten (100%)
            echo "83"
            echo "XXX"
            echo "Starte API-Updater Timer..."
            echo "XXX"
            systemctl start disk2iso-updater.timer
            sleep 0.3
            
            echo "100"
        } | dialog --title "disk2iso Installation - Seite 3/4" \
            --gauge "Installiere Services..." 8 70 0
    else
        # Text-Modus
        print_success "Erstelle Ausgabeverzeichnis: $output_dir"
        create_output_directory "$output_dir"
        sed -i "s|DEFAULT_OUTPUT_DIR=.*|DEFAULT_OUTPUT_DIR=\"$output_dir\"|" "$INSTALL_DIR/conf/disk2iso.conf"
        
        print_success "Installiere disk2iso Service..."
        cp -f "$SCRIPT_DIR/services/disk2iso.service" /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable disk2iso.service >/dev/null 2>&1
        systemctl start disk2iso.service
        
        print_success "Installiere Web-Server..."
        if ! command -v python3 >/dev/null 2>&1; then
            apt-get install -y -qq python3 python3-pip python3-venv >/dev/null 2>&1 || true
        fi
        
        if [[ ! -d "$INSTALL_DIR/venv" ]]; then
            python3 -m venv "$INSTALL_DIR/venv" >/dev/null 2>&1
            "$INSTALL_DIR/venv/bin/pip" install --upgrade pip --quiet >/dev/null 2>&1
            "$INSTALL_DIR/venv/bin/pip" install flask --quiet >/dev/null 2>&1
        fi
        
        cp -f "$SCRIPT_DIR/services/disk2iso-web.service" /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable disk2iso-web.service >/dev/null 2>&1
        systemctl start disk2iso-web.service
        
        print_success "Installiere API-Updater..."
        cp -f "$SCRIPT_DIR/services/disk2iso-updater.service" /etc/systemd/system/
        cp -f "$SCRIPT_DIR/services/disk2iso-updater.timer" /etc/systemd/system/
        systemctl daemon-reload
        systemctl enable disk2iso-updater.timer >/dev/null 2>&1
        systemctl start disk2iso-updater.timer
        
        print_success "Alle Services erfolgreich installiert!"
        print_info "  • disk2iso Service: aktiv"
        print_info "  • Web-Server: http://$(hostname -I | awk '{print $1}'):8080"
        print_info "  • API-Updater: aktiv"
    fi
}

# ============================================================================
# MAIN - WIZARD MODE
# ============================================================================

main() {
    # System-Checks
    check_root
    check_debian
    
    # Installiere dialog für Wizard-UI (falls noch nicht vorhanden)
    if ! command -v dialog >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y -qq dialog >/dev/null 2>&1
    fi
    
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
    
    # disk2iso Dateien installieren
    install_disk2iso_files
    
    # Wizard Seite 3: Service Setup & Installation (fragt Ausgabeverzeichnis ab und installiert alle Services)
    wizard_page_service_setup
    configure_all_services
    
    # Wizard Seite 4: Abschluss
    wizard_page_complete
}

# Script ausführen
main "$@"
