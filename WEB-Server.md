# WEB-Server Integration für disk2iso

## Übersicht

Dieses Dokument beschreibt verschiedene Ansätze zur Integration eines Webservers in `disk2iso`, um den Status über HTTP abfragbar zu machen.

## Home Assistant Integration via MQTT

[... existing content ...]

## 🏗️ Architektur-Entscheidung: Zentrale Status-Verwaltung

### Problem
Wenn sowohl Home Assistant als auch eine Web-Seite die gleichen Status-Informationen anzeigen sollen, stellt sich die Frage:
- **Separate Module** für HA und Web (Code-Duplikation)?
- **Gemeinsames API-Modul** (höhere Komplexität)?
- **Hybrid-Ansatz** mit zentraler Datenhaltung?

### Lösung: Status-File als Single Source of Truth

**Architektur:**
```
disk2iso.sh
    └─> lib-status.sh (zentrale Datenhaltung via JSON)
            ├─> lib-homeassistant.sh (MQTT-Publisher)
            └─> lib-webserver.sh     (HTTP-Server)
```

### Neue Bibliothek: `lib-status.sh`

```bash
#!/bin/bash
# disk2iso-lib/lib-status.sh
# Zentrale Status-Verwaltung für alle Backends

# Status-File Pfad
STATUS_FILE="/var/run/disk2iso/status.json"

# Status-Datenstruktur initialisieren
init_status() {
    mkdir -p "$(dirname "$STATUS_FILE")"
    cat > "$STATUS_FILE" <<EOF
{
  "status": "idle",
  "drive": "empty",
  "disc": {
    "type": "",
    "label": "",
    "size_mb": 0
  },
  "progress": {
    "percent": 0,
    "mb_current": 0,
    "mb_total": 0,
    "eta_minutes": 0
  },
  "current_method": "",
  "last_update": "$(date -Iseconds)",
  "stats": {
    "total": 0,
    "audio": 0,
    "data": 0,
    "dvd": 0,
    "bd": 0
  }
}
EOF
}

# Status aktualisieren (zentrale Funktion)
update_status() {
    local field="$1"
    local value="$2"
    
    # JSON aktualisieren (mit jq falls vorhanden, sonst sed)
    if command -v jq &>/dev/null; then
        tmp=$(mktemp)
        jq ".$field = \"$value\" | .last_update = \"$(date -Iseconds)\"" "$STATUS_FILE" > "$tmp"
        mv "$tmp" "$STATUS_FILE"
    else
        # Fallback ohne jq (einfacher, weniger flexibel)
        sed -i "s|\"$field\": \"[^\"]*\"|\"$field\": \"$value\"|" "$STATUS_FILE"
    fi
    
    # Backends benachrichtigen
    notify_backends "$field" "$value"
}

# Komplexe Updates (verschachtelte Objekte)
update_disc_info() {
    local type="$1"
    local label="$2"
    local size_mb="${3:-0}"
    
    if command -v jq &>/dev/null; then
        tmp=$(mktemp)
        jq ".disc.type = \"$type\" | .disc.label = \"$label\" | .disc.size_mb = $size_mb | .last_update = \"$(date -Iseconds)\"" "$STATUS_FILE" > "$tmp"
        mv "$tmp" "$STATUS_FILE"
    fi
    
    notify_backends "disc" "$type: $label"
}

update_progress() {
    local percent="$1"
    local mb_current="$2"
    local mb_total="$3"
    local eta_min="$4"
    
    if command -v jq &>/dev/null; then
        tmp=$(mktemp)
        jq ".progress.percent = $percent | .progress.mb_current = $mb_current | .progress.mb_total = $mb_total | .progress.eta_minutes = $eta_min | .last_update = \"$(date -Iseconds)\"" "$STATUS_FILE" > "$tmp"
        mv "$tmp" "$STATUS_FILE"
    fi
    
    notify_backends "progress" "$percent"
}

update_stats() {
    local audio=$(find "$OUTPUT_DIR/audio" -name "*.iso" 2>/dev/null | wc -l)
    local data=$(find "$OUTPUT_DIR/data" -name "*.iso" 2>/dev/null | wc -l)
    local dvd=$(find "$OUTPUT_DIR/dvd" -name "*.iso" 2>/dev/null | wc -l)
    local bd=$(find "$OUTPUT_DIR/bd" -name "*.iso" 2>/dev/null | wc -l)
    local total=$((audio + data + dvd + bd))
    
    if command -v jq &>/dev/null; then
        tmp=$(mktemp)
        jq ".stats.total = $total | .stats.audio = $audio | .stats.data = $data | .stats.dvd = $dvd | .stats.bd = $bd | .last_update = \"$(date -Iseconds)\"" "$STATUS_FILE" > "$tmp"
        mv "$tmp" "$STATUS_FILE"
    fi
    
    notify_backends "stats" "updated"
}

# Backend-Benachrichtigung (Hook-System)
notify_backends() {
    local field="$1"
    local value="$2"
    
    # Home Assistant MQTT (falls aktiviert)
    if [[ "$HA_MQTT_ENABLED" == "true" ]] && type ha_notify &>/dev/null; then
        ha_notify "$field" "$value"
    fi
    
    # Webserver (falls aktiviert)
    if [[ "$WEB_ENABLED" == "true" ]] && type web_notify &>/dev/null; then
        web_notify "$field" "$value"
    fi
    
    # Weitere Backends hier einfügbar (Discord, Telegram, etc.)
}

# Status lesen (für Backends)
get_status() {
    cat "$STATUS_FILE"
}

get_status_field() {
    local field="$1"
    if command -v jq &>/dev/null; then
        jq -r ".$field" "$STATUS_FILE"
    fi
}
```

### Angepasstes `lib-homeassistant.sh`

```bash
#!/bin/bash
# disk2iso-lib/lib-homeassistant.sh
# Home Assistant MQTT-Backend

# MQTT-Publish (intern)
_ha_mqtt_publish() {
    local topic="$1"
    local message="$2"
    local retain="${3:-false}"
    
    if command -v mosquitto_pub &>/dev/null; then
        local cmd="mosquitto_pub -h $HA_MQTT_BROKER -p $HA_MQTT_PORT -t disk2iso/$topic -m \"$message\""
        [[ "$retain" == "true" ]] && cmd="$cmd -r"
        [[ -n "$HA_MQTT_USER" ]] && cmd="$cmd -u $HA_MQTT_USER -P $HA_MQTT_PASSWORD"
        eval "$cmd" 2>/dev/null
    fi
}

# Hook für lib-status.sh
ha_notify() {
    local field="$1"
    local value="$2"
    
    # Status-File lesen und komplett zu MQTT publishen
    local status=$(get_status)
    
    if command -v jq &>/dev/null; then
        # Alle relevanten Felder publishen
        _ha_mqtt_publish "status" "$(echo "$status" | jq -r '.status')" true
        _ha_mqtt_publish "drive" "$(echo "$status" | jq -r '.drive')" true
        _ha_mqtt_publish "disc_type" "$(echo "$status" | jq -r '.disc.type')" true
        _ha_mqtt_publish "disc_label" "$(echo "$status" | jq -r '.disc.label')" true
        _ha_mqtt_publish "progress" "$(echo "$status" | jq -r '.progress.percent')" true
        _ha_mqtt_publish "progress_mb" "$(echo "$status" | jq -r '"\(.progress.mb_current)/\(.progress.mb_total)"')" true
        _ha_mqtt_publish "eta" "$(echo "$status" | jq -r '.progress.eta_minutes')" true
        _ha_mqtt_publish "current_method" "$(echo "$status" | jq -r '.current_method')" true
        
        # Statistiken
        _ha_mqtt_publish "stats/total" "$(echo "$status" | jq -r '.stats.total')" true
        _ha_mqtt_publish "stats/audio" "$(echo "$status" | jq -r '.stats.audio')" true
        _ha_mqtt_publish "stats/data" "$(echo "$status" | jq -r '.stats.data')" true
        _ha_mqtt_publish "stats/dvd" "$(echo "$status" | jq -r '.stats.dvd')" true
        _ha_mqtt_publish "stats/bd" "$(echo "$status" | jq -r '.stats.bd')" true
    fi
}

# Events (manueller Call aus Hauptscript)
ha_send_event() {
    local event_type="$1"  # finished, aborted, error
    local message="$2"
    
    _ha_mqtt_publish "event" "$event_type" false
    _ha_mqtt_publish "event_message" "$message" false
}
```

### Neue Bibliothek: `lib-webserver.sh`

```bash
#!/bin/bash
# disk2iso-lib/lib-webserver.sh
# Minimaler HTTP-Server für Status-Abfrage

WEB_PORT=8080

# Webserver starten
start_webserver() {
    if [[ "$WEB_ENABLED" != "true" ]]; then
        return
    fi
    
    # Python Simple HTTP Server (mit custom handler)
    python3 - <<'PYEOF' &
import json
from http.server import HTTPServer, BaseHTTPRequestHandler

class StatusHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/status':
            try:
                with open('/var/run/disk2iso/status.json') as f:
                    data = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(data.encode())
            except:
                self.send_response(500)
                self.end_headers()
        elif self.path == '/':
            # Einfaches HTML-Dashboard
            html = """<!DOCTYPE html>
<html><head><title>disk2iso Status</title>
<meta http-equiv="refresh" content="5">
</head><body>
<h1>disk2iso Live Status</h1>
<div id="status"></div>
<script>
fetch('/status')
  .then(r => r.json())
  .then(data => {
    document.getElementById('status').innerHTML = \`
      <p><strong>Status:</strong> \${data.status}</p>
      <p><strong>Laufwerk:</strong> \${data.drive}</p>
      <p><strong>Disc:</strong> \${data.disc.label} (\${data.disc.type})</p>
      <p><strong>Fortschritt:</strong> \${data.progress.percent}%</p>
      <progress value="\${data.progress.percent}" max="100"></progress>
      <p><strong>Restzeit:</strong> \${data.progress.eta_minutes} min</p>
    \`;
  });
</script>
</body></html>"""
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(html.encode())
        else:
            self.send_response(404)
            self.end_headers()

HTTPServer(('0.0.0.0', 8080), StatusHandler).serve_forever()
PYEOF
    
    echo $! > /var/run/disk2iso/webserver.pid
}

# Hook für lib-status.sh (optional, da Status-File automatisch aktualisiert wird)
web_notify() {
    # Nichts zu tun - Webserver liest direkt aus Status-File
    :
}
```

### Integration in `disk2iso.sh`

```bash
#!/bin/bash

# Libraries laden
source disk2iso-lib/lib-status.sh
source disk2iso-lib/lib-homeassistant.sh  # Optional
source disk2iso-lib/lib-webserver.sh      # Optional

# Initialisierung
init_status
start_webserver  # Falls WEB_ENABLED=true

# Hauptloop
while true; do
    # Disc eingelegt
    update_status "drive" "occupied"
    update_status "status" "detecting"
    
    # Disc erkannt
    update_disc_info "$DISC_TYPE" "$DISC_LABEL" "$SIZE_MB"
    update_status "status" "ripping"
    update_status "current_method" "$METHOD"
    
    # Fortschritt
    while ripping; do
        update_progress "$PERCENT" "$MB_DONE" "$MB_TOTAL" "$ETA"
        sleep 5
    done
    
    # Fertig
    update_status "status" "finished"
    ha_send_event "finished" "$DISC_LABEL erfolgreich gespeichert"
    update_stats
    
    update_status "drive" "empty"
    update_status "status" "idle"
done
```

### Vorteile des Hybrid-Ansatzes

| Aspekt | Bewertung |
|--------|-----------|
| **Code-Duplikation** | ✅ Minimal |
| **Konsistenz** | ✅ Garantiert (Single Source of Truth) |
| **Komplexität** | ✅ Niedrig-Mittel |
| **Erweiterbarkeit** | ✅ Sehr einfach (neue Backends via Hook) |
| **Performance** | ✅ Gut (File-I/O minimal) |
| **Unabhängigkeit** | ✅ Backends optional und entkoppelt |
| **Passt zu disk2iso** | ✅ Sehr gut (modulare Architektur) |

### Warum dieser Ansatz?

1. **Single Source of Truth** - JSON-File als zentrale Datenquelle
2. **Modulare Backends** - HA/Web sind optional und unabhängig
3. **Hook-System** - Einfache Erweiterung um Discord, Telegram, etc.
4. **Graceful Degradation** - Funktioniert auch ohne jq (sed-Fallback)
5. **Status-File nützlich** - Auch für CLI-Monitoring und Debugging
6. **Minimale Dependencies** - jq optional, Python für Web optional

## Weitere Ideen

[... existing content ...]
