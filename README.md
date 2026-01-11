# disk2iso - Automatisches Optical Media Archivierungstool

🚀 Professionelles Tool zur automatischen Archivierung von CDs, DVDs und Blu-rays als ISO-Images mit State Machine, Web-Interface und MusicBrainz-Integration.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.debian.org/)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/Version-1.3.0-blue.svg)](doc/Handbuch.md)

## ✨ Highlights

- 🎯 **Automatische Medien-Erkennung** - Unterscheidet 6 Disc-Typen (Audio-CD, DVD-Video, BD-Video, Data-CDs/DVDs/BDs)
- 🔄 **State Machine** - 11 definierte Zustände für präzise Ablaufsteuerung
- 🌐 **Web-Interface** - Modernes Dashboard mit Live-Updates (Flask, Port 5000)
- 🎵 **Audio-CD Ripping** - MP3-Encoding mit MusicBrainz-Metadaten, CD-TEXT Fallback und Album-Cover
- 📀 **Video-DVD Support** - Entschlüsselung mit dvdbackup/libdvdcss2 & intelligenter Retry-Mechanismus
- 🎬 **Blu-ray Support** - Robustes Kopieren mit ddrescue
- 🔄 **Intelligente Methoden-Wahl** - Beste Kopiermethode basierend auf Disc-Typ und verfügbaren Tools
- ✅ **MD5-Checksummen** - Automatische Integritätsprüfung
- 🔧 **Systemd-Integration** - Automatischer Betrieb als Service
- 📡 **MQTT/Home Assistant** - Echtzeit-Status, Push-Benachrichtigungen, Dashboard
- 🌍 **Mehrsprachig** - 4 vollständige Sprachen (de, en, es, fr) mit je 202 Konstanten
- 📊 **JSON REST API** - Vollständige Programmierschnittstelle für externe Tools
- 🎨 **Whiptail-Wizard** - Komfortable grafische Installation (9 Seiten)

## 🚀 Quick Start

```bash
# Installation
git clone <repository-url>
cd disk2iso
sudo ./install.sh

# Service starten
sudo systemctl start disk2iso
sudo systemctl start disk2iso-web

# Service-Status prüfen
sudo systemctl status disk2iso
sudo systemctl status disk2iso-web

# Logs ansehen
sudo journalctl -u disk2iso -f
```

## 💿 Unterstützte Medientypen

| Typ | Beschreibung | Methode | Modul |
|-----|-------------|---------|-------|
| 🎵 Audio-CD | MP3-Ripping mit MusicBrainz/CD-TEXT | cdparanoia + lame | lib-cd.sh |
| 📀 DVD-Video | Entschlüsselte Backups + Retry | dvdbackup/ddrescue | lib-dvd.sh |
| 🎬 Blu-ray Video | Robustes Kopieren | ddrescue/dd | lib-bluray.sh |
| 💾 Data-CD/DVD/BD | 1:1 ISO-Images | dd/ddrescue | Kern |
| 📡 MQTT-Integration | Home Assistant Status | mosquitto-clients | lib-mqtt.sh |
| 🌐 Web-Interface | Dashboard & API | Flask (Python) | www/ |

## 📦 Installation

### Automatisch (empfohlen)

```bash
sudo ./install.sh
```

**Der Wizard bietet:**
- Modulauswahl (Audio-CD, Video-DVD, Blu-ray)
- Automatische Paket-Installation
- Optional: systemd Service-Setup
- libdvdcss2-Konfiguration (für DVD-Entschlüsselung)

### Systemanforderungen

**Kern-Pakete:**
- coreutils, util-linux, eject, mount
- Empfohlen: genisoimage, gddrescue

**Optional je nach Modul:**
- Audio-CD: cdparanoia, lame, cd-discid, curl, jq, eyed3, wodim/libcdio-utils (CD-TEXT)
- Video-DVD: dvdbackup, libdvdcss2
- Blu-ray: (nutzt gddrescue aus Kern-Paketen)

## 📖 Dokumentation

📚 **[Ausführliches Handbuch](disk2iso-lib/docu/Handbuch.md)** - Vollständige Dokumentation mit:
- Installation als Script/Service
- Verwendung und Konfiguration
- Entwickler-Informationen
- Deinstallation

## 📁 Ausgabe-Struktur

```
output_dir/
├── audio/          # Audio-CDs (Artist/Album/Track.mp3 + Cover)
├── data/           # Daten-CDs/DVDs/Blu-rays (*.iso)
├── dvd/            # Video-DVDs (*.iso)
├── bd/             # Blu-ray Videos (*.iso)
├── .log/           # Log-Dateien (*.log, versteckt)
└── .temp/          # Temporäre Dateien (auto-cleanup, versteckt)
```

Jede ISO-Datei erhält automatisch:
- MD5-Checksumme (`.md5`)
- Log-Datei im `.log/` Verzeichnis (versteckt)

## 🎯 Features im Detail

### Modulare Architektur
- **Kern-Module** - Basis-Funktionalität (immer verfügbar)
- **Optionale Module** - Audio-CD, Video-DVD, Blu-ray (bei Installation wählbar)
- **Graceful Degradation** - Fehlende Module → Fallback auf Daten-Disc-Methode

### Intelligente Disc-Erkennung
1. Medien-Typ erkennen (UDF, ISO9660, Audio-CD)
2. Verfügbare Tools prüfen
3. Beste Kopiermethode wählen
4. Fortschritt anzeigen
5. MD5-Checksumme erstellen
6. Medium auswerfen

### MusicBrainz-Integration
- Automatische Disc-ID-Erkennung
- Metadaten-Lookup (Artist, Album, Track, Jahr)
- Album-Cover Download
- ID3-Tag Einbettung
- Jellyfin-kompatible NFO-Dateien

## 🛠️ Verwendung

### Service-Modus (Standard)
```bash
# Service starten
sudo systemctl start disk2iso

# Status prüfen
sudo systemctl status disk2iso

# Logs verfolgen
sudo journalctl -u disk2iso -f

# Service neustarten
sudo systemctl restart disk2iso
```

Im Service-Modus: Medium einlegen → automatische Archivierung → Auto-Eject

### Web-Interface
```bash
# Web-Server starten
sudo systemctl start disk2iso-web

# Browser öffnen: http://localhost:5000
```

## 🗂️ Projekt-Struktur

```
disk2iso/
├── disk2iso.sh              # Hauptskript (Service-Modus)
├── install.sh               # Installations-Wizard
├── uninstall.sh             # Deinstallations-Wizard
├── lib/
│   ├── config.sh            # Konfiguration
│   ├── lib-common.sh        # Kern (Daten-Discs)
│   ├── lib-cd.sh            # Audio-CD (optional)
│   ├── lib-dvd.sh           # Video-DVD (optional)
│   ├── lib-bluray.sh        # Blu-ray (optional)
│   ├── lib-install.sh       # Shared Installer-Funktionen
│   └── lib-*.sh             # Weitere Kern-Module
├── lang/
│   ├── *.de                 # Deutsche Sprachdateien
│   └── *.en                 # Englische Sprachdateien
├── www/
│   ├── app.py               # Flask Web-App
│   └── templates/           # HTML Templates
├── service/
│   ├── disk2iso.service     # systemd Service
│   └── disk2iso-web.service # Web-Interface Service
└── doc/                     # Ausführliche Dokumentation
```

## ⚙️ Konfiguration

Bearbeite `/opt/disk2iso/lib/config.sh`:

```bash
DEFAULT_OUTPUT_DIR="/media/iso"  # Ausgabeverzeichnis
LANGUAGE="de"                    # Sprache (de oder en)
MQTT_ENABLED=false               # MQTT Integration
MQTT_BROKER="192.168.20.10"      # MQTT Broker IP
```

**Wichtig:** Nach Änderungen Service neu starten:
```bash
sudo systemctl restart disk2iso
DEBUG=1 STRICT=1 ./disk2iso.sh  # Kombiniert
```

## 🔧 Deinstallation

```bash
sudo ./uninstall.sh
```

Wizard-geführte Deinstallation mit optionaler Löschung des Ausgabeverzeichnisses.

## 📝 Lizenz

MIT License - siehe [LICENSE](LICENSE)

## 🤝 Beitragen

Contributions sind willkommen! Bitte:
1. Fork erstellen
2. Feature-Branch erstellen (`git checkout -b feature/AmazingFeature`)
3. Änderungen committen (`git commit -m 'Add AmazingFeature'`)
4. Branch pushen (`git push origin feature/AmazingFeature`)
5. Pull Request öffnen

## 🙏 Credits

- **MusicBrainz** - Metadaten-API
- **cdparanoia, lame** - Audio-CD Ripping
- **icedax, cd-info** - CD-TEXT Auslesen
- **dvdbackup, libdvdcss2** - DVD-Entschlüsselung
- **ddrescue** - Robustes Kopieren

## 📞 Support

- 📖 [Dokumentation](disk2iso-lib/docu/Handbuch.md)
- 🐛 [Issues auf GitHub](../../issues)
- 💬 Logs: `journalctl -u disk2iso -f`

---

**Version:** 1.2.0 | **Status:** Production Ready | **Platform:** Debian Linux

## ✨ Features

- ✓ **Modulare Architektur** - Optionale Unterstützung für Audio-CD, Video-DVD, Blu-ray, MQTT
- ✓ **Automatische Medien-Erkennung** - 6 spezialisierte Disc-Typen
- ✓ **Intelligente Methoden-Auswahl** - Beste Kopiermethode pro Medientyp
- ✓ **MD5-Checksummen** - Automatische Integritätsprüfung
- ✓ **Service-Modus** - systemd-Integration für automatischen Betrieb
- ✓ **MQTT-Integration** - Home Assistant Echtzeit-Status und Benachrichtigungen
- ✓ **Dezentrale Dependency-Checks** - Module prüfen eigene Abhängigkeiten
- ✓ **Debug-Modi** - Umfangreiche Entwickler-Unterstützung

## 💿 Unterstützte Medientypen

### Kern-Funktionen (immer verfügbar)

- 💾 **CD-ROM** - Daten-CDs als ISO mit dd/ddrescue
- 📀 **DVD-ROM** - Daten-DVDs als ISO mit dd/ddrescue
- 📁 **Blu-ray ROM** - Daten-Blu-rays als ISO mit dd/ddrescue

### Optionale Module (bei Installation wählbar)

- 🎵 **Audio-CDs** (lib-cd.sh) - Rippen zu MP3 mit MusicBrainz-Metadaten und Cover
- 💿 **DVD-Video** (lib-dvd.sh) - Entschlüsselte Backups mit dvdbackup
- 🎬 **Blu-ray Video** (lib-bluray.sh) - Entschlüsselte Backups mit MakeMKV

## 💻 Systemanforderungen

### Kern-Pakete (immer erforderlich)

**Kritische Abhängigkeiten:**

- **coreutils** - dd (Kopieren), md5sum (Checksummen)
- **util-linux** - lsblk (Laufwerkserkennung)
- **eject** - Medien auswerfen
- **mount** - Dateisystem-Mount für Label-Erkennung

**Empfohlen für bessere Performance:**

- **genisoimage** - isoinfo für exakte Volume-Größen
- **gddrescue** - Robustes Kopieren mit Fehlerbehandlung

### Optionale Pakete (pro Modul)

**Audio-CD Support (lib-cd.sh):**

- **cdparanoia** - Audio-CD Ripping (kritisch)
- **lame** - MP3-Encoding (kritisch)
- **genisoimage** - ISO-Erstellung (kritisch)
- **cd-discid** - MusicBrainz Disc-ID (optional)
- **curl, jq** - MusicBrainz Metadaten-Abfrage (optional)
- **eyeD3** - Cover-Art Einbettung (optional)
- **wodim** (icedax) - CD-TEXT Auslesen (optional, Fallback)
- **libcdio-utils** (cd-info) - CD-TEXT Auslesen (optional, Fallback)

**Video-DVD Support (lib-dvd.sh):**

- **dvdbackup** - DVD-Entschlüsselung (empfohlen)
- **libdvdcss2** - CSS-Entschlüsselung für kommerzielle DVDs (empfohlen)
- **genisoimage** - ISO-Erstellung aus VIDEO_TS (empfohlen)
- **gddrescue** - Fallback-Methode (optional)

**Blu-ray Support (lib-bluray.sh):**

- **makemkvcon** - Blu-ray-Entschlüsselung (empfohlen)
- **genisoimage** - ISO-Erstellung aus BDMV (empfohlen)
- **gddrescue** - Fallback-Methode (optional)

**MQTT/Home Assistant Integration (lib-mqtt.sh):**

- **mosquitto-clients** - MQTT-Publishing (mosquitto_pub)
- MQTT Broker (z.B. Mosquitto in Home Assistant)
- Home Assistant mit MQTT-Integration

## 🚀 Installation

### Automatische Installation (empfohlen)

```bash
# Repository clonen
git clone <repository-url>
cd disk2iso

# Installations-Script ausführen
sudo ./install.sh
```

**Das Installations-Script bietet:**

1. **Modulare Installation** - Wähle benötigte Features:
   - Nur Daten-Disks (Minimal)
   - Audio-CD Support
   - Video-DVD Support
   - Blu-ray Support
   - Alle Features (Komplett)

2. **Automatische Paket-Installation:**
   - Prüft und installiert Kern-Pakete (dd, md5sum, lsblk, eject)
   - Installiert optionale Pakete basierend auf gewählten Modulen
   - Konfiguriert libdvdcss2 für DVD-Entschlüsselung (optional)
   - MakeMKV Installations-Hinweise für Blu-ray Support

3. **System-Integration:**
   - Installiert nach /opt/disk2iso
   - Erstellt Symlink in /usr/local/bin
   - Konfiguriert systemd Service (optional)

### Manuelle Installation

```bash
# 1. Repository clonen
git clone <repository-url>
cd disk2iso

# 2. Script ausführbar machen
chmod +x disk2iso.sh

# 3. Optional: Als systemd Service einrichten
sudo cp disk2iso.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable disk2iso
sudo systemctl start disk2iso
```

## 💻 Verwendung

### Service-Modus (Standard)

disk2iso läuft ausschließlich als systemd-Service:

```bash
# Service steuern
sudo systemctl start disk2iso
sudo systemctl stop disk2iso
sudo systemctl status disk2iso
sudo systemctl restart disk2iso

# Logs anzeigen
sudo journalctl -u disk2iso -f
```

**Automatisches Verhalten:**

1. Medium einlegen
2. Automatische Typ-Erkennung (audio-cd, dvd-video, bd-video, etc.)
3. Beste Methode wählen basierend auf:
   - Disc-Typ
   - Verfügbaren Tools
   - Installierten Modulen
4. Kopieren mit Fortschrittsanzeige
5. MD5-Checksumme erstellen
6. Medium auswerfen

### Web-Interface

Überwachung und Verwaltung im Browser:

```bash
# Web-Server starten
sudo systemctl start disk2iso-web

# Browser öffnen
http://localhost:5000
```

## 📋 Ausgabe

Das Ausgabeverzeichnis wird in `/opt/disk2iso/lib/config.sh` konfiguriert (Variable `DEFAULT_OUTPUT_DIR`).

Standard-Struktur:
- ISO-Dateien: `${DEFAULT_OUTPUT_DIR}/[audio|dvd|bd|data]/`
- MD5-Checksummen: Gleicher Ordner wie ISO-Dateien (`.md5`)
- Log-Dateien: `${DEFAULT_OUTPUT_DIR}/.log/`
- Temporäre Dateien: `${DEFAULT_OUTPUT_DIR}/.temp/`

## ⚙️ Konfiguration

Bearbeite `/opt/disk2iso/lib/config.sh`:

```bash
# Ausgabeverzeichnis
DEFAULT_OUTPUT_DIR="/media/iso"

# Sprach-Einstellung
LANGUAGE="de"                   # Sprache für Meldungen (de oder en)

# MQTT-Konfiguration (optional)
MQTT_ENABLED=false
MQTT_BROKER="192.168.20.10"
```

**Wichtig:** Das Ausgabeverzeichnis wird ausschließlich aus der Konfigurationsdatei gelesen. Nach Änderungen muss der Service neu gestartet werden:

```bash
sudo systemctl restart disk2iso

### Mehrsprachigkeit

Das Sprachsystem ist modular aufgebaut:

- Jedes Modul hat eigene Sprachdateien: `lang/lib-[modul].[sprache]`
- Beim Laden eines Moduls wird automatisch die Sprachdatei geladen
- Standard: Deutsch, optional: Englisch

**Verfügbare Sprachen:**

- **Deutsch** (de) - Standard
- **Englisch** (en) - Vollständig

**Sprachdateien:**

- `lang/lib-common.[de|en]` - Kern-Funktionen
- `lang/lib-cd.[de|en]` - Audio-CD Support
- `lang/lib-dvd.[de|en]` - Video-DVD Support
- `lang/lib-bluray.[de|en]` - Blu-ray Support
- `lang/lib-folders.[de|en]` - Verzeichnisverwaltung
- `lang/lib-tools.[de|en]` - Tool-Erkennung
- `lang/debugmsg.en` - Debug-Meldungen (nur Englisch)

**Sprache ändern:**

Setze `LANGUAGE="en"` in `disk2iso-lib/config.sh`

## 🔧 Service-Modus (Automatisch)

```bash
# Service aktivieren und starten
sudo systemctl enable disk2iso.service
sudo systemctl start disk2iso.service

# Status prüfen
sudo systemctl status disk2iso.service

# Logs verfolgen
sudo journalctl -u disk2iso.service -f
```

Im Service-Modus:

1. Medium einlegen
2. Automatische Erkennung und Archivierung
3. Medium wird automatisch ausgeworfen
4. Bereit für nächstes Medium

## 📁 Projekt-Struktur

```txt
disk2iso/
├── disk2iso.sh              # Hauptskript mit modularem Loading
├── install.sh               # Installations-Script (modular, 9 Seiten)
├── uninstall.sh             # Deinstallations-Script
└── disk2iso-lib/            # Bibliotheken
    ├── config.sh            # Konfiguration + Sprach-Einstellung
    ├── lib-bluray.sh        # Blu-ray Funktionen (OPTIONAL) - Definiert BD_DIR
    ├── lib-cd.sh            # Audio-CD Funktionen (OPTIONAL) - Definiert AUDIO_DIR
    ├── lib-dvd.sh           # Video-DVD Funktionen (OPTIONAL) - Definiert DVD_DIR
    ├── lib-mqtt.sh          # MQTT/Home Assistant (OPTIONAL)
    ├── lib-common.sh        # Daten-Disc Kopierfunktionen (KERN) - Definiert DATA_DIR
    ├── lib-diskinfos.sh     # Disc-Typ-Erkennung (KERN)
    ├── lib-drivestat.sh     # Laufwerk-Status (KERN)
    ├── lib-files.sh         # Dateinamen-Verwaltung (KERN)
    ├── lib-folders.sh       # Ordner-Verwaltung mit Gettern (KERN)
    ├── lib-logging.sh       # Logging-System + Sprachsystem (KERN)
    └── lang/
        ├── lib-common.de    # Deutsche Meldungen für Kern-Funktionen
        ├── lib-cd.de        # Deutsche Meldungen für Audio-CD
        ├── lib-dvd.de       # Deutsche Meldungen für Video-DVD
        ├── lib-bluray.de    # Deutsche Meldungen für Blu-ray
        └── lib-mqtt.de      # Deutsche Meldungen für MQTT
```

### Modulare Architektur

**Kern-Module (immer geladen):**

- Daten-Disc Unterstützung (dd, ddrescue)
- Laufwerkserkennung und -überwachung
- Logging und Datei-Management

**Optionale Module (konditional geladen):**

- `lib-cd.sh` - Nur wenn Audio-CD Support gewählt
- `lib-dvd.sh` - Nur wenn Video-DVD Support gewählt
- `lib-bluray.sh` - Nur wenn Blu-ray Support gewählt
- `lib-mqtt.sh` - Nur wenn MQTT-Integration aktiviert

**Pfad-Verwaltung:**

- Jedes Modul definiert eigene Pfad-Konstanten (`AUDIO_DIR`, `DVD_DIR`, `BD_DIR`)
- `lib-folders.sh` nutzt Getter-Methoden (`get_path_audio()`, `get_path_dvd()`, etc.)
- Graceful Degradation: Fehlende Module → Fallback auf `data/`

**Sprachsystem:**

- Jedes Modul lädt eigene Sprachdatei beim Start: `load_module_language("cd")`
- Sprachdateien: `lang/lib-[modul].[LANGUAGE]`
- Fallback auf Englisch wenn Sprache fehlt
- Konfigurierbar via `LANGUAGE` in config.sh

**Vorteile:**

- Minimale Installation möglich (nur Daten-Disks)
- Fehlende Module führen zu graceful degradation
- Klare Trennung der Funktionalitäten
- Konsistente lowercase Ordnerstruktur

## 📂 Verzeichnisstruktur der Ausgabe

```text
${DEFAULT_OUTPUT_DIR}/       # Konfiguriert in /opt/disk2iso/lib/config.sh
├── audio/                   # Audio-CDs (nur mit lib-cd.sh)
│   ├── artist_album.iso
│   ├── artist_album.md5
│   └── ...
├── data/                    # Daten-Discs (cd-rom, dvd-rom, bd-rom)
│   ├── disc_label.iso
│   ├── disc_label.md5
│   └── ...
├── dvd/                     # Video-DVDs (nur mit lib-dvd.sh)
│   ├── movie_title.iso
│   ├── movie_title.md5
│   └── ...
├── bd/                      # Blu-ray Videos (nur mit lib-bluray.sh)
│   ├── movie_title.iso
│   ├── movie_title.md5
│   └── ...
├── log/                     # Zentrale Log-Dateien
│   ├── disc_label.log
│   └── ...
└── temp/                    # Temporäre Arbeitsverzeichnisse
    ├── mountpoints/         # Mount-Points für Label-Erkennung
    └── disc_label_$$/       # Wird nach Abschluss gelöscht
```

### Pfad-Logik mit Graceful Degradation

```bash
# Beispiel: DVD-Video ohne lib-dvd.sh installiert
get_path_dvd() → Fallback auf data/

# Alle Disc-Typen haben Fallback-Pfad
audio-cd   → audio/ (oder data/ wenn lib-cd.sh fehlt)
dvd-video  → dvd/   (oder data/ wenn lib-dvd.sh fehlt)
bd-video   → bd/    (oder data/ wenn lib-bluray.sh fehlt)
*-rom      → data/  (immer verfügbar)
```

## �🔧 Deinstallation

```bash
sudo ./uninstall.sh
```

Das Skript:

- ✅ Stoppt und deaktiviert den Service
- ✅ Entfernt alle installierten Dateien
- ✅ Optional: Löscht archivierte Daten

## 📝 Ausgabe-Dateien

### ISO-Images (alle Disc-Typen)

- **Dateiname:** `disc_label.iso` (bereinigt, lowercase)
- **MD5-Checksumme:** `disc_label.md5`
- **Log-Datei:** `disc_label.log` (im separaten .log/ Verzeichnis, versteckt)
- **Speicherort:** `OUTPUT_DIR/[disc-type]/`

**Disc-Type Unterordner:**

- `audio/` - Audio-CD ISOs mit MP3s
- `data/` - Daten-CDs, Daten-DVDs, Daten-Blu-rays
- `dvd/` - Video-DVDs (entschlüsselt/verschlüsselt)
- `bd/` - Blu-ray Videos (entschlüsselt/verschlüsselt)
- `.log/` - Alle Log-Dateien (zentral, versteckt)
- `.temp/` - Temporäre Dateien (werden nach Abschluss gelöscht, versteckt)

### Audio-CDs (mit lib-cd.sh)

**Struktur innerhalb der ISO:**

```text
AlbumArtist/
  Album/
    Artist - Title.mp3
    folder.jpg (Cover)
    album.nfo (Jellyfin-Metadaten)
```

**ID3-Tags:** Artist, Album, Title, Track, Year

## 🛡️ Fehlerbehandlung

- **Robustes Kopieren:** Automatischer Fallback von ddrescue → dd
- **Error Recovery:** Automatisches Cleanup bei Fehlern
- **Signal-Handling:** Sauberes Beenden bei SIGTERM/SIGINT
- **Mount-Point Safety:** Sichere Pfade in OUTPUT_DIR statt /tmp

## 🤝 Beitragen

Beiträge sind willkommen! Bitte:

1. Forken Sie das Repository
2. Erstellen Sie einen Feature-Branch (`git checkout -b feature/AmazingFeature`)
3. Committen Sie Ihre Änderungen (`git commit -m 'Add AmazingFeature'`)
4. Pushen Sie zum Branch (`git push origin feature/AmazingFeature`)
5. Öffnen Sie einen Pull Request

## 📜 Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert - siehe [LICENSE](LICENSE) Datei für Details.

## 🙏 Danksagungen

- MusicBrainz für die Metadaten-API
- MakeMKV für Blu-ray Unterstützung
- Alle Open-Source Tool-Entwickler

## 📞 Support

Bei Problemen oder Fragen:

- Öffnen Sie ein Issue auf GitHub
- Prüfen Sie die Logs: `journalctl -u disk2iso.service`

## 🗺️ Roadmap

- [x] Modulare Architektur mit optionalen Features
- [x] Dezentrale Dependency-Checks pro Modul
- [x] MakeMKV Integration für Blu-ray
- [x] MQTT-Integration für Home Assistant
- [ ] CD-Text Unterstützung
- [ ] Web-Interface für Monitoring und Konfiguration
- [ ] Weitere Sprachen (EN, FR, ES)
- [ ] Automatische Discogs-Integration für Audio-CDs
- [ ] Docker-Container für einfache Deployment
- [ ] Batch-Processing-Modus für mehrere Discs
- [ ] REST-API für externe Steuerung

---

**Version:** 1.2.0  
**Autor:** Dirk  
**Status:** Production Ready  
**Letzte Aktualisierung:** 06.01.2026
