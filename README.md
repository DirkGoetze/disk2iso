# disk2iso - Automatisches Optical Media Archivierungstool

🚀 Professionelles Tool zur automatischen Archivierung von CDs, DVDs und Blu-rays als ISO-Images mit intelligenter Medien-Erkennung und MusicBrainz-Integration.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.debian.org/)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)

## ✨ Highlights

- 🎯 **Automatische Medien-Erkennung** - Unterscheidet 6 Disc-Typen (Audio-CD, DVD-Video, BD-Video, Data-CDs/DVDs/BDs)
- 🎵 **Audio-CD Ripping** - MP3-Encoding mit MusicBrainz-Metadaten und Album-Cover
- 📀 **Video-DVD Support** - Entschlüsselung mit dvdbackup/libdvdcss2
- 🎬 **Blu-ray Support** - Robustes Kopieren mit ddrescue
- 🔄 **Intelligente Methoden-Wahl** - Beste Kopiermethode basierend auf Disc-Typ und verfügbaren Tools
- ✅ **MD5-Checksummen** - Automatische Integritätsprüfung
- 🔧 **Systemd-Integration** - Automatischer Betrieb als Service
- 🌍 **Mehrsprachig** - Modulares Sprachsystem (aktuell: Deutsch)
- 🎨 **Whiptail-Wizard** - Komfortable grafische Installation (8 Seiten)

## 🚀 Quick Start

```bash
# Installation
git clone <repository-url>
cd disk2iso
sudo ./install.sh

# Manuelle Nutzung
sudo disk2iso -o /pfad/zum/ausgabe/verzeichnis

# Als Service
sudo systemctl start disk2iso
```

## 💿 Unterstützte Medientypen

| Typ | Beschreibung | Methode | Modul |
|-----|-------------|---------|-------|
| 🎵 Audio-CD | MP3-Ripping mit MusicBrainz | cdparanoia + lame | lib-cd.sh |
| 📀 DVD-Video | Entschlüsselte Backups | dvdbackup/ddrescue | lib-dvd.sh |
| 🎬 Blu-ray Video | Robustes Kopieren | ddrescue/dd | lib-bluray.sh |
| 💾 Data-CD/DVD/BD | 1:1 ISO-Images | dd/ddrescue | Kern |

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
- Audio-CD: cdparanoia, lame, cd-discid, curl, jq, eyed3
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

### Manueller Modus
```bash
# Einzelne Disc
sudo disk2iso -o /media/nas/images

# Mit Debug-Ausgabe
DEBUG=1 sudo disk2iso -o /media/nas/images
```

### Service-Modus
```bash
# Service starten
sudo systemctl start disk2iso

# Status prüfen
sudo systemctl status disk2iso

# Logs verfolgen
sudo journalctl -u disk2iso -f
```

Im Service-Modus: Medium einlegen → automatische Archivierung → Auto-Eject

## 🗂️ Projekt-Struktur

```
disk2iso/
├── disk2iso.sh              # Hauptskript
├── install.sh               # 8-Seiten Wizard
├── uninstall.sh             # 4-Seiten Wizard
└── disk2iso-lib/
    ├── config.sh            # Konfiguration
    ├── lib-common.sh        # Kern (Daten-Discs)
    ├── lib-cd.sh            # Audio-CD (optional)
    ├── lib-dvd.sh           # Video-DVD (optional)
    ├── lib-bluray.sh        # Blu-ray (optional)
    ├── lib-*.sh             # Weitere Kern-Module
    ├── lang/*.de            # Deutsche Sprachdateien
    └── docu/                # Ausführliche Dokumentation
```

## ⚙️ Konfiguration

Bearbeite `disk2iso-lib/config.sh`:

```bash
LANGUAGE="de"                    # Sprache
OUTPUT_DIR="/srv/iso"            # Ausgabeverzeichnis
AUDIO_QUALITY="V2"               # MP3-Qualität (V0-V9)
AUDIO_USE_MUSICBRAINZ=true       # MusicBrainz-Lookup
AUDIO_DOWNLOAD_COVER=true        # Cover-Download
```

## 🧪 Debug-Modi

```bash
DEBUG=1 ./disk2iso.sh           # Zeigt alle ausgeführten Befehle
STRICT=1 ./disk2iso.sh          # Stoppt bei erstem Fehler
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
- **dvdbackup, libdvdcss2** - DVD-Entschlüsselung
- **ddrescue** - Robustes Kopieren

## 📞 Support

- 📖 [Dokumentation](disk2iso-lib/docu/Handbuch.md)
- 🐛 [Issues auf GitHub](../../issues)
- 💬 Logs: `journalctl -u disk2iso -f`

---

**Version:** 2.0.0 | **Status:** Production Ready | **Platform:** Debian Linux

## ✨ Features

- ✓ **Modulare Architektur** - Optionale Unterstützung für Audio-CD, Video-DVD, Blu-ray
- ✓ **Automatische Medien-Erkennung** - 6 spezialisierte Disc-Typen
- ✓ **Intelligente Methoden-Auswahl** - Beste Kopiermethode pro Medientyp
- ✓ **MD5-Checksummen** - Automatische Integritätsprüfung
- ✓ **Service-Modus** - systemd-Integration für automatischen Betrieb
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

**Video-DVD Support (lib-dvd.sh):**

- **dvdbackup** - DVD-Entschlüsselung (empfohlen)
- **libdvdcss2** - CSS-Entschlüsselung für kommerzielle DVDs (empfohlen)
- **genisoimage** - ISO-Erstellung aus VIDEO_TS (empfohlen)
- **gddrescue** - Fallback-Methode (optional)

**Blu-ray Support (lib-bluray.sh):**

- **makemkvcon** - Blu-ray-Entschlüsselung (empfohlen)
- **genisoimage** - ISO-Erstellung aus BDMV (empfohlen)
- **gddrescue** - Fallback-Methode (optional)

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

### Manueller Modus

```bash
# Mit Ausgabeverzeichnis
sudo ./disk2iso.sh -o /mnt/hdd/nas/images
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

### Debug-Modi

```bash
# Debug-Modus (zeigt jede ausgeführte Zeile):
DEBUG=1 ./disk2iso.sh

# Strict-Modus (stoppt bei Fehlern):
STRICT=1 ./disk2iso.sh

# Kombiniert:
DEBUG=1 STRICT=1 ./disk2iso.sh
```

### Service-Modus

```bash
sudo systemctl start disk2iso
sudo systemctl status disk2iso
sudo systemctl stop disk2iso
```

## 📋 Ausgabe

- ISO-Dateien: `/mnt/hdd/nas/images/`
- MD5-Checksummen: Gleicher Ordner wie ISO-Dateien (`.md5`)
- Log-Dateien: `/mnt/hdd/nas/images/logs/`

## ⚙️ Konfiguration

Bearbeite `disk2iso-lib/config.sh`:

```bash
# Sprach-Einstellung
LANGUAGE="de"                   # Sprache für Meldungen (de, en, ...)

# Ausgabe-Verzeichnis
OUTPUT_DIR="/mnt/hdd/nas/images"

# CD-Device (automatisch erkannt)
CD_DEVICE=""  # Leer lassen für Auto-Detect

# Audio-CD Einstellungen
AUDIO_QUALITY="V2"              # LAME VBR Qualität (V0-V9)
AUDIO_USE_MUSICBRAINZ=true      # MusicBrainz Metadaten-Lookup
AUDIO_USE_CDTEXT=true           # CD-TEXT Extraktion
AUDIO_DOWNLOAD_COVER=true       # Album-Cover herunterladen
```

### Mehrsprachigkeit

Das Sprachsystem ist modular aufgebaut:

- Jedes Modul hat eigene Sprachdateien: `lang/lib-[modul].[sprache]`
- Beim Laden eines Moduls wird automatisch die Sprachdatei geladen
- Fallback auf Englisch wenn Sprache nicht verfügbar

**Verfügbare Sprachdateien:**

- `lang/lib-common.de` - Kern-Funktionen
- `lang/lib-cd.de` - Audio-CD Support
- `lang/lib-dvd.de` - Video-DVD Support
- `lang/lib-bluray.de` - Blu-ray Support

**Neue Sprache hinzufügen:**

1. Kopiere `.de` Dateien zu `.en` (oder andere Sprache)
2. Übersetze die `MSG_*` Konstanten
3. Setze `LANGUAGE="en"` in config.sh

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
├── install.sh               # Installations-Script (modular)
├── uninstall.sh             # Deinstallations-Script
└── disk2iso-lib/            # Bibliotheken
    ├── config.sh            # Konfiguration + Sprach-Einstellung
    ├── lib-bluray.sh        # Blu-ray Funktionen (OPTIONAL) - Definiert BD_DIR
    ├── lib-cd.sh            # Audio-CD Funktionen (OPTIONAL) - Definiert AUDIO_DIR
    ├── lib-dvd.sh           # Video-DVD Funktionen (OPTIONAL) - Definiert DVD_DIR
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
        └── lib-bluray.de    # Deutsche Meldungen für Blu-ray
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

## � Verzeichnisstruktur der Ausgabe

```text
output_dir/                  # -o Parameter beim Start
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
- [ ] CD-Text Unterstützung
- [ ] Web-Interface für Monitoring und Konfiguration
- [ ] Weitere Sprachen (EN, FR, ES)
- [ ] Automatische Discogs-Integration für Audio-CDs
- [ ] Docker-Container für einfache Deployment
- [ ] Batch-Processing-Modus für mehrere Discs
- [ ] REST-API für externe Steuerung

---

**Version:** 2.0.0  
**Autor:** Dirk  
**Status:** Production Ready  
**Letzte Aktualisierung:** 30.12.2025
