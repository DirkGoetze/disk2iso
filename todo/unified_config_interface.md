# Unified Config Interface Konzept

**Status:** Planung  
**Datum:** 2026-02-03  
**Ziel:** Einheitliche API für .conf, .ini und .json Konfigurationsdateien

---

## 1. Motivation

### Aktuelles Problem
- Unterschiedliche Funktionsnamen für verschiedene Formate
- INI-Funktionen existieren bereits: `get_ini_value()`, `write_ini_value()`, etc.
- .conf Format hat eigene Setter: `set_output_dir()`, `set_module_enabled()`, etc.
- .json Format hat keine einheitliche Schnittstelle
- Code-Duplikation und inkonsistente APIs

### Ziel-Architektur
Einheitliche Namenskonvention mit Format-Suffix:
```bash
config_{operation}_{datatype}_{format}(filename, ...)
```

---

## 2. Format-Familien

### .conf Format (Simple Key=Value)
- **Beispiel:** `disk2iso.conf`
- **Struktur:** `KEY="value"` ohne Sections
- **Pfad:** `${INSTALL_DIR}/conf/disk2iso.conf`
- **Tools:** awk, sed, grep (POSIX)

### .ini Format (Sectioned Key=Value)
```ini
[section]
key=value
key2=value2

[section2]
key3=value3
```
- **Beispiel:** `libaudio.ini`, `libdvd.ini`
- **Pfad:** `${INSTALL_DIR}/conf/lib*.ini`
- **Tools:** awk, sed, grep (POSIX)
- **Bestehende Funktionen:** Bereits implementiert

### .json Format (Structured Data)
```json
{
  "key": "value",
  "nested": {
    "key2": "value2"
  },
  "array": [1, 2, 3]
}
```
- **Beispiel:** API-Files, zukünftige Manifeste
- **Pfad:** `${INSTALL_DIR}/conf/*.json`, `${INSTALL_DIR}/api/*.json`
- **Tools:** jq (bevorzugt) mit grep/awk Fallback

---

## 3. Geplante Operationen

### 3.1 Single Value Operations

| Operation | .conf | .ini | .json |
|-----------|-------|------|-------|
| Read Value | `config_get_value_conf(module, key, [default])` | `config_get_value_ini(module, section, key, [default])` | `config_get_value_json(module, jsonpath, [default])` |
| Write Value | `config_set_value_conf(module, key, value)` | `config_set_value_ini(module, section, key, value)` | `config_set_value_json(module, jsonpath, value)` |
| Delete Value | `config_del_value_conf(module, key)` | `config_del_value_ini(module, section, key)` | `config_del_value_json(module, jsonpath)` |

### 3.2 Array Operations

| Operation | .conf | .ini | .json |
|-----------|-------|------|-------|
| Read Array | `config_get_array_conf(module, key)` | `config_get_array_ini(module, section, key)` | `config_get_array_json(module, jsonpath)` |
| Write Array | `config_set_array_conf(module, key, values...)` | `config_set_array_ini(module, section, key, values...)` | `config_set_array_json(module, jsonpath, values...)` |
| Delete Array | `config_del_array_conf(module, key)` | `config_del_array_ini(module, section, key)` | `config_del_array_json(module, jsonpath)` |

### 3.3 Section/Object Operations

| Operation | .conf | .ini | .json |
|-----------|-------|------|-------|
| Read Section | `config_get_section_conf(module)` | `config_get_section_ini(module, section)` | `config_get_section_json(module, jsonpath)` |
| Write Section | `config_set_section_conf(module, key=val...)` | `config_set_section_ini(module, section, key=val...)` | `config_set_section_json(module, jsonpath, json)` |
| Delete Section | `config_del_section_conf(module)` | `config_del_section_ini(module, section)` | `config_del_section_json(module, jsonpath)` |

### 3.4 Comment Operations

| Operation | .conf | .ini | .json |
|-----------|-------|------|-------|
| Add Comment | `config_add_comment_conf(module, key, comment)` | `config_add_comment_ini(module, section, key, comment)` | N/A (JSON hat keine Kommentare) |
| Get Comment | `config_get_comment_conf(module, key)` | `config_get_comment_ini(module, section, key)` | N/A |

**Gesamt:** 11 Operationen × 3 Formate = **33 Funktionen** (JSON: 27, da keine Kommentare)

---

## 4. Technische Details

### 4.1 Pfad-Konvention ✅ ENTSCHIEDEN

**Entscheidung:** Parameter = Modulname (OHNE Suffix), Pfad-Auflösung intern

**Regeln:**
- **Parameter:** Modulname ohne Dateiendung (z.B. `"disk2iso"`, `"mqtt"`, `"audio"`)
- **Interne Auflösung pro Format:**
  - `.conf` → `${INSTALL_DIR}/conf/${modulname}.conf`
  - `.ini` → `get_module_ini_path(modulname)` → `${INSTALL_DIR}/conf/lib${modulname}.ini`
  - `.json` → `${INSTALL_DIR}/conf/${modulname}.json` oder `${INSTALL_DIR}/api/${modulname}.json`

**Beispiele:**
```bash
# .conf Format
config_get_value_conf("disk2iso", "OUTPUT_DIR")
# Intern: ${INSTALL_DIR}/conf/disk2iso.conf

# .ini Format  
config_get_value_ini("mqtt", "api", "broker")
# Intern: get_module_ini_path("mqtt") → ${INSTALL_DIR}/conf/libmqtt.ini

# .json Format
config_get_value_json("status", ".state")
# Intern: ${INSTALL_DIR}/api/status.json
```

**Vorteile:**
- ✅ Semantisch sauberer (Modul-Konzept statt Datei-Konzept)
- ✅ Konsistent über alle Formate
- ✅ Nutzt bestehende `get_module_ini_path()` Logik
- ✅ Kein Path-Traversal möglich
- ✅ Wiederverwendung von `libfiles.sh` / `libfolders.sh`

**Wrapper-Kompatibilität:**
```bash
# Alte Funktion mit vollständigem Pfad:
get_ini_value("/opt/disk2iso/conf/libmqtt.ini", "api", "broker")

# Wrapper extrahiert Modulnamen:
get_ini_value() {
    local ini_file="$1"
    local module=$(basename "$ini_file" .ini | sed 's/^lib//')  # libmqtt.ini → mqtt
    config_get_value_ini "$module" "$2" "$3"
}
```

### 4.2 Dependencies
- **POSIX Tools:** awk, sed, grep (immer verfügbar)
- **jq:** Bevorzugt für JSON, Fallback auf grep/awk
- **Status:** jq ist faktisch Core-Dependency (libapi.sh nutzt es)

### 4.3 Error Handling
```bash
config_get_value_conf() {
    local module="$1"
    local key="$2"
    local default="${3:-}"
    local filepath="${INSTALL_DIR}/conf/${module}.conf"
    
    # Validierung
    [[ -z "$module" ]] && { log_error "Module name missing"; return 1; }
    [[ -z "$key" ]] && { log_error "Key missing"; return 1; }
    [[ ! -f "$filepath" ]] && {
        [[ -n "$default" ]] && { echo "$default"; return 0; }
        log_error "Config file not found: ${module}.conf"
        return 1
    }
    
    # Read operation...
}
```

### 4.4 Atomic Writes
```bash
config_set_value_conf() {
    local module="$1"
    local key="$2"
    local value="$3"
    local filepath="${INSTALL_DIR}/conf/${module}.conf"
    
    # Atomic write mit temp-file
    local temp_file="${filepath}.tmp"
    # ... modify ...
    mv -f "$temp_file" "$filepath" || return 1
}
```

---

## 5. Migration bestehender Funktionen

### 5.1 Mapping: Aktuell → Neu

#### INI-Funktionen (bereits vorhanden)
```bash
# Alt (behalten für Kompatibilität)
get_ini_value(file, section, key)
write_ini_value(file, section, key, value)
delete_ini_value(file, section, key)
get_ini_array(file, section, key)
get_ini_section(file, section)
count_ini_section_entries(file, section)

# Neu (zusätzlich erstellen)
config_get_value_ini(file, section, key)      → Wrapper um get_ini_value
config_set_value_ini(file, section, key, val) → Wrapper um write_ini_value
config_del_value_ini(file, section, key)      → Wrapper um delete_ini_value
config_get_array_ini(file, section, key)      → Wrapper um get_ini_array
config_get_section_ini(file, section)         → Wrapper um get_ini_section
# ... weitere Wrapper
```

#### .conf Setter (disk2iso.conf spezifisch)
```bash
# Alt (behalten, nutzen intern neue API)
set_output_dir(value)           → config_set_value_conf("disk2iso.conf", "OUTPUT_DIR", value)
set_module_enabled(mod, val)    → config_set_value_conf("disk2iso.conf", "${mod}_ENABLED", val)
get_output_dir()                → config_get_value_conf("disk2iso.conf", "OUTPUT_DIR")

# Neu (generisch für alle .conf Files)
config_get_value_conf(file, key)
config_set_value_conf(file, key, value)
```

### 5.2 Strategie
1. **Phase 1:** Neue unified API implementieren
2. **Phase 2:** Alte Funktionen zu Wrapper umbauen (rufen neue API)
3. **Phase 3:** Neuer Code nutzt nur noch neue API
4. **Kompatibilität:** Alte Funktionen bleiben für Legacy-Code

---

## 6. Offene Fragen / Komplikationen

### 6.1 JSON-Pfad-Notation ✅ ENTSCHIEDEN
- **jq:** Nutzt `.path.to.key` Syntax
- **Entscheidung:** Konsistent mit jq-Syntax bleiben
- **Beispiele:**
  - `.key` → Top-level Key
  - `.nested.key` → Nested Object
  - `.array[0]` → Array-Element
  - `.array[]` → Alle Array-Elemente

### 6.2 Array-Format in .conf/.ini ✅ ENTSCHIEDEN
- **Aktuelles Format:** Komma-separiert (z.B. `optional=dvdbackup,genisoimage,ddrescue`)
- **Entscheidung:** Komma-Trennung beibehalten
- **Beispiele:**
  ```bash
  # .conf Format (single-line)
  TOOLS="tool1,tool2,tool3"
  
  # .ini Format (same, komma-separiert)
  [dependencies]
  optional=dvdbackup,genisoimage,ddrescue
  ```

### 6.3 Quoting in .conf ⏳ ANALYSE

#### Aktueller Zustand

**disk2iso.conf nutzt gemischtes Quoting:**
```bash
# String-Werte MIT Quotes
DEFAULT_OUTPUT_DIR="/media/iso"
MQTT_BROKER="192.168.1.100"
MQTT_USER=""
MQTT_PASSWORD=""
MQTT_CLIENT_ID="disk2iso-${HOSTNAME}"

# Numerische Werte OHNE Quotes
MQTT_PORT=1883
MQTT_QOS=0
MP3_QUALITY=2

# Boolean-Werte OHNE Quotes
MQTT_ENABLED=false
MQTT_RETAIN=true
METADATA_ENABLED=true
```

**Aktuelle Setter-Funktionen (libconfig.sh):**
```bash
# String mit Quotes
set_mqtt_broker() {
    /usr/bin/sed -i "s|^MQTT_BROKER=.*|MQTT_BROKER=\"${value}\"|" "$CONFIG_FILE"
}

# Numerisch ohne Quotes
set_mqtt_port() {
    /usr/bin/sed -i "s|^MQTT_PORT=.*|MQTT_PORT=${value}|" "$CONFIG_FILE"
}

# Boolean ohne Quotes
set_mqtt_enabled() {
    /usr/bin/sed -i "s|^MQTT_ENABLED=.*|MQTT_ENABLED=${value}|" "$CONFIG_FILE"
}
```

**Bestehende Reader-Funktion (get_config_value):**
```bash
# Lese Wert mit sed
local value=$(sed -n "s/^${key}=\(.*\)/\1/p" "$config_file" | head -1)

# Entferne Anführungszeichen
value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/')
```
→ Quotes werden beim Lesen automatisch entfernt!

#### Problem-Szenarien

**1. Werte mit Spaces**
```bash
# Funktioniert MIT Quotes:
DEFAULT_OUTPUT_DIR="/media/my iso files"
→ Beim Sourcen in Bash: ✅ Korrekt

# Funktioniert NICHT ohne Quotes:
DEFAULT_OUTPUT_DIR=/media/my iso files
→ Beim Sourcen in Bash: ❌ Nur "/media/my" wird gelesen
```

**2. Leere Strings**
```bash
# MIT Quotes - erkennbar als leer:
MQTT_USER=""
→ Beim Sourcen: ✅ Variable ist leerer String

# OHNE Quotes - nicht unterscheidbar:
MQTT_USER=
→ Beim Sourcen: ⚠️ Variable ist leer (aber Syntax-Error möglich)
```

**3. Variablen-Expansion**
```bash
# MIT Quotes - expandiert beim Sourcen:
MQTT_CLIENT_ID="disk2iso-${HOSTNAME}"
→ Beim Sourcen: ✅ "disk2iso-server01"

# OHNE Quotes - expandiert anders:
MQTT_CLIENT_ID=disk2iso-${HOSTNAME}
→ Beim Sourcen: ✅ Funktioniert auch, aber unsauberer
```

**4. Spezielle Zeichen**
```bash
# Passwort mit Sonderzeichen:
MQTT_PASSWORD="p@ssw0rd!#$"
→ MIT Quotes: ✅ Sicher
→ OHNE Quotes: ❌ Shell-Interpretation von !, $, etc.
```

#### Herausforderungen für unified API

**A) Type Detection beim Schreiben**
```bash
config_set_value_conf("disk2iso.conf", "MQTT_PORT", "1883")
# Frage: Woher weiß Funktion, dass es Numerisch ist?

# Option 1: Heuristik
if [[ "$value" =~ ^[0-9]+$ ]]; then
    # Numerisch - keine Quotes
    sed -i "s|^${key}=.*|${key}=${value}|"
else
    # String - mit Quotes
    sed -i "s|^${key}=.*|${key}=\"${value}\"|"
fi

# Option 2: Immer Quotes (sicherer)
sed -i "s|^${key}=.*|${key}=\"${value}\"|"
→ Problem: Inkonsistent zu bestehendem Format

# Option 3: Optional Type-Parameter
config_set_value_conf("disk2iso.conf", "MQTT_PORT", "1883", "integer")
config_set_value_conf("disk2iso.conf", "MQTT_BROKER", "192.168.1.1", "string")
→ Problem: Mehr Komplexität
```

**B) Quote-Escaping**
```bash
# User-Input mit Quotes im Wert:
config_set_value_conf("disk2iso.conf", "LABEL", 'My "Special" Disc')

# Schreiben muss escapen:
LABEL="My \"Special\" Disc"

# Lesen muss de-escapen:
→ Komplexe sed-Patterns nötig
```

**C) Bestehenden Code nicht brechen**
```bash
# Bestehende set_mqtt_broker() Funktion:
set_mqtt_broker() {
    /usr/bin/sed -i "s|^MQTT_BROKER=.*|MQTT_BROKER=\"${value}\"|"
}

# Neue unified API:
config_set_value_conf("disk2iso.conf", "MQTT_BROKER", value)

# Frage: Müssen beide zum gleichen Ergebnis führen?
→ Ja, für Rückwärts-Kompatibilität!
```

#### Lösungsvorschläge

**Variante A: Smart Quoting (Heuristik)**
```bash
config_set_value_conf() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    # Heuristik: Numerisch, Boolean oder String?
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        # Integer - keine Quotes
        sed -i "s|^${key}=.*|${key}=${value}|" "$filepath"
    elif [[ "$value" =~ ^(true|false)$ ]]; then
        # Boolean - keine Quotes
        sed -i "s|^${key}=.*|${key}=${value}|" "$filepath"
    else
        # String - mit Quotes + Escaping
        value="${value//\"/\\\"}"  # Escape existing quotes
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$filepath"
    fi
}
```
**Vorteile:** Kompatibel zu bestehendem Format  
**Nachteile:** Heuristik kann falsch liegen ("123" als String nicht möglich)

**Variante B: Always Quote (außer explizit unquoted)**
```bash
config_set_value_conf() {
    local file="$1"
    local key="$2"
    local value="$3"
    local quoted="${4:-true}"  # Default: Mit Quotes
    
    if [[ "$quoted" == "false" ]]; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$filepath"
    else
        value="${value//\"/\\\"}"
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$filepath"
    fi
}
```
**Vorteile:** Sicher, explizit steuerbar  
**Nachteile:** Zusätzlicher Parameter, existierendes Format ändern?

**Variante C: Type-Aware API (wie bestehende Setter)**
```bash
config_set_value_conf(file, key, value)         # Auto-detect
config_set_string_conf(file, key, value)        # Immer mit Quotes
config_set_integer_conf(file, key, value)       # Immer ohne Quotes
config_set_boolean_conf(file, key, value)       # Immer ohne Quotes

# Beim Lesen:
config_get_value_conf(file, key)        # String (quotes entfernt)
config_get_integer_conf(file, key)      # Integer (validiert)
config_get_boolean_conf(file, key)      # Boolean (validiert)
```
**Vorteile:** Type-safe, keine Heuristik  
**Nachteile:** 3× mehr Funktionen, Komplexität

**Variante D: Metadata-File mit Type-Info**
```bash
# conf/disk2iso.conf.meta (optional)
DEFAULT_OUTPUT_DIR=string
MQTT_PORT=integer
MQTT_ENABLED=boolean
MQTT_BROKER=string

# API nutzt Meta-Info falls vorhanden:
config_set_value_conf("disk2iso.conf", "MQTT_PORT", "1883")
→ Prüft .meta → Schreibt ohne Quotes
```
**Vorteile:** Explizit, erweiterbar  
**Nachteile:** Extra Datei pflegen, Overhead

#### Empfehlung ✅ ENTSCHIEDEN

**Type Detection Regeln:**

1. **Strings → Immer mit Quotes**
   ```bash
   MQTT_BROKER="192.168.1.100"
   LABEL="My Disc"
   VERSION="1.2.0-beta"      # Mit Bindestrichen → String
   ID="123-4"                # Mit Bindestrichen → String
   ```

2. **Integer → Ohne Quotes, strenge Validierung**
   ```bash
   MQTT_PORT=1883            # Nur Ziffern
   RETRIES=5                 # Nur Ziffern
   OFFSET=-10                # Optional: Negativ erlaubt
   
   # Regex: ^-?[0-9]+$  (optional minus, dann nur Ziffern)
   # Alles andere → String mit Quotes!
   ```

3. **Boolean → Ohne Quotes, flexible Eingabe**
   ```bash
   # Beim Schreiben (normalisiert):
   MQTT_ENABLED=true         # Immer "true" oder "false" (lowercase)
   
   # Beim Lesen (akzeptiert):
   true, false               # String-Werte (aktuell)
   0, 1                      # Numeric (C/C#/Delphi Kompatibilität)
   yes, no                   # Human-readable
   
   # Konvertierung beim Lesen:
   # 0, false, no, off → false
   # 1, true, yes, on  → true
   # Alle anderen → Error
   ```
   **Rationale:** Entwickler aus C#/Delphi/C können gewohnte 0/1 nutzen,
   wird intern zu true/false normalisiert. Exit-Code-Konvention (0=success)
   entspricht true=0 in Bash-Arithmetik.

**Implementierung:**

```bash
config_set_value_conf() {
    local module="$1"
    local key="$2"
    local value="$3"
    local filepath="${INSTALL_DIR}/conf/${module}.conf"
    
    # Type Detection (auto)
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        # Pure Integer - keine Quotes
        sed -i "s|^${key}=.*|${key}=${value}|" "$filepath"
        
    elif [[ "$value" =~ ^(true|false|0|1|yes|no|on|off)$ ]]; then
        # Boolean - normalisieren zu true/false
        case "$value" in
            true|1|yes|on)   value="true" ;;
            false|0|no|off)  value="false" ;;
        esac
        sed -i "s|^${key}=.*|${key}=${value}|" "$filepath"
        
    else
        # String - mit Quotes + Escaping
        value="${value//\"/\\\"}"  # Escape existing quotes
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$filepath"
    fi
}

config_get_value_conf() {
    local module="$1"
    local key="$2"
    local default="${3:-}"
    local filepath="${INSTALL_DIR}/conf/${module}.conf"
    
    # Lese Wert
    local value=$(sed -n "s/^${key}=\(.*\)/\1/p" "$filepath" | head -1)
    
    # Entferne Quotes falls vorhanden
    value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/')
    
    # Return value oder default
    if [[ -n "$value" ]]; then
        echo "$value"
    elif [[ -n "$default" ]]; then
        echo "$default"
    else
        return 1
    fi
}
```

**Vorteile:**
- ✅ Definitiv: Strings erkennbar durch Quotes
- ✅ Integer streng validiert (123-4 wird als String behandelt)
- ✅ Boolean flexibel (0/1 für C#/Delphi-Entwickler, true/false für Bash-Entwickler)
- ✅ Kompatibel zu bestehendem Format
- ✅ Keine Breaking Changes
- ✅ Cross-Language-Freundlich

### 6.4 Default-Werte ✅ TEILWEISE ENTSCHIEDEN

**Entscheidung:** Nur für Single-Value Getter, nicht für Array/Section

#### Single Value - Default unterstützt ✅

```bash
# Optional 3. Parameter für Default-Wert
config_get_value_conf(file, key, [default])
config_get_value_ini(file, section, key, [default])
config_get_value_json(file, jsonpath, [default])

# Beispiel:
output_dir=$(config_get_value_conf "disk2iso.conf" "OUTPUT_DIR" "/opt/disk2iso/output")
# Key existiert     → gibt gelesenen Wert zurück
# Key nicht gefunden → gibt "/opt/disk2iso/output" zurück
# Return Code: 0 in beiden Fällen

# Ohne Default:
output_dir=$(config_get_value_conf "disk2iso.conf" "OUTPUT_DIR")
# Key existiert     → Return 0, gibt Wert zurück
# Key nicht gefunden → Return 1, gibt "" zurück
```

**Vorteil:** Vereinfacht Caller-Code (kein explizites Fallback-Handling nötig)

#### Array - KEIN Default ❌

```bash
# Problem: Wie übergibt man Array als Default in Bash?
config_get_array_conf(file, key, ???)

# Option 1: String mit Delimiter?
tools=$(config_get_array_conf "disk2iso.conf" "TOOLS" "tool1,tool2,tool3")
# → Unklar, komplex zu parsen

# Option 2: Mehrere Parameter?
tools=$(config_get_array_conf "disk2iso.conf" "TOOLS" "tool1" "tool2" "tool3")
# → Signature unklar, wie unterscheidet man Default von varargs?

# Option 3: Leeres Array als Default?
tools=$(config_get_array_conf "disk2iso.conf" "TOOLS" "")
# → Sinnlos, Caller kann selbst prüfen
```

**Entscheidung:** Kein Default-Parameter bei Array-Gettern
- Array nicht gefunden → Return 1, gibt "" zurück
- Caller prüft Return-Code und setzt eigenes Fallback

#### Section - KEIN Default ❌

```bash
# Problem: Wie übergibt man komplexe Section als Default?
config_get_section_ini(file, section, ???)

# Option 1: Multi-line String?
config_get_section_ini "file.ini" "dependencies" "key1=val1\nkey2=val2"
# → Extrem komplex, fehleranfällig

# Option 2: Assoziatives Array?
declare -A defaults=(["key1"]="val1" ["key2"]="val2")
config_get_section_ini "file.ini" "dependencies" defaults
# → Bash Associative Arrays als Parameter problematisch
```

**Entscheidung:** Kein Default-Parameter bei Section-Gettern
- Section nicht gefunden → Return 1, gibt "" zurück
- Caller prüft Return-Code und lädt Defaults aus separater Funktion

#### Implementierung

```bash
# Single Value mit Default
config_get_value_conf() {
    local file="$1"
    local key="$2"
    local default="${3:-}"  # Optional
    local filepath="${INSTALL_DIR}/conf/${file}"
    
    # Validierung
    [[ ! -f "$filepath" ]] && {
        [[ -n "$default" ]] && { echo "$default"; return 0; }
        return 1
    }
    
    # Lese Wert
    local value=$(sed -n "s/^${key}=\(.*\)/\1/p" "$filepath" | head -1)
    value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/')
    
    # Wert gefunden oder Default?
    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    elif [[ -n "$default" ]]; then
        echo "$default"
        return 0
    else
        return 1
    fi
}

# Array ohne Default
config_get_array_conf() {
    local file="$1"
    local key="$2"
    # Kein Default-Parameter!
    
    # ... read logic ...
    # Return 1 wenn nicht gefunden, Caller handled Fallback
}
```

**Begründung:**
- Single Values: Default einfach implementierbar, sehr nützlich
- Arrays/Sections: Default zu komplex, Caller kann besser Fallback definieren
- Konsistent mit bestehendem Pattern (z.B. bash Parameter Expansion)

### 6.5 Type Safety ✅ ENTSCHIEDEN

**Entscheidung:** Type-Heuristik (gleiche Logik wie .conf Format)

**Problem:** JSON hat echte Typen, Bash behandelt alles als String

#### Der Unterschied: JSON vs Bash

**In JSON gibt es ECHTE Typen:**
```json
{
  "port": 1883,        // Integer (OHNE Quotes)
  "port": "1883",      // String (MIT Quotes) - UNTERSCHIEDLICH!
  "enabled": true,     // Boolean (OHNE Quotes)
  "enabled": "true",   // String (MIT Quotes) - UNTERSCHIEDLICH!
  "label": "My Disc"   // String (MIT Quotes)
}
```

**In Bash ist alles String:**
```bash
port=1883          # String "1883"
port="1883"        # String "1883" (IDENTISCH!)
enabled=true       # String "true"
enabled="true"     # String "true" (IDENTISCH!)
```

#### Problem bei der API

**Aktuell in libapi.sh (Zeile 263-275):**
```bash
api_update_progress() {
    local percent="$1"      # Bash: String "42"
    local copied_mb="$2"    # Bash: String "1024"
    
    # JSON schreiben - OHNE Quotes für Integer!
    local progress_json=$(cat <<EOF
{
  "percent": ${percent},      # JSON: Integer 42 (OHNE Quotes)
  "copied_mb": ${copied_mb},  # JSON: Integer 1024 (OHNE Quotes)
  "eta": "${eta}"            # JSON: String "00:05:30" (MIT Quotes)
}
EOF
)
}
```
→ Manuell entschieden: `percent` und `copied_mb` sind Integer (ohne Quotes in JSON)  
→ Manuell entschieden: `eta` ist String (mit Quotes in JSON)

#### Problem für unified config API

**Wenn Caller schreibt:**
```bash
config_set_value_json("status.json", ".port", "1883")
#                                              ^^^^^^
#                                              Bash: Immer String
```

**Was soll in JSON stehen?**
```json
// Variante A: Als Integer (ohne Quotes)
{"port": 1883}

// Variante B: Als String (mit Quotes)
{"port": "1883"}
```

**Beide sind UNTERSCHIEDLICH in JSON!**
- JavaScript/Python: `typeof port` → "number" vs "string"
- JSON-Schema Validierung: Integer vs String
- APIs erwarten oft bestimmten Typ

#### Reales Beispiel aus dem Projekt

**progress.json (aktuell):**
```json
{
  "percent": 0,         // Integer
  "copied_mb": 0,       // Integer
  "total_mb": 0,        // Integer
  "eta": "",           // String
  "timestamp": ""      // String
}
```

**Wenn wir unified API nutzen würden:**
```bash
# Funktioniert das?
config_set_value_json("progress.json", ".percent", "42")

# Schreibt es:
# {"percent": 42}       ← Richtig (Integer)
# oder:
# {"percent": "42"}     ← Falsch (String)
```

#### Lösungsansätze

**Option 1: Type-Heuristik (wie bei .conf)**
```bash
config_set_value_json() {
    local value="$3"
    
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        # Pure Integer - ohne Quotes in JSON
        jq ".${jsonpath} = ${value}" file.json
    elif [[ "$value" =~ ^(true|false)$ ]]; then
        # Boolean - ohne Quotes in JSON
        jq ".${jsonpath} = ${value}" file.json
    elif [[ "$value" == "null" ]]; then
        # JSON null
        jq ".${jsonpath} = null" file.json
    else
        # String - mit Quotes in JSON
        jq ".${jsonpath} = \"${value}\"" file.json
    fi
}
```
**Vorteil:** Automatisch, meistens richtig  
**Nachteil:** String "123" wird zu Integer (nicht unterscheidbar)

**Option 2: Expliziter Type-Parameter**
```bash
config_set_value_json(file, jsonpath, value, type)

# Caller muss Typ angeben:
config_set_value_json("progress.json", ".percent", "42", "integer")
config_set_value_json("progress.json", ".eta", "00:05:30", "string")
config_set_value_json("status.json", ".enabled", "true", "boolean")
```
**Vorteil:** Explizit, keine Mehrdeutigkeit  
**Nachteil:** Mehr Tipparbeit, komplexere Signatur

**Option 3: Separate Funktionen pro Typ**
```bash
config_set_integer_json(file, jsonpath, value)
config_set_string_json(file, jsonpath, value)
config_set_boolean_json(file, jsonpath, value)
config_set_null_json(file, jsonpath)

# Nutzung:
config_set_integer_json("progress.json", ".percent", "42")
config_set_string_json("progress.json", ".eta", "00:05:30")
```
**Vorteil:** Typsicher, selbstdokumentierend  
**Nachteil:** 4× mehr Funktionen für JSON

**Option 4: Nur Type-Heuristik + Escape für Strings**
```bash
# Normal (automatisch):
config_set_value_json("file.json", ".port", "1883")
# → Integer (weil pure Ziffern)

# Erzwinge String mit Präfix:
config_set_value_json("file.json", ".id", "string:123")
# → String "123" (Präfix "string:" entfernt)

# Oder Quote-Flag:
config_set_value_json("file.json", ".id", "123", "quote")
# → String "123"
```

#### Implementierung ✅

**Type-Heuristik (identisch zu .conf Format):**

```bash
config_set_value_json() {
    local module="$1"
    local jsonpath="$2"
    local value="$3"
    
    # JSON kann in conf/ oder api/ liegen - Auto-Detection
    local filepath
    if [[ -f "${INSTALL_DIR}/api/${module}.json" ]]; then
        filepath="${INSTALL_DIR}/api/${module}.json"
    elif [[ -f "${INSTALL_DIR}/conf/${module}.json" ]]; then
        filepath="${INSTALL_DIR}/conf/${module}.json"
    else
        # Default zu api/ für neue Dateien
        filepath="${INSTALL_DIR}/api/${module}.json"
    fi
    
    # Type Detection (GLEICHE Regeln wie config_set_value_conf!)
    if [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        # Integer oder Float - ohne Quotes in JSON
        jq "${jsonpath} = ${value}" "$filepath" > "${filepath}.tmp"
        
    elif [[ "$value" =~ ^(true|false|0|1|yes|no|on|off)$ ]]; then
        # Boolean - normalisieren zu true/false, ohne Quotes in JSON
        case "$value" in
            true|1|yes|on)   value="true" ;;
            false|0|no|off)  value="false" ;;
        esac
        jq "${jsonpath} = ${value}" "$filepath" > "${filepath}.tmp"
        
    elif [[ "$value" == "null" ]]; then
        # JSON null - ohne Quotes
        jq "${jsonpath} = null" "$filepath" > "${filepath}.tmp"
        
    else
        # String - mit Quotes, Escaping nötig
        value="${value//\"/\\\"}"  # Escape existing quotes
        jq "${jsonpath} = \"${value}\"" "$filepath" > "${filepath}.tmp"
    fi
    
    mv -f "${filepath}.tmp" "$filepath"
}
```

**Konsistenz-Regeln (.conf ↔ .json):**

| Eingabe | .conf Ausgabe | .json Ausgabe | Typ |
|---------|--------------|---------------|-----|
| `"1883"` | `PORT=1883` | `"port": 1883` | Integer |
| `"true"` | `ENABLED=true` | `"enabled": true` | Boolean |
| `"0"` | `ENABLED=false` | `"enabled": false` | Boolean (normalisiert) |
| `"My Disc"` | `LABEL="My Disc"` | `"label": "My Disc"` | String |
| `"123-4"` | `ID="123-4"` | `"id": "123-4"` | String |
| `"null"` | N/A | `"value": null` | JSON null |

**Begründung:**
- ✅ Konsistent mit .conf Format (gleiche Heuristik)
- ✅ 95% der Fälle automatisch korrekt
- ✅ JSON wird primär von Bash geschrieben, nicht von Hand
- ✅ Cross-Language Boolean-Support (0/1 → true/false)
- ✅ Sonderfälle (String "123") über Escaping lösbar

**Sonderfälle:**
- String "123" → Caller kann jq direkt nutzen: `jq '.id = "123"'`
- Komplexe Objekte → jq direkt verwenden (API ist für Simple Values)

### 6.6 Validierung ✅ ENTSCHIEDEN

**Entscheidung:** Return 1 bei Fehler, Caller-Verantwortung für Business-Logic

**Strategie:**
```bash
# API macht nur Basis-Validierung:
# - Datei existiert?
# - Key vorhanden (beim Lesen)?
# - Wert ist valider Type (Integer-Format, etc.)?

config_set_value_conf("disk2iso", "MQTT_PORT", "invalid")
# → Return 0 (schreibt String "invalid" mit Quotes)
# → Type-Detection erkennt: nicht Integer, nicht Boolean → String

config_set_value_conf("disk2iso", "MQTT_PORT", "1883")
# → Return 0 (schreibt Integer 1883 ohne Quotes)
# → Business-Logic-Validierung (Port-Range etc.) ist Caller-Verantwortung!
```

**Begründung:**
- Generic API kann Business-Rules nicht kennen
- Validierung in spezifischen Setter-Funktionen (set_mqtt_port, etc.)
- Trennung von Concerns: API = Storage, Setter = Validation

### 6.7 Kommentare in JSON ✅ ENTSCHIEDEN

**Entscheidung:** Keine Kommentar-Unterstützung in JSON

**Rationale:**
- Standard JSON unterstützt keine Kommentare (RFC 8259)
- JSON5/JSONC benötigt spezielle Parser (nicht jq-kompatibel)
- API-Files (status.json, progress.json) brauchen keine Kommentare
- Dokumentation gehört in .md-Files, nicht in JSON

**Konsequenz:**
- `config_add_comment_json()` → Nicht implementiert
- `config_get_comment_json()` → Nicht implementiert
- JSON-Familie hat 9 Funktionen statt 11 (keine Comment-Operations)

### 6.8 Performance ✅ ENTSCHIEDEN

**Entscheidung:** Alle Funktionen in einer Datei (libconfig.sh)

**Begründung:**
- Tool läuft in Single-User-Umgebung (Service + max 4 Web-UI User)
- Performance nicht kritisch
- Start-Zeit: Einmaliges Sourcen beim Service-Start (sekundlich irrelevant)
- Wartbarkeit: Eine Datei einfacher zu pflegen als 3 separate
- Größe: ~33 Funktionen à ~20 Zeilen = ~660 Zeilen (akzeptabel)

**Konsequenz:**
- Keine Aufteilung in libconfig-conf/ini/json.sh
- Kein Lazy-Loading nötig
- libconfig.sh wächst von ~880 auf ~1500 Zeilen

### 6.9 Rückwärts-Kompatibilität ✅ ENTSCHIEDEN

**Entscheidung:** Big-Bang Migration in neuer Version

**Strategie:**
1. **Phase 1:** Unified API komplett implementieren
2. **Phase 2:** Alle bestehenden Aufrufe umschreiben
3. **Phase 3:** Alte Funktionen als deprecated markieren
4. **Phase 4:** Release als neue Major-Version

**Alte Funktionen → Neue API Mapping:**
```bash
# Wird umgeschrieben:
get_ini_value("/opt/disk2iso/conf/libmqtt.ini", "api", "broker")
  → config_get_value_ini("mqtt", "api", "broker")

write_ini_value("/opt/disk2iso/conf/libmqtt.ini", "api", "port", "1883")
  → config_set_value_ini("mqtt", "api", "port", "1883")

set_mqtt_broker("192.168.1.1")
  → config_set_value_conf("disk2iso", "MQTT_BROKER", "192.168.1.1")

# Alte Funktionen als Wrapper (Rückwärts-Kompatibilität):
get_ini_value() {
    local ini_file="$1"
    local section="$2"
    local key="$3"
    
    # Extrahiere Modulnamen aus Pfad: /opt/.../libmqtt.ini → mqtt
    local module=$(basename "$ini_file" .ini | sed 's/^lib//')
    
    config_get_value_ini "$module" "$section" "$key"
}
```

**Begründung:**
- Sauberer Cut, keine Altlasten
- Migration komplett in einer Version
- Einfachere Wartung (kein Dual-API-Support)
- Tool ist nicht in Produktion bei externen Usern (eigenes Projekt)

---

## 7. Nächste Schritte

1. ✅ jq-Dependency klären (ist faktisch Core-Dependency)
2. ✅ **Komplikationen durchgehen und Entscheidungen treffen**
3. ✅ **Implementierungsstrategie definieren**
4. 🔄 **Prototyp .conf Format - Single Value Operations** (in Arbeit)
5. ⏳ Prototyp .conf Format - Array/Section Operations
6. ⏳ INI-Funktionen zu unified API wrappen
7. ⏳ JSON-Funktionen implementieren
8. ⏳ Unit-Tests schreiben
9. ⏳ Dokumentation in `06_Entwickler.md` ergänzen
10. ⏳ Migration bestehender Aufrufe (Big-Bang)
11. ⏳ Code-Review und Refactoring

---

## 8. Implementierungsstrategie

### Phase 1: .conf Format (Einfachste Variante) ✅ Priorität 1

**Rationale:** .conf ist .ini ohne Sections → Kann INI-Logik wiederverwenden

```bash
# .conf ist strukturell ein .ini mit fiktiver Default-Section
# disk2iso.conf:
OUTPUT_DIR="/media/iso"
MQTT_PORT=1883

# Intern behandelt wie .ini:
# [DEFAULT]
# OUTPUT_DIR="/media/iso"
# MQTT_PORT=1883
```

**Implementierung:**
- `config_get_value_conf()` → Eigene Implementierung (Simple Key=Value ohne Sections)
- `config_set_value_conf()` → Eigene Implementierung mit Type-Detection
- `config_del_value_conf()` → sed-basiertes Löschen

**Pfad-Auflösung:**
```bash
# Intern: ${INSTALL_DIR}/conf/${module}.conf
config_get_value_conf("disk2iso", "OUTPUT_DIR")
# → Liest aus: ${INSTALL_DIR}/conf/disk2iso.conf
```

**Funktionen (9 Stück):**
1. `config_get_value_conf(module, key, [default])`
2. `config_set_value_conf(module, key, value)`
3. `config_del_value_conf(module, key)`
4. `config_get_array_conf(module, key)`
5. `config_set_array_conf(module, key, values...)`
6. `config_del_array_conf(module, key)`
7. `config_get_section_conf(module)` → Gibt alle Keys zurück
8. `config_set_section_conf(module, key=val...)` → Bulk-Update
9. `config_del_section_conf(module)` → Löscht alle Keys

### Phase 2: .ini Format (Wrapper um Bestehende) ✅ Priorität 2

**Bestehende Funktionen (behalten für Kompatibilität):**
- `get_ini_value(file, section, key)` → Zeile 639-691
- `write_ini_value(file, section, key, value)` → Zeile 693-753
- `delete_ini_value(file, section, key)` → Zeile 755-806
- `get_ini_array(file, section, key)` → Zeile 808-849
- Weitere Hilfsfunktionen vorhanden

**Neue unified API (KERN-IMPLEMENTIERUNG):**
1. `config_get_value_ini(module, section, key, [default])` → Vollständige awk-Implementierung
2. `config_set_value_ini(module, section, key, value)` → Vollständige awk-Implementierung
3. `config_del_value_ini(module, section, key)` → Vollständige awk-Implementierung
4. `config_get_array_ini(module, section, key)` → Ruft `config_get_value_ini()` + Split
5. `config_set_array_ini(module, section, key, values...)` → Ruft `config_set_value_ini()` + Join
6. `config_del_array_ini(module, section, key)` → Ruft `config_del_value_ini()`
7. `config_get_section_ini(module, section)` → Vollständige awk-Implementierung
8. `config_set_section_ini(module, section, key=val...)` → Bulk-Update via `config_set_value_ini()`
9. `config_del_section_ini(module, section)` → Vollständige awk-Implementierung

**Pfad-Auflösung:**
```bash
# Intern: get_module_ini_path(module) → ${INSTALL_DIR}/conf/lib${module}.ini
config_get_value_ini("mqtt", "api", "broker")
# → get_module_ini_path("mqtt") → ${INSTALL_DIR}/conf/libmqtt.ini
```

**Alte Funktionen (Wrapper für Rückwärts-Kompatibilität):**
```bash
get_ini_value() {
    local ini_file="$1"      # /opt/disk2iso/conf/libmqtt.ini
    local module=$(basename "$ini_file" .ini | sed 's/^lib//')  # → mqtt
    config_get_value_ini "$module" "$2" "$3"
}
```

**Vorteil:** Unified API ist authoritative Implementierung, alte Funktionen delegieren

### Phase 3: .json Format (Neu implementieren) ✅ Priorität 3

**Keine bestehende Implementierung → Komplett neu mit jq**

**Funktionen (9 Stück, keine Comment-Ops):**
1. `config_get_value_json(module, jsonpath, [default])`
2. `config_set_value_json(module, jsonpath, value)` → Type-Heuristik!
3. `config_del_value_json(module, jsonpath)`
4. `config_get_array_json(module, jsonpath)`
5. `config_set_array_json(module, jsonpath, values...)`
6. `config_del_array_json(module, jsonpath)`
7. `config_get_section_json(module, jsonpath)` → Gibt Objekt zurück
8. `config_set_section_json(module, jsonpath, json_string)`
9. `config_del_section_json(module, jsonpath)`

**Pfad-Auflösung (Auto-Detection):**
```bash
# JSON kann in conf/ oder api/ liegen
config_get_value_json("status", ".state")
# 1. Prüft: ${INSTALL_DIR}/api/status.json (bevorzugt)
# 2. Fallback: ${INSTALL_DIR}/conf/status.json

config_get_value_json("progress", ".percent")
# → ${INSTALL_DIR}/api/progress.json
```

### Phase 4: Migration (Big-Bang)

**Alle bestehenden Aufrufe umschreiben:**
```bash
# Alt (mit vollständigem Pfad):
get_ini_value("/opt/disk2iso/conf/libaudio.ini", "dependencies", "optional")
  → config_get_value_ini("audio", "dependencies", "optional")

# Alt (spezifischer Setter):
set_mqtt_broker("192.168.1.1")
  → config_set_value_conf("disk2iso", "MQTT_BROKER", "192.168.1.1")

# Alt (JSON mit jq direkt):
jq '.state = "copying"' api/status.json
  → config_set_value_json("status", ".state", "copying")
```

---

## 9. Referenzen

- **Bestehende INI-Funktionen:** [libconfig.sh:639-849](libconfig.sh)
- **API-Module (nutzt jq):** [libapi.sh:320-327](../lib/libapi.sh)
- **Lazy Initialization Pattern:** [libfolders.sh](../lib/libfolders.sh)
- **CLI-Interface Pattern:** [Modul-CLI-Interface-Pattern.md](Modul-CLI-Interface-Pattern.md)

