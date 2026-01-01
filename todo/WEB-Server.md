# Web-First Architektur für disk2iso

## Übersicht

Dieses Dokument beschreibt die Web-First Architektur für disk2iso und bietet
eine moderne webbasierte Oberfläche für Disk-Imaging-Operationen. Das System
ist für den Betrieb in einem LXC-Container konzipiert, wobei die Web-Oberfläche
die primäre Interaktionsmethode darstellt, während minimale CLI-Unterstützung
für fortgeschrittene Benutzer erhalten bleibt.

## Architektur-Prinzipien

- **Web-First Design**: Primäre Interaktion über eine responsive Web-Oberfläche
- **Container-basiert**: Läuft in LXC-Containern für Isolation und Portabilität
- **RESTful API**: Sauberes API-Design für alle Operationen
- **Progressive Enhancement**: Kernfunktionalität funktioniert ohne JavaScript, verbesserte UX damit
- **Security-First**: Authentifizierung, Autorisierung und Audit-Logging integriert
- **Mobile-freundlich**: Responsives Design für Zugriff von jedem Gerät

## LXC Container Setup

### Container-Anforderungen

```bash
# Empfohlene LXC-Konfiguration
lxc.cgroup2.memory.max = 2G
lxc.cgroup2.cpu.max = 200000 100000  # 2 CPU-Kerne
lxc.mount.entry = /dev/sr0 dev/sr0 none bind,optional,create=file
lxc.mount.entry = /dev/sr1 dev/sr1 none bind,optional,create=file
```

### Installationsschritte

1.**Container erstellen**

```bash
lxc-create -n disk2iso -t download -- -d debian -r bookworm -a amd64
```

2.**Speicher konfigurieren**

```bash
# Speicher-Mount für ISO-Ausgabe hinzufügen
lxc config device add disk2iso storage disk source=/storage/isos path=/opt/disk2iso/output
```

3.**Abhängigkeiten installieren**

```bash
# Im Container
apt-get update
apt-get install -y python3 python3-pip python3-venv \
    ddrescue cdrdao cdrtools genisoimage \
    nginx python3-flask redis-server \
    udev udisks2
```

4.**Anwendung bereitstellen**

```bash
cd /opt/disk2iso
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Systemd Service

```ini
[Unit]
Description=disk2iso Web Service
After=network.target redis.service

[Service]
Type=notify
User=disk2iso
Group=disk2iso
WorkingDirectory=/opt/disk2iso
Environment="PATH=/opt/disk2iso/venv/bin"
ExecStart=/opt/disk2iso/venv/bin/gunicorn \
    --workers 4 \
    --bind unix:/run/disk2iso/disk2iso.sock \
    --access-logfile /var/log/disk2iso/access.log \
    --error-logfile /var/log/disk2iso/error.log \
    wsgi:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

## Web-Oberflächen-Spezifikationen

### 1. Dashboard-Seite (`/`)

**Zweck**: Hauptsteuerungszentrale für Disk-Imaging-Operationen

**Layout**:

```txt
┌─────────────────────────────────────────┐
│  disk2iso - Dashboard                   │
├─────────────────────────────────────────┤
│  [Active Jobs (2)]  [Completed (15)]    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ Job: movie_collection_disc1     │    │
│  │ Status: Running (45%)           │    │
│  │ Progress: ████████░░░░░░░░      │    │
│  │ Speed: 2.4 MB/s | ETA: 4:23     │    │
│  │ [Pause] [Cancel] [Details]      │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ Job: backup_dvd_2024            │    │
│  │ Status: Queued                  │    │
│  │ Position: #2 in queue           │    │
│  │ [Cancel] [Edit Priority]        │    │
│  └─────────────────────────────────┘    │
│                                         │
│  [+ New Imaging Job]                    │
│                                         │
│  System Status:                         │
│  • Available Drives: 2                  │
│  • Storage Free: 847 GB                 │
│  • CPU Usage: 12%                       │
│  • Memory: 456 MB / 2 GB                │
└─────────────────────────────────────────┘
```

**Features**:

- Echtzeit-Jobstatus-Updates (WebSocket oder SSE)
- Fortschrittsbalken mit Prozentangabe und ETA
- Schnellaktionen (Pause, Abbrechen, Fortsetzen)
- Systemressourcen-Überwachung
- Laufwerkserkennung und Status
- Ein-Klick-Job-Erstellung

**Wichtige UI-Elemente**:

- Job-Karten mit farbcodiertem Status (grün=läuft, blau=wartend, grau=abgeschlossen)
- Toast-Benachrichtigungen für Ereignisse
- Responsives Grid-Layout
- Auto-Refresh alle 2 Sekunden für aktive Jobs

### 2. Archiv-Seite (`/archive`)

**Zweck**: Durchsuchen, Suchen und Verwalten abgeschlossener ISO-Images

**Layout**:

```txt
┌─────────────────────────────────────────┐
│  Archive                                │
├─────────────────────────────────────────┤
│  [Search: _________] [Filter ▼] [Sort ▼]│
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ 📀 movie_collection_disc1.iso   │    │
│  │ 4.7 GB • Created: 2025-12-30    │    │
│  │ MD5: a3b4c5d6...                │    │
│  │ [Download] [Verify] [Delete]    │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ 💿 software_archive_2024.iso    │    │
│  │ 8.5 GB • Created: 2025-12-28    │    │
│  │ SHA256: f7e8d9a0...             │    │
│  │ [Download] [Verify] [Delete]    │    │
│  └─────────────────────────────────┘    │
│                                         │
│  Showing 1-20 of 156 items              │
│  [← Previous] [1] [2] [3] ... [Next →]  │
└─────────────────────────────────────────┘
```

**Features**:

- Volltextsuche über Metadaten
- Filter nach Datum, Größe, Typ, Status
- Sortierung nach Name, Datum, Größe
- Massenoperationen (Löschen, Verifizieren)
- Checksummen-Verifizierung
- Direkte Download-Links
- Seitennummerierung für große Archive
- Metadaten-Bearbeitung

**Erweiterte Features**:

- Tags und Kategorien
- Notizen und Beschreibungen
- Qualitätsbewertungen
- Verifizierungshistorie
- Metadaten-Export nach CSV/JSON

### 3. Konfigurations-Seite (`/config`)

**Zweck**: Systemeinstellungen und Präferenzen

**Bereiche**:

#### Speicher-Einstellungen

```txt
┌─────────────────────────────────────────┐
│ Speicher-Konfiguration                  │
├─────────────────────────────────────────┤
│ Ausgabe-Verzeichnis:                    │
│ [/opt/disk2iso/output] [Durchsuchen]    │
│                                         │
│ Auto-Bereinigung:                       │
│ ☑ Quelle bei Erfolg löschen             │
│ ☑ Logs aufbewahren für [30] Tage        │
│                                         │
│ Speicher-Schwellenwerte:                │
│ [⚠️ Warnung bei 90% voll]               │
│ [🛑 Stopp bei 95% voll]                 │
└─────────────────────────────────────────┘
```

#### Imaging-Standards

```txt
┌─────────────────────────────────────────┐
│ Standard Imaging-Optionen               │
├─────────────────────────────────────────┤
│ Leseversuche: [5]                       │
│ Sektorgröße: [2048] Bytes               │
│ Nach Erstellung verifizieren: ☑ Aktiv   │
│ Checksummen generieren: ☑ MD5 ☑ SHA256 │
│ Kompression: [Keine ▼]                  │
│ Priorität: [Normal ▼]                   │
└─────────────────────────────────────────┘
```

#### Benachrichtigungs-Einstellungen

```txt
┌─────────────────────────────────────────┐
│ Benachrichtigungen                      │
├─────────────────────────────────────────┤
│ ☑ E-Mail bei Abschluss                  │
│   E-Mail: [user@example.com]            │
│                                         │
│ ☑ Webhook-Benachrichtigungen            │
│   URL: [https://hooks.example.com]      │
│                                         │
│ ☑ Browser-Benachrichtigungen            │
└─────────────────────────────────────────┘
```

#### Benutzerverwaltung

```txt
┌─────────────────────────────────────────┐
│ Benutzer & Authentifizierung            │
├─────────────────────────────────────────┤
│ Aktueller Benutzer: admin               │
│ Rolle: Administrator                    │
│                                         │
│ [Passwort ändern]                       │
│ [API-Keys verwalten]                    │
│ [Audit-Log anzeigen]                    │
│                                         │
│ Benutzer:                               │
│ • admin (Administrator)                 │
│ • operator (Operator) [Bearb.] [Lösch.] │
│ [+ Benutzer hinzufügen]                 │
└─────────────────────────────────────────┘
```

## API-Endpunkte

### Authentifizierung

Alle API-Endpunkte erfordern Authentifizierung via:

- Session-Cookies (Web-Oberfläche)
- API-Key im Header: `X-API-Key: <key>`
- JWT Bearer-Token: `Authorization: Bearer <token>`

### Kern-Endpunkte

#### Jobs

```http
GET /api/v1/jobs
```

Liste alle Jobs mit Seitennummerierung und Filterung.

**Query-Parameter**:

- `status`: Filter nach Status (running, queued, completed, failed)
- `limit`: Einträge pro Seite (Standard: 50)
- `offset`: Seitennummerierungs-Offset
- `sort`: Sortierfeld (created, updated, name)

**Antwort**:

```json
{
  "jobs": [
    {
      "id": "job_123456",
      "name": "movie_collection_disc1",
      "status": "running",
      "progress": 45,
      "created_at": "2025-12-31T14:00:00Z",
      "updated_at": "2025-12-31T14:15:00Z",
      "device": "/dev/sr0",
      "output_file": "/opt/disk2iso/output/movie_collection_disc1.iso",
      "size_bytes": 4700000000,
      "speed_bps": 2400000,
      "eta_seconds": 263
    }
  ],
  "total": 156,
  "limit": 50,
  "offset": 0
}
```

---

```http
POST /api/v1/jobs
```

Neuen Imaging-Job erstellen.

**Request-Body**:

```json
{
  "name": "my_disk_image",
  "device": "/dev/sr0",
  "options": {
    "read_attempts": 5,
    "verify": true,
    "checksums": ["md5", "sha256"],
    "priority": "normal"
  }
}
```

**Antwort**:

```json
{
  "id": "job_123457",
  "status": "queued",
  "created_at": "2025-12-31T14:20:00Z"
}
```

---

```http
GET /api/v1/jobs/{job_id}
```

Detaillierte Job-Informationen abrufen.

---

```http
PATCH /api/v1/jobs/{job_id}
```

Job aktualisieren (pausieren, fortsetzen, abbrechen, Priorität ändern).

**Request-Body**:

```json
{
  "action": "pause"  // oder "resume", "cancel"
}
```

---

```http
DELETE /api/v1/jobs/{job_id}
```

Job abbrechen und entfernen.

---

#### Archive

```http
GET /api/v1/archives
```

Abgeschlossene ISO-Images auflisten.

**Antwort**:

```json
{
  "archives": [
    {
      "id": "archive_789",
      "filename": "movie_collection_disc1.iso",
      "path": "/opt/disk2iso/output/movie_collection_disc1.iso",
      "size_bytes": 4700000000,
      "created_at": "2025-12-30T20:00:00Z",
      "checksums": {
        "md5": "a3b4c5d6e7f8g9h0",
        "sha256": "f7e8d9a0b1c2d3e4f5g6h7i8j9k0l1m2"
      },
      "metadata": {
        "label": "Movie Collection Vol 1",
        "tags": ["movies", "backup"],
        "notes": "Personal movie collection"
      }
    }
  ]
}
```

---

```http
GET /api/v1/archives/{archive_id}
```

Archiv-Details abrufen.

---

```http
GET /api/v1/archives/{archive_id}/download
```

ISO-Datei herunterladen.

---

```http
POST /api/v1/archives/{archive_id}/verify
```

ISO-Integrität gegen Checksummen verifizieren.

---

```http
PATCH /api/v1/archives/{archive_id}
```

Metadaten aktualisieren.

**Request-Body**:

```json
{
  "metadata": {
    "label": "Updated Label",
    "tags": ["movies", "backup", "2024"],
    "notes": "Updated notes"
  }
}
```

---

```http
DELETE /api/v1/archives/{archive_id}
```

Archiv löschen.

---

#### Geräte

```http
GET /api/v1/devices
```

Verfügbare optische Laufwerke auflisten.

**Antwort**:

```json
{
  "devices": [
    {
      "path": "/dev/sr0",
      "vendor": "ASUS",
      "model": "DVD-RW DRW-24B1ST",
      "status": "idle",
      "has_media": true,
      "media_type": "dvd",
      "media_size_bytes": 4700000000
    }
  ]
}
```

---

```http
POST /api/v1/devices/{device}/eject
```

Medium aus Laufwerk auswerfen.

---

#### System

```http
GET /api/v1/system/status
```

Systemstatus und Ressourcennutzung abrufen.

**Antwort**:

```json
{
  "status": "healthy",
  "version": "2.0.0",
  "uptime_seconds": 86400,
  "resources": {
    "cpu_percent": 12.5,
    "memory_used_bytes": 478150656,
    "memory_total_bytes": 2147483648,
    "storage_used_bytes": 102400000000,
    "storage_total_bytes": 1000000000000
  },
  "services": {
    "redis": "running",
    "nginx": "running"
  }
}
```

---

```http
GET /api/v1/system/config
```

Aktuelle Konfiguration abrufen.

---

```http
PATCH /api/v1/system/config
```

Konfiguration aktualisieren.

---

#### Logs

```http
GET /api/v1/logs
```

Anwendungs-Logs abrufen.

**Query-Parameter**:

- `level`: Filter nach Level (debug, info, warning, error)
- `since`: ISO-Zeitstempel
- `limit`: Anzahl der Einträge

---

### WebSocket-Endpunkte

```http
ws://server/api/v1/ws/jobs
```

Echtzeit-Job-Updates.

**Nachrichten-Format**:

```json
{
  "type": "job_update",
  "job_id": "job_123456",
  "data": {
    "status": "running",
    "progress": 46,
    "speed_bps": 2450000,
    "eta_seconds": 258
  }
}
```

## Sicherheitsüberlegungen

### Authentifizierung & Autorisierung

1. **Benutzerrollen**:
   - `admin`: Voller Systemzugriff
   - `operator`: Jobs erstellen/verwalten, Archive anzeigen
   - `viewer`: Nur-Lese-Zugriff

2. **Passwort-Richtlinie**:
   - Mindestens 12 Zeichen
   - Muss Groß-, Kleinbuchstaben und Zahlen enthalten
   - Gehashed mit bcrypt (Kostenfaktor 12)
   - Erzwungene Rotation alle 90 Tage

3. **API-Keys**:
   - Generiert mit kryptographisch sicherem Zufallsgenerator
   - Können auf spezifische Berechtigungen beschränkt werden
   - Ablaufbar
   - Widerrufbar

4. **Session-Verwaltung**:
   - HTTPOnly, Secure, SameSite Cookies
   - 30-Minuten Timeout mit Aktivitätsverlängerung
   - Maximale 24-Stunden Lebensdauer
   - Limits für gleichzeitige Sessions

### Netzwerk-Sicherheit

```nginx
# Nginx-Konfiguration
server {
    listen 443 ssl http2;
    server_name disk2iso.local;
    
    ssl_certificate /etc/ssl/certs/disk2iso.crt;
    ssl_certificate_key /etc/ssl/private/disk2iso.key;
    ssl_protocols TLSv1.3 TLSv1.2;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    # Sicherheits-Header
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';" always;
    
    # Rate-Limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req zone=api burst=20 nodelay;
    
    location / {
        proxy_pass http://unix:/run/disk2iso/disk2iso.sock;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Eingabe-Validierung

- Alle Benutzereingaben werden bereinigt und validiert
- Path-Traversal-Prävention
- SQL-Injection-Schutz (parametrisierte Queries)
- XSS-Prävention (Output-Encoding)
- CSRF-Tokens für zustandsändernde Operationen
- Datei-Upload-Beschränkungen (Größe, Typ)

### Audit-Logging

Alle sicherheitsrelevanten Ereignisse werden protokolliert:

```json
{
  "timestamp": "2025-12-31T14:21:04Z",
  "event_type": "authentication",
  "action": "login_success",
  "user": "admin",
  "ip_address": "192.168.1.100",
  "user_agent": "Mozilla/5.0...",
  "details": {
    "method": "password"
  }
}
```

Verfolgte Ereignisse:

- Login/Logout-Versuche
- Passwort-Änderungen
- API-Key-Generierung/-Widerruf
- Konfigurations-Änderungen
- Job-Erstellung/-Löschung
- Archiv-Löschung
- Berechtigungs-Änderungen

### Dateisystem-Sicherheit

- Ausgabe-Verzeichnis-Berechtigungen: `755` (rwxr-xr-x)
- ISO-Dateien: `644` (rw-r--r--)
- Konfigurations-Dateien: `600` (rw-------)
- Service läuft als dedizierter Benutzer `disk2iso`
- Keine weltweit beschreibbaren Dateien
- AppArmor/SELinux-Profile

### Backup & Wiederherstellung

```bash
# Automatisiertes Backup-Skript
#!/bin/bash
BACKUP_DIR="/backup/disk2iso"
DATE=$(date +%Y%m%d_%H%M%S)

# Datenbank sichern
sqlite3 /opt/disk2iso/data/disk2iso.db ".backup ${BACKUP_DIR}/db_${DATE}.db"

# Konfiguration sichern
tar -czf ${BACKUP_DIR}/config_${DATE}.tar.gz /opt/disk2iso/config/

# Nur letzte 30 Tage behalten
find ${BACKUP_DIR} -type f -mtime +30 -delete
```

## Minimale CLI-Nutzung

Während die Web-Oberfläche primär ist, sind CLI-Tools verfügbar für:

### Notfall-Operationen

```bash
# Service-Status prüfen
disk2iso status

# Notfall-Stopp aller Jobs
disk2iso stop --all

# Manuelle Job-Erstellung (Web umgehen)
disk2iso create --device /dev/sr0 --output /backup/emergency.iso

# ISO verifizieren
disk2iso verify /path/to/image.iso
```

### System-Administration

```bash
# Benutzerverwaltung
disk2iso user add <benutzername> --role operator
disk2iso user reset-password <benutzername>
disk2iso user list

# Konfiguration
disk2iso config get
disk2iso config set storage.output_dir /neuer/pfad

# Backup/Wiederherstellung
disk2iso backup --output /backup/disk2iso_backup.tar.gz
disk2iso restore --input /backup/disk2iso_backup.tar.gz
```

### Automatisierung & Skripting

```bash
# API-Interaktion via curl
curl -X POST https://disk2iso.local/api/v1/jobs \
  -H "X-API-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "automated_backup",
    "device": "/dev/sr0",
    "options": {"verify": true}
  }'

# Stapelverarbeitung
for device in /dev/sr*; do
  if disk2iso device has-media $device; then
    disk2iso create --device $device --auto-name
  fi
done
```

### Monitoring-Integration

```bash
# Prometheus-Metriken exportieren
disk2iso metrics --format prometheus > /var/lib/prometheus/disk2iso.prom

# Health-Check für Monitoring-Systeme
disk2iso health && echo "OK" || echo "FAIL"

# Log-Streaming
disk2iso logs --follow --level error | logger -t disk2iso
```

## Technologie-Stack

### Backend

- **Framework**: Flask 3.x (Python 3.11+)
- **WSGI-Server**: Gunicorn mit gevent-Workern
- **Datenbank**: SQLite 3 (oder PostgreSQL für Multi-Instanz)
- **Task-Queue**: Redis + RQ (Redis Queue)
- **Cache**: Redis

### Frontend

- **Template-Engine**: Jinja2
- **CSS-Framework**: Tailwind CSS oder Bootstrap 5
- **JavaScript**: Vanilla JS + Alpine.js für Reaktivität
- **Echtzeit**: Server-Sent Events (SSE) oder WebSockets

### DevOps

- **Container**: LXC/LXD
- **Reverse-Proxy**: Nginx
- **Prozess-Manager**: systemd
- **Logging**: Python-Logging + logrotate
- **Monitoring**: Prometheus-Metriken-Endpunkt

## Entwicklungs-Roadmap

### Phase 1: Kern-Web-Oberfläche (v2.0)

- [ ] Basis-Dashboard mit Job-Auflistung
- [ ] Job-Erstellung und -Verwaltung
- [ ] Archiv-Durchsuchung
- [ ] Geräteerkennung und -auswahl
- [ ] Benutzer-Authentifizierung

### Phase 2: Erweiterte Features (v2.1)

- [ ] Echtzeit-Fortschritts-Updates
- [ ] Stapeloperationen
- [ ] Erweiterte Filterung und Suche
- [ ] Benachrichtigungssystem
- [ ] API-Dokumentation (Swagger/OpenAPI)

### Phase 3: Enterprise-Features (v2.2)

- [ ] Multi-User-Unterstützung mit RBAC
- [ ] Audit-Logging und Compliance
- [ ] LDAP/Active Directory-Integration
- [ ] Hochverfügbarkeits-Setup
- [ ] Prometheus-Metriken

### Phase 4: Erweiterungen (v2.3+)

- [ ] Webhook-Integrationen
- [ ] Cloud-Storage-Backends (S3, Azure Blob)
- [ ] Mobile-App (React Native)
- [ ] Erweiterte Zeitplanung
- [ ] Disk-Image-Mounting/-Durchsuchung

## Deployment-Beispiel

```bash
# Vollständiges Deployment-Skript
#!/bin/bash
set -e

# Variablen
CONTAINER_NAME="disk2iso"
APP_DIR="/opt/disk2iso"
OUTPUT_DIR="/storage/isos"

# LXC-Container erstellen
lxc-create -n ${CONTAINER_NAME} -t download -- \
  -d debian -r bookworm -a amd64

# Container konfigurieren
cat >> /var/lib/lxc/${CONTAINER_NAME}/config <<EOF
lxc.cgroup2.memory.max = 2G
lxc.cgroup2.cpu.max = 200000 100000
lxc.mount.entry = /dev/sr0 dev/sr0 none bind,optional,create=file
lxc.mount.entry = ${OUTPUT_DIR} opt/disk2iso/output none bind,create=dir
EOF

# Container starten
lxc-start -n ${CONTAINER_NAME}

# Anwendung installieren
lxc-attach -n ${CONTAINER_NAME} -- bash <<'SETUP'
# System aktualisieren
apt-get update && apt-get upgrade -y

# Abhängigkeiten installieren
apt-get install -y python3 python3-pip python3-venv \
  ddrescue cdrdao cdrtools genisoimage \
  nginx redis-server git

# Anwendungsbenutzer erstellen
useradd -r -s /bin/bash -d /opt/disk2iso disk2iso

# Repository klonen
git clone https://github.com/DirkGoetze/disk2iso.git /opt/disk2iso
chown -R disk2iso:disk2iso /opt/disk2iso

# Python-Umgebung einrichten
su - disk2iso -c "
  python3 -m venv /opt/disk2iso/venv
  source /opt/disk2iso/venv/bin/activate
  pip install -r /opt/disk2iso/requirements.txt
"

# Services konfigurieren
systemctl enable redis-server
systemctl enable nginx
systemctl enable disk2iso

# Services starten
systemctl start redis-server
systemctl start disk2iso
systemctl start nginx

echo "Deployment abgeschlossen!"
SETUP

echo "Zugriff auf die Web-Oberfläche unter: https://$(lxc-info -n ${CONTAINER_NAME} -iH)"
```

## Fazit

Diese Web-First-Architektur verwandelt disk2iso von einem reinen CLI-Tool in eine moderne, zugängliche Webanwendung, die sowohl für einzelne Benutzer als auch für Unternehmens-Deployments geeignet ist. Die LXC-Containerisierung gewährleistet Portabilität und Isolation, während die umfassende API die Integration in bestehende Workflows und Automatisierungssysteme ermöglicht.

Das Design priorisiert Sicherheit, Benutzerfreundlichkeit und Wartbarkeit mit klarer Trennung der Belange zwischen Web-Oberfläche, API und Kern-Imaging-Funktionalität. Die minimale CLI bleibt für Sonderfälle und Automatisierung verfügbar, aber die Web-Oberfläche bietet die primäre Benutzererfahrung.

---

**Zuletzt aktualisiert**: 2025-12-31  
**Version**: 2.0  
**Autor**: DirkGoetze
