# GitHub Issues - disk2iso v1.2.0
**Stand:** 15.01.2026  
**Quelle:** https://github.com/DirkGoetze/disk2iso/issues  
**Status:** 19 Open, 1 Closed

---

## 📊 ÜBERSICHT NACH KATEGORIEN

### 🎵 AUDIO-CD / MP3 TAGGING (lib-cd.sh, lib-cd-metadata.sh)
- [#22](https://github.com/DirkGoetze/disk2iso/issues/22) - Taggen von MP3 bei mehreren Interpreten (enhancement)
- [#21](https://github.com/DirkGoetze/disk2iso/issues/21) - Taggen von MP3 bei Samplern (enhancement)
- [#5](https://github.com/DirkGoetze/disk2iso/issues/5) - Audio CD - Meta Daten erfassen (bug)

### 📀 DVD/BLU-RAY METADATEN (lib-dvd.sh, lib-bluray.sh, lib-dvd-metadata.sh)
- [#7](https://github.com/DirkGoetze/disk2iso/issues/7) - DVD/BD Metadaten funktioniert nicht (bug)
- [#6](https://github.com/DirkGoetze/disk2iso/issues/6) - DVD Metadaten (feat)
- [#4](https://github.com/DirkGoetze/disk2iso/issues/4) - Archiv - Metadaten hinzufügen funktioniert nicht (bug)

### 🌐 WEB-UI INTERFACE (www/app.py, www/templates/, www/static/)
- [#20](https://github.com/DirkGoetze/disk2iso/issues/20) - Formatierungsproblem Fortschritt
- [#19](https://github.com/DirkGoetze/disk2iso/issues/19) - Archivierte Logs über WEB-UI öffnen
- [#16](https://github.com/DirkGoetze/disk2iso/issues/16) - Passwort Feld nicht verschlüsselt (bug)
- [#14](https://github.com/DirkGoetze/disk2iso/issues/14) - Menü verschwindet wenn Seite länger (feat)
- [#13](https://github.com/DirkGoetze/disk2iso/issues/13) - Anzeige zum Service (enhancement)
- [#12](https://github.com/DirkGoetze/disk2iso/issues/12) - Home Seite unruhig (enhancement)
- [#10](https://github.com/DirkGoetze/disk2iso/issues/10) - Feat. Anzeige kompakter machen (feat)
- [#9](https://github.com/DirkGoetze/disk2iso/issues/9) - Anzeige von ISO Dateien (bug)
- [#8](https://github.com/DirkGoetze/disk2iso/issues/8) - Einstellungen Ausgabeverzeichnis (feat)

### 🐛 SYSTEM / SERVICE (disk2iso.sh, lib-common.sh)
- [#18](https://github.com/DirkGoetze/disk2iso/issues/18) - LOG oder CODE Fehler (Doppelter Slash im Pfad)
- [#17](https://github.com/DirkGoetze/disk2iso/issues/17) - Fehlender Neustart (bug/feat)
- [#15](https://github.com/DirkGoetze/disk2iso/issues/15) - Fehlgeschlagene Kopiervorgänge (feat)

### 📡 MQTT INTEGRATION (lib-mqtt.sh)
- [#11](https://github.com/DirkGoetze/disk2iso/issues/11) - MQTT Meldungen kommen doppelt (bug)

---

## 🔥 KRITISCH - BUGS (Priorität: HOCH)

### #18 - LOG oder CODE Fehler ❌ BUG
**Bereich:** lib-folders.sh / lib-common.sh  
**Beschreibung:**  
Doppelter Slash im Ausgabepfad:
```
/mnt/pve/Public/images//dvd/supernatural_season_12_disc_3.iso
                      ^^
```
**Ursache:** Wahrscheinlich `OUTPUT_DIR` endet bereits mit `/` oder Pfad-Verkettung falsch  
**Betroffene Dateien:**
- `lib/lib-folders.sh` - Funktion `get_output_dir_for_type()`
- `lib/lib-common.sh` - Pfad-Konstruktion

**Lösung:** Prüfe alle `"${OUTPUT_DIR}/"` → sollte `"${OUTPUT_DIR%/}/"` sein

---

### #16 - Passwort Feld nicht verschlüsselt ❌ BUG
**Bereich:** www/templates/config.html  
**Beschreibung:**  
MQTT-Passwort wird als Klartext angezeigt statt als `<input type="password">`

**Betroffene Dateien:**
- `www/templates/config.html` - MQTT Password Feld

**Lösung:**
```html
<input type="password" id="mqtt_password" name="mqtt_password" 
       value="{{ config.mqtt_password }}" autocomplete="new-password">
```

---

### #11 - MQTT Meldungen kommen doppelt ❌ BUG
**Bereich:** lib-mqtt.sh  
**Beschreibung:**  
MQTT-Nachrichten werden doppelt gesendet

**Mögliche Ursachen:**
- `publish_mqtt()` wird zweimal aufgerufen
- Mehrere MQTT-Clients aktiv
- Retain-Flag verursacht Echo

**Betroffene Dateien:**
- `lib/lib-mqtt.sh`
- Alle Stellen die `publish_mqtt()` aufrufen

**Diagnose nötig:** Logging aktivieren, MQTT-Broker Logs prüfen

---

### #9 - Anzeige von ISO Dateien ❌ BUG
**Bereich:** www/app.py / www/templates/archive.html  
**Beschreibung:**  
ISO-Dateien werden nicht korrekt angezeigt im Archiv

**Betroffene Dateien:**
- `www/app.py` - `/archive` Route
- `www/templates/archive.html`
- Möglicherweise `get_iso_files_by_type()` Funktion

**Diagnose nötig:** Detaillierte Beschreibung was nicht funktioniert

---

### #7 - DVD/BD Metadaten funktioniert nicht ❌ BUG
**Bereich:** lib-dvd-metadata.sh  
**Beschreibung:**  
TMDB-Metadaten-Abruf für DVDs/Blu-rays funktioniert nicht

**Betroffene Dateien:**
- `lib/lib-dvd-metadata.sh`
- TMDB API Integration

**Mögliche Ursachen:**
- API-Key fehlt/ungültig
- Netzwerk-Problem
- API-Antwort-Format geändert

**Diagnose nötig:** Error-Logs, TMDB API Response prüfen

---

### #5 - Audio CD - Meta Daten erfassen ❌ BUG
**Bereich:** lib-cd-metadata.sh  
**Beschreibung:**  
MusicBrainz-Metadaten für Audio-CDs werden nicht korrekt abgerufen

**Betroffene Dateien:**
- `lib/lib-cd-metadata.sh`
- MusicBrainz API Integration

**Diagnose nötig:** Error-Logs, MusicBrainz Response prüfen

---

### #4 - Archiv - Metadaten hinzufügen funktioniert nicht ❌ BUG
**Bereich:** www/app.py - Archiv-Management  
**Beschreibung:**  
Nachträgliches Hinzufügen von Metadaten über Web-UI schlägt fehl

**Betroffene Dateien:**
- `www/app.py` - Metadata-Update Endpoints
- `www/templates/archive.html`

**Diagnose nötig:** Detaillierte Beschreibung, Error-Logs

---

## ⚡ WICHTIG - SERVICE / SYSTEM

### #17 - Fehlender Neustart ❌ BUG + ✨ FEATURE
**Bereich:** www/app.py - Config-Management  
**Beschreibung:**  
Nach Speichern der Einstellungen wird Service nicht automatisch neu gestartet

**Betroffene Dateien:**
- `www/app.py` - `/api/config` POST Route
- Zeile ~800: Service-Neustart fehlt

**Lösung:**
```python
# Nach erfolgreichem Config-Update:
subprocess.run(['sudo', 'systemctl', 'restart', 'disk2iso'], check=False)
```

**Hinweis:** Sudoers-Eintrag nötig für passwortlosen Neustart!

---

### #15 - Fehlgeschlagene Kopiervorgänge ✨ FEATURE
**Bereich:** lib-common.sh / disk2iso.sh  
**Beschreibung:**  
Bessere Behandlung fehlgeschlagener Kopiervorgänge
- Wiederholungsversuche
- Fehler-Logging
- Benachrichtigung via MQTT

**Betroffene Dateien:**
- `lib/lib-common.sh` - Copy-Funktionen
- `disk2iso.sh` - State-Machine
- `lib/lib-mqtt.sh` - Error-Notifications

**Enhancement:** Robustness-Verbesserungen

---

## 🎨 UI/UX VERBESSERUNGEN

### #20 - Formatierungsproblem Fortschritt 🎨 UI-BUG
**Bereich:** www/static/js/index.js + www/static/css/style.css  
**Beschreibung:**  
Fortschrittsbalken Speicherplatz zeigt falsche Richtung:
- Aktuell: Balken wird kleiner bei mehr Belegung (falsch)
- Soll: Balken wächst von links nach rechts mit Belegung
- Farbe: Grün (0%) → Gelb (50%) → Rot (100%)
- Anzeige: 5294.85 GB / 11081.08 GB (korrekt)
- Prozent: Korrekt, aber Balken falsch

**Betroffene Dateien:**
- `www/static/js/index.js` - Disk-Space Berechnung
- `www/static/css/style.css` - Progress-Bar Styling

**Lösung:**  
Verwendet-% statt Frei-% für Balkenlänge

---

### #19 - Archivierte Logs über WEB-UI öffnen ✨ FEATURE
**Bereich:** www/app.py + www/templates/logs.html  
**Beschreibung:**  
Archivierte Logs können gesucht, aber nicht angezeigt werden

**Betroffene Dateien:**
- `www/app.py` - Neue Route `/logs/view/<filename>`
- `www/templates/logs.html` - Link zu archivierten Logs

**Lösung:**  
Endpoint zum Anzeigen archivierter Log-Dateien

---

### #14 - Menü verschwindet wenn Seite länger ✨ FEATURE
**Bereich:** www/templates/base.html + www/static/css/style.css  
**Beschreibung:**  
Sticky-Navigation fehlt - Menü scrollt weg bei langen Seiten

**Betroffene Dateien:**
- `www/templates/base.html` - Navigation
- `www/static/css/style.css` - Sticky Header

**Lösung:**
```css
header {
    position: sticky;
    top: 0;
    z-index: 1000;
}
```

---

### #13 - Anzeige zum Service ✨ ENHANCEMENT
**Bereich:** www/templates/index.html  
**Beschreibung:**  
Bessere Visualisierung des Service-Status

**Ideen:**
- Service läuft seit: Uptime
- Letzte Aktivität: Zeitstempel
- Status-Icon: Grün/Gelb/Rot

**Betroffene Dateien:**
- `www/app.py` - `/api/status` erweitern
- `www/templates/index.html`

---

### #12 - Home Seite unruhig ✨ ENHANCEMENT
**Bereich:** www/static/js/index.js  
**Beschreibung:**  
AJAX-Polling verursacht flackernde UI-Updates

**Lösung:**
- Diff-basierte Updates (nur Änderungen)
- CSS-Transitions für sanfte Übergänge
- Debouncing

**Betroffene Dateien:**
- `www/static/js/index.js` - `updateStatus()`

---

### #10 - Feat. Anzeige kompakter machen ✨ FEATURE
**Bereich:** www/templates/ + www/static/css/style.css  
**Beschreibung:**  
UI optimieren für weniger Scrolling

**Ideen:**
- Kollapsbare Sektionen
- Kompaktere Layouts
- Responsive Design verbessern

---

### #8 - Einstellungen Ausgabeverzeichnis ✨ FEATURE
**Bereich:** www/templates/config.html + www/app.py  
**Beschreibung:**  
Ausgabeverzeichnis in Web-UI änderbar machen

**Betroffene Dateien:**
- `www/templates/config.html` - Input für `DEFAULT_OUTPUT_DIR`
- `www/app.py` - `/api/config` POST erweitern
- `lib/lib-config.sh` - `update_config_value()` nutzen

**Hinweis:** Validierung ob Pfad existiert & beschreibbar!

---

## 🎵 AUDIO-CD ENHANCEMENTS

### #22 - Taggen von MP3 bei mehreren Interpreten ✨ ENHANCEMENT
**Bereich:** lib-cd-metadata.sh  
**Beschreibung:**  
Besseres Tagging bei "feat." Artists:
```
Titel: "Driving Home for Christmas"
Artist: "Chris Rea feat. XYZ"

Soll werden:
- Album: Original Album von Chris Rea
- AlbumArtist: Chris Rea
- Title: Driving Home for Christmas
- Artist: Chris Rea feat. XYZ

Ordnerstruktur: /Chris Rea/Album/Track.mp3
```

**Betroffene Dateien:**
- `lib/lib-cd-metadata.sh` - Tag-Logik
- MusicBrainz API - Artist-Parsing

**Komplexität:** Mittel - MusicBrainz Artist-Credits nutzen

---

### #21 - Taggen von MP3 bei Samplern ✨ ENHANCEMENT
**Bereich:** lib-cd-metadata.sh  
**Beschreibung:**  
Sampler mit "AlbumArtist: Various Artists" besser handhaben:
```
Aktuell (schlecht):
/Various Artists/Rock Christmas/01 - Driving Home.mp3
/Various Artists/Rock Christmas/02 - Last Christmas.mp3

Soll werden:
/Chris Rea/Original Album/01 - Driving Home.mp3
/Wham!/Original Album/02 - Last Christmas.mp3
```

**Logik:**
1. Erkenne `AlbumArtist == "Various Artists"`
2. Für jeden Track: Suche Original-Album des Künstlers
3. Erstelle Ordner: `/Artist/OriginalAlbum/Track.mp3`
4. Generiere Album-Cover pro Artist-Album
5. Tags: AlbumArtist = Artist, Album = OriginalAlbum

**Betroffene Dateien:**
- `lib/lib-cd-metadata.sh`
- `lib/lib-folders.sh` - Mehrere Ordner pro CD
- MusicBrainz API - Recording-Lookup

**Komplexität:** HOCH - Erfordert zusätzliche API-Calls pro Track

---

## 📋 PRIORITÄTEN-EMPFEHLUNG

### 🔴 KRITISCH (Sofort)
1. **#18** - Doppelter Slash im Pfad (Daten-Integrität)
2. **#16** - Passwort-Feld Klartext (Sicherheit)
3. **#11** - MQTT doppelte Meldungen (Funktionalität)

### 🟡 HOCH (Bald)
4. **#17** - Service-Neustart nach Config-Änderung
5. **#20** - Fortschrittsbalken Formatierung (UX)
6. **#7** - DVD/BD Metadaten funktionieren nicht
7. **#5** - Audio-CD Metadaten funktionieren nicht

### 🟢 MITTEL (Geplant)
8. **#14** - Sticky Navigation
9. **#19** - Archivierte Logs anzeigen
10. **#15** - Fehlerbehandlung verbessern
11. **#8** - Ausgabeverzeichnis über UI ändern

### 🔵 NIEDRIG (Nice-to-have)
12. **#13** - Service-Anzeige verbessern
13. **#12** - UI-Flackern reduzieren
14. **#10** - Kompaktere Anzeige
15. **#9** - ISO-Dateien Anzeige-Bug (Details unklar)
16. **#4** - Metadaten nachträglich hinzufügen

### 🎨 ENHANCEMENTS (Features)
17. **#22** - MP3-Tagging feat. Artists (Komplex)
18. **#21** - MP3-Tagging Sampler (Sehr komplex)
19. **#6** - DVD Metadaten (Details unklar)

---

## 📝 HINWEISE FÜR BEARBEITUNG

- **Bugs zuerst!** Funktionalität > Features
- **Sicherheit:** #16 hat Priorität (Passwort-Leak)
- **Datenintegrität:** #18 kann zu falschen Pfaden führen
- **Komplexe Features (#21, #22):** Erfordern MusicBrainz-Expertise
- **Viele UI-Issues:** Könnten gebündelt in einem "UI-Polish" Sprint bearbeitet werden

**Empfohlene Reihenfolge:** #18 → #16 → #11 → #17 → #20 → #7 → #5
