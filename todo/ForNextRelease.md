# Ideen für nächstes Release

**Version**: Nach 1.2.0  
**Erstellt**: Januar 2026  
**Status**: Planung/Ideen-Sammlung

---

## 1. Wartung & Automatisierung

### 🔴 HOCH: Auto-Cleanup Cronjob

**Problem:**
- Fehlgeschlagene Operationen hinterlassen Temp-Ordner in `/media/iso/.temp/`
- Cover-Cache wächst unbegrenzt in `/opt/disk2iso/.temp/`
- Alte Logs füllen Festplatte

**Lösung:**
Cronjob `/etc/cron.daily/disk2iso-cleanup` erstellen:

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

**Aufwand:** Niedrig  
**Impact:** Hoch - Verhindert vollgelaufene Festplatten

---

## 2. Benutzerfreundlichkeit

### 🟢 NIEDRIG: Metadaten-Edit-Wrapper für normale User

**Problem:**
- ISOs/Metadaten gehören root:root
- User können `.nfo` und Cover-JPG nicht direkt bearbeiten
- Workaround: `sudo nano` oder Web-UI

**Lösung:**
Helper-Script `/usr/local/bin/disk2iso-edit`:

```bash
#!/bin/bash
# Wrapper für Metadaten-Bearbeitung
# User kann ohne sudo Metadaten ändern

case "$1" in
    nfo)
        sudo -u root nano "$2"
        ;;
    cover)
        sudo -u root cp "$2" "$3"
        ;;
    *)
        echo "Usage: disk2iso-edit nfo <file.nfo>"
        echo "       disk2iso-edit cover <source.jpg> <target.jpg>"
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

## 3. Performance-Optimierungen

### 🟢 NIEDRIG: ISO-Scanning-Caching

**Problem:**
- `/api/archive` scannt bei jedem Request alle ISOs neu
- Kann bei vielen ISOs langsam werden

**Lösung:**
```python
# Cache ISO-Liste für 60 Sekunden
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

**Aufwand:** Niedrig  
**Impact:** Niedrig - Nur bei vielen ISOs merkbar

---

## 4. Neue Features (Optional)

### 🟢 NIEDRIG: Audio-CD Normalization

**Idee:**
MP3-Lautstärke normalisieren mit ReplayGain

```bash
# Nach MP3-Konvertierung in lib-cd.sh
if command -v mp3gain &>/dev/null; then
    log_message "INFO" "Normalisiere Lautstärke mit mp3gain..."
    mp3gain -r -k "$temp_dir"/*.mp3 2>&1 | tee -a "$LOGFILE"
fi
```

**Voraussetzung:** `mp3gain` installieren  
**Aufwand:** Niedrig  
**Impact:** Niedrig - Quality-of-Life

---

### 🟢 NIEDRIG: Email-Benachrichtigungen

**Idee:**
Email bei Operation-Ende (Erfolg/Fehler)

**Config:**
```bash
# In config.sh
NOTIFY_EMAIL=""  # Leer = deaktiviert
```

**Implementation:**
```bash
# In lib-common.sh
send_notification() {
    local status=$1
    local disc_label=$2
    
    if [[ -n "$NOTIFY_EMAIL" ]]; then
        echo "Disc: $disc_label - Status: $status" | \
            mail -s "[disk2iso] Operation $status" "$NOTIFY_EMAIL"
    fi
}
```

**Aufwand:** Niedrig  
**Impact:** Niedrig - Für unbeaufsichtigte Systeme

---

## 5. Testing & Qualität

### 🟢 NIEDRIG: validate_deployment.sh erweitern

**Aktuell:**
- Deployment-Validierung vorhanden

**Erweiterungen:**
- JSON-Syntax-Checks (jq validation)
- Permission-Checks (777 korrekt?)
- Bash-Syntax mit shellcheck
- Python-Linting mit ruff/pylint

**Aufwand:** Mittel  
**Impact:** Niedrig - Entwickler-Tool

---

## Priorisierung für nächstes Release

### Must-Have (Version 1.3.0)
1. ⚠️ Auto-Cleanup Cronjob (noch nicht implementiert)

### Nice-to-Have
2. 💡 Metadaten-Edit-Wrapper
3. 💡 Email-Benachrichtigungen
4. 💡 Audio-Normalization
5. 💡 ISO-Scanning-Cache
6. 💡 validate_deployment erweitern

---

## Bereits in v1.2.0 implementiert ✅

Die folgenden Punkte waren ursprünglich für v1.3.0 geplant, sind aber **bereits implementiert**:

### ✅ Disk-Space-Check
- **Status**: Implementiert in [lib-systeminfo.sh](../lib/lib-systeminfo.sh#L115)
- **Funktion**: `check_disk_space(required_mb)`
- **Verwendet von**: DVD/Blu-ray/CD-Ripping (vor Operation)
- **Features**:
  - Prüft verfügbaren Speicherplatz mit `df -BM`
  - Berechnet benötigten Platz (ISO-Größe + 5% Puffer)
  - Bricht Operation ab wenn zu wenig Platz
  - Loggt Warnung/Fehler

### ✅ Fehlende Übersetzungen (ES/FR)
- **Status**: Ergänzt in v1.2.0
- **Dateien**: [lib-web.es](../lang/lib-web.es), [lib-web.fr](../lang/lib-web.fr)
- **Ergänzt**: 12 Konstanten (ES), 14 Konstanten (FR)
- **Vollständigkeit**: 100% für alle 4 Sprachen (DE/EN/ES/FR)

### ✅ Code-Dokumentation 777-Permissions
- **Status**: Dokumentiert in v1.2.0
- **Datei**: [lib-folders.sh](../lib/lib-folders.sh)
- **Funktionen**: `get_log_folder()`, `get_temp_pathname()`
- **Dokumentiert**:
  - Grund für 777 Permissions (Multi-User CLI-Zugriff)
  - Alternativen (Group-Management)
  - Security-Bewertung (OK für Trusted Environment)

---

## Nicht geplant / Abgelehnt

### ❌ Dedizierter disk2iso User mit Group-Management

**Begründung:**
- Aktuelles System (root + 777) funktioniert einwandfrei
- Breaking Change für alle Installationen
- Höherer Setup-Aufwand ohne echten Mehrwert
- Nur sinnvoll für Corporate/Multi-User (nicht Ziel-Usecase)

**Dokumentiert in:** `ORDNER-STRUKTUR-ANALYSE.md` (archiviert nach 1.2.0)

---

### ❌ Weitere Python-zu-Bash Migration

**Begründung:**
- Nach Phase 1-3 ist optimale Architektur erreicht
- requests-Library eliminiert ✅
- Verbleibende Python-Logik minimal und sinnvoll:
  - `/api/system`: psutil effizienter als Bash
  - File-Serving: Flask send_file() korrekte Wahl
  - JSON-I/O: Legitime API-Layer-Aufgabe

**Dokumentiert in:** `PYTHON-API-AUFGABEN-NACH-REFACTORING.md` (archiviert nach 1.2.0)

---

## Archivierte Analysen (nach 1.2.0)

Folgende Analyse-Dokumente wurden nach Release 1.2.0 archiviert, da die Erkenntnisse in diesem Dokument oder im Code eingeflossen sind:

- `ORDNER-STRUKTUR-ANALYSE.md` - Erkenntnisse in Code-Kommentare eingeflossen
- `PYTHON-API-AUFGABEN-NACH-REFACTORING.md` - Refactoring abgeschlossen
- `AUDIO-CD-MODAL-FIX.md` - Fix bereits in 1.2.0 implementiert
- `MQTT-AUDIO-UNIT-FIX.md` - Fix bereits in 1.2.0 implementiert
- `REFACTORING-TMDB-TO-BASH.md` - Phase 1-3 vollständig umgesetzt
- `CODE-ANALYSIS-REPORT.md` - Einmalige Analyse, nicht mehr relevant
- `CODE-CHECK-REPORT.md` - Einmalige Analyse, nicht mehr relevant
- `WEB-INTERFACE-REVIEW-REPORT.md` - Einmalige Analyse, nicht mehr relevant
- `LANGUAGE-SYSTEM-ANALYSIS.md` - Übersetzungs-Todos in Abschnitt 2 extrahiert

---

**Zuletzt aktualisiert:** 13. Januar 2026
