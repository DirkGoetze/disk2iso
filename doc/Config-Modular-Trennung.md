# Config-Modularisierung - Variante A (Radikale Trennung)

## Datum: 03.02.2026

## Übersicht

Komplette Trennung von Core-Settings und Modul-Settings durch Migration zu dezentralen INI-Dateien.

## Architektur

```
┌─────────────────────────────────────────────────────────────┐
│                    disk2iso.conf (CORE ONLY)                 │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ DEFAULT_OUTPUT_DIR="/media/iso"                        │  │
│  │ DDRESCUE_RETRIES=1                                     │  │
│  │ USB_DRIVE_DETECTION_ATTEMPTS=5                         │  │
│  │ USB_DRIVE_DETECTION_DELAY=10                           │  │
│  │ LANGUAGE="de"                                          │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ├── Keine Modul-Settings mehr!
                            ├── Nur Core-Framework-Einstellungen
                            └── Minimale Abhängigkeiten
                            
┌─────────────────────────────────────────────────────────────┐
│                  MODULE INI-DATEIEN (AUTONOM)                │
├─────────────────────────────────────────────────────────────┤
│  conf/libaudio.ini                                           │
│    [module]                                                  │
│    enabled=true                                              │
│    name=audio                                                │
│    version=1.2.0                                             │
│    [encoding]                                                │
│    mp3_quality=2                                             │
├─────────────────────────────────────────────────────────────┤
│  conf/libmqtt.ini                                            │
│    [module]                                                  │
│    enabled=false                                             │
│    [api]                                                     │
│    broker=192.168.1.100                                      │
│    port=1883                                                 │
├─────────────────────────────────────────────────────────────┤
│  conf/libmetadata.ini                                        │
│    [metadata]                                                │
│    enabled=true                                              │
│    [framework]                                               │
│    selection_timeout=60                                      │
├─────────────────────────────────────────────────────────────┤
│  conf/libdvd.ini                                             │
│    [module]                                                  │
│    enabled=true                                              │
├─────────────────────────────────────────────────────────────┤
│  conf/libbluray.ini                                          │
│    [module]                                                  │
│    enabled=true                                              │
└─────────────────────────────────────────────────────────────┘
```

## Durchgeführte Änderungen

### 1. disk2iso.conf bereinigt
**Datei:** `conf/disk2iso.conf`

**ENTFERNT:**
- ❌ MQTT_ENABLED, MQTT_BROKER, MQTT_PORT, MQTT_USER, MQTT_PASSWORD, MQTT_TOPIC_PREFIX, MQTT_CLIENT_ID, MQTT_QOS, MQTT_RETAIN
- ❌ TMDB_API_KEY
- ❌ MP3_QUALITY
- ❌ METADATA_ENABLED, METADATA_AUDIO_PROVIDER, METADATA_VIDEO_PROVIDER, METADATA_SELECTION_TIMEOUT

**BEHALTEN:**
- ✅ DEFAULT_OUTPUT_DIR
- ✅ DDRESCUE_RETRIES
- ✅ USB_DRIVE_DETECTION_ATTEMPTS
- ✅ USB_DRIVE_DETECTION_DELAY
- ✅ LANGUAGE

### 2. INI-Dateien mit enabled-Flag ausgestattet

**libmqtt.ini:**
```ini
[module]
name=mqtt
version=1.2.0
enabled=false  # ← NEU
```

**libaudio.ini:**
```ini
[module]
name=audio
version=1.2.0
enabled=true  # ← NEU
```

**libdvd.ini:**
```ini
[module]
name=dvd
version=1.2.0
enabled=true  # ← NEU
```

**libbluray.ini:**
```ini
[module]
name=bluray
version=1.2.0
enabled=true  # ← NEU
```

**libmetadata.ini:**
```ini
[metadata]
enabled=true  # ← Bereits vorhanden
```

### 3. app.py - `/api/modules` liest aus INI-Dateien
**Datei:** `www/app.py`

**VORHER:**
```python
config = get_config()
enabled_modules = {
    'metadata': config.get('metadata_enabled', True),  # ← Aus disk2iso.conf
    'cd': config.get('cd_enabled', True),
    # ...
}
```

**NACHHER:**
```python
def get_module_enabled(module_name, default=True):
    result = subprocess.run([
        'bash', '-c', 
        f'source {INSTALL_DIR}/lib/libconfig.sh && config_get_value_ini "{module_name}" "module" "enabled" "{str(default).lower()}"'
    ], capture_output=True, text=True, timeout=2)
    return result.stdout.strip().lower() in ['true', '1', 'yes', 'on']

enabled_modules = {
    'metadata': get_module_enabled('metadata', True),  # ← Aus libmetadata.ini
    'audio': get_module_enabled('audio', True),        # ← Aus libaudio.ini
    'dvd': get_module_enabled('dvd', True),            # ← Aus libdvd.ini
    'bluray': get_module_enabled('bluray', True),      # ← Aus libbluray.ini
    'mqtt': get_module_enabled('mqtt', False),         # ← Aus libmqtt.ini
}
```

### 4. libconfig.sh - get_all_config_values() bereinigt
**Datei:** `lib/libconfig.sh`

**Kommentar aktualisiert:**
```bash
# NOTE: DEPRECATED - Nur noch für Core-Settings (disk2iso.conf)
#       Module lesen ihre Konfiguration aus eigenen INI-Dateien
```

**Nur noch Core-Settings:**
```bash
local output_dir=$(config_get_value_conf "disk2iso" "DEFAULT_OUTPUT_DIR" "" 2>/dev/null)
local ddrescue_retries=$(config_get_value_conf "disk2iso" "DDRESCUE_RETRIES" "3" 2>/dev/null)
local usb_attempts=$(config_get_value_conf "disk2iso" "USB_DRIVE_DETECTION_ATTEMPTS" "5" 2>/dev/null)
local usb_delay=$(config_get_value_conf "disk2iso" "USB_DRIVE_DETECTION_DELAY" "10" 2>/dev/null)
```

## Vorteile

### ✅ Vollständige Modularität
- Jedes Modul kann unabhängig aktiviert/deaktiviert werden
- Keine Abhängigkeit von disk2iso.conf
- Modul-Dateien sind self-contained

### ✅ Klare Verantwortlichkeiten
- **disk2iso.conf** = Core-Framework (Output-Dir, Hardware, Sprache)
- **lib*.ini** = Modul-spezifische Settings (Features, API-Keys, Encoding)

### ✅ Einfache Modul-Installation
```bash
# Neues Modul installieren
cp libneues.ini /opt/disk2iso/conf/
# → Modul ist sofort aktiv (wenn enabled=true)
```

### ✅ Konsistent mit Plugin-Architektur
- Frontend-Modularisierung.md: ✅ Module werden per INI gesteuert
- Metadata-PlugIn_Konzept.md: ✅ Provider haben eigene INI-Dateien
- Alle Module folgen gleichem Pattern

## Verwendung

### Modul aktivieren/deaktivieren

**Via Bash:**
```bash
# Audio-Modul deaktivieren
config_set_value_ini "audio" "module" "enabled" "false"

# MQTT-Modul aktivieren
config_set_value_ini "mqtt" "module" "enabled" "true"
```

**Via Python (Web-API):**
```python
subprocess.run([
    'bash', '-c',
    'source /opt/disk2iso/lib/libconfig.sh && config_set_value_ini "mqtt" "module" "enabled" "true"'
])
```

### Modul-Status abfragen

**Via Web-API:**
```bash
curl http://localhost:5000/api/modules | jq
{
  "enabled_modules": {
    "metadata": true,
    "audio": true,
    "dvd": true,
    "bluray": true,
    "mqtt": false
  },
  "timestamp": "2026-02-03T14:30:00"
}
```

### Modul-Settings lesen

**Beispiel: MQTT Broker:**
```bash
config_get_value_ini "mqtt" "api" "broker" "192.168.1.1"
# → 192.168.1.100
```

**Beispiel: MP3 Qualität:**
```bash
config_get_value_ini "audio" "encoding" "mp3_quality" "2"
# → 2
```

## Migration bestehender Code

### ❌ ALT (disk2iso.conf):
```bash
MQTT_ENABLED=true
MQTT_BROKER="192.168.1.100"
TMDB_API_KEY="xyz123"
MP3_QUALITY=2
```

### ✅ NEU (INI-Dateien):
```bash
# libmqtt.ini
[module]
enabled=true
[api]
broker=192.168.1.100

# libtmdb.ini
[api]
api_key=xyz123

# libaudio.ini
[encoding]
mp3_quality=2
```

## Nächste Schritte

1. **Web-UI aktualisieren:**
   - Config-Seite zeigt nur noch Core-Settings
   - Modul-spezifische Tabs lesen aus INI-Dateien

2. **Bash-Scripts migrieren:**
   - Alle `grep MQTT_ENABLED` durch `config_get_value_ini "mqtt" "module" "enabled"` ersetzen
   - Alle `grep MP3_QUALITY` durch `config_get_value_ini "audio" "encoding" "mp3_quality"` ersetzen

3. **get_config() in app.py entfernen:**
   - Funktion parst noch disk2iso.conf
   - Nach Migration nicht mehr benötigt

4. **Tests:**
   - Module einzeln aktivieren/deaktivieren
   - Frontend lädt nur benötigte JS-Dateien
   - Einstellungen persistieren korrekt

## Siehe auch

- [Frontend-Modularisierung.md](Frontend-Modularisierung.md) - Dynamisches JS-Loading
- [Metadata-PlugIn_Konzept.md](Metadata-PlugIn_Konzept.md) - Provider-Architektur
- [Field-by-Field_Config_Implementation.md](Field-by-Field_Config_Implementation.md) - Config-API
