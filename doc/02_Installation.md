# Kapitel 2: Installation

Komplette Installationsanleitung für disk2iso als Service oder Script.

## Inhaltsverzeichnis

1. [Voraussetzungen](#voraussetzungen)
2. [Installation als Service (empfohlen)](#installation-als-service-empfohlen)
3. [Installation als Script](#installation-als-script)
4. [Manuelle Installation](#manuelle-installation)
5. [Installer-Wizard](#installer-wizard)
6. [Service-Verwaltung](#service-verwaltung)
7. [Fehlerbehebung](#fehlerbehebung)

---

## Voraussetzungen

### System-Anforderungen

- **Distribution**: Debian 12+, Ubuntu 22.04+, Linux Mint 21+
- **Kernel**: Linux 5.0+ (für moderne Laufwerks-Treiber)
- **Bash**: Version 4.0 oder höher
- **Speicherplatz**: Minimal 100 MB (+ Platz für ISOs)
- **Optisches Laufwerk**: CD/DVD/Blu-ray kompatibel
- **systemd**: Version 232+ (für Service-Modus)

### Berechtigungen

- **Root-Zugriff**: Erforderlich für Installation und Betrieb
- **sudo**: Empfohlen für sichere Rechteverwaltung

### Prüfen

```bash
# systemd-Version (für Service-Modus)
systemctl --version

# Laufwerk verfügbar?
ls -la /dev/sr0

# Bash-Version
bash --version
```

### Internet-Verbindung

- **Installation**: Zum Download der Abhängigkeiten (apt install)
- **Optional**: Audio-CD (MusicBrainz), DVD/Blu-ray (TMDB)
- **Offline-Betrieb**: Möglich (ohne Metadaten)

---

## Installation als Service (empfohlen)

Der **Service-Modus** ist ideal für Dauerbetrieb und headless-Server.

### Schnellstart

```bash
# 1. Projekt klonen
git clone https://github.com/DirkGoetze/disk2iso.git
cd disk2iso

# 2. Installer starten
sudo ./install.sh
```

### Wizard-Ablauf

#### Seite 1: Willkommen

Kurze Übersicht über disk2iso Features.

#### Seite 2: Installations-Typ auswählen

```plain
┌───────────────────────────────────────────────────────────┐
│  Wählen Sie die gewünschte Installations-Art:            │
│                                                           │
│  ( ) Nur Script - Manuelle Ausführung                     │
│  (*) Script + systemd-Service - Automatischer Betrieb     │
│                                                           │
│  [OK] [Abbrechen]                                         │
└───────────────────────────────────────────────────────────┘
```

**Wähle:** `Script + systemd-Service`

#### Seite 3: Module auswählen

```plain
┌───────────────────────────────────────────────────────────┐
│  Wählen Sie die zu installierenden Module:               │
│                                                           │
│  [X] Audio-CD Support (MP3 + MusicBrainz)                 │
│  [X] Video-DVD Support (Entschlüsselt mit libdvdcss2)     │
│  [ ] Blu-ray Support (ddrescue - robust)                  │
│  [X] MQTT Integration (Home Assistant)                    │
│                                                           │
│  [OK] [Abbrechen]                                         │
└───────────────────────────────────────────────────────────┘
```

**Standard:** Audio-CD + Video-DVD + MQTT aktiv

#### Seite 4: Laufwerk-Erkennung

Automatische Erkennung von `/dev/sr0` oder manuelle Auswahl.

#### Seite 5: Ausgabeverzeichnis

```plain
Standard: /media/iso

Ändern auf: /srv/disk2iso (empfohlen)
```

#### Seite 6: MQTT-Konfiguration

```plain
┌───────────────────────────────────────────────────────────┐
│  MQTT Broker-Einstellungen:                              │
│                                                           │
│  Broker-Adresse: 192.168.20.10                           │
│  Broker-Port: 1883                                        │
│  Benutzername: disk2iso                                   │
│  Passwort: ********                                       │
│                                                           │
│  [OK] [Abbrechen]                                         │
└───────────────────────────────────────────────────────────┘
```

#### Seite 7: Abhängigkeiten installieren

Automatische Installation aller benötigten Pakete:

- Kern: coreutils, util-linux, genisoimage, whiptail
- Audio-CD: cdparanoia, lame, eyed3, curl, jq, cd-discid
- Video-DVD: dvdbackup, libdvdcss2
- Blu-ray: gddrescue
- MQTT: mosquitto-clients

#### Seite 8: Service-Installation

```plain
┌───────────────────────────────────────────────────────────┐
│  Installiere systemd-Service...                           │
│                                                           │
│  ✓ disk2iso.service → /etc/systemd/system/              │
│  ✓ systemctl daemon-reload                               │
│  ✓ systemctl enable disk2iso.service                     │
│  ✓ systemctl start disk2iso.service                      │
│                                                           │
│  Service-Status: ● aktiv (running)                       │
│                                                           │
│  [OK]                                                     │
└───────────────────────────────────────────────────────────┘
```

#### Seite 9: Abschluss

```plain
┌───────────────────────────────────────────────────────────┐
│  ✅ Installation erfolgreich abgeschlossen!               │
│                                                           │
│  Service läuft: disk2iso.service                         │
│  Web-Interface: http://<server-ip>:8080                 │
│                                                           │
│  Logs ansehen:                                            │
│  sudo journalctl -u disk2iso -f                          │
│                                                           │
│  ➜ Disc einlegen → Automatische Archivierung            │
│                                                           │
│  [OK]                                                     │
└───────────────────────────────────────────────────────────┘
```

### Nach der Installation

```bash
# Service-Status prüfen
sudo systemctl status disk2iso

# Logs verfolgen
sudo journalctl -u disk2iso -f

# Web-Interface öffnen
xdg-open http://localhost:8080
```

---

## Installation als Script

Für manuelle Ausführung ohne permanenten Service.

### Installer-Wizard

```bash
sudo ./install.sh
```

**Auf Seite 2:** `Nur Script` auswählen

**Installation nach:**

- `/opt/disk2iso/` - Hauptverzeichnis
- Symlink: `/usr/local/bin/disk2iso`

### Manuelle Ausführung

```bash
# Disc einlegen, dann:
sudo disk2iso

# ODER: Mit spezifischem Laufwerk
sudo disk2iso --device /dev/sr1

# ODER: Mit Ausgabeverzeichnis
sudo disk2iso --output /mnt/nas/media
```

---

## Manuelle Installation

Falls Wizard nicht funktioniert oder spezielle Anpassungen gewünscht:

### 1. Abhängigkeiten installieren

```bash
# Kern-Pakete (immer erforderlich)
sudo apt update
sudo apt install -y coreutils util-linux genisoimage eject mount whiptail

# Optional: Audio-CD Modul
sudo apt install -y cdparanoia lame eyed3 curl jq cd-discid wodim libcdio-utils

# Optional: Video-DVD Modul
sudo apt install -y dvdbackup libdvd-pkg
sudo dpkg-reconfigure libdvd-pkg  # libdvdcss2 installieren

# Optional: Blu-ray Modul
sudo apt install -y gddrescue

# Optional: MQTT
sudo apt install -y mosquitto-clients
```

### 2. Dateien kopieren

```bash
# Erstelle Ziel-Ordner
sudo mkdir -p /opt/disk2iso/disk2iso-lib/lang

# Hauptskript
sudo cp disk2iso.sh /opt/disk2iso/
sudo chmod +x /opt/disk2iso/disk2iso.sh

# Alle Module
sudo cp disk2iso-lib/*.sh /opt/disk2iso/disk2iso-lib/

# Sprachdateien
sudo cp disk2iso-lib/lang/* /opt/disk2iso/disk2iso-lib/lang/

# Konfiguration
sudo cp disk2iso-lib/config.sh /opt/disk2iso/disk2iso-lib/

# Symlink erstellen
sudo ln -s /opt/disk2iso/disk2iso.sh /usr/local/bin/disk2iso
```

### 3. Service einrichten (optional)

```bash
# Service-Datei erstellen
sudo nano /etc/systemd/system/disk2iso.service
```

**Inhalt:**

```ini
[Unit]
Description=disk2iso - Optical Media Archiver
Documentation=https://github.com/DirkGoetze/disk2iso
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/opt/disk2iso/disk2iso.sh
Restart=on-failure
RestartSec=10s
NoNewPrivileges=true
PrivateTmp=true
StandardOutput=journal
StandardError=journal
SyslogIdentifier=disk2iso

[Install]
WantedBy=multi-user.target
```

**Aktivieren:**

```bash
sudo systemctl daemon-reload
sudo systemctl enable disk2iso
sudo systemctl start disk2iso
```

### 4. Web-Service einrichten (optional)

```bash
# Python-Abhängigkeiten
sudo apt install -y python3 python3-flask python3-markdown

# Web-Service-Datei
sudo nano /etc/systemd/system/disk2iso-web.service
```

**Inhalt:**

```ini
[Unit]
Description=disk2iso Web Interface
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/disk2iso/www
ExecStart=/usr/bin/python3 /opt/disk2iso/www/app.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

**Aktivieren:**

```bash
sudo systemctl daemon-reload
sudo systemctl enable disk2iso-web
sudo systemctl start disk2iso-web
```

---

## Installer-Wizard

Detaillierte Beschreibung aller Wizard-Seiten.

### Seite 1: Willkommen

```plain
┌───────────────────────────────────────────────────────────┐
│  Willkommen zur Installation von disk2iso v1.2!          │
│                                                           │
│  Dieses Werkzeug archiviert optische Medien automatisch  │
│  als ISO-Images beim Einlegen in das Laufwerk.           │
│                                                           │
│  Unterstützte Medien:                                     │
│  • Audio-CDs → MP3 mit MusicBrainz-Metadaten            │
│  • Video-DVDs → ISO (entschlüsselt)                      │
│  • Blu-rays → ISO (robustes Kopieren)                    │
│  • Daten-Discs → ISO (CD/DVD/BD-ROM)                     │
│                                                           │
│  Drücken Sie OK zum Fortfahren...                         │
└───────────────────────────────────────────────────────────┘
```

### Seite 2: Installations-Typ

**Nur Script:**
- Keine systemd-Integration
- Manuelle Ausführung: `sudo disk2iso`
- Ideal zum Testen

**Script + Service:**
- Automatischer Start beim Booten
- Permanent im Hintergrund
- Ideal für Dauerbetrieb

### Seite 3: Modul-Auswahl

**Audio-CD Support:**
- cdparanoia (Lossless Ripping)
- lame (MP3 V2 ~190kbps)
- MusicBrainz Metadaten
- Cover-Download

**Video-DVD Support:**
- dvdbackup (CSS-Entschlüsselung)
- genisoimage (ISO-Erstellung)
- TMDB Metadaten

**Blu-ray Support:**
- ddrescue (Robust, Fehlertoleranz)
- dd (Fallback)

**MQTT Integration:**
- Home Assistant Support
- Echtzeit-Status
- Push-Benachrichtigungen

### Seite 4: Laufwerks-Erkennung

Automatische Erkennung via `/dev/sr*`.

**Fallback:** `/dev/sr0` als Standard.

### Seite 5: Ausgabeverzeichnis

**Standard:** `/media/iso`

**Empfohlen:** `/srv/disk2iso` (FHS-konform)

**Alternativ:** Netzwerk-Speicher (NFS/CIFS)

### Seite 6: MQTT-Konfiguration

Nur wenn MQTT-Modul aktiviert.

**Broker-Adresse:** IP deines Home Assistant  
**Port:** 1883 (Standard)  
**Auth:** Optional (empfohlen)

### Seite 7: Abhängigkeiten

Automatische Installation via `apt install`:

1. `apt update`
2. Kern-Pakete (immer)
3. Modul-Pakete (gewählt)
4. Fortschrittsbalken

Dauer: 1-5 Minuten

### Seite 8: Dateien kopieren

Ziel: `/opt/disk2iso/`

Struktur:
```
/opt/disk2iso/
├── disk2iso.sh
├── disk2iso-lib/
│   ├── config.sh
│   ├── lib-*.sh
│   └── lang/
└── www/
```

### Seite 9: Service-Installation

Nur bei "Script + Service":

1. disk2iso.service → `/etc/systemd/system/`
2. `systemctl daemon-reload`
3. `systemctl enable disk2iso`
4. `systemctl start disk2iso`
5. `systemctl enable disk2iso-web`
6. `systemctl start disk2iso-web`

### Seite 10: Abschluss

Zusammenfassung:
- Installierte Module
- Service-Status
- Web-Interface URL
- Nächste Schritte

---

## Service-Verwaltung

### Grundbefehle

```bash
# Status anzeigen
sudo systemctl status disk2iso

# Service starten
sudo systemctl start disk2iso

# Service stoppen
sudo systemctl stop disk2iso

# Service neu starten
sudo systemctl restart disk2iso

# Autostart aktivieren
sudo systemctl enable disk2iso

# Autostart deaktivieren
sudo systemctl disable disk2iso
```

### Logs ansehen

```bash
# Echtzeit-Logs
sudo journalctl -u disk2iso -f

# Letzte 50 Zeilen
sudo journalctl -u disk2iso -n 50

# Seit heute
sudo journalctl -u disk2iso --since today

# Nur Fehler
sudo journalctl -u disk2iso -p err
```

### Konfiguration ändern

```bash
# config.sh bearbeiten
sudo nano /opt/disk2iso/disk2iso-lib/config.sh

# Service neu starten
sudo systemctl restart disk2iso
```

---

## Fehlerbehebung

### Installer startet nicht

**Problem:** `./install.sh: command not found`

**Lösung:**
```bash
chmod +x install.sh
sudo ./install.sh
```

### Kein whiptail/dialog

**Problem:** `whiptail: not found`

**Lösung:**
```bash
sudo apt install whiptail dialog
# ODER: Manuelle Installation (siehe oben)
```

### Laufwerk nicht erkannt

**Problem:** `/dev/sr0` existiert nicht

**Diagnose:**
```bash
ls -la /dev/sr*
lsmod | grep sr_mod
dmesg | grep -i "cd\|dvd"
```

**Lösung:**
```bash
sudo modprobe sr_mod
echo "sr_mod" | sudo tee -a /etc/modules
```

### libdvdcss2 Installation

**Problem:** `libdvdcss2` nicht gefunden

**Lösung:**
```bash
sudo apt install libdvd-pkg
sudo dpkg-reconfigure libdvd-pkg
# Wizard folgen, Lizenz akzeptieren
```

### Service startet nicht

**Problem:** `Failed to start disk2iso.service`

**Diagnose:**
```bash
sudo journalctl -xe | grep disk2iso
sudo systemd-analyze verify disk2iso.service
```

**Häufige Ursachen:**

1. **Hauptskript nicht ausführbar:**
   ```bash
   sudo chmod +x /opt/disk2iso/disk2iso.sh
   ```

2. **Pfad falsch:**
   ```bash
   sudo nano /etc/systemd/system/disk2iso.service
   # ExecStart=/opt/disk2iso/disk2iso.sh prüfen
   ```

3. **Abhängigkeiten fehlen:**
   ```bash
   /opt/disk2iso/disk2iso.sh --test
   ```

### Keine Schreibrechte

**Problem:** `Permission denied` für `/srv/disk2iso`

**Lösung:**
```bash
sudo chown -R root:root /srv/disk2iso
sudo chmod 755 /srv/disk2iso
```

---

## Weiterführende Links

- **[← Zurück: Kapitel 1 - Handbuch](Handbuch.md)**
- **[Weiter: Kapitel 3 - Betrieb →](03_Betrieb.md)**
- **[Kapitel 4 - Optionale Module →](04_Module/)**
- **[Kapitel 5 - Fehlerhandling →](05_Fehlerhandling.md)**
- **[Kapitel 6 - Entwickler →](06_Entwickler.md)**

---

**Version:** 1.2.0  
**Letzte Aktualisierung:** 26. Januar 2026
