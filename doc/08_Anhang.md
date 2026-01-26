# Kapitel 8: Anhang

Referenzen, externe Abhängigkeiten und zusätzliche Ressourcen.

## Inhaltsverzeichnis

1. [Software-Abhängigkeiten](#software-abhängigkeiten)
2. [Externe APIs](#externe-apis)
3. [Dateiformate](#dateiformate)
4. [Glossar](#glossar)

---

## Software-Abhängigkeiten

### Übersicht externe Pakete

Alle von disk2iso verwendeten externen Software-Tools mit Versionsanforderungen.

| Software | Min. Version | Verwendende Module | Status | Paket-Name (Debian/Ubuntu) |
|----------|--------------|-------------------|--------|----------------------------|
| **Basis-System** |
| bash | 4.0 | Alle | **Pflicht** | bash |
| coreutils | 8.0 | Alle (dd, cat, ls, mv, cp, rm, etc.) | **Pflicht** | coreutils |
| util-linux | 2.30 | Alle (blkid, lsblk, eject, mount, umount, findmnt) | **Pflicht** | util-linux |
| genisoimage | 1.1.11 | Alle (isoinfo), Audio-CD, DVD-Video | **Pflicht** | genisoimage |
| md5sum | - | Alle (Checksummen) | **Pflicht** | coreutils |
| systemd | 232 | Service-Modus | **Pflicht*** | systemd |
| whiptail | - | Installer-Wizard | **Pflicht*** | whiptail |
| **Audio-CD Modul** |
| cdparanoia | 3.10.2 | Audio-CD (Ripping) | Optional | cdparanoia |
| lame | 3.100 | Audio-CD (MP3-Encoding) | Optional | lame |
| eyed3 | 0.8 | Audio-CD (ID3-Tags) | Optional | eyed3 |
| cd-discid | 1.4 | Audio-CD (MusicBrainz Disc-ID) | Optional | cd-discid |
| curl | 7.0 | Audio-CD, DVD-Video, Blu-ray (API-Calls) | Optional | curl |
| jq | 1.5 | Audio-CD, DVD-Video, Blu-ray (JSON-Parsing) | Optional | jq |
| wodim | - | Audio-CD (Alternative zu cdparanoia) | Optional | wodim |
| libcdio-utils | - | Audio-CD (cd-info, icedax, cdda2wav Fallbacks) | Optional | libcdio-utils |
| **DVD-Video Modul** |
| dvdbackup | 0.4.2 | DVD-Video (Primäre Kopiermethode) | Optional | dvdbackup |
| libdvdcss2 | 1.4.0 | DVD-Video (CSS-Entschlüsselung) | Optional | libdvd-pkg |
| ddrescue | 1.23 | DVD-Video (Fehlertolerante Kopie), Blu-ray | Optional | gddrescue |
| **Blu-ray Modul** |
| ddrescue | 1.23 | Blu-ray (Primäre Kopiermethode) | Optional | gddrescue |
| dd | - | Blu-ray (Fallback-Methode) | Optional | coreutils |
| blockdev | - | Blu-ray (Disc-Größe ermitteln) | Optional | util-linux |
| **MQTT Integration** |
| mosquitto_pub | 1.6 | MQTT (Nachrichten senden) | Optional | mosquitto-clients |
| **Web-Interface** |
| python3 | 3.7 | Web-Interface (Flask-Backend) | Optional** | python3 |
| python3-flask | 1.0 | Web-Interface (HTTP-Server) | Optional** | python3-flask |
| python3-markdown | 3.0 | Web-Interface (Hilfe-Seiten) | Optional** | python3-markdown |
| **System-Tools** |
| systemd-notify | - | Service-Modus (Statusmeldungen) | Optional | systemd |
| udevadm | - | Laufwerkserkennung (erweitert) | Optional | udev |
| dmesg | - | Laufwerkserkennung (Fallback) | Optional | util-linux |
| modprobe | - | Laufwerkserkennung (Kernel-Module) | Optional | kmod |
| flock | - | Blu-ray (Datei-Locking) | Optional | util-linux |

**Legende:**

- **Pflicht**: Für Basisfunktionalität (Data-Disc Backup) erforderlich
- **Pflicht***: Nur für spezifischen Modus erforderlich (Service / Installer)
- **Optional**: Nur für optionale Module erforderlich (Audio-CD, DVD-Video, Blu-ray, MQTT)
- **Optional****: Web-Interface wird empfohlen, aber nicht zwingend erforderlich

---

### Installationsreferenz

#### Minimale Installation (Data-Discs only)

```bash
# Nur Kern-Pakete
sudo apt update
sudo apt install -y bash coreutils util-linux genisoimage
```

**Funktioniert für:**
- CD-ROM Backup
- DVD-ROM Backup
- BD-ROM Backup (verschlüsselt)

**Nicht verfügbar:**
- Audio-CD Ripping
- DVD-Video Entschlüsselung
- Blu-ray mit ddrescue
- Metadaten (MusicBrainz/TMDB)
- MQTT Integration

---

#### Standard-Installation

```bash
sudo apt update

# Kern-Pakete
sudo apt install -y coreutils util-linux genisoimage eject mount whiptail

# Audio-CD Modul
sudo apt install -y cdparanoia lame eyed3 curl jq cd-discid wodim libcdio-utils

# Video-DVD Modul
sudo apt install -y dvdbackup libdvd-pkg
sudo dpkg-reconfigure libdvd-pkg  # libdvdcss2 installieren

# MQTT Integration
sudo apt install -y mosquitto-clients

# Web-Interface
sudo apt install -y python3 python3-flask python3-markdown
```

**Funktioniert für:**
- Audio-CD → MP3 + MusicBrainz
- DVD-Video → ISO + TMDB (entschlüsselt)
- Data-Discs
- MQTT / Home Assistant
- Web-Interface

**Nicht verfügbar:**
- Blu-ray Support

---

#### Vollständige Installation

```bash
# Standard-Installation +
sudo apt install -y gddrescue  # Blu-ray + DVD-Fallback
```

**Alle Features verfügbar!**

---

### Versionen prüfen

```bash
# Bash-Version
bash --version

# coreutils (dd)
dd --version

# genisoimage
genisoimage --version

# cdparanoia
cdparanoia --version

# lame
lame --version

# eyed3
eyeD3 --version

# dvdbackup
dvdbackup --version

# ddrescue
ddrescue --version

# Python
python3 --version

# Flask
python3 -c "import flask; print(flask.__version__)"

# systemd
systemctl --version

# jq
jq --version

# curl
curl --version

# mosquitto_pub
mosquitto_pub --help
```

---

## Externe APIs

### MusicBrainz API

**Verwendet von:** Audio-CD Modul (Metadaten-Erfassung)

| Eigenschaft | Wert |
|-------------|------|
| **Base-URL** | `https://musicbrainz.org/ws/2/` |
| **Authentifizierung** | Keine (öffentlich) |
| **Rate-Limit** | 1 Request/Sekunde (50 Requests/Sekunde mit OAuth) |
| **API-Version** | v2 |
| **Dokumentation** | https://musicbrainz.org/doc/MusicBrainz_API |
| **User-Agent** | `disk2iso/1.2.0 (https://github.com/DirkGoetze/disk2iso)` |
| **Response-Format** | JSON, XML |

**Verwendete Endpoints:**

```
GET /ws/2/discid/{disc_id}?fmt=json&inc=artist-credits+recordings
```

**Beispiel:**
```bash
curl -H "User-Agent: disk2iso/1.2.0" \
  "https://musicbrainz.org/ws/2/discid/76118c18?fmt=json&inc=artist-credits+recordings"
```

**Cover Art Archive:**

```
GET http://coverartarchive.org/release/{release_id}/front-500
```

---

### TMDB API

**Verwendet von:** DVD-Video & Blu-ray Modul (Metadaten-Erfassung)

| Eigenschaft | Wert |
|-------------|------|
| **Base-URL** | `https://api.themoviedb.org/3/` |
| **Authentifizierung** | API-Key erforderlich (kostenlos) |
| **Rate-Limit** | 40 Requests/10 Sekunden |
| **API-Version** | v3 |
| **Dokumentation** | https://developers.themoviedb.org/3 |
| **Response-Format** | JSON |

**API-Key beantragen:**
1. Account erstellen: https://www.themoviedb.org/signup
2. API-Key beantragen: https://www.themoviedb.org/settings/api
3. In `conf/libtmdb.ini` eintragen: `TMDB_API_KEY="dein_key"`

**Verwendete Endpoints:**

```
GET /search/movie?query={title}&year={year}
GET /search/tv?query={title}
GET /movie/{id}
GET /tv/{id}
```

**Beispiel:**
```bash
curl "https://api.themoviedb.org/3/search/movie?api_key=YOUR_KEY&query=Matrix&year=1999"
```

**Poster-Download:**

```
https://image.tmdb.org/t/p/w500/{poster_path}
```

---

## Dateiformate

### ISO-Images

**Format:** ISO 9660 (Level 1/2/3), UDF 1.02/2.01/2.50/2.60

| Disc-Typ | Dateisystem | Max. Größe | Encoding |
|----------|-------------|------------|----------|
| CD-ROM | ISO 9660 | 700 MB | ISO-8859-1, Joliet |
| DVD-ROM | ISO 9660 + UDF 1.02 | 8.5 GB | UDF (UTF-8) |
| Blu-ray | UDF 2.50/2.60 | 128 GB | UDF (UTF-8) |

**Struktur:**

```
├── [CDFS] ISO 9660 Primary Volume Descriptor
│   ├── System Identifier
│   ├── Volume Identifier (Label)
│   └── Path Table
├── [UDF] Universal Disk Format (optional)
│   ├── Anchor Volume Descriptor
│   ├── File Set Descriptor
│   └── File Entries
└── Rock Ridge Extensions (Linux-Permissions, Symlinks)
```

---

### Audio-Formate

#### MP3 (MPEG-1 Audio Layer III)

| Eigenschaft | Wert |
|-------------|------|
| **Encoder** | LAME 3.100+ |
| **Modus** | VBR V2 (Variable Bitrate, Quality 2) |
| **Durchschnittliche Bitrate** | ~190 kbps |
| **Sample-Rate** | 44.1 kHz (CD-Standard) |
| **Kanäle** | Stereo (2.0) |
| **ID3-Tags** | ID3v2.4 (UTF-8) |

**LAME VBR V2 Quality-Skala:**
- V0 (~245 kbps) - Höchste Qualität
- **V2 (~190 kbps)** - Empfohlene Qualität (disk2iso Standard)
- V4 (~165 kbps) - Gute Qualität
- V9 (~65 kbps) - Minimale Qualität

**ID3v2.4 Tags (disk2iso):**
```
- TIT2: Titel (z.B. "Bohemian Rhapsody")
- TPE1: Artist (z.B. "Queen")
- TALB: Album (z.B. "A Night at the Opera")
- TDRC: Jahr (z.B. "1975")
- TRCK: Track-Nummer (z.B. "11/12")
- APIC: Cover-Bild (JPEG, 500x500)
```

---

#### WAV (Intermediate Format)

| Eigenschaft | Wert |
|-------------|------|
| **Format** | PCM (Pulse Code Modulation) |
| **Bittiefe** | 16-bit |
| **Sample-Rate** | 44.1 kHz |
| **Kanäle** | Stereo (2.0) |
| **Bitrate** | 1411 kbps (unkomprimiert) |

**Verwendung:**
1. cdparanoia extrahiert → WAV (lossless)
2. LAME encodiert WAV → MP3 (lossy)
3. WAV wird gelöscht (Speicherplatzoptimierung)

---

### Metadaten-Formate

#### NFO-Dateien (Jellyfin/Kodi)

**Zwei Varianten:**

**1. XML-Format (Standard für Video):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<movie>
  <title>The Matrix</title>
  <year>1999</year>
  <genre>Sci-Fi</genre>
  <director>Lana Wachowski, Lilly Wachowski</director>
  <runtime>136</runtime>
  <rating>8.7</rating>
  <plot>Neo discovers the true nature of reality...</plot>
  <thumb>poster.jpg</thumb>
</movie>
```

**2. Key-Value-Format (Alternative für Audio):**

```ini
Artist=Queen
Album=A Night at the Opera
Year=1975
Genre=Rock
Tracks=12
Label=EMI
Country=GB
MusicBrainz_ID=6defd963-fe91-4550-b18e-82c685603c2b
```

---

## Glossar

### Disc-Typen

| Begriff | Beschreibung |
|---------|--------------|
| **audio-cd** | Audio-CD mit CD-DA Format (Digital Audio), erkennbar an TOC |
| **cd-rom** | Daten-CD mit ISO 9660 / Joliet Dateisystem |
| **dvd-video** | Video-DVD mit VIDEO_TS-Ordner, enthält VOB/IFO/BUP Dateien |
| **dvd-rom** | Daten-DVD mit ISO 9660 / UDF Dateisystem |
| **bd-video** | Blu-ray Disc mit BDMV-Ordner, UDF 2.50+ Dateisystem |
| **bd-rom** | Daten-Blu-ray mit UDF 2.50/2.60 Dateisystem |

---

### Dateisysteme

| Begriff | Beschreibung |
|---------|--------------|
| **ISO 9660** | Standard-Dateisystem für CDs/DVDs (definiert in ECMA-119) |
| **Joliet** | Microsoft-Erweiterung zu ISO 9660 (Unicode-Dateinamen) |
| **Rock Ridge** | POSIX-Erweiterung zu ISO 9660 (Permissions, Symlinks, lange Namen) |
| **UDF** | Universal Disk Format (moderne Alternative zu ISO 9660) |
| **UDF 1.02** | Standard für DVDs |
| **UDF 2.50/2.60** | Standard für Blu-rays (große Dateien >4GB) |
| **CD-DA** | Compact Disc Digital Audio (Audio-CD Format, kein Dateisystem) |

---

### Kopiermethoden

| Begriff | Beschreibung |
|---------|--------------|
| **dd** | Bit-genaue Kopie (schnell, keine Fehlertoleranz) |
| **ddrescue** | Robuste Kopie mit Fehlertoleranz (langsamer, aber zuverlässiger) |
| **dvdbackup** | DVD-spezifische Kopie mit libdvdcss2-Entschlüsselung |
| **cdparanoia** | Audio-CD Ripping mit Fehlerkorrektur (Jitter-Correction) |
| **genisoimage** | VIDEO_TS Ordner → ISO-Image konvertieren |

---

### Metadaten-Quellen

| Begriff | Beschreibung |
|---------|--------------|
| **MusicBrainz** | Freie Musik-Datenbank (Audio-CDs) |
| **Disc-ID** | SHA-1 Hash des TOC (Table of Contents) einer Audio-CD |
| **CD-TEXT** | Text-Informationen auf Audio-CD (Artist/Album, optional) |
| **TMDB** | The Movie Database (Filme & TV-Serien) |
| **NFO** | Textdatei mit Metadaten (Jellyfin/Kodi/Plex-kompatibel) |

---

### Verschlüsselung

| Begriff | Beschreibung |
|---------|--------------|
| **CSS** | Content Scramble System (DVD-Kopierschutz) |
| **libdvdcss2** | Open-Source Bibliothek zur CSS-Entschlüsselung |
| **AACS** | Advanced Access Content System (Blu-ray-Kopierschutz) |
| **BD+** | Zusätzlicher Blu-ray-Kopierschutz (Java-VM-basiert) |

**Hinweis:** disk2iso entschlüsselt nur CSS (DVDs), nicht AACS/BD+ (Blu-rays).

---

### MQTT-Terminologie

| Begriff | Beschreibung |
|---------|--------------|
| **Broker** | MQTT-Server (z.B. Mosquitto) |
| **Publisher** | Sendet Nachrichten (disk2iso) |
| **Subscriber** | Empfängt Nachrichten (Home Assistant) |
| **Topic** | Hierarchischer Kanal (z.B. `disk2iso/state`) |
| **QoS** | Quality of Service (0=at most once, 1=at least once, 2=exactly once) |
| **Retained** | Nachricht bleibt erhalten (neue Subscriber bekommen sie sofort) |
| **LWT** | Last Will and Testament (Offline-Nachricht bei Verbindungsabbruch) |

---

### Home Assistant

| Begriff | Beschreibung |
|---------|--------------|
| **HA** | Home Assistant (Open-Source Home-Automation) |
| **Sensor** | Gerät mit Zustandswerten (z.B. disk2iso Status) |
| **Binary Sensor** | Sensor mit zwei Zuständen (on/off, z.B. "aktiv") |
| **Automation** | Regel-basierte Automatisierung (z.B. "Bei Abschluss → Benachrichtigung") |
| **Lovelace** | Home Assistant Dashboard (YAML- oder UI-konfiguriert) |
| **Card** | Dashboard-Widget (z.B. Sensor-Karte, Gauge, Markdown) |

---

## Weiterführende Links

### Dokumentation

- **[← Zurück zum Handbuch](Handbuch.md)** (Kapitel 1)
- **[Installation](02_Installation.md)** (Kapitel 2)
- **[Module](04_Module/)** (Kapitel 4)
- **[Entwickler-Dokumentation](06_Entwickler.md)** (Kapitel 6)

### Externe Ressourcen

#### MusicBrainz
- **API-Dokumentation**: https://musicbrainz.org/doc/MusicBrainz_API
- **Disc-ID berechnen**: https://musicbrainz.org/doc/Disc_ID_Calculation
- **Cover Art Archive**: https://coverartarchive.org/

#### TMDB
- **API-Dokumentation**: https://developers.themoviedb.org/3
- **API-Key beantragen**: https://www.themoviedb.org/settings/api
- **Image-API**: https://developers.themoviedb.org/3/getting-started/images

#### MQTT & Home Assistant
- **Mosquitto**: https://mosquitto.org/
- **Home Assistant**: https://www.home-assistant.io/
- **MQTT Integration**: https://www.home-assistant.io/integrations/mqtt/
- **Lovelace Cards**: https://www.home-assistant.io/lovelace/

#### Software-Pakete
- **cdparanoia**: https://www.xiph.org/paranoia/
- **LAME**: https://lame.sourceforge.io/
- **eyeD3**: https://eyed3.readthedocs.io/
- **dvdbackup**: http://dvdbackup.sourceforge.net/
- **libdvdcss**: https://www.videolan.org/developers/libdvdcss.html
- **ddrescue**: https://www.gnu.org/software/ddrescue/
- **genisoimage**: https://linux.die.net/man/1/genisoimage

#### Standards & Spezifikationen
- **ISO 9660**: https://en.wikipedia.org/wiki/ISO_9660
- **UDF**: https://en.wikipedia.org/wiki/Universal_Disk_Format
- **Joliet**: https://en.wikipedia.org/wiki/Joliet_(file_system)
- **Rock Ridge**: https://en.wikipedia.org/wiki/Rock_Ridge
- **CD-DA (Red Book)**: https://en.wikipedia.org/wiki/Compact_Disc_Digital_Audio
- **ID3v2.4**: https://id3.org/id3v2.4.0-structure

---

**Version**: 1.2.0 | **Letzte Aktualisierung**: 26.01.2026
