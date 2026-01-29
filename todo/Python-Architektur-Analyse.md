# Python-Architektur Analyse - Eigenständige Zugriffe
**Datum**: 29. Januar 2026  
**Problem**: Python greift direkt auf Config-Dateien und externe Tools zu

---

## 🔴 PROBLEM: Python macht eigenständige Zugriffe

### **Architektur-Vorgabe:**
```
Web-UI ← HTTP → Python (Flask) ← JSON-API → Bash (disk2iso.sh)
```

**Python sollte NUR**:
- ✅ JSON-Dateien aus `/opt/disk2iso/api/` lesen (die von Bash geschrieben werden)
- ✅ HTTP-Requests von Web-UI verarbeiten
- ✅ JSON-Responses zurückgeben

**Python sollte NICHT**:
- ❌ disk2iso.conf direkt lesen/schreiben
- ❌ mosquitto_pub direkt aufrufen
- ❌ systemctl direkt aufrufen
- ❌ Externe Tools direkt verwenden

---

## ❌ Aktuelle Verstöße

### **1. MQTT-Modul (routes_mqtt.py)**

#### **Config lesen** (Zeilen 42-65):
```python
with open(CONFIG_FILE, 'r') as f:  # ← DIREKTER ZUGRIFF
    for line in f:
        if line.startswith('MQTT_ENABLED='):
            ...
```
**Problem**: Python liest disk2iso.conf direkt statt JSON-API

#### **Config schreiben** (Zeilen 247-286):
```python
with open(CONFIG_FILE, 'r') as f:  # ← DIREKTER ZUGRIFF
    lines = f.readlines()
# ... Änderungen
with open(CONFIG_FILE, 'w') as f:  # ← DIREKTER ZUGRIFF
    f.writelines(updated_lines)
```
**Problem**: Python schreibt disk2iso.conf direkt statt Bash-Script aufzurufen

#### **MQTT Test** (Zeilen 158-171):
```python
cmd = ['mosquitto_pub', '-h', broker, ...]  # ← DIREKTER ZUGRIFF
result = subprocess.run(cmd, ...)
```
**Problem**: Python ruft mosquitto_pub direkt auf

---

### **2. Core-App (app.py)**

#### **Config lesen** (Zeilen 62-102):
```python
with open(CONFIG_FILE, 'r') as f:  # ← DIREKTER ZUGRIFF
    for line in f:
        if line.startswith('DEFAULT_OUTPUT_DIR='):
            ...
```
**Problem**: Python liest disk2iso.conf direkt

#### **Service-Status** (Zeilen 136-155):
```python
subprocess.run(['/usr/bin/systemctl', 'is-active', ...])  # ← DIREKTER ZUGRIFF
```
**Problem**: Python ruft systemctl direkt auf

#### **Config speichern** (ca. Zeile 993+):
```python
subprocess.run(['bash', script_path], ...)  # ← Teilweise OK
```
**Teilweise**: Ruft Bash-Script auf, aber nur für Config-Speicherung

---

## ✅ Was Python RICHTIG macht

### **JSON-API-Zugriffe** (app.py):
```python
# Status-API lesen
status_file = API_DIR / 'status.json'
with open(status_file, 'r') as f:
    status = json.load(f)

# Progress-API lesen
progress_file = API_DIR / 'progress.json'
with open(progress_file, 'r') as f:
    progress = json.load(f)
```
**✅ RICHTIG**: Python liest JSON-Dateien die von Bash geschrieben wurden

---

## 🎯 SOLL-Architektur für MQTT-Modul

### **Config lesen:**
```python
# VORHER (FALSCH):
def get_mqtt_config():
    with open(CONFIG_FILE, 'r') as f:  # Direkter Zugriff
        ...

# NACHHER (RICHTIG):
def get_mqtt_config():
    # Lese mqtt_config.json (generiert von libmqtt.sh)
    config_file = API_DIR / 'mqtt_config.json'
    with open(config_file, 'r') as f:
        return json.load(f)
```

**Voraussetzung**: libmqtt.sh muss mqtt_config.json generieren

---

### **Config speichern:**
```python
# VORHER (FALSCH):
def api_mqtt_save():
    with open(CONFIG_FILE, 'w') as f:  # Direkter Zugriff
        f.writelines(updated_lines)

# NACHHER (RICHTIG):
def api_mqtt_save():
    # Rufe Bash-Helper auf
    subprocess.run([
        '/opt/disk2iso/lib/libconfig.sh',  # Neues Helper-Script
        'set_mqtt_config',
        json.dumps(config_data)
    ])
```

**Voraussetzung**: libconfig.sh mit `set_mqtt_config()` Funktion

---

### **MQTT Test:**
```python
# VORHER (FALSCH):
def api_mqtt_test():
    subprocess.run(['mosquitto_pub', ...])  # Direkter Zugriff

# NACHHER (RICHTIG):
def api_mqtt_test():
    # Rufe libmqtt.sh Funktion auf
    subprocess.run([
        '/opt/disk2iso/lib/libmqtt.sh',
        'mqtt_test_connection',
        broker, port, user, password
    ])
```

**Voraussetzung**: libmqtt.sh als ausführbares Script mit CLI-Interface

---

## 📋 Erforderliche Änderungen

### **Priorität 1: MQTT-Modul sauber machen**

1. **libmqtt.sh erweitern**:
   - [ ] `mqtt_export_config_json()` - Schreibt mqtt_config.json
   - [ ] `mqtt_test_connection()` - CLI-Interface für Verbindungstest
   - [ ] Als eigenständiges Script ausführbar machen

2. **libconfig.sh erstellen**:
   - [ ] `set_mqtt_enabled()` - Schreibt MQTT_ENABLED in disk2iso.conf
   - [ ] `set_mqtt_broker()` - Schreibt MQTT_BROKER in disk2iso.conf
   - [ ] `set_mqtt_credentials()` - Schreibt MQTT_USER/PASSWORD
   - [ ] Als eigenständiges Script ausführbar machen

3. **routes_mqtt.py anpassen**:
   - [ ] `get_mqtt_config()` → Liest `api/mqtt_config.json`
   - [ ] `api_mqtt_save()` → Ruft `libconfig.sh set_mqtt_*` auf
   - [ ] `api_mqtt_test()` → Ruft `libmqtt.sh mqtt_test_connection` auf

4. **app.py anpassen**:
   - [ ] `get_config()` → Liest `api/system_config.json` (neu)
   - [ ] `get_service_status()` → Liest `api/service_status.json` (neu)
   - [ ] Oder: Ruft `libsysteminfo.sh get_service_status` auf

---

### **Priorität 2: Core-App sauber machen**

1. **libsysteminfo.sh erweitern**:
   - [ ] `export_system_config_json()` - Schreibt system_config.json
   - [ ] `export_service_status_json()` - Schreibt service_status.json
   - [ ] Periodisch aufrufen (z.B. alle 30 Sekunden via Cron/Systemd Timer)

2. **app.py anpassen**:
   - [ ] Alle `open(CONFIG_FILE)` entfernen
   - [ ] Alle `systemctl` Aufrufe entfernen
   - [ ] Nur noch JSON-API lesen

---

## 🤔 Diskussionspunkte

### **1. Wie oft Config-JSON aktualisieren?**

**Option A**: On-Demand
- Python ruft `libconfig.sh export_config_json` bei jedem Request auf
- ➕ Immer aktuell
- ➖ Overhead bei jedem Request

**Option B**: Periodisch (Empfohlen)
- Systemd Timer/Cron ruft alle 30s `export_config_json` auf
- ➕ Effizient
- ➖ Bis zu 30s Verzögerung

**Option C**: Bei Änderung
- Config-Änderung triggert sofort `export_config_json`
- ➕ Immer aktuell, effizient
- ➖ Komplexer (File-Watch oder explizite Calls)

**Empfehlung**: Option C für wichtige Daten (Config), Option B für Status-Daten

---

### **2. Bash-Scripts als CLI ausführbar?**

Aktuell sind lib*.sh nur sourcebar. Für Python-Calls benötigen wir:

```bash
#!/bin/bash
# lib/libmqtt.sh - Kann gesourced ODER direkt ausgeführt werden

# Wenn direkt ausgeführt
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # CLI-Interface
    case "$1" in
        mqtt_test_connection)
            mqtt_test_connection "$2" "$3" "$4" "$5"
            ;;
        export_config_json)
            mqtt_export_config_json
            ;;
        *)
            echo "Usage: $0 {mqtt_test_connection|export_config_json}"
            exit 1
            ;;
    esac
fi
```

---

## 📊 Compliance-Score

| Komponente | Direkte Zugriffe | Score | Status |
|------------|------------------|-------|--------|
| **routes_mqtt.py** | 5 (config read/write, mosquitto_pub) | 20% | 🔴 Kritisch |
| **app.py get_config** | 1 (config read) | 50% | 🟡 Mittel |
| **app.py systemctl** | 2 (service status) | 50% | 🟡 Mittel |
| **app.py JSON-API** | 0 (korrekt) | 100% | ✅ Perfekt |

**Gesamt-Compliance: 55%** - Noch nicht architektur-konform

---

## 🚀 Empfehlung

**Status**: MQTT-Modul ist **funktional perfekt**, aber **architektonisch nicht sauber**.

**Optionen**:

### **Option 1: Aktuellen Stand akzeptieren** (Pragmatisch)
- ➕ Funktioniert einwandfrei
- ➕ Kein Refactoring nötig
- ➖ Architektur-Vorgabe nicht erfüllt
- ➖ Python hat zu viele Verantwortlichkeiten

### **Option 2: Sauber refactoren** (Architektur-konform)
- ➕ Erfüllt Architektur-Vorgabe
- ➕ Klare Verantwortlichkeiten
- ➕ Einfacher zu warten
- ➖ 2-3 Stunden Refactoring
- ➖ Mehr Bash-Code

### **Option 3: Hybrid** (Empfohlen)
- Config lesen: JSON-API (Bash generiert)
- Config schreiben: Bash-Helper aufrufen
- MQTT-Test: Bash-Funktion aufrufen
- Service-Status: JSON-API (Bash generiert)
- ➕ Balance zwischen Aufwand und Architektur
- ➕ Kritische Punkte gelöst
- ➖ Nicht 100% sauber

---

## 🎯 Nächste Schritte

**Wenn Architektur-Konformität wichtig ist**:

1. **Bash-Erweiterungen** (2h):
   - libconfig.sh: Config-Writer-Funktionen
   - libmqtt.sh: CLI-Interface, JSON-Export
   - libsysteminfo.sh: Status-JSON-Export

2. **Python-Refactoring** (1h):
   - routes_mqtt.py: Nur JSON + Bash-Calls
   - app.py: Nur JSON-API

3. **Systemd Timer** (30min):
   - Periodische Status-JSON-Generierung

**Zeitaufwand Gesamt**: ~3.5 Stunden

**Oder**: Aktuellen funktionalen Stand akzeptieren und später refactoren.

Was ist Ihre Präferenz?
