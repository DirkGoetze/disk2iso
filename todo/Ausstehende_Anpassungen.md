# disk2iso - Ausstehende Anpassungen

**Stand:** 26. Januar 2026  
**Erstellt:** Automatische Konsolidierung aller TODO-Dateien  
**Quelle:** Analyse von ForNextRelease.md, Frontend-Modularisierung.md, GitHub-Issues.md, Metadata-Cache-DB.md, Metadata-PlugIn_Konzept.md

---

## � GITHUB ISSUES ZUSAMMENFASSUNG

**Gesamt:** 14 Open, 6 Closed  
**Davon:**
- 🔴 **4 kritische Bugs** (#11, #9, #4, #20)
- 🟡 **8 Verbesserungen/Features** (#15, #19, #8, #13, #12, #10, #22, #21)
- ⚠️ **2 teilweise behoben** (#5, #7) - Runtime-Tests ausstehend
- ✅ **4 komplett erledigt** (#18, #17, #16, #14)
- ❓ **2 Details unklar** (#6, #9)

**Quick-Win:** Issue #20 kann in 5 Minuten gelöst werden! ⭐

---

## �📋 ÜBERSICHT NACH PRIORITÄT

### 🔴 KRITISCH - Bugs (Sofort beheben)

#### 1. GitHub #11 - MQTT Meldungen kommen doppelt
**Bereich:** [lib/libmqtt.sh](../lib/libmqtt.sh)  
**Problem:** MQTT-Nachrichten werden doppelt gesendet  
**Mögliche Ursachen:**

- `publish_mqtt()` wird zweimal aufgerufen
- Mehrere MQTT-Clients aktiv
- Retain-Flag verursacht Echo

**Diagnose nötig:**

- MQTT-Logging aktivieren
- MQTT-Broker Logs prüfen
- Alle `publish_mqtt()` Aufrufe durchsuchen

---

#### 2. GitHub #9 - Anzeige von ISO Dateien
**Bereich:** [www/app.py](../www/app.py), [www/templates/archive.html](../www/templates/archive.html)  
**Problem:** ISO-Dateien werden nicht korrekt angezeigt im Archiv  
**Betroffene Dateien:**

- `www/app.py` - `/archive` Route
- `www/templates/archive.html`
- Möglicherweise `get_iso_files_by_type()` Funktion

**Diagnose nötig:** Detaillierte Beschreibung was genau nicht funktioniert

---

#### 3. GitHub #4 - Archiv - Metadaten hinzufügen funktioniert nicht
**Bereich:** [www/app.py](../www/app.py) - Archiv-Management  
**Problem:** Nachträgliches Hinzufügen von Metadaten über Web-UI schlägt fehl  
**Betroffene Dateien:**

- `www/app.py` - Metadata-Update Endpoints
- `www/templates/archive.html`

**Diagnose nötig:** Detaillierte Fehlerbeschreibung, Error-Logs

---

#### 4. GitHub #20 - Formatierungsproblem Fortschritt ⚠️
**Status:** ⚠️ FAST FERTIG - Nur Template-Fix ausstehend (5 Min)  
**Bereich:** [www/templates/index.html:65-67](../www/templates/index.html#L65-L67)  
**Problem:** Fortschrittsbalken Speicherplatz zeigt falsche Richtung

**Noch zu tun:**

```html
<!-- AKTUELL (falsch): -->
<div class="progress-overlay" style="width: {{ disk_space.free_percent }}%"></div>

<!-- KORRIGIEREN ZU: -->
<div class="progress-overlay" style="width: {{ disk_space.used_percent }}%"></div>
```

**Hintergrund:** Issue #20 wurde am 18.01.2026 analysiert, Lösung ist klar, nur 1 Zeile ändern

---

### 🟡 WICHTIG - Verbesserungen (Bald umsetzen)

#### 5. GitHub #15 - Fehlgeschlagene Kopiervorgänge
**Bereich:** [lib/libcommon.sh](../lib/libcommon.sh), [disk2iso.sh](../disk2iso.sh)  
**Features:**
- Wiederholungsversuche bei Fehlern
- Besseres Fehler-Logging
- Benachrichtigung via MQTT

**Betroffene Dateien:**
- `lib/libcommon.sh` - Copy-Funktionen
- `disk2iso.sh` - State-Machine
- `lib/libmqtt.sh` - Error-Notifications

---

#### 6. ForNextRelease - Auto-Cleanup Cronjob
**Bereich:** System-Wartung  
**Problem:**
- Fehlgeschlagene Operationen hinterlassen Temp-Ordner in `/media/iso/.temp/`
- Cover-Cache wächst unbegrenzt in `/opt/disk2iso/.temp/`
- Alte Logs füllen Festplatte

**Lösung:** Cronjob `/etc/cron.daily/disk2iso-cleanup`
```bash
#!/bin/bash
# Alte Temp-Operationen löschen (> 7 Tage)
find /media/iso/.temp -maxdepth 1 -type d -mtime +7 -name "*_*" -exec rm -rf {} \; 2>/dev/null

# Alte Cover-Cache löschen (> 30 Tage)
find /opt/disk2iso/.temp -name "cover_*.jpg" -mtime +30 -delete 2>/dev/null

# Alte Logs komprimieren (> 30 Tage)
find /media/iso/.log -name "disk2iso_*.log" -mtime +30 -exec gzip {} \; 2>/dev/null

# Komprimierte Logs löschen (> 90 Tage)
find /media/iso/.log -name "*.log.gz" -mtime +90 -delete 2>/dev/null
```

**Integration:** In `install.sh` installieren

---

#### 7. GitHub #19 - Archivierte Logs über WEB-UI öffnen
**Bereich:** [www/app.py](../www/app.py), [www/templates/logs.html](../www/templates/logs.html)  
**Problem:** Archivierte Logs können gesucht, aber nicht angezeigt werden

**Lösung:**
- Neue Route `/logs/view/<filename>` in app.py
- Link zu archivierten Logs in logs.html

---

#### 8. GitHub #8 - Einstellungen Ausgabeverzeichnis
**Bereich:** [www/templates/config.html](../www/templates/config.html), [www/app.py](../www/app.py)  
**Feature:** Ausgabeverzeichnis in Web-UI änderbar machen

**Betroffene Dateien:**
- `www/templates/config.html` - Input für `DEFAULT_OUTPUT_DIR`
- `www/app.py` - `/api/config` POST erweitern
- `lib/libconfig.sh` - `update_config_value()` nutzen

**Wichtig:** Validierung ob Pfad existiert & beschreibbar!

---

### 🟢 MITTEL - Neue Features (Geplant)

#### 9. GitHub #13 - Anzeige zum Service
**Bereich:** [www/templates/index.html](../www/templates/index.html)  
**Verbesserung:** Bessere Visualisierung des Service-Status

**Ideen:**
- Service läuft seit: Uptime
- Letzte Aktivität: Zeitstempel
- Status-Icon: Grün/Gelb/Rot

**Betroffene Dateien:**
- `www/app.py` - `/api/status` erweitern
- `www/templates/index.html`

---

#### 10. GitHub #12 - Home Seite unruhig
**Bereich:** [www/static/js/index.js](../www/static/js/index.js)  
**Problem:** AJAX-Polling verursacht flackernde UI-Updates

**Lösung:**
- Diff-basierte Updates (nur Änderungen)
- CSS-Transitions für sanfte Übergänge
- Debouncing

---

#### 11. GitHub #10 - Feat. Anzeige kompakter machen
**Bereich:** [www/templates/](../www/templates/), [www/static/css/style.css](../www/static/css/style.css)  
**Ziel:** UI optimieren für weniger Scrolling

**Ideen:**
- Kollapsbare Sektionen
- Kompaktere Layouts
- Responsive Design verbessern

---

#### 12. GitHub #22 - Taggen von MP3 bei mehreren Interpreten
**Bereich:** [lib/libaudio.sh](../lib/libaudio.sh) (Metadata-Teil)  
**Komplexität:** MITTEL  
**Ziel:** Besseres Tagging bei "feat." Artists

**Beispiel:**
```
Aktuell:
Titel: "Driving Home for Christmas"
Artist: "Chris Rea feat. XYZ"

Soll werden:
- AlbumArtist: Chris Rea
- Artist: Chris Rea feat. XYZ
- Ordner: /Chris Rea/Album/Track.mp3
```

**Lösung:** MusicBrainz Artist-Credits nutzen

---

#### 13. GitHub #21 - Taggen von MP3 bei Samplern
**Bereich:** [lib/libaudio.sh](../lib/libaudio.sh) (Metadata-Teil)  
**Komplexität:** HOCH  
**Ziel:** Sampler mit "AlbumArtist: Various Artists" besser handhaben

**Beispiel:**
```
Aktuell (schlecht):
/Various Artists/Rock Christmas/01 - Driving Home.mp3

Soll werden:
/Chris Rea/Original Album/01 - Driving Home.mp3
```

**Logik:**
1. Erkenne `AlbumArtist == "Various Artists"`
2. Für jeden Track: Suche Original-Album des Künstlers
3. Erstelle Ordner: `/Artist/OriginalAlbum/Track.mp3`
4. Generiere Album-Cover pro Artist-Album

**Betroffene Dateien:**
- `lib/libaudio.sh` (Metadata-Teil)
- `lib/libfolders.sh` - Mehrere Ordner pro CD
- MusicBrainz API - Recording-Lookup

---

### 🎯 OPTIONAL - Nice-to-Have Features

#### 14. ForNextRelease - Metadaten-Edit-Wrapper für normale User
**Bereich:** System-Tools  
**Problem:** ISOs/Metadaten gehören root:root, User können `.nfo` nicht direkt bearbeiten

**Lösung:** Helper-Script `/usr/local/bin/disk2iso-edit`
```bash
#!/bin/bash
case "$1" in
    nfo)
        sudo -u root nano "$2"
        ;;
    cover)
        sudo -u root cp "$2" "$3"
        ;;
esac
```

**Sudoers-Regel:**
```
%users ALL=(root) NOPASSWD: /usr/local/bin/disk2iso-edit
```

**Aufwand:** Mittel  
**Impact:** Niedrig - Quality-of-Life Verbesserung

---

#### 15. ForNextRelease - Audio-CD Normalization
**Bereich:** [lib/libaudio.sh](../lib/libaudio.sh)  
**Feature:** MP3-Lautstärke normalisieren mit ReplayGain

```bash
# Nach MP3-Konvertierung
if command -v mp3gain &>/dev/null; then
    log_message "INFO" "Normalisiere Lautstärke mit mp3gain..."
    mp3gain -r -k "$temp_dir"/*.mp3 2>&1 | tee -a "$LOGFILE"
fi
```

**Voraussetzung:** `mp3gain` installieren

---

#### 16. ForNextRelease - Email-Benachrichtigungen
**Bereich:** [lib/libcommon.sh](../lib/libcommon.sh)  
**Feature:** Email bei Operation-Ende (Erfolg/Fehler)

**Config:**
```bash
NOTIFY_EMAIL=""  # Leer = deaktiviert
```

**Implementation:**
```bash
send_notification() {
    local status=$1
    local disc_label=$2
    
    if [[ -n "$NOTIFY_EMAIL" ]]; then
        echo "Disc: $disc_label - Status: $status" | \
            mail -s "[disk2iso] Operation $status" "$NOTIFY_EMAIL"
    fi
}
```

---

#### 17. ForNextRelease - ISO-Scanning-Caching
**Bereich:** [www/app.py](../www/app.py)  
**Problem:** `/api/archive` scannt bei jedem Request alle ISOs neu

**Lösung:** Cache ISO-Liste für 60 Sekunden
```python
from functools import lru_cache
import time

_iso_cache = None
_iso_cache_time = 0

@app.route('/api/archive')
def api_archive():
    global _iso_cache, _iso_cache_time
    
    if time.time() - _iso_cache_time < 60 and _iso_cache:
        return jsonify(_iso_cache)
    
    # Scan durchführen...
    _iso_cache = result
    _iso_cache_time = time.time()
    
    return jsonify(result)
```

---

## 📚 LANGFRISTIGE PROJEKTE

### 18. Frontend-Modularisierung - Dynamisches JS-Loading
**Status:** Konzept vorhanden, nicht implementiert  
**Ziel:** Nur aktivierte Module laden JS-Dateien

**Komponenten:**
1. Backend: `/api/modules` Endpoint (Module-Status)
2. Frontend: `module-loader.js` (Zentrale Koordination)
3. Manifeste: `conf/lib-*.json` (Modul-Definitionen)

**Vorteile:**
- Keine unnötigen Downloads (deaktivierte Module)
- Keine Runtime-Fehler (fehlende APIs)
- Offline-fähig (gecachte Module)

**Siehe:** [Frontend-Modularisierung.md](Frontend-Modularisierung.md)

---

### 19. Metadata Cache-DB
**Status:** Konzept vorhanden, nicht implementiert  
**Ziel:** Lokale Metadaten-Datenbank für schnelle Suche ohne API-Calls

**Struktur:**
```
.temp/musicbrainz/
├── ronan_keating_ronan_de_2000_mercury_14tracks_9767fd7e.nfo
├── ronan_keating_ronan_de_2000_mercury_14tracks_9767fd7e-thumb.jpg
```

**Vorteile:**
- ✅ **10-40x schneller** (grep vs. API-Call)
- ✅ **API-schonend** (nur bei echten Neusuchen)
- ✅ **Offline-fähig** (Web-UI funktioniert ohne Internet)
- ✅ **Wiederverwendung** (zweite Supernatural-Disc → Instant-Results)

**Implementierungs-Phasen:**
1. Cache-Befüllung (2 Tage)
2. Cache-First-Suche (2 Tage)
3. Web-UI Integration (1 Tag)
4. Cache-Verwaltung (1 Tag)

**Siehe:** [Metadata-Cache-DB.md](Metadata-Cache-DB.md)

---

### 20. Plugin-System Architektur
**Status:** Teilweise implementiert (INI-basierte Manifeste)  
**Ziel:** Vollständige Modularität für ALLE Komponenten

**Bereits implementiert:**
- ✅ INI-basiertes Manifest-System für Module
- ✅ Einheitliche Dependency-Checks via `check_module_dependencies()`
- ✅ Modul-Selbstverwaltung (`*_SUPPORT` Flags)
- ✅ TMDB/MusicBrainz API-Konfiguration externalisiert

**Noch ausstehend:**
- ⏳ Backend-Routing Modularisierung (Flask Blueprints)
- ⏳ Frontend-Komponenten (DOM-Injection)
- ⏳ Vollständige Manifest-Dateien (`conf/lib-*.json`)

**Siehe:** [Metadata-PlugIn_Konzept.md](Metadata-PlugIn_Konzept.md)

---

## ⚠️ TEILWEISE ERLEDIGTE GITHUB ISSUES

Die folgenden Issues sind **bereits implementiert**, benötigen aber noch Tests:

### ⚠️ GitHub #5 - Audio CD - Meta Daten erfassen
**Status:** ⚠️ **TEILWEISE BEHOBEN** (18. Januar 2026)  
**Implementiert:**

- ✅ `check_audio_metadata_dependencies()` Funktion
- ✅ Runtime-Prüfung von jq, curl, eyeD3, id3v2
- ✅ User-Agent Header in MusicBrainz API-Calls (RFC-konform)
- ✅ URL-Encoding Funktion
- ✅ Cache-basierte API-Funktionen
- ✅ Artist-Sanitization für sichere Dateinamen

**Noch ausstehend:**

- ⏳ Laufzeit-Tests mit realen Audio-CDs
- ⏳ Log-Analyse bei Fehlern
- ⏳ MusicBrainz API Response prüfen

**Siehe:** [GitHub-Issues.md](GitHub-Issues.md) - Issue #5

---

### ⚠️ GitHub #7 - DVD/BD Metadaten funktioniert nicht
**Status:** ⚠️ **TEILWEISE BEHOBEN** (18. Januar 2026)  
**Implementiert:**

- ✅ `check_dvd_metadata_dependencies()` Funktion
- ✅ Runtime-Prüfung von jq, curl und TMDB_API_KEY
- ✅ User-Agent Header bei TMDB API-Calls
- ✅ Klare Fehlermeldungen bei fehlenden Dependencies
- ✅ Integration in disk2iso.sh Startup

**Noch ausstehend:**

- ⏳ TMDB_API_KEY konfigurieren und Live-Test
- ⏳ Error-Handling bei API-Fehlern verbessern
- ⏳ Log-Analyse bei Fehlern

**Siehe:** [GitHub-Issues.md](GitHub-Issues.md) - Issue #7

---

## ✅ KOMPLETT ERLEDIGTE GITHUB ISSUES

Die folgenden Issues sind **vollständig gelöst** (kein weiterer Code nötig):

### ✅ GitHub #18 - LOG oder CODE Fehler (Doppelter Slash im Pfad)
**Behoben:** 18. Januar 2026  
**Lösung:** `"${OUTPUT_DIR%/}/"` in [lib/libfolders.sh:45](../lib/libfolders.sh#L45)  
**Verifikation:** ✅ Kein doppelter Slash mehr möglich

---

### ✅ GitHub #17 - Fehlender Neustart nach Config-Änderung
**Behoben:** 18. Januar 2026  
**Lösung:** 

- `apply_config_changes()` Funktion in [lib/libconfig.sh:190-275](../lib/libconfig.sh#L190-L275)
- `perform_service_restarts()` Funktion
- Intelligente Service-Neustarts basierend auf Config-Keys

**Verifikation:** ✅ Services werden automatisch neu gestartet

---

### ✅ GitHub #16 - Passwort Feld nicht verschlüsselt
**Behoben:** 18. Januar 2026  
**Lösung:** `type="password"` in [www/templates/config.html:230](../www/templates/config.html#L230)  
**Verifikation:** ✅ Passwort-Feld ist maskiert

---

### ✅ GitHub #14 - Menü verschwindet wenn Seite länger
**Behoben:** 18. Januar 2026  
**Lösung:** Sticky Header in [www/static/css/style.css:29-31](../www/static/css/style.css#L29-L31)  
**Verifikation:** ✅ Navigation bleibt beim Scrollen sichtbar

---

## 📚 ABGESCHLOSSENE AUFGABEN (NICHT GITHUB)

Die folgenden Dateien enthalten **nur erledigte Aufgaben** und wurden archiviert:

### ✅ Logging-Konvertierung.md
**Status:** ✅ Vollständig abgeschlossen (20. Januar 2026)  
**Aufgabe:** Alle 248 `log_message` Aufrufe auf kategorisierte Logging-Funktionen umgestellt
- log_error: 58× (23%)
- log_warning: 14× (6%)
- log_info: 176× (71%)

**Ergebnis:** System läuft produktiv, keine weiteren Aufgaben

---

### ✅ Metadata-BEFORE-vs-AFTER.md
**Status:** ✅ Vollständig implementiert (19.-20. Januar 2026)  
**Aufgabe:** Metadata-Abfrage VOR Copy-Vorgang durchführen

**Implementiert:**
- ✅ Audio-CD (MusicBrainz): BEFORE Copy mit Modal, Countdown, Skip-Button
- ✅ DVD/Blu-ray (TMDB): BEFORE Copy mit Modal, Countdown, Skip-Button
- ✅ Frontend: index.js Status-Handling, Auto-Polling alle 3 Sek
- ✅ Config: `METADATA_SELECTION_TIMEOUT` (0-300 Sek, Default: 60)

**Ausstehend:** Systematische Tests mit echten Discs (Phase 4)

---

### ✅ load-order-analysis.md
**Status:** ✅ Analyse abgeschlossen und umgesetzt (26. Januar 2026)  
**Aufgabe:** Ladereihenfolge vs. Prüfreihenfolge analysieren und korrigieren

**Umgesetzt:**
- Optimale Ladereihenfolge implementiert
- Prüfreihenfolge an Ladereihenfolge angepasst
- Abhängigkeiten dokumentiert

**Keine weiteren Aufgaben**

---

### ✅ module_dependencies_analysis.md
**Status:** ✅ Analyse abgeschlossen (26. Januar 2026)  
**Aufgabe:** Modul-Abhängigkeiten dokumentieren

**Ergebnis:** 
- Abhängigkeits-Matrix erstellt
- Kritische Pfade identifiziert
- Defensive Programmierung dokumentiert

**Keine weiteren Aufgaben**

---

## 🔧 HILFS-SCRIPTS (Archiviert)

Die folgenden Dateien sind **Einmal-Tools** und können gelöscht werden:

### convert_logging.py
**Status:** Erfolgreich ausgeführt, nicht mehr benötigt  
**Zweck:** Automatische Konvertierung von log_message zu kategorisierten Funktionen  
**Ergebnis:** 248 Konvertierungen durchgeführt

### convert-logging.sh
**Status:** Nicht verwendet, wurde durch Python-Script ersetzt  
**Kann gelöscht werden**

---

## 📋 EMPFOHLENE ARBEITSREIHENFOLGE

### Sofort (diese Woche):

1. **#20 Template-Fix** ⭐ (5 Min) - Eine Zeile in index.html ändern
2. **#11 MQTT Debug** (2 Std) - Logging aktivieren, Broker-Logs prüfen
3. **#9 ISO-Anzeige** (4 Std) - Detaillierte Diagnose, Issue-Details klären
4. **#4 Metadaten nachträglich** (4 Std) - Error-Logs sammeln, Reproduzieren

### Kurzfristig (nächste 2 Wochen):

5. **#5/#7 Runtime-Tests** (4 Std) - Audio-CD + DVD/BD mit echten Discs testen
6. **Auto-Cleanup Cronjob** (1 Tag) - install.sh erweitern
7. **#15 Fehlerbehandlung** (2 Tage) - Retry-Logik implementieren
8. **#19 Archivierte Logs** (1 Tag) - Neue Route + Template
9. **#8 Ausgabeverzeichnis UI** (1 Tag) - Config-UI erweitern

### Mittelfristig (nächste 4 Wochen):

10. **#13 Service-Anzeige** (1 Tag) - Uptime, Status-Icons
11. **#12 UI-Flackern** (2 Tage) - Diff-Updates, CSS-Transitions
12. **#10 Kompaktere Anzeige** (2 Tage) - Kollapsbare Sektionen

### Langfristig (nächste 3 Monate):

13. **Frontend-Modularisierung** (1 Woche) - Dynamisches JS-Loading
14. **Metadata Cache-DB** (1 Woche) - 10-40x schneller
15. **Plugin-System Backend** (2 Wochen) - Flask Blueprints

### Features (nach Bedarf):

16. **#22 MP3 feat. Artists** (3 Tage) - MusicBrainz Artist-Credits
17. **#21 MP3 Sampler** (1 Woche) - Komplexe MusicBrainz-Logik
18. **#6 DVD Metadaten** (Details noch unklar)

---

## 📝 DATEIEN ZUM LÖSCHEN

Nach Erstellung dieser konsolidierten Übersicht können **folgende Dateien gelöscht werden**:

- ❌ `convert_logging.py` - Script wurde erfolgreich ausgeführt
- ❌ `convert-logging.sh` - Wurde nicht verwendet
- 📁 **Archivieren** (nach doc/archive/):
  - `Logging-Konvertierung.md` - Alle Aufgaben erledigt
  - `Metadata-BEFORE-vs-AFTER.md` - Implementierung abgeschlossen
  - `load-order-analysis.md` - Analyse umgesetzt
  - `module_dependencies_analysis.md` - Analyse abgeschlossen

**Behalten:**
- ✅ `ForNextRelease.md` - Enthält noch offene Features
- ✅ `Frontend-Modularisierung.md` - Konzept für zukünftiges Feature
- ✅ `GitHub-Issues.md` - Aktive Bug-Tracking-Liste
- ✅ `Metadata-Cache-DB.md` - Konzept für zukünftiges Feature
- ✅ `Metadata-PlugIn_Konzept.md` - Konzept für zukünftiges Feature
- ✅ `Ausstehende_Anpassungen.md` - Diese Datei (Master-Übersicht)

---

**Zuletzt aktualisiert:** 26. Januar 2026  
**Nächste Aktualisierung:** Nach Abschluss einer Aufgabe aus der Liste
