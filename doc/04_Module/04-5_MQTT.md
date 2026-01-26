# Kapitel 4.5: MQTT-Integration

Home Assistant Integration via MQTT für Echtzeit-Status, Benachrichtigungen und Dashboard.

## Inhaltsverzeichnis

1. [Übersicht](#übersicht)
2. [MQTT-Broker Setup](#mqtt-broker-setup)
3. [disk2iso Konfiguration](#disk2iso-konfiguration)
4. [MQTT-Topics](#mqtt-topics)
5. [Home Assistant Integration](#home-assistant-integration)
6. [Benachrichtigungen](#benachrichtigungen)
7. [Dashboard-Karten](#dashboard-karten)
8. [Troubleshooting](#troubleshooting)

---

## Übersicht

### Was ist MQTT?

**MQTT (Message Queuing Telemetry Transport)** ist ein leichtgewichtiges Publish/Subscribe-Protokoll:

- **Broker-basiert**: Zentraler Server (z.B. Mosquitto)
- **Topics**: Hierarchische Nachrichten-Kanäle
- **Publish/Subscribe**: Sender (disk2iso) publiziert, Empfänger (Home Assistant) abonniert
- **Real-time**: Instant-Updates (kein Polling)

### Warum MQTT für disk2iso?

#### 📡 Echtzeit-Status

**Ohne MQTT**:
- Web-Interface muss Polling verwenden (alle 5s)
- Keine Push-Benachrichtigungen
- Nur lokal nutzbar

**Mit MQTT**:
- Instant-Updates an Home Assistant
- Push-Benachrichtigungen auf Handy
- Status-Tracking im Dashboard
- Automatisierungen möglich

#### 🏠 Home Assistant Integration

**Home Assistant** ist die beliebteste Open-Source Home-Automation-Plattform:

- **100+ Integrationen**: Lichter, Sensoren, Kameras, Media-Player
- **Automatisierungen**: "Wenn DVD fertig → Benachrichtigung senden"
- **Dashboard**: Übersicht aller Smart-Home-Geräte
- **Mobile App**: iOS/Android mit Push-Benachrichtigungen

#### 🔔 Praktische Anwendungsfälle

1. **Push-Benachrichtigung**: DVD fertig → Nachricht auf Handy
2. **Dashboard**: Live-Fortschrittsanzeige während Kopiervorgang
3. **Automatisierung**: Wenn Kopie fertig → Licht blinken lassen
4. **Historie**: Statistiken über archivierte Medien

---

## MQTT-Broker Setup

### Mosquitto auf Home Assistant

**Installation** (als Add-on):

1. Home Assistant öffnen: `http://homeassistant.local:8123`
2. **Einstellungen** → **Add-ons** → **Add-on Store**
3. Suche: **"Mosquitto broker"**
4. **Installieren** → **Starten** → **Bei Boot starten** aktivieren

**MQTT-Integration hinzufügen**:

1. **Einstellungen** → **Geräte & Dienste** → **Integration hinzufügen**
2. Suche: **"MQTT"**
3. Standardeinstellungen übernehmen:
   - Broker: `localhost` (oder IP von Home Assistant)
   - Port: `1883`

### Authentifizierung (Optional, empfohlen)

**Mosquitto Broker-Logins**:

1. **Add-ons** → **Mosquitto broker** → **Konfiguration**
2. YAML-Modus:
   ```yaml
   logins:
     - username: disk2iso
       password: disk2iso_secure_password
   ```
3. **Speichern** → **Mosquitto neu starten**

### Mosquitto auf eigenem Server

**Installation** (Debian/Ubuntu):

```bash
sudo apt update
sudo apt install mosquitto mosquitto-clients

# Service starten
sudo systemctl enable mosquitto
sudo systemctl start mosquitto
```

**Authentifizierung** (optional):

```bash
# Passwort-Datei erstellen
sudo mosquitto_passwd -c /etc/mosquitto/passwd disk2iso

# mosquitto.conf bearbeiten
sudo nano /etc/mosquitto/mosquitto.conf
```

Hinzufügen:
```
allow_anonymous false
password_file /etc/mosquitto/passwd
```

```bash
# Service neu starten
sudo systemctl restart mosquitto
```

### Firewall

**Port 1883 öffnen** (falls Firewall aktiv):

```bash
sudo ufw allow 1883/tcp
```

---

## disk2iso Konfiguration

### Automatische Konfiguration (Installer)

**Während Installation**:

```bash
sudo ./install.sh
```

**Seite 7/9 - MQTT-Konfiguration**:

```
═══════════════════════════════════════════════════════════
            MQTT-INTEGRATION (Optional)
═══════════════════════════════════════════════════════════

MQTT aktivieren? [j/n]: j
MQTT Broker IP-Adresse [192.168.1.100]: 192.168.20.10
MQTT Port [1883]: 1883
MQTT Benutzername (leer für anonym): disk2iso
MQTT Passwort: ****************
```

### Manuelle Konfiguration

**Datei**: `/opt/disk2iso/lib/config.sh`

```bash
# ═══════════════════════════════════════════════════════════
#  MQTT-KONFIGURATION
# ═══════════════════════════════════════════════════════════

# MQTT aktivieren
readonly MQTT_ENABLED=true

# Broker-Einstellungen
readonly MQTT_BROKER="192.168.20.10"    # Home Assistant IP
readonly MQTT_PORT=1883

# Authentifizierung (optional)
readonly MQTT_USER="disk2iso"
readonly MQTT_PASSWORD="disk2iso_secure_password"

# Topic-Präfix
readonly MQTT_TOPIC_PREFIX="homeassistant/sensor/disk2iso"

# Publish-Intervalle
readonly MQTT_PROGRESS_INTERVAL=10      # Sekunden (Fortschritt)
readonly MQTT_HEARTBEAT_INTERVAL=60     # Sekunden (Availability)
```

**Service neu starten**:

```bash
sudo systemctl restart disk2iso
```

### Dependencies prüfen

**mosquitto_pub erforderlich**:

```bash
# Prüfen
which mosquitto_pub

# Falls nicht installiert
sudo apt install mosquitto-clients
```

---

## MQTT-Topics

### Topic-Hierarchie

```
homeassistant/sensor/disk2iso/
├── availability          # online/offline
├── state                 # Status + Timestamp
├── progress              # Fortschritt 0-100%
└── attributes            # Alle Metadaten (JSON)
```

### availability

**Beschreibung**: Service Online-Status

**Payload**:
- `online` - disk2iso Service läuft
- `offline` - Service gestoppt

**Publish**:
- Bei Service-Start: `online`
- Bei Service-Stop: `offline` (via LWT - Last Will Testament)
- Heartbeat alle 60 Sekunden: `online`

**Beispiel**:
```bash
homeassistant/sensor/disk2iso/availability
→ "online"
```

### state

**Beschreibung**: Aktueller Workflow-Status

**Payload** (JSON):
```json
{
  "status": "copying",
  "timestamp": "2026-01-26T14:30:22+01:00"
}
```

**Status-Werte**:
- `idle` - Warten auf Medium
- `analyzing` - Disc-Typ wird erkannt
- `copying` - Kopiervorgang läuft
- `completed` - Erfolgreich abgeschlossen
- `waiting` - Disc kann entfernt werden
- `error` - Fehler aufgetreten
- `waiting_user_input` - MusicBrainz/TMDB Auswahl erforderlich

**Beispiel**:
```bash
homeassistant/sensor/disk2iso/state
→ {"status":"copying","timestamp":"2026-01-26T14:30:22+01:00"}
```

### progress

**Beschreibung**: Fortschritt in Prozent

**Payload**: `0` bis `100`

**Publish**:
- Alle 10 Sekunden (wenn Änderung ≥1%)
- Bei 0%, 25%, 50%, 75%, 100% (immer)

**Beispiel**:
```bash
homeassistant/sensor/disk2iso/progress
→ "45"
```

### attributes

**Beschreibung**: Vollständige Metadaten

**Payload** (JSON):
```json
{
  "disc_label": "THE_MATRIX",
  "disc_type": "dvd-video",
  "disc_size_mb": 7500,
  "filename": "/srv/disk2iso/dvd/THE_MATRIX.iso",
  "method": "dvdbackup",
  "progress_mb": 3375,
  "total_mb": 7500,
  "progress_percent": 45,
  "eta": "00:12:34",
  "speed_mbps": 4.2,
  "error_message": "",
  "timestamp": "2026-01-26T14:30:22+01:00"
}
```

**Felder** (wenn verfügbar):

| Feld | Typ | Beschreibung |
|------|-----|--------------|
| `disc_label` | String | Disc-Name |
| `disc_type` | String | audio-cd, dvd-video, bd-video, cd-rom, dvd-rom, bd-rom |
| `disc_size_mb` | Number | Größe in MB |
| `filename` | String | Ausgabe-Datei |
| `method` | String | dd, ddrescue, dvdbackup, cdparanoia |
| `progress_mb` | Number | Kopierte MB |
| `total_mb` | Number | Gesamt MB |
| `progress_percent` | Number | Prozent (0-100) |
| `eta` | String | Verbleibende Zeit (HH:MM:SS) |
| `speed_mbps` | Number | Geschwindigkeit (MB/s) |
| `error_message` | String | Fehlermeldung (falls error) |

**Beispiel**:
```bash
homeassistant/sensor/disk2iso/attributes
→ {"disc_label":"THE_MATRIX","disc_type":"dvd-video",...}
```

---

## Home Assistant Integration

### Sensoren konfigurieren

**Datei**: `configuration.yaml`

> 💡 **Vollständige Beispielkonfiguration**: [samples/homeassistant-configuration.yaml](../../samples/homeassistant-configuration.yaml)

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

# Binary Sensor für "ist aktiv"
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

**Nach Bearbeitung**:

1. **Entwicklerwerkzeuge** → **YAML** → **YAML-Konfiguration prüfen**
2. Bei ✅: **Alle YAML-Konfigurationen neu laden**
3. Warte 30 Sekunden

**Prüfen**:

1. **Einstellungen** → **Geräte & Dienste** → **Entitäten**
2. Suche: `disk2iso`
3. Sollte zeigen:
   - `sensor.disk2iso_status`
   - `sensor.disk2iso_fortschritt`
   - `binary_sensor.disk2iso_aktiv`

### Attribute nutzen

**In Templates**:

```jinja
{{ state_attr('sensor.disk2iso_status', 'disc_label') }}
→ "THE_MATRIX"

{{ state_attr('sensor.disk2iso_status', 'disc_type') }}
→ "dvd-video"

{{ state_attr('sensor.disk2iso_status', 'progress_mb') }}
→ 3375

{{ state_attr('sensor.disk2iso_status', 'eta') }}
→ "00:12:34"
```

---

## Benachrichtigungen

### Mobile App Setup

**App installieren**:
- **iOS**: [Home Assistant Companion](https://apps.apple.com/app/home-assistant/id1099568401)
- **Android**: [Home Assistant Companion](https://play.google.com/store/apps/details?id=io.homeassistant.companion.android)

**Service-Namen finden**:

1. **Entwicklerwerkzeuge** → **Dienste**
2. Suche: `notify`
3. Beispiele: `notify.mobile_app_iphone`, `notify.mobile_app_pixel_7`

### Automatisierungen

**Datei**: `automations.yaml`

#### Kopie gestartet

```yaml
- alias: "Disk2ISO - Kopie gestartet"
  trigger:
    - platform: mqtt
      topic: "homeassistant/sensor/disk2iso/state"
      value_template: "{{ value_json.status }}"
      payload: "copying"
  action:
    - service: notify.mobile_app_iphone  # ⚠️ Anpassen!
      data:
        title: "💿 DVD wird kopiert"
        message: >
          {{ state_attr('sensor.disk2iso_status', 'disc_label') }}
          ({{ state_attr('sensor.disk2iso_status', 'disc_type') }})
        data:
          notification_icon: mdi:disc-player
          color: blue
```

#### Kopie abgeschlossen

```yaml
- alias: "Disk2ISO - Kopie abgeschlossen"
  trigger:
    - platform: mqtt
      topic: "homeassistant/sensor/disk2iso/state"
      value_template: "{{ value_json.status }}"
      payload: "completed"
  action:
    - service: notify.mobile_app_iphone
      data:
        title: "✅ DVD-Kopie fertig"
        message: >
          {{ state_attr('sensor.disk2iso_status', 'filename') }}
          ({{ state_attr('sensor.disk2iso_status', 'disc_size_mb') }} MB)
        data:
          notification_icon: mdi:check-circle
          color: green
```

#### Medium entfernen

```yaml
- alias: "Disk2ISO - Medium entfernen"
  trigger:
    - platform: mqtt
      topic: "homeassistant/sensor/disk2iso/state"
      value_template: "{{ value_json.status }}"
      payload: "waiting"
  action:
    - service: notify.mobile_app_iphone
      data:
        title: "💿 DVD bereit"
        message: >
          {{ state_attr('sensor.disk2iso_status', 'disc_label') }}
          erfolgreich kopiert. Bitte Medium entfernen.
        data:
          notification_icon: mdi:disc
          color: green
```

#### Fehler

```yaml
- alias: "Disk2ISO - Fehler"
  trigger:
    - platform: mqtt
      topic: "homeassistant/sensor/disk2iso/state"
      value_template: "{{ value_json.status }}"
      payload: "error"
  action:
    - service: notify.mobile_app_iphone
      data:
        title: "❌ Disk2ISO Fehler"
        message: >
          {{ state_attr('sensor.disk2iso_status', 'error_message') }}
        data:
          notification_icon: mdi:alert-circle
          color: red
          tag: disk2iso_error
```

**Nach Bearbeitung**:

```bash
# In Home Assistant
Entwicklerwerkzeuge → YAML → Automatisierungen → Neu laden
```

---

## Dashboard-Karten

### Übersichts-Karte

**Dashboard bearbeiten** → **Karte hinzufügen** → **Manuell**:

```yaml
type: vertical-stack
cards:
  # Titel
  - type: markdown
    content: |
      ## 💿 Disk2ISO

  # Status & Aktiv
  - type: entities
    entities:
      - entity: sensor.disk2iso_status
        name: Status
        icon: mdi:disc
      - entity: binary_sensor.disk2iso_aktiv
        name: Aktiv
        
  # Fortschritt (nur bei copying)
  - type: conditional
    conditions:
      - entity: sensor.disk2iso_status
        state: "copying"
    card:
      type: gauge
      entity: sensor.disk2iso_fortschritt
      min: 0
      max: 100
      name: Fortschritt
      needle: true
      severity:
        green: 75
        yellow: 25
        red: 0
        
  # Details
  - type: markdown
    content: |
      **Medium:** {{ state_attr('sensor.disk2iso_status', 'disc_label') or 'Kein Medium' }}  
      **Typ:** {{ state_attr('sensor.disk2iso_status', 'disc_type') or '-' }}  
      **Größe:** {{ state_attr('sensor.disk2iso_status', 'disc_size_mb') or 0 }} MB  
      
      {% if is_state('sensor.disk2iso_status', 'copying') %}
      **Fortschritt:** {{ state_attr('sensor.disk2iso_status', 'progress_mb') }} / {{ state_attr('sensor.disk2iso_status', 'total_mb') }} MB  
      **Geschwindigkeit:** {{ state_attr('sensor.disk2iso_status', 'speed_mbps') }} MB/s  
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

### Einfache Karte

**Für Anfänger** - Dashboard bearbeiten → **Karte hinzufügen** → **Nach Entität**:

Wähle:
- `sensor.disk2iso_status`
- `sensor.disk2iso_fortschritt`
- `binary_sensor.disk2iso_aktiv`

Fertig!

---

## Troubleshooting

### Keine MQTT-Nachrichten

**Prüfen**:

```bash
# Service läuft?
systemctl status disk2iso

# MQTT-Modul geladen?
journalctl -u disk2iso -n 50 | grep -i mqtt
# Sollte zeigen: "MQTT Support aktiviert"

# mosquitto_pub installiert?
which mosquitto_pub
# Falls nicht:
sudo apt install mosquitto-clients
```

**Test-Publish**:

```bash
mosquitto_pub -h 192.168.20.10 -t "test" -m "hello"
# ✅ Kein Fehler = Verbindung OK
# ❌ Connection Refused = Authentifizierung fehlt
# ❌ Timeout = Falsche IP oder Firewall
```

### Authentifizierung fehlgeschlagen

**Mosquitto Log prüfen** (in Home Assistant):

```
Client disk2iso disconnected, not authorised.
```

**Lösung**:

1. Mosquitto Broker-Logins korrekt?
2. `MQTT_USER` und `MQTT_PASSWORD` in `config.sh` gesetzt?
3. Service neu starten: `systemctl restart disk2iso`

### Sensoren in HA unavailable

**Prüfen**:

1. **Entwicklerwerkzeuge** → **MQTT** → **Auf Topic lauschen**
2. Topic: `homeassistant/sensor/disk2iso/#`
3. Nachrichten sichtbar?
   - ✅ Ja → HA-Konfiguration falsch
   - ❌ Nein → disk2iso sendet nicht

**HA-Konfiguration prüfen**:

```yaml
# configuration.yaml Einrückung korrekt?
# 2 Leerzeichen, KEINE Tabs!
mqtt:
  sensor:
    - name: "Disk2ISO Status"
      ...
```

### Fortschritt bleibt bei 0%

**Log prüfen**:

```bash
journalctl -u disk2iso -f | grep -i "mqtt.*fortschritt"
# Sollte alle 10s erscheinen während copying
```

**Falls nichts erscheint**: Update erforderlich (ältere Version)

---

## Weiterführende Links

### Dokumentation

- **[← Zurück: Kapitel 4.4.2 - TMDB-Integration](04-4_Metadaten/04-4-2_TMDB.md)**
- **[Kapitel 5: Fehlerhandling →](../05_Fehlerhandling.md)**
- **[Kapitel 3: Betrieb →](../03_Betrieb.md)**

### Beispieldateien

- **[Home Assistant Konfiguration](../../samples/homeassistant-configuration.yaml)** - Vollständige configuration.yaml mit Sensoren, Automatisierungen und Dashboard-Beispielen

### Externe Ressourcen

- **Home Assistant**: https://www.home-assistant.io
- **Mosquitto**: https://mosquitto.org
- **MQTT Docs**: https://mqtt.org

---

**Version:** 1.2.0  
**Letzte Aktualisierung:** 26. Januar 2026
