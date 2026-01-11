# Deinstallation

Vollständige Entfernung von disk2iso vom System.

## Inhaltsverzeichnis

1. [Automatische Deinstallation](#automatische-deinstallation)
2. [Manuelle Deinstallation](#manuelle-deinstallation)
3. [Ausgabe-Verzeichnis](#ausgabe-verzeichnis)
4. [Verifizierung](#verifizierung)

---

## Automatische Deinstallation

### Uninstaller-Wizard

Der empfohlene Weg zur Deinstallation ist der **4-seitige Wizard**:

```bash
cd disk2iso
sudo ./uninstall.sh
```

### Wizard-Ablauf

#### Seite 1: Warnung

```
┌───────────────────────────────────────────────────────────┐
│  ⚠️  disk2iso Deinstallation                              │
│                                                           │
│  Folgendes wird entfernt:                                 │
│                                                           │
│  • Programm-Dateien:     /opt/disk2iso/                  │
│  • Systemd-Service:      /etc/systemd/system/            │
│                            disk2iso.service               │
│  • Symlink:              /usr/local/bin/disk2iso         │
│                                                           │
│  ⚠️  NICHT entfernt:                                      │
│                                                           │
│  • Ausgabe-Verzeichnis:  /srv/disk2iso/                  │
│    (Ihre archivierten ISOs bleiben erhalten)            │
│                                                           │
│  • Installierte Pakete:  cdparanoia, lame, etc.          │
│    (werden von anderen Programmen benötigt)              │
│                                                           │
│  Möchten Sie fortfahren?                                  │
│                                                           │
│  [Ja] [Nein]                                              │
└───────────────────────────────────────────────────────────┘
```

**Auswahl**:
- **Ja**: Fortfahren mit Deinstallation
- **Nein**: Abbrechen

#### Seite 2: Deinstallation

```
┌───────────────────────────────────────────────────────────┐
│  Deinstalliere disk2iso...                                │
│                                                           │
│  [████████████████████████████████] 100%                 │
│                                                           │
│  ✓ Service gestoppt:     systemctl stop disk2iso         │
│  ✓ Service deaktiviert:  systemctl disable disk2iso      │
│  ✓ Service gelöscht:     /etc/systemd/system/            │
│                            disk2iso.service               │
│  ✓ systemd neu geladen:  systemctl daemon-reload         │
│  ✓ Symlink entfernt:     /usr/local/bin/disk2iso         │
│  ✓ Programm gelöscht:    /opt/disk2iso/                  │
│                                                           │
│  Deinstallation abgeschlossen.                            │
│                                                           │
│  [OK]                                                     │
└───────────────────────────────────────────────────────────┘
```

**Aktionen**:
1. Service stoppen (falls läuft)
2. Service deaktivieren (kein Autostart)
3. Service-Datei löschen
4. systemd neu laden
5. Symlink entfernen
6. Programm-Dateien löschen

#### Seite 3: Ausgabe-Verzeichnis

```
┌───────────────────────────────────────────────────────────┐
│  Ausgabe-Verzeichnis behalten oder löschen?              │
│                                                           │
│  Verzeichnis: /srv/disk2iso                              │
│                                                           │
│  Größe:       125.8 GB                                    │
│  Dateien:     1.234 Dateien                              │
│                                                           │
│  Inhalt:                                                  │
│  • audio/     42.3 GB  (327 Alben)                       │
│  • dvd/       58.7 GB  (12 DVDs)                         │
│  • bd/        24.8 GB  (1 Blu-ray)                       │
│  • data/       0.5 GB  (8 ISOs)                          │
│  • log/        0.1 MB  (1.234 Log-Dateien)               │
│                                                           │
│  ⚠️  Diese Aktion kann nicht rückgängig gemacht werden!  │
│                                                           │
│  Soll das Ausgabe-Verzeichnis gelöscht werden?           │
│                                                           │
│  [Nein] [Ja - Alles löschen]                             │
└───────────────────────────────────────────────────────────┘
```

**Auswahl**:
- **Nein** (Standard): Verzeichnis bleibt erhalten
- **Ja - Alles löschen**: Vollständige Löschung (dauerhaft!)

**Empfehlung**: **Nein** - ISOs archivieren, bevor Sie löschen!

#### Seite 4: Abschluss

**Fall 1: Ausgabe-Verzeichnis behalten**

```
┌───────────────────────────────────────────────────────────┐
│  ✅ disk2iso wurde deinstalliert                          │
│                                                           │
│  Entfernt:                                                │
│  • /opt/disk2iso/                                        │
│  • /usr/local/bin/disk2iso                               │
│  • /etc/systemd/system/disk2iso.service                  │
│                                                           │
│  Behalten:                                                │
│  • /srv/disk2iso/ (125.8 GB, 1.234 Dateien)             │
│                                                           │
│  Hinweise:                                                │
│  • Ihre archivierten ISOs sind weiterhin verfügbar      │
│  • Ausgabe-Verzeichnis kann manuell gelöscht werden:     │
│    sudo rm -rf /srv/disk2iso                             │
│                                                           │
│  • Pakete können deinstalliert werden:                   │
│    sudo apt remove cdparanoia lame eyed3 dvdbackup       │
│                                                           │
│  [OK]                                                     │
└───────────────────────────────────────────────────────────┘
```

**Fall 2: Ausgabe-Verzeichnis gelöscht**

```
┌───────────────────────────────────────────────────────────┐
│  ✅ disk2iso wurde vollständig deinstalliert              │
│                                                           │
│  Entfernt:                                                │
│  • /opt/disk2iso/                                        │
│  • /usr/local/bin/disk2iso                               │
│  • /etc/systemd/system/disk2iso.service                  │
│  • /srv/disk2iso/ (125.8 GB gelöscht)                    │
│                                                           │
│  Hinweise:                                                │
│  • Alle archivierten ISOs wurden gelöscht                │
│  • Keine Spuren von disk2iso auf dem System              │
│                                                           │
│  • Pakete können deinstalliert werden:                   │
│    sudo apt remove cdparanoia lame eyed3 dvdbackup       │
│                                                           │
│  [OK]                                                     │
└───────────────────────────────────────────────────────────┘
```

---

## Manuelle Deinstallation

Falls der Uninstaller nicht funktioniert oder nicht verfügbar ist:

### 1. Service stoppen & deaktivieren

```bash
# Nur wenn Service-Modus installiert war
sudo systemctl stop disk2iso.service
sudo systemctl disable disk2iso.service
```

### 2. Service-Datei löschen

```bash
sudo rm -f /etc/systemd/system/disk2iso.service
sudo systemctl daemon-reload
```

**Verifizierung**:
```bash
systemctl status disk2iso.service
# → Unit disk2iso.service could not be found.
```

### 3. Symlink entfernen

```bash
sudo rm -f /usr/local/bin/disk2iso
```

**Verifizierung**:
```bash
which disk2iso
# → (keine Ausgabe)
```

### 4. Programm-Dateien löschen

```bash
sudo rm -rf /opt/disk2iso
```

**Verifizierung**:
```bash
ls /opt/disk2iso
# → ls: cannot access '/opt/disk2iso': No such file or directory
```

### 5. Abhängigkeiten entfernen (optional)

**Warnung**: Nur wenn keine anderen Programme diese Pakete benötigen!

```bash
# Audio-CD Pakete
sudo apt remove cdparanoia lame eyed3

# Video-DVD Pakete
sudo apt remove dvdbackup libdvd-pkg

# Blu-ray Pakete
sudo apt remove ddrescue

# Basis-Tools (NICHT entfernen, werden von System benötigt)
# sudo apt remove coreutils util-linux genisoimage  # NICHT ausführen!

# Autoremove (nicht mehr benötigte Abhängigkeiten)
sudo apt autoremove
```

**Prüfen welche Pakete entfernt werden**:
```bash
apt-cache rdepends --installed cdparanoia
# Zeigt welche Programme cdparanoia nutzen
```

---

## Ausgabe-Verzeichnis

### Archivieren vor Löschung

**Empfohlen**: ISOs sichern, bevor Sie das Verzeichnis löschen!

#### Methode 1: Tar-Archiv

```bash
# Vollständiges Archiv
cd /srv
sudo tar -czf disk2iso_backup_$(date +%Y%m%d).tar.gz disk2iso/

# Größe prüfen
ls -lh disk2iso_backup_*.tar.gz

# Auf externe Festplatte kopieren
sudo cp disk2iso_backup_*.tar.gz /media/usb/
```

#### Methode 2: Rsync (Netzwerk)

```bash
# Zu NAS/Server
sudo rsync -av --progress /srv/disk2iso/ user@nas:/backup/disk2iso/

# Verifizierung
rsync -av --dry-run --checksum /srv/disk2iso/ user@nas:/backup/disk2iso/
```

#### Methode 3: Selektiv kopieren

```bash
# Nur Audio-CDs
sudo cp -r /srv/disk2iso/audio/ /media/usb/music/

# Nur DVDs/Blu-rays
sudo cp -r /srv/disk2iso/{dvd,bd}/ /media/usb/movies/

# Nur Daten-ISOs
sudo cp -r /srv/disk2iso/data/ /media/usb/archives/
```

### Verzeichnis löschen

**Nach Archivierung**:

```bash
# Größe nochmal prüfen
du -sh /srv/disk2iso
# 125.8G /srv/disk2iso

# Inhalt auflisten
ls -lh /srv/disk2iso/

# Löschen (VORSICHT!)
sudo rm -rf /srv/disk2iso
```

**Verifizierung**:
```bash
ls /srv/disk2iso
# → ls: cannot access '/srv/disk2iso': No such file or directory
```

### Nur Logs/Temp löschen (Dateien behalten)

```bash
# Nur temporäre Dateien
sudo rm -rf /srv/disk2iso/.temp/*
sudo rm -rf /srv/disk2iso/.log/*

# Größe vorher/nachher
du -sh /srv/disk2iso
```

---

## Verifizierung

### Deinstallation vollständig

**Checkliste**:

```bash
# 1. Service nicht mehr vorhanden
systemctl status disk2iso.service
# → could not be found

# 2. Symlink entfernt
which disk2iso
# → (keine Ausgabe)

# 3. Programm-Dateien weg
ls /opt/disk2iso
# → No such file or directory

# 4. Service-Datei weg
ls /etc/systemd/system/disk2iso.service
# → No such file or directory

# 5. Keine laufenden Prozesse
ps aux | grep disk2iso
# → nur grep selbst
```

### Ausgabe-Verzeichnis

**Behalten**:
```bash
ls -lh /srv/disk2iso/
# → audio/ dvd/ bd/ data/ log/
```

**Gelöscht**:
```bash
ls /srv/disk2iso
# → No such file or directory
```

### Keine Reste

**Konfiguration**:
```bash
# Keine Configs in Home
ls ~/.disk2iso*
ls ~/.config/disk2iso

# Keine systemd-Logs mehr
sudo journalctl -u disk2iso.service
# → No entries (oder alte Einträge)
```

**Cleanup**:
```bash
# Alte Journal-Logs löschen
sudo journalctl --vacuum-time=1d
```

---

## Neuinstallation

Nach Deinstallation kann disk2iso jederzeit neu installiert werden:

```bash
# Frische Installation
cd disk2iso
sudo ./install.sh

# Ausgabe-Verzeichnis erneut nutzen (falls behalten)
# Wizard zeigt vorhandene Daten an:
# "Ausgabe-Verzeichnis /srv/disk2iso existiert bereits (125.8 GB)"
```

---

## Weiterführende Links

- **[← Zurück zum Handbuch](Handbuch.md)**
- **[Installation als Script](Installation-Script.md)** - Neuinstallation
- **[Installation als Service](Installation-Service.md)** - Service-Modus

---

**Version**: 1.3.0 | **Letzte Aktualisierung**: 11.01.2026
