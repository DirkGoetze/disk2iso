# Home Assistant Integration für disk2iso

## Übersicht

Dieses Dokument beschreibt die Implementierung einer Home Assistant Integration für disk2iso.
Die Integration ermöglicht Statusüberwachung, Benachrichtigungen und Dashboard-Visualisierung
des Disc-Kopiervorgangs direkt in Home Assistant.

## Ziele

- **Echtzeit-Status**: Aktuelle Kopier-Aktivität in Home Assistant anzeigen
- **Benachrichtigungen**: Push-Notifications bei Medium-Wechsel, Abschluss, Fehler
- **Dashboard-Integration**: Eigene Lovelace-Card mit Fortschrittsanzeige
- **MQTT-basiert**: Einfache Integration ohne Custom Component
- **Container-kompatibel**: Funktioniert in LXC/Docker-Umgebungen

---

## 1. MQTT-Integration

### 1.1 Architektur

```
disk2iso.sh 
    ↓ (MQTT Publish)
MQTT Broker (Mosquitto)
    ↓ (MQTT Subscribe)
Home Assistant
    ↓ (Sensor/Automation)
Lovelace Dashboard
```

### 1.2 Komponenten

#### disk2iso-Seite

**Neue Datei: `disk2iso-lib/lib-mqtt.sh`**

- Funktionen zum Senden von MQTT-Nachrichten
- Status-Updates: idle, copying, waiting, completed, error
- Fortschritts-Updates: Prozent, MB kopiert, ETA
- Medium-Informationen: Label, Typ, Größe

**Konfiguration in `disk2iso-lib/config.sh`**

```bash
# MQTT Settings
MQTT_ENABLED=false
MQTT_BROKER="192.168.20.10"
MQTT_PORT=1883
MQTT_USER=""
MQTT_PASSWORD=""
MQTT_TOPIC_PREFIX="homeassistant/sensor/disk2iso"
MQTT_CLIENT_ID="disk2iso-${HOSTNAME}"
```

**Abhängigkeiten**

- `mosquitto-clients` (mosquitto_pub)
- Optional: `paho-mqtt` (Python) für erweiterte Features

#### Home Assistant-Seite

**MQTT Sensor Konfiguration**

```yaml
# configuration.yaml
mqtt:
  sensor:
    - name: "Disk2ISO Status"
      state_topic: "homeassistant/sensor/disk2iso/state"
      json_attributes_topic: "homeassistant/sensor/disk2iso/attributes"
      icon: mdi:disc
      
    - name: "Disk2ISO Progress"
      state_topic: "homeassistant/sensor/disk2iso/progress"
      unit_of_measurement: "%"
      icon: mdi:progress-clock
```

**Automatisierungen**

```yaml
automation:
  - alias: "Disk2ISO - Medium Ready"
    trigger:
      platform: mqtt
      topic: "homeassistant/sensor/disk2iso/state"
      payload: "waiting"
    action:
      - service: notify.mobile_app
        data:
          message: "DVD bereit zum Wechsel - {{ states.sensor.disk2iso_attributes.disc_label }}"
          
  - alias: "Disk2ISO - Copy Complete"
    trigger:
      platform: mqtt
      topic: "homeassistant/sensor/disk2iso/state"
      payload: "completed"
    action:
      - service: notify.mobile_app
        data:
          message: "DVD-Kopie abgeschlossen - {{ states.sensor.disk2iso_attributes.filename }}"
```

### 1.3 MQTT-Payload-Struktur

#### State Topic (`/state`)

```json
{
  "status": "copying",           // idle|copying|waiting|completed|error
  "timestamp": "2026-01-02T17:30:00"
}
```

#### Attributes Topic (`/attributes`)

```json
{
  "disc_label": "Supernatural_S02D01",
  "disc_type": "dvd-video",
  "disc_size_mb": 7562,
  "progress_percent": 45,
  "progress_mb": 3400,
  "total_mb": 7562,
  "eta": "00:23:15",
  "filename": "Supernatural_S02D01.iso",
  "method": "dvdbackup",
  "container_type": "lxc",
  "error_message": null
}
```

#### Progress Topic (`/progress`) - Nur Prozent

```txt
45
```

### 1.4 Implementierung in lib-mqtt.sh

**Funktionen:**

```bash
# MQTT initialisieren (Verfügbarkeit prüfen)
mqtt_init()

# Status senden
mqtt_publish_state(status, disc_label, disc_type)

# Fortschritt senden (während Kopiervorgang)
mqtt_publish_progress(percent, copied_mb, total_mb, eta)

# Abschluss senden
mqtt_publish_complete(filename, duration)

# Fehler senden
mqtt_publish_error(error_message)

# Verfügbarkeit setzen (online/offline)
mqtt_publish_availability(online|offline)
```

**Integration in disk2iso.sh:**
- `mqtt_init()` beim Start
- `mqtt_publish_availability("online")` nach Init
- `mqtt_publish_state("copying", ...)` bei Kopierstart
- `mqtt_publish_progress(...)` alle 30-60 Sekunden während Kopieren
- `mqtt_publish_state("waiting", ...)` in Container nach eject
- `mqtt_publish_complete(...)` nach erfolgreichem Abschluss
- `mqtt_publish_error(...)` bei Fehlern
- `mqtt_publish_availability("offline")` beim Beenden (Signal-Handler)

---

## 2. Lovelace Dashboard Card

### 2.1 Custom Card: `disk2iso-card`

**Features:**

- Aktueller Status (Icon + Text)
- Fortschrittsbalken mit Prozent
- Medium-Informationen (Label, Typ, Größe)
- ETA (geschätzte Restzeit)
- Letzte Kopie (Filename, Zeitstempel)
- Fehleranzeige

**UI-Konzept:**

```txt
┌─────────────────────────────────────┐
│ 💿 Disk2ISO                         │
├─────────────────────────────────────┤
│ Status: Kopiere DVD...              │
│                                     │
│ Medium: Supernatural_S02D01         │
│ Typ: Video-DVD (7.4 GB)            │
│                                     │
│ ▓▓▓▓▓▓▓▓▓▓░░░░░░░░ 45%            │
│ 3.4 GB / 7.4 GB                    │
│ Verbleibend: 00:23:15              │
│                                     │
│ Methode: dvdbackup (entschlüsselt) │
│ Container: LXC                      │
└─────────────────────────────────────┘
```

### 2.2 Implementierung

**Option 1: Standard Lovelace (kein Custom Card)**

```yaml
# Einfach mit Standard-Karten
type: vertical-stack
cards:
  - type: entity
    entity: sensor.disk2iso_status
    name: Disk2ISO
    icon: mdi:disc
    
  - type: conditional
    conditions:
      - entity: sensor.disk2iso_status
        state: "copying"
    card:
      type: gauge
      entity: sensor.disk2iso_progress
      min: 0
      max: 100
      needle: true
      
  - type: markdown
    content: |
      **Medium:** {{ state_attr('sensor.disk2iso_status', 'disc_label') }}  
      **Typ:** {{ state_attr('sensor.disk2iso_status', 'disc_type') }}  
      **Fortschritt:** {{ state_attr('sensor.disk2iso_status', 'progress_mb') }} MB / {{ state_attr('sensor.disk2iso_status', 'total_mb') }} MB  
      **Verbleibend:** {{ state_attr('sensor.disk2iso_status', 'eta') }}
```

**Option 2: Custom Lovelace Card (YAML)**

- Entwicklung eigener Card mit `card-tools`
- Komplexere Logik und besseres Design
- Aufwand: ~200-300 Zeilen JavaScript/YAML

**Option 3: Custom Component (Python)**

- Vollständige Integration als HA-Component
- Mehr Features (Services, Events)
- Aufwand: ~500-1000 Zeilen Python + Setup

### 2.3 Empfehlung

**Start: Option 1** (Standard Lovelace)

- Schnell umsetzbar
- Keine zusätzlichen Komponenten
- Ausreichend für MVP

**Zukunft: Option 2** (Custom Card)

- Besseres UX
- Spezifische Features (Button für eject-retry etc.)
- Moderate Komplexität

---

## 3. Implementierungsplan

### Phase 1: MQTT Basis (MVP)
**Aufwand: 2-3 Stunden**

- [ ] `lib-mqtt.sh` erstellen
  - [ ] `mqtt_init()` - Prüfe mosquitto_pub Verfügbarkeit
  - [ ] `mqtt_publish_state()` - State + Attributes in einem Publish
  - [ ] `mqtt_publish_progress()` - Nur Prozent-Update
  - [ ] `mqtt_publish_availability()` - online/offline
  
- [ ] `config.sh` erweitern
  - [ ] MQTT-Konfigurationsvariablen
  - [ ] Installation fragt nach MQTT-Aktivierung
  
- [ ] `disk2iso.sh` erweitern
  - [ ] Source lib-mqtt.sh (optional wie andere Module)
  - [ ] MQTT_SUPPORT Flag setzen
  - [ ] Calls zu mqtt_publish_* an passenden Stellen
  
- [ ] Signal-Handler erweitern
  - [ ] `mqtt_publish_availability("offline")` bei EXIT

### Phase 2: Home Assistant Config
**Aufwand: 1 Stunde**

- [ ] MQTT Sensor-Konfiguration in HA
  - [ ] sensor.disk2iso_status (State)
  - [ ] sensor.disk2iso_progress (Prozent)
  
- [ ] Basis-Automatisierungen
  - [ ] Notify bei "waiting" (Medium-Wechsel)
  - [ ] Notify bei "completed" (Abschluss)
  - [ ] Notify bei "error" (Fehler)

### Phase 3: Dashboard
**Aufwand: 1-2 Stunden**

- [ ] Lovelace-Card mit Standard-Komponenten
  - [ ] Status-Anzeige
  - [ ] Fortschrittsbalken
  - [ ] Medium-Informationen
  - [ ] Letzte Kopie
  
- [ ] Testing verschiedene States
  - [ ] idle, copying, waiting, completed, error

### Phase 4: Erweiterte Features (Optional)
**Aufwand: 4-8 Stunden**

- [ ] Custom Lovelace Card entwickeln
- [ ] History/Log-Integration (Kopierte Discs anzeigen)
- [ ] Service-Calls (manueller eject-retry, cancel)
- [ ] Statistiken (Anzahl kopierter Discs, Gesamtgröße)
- [ ] Fehler-Diagnose in Card anzeigen

---

## 4. Technische Details

### 4.1 MQTT-Broker Setup

**Mosquitto auf gleichem Host wie disk2iso:**

```bash
# Installation
apt-get install mosquitto mosquitto-clients

# Konfiguration /etc/mosquitto/mosquitto.conf
listener 1883
allow_anonymous true  # Oder mit Authentifizierung

# Start
systemctl enable mosquitto
systemctl start mosquitto
```

**Authentifizierung (empfohlen):**

```bash
# Benutzer erstellen
mosquitto_passwd -c /etc/mosquitto/passwd disk2iso

# mosquitto.conf
password_file /etc/mosquitto/passwd
allow_anonymous false
```

### 4.2 Home Assistant MQTT Discovery (Optional)

Automatische Sensor-Registrierung via MQTT Discovery:

```bash
# Publish bei mqtt_init()
mosquitto_pub -h "$MQTT_BROKER" -p "$MQTT_PORT" \
  -t "homeassistant/sensor/disk2iso/config" \
  -m '{
    "name": "Disk2ISO",
    "state_topic": "homeassistant/sensor/disk2iso/state",
    "json_attributes_topic": "homeassistant/sensor/disk2iso/attributes",
    "availability_topic": "homeassistant/sensor/disk2iso/availability",
    "unique_id": "disk2iso_sensor",
    "device": {
      "identifiers": ["disk2iso"],
      "name": "Disk2ISO Service",
      "model": "v1.0.0",
      "manufacturer": "disk2iso"
    }
  }' -r
```

Vorteil: Keine manuelle Sensor-Konfiguration in Home Assistant nötig.

### 4.3 Performance-Überlegungen

**Publish-Frequenz:**

- State-Updates: Bei Zustandsänderung (idle→copying, copying→waiting, etc.)
- Progress-Updates: Alle 30-60 Sekunden während Kopiervorgang
- Attributes: Zusammen mit State (um Sync-Probleme zu vermeiden)

**MQTT QoS:**

- State/Progress: QoS 0 (Fire-and-forget, ausreichend)
- Availability: QoS 1 (At-least-once, wichtig für offline-Erkennung)

**Retained Messages:**

- State: `retained=true` (letzter Status bleibt nach Neustart)
- Availability: `retained=true` (HA erkennt offline sofort)
- Progress: `retained=false` (nur während aktiver Kopie relevant)

---

## 5. Testing & Debugging

### 5.1 MQTT Test ohne Home Assistant

**Manuelles Publizieren:**

```bash
mosquitto_pub -h 192.168.20.10 -p 1883 \
  -t "homeassistant/sensor/disk2iso/state" \
  -m '{"status":"copying","timestamp":"2026-01-02T18:00:00"}'
```

**Manuelles Subscriben:**

```bash
mosquitto_sub -h 192.168.20.10 -p 1883 \
  -t "homeassistant/sensor/disk2iso/#" -v
```

### 5.2 Logging

**lib-mqtt.sh Debug-Modus:**

```bash
# In mqtt_publish_* Funktionen
if [[ "${MQTT_DEBUG:-0}" == "1" ]]; then
    log_message "MQTT: Publishing to $topic - $payload"
fi
```

**Home Assistant MQTT Debug:**

```yaml
# configuration.yaml
logger:
  default: info
  logs:
    homeassistant.components.mqtt: debug
```

---

## 6. Dokumentation

Nach Implementierung:

- [ ] README.md aktualisieren (MQTT-Features dokumentieren)
- [ ] Beispiel Home Assistant Config in `/docu/HomeAssistant.md`
- [ ] Screenshots der Lovelace-Card
- [ ] Troubleshooting-Guide (MQTT Connection, Auth, etc.)

---

## 7. Abhängigkeiten

**Neue Pakete für disk2iso:**

- `mosquitto-clients` (mosquitto_pub)

**Home Assistant:**

- MQTT Integration aktiviert
- MQTT Broker (Mosquitto) verfügbar

**Optional:**

- `jq` für komplexere JSON-Payloads in Bash

---

## Zeitschätzung

- **Phase 1 (MVP):** 2-3 Stunden
- **Phase 2 (HA Config):** 1 Stunde
- **Phase 3 (Dashboard):** 1-2 Stunden
- **Phase 4 (Optional):** 4-8 Stunden

**Gesamt MVP (Phase 1-3):** ~4-6 Stunden

---

## Nächste Schritte

1. Entscheidung: MVP mit Standard Lovelace oder direkt Custom Card?
2. MQTT-Broker Setup testen (falls noch nicht vorhanden)
3. `lib-mqtt.sh` Grundgerüst erstellen
4. Integration in `disk2iso.sh` an 2-3 Test-Punkten
5. Home Assistant Sensor-Config testen
6. Iterativ erweitern

---

**Status:** 📋 Planung  
**Priorität:** Mittel  
**Abhängigkeiten:** Mosquitto MQTT Broker  
**Geschätzte Fertigstellung:** TBD
