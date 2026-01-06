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

**💡 Systematischer Diagnosepfad:** Arbeite diese Schritte der Reihe nach durch, um Probleme schnell zu identifizieren.

---

### Schritt 1: Grundlegende Konnektivität prüfen

**Ziel:** Sicherstellen, dass die MQTT-Infrastruktur funktioniert

**In Home Assistant:**

1. **MQTT Broker läuft?**
   - **Einstellungen** → **Add-ons** → **Mosquitto broker**
   - Status sollte **"Gestartet"** sein (grüner Punkt)
   - Falls nicht: Klicke **"Start"**

2. **MQTT Integration aktiv?**
   - **Einstellungen** → **Geräte & Dienste**
   - Suche nach **"MQTT"** → sollte **"Konfiguriert"** sein
   - Falls nicht: **Integration hinzufügen** → **"MQTT"** → Standardeinstellungen übernehmen

3. **Live MQTT-Traffic überwachen:**
   - **Entwicklerwerkzeuge** → Tab **"YAML"**
   - Unter Sektion **"MQTT"**: **"Auf ein Topic lauschen"**
   - Gib ein: `homeassistant/sensor/disk2iso/#`
   - Klicke **"Starten zu lauschen"**
   - ✅ Du solltest `availability: online` sehen (wenn disk2iso Service läuft)

**Auf dem disk2iso Server:**

```bash
# Broker-Verbindung testen
mosquitto_pub -h 192.168.20.13 -u disk2iso -P "dein-passwort" -t "test" -m "hello"

# ✅ Kein Fehler = Verbindung OK
# ❌ "Connection Refused" = Authentifizierung fehlgeschlagen → Gehe zu Schritt 2
# ❌ "Connection timeout" = Netzwerkproblem / falsche IP → Prüfe MQTT_BROKER in config.sh
```

---

### Schritt 2: disk2iso MQTT-Konfiguration prüfen

**Ziel:** Sicherstellen, dass disk2iso korrekt konfiguriert ist

```bash
# 1. Ist MQTT aktiviert?
grep MQTT_ENABLED /opt/disk2iso/disk2iso-lib/config.sh
# ✅ Sollte zeigen: MQTT_ENABLED=true
# ❌ Falls false: Setze auf true und starte Service neu

# 2. Broker-Adresse korrekt?
grep MQTT_BROKER /opt/disk2iso/disk2iso-lib/config.sh
# ✅ Sollte zeigen: MQTT_BROKER="192.168.20.13" (deine HA IP)

# 3. Credentials gesetzt?
grep MQTT_USER /opt/disk2iso/disk2iso-lib/config.sh
grep MQTT_PASSWORD /opt/disk2iso/disk2iso-lib/config.sh
# ✅ Sollten Werte enthalten wenn Broker Authentifizierung benötigt
# ⚠️ Müssen mit Mosquitto Broker Logins übereinstimmen!

# 4. mosquitto_pub installiert?
which mosquitto_pub
# ✅ Sollte zeigen: /usr/bin/mosquitto_pub
# ❌ Falls nicht:
sudo apt install mosquitto-clients
```

**Häufigstes Problem: Authentifizierung**

Symptom im Mosquitto Broker Log:
```
error: received null username or password for unpwd check
Client disk2iso-prxFileSrv disconnected, not authorised.
```

**Lösung:**
1. In Home Assistant: **Add-ons** → **Mosquitto broker** → **Konfiguration**
2. Füge unter "Logins" hinzu:
   ```yaml
   logins:
     - username: disk2iso
       password: disk2iso123
   ```
3. **Speichern** und Mosquitto **neu starten**
4. Auf dem Server: Aktualisiere `/opt/disk2iso/disk2iso-lib/config.sh`:
   ```bash
   MQTT_USER="disk2iso"
   MQTT_PASSWORD="disk2iso123"
   ```
5. Service neu starten: `systemctl restart disk2iso`

---

### Schritt 3: Service-Status und Logs prüfen

**Ziel:** Sicherstellen, dass disk2iso Service MQTT-Nachrichten sendet

```bash
# 1. Service läuft?
systemctl status disk2iso
# ✅ Active: active (running) since ...
# ❌ Falls inactive: systemctl start disk2iso

# 2. MQTT-Modul geladen?
journalctl -u disk2iso -n 50 | grep -i mqtt
# ✅ Du solltest sehen:
#    "MQTT Support verfügbar"
#    "MQTT: Status → online"
#    "MQTT Support aktiviert"

# ❌ Falls "Kommando nicht gefunden" in lib-mqtt.de:
#    → Windows-Zeilenumbrüche Problem (siehe Schritt 4)

# 3. Live-Monitoring während Disc-Kopie
journalctl -u disk2iso -f | grep -E "MQTT|Fortschritt|copying"
# ✅ Alle 60 Sekunden solltest du sehen:
#    "Fortschritt:: XX MB / YY MB (ZZ%)"
#    "MQTT: Fortschritt → ZZ% (XX/YY MB)"
```

---

### Schritt 4: Sprachdateien-Problem (Windows-Zeilenumbrüche)

**Symptom:**
```
/opt/disk2iso/disk2iso-lib/lang/lib-mqtt.de: Zeile 10: $'\r': Kommando nicht gefunden.
```

**Ursache:** Datei hat Windows-Zeilenumbrüche (CRLF) statt Unix (LF)

**Lösung:**
```bash
# Konvertiere alle MQTT-Sprachdateien
sed -i 's/\r$//' /opt/disk2iso/disk2iso-lib/lang/lib-mqtt.de
sed -i 's/\r$//' /opt/disk2iso/disk2iso-lib/lang/lib-mqtt.en

# Service neu starten
systemctl restart disk2iso

# Prüfe Log - Fehler sollten weg sein
journalctl -u disk2iso -n 20 | grep mqtt
```

---

### Schritt 5: Home Assistant Sensoren prüfen

**Ziel:** Sicherstellen, dass HA die Sensoren korrekt angelegt hat

1. **Sensoren vorhanden?**
   - **Einstellungen** → **Geräte & Dienste** → **Entitäten**
   - Suche: `disk2iso`
   - ✅ Du solltest sehen:
     - `sensor.disk2iso_status`
     - `sensor.disk2iso_fortschritt` (oder `disk2iso_progress`)
     - `binary_sensor.disk2iso_active`

2. **Falls Sensoren fehlen:**
   - **Entwicklerwerkzeuge** → **YAML** → **YAML-Konfiguration prüfen**
   - ❌ Bei Fehler: Prüfe `configuration.yaml` Einrückung (2 Leerzeichen, **keine Tabs!**)
   - Nach Korrektur: **Alle YAML-Konfigurationen neu laden**
   - Warte 30 Sekunden → Aktualisiere Seite (F5)

3. **Sensor-Status prüfen:**
   - **Entwicklerwerkzeuge** → **Zustände**
   - Klicke auf `sensor.disk2iso_status`
   - ✅ Status sollte sein: `idle`, `copying`, `completed`, `waiting` oder `error`
   - ❌ `unknown`: HA hat noch nie Daten empfangen → Zurück zu Schritt 1
   - ❌ `unavailable`: Service ist offline oder sendet nicht → Zurück zu Schritt 3

---

### Schritt 6: Fortschritts-Updates prüfen

**Symptom:** Status funktioniert, aber Fortschritt bleibt bei 0%

**Diagnose:**

```bash
# 1. Wird mqtt_publish_progress() aufgerufen?
journalctl -u disk2iso -f | grep -i "mqtt.*fortschritt"

# ✅ Alle 60 Sekunden sollte erscheinen:
#    "MQTT: Fortschritt → XX% (YYY/ZZZ MB, ETA: HH:MM:SS)"

# ❌ Falls nichts erscheint:
#    Die Copy-Funktion ruft mqtt_publish_progress() nicht auf
#    → lib-dvd.sh, lib-common.sh, lib-bluray.sh müssen aktualisiert werden
```

**In Home Assistant:**
- **Entwicklerwerkzeuge** → **YAML** → **"MQTT"** → **"Auf ein Topic lauschen"**
- Topic: `homeassistant/sensor/disk2iso/progress`
- ✅ Du solltest alle 60 Sekunden Updates sehen: `15`, `16`, `17`, ...
- Rate-Limiting: Updates nur bei Änderung ≥1% oder alle 10 Sekunden

---

### Schritt 7: Push-Benachrichtigungen testen

**Ziel:** Automatisierungen lösen korrekt aus

1. **Home Assistant Companion App installiert?**
   - iOS: [App Store](https://apps.apple.com/app/home-assistant/id1099568401)
   - Android: [Play Store](https://play.google.com/store/apps/details?id=io.homeassistant.companion.android)
   - App öffnen → Mit HA verbinden → **Benachrichtigungen erlauben!**

2. **Service-Namen finden:**
   - **Entwicklerwerkzeuge** → **Dienste**
   - Suche: `notify`
   - ✅ Du siehst z.B.: `notify.mobile_app_iphone`, `notify.mobile_app_pixel_7`
   - ⚠️ **Notiere dir diesen Namen!**

3. **Test-Benachrichtigung senden:**
   - **Entwicklerwerkzeuge** → **Dienste**
   - Dienst: `notify.mobile_app_[dein_gerät]`
   - Dienst-Daten (YAML):
     ```yaml
     title: "🧪 Test"
     message: "Benachrichtigungen funktionieren!"
     ```
   - Klicke **"Dienst aufrufen"**
   - ✅ Push-Nachricht auf Handy erhalten? → Alles OK!
   - ❌ Keine Nachricht? → Prüfe Handy-Einstellungen (Benachrichtigungen für HA-App erlaubt?)

4. **Automatisierungen aktualisieren:**
   - Ersetze in `automations.yaml` **alle** `notify.mobile_app_smartphone` durch deinen echten Service-Namen
   - **YAML-Konfiguration neu laden** → **Automatisierungen**

---

### Schritt 8: Status-Übergänge zu schnell (completed nicht sichtbar)

**Symptom:** Automatisierung für "Kopie abgeschlossen" wird nicht ausgelöst

**Ursache:** Übergang `copying` → `completed` → `waiting` passiert in <1 Sekunde

**Lösung:** Bereits in disk2iso.sh eingebaut (seit Version 1.0.0):
- Nach `completed` wird 3 Sekunden gewartet
- Dann erst Wechsel zu `waiting`
- HA hat genug Zeit den Status zu erfassen

**Falls du eine ältere Version hast:**
```bash
# Prüfe Version
grep "^# Version:" /opt/disk2iso/disk2iso.sh

# Bei Version < 1.0.0: Update durchführen
cd ~/disk2iso-1.0.2
./install.sh  # Wähle gleiche Optionen wie bei Erstinstallation
```

---

### Häufige Fehlerquellen - Checkliste

| Problem | Symptom | Lösung |
|---------|---------|--------|
| ❌ **Authentifizierung** | `Connection Refused: not authorised` | Mosquitto Broker Logins anlegen + config.sh aktualisieren |
| ❌ **Zeilenumbrüche** | `$'\r': Kommando nicht gefunden` | `sed -i 's/\r$//' lib-mqtt.de` |
| ❌ **Kein Fortschritt** | `progress_percent: 0` bleibt | lib-dvd.sh muss `mqtt_publish_progress()` aufrufen |
| ❌ **Falscher Service-Name** | Keine Push-Benachrichtigung | `notify.mobile_app_*` in automations.yaml korrigieren |
| ❌ **MQTT nicht aktiviert** | Keine MQTT-Logs | `MQTT_ENABLED=true` in config.sh setzen |
| ❌ **Speicherplatz voll** | `No space left on device` | `/media/iso/.temp/` aufräumen oder `DEFAULT_OUTPUT_DIR` ändern |
| ❌ **Falsche Broker IP** | `Connection timeout` | `MQTT_BROKER` in config.sh prüfen |

---

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
