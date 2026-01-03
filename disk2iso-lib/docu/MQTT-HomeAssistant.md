# Home Assistant MQTT Sensor Configuration für disk2iso

## Installation

### 1. MQTT Broker
Stelle sicher, dass ein MQTT Broker läuft (z.B. Mosquitto in Home Assistant).

### 2. disk2iso Konfiguration

Bearbeite `/usr/local/bin/disk2iso-lib/config.sh`:

```bash
# MQTT aktivieren
MQTT_ENABLED=true

# MQTT Broker (Home Assistant IP)
MQTT_BROKER="192.168.20.10"
MQTT_PORT=1883

# Optional: Authentifizierung
MQTT_USER="disk2iso"
MQTT_PASSWORD="dein-passwort"

# Topic-Präfix (Standard)
MQTT_TOPIC_PREFIX="homeassistant/sensor/disk2iso"
```

### 3. Home Assistant Konfiguration

Füge folgendes in `configuration.yaml` ein:

```yaml
# disk2iso MQTT Integration
mqtt:
  sensor:
    # Status Sensor
    - name: "Disk2ISO Status"
      unique_id: "disk2iso_status"
      state_topic: "homeassistant/sensor/disk2iso/state"
      value_template: "{{ value_json.status }}"
      json_attributes_topic: "homeassistant/sensor/disk2iso/attributes"
      availability_topic: "homeassistant/sensor/disk2iso/availability"
      icon: mdi:disc
      
    # Fortschritt Sensor
    - name: "Disk2ISO Fortschritt"
      unique_id: "disk2iso_progress"
      state_topic: "homeassistant/sensor/disk2iso/progress"
      unit_of_measurement: "%"
      availability_topic: "homeassistant/sensor/disk2iso/availability"
      icon: mdi:progress-clock

# Optional: Binary Sensor für "ist aktiv"
binary_sensor:
  - platform: mqtt
    name: "Disk2ISO Aktiv"
    unique_id: "disk2iso_active"
    state_topic: "homeassistant/sensor/disk2iso/state"
    value_template: >
      {% if value_json.status == 'copying' %}
        ON
      {% else %}
        OFF
      {% endif %}
    availability_topic: "homeassistant/sensor/disk2iso/availability"
    device_class: running
```

### 4. Automatisierungen

Erstelle `automations.yaml` Einträge:

```yaml
# Benachrichtigung bei Medium bereit
- alias: "Disk2ISO - Medium entfernen"
  trigger:
    - platform: mqtt
      topic: "homeassistant/sensor/disk2iso/state"
      value_template: "{{ value_json.status }}"
      payload: "waiting"
  action:
    - service: notify.mobile_app_smartphone
      data:
        title: "💿 DVD bereit"
        message: "{{ state_attr('sensor.disk2iso_status', 'disc_label') }} erfolgreich kopiert. Bitte Medium entfernen."
        data:
          notification_icon: mdi:disc
          color: green

# Benachrichtigung bei Kopierstart
- alias: "Disk2ISO - Kopie gestartet"
  trigger:
    - platform: mqtt
      topic: "homeassistant/sensor/disk2iso/state"
      value_template: "{{ value_json.status }}"
      payload: "copying"
  action:
    - service: notify.mobile_app_smartphone
      data:
        title: "💿 DVD wird kopiert"
        message: "{{ state_attr('sensor.disk2iso_status', 'disc_label') }} ({{ state_attr('sensor.disk2iso_status', 'disc_type') }})"
        data:
          notification_icon: mdi:disc-player
          color: blue

# Benachrichtigung bei Abschluss
- alias: "Disk2ISO - Kopie abgeschlossen"
  trigger:
    - platform: mqtt
      topic: "homeassistant/sensor/disk2iso/state"
      value_template: "{{ value_json.status }}"
      payload: "completed"
  action:
    - service: notify.mobile_app_smartphone
      data:
        title: "✅ DVD-Kopie fertig"
        message: "{{ state_attr('sensor.disk2iso_status', 'filename') }} wurde erstellt."
        data:
          notification_icon: mdi:check-circle
          color: green
          
# Benachrichtigung bei Fehler
- alias: "Disk2ISO - Fehler"
  trigger:
    - platform: mqtt
      topic: "homeassistant/sensor/disk2iso/state"
      value_template: "{{ value_json.status }}"
      payload: "error"
  action:
    - service: notify.mobile_app_smartphone
      data:
        title: "❌ Disk2ISO Fehler"
        message: "{{ state_attr('sensor.disk2iso_status', 'error_message') }}"
        data:
          notification_icon: mdi:alert-circle
          color: red
```

### 5. Lovelace Dashboard Card

Erstelle eine Card in deinem Dashboard:

```yaml
type: vertical-stack
cards:
  # Titel
  - type: markdown
    content: |
      ## 💿 Disk2ISO

  # Status Card
  - type: entities
    entities:
      - entity: sensor.disk2iso_status
        name: Status
        icon: mdi:disc
      - entity: binary_sensor.disk2iso_active
        name: Aktiv
        
  # Fortschritt (nur wenn copying)
  - type: conditional
    conditions:
      - entity: sensor.disk2iso_status
        state: "copying"
    card:
      type: gauge
      entity: sensor.disk2iso_progress
      min: 0
      max: 100
      name: Fortschritt
      needle: true
      severity:
        green: 75
        yellow: 25
        red: 0
        
  # Details Card
  - type: markdown
    content: |
      **Medium:** {{ state_attr('sensor.disk2iso_status', 'disc_label') or 'Kein Medium' }}  
      **Typ:** {{ state_attr('sensor.disk2iso_status', 'disc_type') or '-' }}  
      **Größe:** {{ state_attr('sensor.disk2iso_status', 'disc_size_mb') or 0 }} MB  
      
      {% if is_state('sensor.disk2iso_status', 'copying') %}
      **Fortschritt:** {{ state_attr('sensor.disk2iso_status', 'progress_mb') }} / {{ state_attr('sensor.disk2iso_status', 'total_mb') }} MB  
      **Verbleibend:** {{ state_attr('sensor.disk2iso_status', 'eta') }}  
      **Methode:** {{ state_attr('sensor.disk2iso_status', 'method') }}
      {% endif %}
      
      {% if is_state('sensor.disk2iso_status', 'completed') %}
      **Datei:** {{ state_attr('sensor.disk2iso_status', 'filename') }}
      {% endif %}
      
      {% if is_state('sensor.disk2iso_status', 'error') %}
      **Fehler:** {{ state_attr('sensor.disk2iso_status', 'error_message') }}
      {% endif %}
```

## MQTT Topics Übersicht

| Topic | Payload | Beschreibung |
|-------|---------|--------------|
| `.../availability` | `online` / `offline` | disk2iso Service Status |
| `.../state` | JSON (status, timestamp) | Aktueller Status (idle, copying, waiting, completed, error) |
| `.../progress` | `0` bis `100` | Fortschritt in Prozent |
| `.../attributes` | JSON (alle Details) | Medium-Infos, Fortschritt, ETA, Fehler |

## Status-Werte

- **idle**: Warten auf Medium
- **copying**: Kopiervorgang läuft
- **waiting**: Kopie fertig, Medium kann entfernt werden
- **completed**: Erfolgreich abgeschlossen
- **error**: Fehler aufgetreten

## Testen

```bash
# MQTT Messages manuell überwachen
mosquitto_sub -h 192.168.20.10 -t "homeassistant/sensor/disk2iso/#" -v

# Test-Nachricht senden
mosquitto_pub -h 192.168.20.10 \
  -t "homeassistant/sensor/disk2iso/state" \
  -m '{"status":"copying","timestamp":"2026-01-03T12:00:00"}'
```

## Troubleshooting

### MQTT wird nicht gesendet
```bash
# Prüfe mosquitto_pub
which mosquitto_pub

# Installiere mosquitto-clients
sudo apt install mosquitto-clients

# Prüfe Log
tail -f /srv/iso/.log/*.log | grep MQTT

# Teste Broker-Verbindung
mosquitto_pub -h 192.168.20.10 -t "test" -m "hello"
```

### Sensoren erscheinen nicht in HA
```bash
# Prüfe configuration.yaml Syntax
ha core check

# Restart Home Assistant
ha core restart

# Prüfe MQTT Integration
ha addons info core_mosquitto
```

### Keine Benachrichtigungen
- Prüfe Mobile App Integration
- Prüfe `notify.mobile_app_*` Service-Namen
- Teste manuell: Developer Tools → Services → notify.mobile_app

## Erweiterte Features

### Persistente Historie
```yaml
# configuration.yaml
recorder:
  include:
    entities:
      - sensor.disk2iso_status
      - sensor.disk2iso_progress
      - binary_sensor.disk2iso_active
```

### Statistiken
```yaml
# configuration.yaml
sensor:
  - platform: history_stats
    name: Disk2ISO Kopierzeit heute
    entity_id: binary_sensor.disk2iso_active
    state: "on"
    type: time
    start: "{{ now().replace(hour=0, minute=0, second=0) }}"
    end: "{{ now() }}"
```
