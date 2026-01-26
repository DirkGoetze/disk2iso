# Kapitel 5: Fehlerhandling

Intelligente Fehlerbehandlung und Recovery-Mechanismen in disk2iso.

## Inhaltsverzeichnis

1. [Übersicht](#übersicht)
2. [DVD Fehler-Tracking](#dvd-fehler-tracking)
3. [Automatische Fallback-Mechanismen](#automatische-fallback-mechanismen)
4. [Fehlerhafte Discs](#fehlerhafte-discs)
5. [Error States](#error-states)
6. [Häufige Fehler & Lösungen](#häufige-fehler--lösungen)
7. [Debug-Modus](#debug-modus)

---

## Übersicht

disk2iso implementiert **robuste Fehlerbehandlung** auf mehreren Ebenen:

1. **Automatische Retry-Mechanismen** - Mehrere Versuche bei Fehlern
2. **Intelligenter Fallback** - Alternative Methoden bei Problemen
3. **Fehler-Tracking** - Persistente Historie für problematische Medien
4. **Graceful Degradation** - System bleibt funktionsfähig auch bei Teil-Fehlern
5. **State Machine Error-States** - Definierte Fehler-Zustände

---

## DVD Fehler-Tracking

Das **Fehler-Tracking-System** verhindert, dass defekte DVDs endlos wiederholt werden.

### Drei-Stufen-System

```
1. Versuch: dvdbackup (schnell, entschlüsselt)
    ↓ Fehler
2. Versuch: ddrescue (robust, fehlertoleranter)
    ↓ Fehler
3. Versuch: ABLEHNUNG (DVD ist unlesbar)
```

### Workflow-Szenarien

#### Szenario 1: Erfolgreicher erster Versuch

```
DVD einlegen → dvdbackup kopiert → ISO erstellt → Erfolg ✓
```

**Log-Ausgabe:**
```
[INFO] Disc-Typ: dvd-video
[INFO] Label: MOVIE_TITLE
[INFO] Starte Video-DVD Backup (dvdbackup)...
[INFO] Entschlüssele mit libdvdcss2...
[SUCCESS] ISO: /media/iso/dvd/MOVIE_TITLE.iso (7.5 GB)
```

#### Szenario 2: Fehler beim ersten Versuch, Erfolg beim zweiten

```
1. DVD einlegen → dvdbackup fehlschlägt → Fehler registriert
   [INFO] DVD wird beim nächsten Versuch mit ddrescue kopiert

2. DVD reinigen → DVD erneut einlegen
   [WARNING] Diese DVD ist beim letzten Versuch fehlgeschlagen
   [INFO] Automatischer Fallback auf ddrescue (fehlertolerante Methode)
   → ddrescue kopiert → ISO erstellt → Erfolg ✓
   → Fehler-Historie wird gelöscht
```

**Log-Ausgabe:**
```
# Versuch 1:
[INFO] Disc-Typ: dvd-video
[INFO] Label: SCRATCHED_DVD
[INFO] Starte Video-DVD Backup (dvdbackup)...
[ERROR] dvdbackup fehlgeschlagen: Lesefehler Sektor 123456
[WARNING] Fehler in .failed_dvds registriert: SCRATCHED_DVD (1/2)
[INFO] Bitte Disc reinigen und erneut einlegen

# Versuch 2:
[INFO] Disc-Typ: dvd-video
[INFO] Label: SCRATCHED_DVD
[WARNING] DVD war bereits fehlgeschlagen, nutze ddrescue
[INFO] Starte Video-DVD Backup (ddrescue)...
[INFO] ddrescue: Retry fehlerhafter Sektoren...
[WARNING] 150 Sektoren nicht lesbar (0.02%)
[SUCCESS] ISO: /media/iso/dvd/SCRATCHED_DVD.iso (7.5 GB, mit Fehlern)
[INFO] Fehler-Historie gelöscht: DVD erfolgreich
```

#### Szenario 3: Mehrfacher Fehler (Ablehnung)

```
1. DVD einlegen → dvdbackup fehlschlägt → Fehler registriert

2. DVD reinigen → DVD erneut einlegen
   → ddrescue fehlschlägt → Zweiter Fehler registriert
   [ERROR] DVD endgültig fehlgeschlagen - wird beim nächsten Einlegen abgelehnt

3. DVD erneut einlegen
   [ERROR] DVD wird abgelehnt: Bereits 2x fehlgeschlagen
   [INFO] Hinweis: DVD reinigen/ersetzen und .failed_dvds löschen zum Zurücksetzen
   → Kopiervorgang wird NICHT gestartet
```

**Log-Ausgabe:**
```
# Versuch 1:
[ERROR] dvdbackup fehlgeschlagen
[WARNING] Fehler registriert: DEFECTIVE_DVD (1/2)

# Versuch 2:
[WARNING] DVD war bereits fehlgeschlagen, nutze ddrescue
[ERROR] ddrescue fehlgeschlagen: Zu viele defekte Sektoren
[ERROR] Fehler registriert: DEFECTIVE_DVD (2/2)
[ERROR] DVD wurde endgültig als defekt markiert

# Versuch 3:
[ERROR] DVD wird abgelehnt: DEFECTIVE_DVD bereits 2x fehlgeschlagen
[INFO] Disc ausgeworfen (nicht kopiert)
[INFO] Zum Zurücksetzen: sudo rm /media/iso/.failed_dvds
```

### Fehler-Datei: `.failed_dvds`

**Speicherort:** `OUTPUT_DIR/.failed_dvds`

**Format:**
```
SCRATCHED_DVD:1:2026-01-26_10:30:45
DEFECTIVE_DVD:2:2026-01-26_11:15:20
```

**Struktur:**
- Spalte 1: Disc-Label
- Spalte 2: Anzahl Fehlversuche (1 oder 2)
- Spalte 3: Zeitstempel

**Manuelles Zurücksetzen:**

```bash
# Gesamte Historie löschen
sudo rm /media/iso/.failed_dvds

# Nur eine DVD zurücksetzen
sudo nano /media/iso/.failed_dvds
# Zeile mit SCRATCHED_DVD löschen
```

### Implementierung

**Fehler registrieren:**
```bash
register_dvd_failure() {
    local disc_label="$1"
    local failed_dvds_file="$OUTPUT_DIR/.failed_dvds"
    
    # Anzahl Fehler ermitteln
    local fail_count=$(grep "^${disc_label}:" "$failed_dvds_file" 2>/dev/null | cut -d':' -f2)
    
    if [[ -z "$fail_count" ]]; then
        # Erster Fehler
        echo "${disc_label}:1:$(date +%Y-%m-%d_%H:%M:%S)" >> "$failed_dvds_file"
        log_warning "Fehler registriert: $disc_label (1/2)"
    else
        # Zweiter Fehler → endgültig defekt
        sed -i "s/^${disc_label}:1:.*/${disc_label}:2:$(date +%Y-%m-%d_%H:%M:%S)/" "$failed_dvds_file"
        log_error "DVD wurde endgültig als defekt markiert: $disc_label (2/2)"
    fi
}
```

**Fehler prüfen:**
```bash
check_dvd_failure() {
    local disc_label="$1"
    local failed_dvds_file="$OUTPUT_DIR/.failed_dvds"
    
    if [[ -f "$failed_dvds_file" ]]; then
        local fail_count=$(grep "^${disc_label}:" "$failed_dvds_file" 2>/dev/null | cut -d':' -f2)
        
        if [[ "$fail_count" == "2" ]]; then
            # Endgültig defekt → ablehnen
            log_error "DVD wird abgelehnt: $disc_label bereits 2x fehlgeschlagen"
            return 2
        elif [[ "$fail_count" == "1" ]]; then
            # Erster Fehler → ddrescue nutzen
            log_warning "DVD war bereits fehlgeschlagen, nutze ddrescue"
            return 1
        fi
    fi
    
    return 0  # Keine Fehler
}
```

---

## Automatische Fallback-Mechanismen

### DVD-Kopiermethoden

**Priorität:**
1. **dvdbackup** (schnell, entschlüsselt) - Standard
2. **ddrescue** (robust, fehlertoleranter) - Bei Fehlern oder nach 1. Versuch
3. **dd** (basic, Fallback) - Falls ddrescue nicht installiert

**Entscheidungslogik:**

```bash
copy_video_dvd() {
    local device="$1"
    local output_dir="$2"
    local disc_label="$3"
    
    # Fehler-Historie prüfen
    check_dvd_failure "$disc_label"
    local failure_status=$?
    
    case $failure_status in
        2)
            # DVD 2x fehlgeschlagen → ablehnen
            log_error "DVD wird abgelehnt (zu viele Fehler)"
            eject "$device"
            return 1
            ;;
        1)
            # DVD 1x fehlgeschlagen → sofort ddrescue
            log_warning "Nutze ddrescue (vorheriger Fehler)"
            if copy_video_dvd_ddrescue "$device" "$output_dir" "$disc_label"; then
                clear_dvd_failure "$disc_label"  # Erfolg → Historie löschen
                return 0
            else
                register_dvd_failure "$disc_label"  # 2. Fehler → endgültig
                return 1
            fi
            ;;
        0)
            # Keine Fehler → normaler Versuch mit dvdbackup
            if copy_video_dvd_backup "$device" "$output_dir" "$disc_label"; then
                return 0
            else
                # dvdbackup fehlgeschlagen → Fehler registrieren
                register_dvd_failure "$disc_label"
                log_warning "Beim nächsten Einlegen wird ddrescue verwendet"
                return 1
            fi
            ;;
    esac
}
```

### Daten-Disc Fallback

**Priorität:**
1. **dd** (schnell) - Standard
2. **ddrescue** (robust) - Bei Fehlern

**Implementierung:**

```bash
copy_data_disc() {
    local device="$1"
    local output_file="$2"
    
    # Versuche dd (schnell)
    if copy_with_dd "$device" "$output_file"; then
        log_success "Kopie erfolgreich (dd)"
        return 0
    fi
    
    # dd fehlgeschlagen → ddrescue
    log_warning "dd fehlgeschlagen, versuche ddrescue..."
    
    if command -v ddrescue &>/dev/null; then
        if copy_with_ddrescue "$device" "$output_file"; then
            log_success "Kopie erfolgreich (ddrescue, mit Retry)"
            return 0
        fi
    fi
    
    log_error "Beide Methoden fehlgeschlagen"
    return 1
}
```

---

## Fehlerhafte Discs

### Symptome

- **Lesefehler:** Kratzer, Verschmutzung, Alterung
- **Verschlüsselung:** Kaputte CSS/AACS-Sektoren
- **Physischer Schaden:** Risse, Dellen, Verfärbung

### ddrescue: Robuste Recovery

**Vorteile:**
- Multiple Retry-Versuche
- Überspringt defekte Sektoren
- Log-Datei für Resume
- Fehlerhafte Bereiche markiert

**Beispiel-Log:**

```
[INFO] Starte ddrescue (robust mode)
[INFO] Erste Runde: Schnelle Kopie gesunder Bereiche
[INFO] Fortschritt: 4.2 GB / 7.5 GB (56%, 22 MB/s)
[WARNING] Lesefehler bei Sektor 1234567
[INFO] Zweite Runde: Retry fehlerhafter Sektoren
[INFO] Retry 1/3: Sektor 1234567
[INFO] Retry 2/3: Sektor 1234567
[WARNING] Sektor 1234567 bleibt unlesbar
[INFO] Dritte Runde: Langsame Scraping-Methode
[WARNING] Gesamt 150 Sektoren nicht lesbar (0.02%)
[SUCCESS] ISO erstellt: /media/iso/dvd/SCRATCHED.iso (7.5 GB)
[INFO] Hinweis: ISO enthält 150 defekte Sektoren (mit Nullen gefüllt)
```

### Manuelle Recovery

**ddrescue mit Log-Datei:**

```bash
# Erste Kopie (schnell)
sudo ddrescue -n /dev/sr0 disc.iso disc.log

# Disc reinigen, erneut versuchen (Resume)
sudo ddrescue -r 3 /dev/sr0 disc.iso disc.log

# Log-Datei analysieren
cat disc.log | grep -i "error"
```

**ddrescue-Optionen:**

| Option | Bedeutung |
|--------|-----------|
| `-n` | No-scrape (schnell, überspringt Fehler) |
| `-r 3` | Retry 3x bei Fehlern |
| `-d` | Direct I/O (bypass cache) |
| `-v` | Verbose (detailliert) |

### ISO mit Fehlern

**Was passiert:**
- Defekte Sektoren werden mit Nullen (`\0`) gefüllt
- ISO ist lesbar, aber Daten in fehlerhaften Bereichen fehlen

**Auswirkung:**
- Video-DVD: Bild-/Ton-Aussetzer bei defekten Sektoren
- Daten-Disc: Dateien in fehlerhaften Bereichen korrupt

**Verifikation:**

```bash
# MD5 prüfen
md5sum -c disc.md5
# Warnung: MD5 ist korrekt, aber ISO enthält Nullen statt Daten

# ISO mounten und Dateien prüfen
sudo mount -o loop disc.iso /mnt
ls -lah /mnt
# Prüfe ob wichtige Dateien lesbar sind
```

---

## Error States

Die State Machine definiert den `error`-State für kritische Fehler.

### Fehler-Transition

```
[copying] → (Fehler) → [error]
                          ↓
                  [waiting_for_removal]
                          ↓
                        [idle]
```

### Error-State Auslöser

**Kritische Fehler:**
- Laufwerk nicht lesbar (Hardware-Fehler)
- Ausgabeverzeichnis nicht beschreibbar
- Abhängigkeiten fehlen (cdparanoia, dvdbackup, etc.)
- Unerwartete Exceptions

**Nicht-kritische Fehler:**
- Einzelne Disc fehlgeschlagen (→ `completed` mit Warnung)
- MusicBrainz API offline (→ Fallback zu CD-TEXT)
- MQTT-Broker offline (→ nur lokales Logging)

### Fehlerbehandlung im Code

```bash
copy_disc() {
    local device="$1"
    local output_dir="$2"
    
    # Pre-Check
    if [[ ! -b "$device" ]]; then
        log_error "Laufwerk nicht gefunden: $device"
        transition_to_state "$STATE_ERROR" "Laufwerk fehlt"
        return 1
    fi
    
    if [[ ! -w "$output_dir" ]]; then
        log_error "Ausgabeverzeichnis nicht beschreibbar: $output_dir"
        transition_to_state "$STATE_ERROR" "Keine Schreibrechte"
        return 1
    fi
    
    # Kopiervorgang
    transition_to_state "$STATE_COPYING"
    
    if ! perform_copy "$device" "$output_dir"; then
        log_error "Kopiervorgang fehlgeschlagen"
        transition_to_state "$STATE_ERROR" "Kopie fehlgeschlagen"
        return 1
    fi
    
    transition_to_state "$STATE_COMPLETED"
    return 0
}
```

### Error-State Recovery

**Automatisch:**
```
[error] → Disc entfernen → [idle] → [waiting_for_media]
```

**Manuell:**
```bash
# Service neu starten
sudo systemctl restart disk2iso

# Oder: Fehler-State manuell löschen (via API)
curl -X POST http://localhost:5000/api/reset
```

---

## Häufige Fehler & Lösungen

### Fehler: "Laufwerk nicht gefunden"

**Symptom:**
```
[ERROR] Laufwerk nicht gefunden: /dev/sr0
[ERROR] State: error (Laufwerk fehlt)
```

**Ursachen:**
- Laufwerk nicht angeschlossen
- USB-Laufwerk nicht erkannt
- Kernel-Modul nicht geladen

**Lösung:**
```bash
# Laufwerk prüfen
ls -la /dev/sr*

# Kernel-Modul laden
sudo modprobe sr_mod

# USB-Laufwerk neustarten
sudo systemctl restart disk2iso
```

### Fehler: "Permission denied"

**Symptom:**
```
[ERROR] Kann nicht auf /dev/sr0 zugreifen: Permission denied
```

**Ursache:**
Service läuft nicht als root.

**Lösung:**
```bash
# Service-Datei prüfen
sudo nano /etc/systemd/system/disk2iso.service
# User=root muss gesetzt sein

sudo systemctl daemon-reload
sudo systemctl restart disk2iso
```

### Fehler: "Output directory not writable"

**Symptom:**
```
[ERROR] Ausgabeverzeichnis nicht beschreibbar: /media/iso
[ERROR] State: error (Keine Schreibrechte)
```

**Lösung:**
```bash
# Verzeichnis erstellen
sudo mkdir -p /media/iso

# Rechte setzen
sudo chown root:root /media/iso
sudo chmod 755 /media/iso
```

### Fehler: "libdvdcss2 not found"

**Symptom:**
```
[ERROR] dvdbackup fehlgeschlagen: libdvdcss.so.2 nicht gefunden
```

**Lösung:**
```bash
sudo apt install libdvd-pkg
sudo dpkg-reconfigure libdvd-pkg
# Lizenz akzeptieren, installieren
```

### Fehler: "MusicBrainz timeout"

**Symptom:**
```
[WARNING] MusicBrainz API nicht erreichbar (Timeout nach 10s)
[INFO] Fallback zu CD-TEXT
```

**Ursache:**
- Keine Internet-Verbindung
- MusicBrainz.org offline
- Firewall blockiert

**Lösung:**
```bash
# Internet testen
ping -c 3 musicbrainz.org

# Fallback funktioniert automatisch → CD-TEXT wird genutzt
# Keine Aktion erforderlich
```

### Fehler: "MQTT broker unreachable"

**Symptom:**
```
[WARNING] MQTT Broker nicht erreichbar: 192.168.20.10:1883
[INFO] Fahre fort ohne MQTT (nur lokales Logging)
```

**Lösung:**
```bash
# Broker-IP prüfen
ping 192.168.20.10

# Mosquitto auf Home Assistant prüfen
# Add-on → Mosquitto broker → Logs

# Falls nicht wichtig: In config.sh deaktivieren
sudo nano /opt/disk2iso/disk2iso-lib/config.sh
# MQTT_ENABLED=false
```

---

## Debug-Modus

### DEBUG=true

**Aktivieren:**
```bash
# In config.sh
sudo nano /opt/disk2iso/disk2iso-lib/config.sh
DEBUG=true

# Service neu starten
sudo systemctl restart disk2iso
```

**Effekt:**
- Detaillierte Funktions-Aufrufe
- Tool-Kommandos mit vollständiger Ausgabe
- API-Responses (JSON komplett)
- Variablen-Werte bei Fehlern

**Log-Beispiel:**
```
[DEBUG] check_disc_type() aufgerufen
[DEBUG] Device: /dev/sr0
[DEBUG] Running: blkid -p -s TYPE /dev/sr0
[DEBUG] Output: TYPE="iso9660"
[DEBUG] is_data_disc() → true
[DEBUG] DISC_TYPE=cd-rom
[INFO] Disc-Typ: cd-rom
[DEBUG] copy_data_disc() aufgerufen
[DEBUG] Running: dd if=/dev/sr0 of=/media/iso/data/disc.iso bs=1M
[DEBUG] dd output: 612+0 records in, 612+0 records out
[SUCCESS] ISO erstellt
```

### VERBOSE=true

**Zusätzlich zu DEBUG:**
- Zeigt alle Bash-Kommandos (set -x)
- Hilfreich bei Script-Fehlern

```bash
DEBUG=true
VERBOSE=true
```

### Debug-Shell bei Fehler

**Aktivieren:**
```bash
DEBUG=true
DEBUG_SHELL=true
```

**Effekt:**
Bei Fehler → Interaktive Shell im Kontext öffnet.

**Beispiel:**
```
[ERROR] MusicBrainz-Lookup fehlgeschlagen
[DEBUG] Öffne Debug-Shell (exit zum Fortfahren)
bash-5.1# echo $DISCID
wXyz1234AbCd5678
bash-5.1# curl "https://musicbrainz.org/ws/2/discid/$DISCID?fmt=json"
{"error": "Rate limit exceeded"}
bash-5.1# exit
[INFO] Fahre fort ohne Metadaten...
```

---

## Weiterführende Links

- **[← Zurück: Kapitel 4 - Optionale Module](04_Module/)**
- **[Weiter: Kapitel 6 - Entwickler →](06_Entwickler.md)**
- **[Kapitel 1 - Handbuch →](Handbuch.md)**
- **[Kapitel 2 - Installation →](02_Installation.md)**
- **[Kapitel 3 - Betrieb →](03_Betrieb.md)**

---

**Version:** 1.2.0  
**Letzte Aktualisierung:** 26. Januar 2026
