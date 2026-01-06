#!/bin/bash
################################################################################
# disk2iso v1.2.0 - Deinstallations-Script
# Filepath: uninstall.sh
#
# Beschreibung:
#   Wizard-basierte Deinstallation von disk2iso
#   - 4-Seiten Deinstallations-Wizard mit whiptail
#   - Entfernt Service, Dateien und optional Ausgabeverzeichnis
#
# Version: 1.2.0
# Datum: 06.01.2026
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
WEB_SERVICE_FILE="/etc/systemd/system/disk2iso-web.service"
BIN_LINK="/usr/local/bin/disk2iso"

# Ausgabeverzeichnis aus Service-Datei ermitteln
OUTPUT_DIR=""
if [[ -f "$SERVICE_FILE" ]]; then
    OUTPUT_DIR=$(grep -oP 'ExecStart=.*-o\s+\K[^\s]+' "$SERVICE_FILE" 2>/dev/null || echo "")
fi

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

# Whiptail-Wrapper
use_whiptail() {
    command -v whiptail >/dev/null 2>&1
}

ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    
    if use_whiptail; then
        if [[ "$default" == "y" ]]; then
            whiptail --title "disk2iso Deinstallation" --yesno "$question" 10 60 --defaultno
        else
            whiptail --title "disk2iso Deinstallation" --yesno "$question" 10 60
        fi
        return $?
    else
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
# WIZARD FUNCTIONS
# ============================================================================

# Seite 1: Warnhinweis
wizard_page_warning() {
    local service_status=""
    if [[ -f "$SERVICE_FILE" ]] || [[ -f "$WEB_SERVICE_FILE" ]]; then
        service_status="
• Systemd-Service(s) wird/werden gestoppt und entfernt"
    fi
    
    local output_info=""
    if [[ -n "$OUTPUT_DIR" ]] && [[ -d "$OUTPUT_DIR" ]]; then
        output_info="

Hinweis: Das Ausgabeverzeichnis ($OUTPUT_DIR) wird im nächsten Schritt abgefragt."
    fi
    
    local info="WARNUNG: Diese Aktion entfernt disk2iso komplett vom System!

Was wird entfernt:
• disk2iso Script und Bibliotheken ($INSTALL_DIR)
• Symlink in /usr/local/bin${service_status}

Sie verlieren die Möglichkeit zur automatisierten ISO-Erstellung von optischen Medien.${output_info}

Möchten Sie wirklich fortfahren?"

    if use_whiptail; then
        if whiptail --title "disk2iso Deinstallation - Seite 1/4" \
            --yesno "$info" 20 70 \
            --yes-button "Deinstallieren" \
            --no-button "Abbrechen" \
            --defaultno; then
            return 0
        else
            return 1
        fi
    else
        echo "$info"
        ask_yes_no "Wirklich deinstallieren?"
    fi
}

# Seite 2: Deinstallation durchführen
wizard_page_uninstall() {
    local steps=()
    local step_count=0
    
    # Sammle Schritte
    if [[ -f "$SERVICE_FILE" ]]; then
        steps+=("Service stoppen und deaktivieren")
        step_count=$((step_count + 1))
    fi
    
    if [[ -f "$WEB_SERVICE_FILE" ]]; then
        steps+=("Web-Server-Service stoppen und deaktivieren")
        step_count=$((step_count + 1))
    fi
    
    if [[ -L "$BIN_LINK" ]]; then
        steps+=("Symlink entfernen")
        step_count=$((step_count + 1))
    fi
    
    if [[ -d "$INSTALL_DIR" ]]; then
        steps+=("Installationsverzeichnis entfernen")
        step_count=$((step_count + 1))
    fi
    
    local total=${#steps[@]}
    local current=0
    
    if use_whiptail; then
        {
            # Service stoppen
            if [[ -f "$SERVICE_FILE" ]]; then
                current=$((current + 1))
                percent=$((current * 100 / total))
                echo "$percent"
                echo "XXX"
                echo "Stoppe und deaktiviere Service ($current/$total)..."
                echo "XXX"
                
                systemctl stop disk2iso.service 2>/dev/null || true
                systemctl disable disk2iso.service 2>/dev/null || true
                rm -f "$SERVICE_FILE"
                systemctl daemon-reload
                sleep 0.5
            fi
            
            # Web-Server-Service stoppen
            if [[ -f "$WEB_SERVICE_FILE" ]]; then
                current=$((current + 1))
                percent=$((current * 100 / total))
                echo "$percent"
                echo "XXX"
                echo "Stoppe und deaktiviere Web-Server-Service ($current/$total)..."
                echo "XXX"
                
                systemctl stop disk2iso-web.service 2>/dev/null || true
                systemctl disable disk2iso-web.service 2>/dev/null || true
                rm -f "$WEB_SERVICE_FILE"
                systemctl daemon-reload
                sleep 0.5
            fi
            
            # Symlink entfernen
            if [[ -L "$BIN_LINK" ]]; then
                current=$((current + 1))
                percent=$((current * 100 / total))
                echo "$percent"
                echo "XXX"
                echo "Entferne Symlink ($current/$total)..."
                echo "XXX"
                
                rm -f "$BIN_LINK"
                sleep 0.3
            fi
            
            # Installationsverzeichnis entfernen
            if [[ -d "$INSTALL_DIR" ]]; then
                current=$((current + 1))
                percent=$((current * 100 / total))
                echo "$percent"
                echo "XXX"
                echo "Entferne Installationsverzeichnis ($current/$total)..."
                echo "XXX"
                
                rm -rf "$INSTALL_DIR"
                sleep 0.3
            fi
            
            echo "100"
        } | whiptail --title "disk2iso Deinstallation - Seite 2/4" \
            --gauge "Deinstalliere disk2iso..." 8 70 0
    else
        print_header "DEINSTALLATION"
        
        if [[ -f "$SERVICE_FILE" ]]; then
            print_info "Stoppe Service..."
            systemctl stop disk2iso.service 2>/dev/null || true
            systemctl disable disk2iso.service 2>/dev/null || true
            rm -f "$SERVICE_FILE"
            systemctl daemon-reload
            print_success "Service entfernt"
        fi
        
        if [[ -f "$WEB_SERVICE_FILE" ]]; then
            print_info "Stoppe Web-Server-Service..."
            systemctl stop disk2iso-web.service 2>/dev/null || true
            systemctl disable disk2iso-web.service 2>/dev/null || true
            rm -f "$WEB_SERVICE_FILE"
            systemctl daemon-reload
            print_success "Web-Server-Service entfernt"
        fi
        
        if [[ -L "$BIN_LINK" ]]; then
            print_info "Entferne Symlink..."
            rm -f "$BIN_LINK"
            print_success "Symlink entfernt"
        fi
        
        if [[ -d "$INSTALL_DIR" ]]; then
            print_info "Entferne Installationsverzeichnis..."
            rm -rf "$INSTALL_DIR"
            print_success "Verzeichnis entfernt"
        fi
    fi
}

# Seite 3: Ausgabeverzeichnis löschen
wizard_page_output_directory() {
    # Prüfe ob Ausgabeverzeichnis existiert
    if [[ -z "$OUTPUT_DIR" ]] || [[ ! -d "$OUTPUT_DIR" ]]; then
        return 0
    fi
    
    # Zähle ISO-Dateien
    local iso_count=$(find "$OUTPUT_DIR" -maxdepth 1 -type f \( -name "*.iso" -o -name "*.bin" \) 2>/dev/null | wc -l)
    local size_info=""
    if [[ $iso_count -gt 0 ]]; then
        local total_size=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)
        size_info="

Das Verzeichnis enthält $iso_count ISO/BIN-Datei(en) ($total_size)."
    fi
    
    local info="Ausgabeverzeichnis gefunden:
$OUTPUT_DIR${size_info}

Möchten Sie dieses Verzeichnis und alle darin enthaltenen Dateien löschen?

WARNUNG: Diese Aktion kann nicht rückgängig gemacht werden!"

    if use_whiptail; then
        if whiptail --title "disk2iso Deinstallation - Seite 3/4" \
            --yesno "$info" 18 70 \
            --yes-button "Löschen" \
            --no-button "Überspringen" \
            --defaultno; then
            
            # Lösche Verzeichnis
            {
                echo "50"
                echo "XXX"
                echo "Lösche Ausgabeverzeichnis..."
                echo "XXX"
                rm -rf "$OUTPUT_DIR"
                sleep 0.5
                echo "100"
            } | whiptail --title "Ausgabeverzeichnis löschen" \
                --gauge "Lösche $OUTPUT_DIR..." 8 70 0
        fi
    else
        echo "$info"
        if ask_yes_no "Ausgabeverzeichnis löschen?"; then
            print_info "Lösche $OUTPUT_DIR..."
            rm -rf "$OUTPUT_DIR"
            print_success "Verzeichnis gelöscht"
        else
            print_info "Ausgabeverzeichnis bleibt erhalten"
        fi
    fi
}

# Seite 4: Abschluss
wizard_page_complete() {
    local info="Deinstallation erfolgreich abgeschlossen!

disk2iso wurde vollständig vom System entfernt.

Entfernte Komponenten:
• disk2iso Script und Bibliotheken
• Systemd-Service(s) (falls vorhanden)
• Symlink in /usr/local/bin"

    if [[ -n "$OUTPUT_DIR" ]] && [[ ! -d "$OUTPUT_DIR" ]]; then
        info="${info}
• Ausgabeverzeichnis"
    fi
    
    info="${info}

Hinweis: Installierte Pakete (genisoimage, gddrescue, etc.) wurden NICHT entfernt.
Diese könnten von anderen Programmen verwendet werden.

Bei Bedarf können Sie diese manuell entfernen mit:
apt-get remove genisoimage gddrescue dvdbackup"

    if use_whiptail; then
        whiptail --title "disk2iso Deinstallation - Seite 4/4" \
            --msgbox "$info" 22 70
    else
        print_header "DEINSTALLATION ABGESCHLOSSEN"
        echo "$info"
    fi
}

# ============================================================================
# MAIN - WIZARD MODE
# ============================================================================

main() {
    # Root-Check
    check_root
    
    # Wizard Seite 1: Warnung
    if ! wizard_page_warning; then
        echo "Deinstallation abgebrochen."
        exit 0
    fi
    
    # Wizard Seite 2: Deinstallation durchführen
    wizard_page_uninstall
    
    # Wizard Seite 3: Ausgabeverzeichnis löschen
    wizard_page_output_directory
    
    # Wizard Seite 4: Abschluss
    wizard_page_complete
}

# Script ausführen
main "$@"
