# disk2iso - Modul-Abhängigkeiten und Lade-Reihenfolge

## Start-Sequenz

### Phase 1: Bootstrap (Zeile 70-79)
```bash
1. SCRIPT_DIR ermitteln
2. source conf/disk2iso.conf          # Konfiguration laden
3. source lib/libconfig.sh             # Config-Management
4. OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"  # Globale Variable setzen
```

### Phase 2: Core-Module laden (Zeile 85-92)
```bash
5. source lib/liblogging.sh
6. source lib/libapi.sh
7. source lib/libfiles.sh
8. source lib/libfolders.sh
9. source lib/libdiskinfos.sh
10. source lib/libdrivestat.sh
11. source lib/libsysteminfo.sh
12. source lib/libcommon.sh
```

### Phase 3: Sprachdatei laden (Zeile 95)
```bash
13. load_module_language "disk2iso"    # Nutzt liblogging.sh
```

### Phase 4: Dependency-Checks (Zeile 100-144)
```bash
14. check_dependencies_logging
15. check_dependencies_folders         # PROBLEM: Nutzt log_error (liblogging)
16. check_dependencies_files
17. check_dependencies_api
18. check_dependencies_diskinfos
19. check_dependencies_drivestat
20. check_dependencies_systeminfo
21. check_dependencies_common         # PROBLEM: Nutzt ensure_subfolder (libfolders)
```

---

## Erkannte Abhängigkeiten

### Modul-zu-Modul-Abhängigkeiten

| Modul | Benötigt Funktionen aus | Funktionen | Kritikalität |
|-------|------------------------|-----------|--------------|
| **liblogging** | libfolders | `ensure_subfolder()` | ⚠️ Optional |
| **libconfig** | liblogging | `log_*()` | ⚠️ Optional |
| **libconfig** | libfolders | `ensure_subfolder()` | ⚠️ Optional |
| **libfiles** | - | - | ✅ Keine |
| **libfolders** | liblogging | `log_*()` | ⚠️ Optional |
| **libdiskinfos** | liblogging | `log_*()` | ⚠️ Optional |
| **libdrivestat** | liblogging | `log_*()` | ⚠️ Optional |
| **libsysteminfo** | liblogging | `log_*()` | ⚠️ Optional |
| **libcommon** | liblogging | `log_*()` | ⚠️ Optional |
| **libcommon** | libfolders | `ensure_subfolder()` | ⚠️ Optional |
| **libapi** | - | - | ✅ Keine |

---

## Probleme in der aktuellen Reihenfolge

### Problem 1: Zirkuläre Abhängigkeit (liblogging ↔ libfolders)

**liblogging.sh check_dependencies_logging():**
```bash
if declare -f ensure_subfolder >/dev/null 2>&1; then
    if ! ensure_subfolder "$LOG_DIR" >/dev/null 2>&1; then
        echo "FEHLER: Log-Ordner konnte nicht erstellt werden" >&2
        return 1
    fi
fi
```

**libfolders.sh ensure_subfolder():**
```bash
if [[ ! -d "$full_path" ]]; then
    if mkdir -p "$full_path" 2>/dev/null; then
        log_info "$MSG_SUBFOLDER_CREATED $full_path" >&2  # ← Nutzt liblogging!
    else
        log_error "$MSG_ERROR_CREATE_SUBFOLDER $full_path" >&2
        return 1
    fi
fi
```

**Status:** ⚠️ Funktioniert nur weil `declare -f` prüft + Fallback

---

### Problem 2: check_dependencies Reihenfolge vs. Nutzung

**Aktuell:**
```bash
# Zeile 100-144
check_dependencies_logging    # Wird zuerst geprüft
check_dependencies_folders    # Nutzt log_error (von liblogging)
check_dependencies_common     # Nutzt log_error + ensure_subfolder
```

**Problem:** 
- `check_dependencies_folders` nutzt `log_error()` aus liblogging
- ABER: liblogging wurde bereits geladen (Zeile 85)
- ✅ Funktioniert, weil Module VOR check_dependencies geladen werden

---

## Optimale Lade-Reihenfolge

### Ebene 0: Keine Abhängigkeiten
```bash
1. libconfig.sh        # Nur awk, sed, grep (POSIX)
2. libfiles.sh         # Nur Bash-Funktionen
3. libapi.sh           # Nur Bash-Funktionen
```

### Ebene 1: Basis-Infrastruktur
```bash
4. liblogging.sh       # Braucht: keine (nutzt optional libfolders)
```

### Ebene 2: Logging verfügbar
```bash
5. libfolders.sh       # Braucht: liblogging (für log_*)
6. libsysteminfo.sh    # Braucht: liblogging
7. libdrivestat.sh     # Braucht: liblogging
8. libdiskinfos.sh     # Braucht: liblogging
```

### Ebene 3: Alles verfügbar
```bash
9. libcommon.sh        # Braucht: liblogging, libfolders
```

---

## Empfohlene Lade-Reihenfolge (neu)

```bash
# Phase 1: Bootstrap (keine Abhängigkeiten)
source lib/libconfig.sh          # 1. Config-Management
source lib/libapi.sh             # 2. API (nur Bash)
source lib/libfiles.sh           # 3. Dateinamen (nur Bash)

# Phase 2: Basis-Logging
source lib/liblogging.sh         # 4. Logging (unabhängig)

# Phase 3: Ordner-Verwaltung (braucht Logging)
source lib/libfolders.sh         # 5. Ordner (nutzt log_*)

# Phase 4: System-Informationen (braucht Logging)
source lib/libsysteminfo.sh      # 6. System-Info
source lib/libdrivestat.sh       # 7. Drive-Status
source lib/libdiskinfos.sh       # 8. Disk-Infos

# Phase 5: Common (braucht alles)
source lib/libcommon.sh          # 9. Common Functions
```

### Entsprechende check_dependencies Reihenfolge

```bash
check_dependencies_config        # Keine Abhängigkeiten
check_dependencies_api           # Keine Abhängigkeiten
check_dependencies_files         # Keine Abhängigkeiten
check_dependencies_logging       # Optional: libfolders
check_dependencies_folders       # Nutzt: log_* (bereits geladen)
check_dependencies_systeminfo    # Nutzt: log_*
check_dependencies_drivestat     # Nutzt: log_*
check_dependencies_diskinfos     # Nutzt: log_*
check_dependencies_common        # Nutzt: log_*, ensure_subfolder
```

---

## Aktuelle Reihenfolge (IST-Zustand)

**Laden (Zeile 85-92):**
```
liblogging → libapi → libfiles → libfolders → libdiskinfos → libdrivestat → libsysteminfo → libcommon
```

**Check (Zeile 100-144):**
```
logging → folders → files → api → diskinfos → drivestat → systeminfo → common
```

**Problem:** Check-Reihenfolge ≠ Lade-Reihenfolge

---

## Kritische Erkenntnisse

### 1. Zirkuläre Abhängigkeit existiert NICHT wirklich
- liblogging nutzt libfolders **optional** (mit `declare -f`)
- libfolders nutzt liblogging **optional** (mit `declare -f`)
- ✅ Beide Module sind defensiv programmiert

### 2. Module werden VOR check_dependencies geladen
- ✅ Alle Funktionen sind verfügbar wenn checks laufen
- ⚠️ Reihenfolge der checks ist inkonsistent

### 3. Defensive Programmierung rettet die Situation
```bash
# Pattern überall:
if declare -f function_name >/dev/null 2>&1; then
    function_name "$@"
fi
```

---

## Empfehlung

### Option A: Reihenfolge anpassen (konservativ)
Lade-Reihenfolge nach Abhängigkeiten sortieren:
```bash
# 1. Keine Abhängigkeiten
libconfig → libapi → libfiles

# 2. Basis
liblogging

# 3. Nutzen Logging
libfolders → libsysteminfo → libdrivestat → libdiskinfos

# 4. Nutzen alles
libcommon
```

### Option B: Aktuelle Reihenfolge beibehalten (pragmatisch)
- ✅ Funktioniert bereits
- ✅ Defensives Programming verhindert Probleme
- ⚠️ Aber: Check-Reihenfolge sollte Lade-Reihenfolge entsprechen

### Option C: Dokumentieren (minimal)
- Abhängigkeiten dokumentieren
- Keine Code-Änderungen
- ✅ Wartbar

---

## Zusammenfassung

**Aktuelle Situation:**
- Modul-Abhängigkeiten existieren, sind aber **optional**
- Defensive Programmierung verhindert Fehler
- Check-Reihenfolge stimmt nicht mit Lade-Reihenfolge überein

**Risiko:**
- 🟢 NIEDRIG - System funktioniert stabil
- 🟡 WARTUNG - Bei Änderungen Reihenfolge beachten

**Empfehlung:**
- ✅ Check-Reihenfolge an Lade-Reihenfolge anpassen
- ✅ Abhängigkeiten dokumentieren
- ⚠️ Lade-Reihenfolge nur bei Bedarf ändern

---

## Visuelles Abhängigkeits-Diagramm

```
┌─────────────────────────────────────────────────────────────┐
│                    DISK2ISO START-ABLAUF                    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ PHASE 1: Bootstrap (keine externen Funktionen)              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  conf/disk2iso.conf  →  DEFAULT_OUTPUT_DIR                  │
│  lib/libconfig.sh    →  get_ini_value, update_config_value  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ PHASE 2: Kern-Module laden (Funktionen definieren)          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐                                           │
│  │ liblogging   │ ← Keine Abhängigkeiten                    │
│  └──────────────┘                                           │
│         │                                                    │
│         ├─────────→ log_error(), log_info(), log_warning()  │
│         │                                                    │
│  ┌──────┴───────┐                                           │
│  │ libapi       │ ← Keine Abhängigkeiten                    │
│  │ libfiles     │ ← Keine Abhängigkeiten                    │
│  └──────────────┘                                           │
│         │                                                    │
│  ┌──────┴───────┐                                           │
│  │ libfolders   │ ← Nutzt: log_*() [optional]               │
│  └──────────────┘                                           │
│         │                                                    │
│         ├─────────→ ensure_subfolder()                      │
│         │                                                    │
│  ┌──────┴───────────────────────┐                           │
│  │ libdiskinfos   libdrivestat  │ ← Nutzt: log_*()          │
│  │ libsysteminfo                │ ← Nutzt: log_*()          │
│  └──────────────────────────────┘                           │
│         │                                                    │
│  ┌──────┴───────┐                                           │
│  │ libcommon    │ ← Nutzt: log_*(), ensure_subfolder()      │
│  └──────────────┘                                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ PHASE 3: Sprachdateien laden                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  load_module_language "disk2iso"                            │
│    ↳ Nutzt: liblogging.sh (load_module_language)            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ PHASE 4: Dependency-Checks (alle Funktionen verfügbar!)     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ✓ check_dependencies_logging    (nutzt: ensure_subfolder)  │
│  ✓ check_dependencies_folders    (nutzt: log_*)             │
│  ✓ check_dependencies_files      (keine Abhängigkeiten)     │
│  ✓ check_dependencies_api        (keine Abhängigkeiten)     │
│  ✓ check_dependencies_diskinfos  (nutzt: log_*)             │
│  ✓ check_dependencies_drivestat  (nutzt: log_*)             │
│  ✓ check_dependencies_systeminfo (nutzt: log_*)             │
│  ✓ check_dependencies_common     (nutzt: log_*, ensure_*)   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ PHASE 5: Optionale Module (gleiche Abhängigkeitslogik)      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  libcd.sh → libdvd.sh → libbluray.sh → libmetadata.sh       │
│    ↳ Alle nutzen: log_*(), ensure_subfolder()               │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Abhängigkeits-Matrix

| Modul ↓ / Benötigt → | log_* | ensure_subfolder | get_ini_value | api_* | Extern |
|----------------------|-------|------------------|---------------|-------|--------|
| **libconfig**        | ⚠️    | ⚠️               | -             | -     | awk, sed |
| **libapi**           | -     | -                | -             | -     | -      |
| **libfiles**         | -     | -                | -             | -     | -      |
| **liblogging**       | -     | ⚠️               | -             | -     | -      |
| **libfolders**       | ✅    | -                | -             | -     | mkdir  |
| **libdiskinfos**     | ✅    | -                | -             | -     | mount, umount |
| **libdrivestat**     | ✅    | -                | -             | -     | lsblk  |
| **libsysteminfo**    | ✅    | -                | -             | -     | df, blkid |
| **libcommon**        | ✅    | ✅               | -             | ⚠️    | dd, md5sum |

**Legende:**
- ✅ = Aktiv genutzt (Funktion wird aufgerufen)
- ⚠️ = Optional (mit `declare -f` geprüft)
- - = Keine Abhängigkeit

---

## Kritische Pfade

### Kritischer Pfad 1: Logging-Setup
```
liblogging geladen
    ↓
libfolders geladen (nutzt log_*)
    ↓
check_dependencies_logging
    ↓ (nutzt ensure_subfolder - OPTIONAL)
LOG_DIR wird erstellt
    ↓
Logging voll funktionsfähig
```

**Problem:** Zirkuläre Abhängigkeit wird durch optionale Nutzung aufgelöst.

### Kritischer Pfad 2: Ordner-Verwaltung
```
libfolders geladen
    ↓
ensure_subfolder() verfügbar
    ↓
check_dependencies_common
    ↓ (nutzt ensure_subfolder für DATA_DIR)
DATA_DIR wird erstellt
    ↓
Ordner-System funktionsfähig
```

**Lösung:** libfolders wird VOR check_dependencies_common geladen.

---

## Test-Szenarien

### Szenario 1: liblogging ohne libfolders
```bash
# Was passiert wenn libfolders nicht geladen wurde?
source lib/liblogging.sh
check_dependencies_logging
# → Funktioniert! LOG_DIR-Check wird übersprungen (declare -f)
```

### Szenario 2: libfolders ohne liblogging
```bash
# Was passiert wenn liblogging nicht geladen wurde?
source lib/libfolders.sh
ensure_subfolder "test"
# → Funktioniert! log_* Aufrufe werden ausgeführt (aber Funktionen fehlen)
# → FEHLER möglich wenn log_error nicht definiert ist
```

**Aktueller Schutz:** Keine! libfolders verlässt sich darauf, dass liblogging geladen ist.

### Szenario 3: Falsche Lade-Reihenfolge
```bash
# Wenn libfolders VOR liblogging geladen würde:
source lib/libfolders.sh  # ← log_error() nicht definiert!
source lib/liblogging.sh  # ← zu spät
ensure_subfolder "test"   # → FEHLER: log_error: command not found
```

**Aktueller Schutz:** Lade-Reihenfolge in disk2iso.sh ist fest codiert.

---

## Verbesserungsvorschläge

### 1. Defensive Programmierung in libfolders.sh
```bash
# AKTUELL:
log_info "$MSG_SUBFOLDER_CREATED $full_path" >&2

# BESSER:
if declare -f log_info >/dev/null 2>&1; then
    log_info "$MSG_SUBFOLDER_CREATED $full_path" >&2
else
    echo "INFO: Ordner erstellt: $full_path" >&2
fi
```

### 2. Check-Reihenfolge anpassen
```bash
# AKTUELL (disk2iso.sh):
check_dependencies_logging    # 1.
check_dependencies_folders    # 2. nutzt log_*

# BESSER:
check_dependencies_logging    # 1.
check_dependencies_api        # 2. keine Abhängigkeit
check_dependencies_files      # 3. keine Abhängigkeit
check_dependencies_folders    # 4. nutzt log_*
```

### 3. Explizite Abhängigkeits-Dokumentation
Jedes Modul sollte am Anfang dokumentieren:
```bash
# ============================================================================
# MODUL-ABHÄNGIGKEITEN
# ============================================================================
# Erforderlich: liblogging (log_error, log_info)
# Optional: -
# Externe Tools: mkdir (POSIX)
```

---

## Fazit

✅ **Das aktuelle System funktioniert stabil**
- Defensive Programmierung verhindert Fehler
- Module prüfen Funktions-Verfügbarkeit mit `declare -f`

⚠️ **Aber es gibt Inkonsistenzen**
- Check-Reihenfolge ≠ Lade-Reihenfolge
- libfolders verlässt sich auf liblogging (nicht defensiv)
- Keine explizite Abhängigkeits-Dokumentation

🎯 **Empfohlene Maßnahmen**
1. Check-Reihenfolge an Lade-Reihenfolge anpassen
2. libfolders.sh defensiver programmieren
3. Abhängigkeiten in Modul-Header dokumentieren
4. Bei zukünftigen Modulen: Abhängigkeiten minimieren
