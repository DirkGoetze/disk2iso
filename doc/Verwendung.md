# Verwendung

Praktische Anleitung zur Nutzung von disk2iso im Script- und Service-Modus.

## Inhaltsverzeichnis

1. [Script-Modus](#script-modus)
2. [Service-Modus](#service-modus)
3. [Konfiguration](#konfiguration)
4. [Ausgabe-Struktur](#ausgabe-struktur)
5. [Disc-Typen](#disc-typen)
6. [Debug-Modus](#debug-modus)
7. [Tipps & Best Practices](#tipps--best-practices)

---

## Script-Modus

### Grundlegende Verwendung

```bash
# Einfacher Start (erfordert Ausgabeverzeichnis)
sudo disk2iso -o /srv/disk2iso

# Oder mit langer Option
sudo disk2iso --output /srv/disk2iso

# Im Hintergrund
sudo disk2iso -o /srv/disk2iso &
```

**Hinweis**: Das Ausgabeverzeichnis **muss** immer angegeben werden.

### Parameter

| Parameter | Beschreibung |
|-----------|-------------|
| `-o DIR`, `--output DIR` | Ausgabeverzeichnis (erforderlich) |

**Keine weiteren Parameter** verfügbar.

### Workflow

1. **Script starten**:
   ```bash
   sudo disk2iso -o /srv/disk2iso
   ```
   
   **Ausgabe**:
   ```
   disk2iso gestartet
   Ausgabeverzeichnis: /srv/disk2iso
   Laufwerk erkannt: /dev/sr0
   Überwache Laufwerk...
   ```

2. **Disc einlegen**: Audio-CD, DVD oder Blu-ray

3. **Automatische Erkennung**:
   ```
   [INFO] Disc eingelegt
   [INFO] Erkenne Disc-Typ... audio-cd
   [INFO] Label: Greatest_Hits_2023
   [INFO] Starte Archivierung...
   ```

4. **Fortschritt**:
   ```
   [INFO] Track 1/14: Song Title
   [=====>                    ] 25% (3.2 MB/s, ETA 2:15)
   ```

5. **Abschluss**:
   ```
   [SUCCESS] Archivierung abgeschlossen
   [INFO] Ausgabe: /srv/disk2iso/audio/Artist/Album
   [INFO] Disc wird ausgeworfen...
   ```

6. **Nächste Disc**: Automatisch zurück zu "Warte auf Disc..."

### Beenden

```bash
# Mit Strg+C
^C
[INFO] SIGINT empfangen, beende...
[INFO] Cleanup abgeschlossen
```

---

## Service-Modus

### Automatischer Betrieb

Im Service-Modus läuft disk2iso permanent:

1. **Disc einlegen** → Automatisch Start
2. **Archivierung** → Automatisch
3. **Disc auswerfen** → Automatisch
4. **Bereit für nächste Disc**

### Keine Interaktion erforderlich

✅ **Workflow**:
- Disc rein → Warten → Disc raus → Fertig

❌ **Nicht möglich**:
- Manuelle Steuerung während Archivierung
- Interaktive Bestätigung

### Logs verfolgen

```bash
# Echtzeit-Monitoring
sudo journalctl -u disk2iso.service -f

# Letzte 50 Zeilen
sudo journalctl -u disk2iso.service -n 50

# Seit letztem Neustart
sudo journalctl -u disk2iso.service -b

# Nur Fehler
sudo journalctl -u disk2iso.service -p err
```

### Temporär pausieren

```bash
# Service stoppen
sudo systemctl stop disk2iso

# Disc manuell bearbeiten (direkter Aufruf)
sudo /opt/disk2iso/disk2iso.sh -o /srv/disk2iso

# Service wieder starten
sudo systemctl start disk2iso
```

---

## Konfiguration

### Eingebaute Konfiguration

disk2iso hat **keine editierbare config.sh** mit Benutzeroptionen. Alle Einstellungen sind fest im Code integriert:

#### Ausgabe-Verzeichnis

**Festgelegt bei Installation** (via install.sh) oder per Parameter:

```bash
# Manuelle Ausführung mit anderem Ausgabeverzeichnis
sudo disk2iso -o /media/usb/archiv
sudo disk2iso --output /mnt/nas/media
```

**Standard-Installation**: `/srv/disk2iso`

#### Laufwerk

**Automatische Erkennung**: `/dev/sr0` (erstes optisches Laufwerk)

```bash
# Anderes Laufwerk nutzen
sudo disk2iso -d /dev/sr1
sudo disk2iso --device /dev/sr1
```

#### Module

**Automatische Aktivierung** basierend auf installierten Tools:

- **Audio-CD**: Aktiv wenn `cdparanoia`, `lame`, `genisoimage` vorhanden
- **Video-DVD**: Aktiv wenn `dvdbackup`, `genisoimage` vorhanden  
- **Blu-ray**: Aktiv wenn `ddrescue` vorhanden
- **Daten-Discs**: Immer aktiv (nutzt `dd`)

**Kein manueller Schalter** - Module werden bei Bedarf geladen.

#### Audio-CD Einstellungen

**Fest kodiert** in `lib-cd.sh`:

```bash
# MP3-Qualität: VBR V2 (~190 kbps)
lame -V2 --quiet

# MusicBrainz: Immer aktiviert (falls curl/jq verfügbar)
# Cover-Download: Immer aktiviert (falls eyeD3 verfügbar)
# Jellyfin NFO: Immer erstellt
```

**Nicht konfigurierbar** ohne Code-Änderung.

#### DVD/Blu-ray Methoden

**Automatische Methoden-Wahl** basierend auf verfügbaren Tools:

**DVD**:
1. `dvdbackup` + `genisoimage` (entschlüsselt, bevorzugt)
2. `ddrescue` (verschlüsselt, robust)
3. `dd` (verschlüsselt, Fallback)

**Blu-ray**:
1. `ddrescue` (verschlüsselt, robust)
2. `dd` (verschlüsselt, Fallback)

**Keine Konfiguration** - beste verfügbare Methode wird automatisch gewählt.

#### Fest integrierte Optionen

**Immer aktiv**:
- ✅ MD5-Checksummen für alle ISOs
- ✅ Auto-Eject nach Erfolg
- ✅ Detailliertes Logging pro Disc
- ✅ Automatisches Temp-Cleanup

**Nicht konfigurierbar**.

### Debug-Modus

**Aktivierung per Umgebungsvariable** (nicht in config.sh):

```bash
# Debug-Ausgabe
DEBUG=1 sudo disk2iso

# Verbose-Modus
VERBOSE=1 sudo disk2iso

# Strict-Modus (Entwicklung)
STRICT=1 sudo disk2iso
```

### Sprache

**Fest kodiert** in `config.sh`:

```bash
readonly LANGUAGE="de"
```

**Änderung**: Code-Datei editieren (kein User-Setting):
```bash
sudo nano /opt/disk2iso/disk2iso-lib/config.sh
# Zeile 18: readonly LANGUAGE="en"
```

**Verfügbare Sprachen**:
- `de`: Deutsch (Standard)
- `en`: Englisch (Fallback)

### Zusammenfassung

**disk2iso ist nicht konfigurierbar** im klassischen Sinne. Alle Einstellungen sind:
- ✅ Automatisch (beste Methode basierend auf Tools)
- ✅ Fest kodiert (optimale Defaults)
- ✅ Per Parameter (Ausgabeverzeichnis, Laufwerk)

**Für Anpassungen**: Code-Änderungen in `/opt/disk2iso/disk2iso-lib/lib-*.sh` erforderlich.

---

## Ausgabe-Struktur

### Ordner-Hierarchie

```
OUTPUT_DIR/
├── audio/              # Audio-CDs (lib-cd.sh)
├── dvd/                # Video-DVDs (lib-dvd.sh)
├── bd/                 # Blu-rays (lib-bluray.sh)
├── data/               # Daten-Discs (immer)
├── .log/               # Log-Dateien (versteckt)
└── .temp/              # Temporär (auto-cleanup, versteckt)
```

### Audio-CD Struktur

```
audio/
└── Artist Name/
    └── Album Title (Year)/
        ├── 01 - Track Title.mp3
        ├── 02 - Track Title.mp3
        ├── ...
        ├── 14 - Track Title.mp3
        ├── folder.jpg           # Album-Cover (500x500)
        └── album.nfo            # Jellyfin-Metadaten
```

**Dateinamen-Schema**:
- **Mit MusicBrainz**: `Artist/Album (Year)/NN - Title.mp3`
- **Ohne MusicBrainz**: `Unknown_Artist/Unknown_Album/Track_NN.mp3`

**album.nfo** (Jellyfin/Kodi):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<album>
  <title>Album Title</title>
  <artist>Artist Name</artist>
  <year>2023</year>
  <genre>Rock</genre>
  <musicbrainzalbumid>a1b2c3d4-...</musicbrainzalbumid>
</album>
```

### Video-DVD Struktur

```
dvd/
├── Movie_Title.iso
└── Movie_Title.md5
```

**ISO-Inhalt**: Entschlüsselte VIDEO_TS-Struktur
```
VIDEO_TS/
├── VIDEO_TS.IFO
├── VIDEO_TS.VOB
├── VTS_01_0.IFO
├── VTS_01_1.VOB
├── VTS_01_2.VOB
└── ...
```

### Blu-ray Struktur

```
bd/
├── Movie_Title.iso
└── Movie_Title.md5
```

**ISO-Inhalt**: 1:1 Kopie (ggf. verschlüsselt)
```
BDMV/
├── index.bdmv
├── MovieObject.bdmv
├── PLAYLIST/
│   └── 00000.mpls
└── STREAM/
    ├── 00000.m2ts
    └── ...
```

### Daten-Disc Struktur

```
data/
├── Backup_2023-01-01.iso
├── Backup_2023-01-01.md5
├── Software_Install_CD.iso
└── Software_Install_CD.md5
```

### Log-Dateien

```
log/
├── Greatest_Hits_2023.log      # Pro Disc
├── Movie_Title.log
└── Backup_2023-01-01.log
```

**Log-Inhalt**:
```
[2026-01-01 10:15:00] [INFO] Disc eingelegt: /dev/sr0
[2026-01-01 10:15:01] [INFO] Disc-Typ: audio-cd
[2026-01-01 10:15:01] [INFO] Label: Greatest_Hits_2023
[2026-01-01 10:15:01] [INFO] MusicBrainz Disc ID: wXyz1234...
[2026-01-01 10:15:02] [INFO] Album: Artist - Greatest Hits (2023)
[2026-01-01 10:15:02] [INFO] Tracks: 14
[2026-01-01 10:15:02] [INFO] Starte Audio-Extraktion...
...
[2026-01-01 10:18:46] [SUCCESS] Ausgabe: /srv/disk2iso/audio/Artist/Greatest_Hits
```

### Temp-Verzeichnis

```
temp/
├── mountpoints/
│   └── disc_wXyz1234_12345/   # Mount-Point für Label-Erkennung
└── disc_wXyz1234_12345/       # Arbeitsverzeichnis
    ├── track01.cdda.wav       # Temporäre WAV-Dateien
    └── track01.cdda.wav.mp3   # Vor ID3-Tagging
```

**Cleanup**: Automatisch nach Abschluss oder Fehler.

---

## Disc-Typen

### Audio-CD

**Erkennung**: TOC-Analyse (keine Dateisystem, nur Audio-Tracks)

**Prozess**:
1. Disc ID via cdparanoia
2. MusicBrainz-Lookup (falls aktiviert)
3. Track-Extraktion (cdparanoia)
4. MP3-Encoding (lame)
5. ID3-Tags (eyed3)
6. Cover-Download (Cover Art Archive)
7. NFO-Datei (Jellyfin)

**Ausgabe**: `/srv/disk2iso/audio/Artist/Album/*.mp3`

**Beispiel-Log**:
```
[INFO] Disc-Typ: audio-cd
[INFO] Tracks: 14
[INFO] MusicBrainz ID: wXyz1234AbCd5678
[INFO] Album: Pink Floyd - The Wall (1979)
[INFO] Track 1/14: In the Flesh?
[INFO] cdparanoia: 0 Fehler, 0 Jitter
[INFO] lame: VBR V2, 192 kbps average
[INFO] Cover: 500x500 px (45 KB)
[SUCCESS] 14 Tracks, 56:32 min, 108 MB
```

### Video-DVD

**Erkennung**: UDF-Dateisystem + VIDEO_TS-Ordner

**Prozess**:
1. Label-Erkennung (isoinfo/blkid)
2. dvdbackup (entschlüsselt mit libdvdcss2)
3. genisoimage (VIDEO_TS → ISO)
4. MD5-Checksumme

**Ausgabe**: `/srv/disk2iso/dvd/Movie_Title.iso`

**Beispiel-Log**:
```
[INFO] Disc-Typ: dvd-video
[INFO] Label: THE_MATRIX
[INFO] Größe: 7.8 GB
[INFO] Verschlüsselt: ja (CSS)
[INFO] dvdbackup: Entschlüssele...
[INFO] Titel: 1/8
[INFO] genisoimage: Erstelle ISO...
[INFO] MD5: a1b2c3d4e5f6...
[SUCCESS] ISO: /srv/disk2iso/dvd/THE_MATRIX.iso (7.8 GB)
```

### Blu-ray

**Erkennung**: UDF 2.50+ + BDMV-Ordner

**Prozess**:
1. Label-Erkennung
2. ddrescue (robustes Kopieren)
3. MD5-Checksumme

**Ausgabe**: `/srv/disk2iso/bd/Movie_Title.iso`

**Beispiel-Log**:
```
[INFO] Disc-Typ: bd-video
[INFO] Label: ALITA_BATTLE_ANGEL
[INFO] Größe: 48.2 GB
[INFO] Verschlüsselt: ja (AACS v4)
[INFO] ddrescue: Start (robust mode)
[INFO] Fortschritt: 12.5 GB / 48.2 GB (25%, 42 MB/s, ETA 15:20)
[WARNING] 128 Sektoren nicht lesbar (verschlüsselt)
[INFO] MD5: 1a2b3c4d5e6f...
[SUCCESS] ISO: /srv/disk2iso/bd/ALITA_BATTLE_ANGEL.iso (48.2 GB)
```

**Hinweis**: ISO enthält verschlüsselte Daten. Wiedergabe erfordert AACS-Schlüssel (z.B. via MakeMKV extern).

### Daten-CD/DVD/BD

**Erkennung**: ISO9660, UDF oder gemischtes Dateisystem (ohne VIDEO_TS/BDMV)

**Prozess**:
1. Label-Erkennung
2. dd (schnell) oder ddrescue (bei Fehler)
3. MD5-Checksumme

**Ausgabe**: `/srv/disk2iso/data/Disc_Label.iso`

**Beispiel-Log**:
```
[INFO] Disc-Typ: cd-rom
[INFO] Label: Backup_2023-01-01
[INFO] Dateisystem: ISO9660 + Joliet
[INFO] Größe: 612 MB
[INFO] dd: Start...
[INFO] Fortschritt: 612 MB / 612 MB (100%, 18 MB/s)
[INFO] MD5: 9z8y7x6w5v4u...
[SUCCESS] ISO: /srv/disk2iso/data/Backup_2023-01-01.iso (612 MB)
```

---

## Debug-Modus

### Aktivieren

Per **Umgebungsvariable** (vor dem Aufruf):

```bash
# Debug-Modus (detaillierte Ausgabe)
DEBUG=1 sudo disk2iso -o /srv/disk2iso

# Verbose-Modus (zeigt gelesene Zeilen)
VERBOSE=1 sudo disk2iso -o /srv/disk2iso

# Strict-Modus (Entwicklung, beendet bei Fehlern)
STRICT=1 sudo disk2iso -o /srv/disk2iso
```

### DEBUG=1

**Normale Ausgabe**:
```
[INFO] Disc-Typ: audio-cd
[INFO] Starte cdparanoia...
[SUCCESS] Track 1 abgeschlossen
```

**Debug-Ausgabe**:
```
[DEBUG] check_disc_type() aufgerufen
[DEBUG] Lese TOC: /dev/sr0
[DEBUG] cdparanoia -d /dev/sr0 -Q
[DEBUG] Output: 14 Audio-Tracks gefunden
[DEBUG] is_audio_cd() → true
[DEBUG] Disc-Typ: audio-cd
[DEBUG] MODULE_AUDIO_CD=true
[DEBUG] Lade lib-cd.sh...
[DEBUG] copy_audio_cd() aufgerufen
[DEBUG] MusicBrainz lookup: discid=wXyz1234...
[DEBUG] curl -s 'https://musicbrainz.org/ws/2/discid/wXyz1234?fmt=json'
[DEBUG] Response: {"artist": "Pink Floyd", "title": "The Wall", ...}
[DEBUG] parse_musicbrainz_response()
[DEBUG] Artist: Pink Floyd
[DEBUG] Album: The Wall
[DEBUG] Year: 1979
[DEBUG] Tracks: 14
[DEBUG] cdparanoia -d /dev/sr0 -w 1
[DEBUG] Output: PARANOIA: retries=0, jitter=0
[SUCCESS] Track 1 abgeschlossen
```

**Verwendung**:
- Fehlersuche bei MusicBrainz-Problemen
- API-Response überprüfen
- Tool-Aufrufe nachvollziehen

---

## Tipps & Best Practices

### Performance

#### DVD/Blu-ray (Lese-Geschwindigkeit)

**Problem**: Laufwerk zu laut

**Lösung**:
```bash
# Geschwindigkeit begrenzen (vor Start)
sudo hdparm -E 8 /dev/sr0    # 8x Speed

# Nach Abschluss zurücksetzen
sudo hdparm -E 255 /dev/sr0  # Max Speed
```

### Netzwerk-Speicher (NFS/CIFS)

**config.sh**:
```bash
OUTPUT_DIR="/mnt/nas/media"
```

**Mount in /etc/fstab**:
```bash
# NFS
nas:/media /mnt/nas nfs defaults,auto 0 0

# CIFS (SMB)
//nas/media /mnt/nas cifs credentials=/root/.smbcreds,uid=root,gid=root 0 0
```

**Performance-Tipp**: Große Dateien (Blu-ray) profitieren von Gigabit-Ethernet.

### Duplikate vermeiden

**Problem**: Disc schon archiviert?

**Lösung**:
```bash
# MD5-Prüfung vor Archivierung (custom script)
#!/bin/bash
DISC_MD5=$(isoinfo -d -i /dev/sr0 | md5sum | awk '{print $1}')
if grep -q "$DISC_MD5" /srv/disk2iso/duplicates.log; then
    echo "Disc bereits archiviert!"
    exit 1
fi
```

**Integration**: In disk2iso.sh nach Zeile 120 einfügen.

### Batch-Processing

**Szenario**: 100 CDs archivieren

**Empfehlung**: Service-Modus

1. `sudo systemctl start disk2iso`
2. Disc 1 einlegen → Warten → Disc raus
3. Disc 2 einlegen → Warten → Disc raus
4. ...
5. Disc 100 → Fertig

**Zeit**:
- Audio-CD: ~15 Min (12 Tracks)
- Video-DVD: ~33 Min (7.5 GB, entschlüsselt)
- Blu-ray: ~42 Min (46.6 GB, ddrescue)

### Fehlerhafte Discs

**Symptom**: Lese-Fehler, Kratzer

**Auto-Recovery**:
1. ddrescue versucht mehrfach
2. Fehlerhafte Sektoren → Log
3. ISO trotzdem erstellt (mit Lücken)

**Manuelle Verbesserung**:
```bash
# ddrescue mit Log-Datei (Resume möglich)
sudo ddrescue -n /dev/sr0 disc.iso disc.log

# Disc reinigen, erneut versuchen
sudo ddrescue -r 3 /dev/sr0 disc.iso disc.log

# Log analysieren
cat disc.log | grep -i "error"
```

### Metadaten-Qualität (Audio-CD)

**Problem**: Falsche MusicBrainz-Daten

**Lösung 1: MusicBrainz-Eintrag korrigieren**
- Auf [musicbrainz.org](https://musicbrainz.org) registrieren
- Disc-ID suchen
- Metadaten bearbeiten

**Lösung 2: Manuelle Bearbeitung**
```bash
# ID3-Tags ändern
eyeD3 --artist "Correct Artist" --album "Correct Album" track.mp3

# Album-Cover ersetzen
eyeD3 --add-image correct_cover.jpg:FRONT_COVER *.mp3

# NFO bearbeiten
nano album.nfo
```

---

## Weiterführende Links

- **[← Zurück zum Handbuch](Handbuch.md)**
- **[Installation als Script](Installation-Script.md)**
- **[Installation als Service](Installation-Service.md)**
- **[Entwickler-Dokumentation →](Entwickler.md)**

---

**Version**: 1.1.0 | **Letzte Aktualisierung**: 04.01.2026
