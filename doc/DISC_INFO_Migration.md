# DISC_INFO/DISC_DATA Migration - Status

**Datum:** 28. Januar 2026  
**Ziel:** Eliminierung globaler Variablen durch DISC_INFO/DISC_DATA Arrays

---

## ✅ Phase 1: Setter-Funktionen (ABGESCHLOSSEN)

### **Erstellt in libdiskinfos.sh:**

| Funktion | Zweck | Status |
|----------|-------|--------|
| `discinfo_init()` | Initialisiere/Leere alle DISC_INFO Felder | ✅ |
| `discinfo_set_type(type)` | Setze Disc-Typ mit Validierung | ✅ |
| `discinfo_set_label(label)` | Setze Label mit Normalisierung | ✅ |
| `discinfo_set_size(sectors, block_size)` | Setze Größe (auto-berechnet MB) | ✅ |
| `discinfo_set_filesystem(fs)` | Setze Dateisystem-Typ | ✅ |
| `discinfo_set_id(id)` | Setze Disc-ID | ✅ |

### **Erstellt in libdiskinfos.sh (Getter):**

| Funktion | Zweck | Status |
|----------|-------|--------|
| `discinfo_get_type()` | Lese Disc-Typ | ✅ |
| `discinfo_get_label()` | Lese Disc-Label | ✅ |
| `discinfo_get_size_mb()` | Lese Größe in MB | ✅ |
| `discinfo_get_size_sectors()` | Lese Größe in Sektoren | ✅ |

---

## ✅ Phase 2: Anpassung bestehender Funktionen

### **Angepasste Setter-Verwendungen:**

| Datei | Funktion | Zeile | Änderung | Status |
|-------|----------|-------|----------|--------|
| libdiskinfos.sh | `detect_disc_type()` | 149-410 | 15x `disc_type=` → `discinfo_set_type()` | ✅ |
| libdiskinfos.sh | `detect_disc_type()` | ~360 | `discinfo_set_filesystem()` hinzugefügt | ✅ |
| libdiskinfos.sh | `get_disc_label()` | 580 | `disc_label=` → `discinfo_set_label()` | ✅ |
| libcommon.sh | `get_disc_size()` | 386-418 | `volume_size=` → `discinfo_set_size()` | ✅ |
| libcommon.sh | `reset_disc_variables()` | 591-601 | Ruft `discinfo_init()` auf | ✅ |
| libaudio.sh | `copy_audio_cd()` | 802 | `disc_label=` → `discinfo_set_label()` | ✅ |
| libaudio.sh | `copy_audio_cd()` | 807 | `disc_label=` → `discinfo_set_label()` | ✅ |
| libaudio.sh | `copy_audio_cd()` | 811 | `disc_label=` → `discinfo_set_label()` | ✅ |

**Gesamt:** 21 Schreibzugriffe konvertiert ✅

---

## 🔄 Phase 3: Lesezugriffe analysieren (IN ARBEIT)

### **Verbleibende Lesezugriffe auf globale Variablen:**

| Variable | Anzahl Lesezugriffe | Dateien |
|----------|---------------------|---------|
| `$disc_type` / `${disc_type}` | ~50 | disk2iso.sh, lib*.sh |
| `$disc_label` / `${disc_label}` | ~33 | disk2iso.sh, lib*.sh |
| `$disc_volume_size` | ~5 | libdiskinfos.sh, libbluray.sh |

**Strategie:**
- ✅ **Setter:** Verwenden `discinfo_set_*()` Funktionen (ERLEDIGT)
- 🔄 **Getter:** Direktzugriff `${DISC_INFO[type]}` statt Funktionsaufruf
- ⚠️ **Rückwärtskompatibilität:** Setter setzen auch alte globale Variablen (DEPRECATED)

---

## 📋 Phase 4: Migration aller Lesezugriffe (AUSSTEHEND)

### **Zu ändernde Dateien (Priorität):**

#### **🔴 KRITISCH (Hauptlogik):**

1. **disk2iso.sh** (~21 Stellen)
   - State Machine: `if [[ "$disc_type" == "audio-cd" ]]`
   - API Updates: `api_update_status "copying" "$disc_label" "$disc_type"`
   - MQTT: `mqtt_publish_state "copying" "$disc_label" "$disc_type"`
   - **Änderung:** `"$disc_type"` → `"${DISC_INFO[type]}"`

#### **🟠 HOCH (Häufige Nutzung):**

2. **libdvd.sh** (~12 Stellen)
   - Dateinamen-Erzeugung, Metadata-Queries, Logging
   - **Änderung:** `"$disc_label"` → `"${DISC_INFO[label]}"`

3. **libaudio.sh** (~8 Stellen - nach Setter-Migration)
   - API Updates, Dateinamen, Logging
   - **Änderung:** Direktzugriff auf `${DISC_INFO[label]}`

4. **libsysteminfo.sh** (~11 Stellen)
   - Duplicate-Check, Target-Folder-Erzeugung
   - **Änderung:** Direktzugriff

5. **libfiles.sh** (~2 Stellen)
   - ISO-Pfad-Erzeugung
   - **Änderung:** `get_unique_iso_path "$target_dir" "$disc_label"` → `"${DISC_INFO[label]}"`

#### **🟡 MITTEL:**

6. **libmetadata.sh** (~11 Stellen)
   - Provider-Lookup, Query-Funktionen
   - **Änderung:** Direktzugriff

7. **libmusicbrainz.sh** (~5 Stellen)
8. **libtmdb.sh** (~5 Stellen)
9. **libbluray.sh** (~2 Stellen)
10. **libcommon.sh** (~4 Stellen - nach get_disc_size)
11. **liblogging.sh** (~2 Stellen)

---

## 🎯 Nächste Schritte

### **Phase 4a: Kritische Dateien migrieren**
```bash
# disk2iso.sh - Beispiel-Änderung
# VORHER:
if [[ "$disc_type" == "audio-cd" ]]; then
    api_update_status "copying" "$disc_label" "$disc_type"
fi

# NACHHER:
if [[ "${DISC_INFO[type]}" == "audio-cd" ]]; then
    api_update_status "copying" "${DISC_INFO[label]}" "${DISC_INFO[type]}"
fi
```

### **Phase 4b: Alle Library-Module migrieren**
- Systematisch durch alle lib*.sh Dateien
- Pattern: `$disc_type` → `${DISC_INFO[type]}`
- Pattern: `$disc_label` → `${DISC_INFO[label]}`

### **Phase 5: Globale Variablen entfernen**
```bash
# libconfig.sh - Diese Zeilen löschen:
disc_label=""         # DEPRECATED - Nutze DISC_INFO[label]
disc_type=""          # DEPRECATED - Nutze DISC_INFO[type]
disc_volume_size=""   # DEPRECATED - Nutze DISC_INFO[size_sectors]
disc_block_size=""    # DEPRECATED - Nutze DISC_INFO[block_size]
```

### **Phase 6: Rückwärtskompatibilität entfernen**
```bash
# Aus Setter-Funktionen entfernen:
disc_type="$type"     # DEPRECATED
disc_label="$label"   # DEPRECATED
```

---

## 📊 Fortschritt

- ✅ **Phase 1:** Setter/Getter erstellt (100%)
- ✅ **Phase 2:** Setter-Verwendungen konvertiert (100%)
- 🔄 **Phase 3:** Lesezugriffe analysiert (100%)
- ⏳ **Phase 4:** Lesezugriffe migrieren (0%)
- ⏳ **Phase 5:** Globale Variablen entfernen (0%)
- ⏳ **Phase 6:** Rückwärtskompatibilität entfernen (0%)

**Gesamt-Fortschritt:** ~40% ✅

---

## ⚠️ Wichtige Hinweise

### **Rückwärtskompatibilität (TEMPORARY):**
Alle Setter setzen zusätzlich die alten globalen Variablen:
```bash
discinfo_set_type "audio-cd"
# Setzt: DISC_INFO[type]="audio-cd"
# UND:   disc_type="audio-cd" (DEPRECATED)
```

**Zweck:** Schrittweise Migration ermöglichen, Code bleibt funktionsfähig

### **Nach vollständiger Migration:**
1. Rückwärtskompatibilität aus Settern entfernen
2. Globale Variablen aus libconfig.sh löschen
3. `disc_type` und `disc_label` nur noch in DISC_INFO Array

---

## 🔍 Test-Strategie

Nach jeder Phase:
1. **Syntax-Check:** `bash -n disk2iso.sh`
2. **Modul-Tests:** Dependency-Checks laufen lassen
3. **Integration-Test:** Testlauf mit echter Disc
4. **Regression-Test:** Alte Funktionalität prüfen

---

## 📝 Offene Fragen

1. ❓ Sollen Getter-Funktionen für ALLE Felder erstellt werden?
   - **Aktuell:** Nur für häufig genutzte Felder (type, label, size)
   - **Alternative:** Direktzugriff `${DISC_INFO[xyz]}` bevorzugen

2. ❓ Wie lange Rückwärtskompatibilität beibehalten?
   - **Vorschlag:** Bis Phase 4 abgeschlossen, dann entfernen

3. ❓ DISC_DATA Migration parallel oder nachgelagert?
   - **Aktuell:** Fokus auf DISC_INFO
   - **Später:** DISC_DATA für Metadaten (libmetadata.sh, libaudio.sh)

---

**Letzte Aktualisierung:** 28.01.2026, Phase 2 abgeschlossen
