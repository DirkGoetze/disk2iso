# Installation als Script

Diese Anleitung beschreibt die Installation von disk2iso als manuell gestartetes Script ohne systemd-Service. Für automatischen Betrieb siehe [Installation als Service](Installation-Service.md).

## Inhaltsverzeichnis

1. [Voraussetzungen](#voraussetzungen)
2. [Download & Installation](#download--installation)
3. [Installer-Wizard](#installer-wizard)
4. [Manuelle Installation](#manuelle-installation)
5. [Modul-Auswahl](#modul-auswahl)
6. [Konfiguration](#konfiguration)
7. [Fehlerbehebung](#fehlerbehebung)

---

## Voraussetzungen

### System-Anforderungen

- **Distribution**: Debian 12+, Ubuntu 22.04+, Linux Mint 21+
- **Kernel**: Linux 5.0+ (für moderne Laufwerks-Treiber)
- **Bash**: Version 4.0 oder höher
- **Speicherplatz**: Minimal 100 MB (+ Platz für ISOs)
- **Optisches Laufwerk**: CD/DVD/Blu-ray kompatibel

### Berechtigungen

- **Root-Zugriff**: Erforderlich für Installation und Betrieb
- **sudo**: Empfohlen für sichere Rechteverwaltung

### Internet-Verbindung

- **Installation**: Zum Download der Abhängigkeiten (apt install)
- **Audio-CD**: Optional für MusicBrainz-Metadaten
- **Betrieb**: Offline-Modus möglich (ohne Metadaten)

---

## Download & Installation

### Schnellstart (empfohlen)

```bash
# 1. Projekt klonen
git clone https://github.com/username/disk2iso.git
cd disk2iso

# 2. Installer starten
sudo ./install.sh
```

Der **8-seitige Wizard** führt durch die Installation.

### Alternative: Direkter Download

```bash
# ZIP herunterladen
wget https://github.com/username/disk2iso/archive/refs/heads/main.zip
unzip main.zip
cd disk2iso-main

# Installer ausführbar machen
chmod +x install.sh
sudo ./install.sh
```

---

## Installer-Wizard

Der Installer ist als **interaktiver Assistent** mit 8 Seiten implementiert (whiptail/dialog).

### Seite 1: Willkommen

```
┌───────────────────────────────────────────────────────────┐
│  Willkommen zur Installation von disk2iso v1.1!          │
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

**Aktion**: Kurze Einführung, keine Eingaben erforderlich.

### Seite 2: Installations-Typ

```
┌───────────────────────────────────────────────────────────┐
│  Wählen Sie die gewünschte Installations-Art:            │
│                                                           │
│  (*) Nur Script                                           │
│      - Kein systemd-Service                              │
│      - Manuelle Ausführung: sudo disk2iso.sh            │
│      - Ideal zum Testen oder gelegentlichen Gebrauch     │
│                                                           │
│  ( ) Script + systemd-Service                             │
│      - Automatischer Start beim Booten                   │
│      - Überwacht Laufwerk permanent                      │
│      - Ideal für Server oder Dauerbetrieb                │
│                                                           │
│  [OK] [Abbrechen]                                         │
└───────────────────────────────────────────────────────────┘
```

**Auswahl**: 
- **Nur Script**: Fortfahren mit Seite 3 (Modul-Auswahl)
- **Script + Service**: Wechselt zu [Installation als Service](Installation-Service.md)

### Seite 3: Modul-Auswahl

```
┌───────────────────────────────────────────────────────────┐
│  Wählen Sie die zu installierenden Module:               │
│                                                           │
│  [X] Audio-CD Support (lib-cd.sh)                         │
│      • cdparanoia, lame, eyed3                           │
│      • MusicBrainz-Metadaten + Album-Cover              │
│                                                           │
│  [X] Video-DVD Support (lib-dvd.sh)                       │
│      • dvdbackup, genisoimage                            │
│      • Entschlüsselt DVDs mit libdvdcss2                 │
│                                                           │
│  [ ] Blu-ray Support (lib-bluray.sh)                      │
│      • ddrescue (robust), dd (fallback)                  │
│      • ISO-Kopie (verschlüsselt möglich)                 │
│                                                           │
│  [OK] [Abbrechen]                                         │
└───────────────────────────────────────────────────────────┘
```

**Standardwerte**: Audio-CD **ON**, Video-DVD **ON**, Blu-ray **OFF**  
**Hinweis**: Blu-ray standardmäßig aus, da weniger verbreitet.

**Navigation**:
- **Leertaste**: Modul an/ausschalten
- **Tab**: Zwischen Modulen und OK wechseln
- **Enter**: Bestätigen

### Seite 4: Laufwerks-Erkennung

```
┌───────────────────────────────────────────────────────────┐
│  Erkannte optische Laufwerke:                             │
│                                                           │
│  [X] /dev/sr0 (HL-DT-ST BD-RE BH16NS55)                   │
│      Typ: Blu-ray Writer                                  │
│                                                           │
│  [?] Laufwerk nicht erkannt?                              │
│      • Laufwerk physisch angeschlossen?                  │
│      • Kernel-Modul geladen? (lsmod | grep sr_mod)       │
│      • In BIOS aktiviert?                                │
│                                                           │
│  [OK] [Abbrechen]                                         │
└───────────────────────────────────────────────────────────┘
```

**Erkennung**: Automatisch via `/dev/sr*`  
**Fallback**: Falls nicht erkannt, wird `/dev/sr0` als Standard gesetzt.

### Seite 6: Abhängigkeiten installieren

```
┌───────────────────────────────────────────────────────────┐
│  Installiere Abhängigkeiten...                            │
│                                                           │
│  [################··················] 65%                │
│                                                           │
│  Aktuell: lame (MP3-Encoder)                             │
│                                                           │
│  Kern-Pakete:                                             │
│  ✓ coreutils, util-linux, genisoimage                    │
│  ✓ whiptail                                               │
│                                                           │
│  Audio-CD Module (lib-cd.sh):                             │
│  ⌛ cdparanoia, lame, eyed3                               │
│  ⌛ curl, jq (für MusicBrainz API)                        │
│                                                           │
│  Video-DVD Module (lib-dvd.sh):                           │
│  • dvdbackup, libdvdcss2                                 │
│                                                           │
│  Bitte warten...                                          │
└───────────────────────────────────────────────────────────┘
```

**Ablauf**:
1. `apt update` (Package-Listen aktualisieren)
2. Kern-Pakete installieren (immer)
3. Modul-spezifische Pakete (nur ausgewählte Module)
4. Fortschritts-Balken zeigt Status

**Dauer**: 1-5 Minuten (abhängig von Internet-Geschwindigkeit)

### Seite 7: Dateien kopieren

```
┌───────────────────────────────────────────────────────────┐
│  Kopiere Dateien nach /opt/disk2iso...                   │
│                                                           │
│  [██████████████████████████████████] 100%               │
│                                                           │
│  ✓ disk2iso.sh → /opt/disk2iso/                          │
│  ✓ lib-common.sh → /opt/disk2iso/disk2iso-lib/          │
│  ✓ lib-logging.sh → /opt/disk2iso/disk2iso-lib/         │
│  ✓ lib-files.sh → /opt/disk2iso/disk2iso-lib/           │
│  ✓ lib-cd.sh → /opt/disk2iso/disk2iso-lib/              │
│  ✓ lib-dvd.sh → /opt/disk2iso/disk2iso-lib/             │
│  ✓ config.sh → /opt/disk2iso/disk2iso-lib/              │
│  ✓ Sprachdateien → /opt/disk2iso/disk2iso-lib/lang/     │
│                                                           │
│  Symlink erstellt: /usr/local/bin/disk2iso               │
└───────────────────────────────────────────────────────────┘
```

**Installation-Struktur**:
```
/opt/disk2iso/
├── disk2iso.sh             # Hauptskript
├── disk2iso-lib/
│   ├── config.sh           # Konfiguration (manuell editierbar)
│   ├── lib-*.sh            # Module
│   └── lang/
│       ├── lib-cd.de
│       ├── lib-dvd.de
│       └── lib-common.de
│
/usr/local/bin/disk2iso → /opt/disk2iso/disk2iso.sh (Symlink)
```

### Seite 8: Abschluss

```
┌───────────────────────────────────────────────────────────┐
│  ✅ Installation erfolgreich abgeschlossen!               │
│                                                           │
│  Installiert:                                             │
│  • Module: Audio-CD, Video-DVD                           │
│  • Laufwerk: /dev/sr0                                     │
│                                                           │
│  Starten:                                                 │
│  sudo disk2iso -o /pfad/zum/ausgabeverzeichnis            │
│                                                           │
│  Hilfe:                                                   │
│  disk2iso --help                                          │
│                                                           │
│  Dokumentation:                                           │
│  /opt/disk2iso/disk2iso-lib/docu/Handbuch.md            │
│                                                           │
│  [OK]                                                     │
└───────────────────────────────────────────────────────────┘
```

**Nach der Installation**:
1. Testen: `sudo disk2iso --test`
2. Disc einlegen und starten: `sudo disk2iso`
3. Konfiguration anpassen: `/opt/disk2iso/disk2iso-lib/config.sh`

---

## Manuelle Installation

Falls der Wizard nicht funktioniert (z.B. kein whiptail/dialog), manuelle Installation:

### 1. Abhängigkeiten installieren

```bash
# Kern-Pakete (immer erforderlich)
sudo apt update
sudo apt install -y coreutils util-linux genisoimage whiptail

# Optional: Audio-CD Modul
sudo apt install -y cdparanoia lame eyed3 curl jq

# Optional: Video-DVD Modul
sudo apt install -y dvdbackup libdvd-pkg
sudo dpkg-reconfigure libdvd-pkg  # libdvdcss2 installieren

# Optional: Blu-ray Modul
sudo apt install -y ddrescue
```

### 2. Dateien kopieren

```bash
# Erstelle Ziel-Ordner
sudo mkdir -p /opt/disk2iso/disk2iso-lib/lang

# Hauptskript
sudo cp disk2iso.sh /opt/disk2iso/
sudo chmod +x /opt/disk2iso/disk2iso.sh

# Kern-Module (immer)
sudo cp disk2iso-lib/lib-common.sh /opt/disk2iso/disk2iso-lib/
sudo cp disk2iso-lib/lib-logging.sh /opt/disk2iso/disk2iso-lib/
sudo cp disk2iso-lib/lib-files.sh /opt/disk2iso/disk2iso-lib/
sudo cp disk2iso-lib/lib-folders.sh /opt/disk2iso/disk2iso-lib/
sudo cp disk2iso-lib/lib-diskinfos.sh /opt/disk2iso/disk2iso-lib/
sudo cp disk2iso-lib/lib-drivestat.sh /opt/disk2iso/disk2iso-lib/
sudo cp disk2iso-lib/lib-tools.sh /opt/disk2iso/disk2iso-lib/

# Optionale Module (nach Bedarf)
sudo cp disk2iso-lib/lib-cd.sh /opt/disk2iso/disk2iso-lib/
sudo cp disk2iso-lib/lib-dvd.sh /opt/disk2iso/disk2iso-lib/
sudo cp disk2iso-lib/lib-bluray.sh /opt/disk2iso/disk2iso-lib/

# Sprachdateien
sudo cp disk2iso-lib/lang/*.de /opt/disk2iso/disk2iso-lib/lang/

# Konfiguration
sudo cp disk2iso-lib/config.sh /opt/disk2iso/disk2iso-lib/
```

### 3. Sprache anpassen (optional)

```bash
sudo nano /opt/disk2iso/disk2iso-lib/config.sh
```

**Einzige Benutzer-Einstellung** (Zeile 18):

```bash
# Sprache für Meldungen
readonly LANGUAGE="de"  # oder "en"
```

**Hinweis**: Alle anderen Einstellungen (Module, Qualität, Methoden) sind fest im Code integriert und nicht konfigurierbar.

### 4. Symlink erstellen

```bash
sudo ln -s /opt/disk2iso/disk2iso.sh /usr/local/bin/disk2iso
```

### 5. Verzeichnisse erstellen

```bash
# Ausgabe-Verzeichnis
sudo mkdir -p /srv/disk2iso/{audio,dvd,bd,data,log,temp}
sudo chmod 755 /srv/disk2iso

# Optional: Eigentümer ändern
sudo chown -R $USER:$USER /srv/disk2iso
```

### 6. Testen

```bash
# Script starten (erfordert -o Parameter)
sudo disk2iso -o /srv/disk2iso

# Im Hintergrund
sudo disk2iso -o /srv/disk2iso &

# Mit Debug
DEBUG=1 sudo disk2iso -o /srv/disk2iso
```

---

## Modul-Auswahl

### lib-cd.sh (Audio-CD Support)

**Installieren wenn**:
- Audio-CDs zu MP3 konvertieren
- MusicBrainz-Metadaten gewünscht
- Album-Cover automatisch herunterladen

**Abhängigkeiten**:
- `cdparanoia` - Lossless Audio-Extraktion
- `lame` - MP3-Encoding
- `eyed3` - ID3-Tag-Editor
- `curl`, `jq` - MusicBrainz API

**Speicherplatz**: ~700 MB pro Audio-CD (VBR V2)

### lib-dvd.sh (Video-DVD Support)

**Installieren wenn**:
- Video-DVDs entschlüsseln und archivieren
- Kommerzielle DVDs (CSS-Schutz)

**Abhängigkeiten**:
- `dvdbackup` - DVD-Extraktion
- `libdvdcss2` - CSS-Entschlüsselung (via libdvd-pkg)
- `genisoimage` - ISO-Erstellung

**Speicherplatz**: ~4-8 GB pro DVD

### lib-bluray.sh (Blu-ray Support)

**Installieren wenn**:
- Blu-rays archivieren (auch beschädigt)
- Große Medien (25/50/100 GB)

**Abhängigkeiten**:
- `ddrescue` - Robustes Kopieren (primär)
- `dd` - Fallback-Methode

**Speicherplatz**: 25-100 GB pro Blu-ray

**Hinweis**: Entschlüsselung nicht integriert (AACS v4 zu komplex).

---

---

## Fehlerbehebung

### Installer startet nicht

**Problem**: `./install.sh: command not found`

**Lösung**:
```bash
chmod +x install.sh
sudo ./install.sh
```

### Kein whiptail/dialog

**Problem**: `whiptail: not found`

**Lösung**:
```bash
sudo apt install whiptail dialog
# ODER: Manuelle Installation (siehe oben)
```

### Laufwerk nicht erkannt

**Problem**: `/dev/sr0` existiert nicht

**Diagnose**:
```bash
# Laufwerke auflisten
ls -la /dev/sr*

# Kernel-Modul prüfen
lsmod | grep sr_mod

# Kernel-Log prüfen
dmesg | grep -i "cd\|dvd\|blu-ray"
```

**Lösung**:
```bash
# Kernel-Modul laden
sudo modprobe sr_mod

# Dauerhaft aktivieren
echo "sr_mod" | sudo tee -a /etc/modules
```

### Abhängigkeiten-Installation fehlgeschlagen

**Problem**: `E: Unable to locate package lame`

**Lösung**:
```bash
# Repositories aktualisieren
sudo apt update

# Falls contrib/non-free fehlt:
sudo nano /etc/apt/sources.list
# Zeile ergänzen: deb http://deb.debian.org/debian bookworm main contrib non-free
sudo apt update
```

### libdvdcss2 Installation

**Problem**: `libdvdcss2` nicht gefunden

**Lösung**:
```bash
sudo apt install libdvd-pkg
sudo dpkg-reconfigure libdvd-pkg
# Wizard folgen, Lizenz akzeptieren
```

### Keine Schreibrechte

**Problem**: `Permission denied` beim Schreiben nach `/srv/disk2iso`

**Lösung**:
```bash
# Besitzer ändern
sudo chown -R $USER:$USER /srv/disk2iso

# ODER: Schreibrechte für Gruppe
sudo chmod 775 /srv/disk2iso
sudo usermod -a -G disk $USER
```

---

## Weiterführende Links

- **[← Zurück zum Handbuch](Handbuch.md)**
- **[Nächster Schritt: Verwendung →](Verwendung.md)**
- **[Alternative: Installation als Service](Installation-Service.md)**

---

**Version**: 1.1.0 | **Letzte Aktualisierung**: 04.01.2026
