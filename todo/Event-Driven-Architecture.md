# Event-Driven Architecture Migration

**Ziel:** Entkopplung von API-JSON-Schreibvorgängen und MQTT-Publishing

**Status:** In Arbeit
**Gestartet:** 10.01.2026
**Geschätzte Dauer:** 8-10 Stunden

---

## Phase 1: Core-Entkopplung ✅ ABGESCHLOSSEN

**Dauer:** 2-3 Stunden
**Status:** ABGESCHLOSSEN (10.01.2026 23:02)

### Aufgaben:
- [x] Neue `lib-api.sh` erstellt mit unabhängigen API-Funktionen
- [x] `api_write_json()` - Low-level JSON-Writer (atomic)
- [x] `api_update_status()` - Status-Updates (idle/copying/waiting/completed/error)
- [x] `api_update_progress()` - Fortschritts-Updates
- [x] `api_add_history()` - History-Einträge
- [x] `api_init()` - Initialisierung beim Service-Start
- [x] `disk2iso.sh`: lib-api.sh laden
- [x] `disk2iso.sh`: api_init() beim Start aufrufen
- [x] `disk2iso.sh`: api_update_status() VOR mqtt_publish_state() aufrufen
- [x] `lib-mqtt.sh`: api_write_json() VOR MQTT_AVAILABLE Check verschoben
- [x] Test: JSON-Dateien werden auch bei MQTT_ENABLED=false geschrieben
- [x] Test: Service startet und schreibt JSON-Updates
- [x] Test: Web-UI zeigt Live-Status korrekt an
- [x] Deployment getestet

### Erfolgskriterien:
- ✅ JSON-Dateien werden IMMER geschrieben (unabhängig von MQTT)
- ✅ Web-UI zeigt aktuellen Status (service_running: true, status: idle)
- ✅ JSON-Timestamps sind aktuell (2026-01-10T23:01:05)
- ✅ Keine Regression: Code funktioniert weiterhin

### Änderungen:
- **NEU:** `lib/lib-api.sh` - Separate API-Library (240 Zeilen)
- **GEÄNDERT:** `disk2iso.sh` - Lädt lib-api.sh, ruft api_* Funktionen auf
- **GEÄNDERT:** `lib/lib-mqtt.sh` - api_write_json() vor MQTT-Check
- **DEPLOYMENT:** Beide Services laufen, JSON-Updates funktionieren

---

## Phase 1b: State Machine Implementierung ✅ ABGESCHLOSSEN

**Dauer:** 1.5 Stunden (geplant: 3-4h)
**Status:** ABGESCHLOSSEN (10.01.2026 23:22)
**Priorität:** HOCH (Besser als Phase 2, weil Basis für alles)

### Problem:
- Aktuelle Logik: Service crasht und restartet wenn kein Laufwerk gefunden wird
- Ineffizient: Ständige systemd Restarts statt kontinuierliches Polling
- Unklare States: "idle" bedeutet viele verschiedene Zustände

### Lösung: State Machine
Kontinuierlicher Service mit klaren Zustandsübergängen:

**States:**
1. `initializing` - Service startet
2. `waiting_for_drive` - Polling alle 20s für Laufwerk
3. `drive_detected` - Laufwerk gefunden (/dev/sr0)
4. `waiting_for_media` - Warte auf eingelegtes Medium
5. `media_detected` - Medium eingelegt
6. `analyzing` - Erkenne Medientyp
7. `copying` - ISO wird erstellt
8. `completed` - Erfolgreich
9. `error` - Fehler aufgetreten
10. `waiting_for_removal` - Warte auf Medienwechsel
11. `idle` - Kurze Pause vor neuem Zyklus

### Aufgaben:
- [x] State-Definitionen in disk2iso.sh (11 readonly Konstanten)
- [x] Polling-Intervalle konfigurierbar (POLL_DRIVE_INTERVAL=20s, POLL_MEDIA_INTERVAL=2s, POLL_REMOVAL_INTERVAL=5s)
- [x] Hauptschleife: `while true` statt Exit bei "kein Laufwerk"
- [x] `transition_to_state()` Funktion - Zentraler State-Handler
- [x] State: `initializing` → api_update_status()
- [x] State: `waiting_for_drive` → Polling alle 20s
- [x] State: `drive_detected` → Log welches Device + ensure_device_ready()
- [x] State: `waiting_for_media` → Polling für Medium
- [x] State: `media_detected` → wait_for_disc_ready()
- [x] State: `analyzing` → Medientyp-Erkennung + Label
- [x] State: `copying` → Bestehende Copy-Logik (copy_disc_to_iso)
- [x] State: `completed` → Kurze Pause für Anzeige
- [x] State: `error` → Fehler loggen, zu waiting_for_removal
- [x] State: `waiting_for_removal` → Polling bis Medium entfernt
- [x] State: `idle` → Kurze Pause, zurück zu waiting_for_media
- [x] Fehlerbehandlung: Laufwerk während Betrieb entfernt (in waiting_for_media)
- [x] API-Updates bei jedem State-Übergang
- [x] API_DIR Konflikt behoben (lib-mqtt.sh definiert nicht mehr)
- [x] main() vereinfacht - kein exit(1) mehr
- [x] Deployment und Verifikation

### Erfolgskriterien:
- ✅ Service läuft kontinuierlich (kein Exit/Restart)
- ✅ Klare Status-Anzeige in Web-UI für jeden State
- ✅ Polling-Intervalle einstellbar (als readonly Konstanten)
- ✅ Robuste Fehlerbehandlung (Laufwerk entfernt, Medium-Fehler)
- ✅ API-JSON Updates funktionieren
- ✅ Keine API_DIR Fehler mehr

### Änderungen:
- **GEÄNDERT:** `disk2iso.sh` Kopf - 11 State-Konstanten + 3 Polling-Intervalle
- **NEU:** `transition_to_state()` Funktion (80 Zeilen) - Zentrale State-Verwaltung
- **NEU:** `run_state_machine()` Funktion (120 Zeilen) - Hauptschleife mit State-Logik
- **GEÄNDERT:** `main()` - Kein exit(1) mehr, ruft run_state_machine() auf
- **ENTFERNT:** `monitor_cdrom()` - Ersetzt durch State Machine
- **GEÄNDERT:** `lib/lib-mqtt.sh` - API_DIR Definition entfernt (Konflikt)

### Test-Status:
- ✅ Service startet ohne Fehler
- ✅ State Machine läuft (INITIALIZING → WAITING_FOR_DRIVE)
- ✅ Polling funktioniert (alle 20s nach Laufwerk suchen)
- ✅ API_DIR Fehler behoben
- ⏳ BEREIT für Volltest mit echtem Laufwerk + Medium

---

## Phase 2: MQTT File Watcher (TODO)

**Dauer:** 3-4 Stunden
**Status:** AUSSTEHEND

### Aufgaben:
- [ ] Entscheidung: Python watchdog vs. Bash inotifywait
- [ ] Verzeichnis erstellen: `/opt/disk2iso/mqtt-watcher/`
- [ ] Watcher-Script implementieren
  - [ ] File-Watching auf /opt/disk2iso/api/*.json
  - [ ] MQTT-Publish bei Änderungen
  - [ ] Debouncing (max 1 update/sec pro Datei)
  - [ ] Fehlerbehandlung & Logging
  - [ ] Config aus config.sh lesen
- [ ] Lokale Tests mit Mosquitto
- [ ] Performance-Tests (CPU/Memory bei häufigen Updates)

### Erfolgskriterien:
- ✅ Watcher startet und überwacht JSON-Dateien
- ✅ MQTT-Messages werden bei JSON-Änderungen gesendet
- ✅ Keine CPU-Last im Idle
- ✅ Robuste Fehlerbehandlung (MQTT Broker down, File-Errors)

---

## Phase 3: Systemd Integration (TODO)

**Dauer:** 1 Stunde
**Status:** AUSSTEHEND

### Aufgaben:
- [ ] systemd Service-Datei erstellen: `disk2iso-mqtt.service`
- [ ] Dependencies konfigurieren: After=disk2iso.service
- [ ] Environment-File Integration (Config aus config.sh)
- [ ] Auto-Start konfigurieren
- [ ] Service-Installation in install.sh integrieren
- [ ] Uninstall-Script anpassen
- [ ] Dokumentation: Service-Management

### Erfolgskriterien:
- ✅ Service startet automatisch mit disk2iso.service
- ✅ Service restartet bei Fehlern (Restart=always)
- ✅ `systemctl status disk2iso-mqtt` zeigt Status korrekt
- ✅ Installation/Deinstallation funktioniert sauber

---

## Phase 4: Cleanup & Dokumentation (TODO)

**Dauer:** 1-2 Stunden
**Status:** AUSSTEHEND

### Aufgaben:
- [ ] Alte MQTT-Logik aus lib-mqtt.sh entfernen (oder als deprecated markieren)
- [ ] Code-Dokumentation aktualisieren
- [ ] README.md: Architektur-Diagramm hinzufügen
- [ ] Installation.md: MQTT-Watcher-Setup dokumentieren
- [ ] Entwickler-Doku: Wie man eigene Watcher schreibt
- [ ] Changelog aktualisieren
- [ ] Version auf 1.4.0 erhöhen

### Erfolgskriterien:
- ✅ Keine toten Code-Pfade
- ✅ Dokumentation beschreibt aktuelle Architektur
- ✅ User versteht wie MQTT-Integration funktioniert

---

## Testing-Checkliste (TODO)

### Funktionstests:
- [ ] JSON-Dateien werden bei Status-Änderungen aktualisiert
- [ ] Web-UI zeigt Live-Status korrekt
- [ ] MQTT-Messages kommen bei Home Assistant an
- [ ] Service überlebt Neustart
- [ ] MQTT Broker Ausfall wird behandelt
- [ ] Disc-Erkennung triggert Status-Update
- [ ] Kopier-Fortschritt wird aktualisiert
- [ ] Abschluss/Fehler werden korrekt gemeldet

### Performance-Tests:
- [ ] CPU-Last bei Idle: < 1%
- [ ] Memory: MQTT-Watcher < 50MB
- [ ] Latenz: JSON-Update → MQTT < 1 Sekunde
- [ ] Kein Memory-Leak bei 100 Kopiervorgängen

### Edge Cases:
- [ ] Sehr schnelle Status-Änderungen (< 1 Sekunde)
- [ ] Große JSON-Dateien (> 100KB)
- [ ] Gleichzeitiges Schreiben mehrerer JSONs
- [ ] MQTT Broker langsam/timeout
- [ ] File System voll

---

## Zukünftige Erweiterungen (Ideen)

### Weitere File Watcher:
- [ ] **Webhook-Watcher:** Discord/Slack Notifications
- [ ] **InfluxDB-Watcher:** Metriken für Grafana
- [ ] **Telegram-Bot:** Push-Notifications
- [ ] **Prometheus-Exporter:** Monitoring-Integration
- [ ] **S3-Uploader:** Backup der ISOs in Cloud

### API-Verbesserungen:
- [ ] REST API: /api/control/start, /api/control/stop
- [ ] WebSocket für Echtzeit-Updates (statt Polling)
- [ ] GraphQL Interface
- [ ] Multi-Server Support (mehrere disk2iso Instanzen)

---

## Notizen

### Architektur-Entscheidungen:
- **Warum File Watcher?** Entkopplung von Business-Logik und Integration-Layer
- **Warum nicht direkt MQTT in disk2iso.sh?** Separation of Concerns, Fehlertoleranz
- **Python vs. Bash?** Python für komplexere Logik, Bash für einfache Fälle

### Lessons Learned:
- (Hier Erkenntnisse während Implementierung festhalten)

---

## Links & Ressourcen

- Python watchdog: https://python-watchdog.readthedocs.io/
- paho-mqtt: https://www.eclipse.org/paho/index.php?page=clients/python/index.php
- inotify-tools: https://github.com/inotify-tools/inotify-tools
- systemd Service-Units: https://www.freedesktop.org/software/systemd/man/systemd.service.html
