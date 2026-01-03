# Home Assistant MQTT Sensor Configuration für disk2iso

Diese Anleitung zeigt Schritt für Schritt, wie du die MQTT-Integration zwischen disk2iso und Home Assistant einrichtest. Auch für Anfänger geeignet!

## Voraussetzungen

✅ Home Assistant installiert und erreichbar  
✅ MQTT Broker installiert (meist als "Mosquitto broker" Add-on)  
✅ disk2iso mit aktivierter MQTT-Unterstützung installiert  

## Installation

### 1. MQTT Broker in Home Assistant einrichten

**Wenn noch nicht installiert:**

1. Öffne Home Assistant in deinem Browser (z.B. `http://homeassistant.local:8123`)
2. Gehe zu: **Einstellungen** → **Add-ons** → **Add-on Store** (unten rechts)
3. Suche nach **"Mosquitto broker"**
4. Klicke auf **Installieren**
5. Nach Installation: **Start** aktivieren und **Bei Boot starten** aktivieren
6. Gehe zu: **Einstellungen** → **Geräte & Dienste** → **Integration hinzufügen**
7. Suche nach **"MQTT"** und füge die Integration hinzu
8. Standardeinstellungen übernehmen (Broker: localhost, Port: 1883)

**Broker-Benutzer anlegen (empfohlen):**

1. In den **Mosquitto broker** Add-on Einstellungen
2. Unter **"Konfiguration"** (YAML-Modus):
```yaml
logins:
  - username: disk2iso
    password: dein-sicheres-passwort
```
3. Speichern und Add-on neu starten

### 2. disk2iso Konfiguration

**Option A: Während der Installation**  
Der Installationsassistent (`sudo ./install.sh`) fragt auf Seite 7/9 nach:
- MQTT aktivieren? → Ja
- Broker IP-Adresse → IP deines Home Assistant (z.B. `192.168.20.10`)
- Benutzername → `disk2iso` (optional)
- Passwort → dein Passwort (optional)

**Option B: Manuelle Konfiguration**  
Bearbeite `/usr/local/bin/disk2iso-lib/config.sh` (oder `/opt/disk2iso/disk2iso-lib/config.sh` bei Service-Installation):

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

### 3. Home Assistant Sensoren konfigurieren

**Wichtig:** Home Assistant kann entweder per **YAML-Dateien** oder per **UI** konfiguriert werden. Seit Version 2023.x bevorzugt HA die UI-Konfiguration, aber MQTT-Sensoren erfordern aktuell noch YAML.

**Wo finde ich die configuration.yaml?**

**Methode 1: File Editor Add-on (einfachste Methode)**
1. Installiere das Add-on **"File editor"** (Add-on Store)
2. Öffne **File editor** aus der Sidebar
3. Klicke auf das Ordner-Symbol oben links
4. Öffne die Datei **`configuration.yaml`** (im Hauptverzeichnis)

**Methode 2: SSH/Terminal**
1. Installiere das Add-on **"Terminal & SSH"**
2. Öffne Terminal und gib ein: `nano /config/configuration.yaml`

**Methode 3: Samba Share**
1. Installiere das Add-on **"Samba share"**
2. Verbinde von deinem PC aus: `\\homeassistant.local\config`
3. Öffne `configuration.yaml` mit einem Texteditor

**YAML-Code hinzufügen:**

Füge folgendes **am Ende** der `configuration.yaml` ein (achte auf korrekte Einrückung!):

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

**Nach dem Speichern:**
1. Prüfe die YAML-Syntax: **Entwicklerwerkzeuge** → **YAML** → **YAML-Konfiguration prüfen**
2. Bei ✅ grünem Haken: **YAML-Konfiguration neu laden** → **Alle YAML-Konfigurationen**
3. Prüfe ob Sensoren da sind: **Einstellungen** → **Geräte & Dienste** → **Entitäten** → Suche nach "disk2iso"

Du solltest jetzt sehen:
- `sensor.disk2iso_status` (Status)
- `sensor.disk2iso_progress` (Fortschritt %)
- `binary_sensor.disk2iso_active` (An/Aus)

### 4. Benachrichtigungen einrichten (Optional)

**Automatisierungen erstellen zwei Wege:**

**Weg 1: UI-Automatisierung (empfohlen für Anfänger)**

1. Gehe zu: **Einstellungen** → **Automatisierungen & Szenen** → **Automatisierung erstellen**
2. Klicke **Neue Automatisierung** → **Leere Automatisierung erstellen**
3. **Auslöser hinzufügen** → Typ: **MQTT**
   - Topic: `homeassistant/sensor/disk2iso/state`
   - Template: `{{ value_json.status }}`
   - Nutzlast: `waiting`
4. **Aktion hinzufügen** → **Benachrichtigung senden**
   - Dienst: Wähle dein Gerät (z.B. `notify.mobile_app_iphone`)
   - Titel: `💿 DVD bereit`
   - Nachricht: `Bitte Medium entfernen`
5. Speichern mit Namen: "Disk2ISO - Medium entfernen"

Wiederhole für `copying`, `completed`, `error` mit angepassten Nachrichten.

**Weg 2: YAML-Automatisierung (für Fortgeschrittene)**

Öffne `automations.yaml` (über File Editor) und füge hinzu:

```yaml
# Benachrichtigung bei Medium bereit
- alias: "Disk2ISO - Medium entfernen"
  trigger:
    - platform: mqtt
      topic: "homeassistant/sensor/disk2iso/state"
      value_template: "{{ value_json.status }}"
      payload: "waiting"
  action:
    - service: notify.mobile_app_smartphone  # ⚠️ Ersetze "smartphone" durch deinen Gerätenamen!
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

**⚠️ Wichtig:** Ersetze `notify.mobile_app_smartphone` durch deinen tatsächlichen Service-Namen!

**Wie finde ich meinen Service-Namen?**
1. **Entwicklerwerkzeuge** → **Dienste** (Services)
2. Suche nach **"notify"** in der Dienst-Liste
3. Du siehst z.B.: `notify.mobile_app_iphone`, `notify.mobile_app_pixel_7`, usw.
4. Verwende diesen Namen in allen Automatisierungen

**Automatisierungen aktivieren:**
1. Nach Bearbeitung von `automations.yaml`: **YAML-Konfiguration neu laden** → **Automatisierungen**
2. Prüfe unter **Einstellungen** → **Automatisierungen & Szenen** ob alle da sind
3. Aktiviere jede Automatisierung mit dem Schalter (falls nicht schon aktiv)

### 5. Dashboard-Karte erstellen (Optional)

**So erstellst du eine schöne Übersicht:**

1. Öffne dein **Dashboard** (z.B. "Übersicht")
2. Klicke oben rechts auf **⋮** (3 Punkte) → **Dashboard bearbeiten**
3. Klicke **+ Karte hinzufügen** (unten rechts)
4. Wähle **"Manuell"** (ganz unten in der Liste)
5. Füge folgenden YAML-Code ein:

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

6. Klicke **Speichern** → **Fertig** (oben rechts)

**Alternative: Einfache Entities Card**
Wenn der obige Code zu komplex ist, nutze die Standard-Karte:
1. **+ Karte hinzufügen** → **"Nach Entität"**
2. Wähle: `sensor.disk2iso_status`, `sensor.disk2iso_progress`, `binary_sensor.disk2iso_active`
3. Fertig! Weniger Features, aber funktioniert sofort.

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

## Testen der Integration

### Schnelltest in Home Assistant

1. **Prüfe MQTT-Verbindung:**
   - **Einstellungen** → **Geräte & Dienste** → **MQTT**
   - Klicke auf **MQTT** → **Gerät konfigurieren**
   - Unter **"MQTT-Nachrichten überwachen"**: Topic `homeassistant/sensor/disk2iso/#`
   - Klicke **"Zuhören starten"**

2. **Teste disk2iso:**
   - Lege eine DVD in das Laufwerk ein
   - Du solltest MQTT-Nachrichten sehen:
     ```
     homeassistant/sensor/disk2iso/availability: online
     homeassistant/sensor/disk2iso/state: {"status":"copying",...}
     homeassistant/sensor/disk2iso/progress: 15
     ```

3. **Prüfe Sensoren:**
   - **Entwicklerwerkzeuge** → **Zustände**
   - Suche nach `disk2iso`
   - `sensor.disk2iso_status` sollte "copying" oder "idle" zeigen

### Terminal-Tests (für Fortgeschrittene)

```bash
# MQTT Messages manuell überwachen (auf dem Server mit disk2iso)
mosquitto_sub -h 192.168.20.10 -t "homeassistant/sensor/disk2iso/#" -v

# Test-Nachricht senden (simuliert Status-Update)
mosquitto_pub -h 192.168.20.10 \
  -t "homeassistant/sensor/disk2iso/state" \
  -m '{"status":"copying","timestamp":"2026-01-03T12:00:00"}'
```

## Troubleshooting / Problemlösung

### Problem: Sensoren erscheinen nicht in Home Assistant

**Checkliste:**

1. ✅ **MQTT Broker läuft?**
   - **Einstellungen** → **Add-ons** → **Mosquitto broker** → Status sollte "Gestartet" sein
   
2. ✅ **MQTT Integration hinzugefügt?**
   - **Einstellungen** → **Geräte & Dienste** → Suche nach "MQTT"
   - Sollte als **"konfiguriert"** erscheinen
   
3. ✅ **YAML korrekt eingefügt?**
   - Öffne **Entwicklerwerkzeuge** → **YAML** → **YAML-Konfiguration prüfen**
   - Bei Fehlern: Prüfe Einrückung (2 Leerzeichen, keine Tabs!)
   - YAML ist sehr streng bei Formatierung
   
4. ✅ **YAML neu geladen?**
   - **Entwicklerwerkzeuge** → **YAML** → **Alle YAML-Konfigurationen neu laden**
   - Oder: **Einstellungen** → **System** → **Home Assistant neu starten**

5. ✅ **Sensoren sichtbar?**
   - **Einstellungen** → **Geräte & Dienste** → **Entitäten**
   - Suche: `disk2iso`
   - Falls nicht da: Warte 30 Sekunden und aktualisiere Seite (F5)

### Problem: MQTT-Nachrichten werden nicht gesendet (von disk2iso)

**Auf dem Server mit disk2iso:**

```bash
# 1. Ist mosquitto_pub installiert?
which mosquitto_pub
# Sollte zeigen: /usr/bin/mosquitto_pub

# Falls nicht:
sudo apt install mosquitto-clients

# 2. Ist MQTT in disk2iso aktiviert?
grep MQTT_ENABLED /usr/local/bin/disk2iso-lib/config.sh
# Sollte zeigen: MQTT_ENABLED=true

# 3. Kann disk2iso den Broker erreichen?
mosquitto_pub -h 192.168.20.10 -t "test" -m "hello"
# Kein Fehler = Verbindung OK

# 4. Prüfe Log-Dateien
tail -f /srv/iso/.log/*.log | grep -i mqtt
# Hier siehst du MQTT-Aktivität während dem Kopieren
```

### Problem: Keine Push-Benachrichtigungen auf dem Handy

1. ✅ **Home Assistant Companion App installiert?**
   - Installiere aus [App Store](https://apps.apple.com/app/home-assistant/id1099568401) (iOS)
   - Oder [Play Store](https://play.google.com/store/apps/details?id=io.homeassistant.companion.android) (Android)
   
2. ✅ **App mit Home Assistant verbunden?**
   - Öffne App → Einstellungen → sollte deine HA-Instanz zeigen
   - Benachrichtigungen erlauben (iOS/Android Systemeinstellungen!)

3. ✅ **Richtiger Service-Name in Automatisierungen?**
   - **Entwicklerwerkzeuge** → **Dienste** → Suche "notify"
   - Siehst du `notify.mobile_app_[dein_gerät]`?
   - Ersetze in `automations.yaml`: `notify.mobile_app_smartphone` → dein echter Name
   
4. ✅ **Test-Benachrichtigung senden:**
   - **Entwicklerwerkzeuge** → **Dienste**
   - Dienst: `notify.mobile_app_[dein_gerät]`
   - Dienst-Daten:
     ```yaml
     title: Test
     message: Funktioniert!
     ```
   - Klicke **"Dienst aufrufen"**
   - Bekommst du eine Push-Nachricht? → App funktioniert
   - Keine Nachricht? → Prüfe App-Benachrichtigungseinstellungen

### Problem: Fortschritt zeigt immer 0% oder aktualisiert nicht

**Mögliche Ursachen:**

- Rate-Limiting greift (nur alle 10 Sekunden oder bei 1% Änderung)
- Warte bis Kopierprozess mindestens 1% erreicht hat
- Prüfe ob `sensor.disk2iso_progress` überhaupt Werte empfängt:
  - **Entwicklerwerkzeuge** → **Zustände** → `sensor.disk2iso_progress`
  - Unter **"Historie"** sollten Änderungen sichtbar sein

### Problem: Status bleibt auf "unknown" oder "unavailable"

**Bedeutung:**
- `unknown`: Home Assistant hat noch nie Daten empfangen
- `unavailable`: Verfügbarkeits-Topic sagt "offline"

**Lösung:**
```bash
# Auf dem disk2iso Server: Starte Service neu
sudo systemctl restart disk2iso

# Oder starte manuell (falls kein Service)
cd /usr/local/bin
sudo ./disk2iso.sh

# Prüfe ob "online" gesendet wird:
mosquitto_sub -h 192.168.20.10 -t "homeassistant/sensor/disk2iso/availability"
# Sollte zeigen: online
```

### Erweiterte Diagnose (für Experten)

**Terminal-Befehle auf dem Server:**

```bash
# Live MQTT Traffic überwachen
mosquitto_sub -h 192.168.20.10 -t "homeassistant/sensor/disk2iso/#" -v

# Manuelle Test-Nachricht senden
mosquitto_pub -h 192.168.20.10 \
  -t "homeassistant/sensor/disk2iso/state" \
  -m '{"status":"copying","timestamp":"2026-01-03T12:00:00"}'

# MQTT Credentials testen (falls Authentifizierung)
mosquitto_pub -h 192.168.20.10 \
  -u disk2iso -P dein-passwort \
  -t "test" -m "hello"
```

**Home Assistant Terminal (Terminal & SSH Add-on):**

```bash
# HA Core Konfiguration prüfen
ha core check

# Home Assistant neu starten
ha core restart

# MQTT Add-on Status
ha addons info core_mosquitto

# MQTT Add-on Logs
ha addons logs core_mosquitto
```

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
