# Field-by-Field Config Management - Implementierung

## Übersicht
Neue Architektur für Core-Module Settings: Jedes Feld speichert automatisch beim Verlassen (onBlur/onChange), kein "Speichern"-Button mehr nötig.

## Implementierte Komponenten

### 1. Python API (routes/routes_config.py)
✅ **GET /api/config/<key>** - Lese einzelnen Config-Wert
✅ **PUT /api/config/<key>** - Schreibe einzelnen Config-Wert + optionaler Service-Restart
✅ **GET /api/config/all** - Legacy Batch-Read (DEPRECATED)

**Unterstützte Keys:**
- `DEFAULT_OUTPUT_DIR` → Restart: disk2iso
- `DDRESCUE_RETRIES` → Restart: none
- `USB_DRIVE_DETECTION_ATTEMPTS` → Restart: none
- `USB_DRIVE_DETECTION_DELAY` → Restart: none

### 2. Shell-Funktionen (lib/libconfig.sh)
✅ **get_config_value(key)** - Wrapper um config_get_value_conf()
✅ **update_config_value(key, value)** - Wrapper um config_set_value_conf()
✅ **get_all_config_values()** - Wrapper für Legacy-Support (DEPRECATED)

### 3. JavaScript API (static/js/config-api.js)
✅ **getConfigValue(key)** - Async read einzelner Wert
✅ **setConfigValue(key, value)** - Async write + Toast-Benachrichtigung
✅ **initConfigField(elementId, configKey, defaultValue)** - Auto-Init Feld mit Events
✅ **showToast(message, type)** - Toast-Benachrichtigungen (success/error/warning/info)
✅ **getAllConfigValues()** - Legacy Batch-Read (DEPRECATED)

### 4. HTML Template (templates/config_new.html)
✅ Beispiel-Implementation mit Core Settings
✅ USB Detection Settings
✅ Automatische Speicherung onBlur/onChange
✅ Optional: Saving-Indicator während Speichern

## Workflow

### Alt (Batch):
```
1. Seite lädt → get_all_config_values() → ALLE Felder
2. User editiert mehrere Felder
3. "Speichern" Button → save_config_and_restart() → Batch-Update + Neustart
```

### Neu (Field-by-Field):
```
1. Seite lädt → Für JEDES Feld: getConfigValue(key) via initConfigField()
2. User editiert EIN Feld → onBlur/onChange Event
3. Sofort: setConfigValue(key, value) → Einzelwert speichern
4. Optional: Service-Restart nur bei kritischen Feldern (DEFAULT_OUTPUT_DIR)
5. Toast-Benachrichtigung: "Gespeichert" oder "Gespeichert (disk2iso neu gestartet)"
```

## Beispiel-Nutzung

### HTML:
```html
<input type="text" id="output-dir" />
<input type="number" id="ddrescue-retries" />
<select id="usb-attempts">
  <option value="5">5</option>
  <option value="10">10</option>
</select>

<script src="/static/js/config-api.js"></script>
<script>
document.addEventListener('DOMContentLoaded', async () => {
    await initConfigField('output-dir', 'DEFAULT_OUTPUT_DIR', '/media/iso');
    await initConfigField('ddrescue-retries', 'DDRESCUE_RETRIES', '3');
    await initConfigField('usb-attempts', 'USB_DRIVE_DETECTION_ATTEMPTS', '5');
});
</script>
```

### Python (manuell):
```python
# Lesen
response = requests.get('/api/config/DEFAULT_OUTPUT_DIR')
data = response.json()
# {"success": true, "value": "/media/iso"}

# Schreiben
response = requests.put('/api/config/DEFAULT_OUTPUT_DIR', 
                       json={'value': '/new/path'})
data = response.json()
# {"success": true, "restart_required": true, "restart_service": "disk2iso"}
```

### Bash (direkt):
```bash
source /opt/disk2iso/lib/libconfig.sh

# Lesen
get_config_value "DEFAULT_OUTPUT_DIR"
# {"success": true, "value": "/media/iso"}

# Schreiben
update_config_value "DEFAULT_OUTPUT_DIR" "/new/path"
# {"success": true}
```

## Integration

### App.py Blueprint-Registrierung:
```python
# Core Config API (field-by-field)
from routes import config_bp
app.register_blueprint(config_bp)
```

### Routes __init__.py:
```python
from .routes_config import config_bp
__all__ = ['config_bp', 'mqtt_bp']
```

## Nächste Schritte für optionale Module

Wenn ein optionales Modul eigene Config-Felder hat (z.B. MQTT, TMDB):

1. **Eigene Routes erstellen**: `routes_mqtt.py` → `/api/mqtt/<key>`
2. **Module-spezifische Keys**: Nutze `config_get_value_ini()` für .ini-Dateien
3. **JavaScript Injection**: Modul injiziert eigene Felder ins DOM
4. **Gleiche API-Pattern**: `initConfigField('mqtt-broker', 'MQTT_BROKER', 'localhost')`

## Vorteile

✅ **Keine verlorenen Änderungen** - Sofortige Speicherung
✅ **Bessere UX** - Kein manuelles Speichern nötig
✅ **Granulare Restarts** - Nur bei kritischen Feldern
✅ **Erweiterbar** - Module können eigene Felder injizieren
✅ **Type-Safe** - Automatische Type-Detection (Integer/Boolean/String)
✅ **Self-Healing** - Defaults werden automatisch gespeichert
✅ **Toast-Feedback** - User sieht sofort ob gespeichert wurde

## Dateien

| Datei | Status | Beschreibung |
|-------|--------|--------------|
| `www/routes/routes_config.py` | ✅ NEU | Python Blueprint für Config-API |
| `www/routes/__init__.py` | ✅ UPDATED | Blueprint-Export |
| `www/app.py` | ✅ UPDATED | Blueprint-Registrierung |
| `www/static/js/config-api.js` | ✅ NEU | JavaScript API + Utils |
| `www/templates/config_new.html` | ✅ NEU | Beispiel-Template |
| `lib/libconfig.sh` | ✅ READY | Shell-API (bereits vorhanden) |
