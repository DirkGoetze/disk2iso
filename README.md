# disk2iso - Automatisches Optical Media Archivierungstool

🚀 Professionelles Tool zur automatischen Archivierung von CDs, DVDs und Blu-rays als ISO-Images mit State Machine, Web-Interface und MusicBrainz-Integration.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.debian.org/)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/Version-1.2.0-blue.svg)](doc/Handbuch.md)

## ✨ Highlights

- 🎯 **Automatische Medien-Erkennung** - Unterscheidet 6 Disc-Typen (Audio-CD, DVD-Video, BD-Video, Data-CDs/DVDs/BDs)
- 🔄 **State Machine** - 11 definierte Zustände für präzise Ablaufsteuerung
- 🌐 **Web-Interface** - Modernes Dashboard mit Live-Updates (Flask, Port 8080)
- 🎵 **Audio-CD Ripping** - MP3-Encoding mit MusicBrainz-Metadaten, CD-TEXT Fallback und Album-Cover
- 📀 **Video-DVD Support** - Entschlüsselung mit dvdbackup/libdvdcss2 & intelligenter Retry-Mechanismus
- 🎬 **Blu-ray Support** - Robustes Kopieren mit ddrescue
- 🔧 **Systemd-Integration** - Automatischer Betrieb als Service
- 📡 **MQTT/Home Assistant** - Echtzeit-Status, Push-Benachrichtigungen, Dashboard
- 🌍 **Mehrsprachig** - 4 vollständige Sprachen (de, en, es, fr)
- 📊 **JSON REST API** - Vollständige Programmierschnittstelle für externe Tools

## 🚀 Quick Start

```bash
# Installation
git clone <repository-url>
cd disk2iso
sudo ./install.sh

# Interaktiver Wizard installiert automatisch alle Abhängigkeiten
```

**Manuelle Abhängigkeiten-Installation:**
```bash
# Kern-Pakete (immer erforderlich)
sudo apt install -y coreutils util-linux genisoimage gddrescue eject mount

# Audio-CD Support (optional)
sudo apt install -y cdparanoia lame eyed3 curl jq cd-discid wodim libcdio-utils

# Video-DVD Support (optional)
sudo apt install -y dvdbackup libdvd-pkg

# Web-Interface (optional)
sudo apt install -y python3 python3-pip python3-venv

# MQTT-Integration (optional)
sudo apt install -y mosquitto-clients
```

**Weitere Details:** [Installation-Script](doc/Installation-Script.md) | [Installation-Service](doc/Installation-Service.md)

# Service starten
sudo systemctl start disk2iso
sudo systemctl start disk2iso-web

# Web-Interface öffnen
# Browser: http://localhost:8080
```

## 💿 Unterstützte Medientypen

| Typ | Beschreibung | Methode | 
|-----|-------------|---------|
| 🎵 Audio-CD | MP3-Ripping mit MusicBrainz/CD-TEXT | cdparanoia + lame |
| 📀 DVD-Video | Entschlüsselte Backups | dvdbackup/ddrescue |
| 🎬 Blu-ray Video | Robustes Kopieren | ddrescue/dd |
| 💾 Data-CD/DVD/BD | 1:1 ISO-Images | dd/ddrescue |

## 📖 Dokumentation

📚 **[Vollständiges Handbuch](doc/Handbuch.md)** - Ausführliche Dokumentation mit:
- **[Installation](doc/Installation-Service.md)** - Automatische Installation mit systemd
- **[Verwendung](doc/Verwendung.md)** - Bedienung, Web-Interface und Konfiguration
- **[MQTT Integration](doc/MQTT-HomeAssistant.md)** - Home Assistant Anbindung
- **[Entwickler-Infos](doc/Entwickler.md)** - Technische Details und API-Referenz
- **[Deinstallation](doc/Deinstallation.md)** - Vollständige Entfernung

## 🎯 Hauptfunktionen

### 🔄 Automatischer Workflow
1. Medium einlegen → Automatische Typ-Erkennung
2. Beste Kopiermethode wählen
3. Archivierung mit Fortschrittsanzeige
4. MD5-Checksumme erstellen
5. Medium automatisch auswerfen

### 🎵 Audio-CD Features
- MusicBrainz-Metadaten (Artist, Album, Track, Jahr)
- Album-Cover Download und Einbettung
- CD-TEXT Fallback
- Jellyfin-kompatible Ausgabe
- **Nachträgliche Metadaten-Erfassung** (v1.2.0+)
  - ISO-Remastering mit korrekten Tags über Web-Interface
  - MusicBrainz-Suche für bereits erstellte ISOs

### 🌐 Web-Interface
- Live-Status Dashboard
- Fortschrittsanzeige (Prozent, MB, ETA)
- Archiv-Verwaltung mit Kategorisierung
- **Nachträgliche Metadaten-Erfassung** (v1.2.0+)
  - MusicBrainz-Suche für Audio-CDs
  - TMDB-Suche für DVDs/Blu-rays (Filme & TV-Serien)
  - ISO-Remastering mit korrekten Tags
- Logs und Systeminfos
- 4 Sprachen (de, en, es, fr)

### 📡 MQTT/Home Assistant
- Echtzeit-Status Updates
- Push-Benachrichtigungen
- Fortschritts-Sensor
- Availability-Tracking

## 📁 Ausgabe-Struktur

```
output_dir/
├── audio/          # Audio-CDs (Artist/Album/Track.mp3 + Cover)
├── data/           # Daten-CDs/DVDs/Blu-rays (*.iso)
├── dvd/            # Video-DVDs (*.iso)
├── bd/             # Blu-ray Videos (*.iso)
├── .log/           # Log-Dateien (versteckt)
└── .temp/          # Temporäre Dateien (versteckt)
```

Jede ISO-Datei erhält automatisch:
- MD5-Checksumme (`.md5`)
- Log-Datei im `.log/` Verzeichnis

## ⚙️ Konfiguration

Konfigurationsdatei: `/opt/disk2iso/lib/config.sh`

```bash
DEFAULT_OUTPUT_DIR="/media/iso"  # Ausgabeverzeichnis
LANGUAGE="de"                    # Sprache (de, en, es, fr)
MQTT_ENABLED=false               # MQTT Integration
```

Nach Änderungen Service neu starten: `sudo systemctl restart disk2iso`

**Weitere Details:** [Verwendung](doc/Verwendung.md)

## 🔧 Service-Verwaltung

```bash
# Service steuern
sudo systemctl start disk2iso
sudo systemctl stop disk2iso
sudo systemctl status disk2iso

# Logs verfolgen
sudo journalctl -u disk2iso -f
```

## 🗑️ Deinstallation

```bash
sudo ./uninstall.sh
```

Wizard-geführte Deinstallation mit optionaler Löschung des Ausgabeverzeichnisses.

**Weitere Details:** [Deinstallation](doc/Deinstallation.md)

## 📝 Lizenz

MIT License - siehe [LICENSE](LICENSE)

## 🤝 Beitragen

Contributions sind willkommen! Bitte:
1. Fork erstellen
2. Feature-Branch erstellen
3. Pull Request öffnen

## 🙏 Credits

- **MusicBrainz** - Metadaten-API
- **cdparanoia, lame** - Audio-CD Ripping
- **dvdbackup, libdvdcss2** - DVD-Entschlüsselung
- **ddrescue** - Robustes Kopieren

## 📞 Support

- �� [Vollständige Dokumentation](doc/Handbuch.md)
- 🐛 [Issues auf GitHub](../../issues)
- 💬 Logs: `journalctl -u disk2iso -f`

---

**Version:** 1.2.0  
**Status:** Production Ready  
**Platform:** Debian Linux
