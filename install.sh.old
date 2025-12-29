#!/bin/bash
################################################################################
# disk2iso - Installations-Script
# Installiert Script, Service und optionale Pakete
################################################################################

set -e

# Farben für Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}disk2iso - Installation${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Root-Check
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}FEHLER: Dieses Script muss als root ausgeführt werden${NC}"
    echo "Bitte verwenden Sie: su -c './install.sh'"
    exit 1
fi

# Prüfe kritische Tools
echo -e "${BLUE}► Prüfe kritische System-Tools...${NC}"
missing_critical=()
for tool in dd md5sum lsblk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        missing_critical+=("$tool")
    fi
done

if [[ ${#missing_critical[@]} -gt 0 ]]; then
    echo -e "${RED}✗ Kritische Tools fehlen: ${missing_critical[*]}${NC}"
    echo "Diese sollten in einer Standard Debian-Installation vorhanden sein!"
    exit 1
fi
echo -e "${GREEN}✓ Alle kritischen Tools vorhanden${NC}"
echo ""

# Prüfe optionale Tools
echo -e "${BLUE}► Prüfe optionale Tools...${NC}"
has_isoinfo=false
has_dvdbackup=false
has_libdvdcss=false
has_genisoimage=false
has_ddrescue=false

command -v isoinfo >/dev/null 2>&1 && has_isoinfo=true
command -v dvdbackup >/dev/null 2>&1 && has_dvdbackup=true
dpkg -l | grep -q libdvdcss2 && has_libdvdcss=true
command -v genisoimage >/dev/null 2>&1 && has_genisoimage=true
command -v ddrescue >/dev/null 2>&1 && has_ddrescue=true

$has_isoinfo && echo -e "${GREEN}✓ isoinfo vorhanden${NC}" || echo -e "${YELLOW}✗ isoinfo fehlt${NC}"
$has_genisoimage && echo -e "${GREEN}✓ genisoimage vorhanden${NC}" || echo -e "${YELLOW}✗ genisoimage fehlt${NC}"
$has_dvdbackup && echo -e "${GREEN}✓ dvdbackup vorhanden${NC}" || echo -e "${YELLOW}✗ dvdbackup fehlt${NC}"
$has_libdvdcss && echo -e "${GREEN}✓ libdvdcss2 vorhanden${NC}" || echo -e "${YELLOW}✗ libdvdcss2 fehlt${NC}"
$has_ddrescue && echo -e "${GREEN}✓ ddrescue vorhanden${NC}" || echo -e "${YELLOW}✗ ddrescue fehlt${NC}"
echo ""

# Benutzer-Abfrage für Video-DVD Unterstützung
echo -e "${BLUE}► Video-DVD Unterstützung${NC}"
echo ""
echo "Für Video-DVDs gibt es 3 Optionen:"
echo ""
echo -e "${GREEN}Option 1: Entschlüsselte ISOs (empfohlen)${NC}"
echo "  - Pakete: dvdbackup, libdvdcss2, genisoimage"
echo "  - libdvdcss2 benötigt deb-multimedia.org Repository"
echo "  - Schnell: ~10-15 Min für 4,7 GB DVD"
echo "  - ISO ist entschlüsselt und direkt verarbeitbar"
echo ""
echo -e "${YELLOW}Option 2: Verschlüsselte ISOs mit ddrescue${NC}"
echo "  - Pakete: gddrescue, genisoimage"
echo "  - Nur Standard-Repositories"
echo "  - Mittelschnell: ~15-30 Min"
echo "  - ISO bleibt verschlüsselt (Weiterverarbeitung benötigt libdvdcss2)"
echo ""
echo -e "${RED}Option 3: Nur dd (langsam)${NC}"
echo "  - Keine zusätzlichen Pakete"
echo "  - Sehr langsam bei kopiergeschützten DVDs"
echo "  - ISO bleibt verschlüsselt"
echo ""

# Abfrage welche Option
install_option1=false
install_option2=false

read -p "Option 1 installieren (entschlüsselt, deb-multimedia)? [j/N]: " choice
case "$choice" in
    j|J|y|Y ) install_option1=true;;
    * ) install_option1=false;;
esac

if ! $install_option1; then
    read -p "Option 2 installieren (ddrescue, Standard-Repos)? [j/N]: " choice
    case "$choice" in
        j|J|y|Y ) install_option2=true;;
        * ) install_option2=false;;
    esac
fi

# Installation durchführen
echo ""
echo -e "${BLUE}► Starte Installation...${NC}"

# Update package list
echo "Aktualisiere Paketlisten..."
apt-get update -qq

# Basis-Pakete (immer installieren)
echo "Installiere Basis-Pakete..."
apt-get install -y genisoimage >/dev/null 2>&1

if $install_option1; then
    echo -e "${GREEN}► Installiere Option 1: Entschlüsselte Video-DVDs${NC}"
    
    # Prüfe ob deb-multimedia schon konfiguriert ist
    if ! grep -q "deb-multimedia.org" /etc/apt/sources.list.d/*.list 2>/dev/null; then
        echo "Füge deb-multimedia.org Repository hinzu..."
        echo "deb http://www.deb-multimedia.org trixie main" > /etc/apt/sources.list.d/deb-multimedia.list
        
        echo "Importiere GPG-Key..."
        apt-get update -oAcquire::AllowInsecureRepositories=true -qq
        apt-get install -y --allow-unauthenticated deb-multimedia-keyring >/dev/null 2>&1
        apt-get update -qq
    fi
    
    echo "Installiere libdvdcss2 und dvdbackup..."
    apt-get install -y libdvdcss2 dvdbackup >/dev/null 2>&1
    echo -e "${GREEN}✓ Option 1 installiert${NC}"
    
elif $install_option2; then
    echo -e "${YELLOW}► Installiere Option 2: ddrescue${NC}"
    apt-get install -y gddrescue >/dev/null 2>&1
    echo -e "${GREEN}✓ Option 2 installiert${NC}"
else
    echo -e "${YELLOW}⚠ Nur Basis-Pakete installiert (Option 3: dd)${NC}"
fi

# Script installieren
echo ""
echo -e "${BLUE}► Installiere disk2iso Script...${NC}"

INSTALL_DIR="/usr/local/bin"
LIB_DIR="/usr/local/lib/disk2iso"

# Kopiere Haupt-Script
cp disk2iso.sh "$INSTALL_DIR/disk2iso"
chmod +x "$INSTALL_DIR/disk2iso"
echo -e "${GREEN}✓ Script installiert: $INSTALL_DIR/disk2iso${NC}"

# Kopiere Bibliotheken
mkdir -p "$LIB_DIR"
cp -r disk2iso-lib/* "$LIB_DIR/"
echo -e "${GREEN}✓ Bibliotheken installiert: $LIB_DIR${NC}"

# Passe Pfad im Haupt-Script an
sed -i "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$LIB_DIR\"|" "$INSTALL_DIR/disk2iso"

# Service-Installation abfragen
echo ""
read -p "Systemd-Service installieren? [j/N]: " choice
case "$choice" in
    j|J|y|Y )
        echo -e "${BLUE}► Installiere systemd-Service...${NC}"
        
        # Frage nach Ausgabe-Verzeichnis
        read -p "Ausgabe-Verzeichnis für ISOs [/media/iso-backup]: " output_dir
        output_dir=${output_dir:-/media/iso-backup}
        
        # Erstelle Service-Datei
        cat > /etc/systemd/system/disk2iso.service <<EOF
[Unit]
Description=disk2iso - Automatische ISO-Erstellung von optischen Medien
After=multi-user.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/disk2iso -o $output_dir
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        # Erstelle Ausgabe-Verzeichnis
        mkdir -p "$output_dir"
        
        systemctl daemon-reload
        echo -e "${GREEN}✓ Service installiert${NC}"
        
        read -p "Service beim Systemstart aktivieren? [j/N]: " choice
        case "$choice" in
            j|J|y|Y )
                systemctl enable disk2iso.service
                echo -e "${GREEN}✓ Service aktiviert (startet beim Systemstart)${NC}"
                ;;
        esac
        
        read -p "Service jetzt starten? [j/N]: " choice
        case "$choice" in
            j|J|y|Y )
                systemctl start disk2iso.service
                echo -e "${GREEN}✓ Service gestartet${NC}"
                ;;
        esac
        ;;
esac

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Installation erfolgreich!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "Verwendung:"
echo "  Manuell: disk2iso -o /pfad/zum/ausgabe-ordner"
echo "  Service: systemctl status disk2iso"
echo "  Logs:    journalctl -u disk2iso -f"
echo ""
