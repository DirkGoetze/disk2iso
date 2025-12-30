# Sprachsystem-Analyse für disk2iso

**Datum:** 30.12.2025  
**Status:** Modulare Sprachdateien erstellt, aber NICHT verwendet

---

## 🔴 Problem 1: Keine Verwendung der Sprachkonstanten

**Befund:** ALLE Meldungen im Code sind hardcodiert. Die definierten `MSG_*` Konstanten werden NIRGENDS verwendet.

### Beispiele hardcodierter Meldungen:

#### lib-common.sh
```bash
# Hardcodiert:
log_message "INFO: Optionale Tools für bessere Performance: ${optional_missing[*]}"

# Sollte sein:
log_message "$MSG_OPTIONAL_TOOLS_INFO: ${optional_missing[*]}"
```

#### lib-cd.sh
```bash
# Hardcodiert:
log_message "Audio-CD Support verfügbar: cdparanoia + lame + genisoimage"

# Sollte sein:
log_message "$MSG_AUDIO_SUPPORT_AVAILABLE"
```

#### lib-dvd.sh
```bash
# Hardcodiert:
log_message "Video-DVD/BD Support verfügbar mit: ${available_methods[*]}"

# Sollte sein:
log_message "$MSG_DVD_SUPPORT_AVAILABLE: ${available_methods[*]}"
```

#### lib-bluray.sh
```bash
# Hardcodiert:
log_message "Blu-ray Support verfügbar mit: ${available_methods[*]}"

# Sollte sein:
log_message "$MSG_BLURAY_SUPPORT_AVAILABLE: ${available_methods[*]}"
```

---

## 📊 Statistik

- **Hardcodierte Meldungen gefunden:** >120
- **Definierte MSG_ Konstanten:** 40
- **Verwendete MSG_ Konstanten:** 0 ❌
- **Module betroffen:** Alle (lib-common.sh, lib-cd.sh, lib-dvd.sh, lib-bluray.sh)

---

## ✅ Problem 2: Fehlende Konstanten für häufige Meldungen

Viele wiederkehrende Meldungsmuster haben KEINE Konstanten:

### Häufige Muster ohne Konstanten:

1. **Dependency-Checks:**
   - `"Support verfügbar mit: ..."`
   - `"NICHT verfügbar - fehlende Tools: ..."`
   - `"Installation: apt-get install ..."`

2. **Methoden-Auswahl:**
   - `"Methode: ddrescue (robust)"`
   - `"Methode: dvdbackup (entschlüsselt)"`
   - `"Methode: MakeMKV (entschlüsselt)"`

3. **Erfolgs-/Fehlermeldungen:**
   - `"✓ ... erfolgreich kopiert"`
   - `"FEHLER: ... fehlgeschlagen"`
   - `"WARNUNG: ..."`

4. **Fortschritts-Meldungen:**
   - `"Fortschritt: XX MB von YY MB (ZZ%)"`
   - `"Erstelle ISO: ..."`
   - `"Erstelle MD5-Checksumme..."`

---

## 🔄 Problem 3: Doppelte/ähnliche Meldungen

### Identische Meldungen in verschiedenen Modulen:

**1. "FEHLER: ... fehlgeschlagen"**
- lib-common.sh: `"FEHLER: ddrescue fehlgeschlagen"` (2x)
- lib-dvd.sh: `"FEHLER: dvdbackup fehlgeschlagen"`, `"FEHLER: genisoimage fehlgeschlagen"` (2x)
- lib-bluray.sh: `"FEHLER: ddrescue fehlgeschlagen"` (2x), `"FEHLER: MakeMKV Backup fehlgeschlagen"`
- lib-cd.sh: `"FEHLER: ISO-Erstellung fehlgeschlagen"`, `"FEHLER: MP3-Encoding ... fehlgeschlagen"`

**Empfehlung:** Gemeinsame Konstante + Parameter
```bash
readonly MSG_ERROR_FAILED="FEHLER: %s fehlgeschlagen"
# Verwendung:
log_message "$(printf "$MSG_ERROR_FAILED" "ddrescue")"
```

**2. "✓ ... erfolgreich ..."**
- lib-common.sh: `"✓ Daten-Disc mit ddrescue erfolgreich kopiert"` (2x)
- lib-dvd.sh: `"✓ Video-DVD mit ddrescue erfolgreich kopiert"` (2x)
- lib-bluray.sh: `"✓ Blu-ray mit ddrescue erfolgreich kopiert"` (2x)

**Empfehlung:** Template-Konstante
```bash
readonly MSG_SUCCESS_COPIED="✓ %s erfolgreich kopiert"
```

**3. ISO-Volume erkannt**
- lib-common.sh: `"ISO-Volume erkannt: ... Blöcke"` (2x)
- lib-dvd.sh: `"ISO-Volume erkannt: ... Blöcke"`
- lib-bluray.sh: `"ISO-Volume erkannt: ... Blöcke"`

**Empfehlung:** Gemeinsame Konstante in lib-common.de

**4. Fortschritts-Meldungen**
- lib-dvd.sh: `"Fortschritt: ${copied_mb} MB von ${dvd_size_mb} MB (${percent}%)"`
- lib-bluray.sh: `"MakeMKV Fortschritt: ${copied_mb} MB von ${total_size_mb} MB (${percent}%)"`
- lib-common.sh: `"Fortschritt: ${current_mb} MB / ${total_mb} MB (${percent}%)"`

**Empfehlung:** Vereinheitlichen
```bash
readonly MSG_PROGRESS_WITH_TOTAL="Fortschritt: %s MB von %s MB (%s%%)"
readonly MSG_PROGRESS_WITHOUT_TOTAL="Fortschritt: %s MB kopiert"
```

---

## 🗑️ Problem 4: Ungenutzte Konstanten

Diese definierten MSG_ Konstanten werden NICHT im Code verwendet:

### lib-common.de (nicht verwendet):
- `MSG_STARTUP` ❌
- `MSG_SEARCH_DRIVE` ❌
- `MSG_DRIVE_FOUND` ❌
- `MSG_DRIVE_NOT_FOUND` ❌
- `MSG_DRIVE_NOT_AVAILABLE` ❌
- `MSG_DRIVE_USB_TIP` ❌
- `MSG_DEPS_CRITICAL_MISSING` ❌
- `MSG_DEPS_INSTALL_HINT` ❌
- `MSG_DEPS_OPTIONAL_MISSING` ❌
- `MSG_DEPS_OPTIONAL_HINT` ❌
- `MSG_STEP_1` bis `MSG_STEP_7` ❌ (alle)
- `MSG_COPY_START` ❌
- `MSG_COPY_LABEL` ❌
- `MSG_COPY_TARGET` ❌
- `MSG_COPY_SUCCESS` ❌
- `MSG_COPY_FAILED` ❌
- `MSG_COPY_COMPLETE` ❌
- `MSG_COPY_ERROR` ❌
- `MSG_MODULE_DATA` ❌
- `MSG_MD5_CREATED` ❌
- `MSG_CLEANUP_SUCCESS` ❌
- `MSG_CLEANUP_FAILURE` ❌
- `MSG_CLEANUP_INTERRUPTED` ❌
- `MSG_SERVICE_SHUTDOWN` ❌
- `MSG_SERVICE_EXIT` ❌

### lib-cd.de (nicht verwendet):
- `MSG_MODULE_AUDIO` ❌
- `MSG_DETECTED_TYPE_AUDIO` ❌
- `MSG_NOTIFY_AUDIO_SUCCESS` ❌
- `MSG_NOTIFY_TITLE` ❌

### lib-dvd.de (nicht verwendet):
- `MSG_MODULE_VIDEO_DVD` ❌
- `MSG_DETECTED_TYPE_DVD` ❌

### lib-bluray.de (nicht verwendet):
- `MSG_MODULE_VIDEO_BLURAY` ❌
- `MSG_DETECTED_TYPE_BLURAY` ❌

**Gesamt: 40 von 40 Konstanten werden NICHT verwendet!** 😱

---

## 💡 Empfehlungen

### Phase 1: Kritische Meldungen (Sofort)
Ersetze die häufigsten/wichtigsten hardcodierten Meldungen:

1. **Dependency-Check Meldungen** (alle Module)
2. **Fehler-/Erfolgs-Meldungen** (alle Module)
3. **Methoden-Auswahl** (alle Module)

### Phase 2: Erweiterte Meldungen (Optional)
Ersetze alle verbleibenden hardcodierten Meldungen

### Phase 3: Bereinigung
Entferne ungenutzte MSG_ Konstanten oder implementiere sie im Code

---

## 📝 Implementierungs-Vorschlag

### 1. Erweitere Sprachdateien mit fehlenden Konstanten

**lib-common.de:**
```bash
# Dependency-Checks
readonly MSG_OPTIONAL_TOOLS_INFO="INFO: Optionale Tools für bessere Performance:"
readonly MSG_INSTALL_COMMAND="Installation: apt-get install %s"

# Methoden
readonly MSG_METHOD_DDRESCUE="Methode: ddrescue (robust)"
readonly MSG_METHOD_DD="Methode: dd (Standard)"

# Fortschritt
readonly MSG_PROGRESS_WITH_TOTAL="Fortschritt: %s MB von %s MB (%s%%)"
readonly MSG_ISO_VOLUME_DETECTED="ISO-Volume erkannt: %s Blöcke (%s MB)"

# Erfolg/Fehler
readonly MSG_SUCCESS_COPIED="✓ %s erfolgreich kopiert"
readonly MSG_ERROR_FAILED="FEHLER: %s fehlgeschlagen"
readonly MSG_COPYING_COMPLETE_DISC="Kopiere komplette Disc (kein isoinfo verfügbar)"

# Speicherplatz
readonly MSG_DISK_SPACE_CHECK="Speicherplatz: %s MB verfügbar, %s MB benötigt"
readonly MSG_DISK_SPACE_ERROR="FEHLER: Nicht genug Speicherplatz! Benötigt: %s MB, Verfügbar: %s MB"
```

**lib-cd.de:**
```bash
# Dependency-Check
readonly MSG_AUDIO_SUPPORT_AVAILABLE="Audio-CD Support verfügbar: cdparanoia + lame + genisoimage"
readonly MSG_AUDIO_SUPPORT_NOT_AVAILABLE="Audio-CD Support NICHT verfügbar - fehlende Tools:"
readonly MSG_AUDIO_OPTIONAL_LIMITED="Audio-CD: Optionale Features eingeschränkt - fehlende Tools:"

# Ripping-Prozess
readonly MSG_RIPPING_START="Starte Audio-CD Ripping..."
readonly MSG_RIPPING_TRACK="Rippe Track %s von %s..."
readonly MSG_ENCODING_TRACK="Kodiere Track %s zu MP3: %s"
readonly MSG_RIPPING_COMPLETE="Ripping abgeschlossen - erstelle ISO..."

# MusicBrainz
readonly MSG_MUSICBRAINZ_QUERY="Frage MusicBrainz-Datenbank ab..."
readonly MSG_MUSICBRAINZ_NOT_FOUND="WARNUNG: Keine MusicBrainz-Einträge gefunden für Disc-ID:"
readonly MSG_ALBUM="Album:"
readonly MSG_ARTIST="Künstler:"
readonly MSG_YEAR="Jahr:"
```

### 2. Ersetze hardcodierte Strings im Code

**Beispiel lib-common.sh:**
```bash
# Vorher:
log_message "INFO: Optionale Tools für bessere Performance: ${optional_missing[*]}"

# Nachher:
log_message "$MSG_OPTIONAL_TOOLS_INFO ${optional_missing[*]}"
```

**Beispiel lib-cd.sh:**
```bash
# Vorher:
log_message "Audio-CD Support verfügbar: cdparanoia + lame + genisoimage"

# Nachher:
log_message "$MSG_AUDIO_SUPPORT_AVAILABLE"
```

### 3. Nutze printf für parametrisierte Meldungen

```bash
# Vorher:
log_message "FEHLER: ddrescue fehlgeschlagen"

# Nachher:
log_message "$(printf "$MSG_ERROR_FAILED" "ddrescue")"
```

---

## 🎯 Nächste Schritte

1. ✅ **Sprachsystem ist implementiert** (Infrastruktur vorhanden)
2. ❌ **Code verwendet Sprachsystem NICHT** → Hauptaufgabe!
3. ⚠️ **Viele Konstanten fehlen** → Erweitern
4. ⚠️ **Definierte Konstanten ungenutzt** → Implementieren oder entfernen

**Empfehlung:** Schrittweise Migration
- Start mit einem Modul (z.B. lib-common.sh)
- Alle hardcodierten Strings durch MSG_ ersetzen
- Fehlende Konstanten ergänzen
- Testen
- Nächstes Modul

---

## 📈 Aufwand-Schätzung

- **Konstanten ergänzen:** ~50 neue MSG_ Konstanten
- **Code anpassen:** ~120 log_message() Aufrufe
- **Testing:** Alle Module durchlaufen
- **Gesamt-Aufwand:** 4-6 Stunden

