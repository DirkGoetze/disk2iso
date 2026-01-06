# disk2iso - Vollständiges Handbuch

Willkommen zur ausführlichen Dokumentation von disk2iso - dem professionellen Tool zur Archivierung optischer Medien.

## 📚 Inhaltsverzeichnis

### [1. Übersicht](#übersicht)
Allgemeine Informationen, Features und Systemarchitektur

### [2. Installation als Script](Installation-Script.md)
Manuelle Installation und Konfiguration ohne systemd-Service

### [3. Installation als Service](Installation-Service.md)
Automatische Installation mit systemd-Integration für permanenten Betrieb

### [4. Verwendung](Verwendung.md)
Bedienung, Konfiguration und praktische Beispiele

### [5. MQTT & Home Assistant Integration](MQTT-HomeAssistant.md)
Echtzeit-Status, Benachrichtigungen und Dashboard-Integration

### [6. Entwickler-Dokumentation](Entwickler.md)
Technische Details, Modulstruktur und API-Referenz

### [7. Deinstallation](Deinstallation.md)
Vollständige Entfernung von disk2iso

---

## Übersicht

### Was ist disk2iso?

disk2iso ist ein modulares Bash-basiertes Tool zur automatischen Archivierung optischer Medien (CDs, DVDs, Blu-rays) als ISO-Images. Es kombiniert intelligente Medien-Erkennung mit optimierten Kopiermethoden für jeden Disc-Typ.

### Hauptmerkmale

#### 🎯 Automatische Medien-Erkennung
- **6 Disc-Typen**: audio-cd, dvd-video, bd-video, cd-rom, dvd-rom, bd-rom
- **Intelligente Analyse**: UDF, ISO9660, Audio-CD Format-Erkennung
- **Label-Extraktion**: Automatische Disc-Namen via isoinfo oder blkid

#### 🎵 Audio-CD Support (Modul: lib-cd.sh)
- **Lossless Ripping**: cdparanoia mit Fehlerkorrektur
- **MP3-Encoding**: LAME VBR V2 (~190 kbps, fest kodiert)
- **MusicBrainz-Integration**:
  - Automatische Disc-ID-Erkennung
  - Metadaten-Lookup (Artist, Album, Track, Jahr)
  - Album-Cover Download (Cover Art Archive)
- **ID3-Tags**: Vollständige Metadaten-Einbettung
- **Jellyfin-Support**: NFO-Dateien für Media-Server

#### 📀 Video-DVD Support (Modul: lib-dvd.sh)
- **Entschlüsselung**: dvdbackup mit libdvdcss2
- **Fallback-Methoden**: ddrescue → dd
- **Priorität**: Entschlüsselt vor verschlüsselt
- **Struktur**: VIDEO_TS → ISO-Konvertierung

#### 🎬 Blu-ray Support (Modul: lib-bluray.sh)
- **Robustes Kopieren**: ddrescue (primär), dd (fallback)
- **UDF-Support**: Moderne Blu-ray-Dateisysteme
- **Große Medien**: Bis 100GB+ unterstützt
- **Verschlüsselt**: ISO-Kopie (Entschlüsselung extern möglich)

#### 💾 Daten-Discs (Kern-Modul)
- **Universell**: CD-ROM, DVD-ROM, BD-ROM
- **Methoden**: dd (schnell), ddrescue (bei Fehlern)
- **1:1 Kopie**: Bit-genaue ISO-Images

#### 🔐 Integrität & Qualität
- **MD5-Checksummen**: Automatisch für jede ISO
- **Fehlerbehandlung**: Robuste Recovery-Mechanismen
- **Fortschrittsanzeige**: Echtzeit-Feedback (MB/s, ETA)
- **Logging**: Detaillierte Log-Dateien pro Disc

#### 🌍 Mehrsprachigkeit
- **Modulares Sprachsystem**: Jedes Modul hat eigene Sprachdateien
- **Aktuell verfügbar**: Deutsch (de)
- **Erweiterbar**: Einfaches Hinzufügen neuer Sprachen
- **Fallback**: Englisch bei fehlenden Übersetzungen

#### 📡 MQTT-Integration (Modul: lib-mqtt.sh)
- **Home Assistant Support**: Native Integration über MQTT
- **Echtzeit-Status**: Live-Updates im Dashboard
- **Push-Benachrichtigungen**: Bei Medium-Wechsel, Abschluss, Fehler
- **Fortschrittsanzeige**: Prozent, MB, ETA
- **Availability-Tracking**: Online/Offline Status
- **Konfigurierbar**: Broker, Auth, Topics

### Systemarchitektur

```
┌─────────────────────────────────────────────────────────┐
│              disk2iso.sh (Hauptskript)                  │
│  • Laufwerks-Überwachung                                │
│  • Disc-Erkennung                                       │
│  • Modul-Loading (konditional)                          │
└──────────────┬──────────────────────────────────────────┘
               │
               ├── Kern-Module (immer geladen)
               │   ├── lib-common.sh      (Daten-Discs, Basis-Kopiermethoden)
               │   ├── lib-diskinfos.sh   (Disc-Typ-Erkennung)
               │   ├── lib-drivestat.sh   (Laufwerk-Status)
               │   ├── lib-files.sh       (Dateinamen-Verwaltung)
               │   ├── lib-folders.sh     (Ordner-Verwaltung)
               │   └── lib-logging.sh     (Logging + Sprachsystem)
               │
               └── Optionale Module (bei Installation wählbar)
                   ├── lib-cd.sh         (Audio-CD Ripping)
                   ├── lib-dvd.sh        (Video-DVD Backup)
                   ├── lib-bluray.sh     (Blu-ray Backup)
                   └── lib-mqtt.sh       (MQTT/Home Assistant Integration)
```

### Ausgabe-Struktur

```
OUTPUT_DIR/
├── audio/                  # Audio-CDs (nur mit lib-cd.sh)
│   └── Artist/
│       └── Album/
│           ├── 01 - Track.mp3
│           ├── 02 - Track.mp3
│           ├── folder.jpg
│           └── album.nfo
│
├── data/                   # Daten-CDs/DVDs/Blu-rays
│   ├── disc_label.iso
│   └── disc_label.md5
│
├── dvd/                    # Video-DVDs (nur mit lib-dvd.sh)
│   ├── movie_title.iso
│   └── movie_title.md5
│
├── bd/                     # Blu-ray Videos (nur mit lib-bluray.sh)
│   ├── movie_title.iso
│   └── movie_title.md5
│
├── .log/                   # Zentrale Log-Dateien (versteckt)
│   ├── disc_label.log
│   └── audio.log
│
└── .temp/                  # Temporär (auto-cleanup, versteckt)
    ├── mountpoints/        # Mount-Points für Label-Erkennung
    └── disc_label_$$/      # Arbeitsverzeichnisse
```

### Graceful Degradation

disk2iso funktioniert auch mit minimaler Installation:

| Modul fehlt | Disc-Typ | Fallback |
|-------------|----------|----------|
| lib-cd.sh | audio-cd | → data/ (dd/ddrescue) |
| lib-dvd.sh | dvd-video | → data/ (dd/ddrescue) |
| lib-bluray.sh | bd-video | → data/ (dd/ddrescue) |
| lib-mqtt.sh | - | Kein MQTT (nur lokales Logging) |

**Resultat**: Immer ein ISO-Image, auch wenn spezialisierte Module fehlen.

### Performance-Optimierungen

- **Lazy Initialization**: Verzeichnisse nur bei Bedarf erstellen
- **Intelligente Methoden-Wahl**: Beste Tool basierend auf Disc-Typ
- **Sequenzielle Verarbeitung**: Audio-Track-Encoding Track für Track (platzsparend)
- **Fortschritts-Monitoring**: Effizientes stat-basiertes Tracking

**Tatsächliche Verarbeitungszeiten** (gemessen):
- Audio-CD (12 Tracks): ~15 Min (MusicBrainz + MP3 + ISO)
- Video-DVD (7.5 GB): ~33 Min (dvdbackup entschlüsselt)
- Blu-ray (46.6 GB): ~42 Min (ddrescue, verschlüsselt)

### Sicherheits-Features

- **Root-Rechte erforderlich**: Zugriff auf optische Laufwerke
- **Sichere Mount-Points**: In OUTPUT_DIR statt /tmp
- **Signal-Handling**: Sauberes Cleanup bei SIGTERM/SIGINT
- **Temp-Verzeichnis Cleanup**: Automatisch nach jedem Vorgang
- **MD5-Checksummen**: Integritätsprüfung aller ISOs

### Unterstützte Plattformen

- **Primär**: Debian 12 (Bookworm) / Debian 13 (Trixie)
- **Getestet auf**: Ubuntu 22.04+, Linux Mint 21+
- **Voraussetzung**: Bash 4.0+, systemd (für Service-Modus)

### Lizenz & Credits

- **Lizenz**: MIT License
- **Sprache**: Bash
- **Abhängigkeiten**: Open Source Tools (cdparanoia, lame, dvdbackup, ddrescue)
- **API-Nutzung**: MusicBrainz (Community-Projekt)

---

## Navigation

**Weiter**: [Installation als Script →](Installation-Script.md)

**Siehe auch**:
- [Installation als Service](Installation-Service.md) - Automatischer Betrieb
- [Verwendung](Verwendung.md) - Praktische Anleitung
- [MQTT & Home Assistant](MQTT-HomeAssistant.md) - Integration & Dashboard
- [Entwickler-Dokumentation](Entwickler.md) - Technische Details
- [Deinstallation](Deinstallation.md) - Vollständige Entfernung

---

**Version**: 1.1.0 | **Letzte Aktualisierung**: 04.01.2026
