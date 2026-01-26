# Kapitel 3: Betrieb & Verwendung

Praktische Anleitung zur Nutzung von disk2iso im täglichen Betrieb.

## Inhaltsverzeichnis

1. [Service-Modus](#service-modus)
2. [Web-Interface](#web-interface)
3. [Ausgabe-Struktur](#ausgabe-struktur)
4. [Disc-Typen](#disc-typen)
5. [Logs & Monitoring](#logs--monitoring)
6. [REST API](#rest-api)
7. [Tipps & Best Practices](#tipps--best-practices)

---

## Service-Modus

disk2iso läuft als systemd Service und arbeitet vollautomatisch im Hintergrund.

### Automatischer Workflow

1. **Disc einlegen** → System erkennt Medium automatisch
2. **Archivierung** → Läuft vollautomatisch (keine Interaktion nötig)
3. **Disc auswerfen** → Automatisch nach Abschluss
4. **Bereit** → Für nächste Disc

### State Machine

disk2iso verwendet eine Finite State Machine mit 11 Zuständen:

```
[initializing] → [waiting_for_drive] → [drive_detected]
                                             ↓
                                  [waiting_for_media]
                                             ↓
                          (Medium eingelegt) [media_detected]
                                             ↓
                                       [analyzing]
                                             ↓
                                        [copying]
                                        ↙        ↘
                                (Erfolg)         (Fehler)
                                   ↓                ↓
                             [completed]        [error]
                                   ↓                ↓
                        [waiting_for_removal]  [waiting_for_removal]
                                   ↓
                            (Medium entfernt)
                                   ↓
                                [idle] → [waiting_for_media]
                                           (Loop)
```

### Polling-Intervalle

- **Laufwerk-Suche:** 20 Sekunden
- **Medium-Erkennung:** 2 Sekunden
- **Entnahme-Check:** 5 Sekunden

### Service-Steuerung

```bash
# Service-Status anzeigen
sudo systemctl status disk2iso

# Service stoppen (z.B. für Wartung)
sudo systemctl stop disk2iso

# Service starten
sudo systemctl start disk2iso

# Service neu starten (nach Config-Änderung)
sudo systemctl restart disk2iso

# Logs in Echtzeit verfolgen
sudo journalctl -u disk2iso -f

# Letzte 50 Log-Zeilen
sudo journalctl -u disk2iso -n 50

# Nur Fehler anzeigen
sudo journalctl -u disk2iso -p err
```

### Typischer Log-Ablauf

**Erfolgreiche Archivierung:**

```
Jan 26 10:15:00 hostname disk2iso[12345]: [INFO] State: waiting_for_media → media_detected
Jan 26 10:15:00 hostname disk2iso[12345]: [INFO] Disc eingelegt: /dev/sr0
Jan 26 10:15:01 hostname disk2iso[12345]: [INFO] State: media_detected → analyzing
Jan 26 10:15:01 hostname disk2iso[12345]: [INFO] Disc-Typ: dvd-video
Jan 26 10:15:01 hostname disk2iso[12345]: [INFO] Label: THE_MATRIX
Jan 26 10:15:01 hostname disk2iso[12345]: [INFO] State: analyzing → copying
Jan 26 10:15:01 hostname disk2iso[12345]: [INFO] Starte Video-DVD Backup...
Jan 26 10:15:02 hostname disk2iso[12345]: [INFO] Größe: 7.8 GB
Jan 26 10:15:02 hostname disk2iso[12345]: [INFO] Verschlüsselt: ja (CSS)
Jan 26 10:48:45 hostname disk2iso[12345]: [INFO] Kopie abgeschlossen: 7.8 GB
Jan 26 10:48:46 hostname disk2iso[12345]: [INFO] MD5: a1b2c3d4e5f6...
Jan 26 10:48:46 hostname disk2iso[12345]: [SUCCESS] Ausgabe: /media/iso/dvd/THE_MATRIX.iso
Jan 26 10:48:46 hostname disk2iso[12345]: [INFO] State: copying → completed
Jan 26 10:48:46 hostname disk2iso[12345]: [INFO] Disc ausgeworfen
Jan 26 10:48:46 hostname disk2iso[12345]: [INFO] State: completed → idle
```

---

## Web-Interface

Das Web-Interface bietet komfortable Überwachung und Verwaltung über den Browser.

### Zugriff

```bash
# Web-Service starten (falls nicht aktiv)
sudo systemctl start disk2iso-web

# Autostart aktivieren
sudo systemctl enable disk2iso-web

# Im Browser öffnen
http://<server-ip>:8080
```

**Standard-Port:** 8080  
**Keine Authentifizierung** (lokal oder via Firewall absichern!)

### Seiten-Übersicht

#### 🏠 Home (Übersicht)

**Live-Status:**
- **State Machine:** Aktueller Zustand (z.B. "copying", "waiting_for_media")
- **Fortschritt:** Prozent, MB kopiert, Geschwindigkeit, ETA
- **Speicherplatz:** Verfügbar/Gesamt im Ausgabeverzeichnis
- **Service-Status:** disk2iso & disk2iso-web laufend

**Letzte ISOs:**
- 5 zuletzt erstellte Archive
- Dateigröße, Erstellungsdatum

**Auto-Refresh:** Alle 5 Sekunden

#### 📦 Archive

**Kategorisierung:**
- Audio (nur mit Audio-CD Modul)
- DVD (nur mit Video-DVD Modul)
- Blu-ray (nur mit Blu-ray Modul)
- Data (immer verfügbar)

**Funktionen:**
- **Liste:** Alle ISOs mit Größe und Datum
- **MD5-Download:** Prüfsummen-Dateien
- **Filter:** Schnellsuche nach Namen
- **Metadaten:** Cover/Poster (falls vorhanden)

**Beispiel-Anzeige:**

```
📀 Data
  ├─ Backup_2024-01-15.iso (612 MB) - 15.01.2024
  ├─ Software_CD.iso (450 MB) - 10.01.2024
  └─ Photos_Archive.iso (3.2 GB) - 05.01.2024
```

#### 📋 Logs

**Live-Logs:**
- Letzte 100 Zeilen
- Auto-Scroll
- Farbcodierung (INFO, WARNING, ERROR)

**Filter:**
- Nach Disc-Label
- Nach Log-Datei
- Nach Zeitraum

**Download:**
- Komplette Log-Datei als .txt
- Archivierte Logs (.log.gz)

#### ⚙️ Config

**Anzeige:**
- Ausgabeverzeichnis
- Laufwerk
- Aktivierte Module
- Sprache
- MQTT-Status

**Nur-Lesen:**
Änderungen nur via `/opt/disk2iso/disk2iso-lib/config.sh` möglich.

#### 💻 System

**System-Informationen:**
- OS: Debian 12 (Bookworm)
- Kernel: Linux 6.x
- Uptime: 5 Tage
- RAM: 4 GB / 8 GB

**Hardware:**
- CPU: Intel Core i5
- Laufwerk: /dev/sr0 (HL-DT-ST BD-RE BH16NS55)

**Software:**
- disk2iso: v1.2.0
- Module: Audio-CD, Video-DVD, MQTT

**Dependencies:**
- ✅ cdparanoia, lame, eyed3 (Audio-CD)
- ✅ dvdbackup, libdvdcss2 (Video-DVD)
- ✅ genisoimage, dd, ddrescue

#### ❓ Help

**Integrierte Hilfe:**
- Markdown-Rendering
- Verlinkung zur vollständigen Dokumentation
- FAQ
- Schnellstart-Guide

### Sprachunterstützung

**Automatische Erkennung:**
Web-Interface nutzt `LANGUAGE`-Einstellung aus `config.sh`.

**Verfügbare Sprachen:**
- Deutsch (de)
- English (en)
- Español (es)
- Français (fr)

**Ändern:**
```bash
sudo nano /opt/disk2iso/disk2iso-lib/config.sh
# readonly LANGUAGE="en"
sudo systemctl restart disk2iso
sudo systemctl restart disk2iso-web
```

---

## Ausgabe-Struktur

### Ordner-Hierarchie

```
OUTPUT_DIR/
├── audio/              # Audio-CDs (nur mit Modul)
├── dvd/                # Video-DVDs (nur mit Modul)
├── bd/                 # Blu-rays (nur mit Modul)
├── data/               # Daten-Discs (immer)
├── .log/               # Log-Dateien (versteckt)
└── .temp/              # Temporär (auto-cleanup, versteckt)
```

### Daten-Disc Struktur

**Standard-Fall** (ohne optionale Module):

```
data/
├── Disc_Label.iso
├── Disc_Label.md5
├── Backup_2024.iso
└── Backup_2024.md5
```

**Dateinamen:**
- Basierend auf Disc-Label (via isoinfo/blkid)
- Sonderzeichen entfernt: `Album: Best Of` → `Album_Best_Of`
- Bei Duplikaten: `Disc_Label_1.iso`, `Disc_Label_2.iso`

### MD5-Checksummen

**Automatisch erstellt:**
Jede ISO erhält eine `.md5`-Datei.

**Format:**
```
a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6  Disc_Label.iso
```

**Überprüfen:**
```bash
cd /media/iso/data
md5sum -c Disc_Label.md5
# Ausgabe: Disc_Label.iso: OK
```

### Log-Dateien

```
.log/
├── Disc_Label.log           # Pro Disc
├── Backup_2024.log
└── archived/                # Alte Logs (optional)
    └── Disc_Label.log.gz
```

**Log-Inhalt:**
```
[2026-01-26 10:15:00] [INFO] Disc eingelegt: /dev/sr0
[2026-01-26 10:15:01] [INFO] Disc-Typ: cd-rom
[2026-01-26 10:15:01] [INFO] Label: Backup_2024
[2026-01-26 10:15:01] [INFO] Dateisystem: ISO9660
[2026-01-26 10:15:01] [INFO] Größe: 612 MB
[2026-01-26 10:15:01] [INFO] Methode: dd
[2026-01-26 10:17:30] [INFO] Fortschritt: 612 MB / 612 MB (100%)
[2026-01-26 10:17:30] [INFO] MD5: 9z8y7x6w5v4u...
[2026-01-26 10:17:30] [SUCCESS] ISO: /media/iso/data/Backup_2024.iso
```

### Temp-Verzeichnis

```
.temp/
├── mountpoints/
│   └── disc_abc123_12345/   # Mount-Point für Label-Erkennung
└── disc_abc123_12345/       # Arbeitsverzeichnis
```

**Cleanup:**
- Automatisch nach Erfolg
- Automatisch nach Fehler
- Manuell via Cronjob (optional)

---

## Disc-Typen

disk2iso erkennt 6 verschiedene Disc-Typen automatisch.

### Erkennungs-Logik

```bash
# 1. Audio-CD prüfen
if is_audio_cd "$device"; then
    DISC_TYPE="audio-cd"
    
# 2. Video-DVD prüfen
elif is_video_dvd "$device"; then
    DISC_TYPE="dvd-video"
    
# 3. Blu-ray prüfen
elif is_bluray "$device"; then
    DISC_TYPE="bd-video"
    
# 4. Daten-Disc (Fallback)
else
    # Größe ermitteln
    size=$(blockdev --getsize64 "$device")
    
    if [[ $size -le 737280000 ]]; then
        DISC_TYPE="cd-rom"       # < 700 MB
    elif [[ $size -le 5000000000 ]]; then
        DISC_TYPE="dvd-rom"      # 700 MB - 4.7 GB
    else
        DISC_TYPE="bd-rom"       # > 4.7 GB
    fi
fi
```

### Daten-CD (cd-rom)

**Erkennung:** Dateisystem (ISO9660, Joliet), keine Video/Audio-Struktur

**Größe:** Bis 700 MB

**Prozess:**
1. Label-Erkennung via `isoinfo` oder `blkid`
2. Kopie mit `dd` (schnell)
3. Falls Fehler: `ddrescue` (robust)
4. MD5-Checksumme

**Ausgabe:** `/media/iso/data/Label.iso`

**Beispiel-Log:**
```
[INFO] Disc-Typ: cd-rom
[INFO] Label: Software_Install_CD
[INFO] Dateisystem: ISO9660 + Joliet
[INFO] Größe: 450 MB
[INFO] Methode: dd
[INFO] Fortschritt: 450 MB / 450 MB (100%, 22 MB/s)
[SUCCESS] ISO: /media/iso/data/Software_Install_CD.iso (450 MB)
```

### Daten-DVD (dvd-rom)

**Erkennung:** UDF-Dateisystem, keine VIDEO_TS-Struktur

**Größe:** 700 MB - 4.7 GB (Single Layer) oder 8.5 GB (Dual Layer)

**Prozess:** Wie CD-ROM, aber mit längerer Kopierdauer

**Ausgabe:** `/media/iso/data/Label.iso`

**Beispiel-Log:**
```
[INFO] Disc-Typ: dvd-rom
[INFO] Label: Backup_Archive_2024
[INFO] Dateisystem: UDF 1.02
[INFO] Größe: 3.2 GB
[INFO] Methode: dd
[INFO] Fortschritt: 3.2 GB / 3.2 GB (100%, 18 MB/s, 3m 05s)
[SUCCESS] ISO: /media/iso/data/Backup_Archive_2024.iso (3.2 GB)
```

### Daten-Blu-ray (bd-rom)

**Erkennung:** UDF 2.50+, keine BDMV-Struktur

**Größe:** 25 GB (Single Layer), 50 GB (Dual Layer), 100 GB (Triple/Quad)

**Prozess:**
1. `ddrescue` (primär, robust)
2. Falls nicht verfügbar: `dd` (Fallback)

**Ausgabe:** `/media/iso/data/Label.iso`

**Beispiel-Log:**
```
[INFO] Disc-Typ: bd-rom
[INFO] Label: Data_Archive_XL
[INFO] Dateisystem: UDF 2.60
[INFO] Größe: 23.8 GB
[INFO] Methode: ddrescue
[INFO] Fortschritt: 23.8 GB / 23.8 GB (100%, 45 MB/s, 9m 12s)
[SUCCESS] ISO: /media/iso/data/Data_Archive_XL.iso (23.8 GB)
```

### Graceful Degradation

**Wenn optionale Module fehlen:**

```
Audio-CD + lib-cd.sh FEHLT → Kopie als data/Audio_CD.iso (dd)
DVD-Video + lib-dvd.sh FEHLT → Kopie als data/DVD_Video.iso (dd, verschlüsselt!)
Blu-ray + lib-bluray.sh FEHLT → Kopie als data/Bluray.iso (dd/ddrescue)
```

**Vorteil:** Immer ein ISO-Image, auch wenn spezialisierte Module fehlen.

**Nachteil:** 
- Audio-CD: Keine MP3s, kein Cover
- Video-DVD: Verschlüsselt (CSS), nicht direkt abspielbar
- Blu-ray: Verschlüsselt (AACS), nicht direkt abspielbar

---

## Logs & Monitoring

### systemd Journal

**Echtzeit-Logs:**
```bash
sudo journalctl -u disk2iso -f
```

**Letzte 50 Zeilen:**
```bash
sudo journalctl -u disk2iso -n 50
```

**Seit heute:**
```bash
sudo journalctl -u disk2iso --since today
```

**Zeitraum:**
```bash
sudo journalctl -u disk2iso --since "2026-01-26 08:00" --until "2026-01-26 18:00"
```

**Nur Fehler:**
```bash
sudo journalctl -u disk2iso -p err
```

### Disc-spezifische Logs

**Speicherort:** `OUTPUT_DIR/.log/`

**Dateiname:** `<disc_label>.log`

**Ansehen:**
```bash
tail -f /media/iso/.log/Backup_2024.log
```

**Suchen:**
```bash
grep -i error /media/iso/.log/*.log
grep -i warning /media/iso/.log/*.log
```

### Performance-Monitoring

**CPU & RAM:**
```bash
systemctl status disk2iso | grep -E "Memory|CPU"
```

**Detailliert:**
```bash
systemd-cgtop
```

**Disc-I/O:**
```bash
sudo iotop -p $(pgrep -f disk2iso.sh)
```

### Log-Export

**Als Textdatei:**
```bash
sudo journalctl -u disk2iso > disk2iso.log
```

**Komprimiert:**
```bash
sudo journalctl -u disk2iso | gzip > disk2iso.log.gz
```

**JSON (für Analyse):**
```bash
sudo journalctl -u disk2iso -o json-pretty > disk2iso.json
```

---

## REST API

Das Web-Interface nutzt eine JSON REST API für alle Daten.

### Basis-URL

```
http://<server-ip>:5000/api
```

**Port:** 5000 (Flask-Backend)

### Endpunkte

#### GET /api/status

**Aktueller Systemstatus:**

```bash
curl http://localhost:5000/api/status
```

**Response:**
```json
{
  "state": "copying",
  "disc_type": "dvd-video",
  "disc_label": "THE_MATRIX",
  "progress": {
    "percent": 45,
    "current_mb": 3500,
    "total_mb": 7800,
    "speed_mbps": 18.5,
    "eta_seconds": 240
  },
  "drive": "/dev/sr0",
  "output_dir": "/media/iso"
}
```

#### GET /api/archive

**Liste aller ISOs:**

```bash
curl http://localhost:5000/api/archive
```

**Response:**
```json
{
  "audio": [],
  "dvd": [
    {
      "filename": "THE_MATRIX.iso",
      "size_mb": 7800,
      "created": "2026-01-26 10:48:46",
      "md5": "a1b2c3d4e5f6..."
    }
  ],
  "bd": [],
  "data": [
    {
      "filename": "Backup_2024.iso",
      "size_mb": 612,
      "created": "2026-01-25 14:22:10",
      "md5": "9z8y7x6w5v4u..."
    }
  ]
}
```

#### GET /api/logs

**Verfügbare Log-Dateien:**

```bash
curl http://localhost:5000/api/logs
```

**Response:**
```json
{
  "logs": [
    {
      "filename": "THE_MATRIX.log",
      "size_kb": 45,
      "modified": "2026-01-26 10:48:46"
    },
    {
      "filename": "Backup_2024.log",
      "size_kb": 12,
      "modified": "2026-01-25 14:22:10"
    }
  ]
}
```

#### GET /api/config

**Aktuelle Konfiguration:**

```bash
curl http://localhost:5000/api/config
```

**Response:**
```json
{
  "output_dir": "/media/iso",
  "cdrom_device": "/dev/sr0",
  "language": "de",
  "modules": {
    "audio_cd": true,
    "video_dvd": true,
    "bluray": false,
    "mqtt": true
  },
  "mqtt": {
    "broker": "192.168.20.10",
    "port": 1883,
    "enabled": true
  }
}
```

#### GET /api/system

**System-Informationen:**

```bash
curl http://localhost:5000/api/system
```

**Response:**
```json
{
  "os": "Debian GNU/Linux 12 (bookworm)",
  "kernel": "6.1.0-18-amd64",
  "uptime": "5 days, 12:30:45",
  "cpu": "Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz",
  "ram": {
    "total_gb": 8,
    "used_gb": 4,
    "free_gb": 4
  },
  "disk": {
    "total_gb": 500,
    "used_gb": 120,
    "free_gb": 380
  },
  "version": "1.2.0"
}
```

### Verwendung in Skripten

**Beispiel: Warten auf Abschluss**

```bash
#!/bin/bash

while true; do
    STATE=$(curl -s http://localhost:5000/api/status | jq -r '.state')
    
    if [[ "$STATE" == "completed" ]]; then
        echo "Archivierung abgeschlossen!"
        break
    elif [[ "$STATE" == "error" ]]; then
        echo "Fehler aufgetreten!"
        break
    fi
    
    echo "Aktueller Status: $STATE"
    sleep 5
done
```

---

## Tipps & Best Practices

### Performance

**Lese-Geschwindigkeit begrenzen** (weniger Lärm):

```bash
sudo hdparm -E 8 /dev/sr0    # 8x Speed
# Nach Abschluss zurücksetzen:
sudo hdparm -E 255 /dev/sr0  # Max Speed
```

**Netzwerk-Speicher:**

```bash
# NFS-Mount in /etc/fstab
nas:/media /mnt/nas nfs defaults,auto 0 0

# In config.sh
OUTPUT_DIR="/mnt/nas/media"
```

**Tipp:** Gigabit-Ethernet empfohlen für Blu-ray (50 GB).

### Batch-Processing

**100 Discs archivieren:**

1. Service läuft permanent
2. Disc 1 einlegen → Warten (~15-45 Min je nach Typ) → Disc raus
3. Disc 2 einlegen → ...
4. Disc 100 → Fertig

**Geschätzte Zeiten:**
- Daten-CD (600 MB): ~3 Min
- Daten-DVD (4 GB): ~12 Min
- Daten-Blu-ray (25 GB): ~30 Min

### Fehlerhafte Discs

**Auto-Recovery:**
- `dd` schlägt fehl → automatischer Fallback zu `ddrescue`
- `ddrescue` versucht mehrfach (3 Retries)
- ISO trotzdem erstellt (mit Lücken markiert)

**Manuelle Verbesserung:**

```bash
# ddrescue mit Log-Datei (Resume möglich)
sudo ddrescue -n /dev/sr0 disc.iso disc.log

# Disc reinigen, erneut versuchen
sudo ddrescue -r 3 /dev/sr0 disc.iso disc.log

# Log analysieren
cat disc.log | grep -i "error"
```

### Duplikate vermeiden

**Problem:** Disc schon archiviert?

**Lösung:**

```bash
# Vor Einlegen prüfen
ls /media/iso/data/ | grep "Disc_Label"

# ODER: MD5-basierte Duplikat-Erkennung (custom)
DISC_MD5=$(dd if=/dev/sr0 bs=1M count=10 2>/dev/null | md5sum | awk '{print $1}')
grep -q "$DISC_MD5" /media/iso/.duplicates && echo "Duplikat!" || echo "Neu"
```

### Konfiguration anpassen

**Ausgabeverzeichnis ändern:**

```bash
sudo nano /opt/disk2iso/disk2iso-lib/config.sh
# OUTPUT_DIR="/mnt/nas/archive"

sudo systemctl restart disk2iso
```

**Sprache ändern:**

```bash
sudo nano /opt/disk2iso/disk2iso-lib/config.sh
# readonly LANGUAGE="en"

sudo systemctl restart disk2iso
sudo systemctl restart disk2iso-web
```

### Wartung

**Log-Rotation:**

```bash
# Alte Logs komprimieren (> 30 Tage)
find /media/iso/.log -name "*.log" -mtime +30 -exec gzip {} \;

# Komprimierte Logs löschen (> 90 Tage)
find /media/iso/.log -name "*.log.gz" -mtime +90 -delete
```

**Temp-Cleanup:**

```bash
# Alte Temp-Ordner löschen (> 7 Tage)
find /media/iso/.temp -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;
```

**Cronjob (optional):**

```bash
sudo crontab -e

# Täglich um 3 Uhr
0 3 * * * find /media/iso/.log -name "*.log" -mtime +30 -exec gzip {} \;
0 3 * * * find /media/iso/.temp -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;
```

---

## Weiterführende Links

- **[← Zurück: Kapitel 2 - Installation](02_Installation.md)**
- **[Weiter: Kapitel 4 - Optionale Module →](04_Module/)**
- **[Kapitel 5 - Fehlerhandling →](05_Fehlerhandling.md)**
- **[Kapitel 6 - Entwickler →](06_Entwickler.md)**
- **[Kapitel 1 - Handbuch →](Handbuch.md)**

---

**Version:** 1.2.0  
**Letzte Aktualisierung:** 26. Januar 2026
