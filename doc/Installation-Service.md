# Installation als systemd-Service

Diese Anleitung beschreibt die Installation von disk2iso als permanenter systemd-Service. Für manuelle Ausführung siehe [Installation als Script](Installation-Script.md).

## Inhaltsverzeichnis

1. [Übersicht](#übersicht)
2. [Voraussetzungen](#voraussetzungen)
3. [Installation mit Wizard](#installation-mit-wizard)
4. [Manuelle Service-Installation](#manuelle-service-installation)
5. [Service-Verwaltung](#service-verwaltung)
6. [Monitoring & Logging](#monitoring--logging)
7. [Fehlerbehebung](#fehlerbehebung)

---

## Übersicht

### Was ist der Service-Modus?

Im Service-Modus läuft disk2iso permanent im Hintergrund und überwacht das optische Laufwerk. Bei eingelegter Disc startet automatisch die Archivierung.

### Vorteile

- ✅ **Kein manueller Start**: Disc einlegen genügt
- ✅ **Autostart beim Booten**: Service startet automatisch
- ✅ **Headless-Betrieb**: Ideal für Server ohne Desktop
- ✅ **Logging**: Alle Aktionen in systemd-Journal
- ✅ **Zuverlässigkeit**: Automatischer Neustart bei Fehlern

### Nachteile

- ⚠️ **Ressourcen**: Permanenter Prozess (minimal: ~10 MB RAM)
- ⚠️ **Komplexität**: Mehr Konfiguration als Script-Modus
- ⚠️ **Debugging**: Fehler nur in Logs sichtbar

---

## Voraussetzungen

### System-Anforderungen

- **systemd**: Version 232+ (Debian 9+, Ubuntu 18.04+)
- **Root-Rechte**: Für Service-Installation
- **Laufwerk**: Muss beim Boot verfügbar sein (nicht USB!)

### Prüfen

```bash
# systemd-Version
systemctl --version

# Laufwerk dauerhaft verfügbar?
ls -la /dev/sr0
# ✓ crw-rw----+ 1 root cdrom → OK
# ✗ ls: cannot access → Problem!
```

---

## Installation mit Wizard

### Start

```bash
git clone https://github.com/username/disk2iso.git
cd disk2iso
sudo ./install.sh
```

### Wizard-Seiten (Service-spezifisch)

Die ersten 7 Seiten sind identisch zur [Script-Installation](Installation-Script.md). Ab Seite 2 wählen Sie:

#### Seite 2: Installations-Typ (Service-Option)

```
┌───────────────────────────────────────────────────────────┐
│  Wählen Sie die gewünschte Installations-Art:            │
│                                                           │
│  ( ) Nur Script                                           │
│  (*) Script + systemd-Service                             │
│      - Automatischer Start beim Booten                   │
│      - Überwacht Laufwerk permanent                      │
│      - Ideal für Server oder Dauerbetrieb                │
│                                                           │
│  [OK] [Abbrechen]                                         │
└───────────────────────────────────────────────────────────┘
```

**Auswahl**: `Script + systemd-Service`

#### Seite 8: Service-Installation (zusätzlich)

```
┌───────────────────────────────────────────────────────────┐
│  Installiere systemd-Service...                           │
│                                                           │
│  [████████████████████████████████] 100%                 │
│                                                           │
│  ✓ disk2iso.service → /etc/systemd/system/              │
│  ✓ systemctl daemon-reload                               │
│  ✓ systemctl enable disk2iso.service                     │
│  ✓ systemctl start disk2iso.service                      │
│                                                           │
│  Service-Status: ● aktiv (running)                       │
│                                                           │
│  Logs anzeigen:                                           │
│  sudo journalctl -u disk2iso.service -f                  │
│                                                           │
│  [OK]                                                     │
└───────────────────────────────────────────────────────────┘
```

**Aktionen**:
1. Service-Datei kopiert nach `/etc/systemd/system/`
2. Service aktiviert (Autostart beim Booten)
3. Service sofort gestartet
4. Status-Prüfung zeigt "aktiv (running)"

#### Seite 9: Abschluss (Service-Modus)

```
┌───────────────────────────────────────────────────────────┐
│  ✅ Installation erfolgreich abgeschlossen!               │
│                                                           │
│  Installiert:                                             │
│  • Ausgabe-Verzeichnis: /media/iso                        │
│  • Module: Audio-CD, Video-DVD                           │
│  • Laufwerk: /dev/sr0                                     │
│  • Service: disk2iso.service (aktiv)                     │
│                                                           │
│  Service-Befehle:                                         │
│  sudo systemctl status disk2iso                          │
│  sudo systemctl stop disk2iso                            │
│  sudo systemctl restart disk2iso                         │
│                                                           │
│  Logs anzeigen:                                           │
│  sudo journalctl -u disk2iso -f                          │
│                                                           │
│  ➜ Disc einlegen → Automatische Archivierung            │
│                                                           │
│  [OK]                                                     │
└───────────────────────────────────────────────────────────┘
```

---

## Manuelle Service-Installation

Falls der Wizard nicht funktioniert, manuelle Installation:

### 1. Script installieren

Zuerst [Script-Installation](Installation-Script.md#manuelle-installation) durchführen, dann:

### 2. Service-Datei erstellen

```bash
sudo nano /etc/systemd/system/disk2iso.service
```

**Inhalt**:

```ini
[Unit]
Description=disk2iso - Optical Media Archiver
Documentation=https://github.com/username/disk2iso
After=network.target

[Service]
Type=simple
User=root
Group=root

# Hauptskript
ExecStart=/opt/disk2iso/disk2iso.sh

# Restart-Verhalten
Restart=on-failure
RestartSec=10s

# Sicherheit
NoNewPrivileges=true
PrivateTmp=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=disk2iso

[Install]
WantedBy=multi-user.target
```

**Wichtige Optionen**:

| Option | Bedeutung |
|--------|-----------|
| `User=root` | Erforderlich für Laufwerks-Zugriff |
| `Restart=on-failure` | Automatischer Neustart bei Fehler |
| `RestartSec=10s` | Wartezeit vor Neustart |
| `NoNewPrivileges=true` | Sicherheit: Keine Rechte-Eskalation |
| `PrivateTmp=true` | Isoliertes /tmp-Verzeichnis |

### 3. Service aktivieren

```bash
# systemd neu laden
sudo systemctl daemon-reload

# Service aktivieren (Autostart)
sudo systemctl enable disk2iso.service

# Service starten
sudo systemctl start disk2iso.service
```

### 4. Status prüfen

```bash
sudo systemctl status disk2iso.service
```

**Erwartete Ausgabe**:

```
● disk2iso.service - disk2iso - Optical Media Archiver
     Loaded: loaded (/etc/systemd/system/disk2iso.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-01-01 10:00:00 CET; 5min ago
       Docs: https://github.com/username/disk2iso
   Main PID: 12345 (disk2iso.sh)
      Tasks: 1 (limit: 4915)
     Memory: 8.2M
        CPU: 100ms
     CGroup: /system.slice/disk2iso.service
             └─12345 /bin/bash /opt/disk2iso/disk2iso.sh

Jan 01 10:00:00 hostname systemd[1]: Started disk2iso - Optical Media Archiver.
Jan 01 10:00:00 hostname disk2iso[12345]: [INFO] disk2iso v2.0 gestartet
Jan 01 10:00:00 hostname disk2iso[12345]: [INFO] Überwache Laufwerk: /dev/sr0
```

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

### Service-Status verstehen

```bash
sudo systemctl status disk2iso
```

**Status-Ausgaben**:

| Status | Bedeutung | Aktion |
|--------|-----------|--------|
| `active (running)` | Service läuft normal | Keine |
| `inactive (dead)` | Service gestoppt | `systemctl start` |
| `failed` | Service abgestürzt | Logs prüfen |
| `activating (start)` | Service startet gerade | Warten |

### Konfiguration neu laden

```bash
# config.sh geändert → Service neu starten
sudo systemctl restart disk2iso

# disk2iso.service geändert → systemd neu laden
sudo systemctl daemon-reload
sudo systemctl restart disk2iso
```

---

## Monitoring & Logging

### Logs in Echtzeit

```bash
# Alle Logs (folgen)
sudo journalctl -u disk2iso.service -f

# Nur Fehler
sudo journalctl -u disk2iso.service -p err -f

# Letzte 50 Zeilen
sudo journalctl -u disk2iso.service -n 50

# Seit heute
sudo journalctl -u disk2iso.service --since today

# Zeitraum
sudo journalctl -u disk2iso.service --since "2026-01-01 08:00" --until "2026-01-01 18:00"
```

### Log-Beispiele

**Normale Archivierung**:

```
Jan 01 10:15:00 hostname disk2iso[12345]: [INFO] Disc eingelegt: /dev/sr0
Jan 01 10:15:01 hostname disk2iso[12345]: [INFO] Disc-Typ: audio-cd
Jan 01 10:15:01 hostname disk2iso[12345]: [INFO] Label: Greatest_Hits_2023
Jan 01 10:15:01 hostname disk2iso[12345]: [INFO] MusicBrainz Disc ID: wXyz1234AbCd5678
Jan 01 10:15:02 hostname disk2iso[12345]: [INFO] Album gefunden: Artist - Greatest Hits (2023)
Jan 01 10:15:02 hostname disk2iso[12345]: [INFO] Starte Audio-Extraktion (14 Tracks)
Jan 01 10:18:45 hostname disk2iso[12345]: [INFO] Encoding abgeschlossen: 14/14 Tracks
Jan 01 10:18:46 hostname disk2iso[12345]: [INFO] Cover heruntergeladen: 500x500px
Jan 01 10:18:46 hostname disk2iso[12345]: [INFO] NFO-Datei erstellt
Jan 01 10:18:46 hostname disk2iso[12345]: [SUCCESS] Ausgabe: /srv/disk2iso/audio/Artist/Greatest_Hits
Jan 01 10:18:46 hostname disk2iso[12345]: [INFO] Disc ausgeworfen
```

**Fehler-Beispiel**:

```
Jan 01 10:20:00 hostname disk2iso[12345]: [INFO] Disc eingelegt: /dev/sr0
Jan 01 10:20:01 hostname disk2iso[12345]: [ERROR] Lesefehler bei Sektor 12345
Jan 01 10:20:01 hostname disk2iso[12345]: [INFO] Starte ddrescue (Retry 1/3)
Jan 01 10:22:00 hostname disk2iso[12345]: [WARNING] 5 Sektoren nicht lesbar
Jan 01 10:22:00 hostname disk2iso[12345]: [SUCCESS] ISO erstellt (mit Fehlern)
Jan 01 10:22:00 hostname disk2iso[12345]: [INFO] MD5: a1b2c3d4e5f6...
```

### Performance-Monitoring

```bash
# CPU/RAM-Nutzung
systemctl status disk2iso | grep -E "Memory|CPU"

# Detaillierte Prozess-Infos
systemd-cgtop

# Disc-I/O
sudo iotop -p $(pgrep -f disk2iso.sh)
```

### Logs exportieren

```bash
# Alle Logs als Text
sudo journalctl -u disk2iso.service > disk2iso.log

# Komprimiert
sudo journalctl -u disk2iso.service | gzip > disk2iso.log.gz

# JSON-Format (für Analyse)
sudo journalctl -u disk2iso.service -o json-pretty > disk2iso.json
```

---

## Fehlerbehebung

### Service startet nicht

**Problem**: `Failed to start disk2iso.service`

**Diagnose**:
```bash
# Detaillierte Fehler
sudo journalctl -xe | grep disk2iso

# Service-Datei validieren
sudo systemd-analyze verify disk2iso.service
```

**Häufige Ursachen**:

1. **Hauptskript nicht ausführbar**:
   ```bash
   sudo chmod +x /opt/disk2iso/disk2iso.sh
   ```

2. **Pfad falsch in disk2iso.service**:
   ```bash
   sudo nano /etc/systemd/system/disk2iso.service
   # ExecStart=/opt/disk2iso/disk2iso.sh (prüfen!)
   ```

3. **Abhängigkeiten fehlen**:
   ```bash
   /opt/disk2iso/disk2iso.sh --test
   ```

### Service stürzt ab

**Problem**: Status zeigt `failed`

**Diagnose**:
```bash
# Crash-Log
sudo journalctl -u disk2iso.service -n 100 | grep -i error

# Core-Dump prüfen
coredumpctl list
coredumpctl info disk2iso.sh
```

**Lösung**:
```bash
# Debug-Modus aktivieren
sudo nano /opt/disk2iso/disk2iso-lib/config.sh
# DEBUG=true
# DEBUG_SHELL=true (bei Fehler Shell öffnen)

# Service neu starten
sudo systemctl restart disk2iso
```

### Service läuft, aber erkennt keine Discs

**Problem**: Disc eingelegt, keine Reaktion

**Diagnose**:
```bash
# Laufwerk testen
sudo eject -t /dev/sr0     # Schublade schließen
lsblk | grep sr0           # Disc erkannt?

# udev-Events prüfen
sudo udevadm monitor --property --udev | grep sr0
```

**Lösung**:
```bash
# CDROM_DEVICE korrekt?
sudo nano /opt/disk2iso/disk2iso-lib/config.sh
# CDROM_DEVICE="/dev/sr0" (prüfen!)

# Service neu starten
sudo systemctl restart disk2iso
```

### Hoher Ressourcen-Verbrauch

**Problem**: CPU/RAM-Last zu hoch

**Diagnose**:
```bash
# Prozess-Baum
pstree -p $(pgrep -f disk2iso.sh)

# Ressourcen
top -p $(pgrep -f disk2iso.sh)
```

**Lösungen**:

1. **Paralleles Encoding reduzieren** (Audio-CD):
   ```bash
   # In lib-cd.sh (Zeile ~220)
   # Von: parallel --jobs 4
   # Zu:  parallel --jobs 2
   ```

2. **Polling-Intervall erhöhen**:
   ```bash
   # In disk2iso.sh (Zeile ~50)
   # Von: sleep 2
   # Zu:  sleep 5
   ```

3. **CPU-Limit setzen**:
   ```bash
   sudo systemctl edit disk2iso.service
   # [Service]
   # CPUQuota=50%
   ```

### Logs zu groß

**Problem**: journalctl zu viele Einträge

**Lösung**:
```bash
# Log-Rotation konfigurieren
sudo nano /etc/systemd/journald.conf

# Einstellungen:
SystemMaxUse=100M          # Max. 100 MB für alle Services
SystemKeepFree=1G          # 1 GB frei lassen
MaxRetentionSec=7day       # 7 Tage aufbewahren

# journald neu starten
sudo systemctl restart systemd-journald
```

### Berechtigungs-Fehler

**Problem**: `Permission denied` für `/dev/sr0`

**Lösung**:
```bash
# Service läuft als root?
sudo systemctl status disk2iso | grep "User"

# Laufwerk-Rechte prüfen
ls -la /dev/sr0
# Sollte sein: crw-rw----+ 1 root cdrom

# Falls falsch:
sudo chmod 660 /dev/sr0
sudo chgrp cdrom /dev/sr0
```

---

## Erweiterte Konfiguration

### Service-Override (empfohlen)

Änderungen nicht direkt in `/etc/systemd/system/disk2iso.service`, sondern via Override:

```bash
sudo systemctl edit disk2iso.service
```

**Beispiele**:

```ini
[Service]
# CPU-Limit
CPUQuota=50%

# Höhere Priorität (nice -10)
Nice=-10

# Umgebungsvariablen
Environment="DEBUG=true"
Environment="LANG=de"

# Email bei Fehler (erfordert mail-Setup)
OnFailure=email-notification@%n.service
```

**Anwenden**:
```bash
sudo systemctl daemon-reload
sudo systemctl restart disk2iso
```

### Mehrere Laufwerke

Für mehrere Laufwerke (`/dev/sr0`, `/dev/sr1`) separate Service-Instanzen:

```bash
# Template-Service erstellen
sudo cp /etc/systemd/system/disk2iso.service /etc/systemd/system/disk2iso@.service

# Anpassen:
sudo nano /etc/systemd/system/disk2iso@.service
# ExecStart=/opt/disk2iso/disk2iso.sh --device /dev/%i

# Instanzen starten
sudo systemctl enable disk2iso@sr0.service
sudo systemctl enable disk2iso@sr1.service
sudo systemctl start disk2iso@sr0.service
sudo systemctl start disk2iso@sr1.service
```

---

## Weiterführende Links

- **[← Zurück zum Handbuch](Handbuch.md)**
- **[Alternative: Installation als Script](Installation-Script.md)**
- **[Nächster Schritt: Verwendung →](Verwendung.md)**

---

**Version**: 1.1.0 | **Letzte Aktualisierung**: 04.01.2026
