# Web-First Architektur für disk2iso

## Übersicht

Dieses Dokument beschreibt die Web-First Architektur für disk2iso und bietet eine moderne webbasierte Oberfläche für Disk-Imaging-Operationen. Das System ist für den Betrieb in einem LXC-Container konzipiert für lokale Netzwerke, wobei die Web-Oberfläche die primäre Interaktionsmethode darstellt, während minimale CLI-Unterstützung für fortgeschrittene Benutzer erhalten bleibt.

## Architektur-Prinzipien

- **Web-First Design**: Primäre Interaktion über eine responsive Web-Oberfläche
- **Container-basiert**: Läuft in LXC-Containern für Isolation und Portabilität
- **Einfacher Stack**: Flask mit eingebautem Server für lokale Netzwerke
- **RESTful API**: Sauberes API-Design für alle Operationen
- **Progressive Enhancement**: Kernfunktionalität funktioniert ohne JavaScript, verbesserte UX damit
- **Mobile-freundlich**: Responsives Design für Zugriff von jedem Gerät

## Verzeichnisstruktur

```
/opt/disk2iso/
├── app.py                    # Haupt-Flask-Anwendung
├── disk2iso/                 # Kern-Imaging-Logik
│   ├── __init__.py
│   ├── imaging.py           # ISO-Erstellung
│   ├── devices.py           # Geräteerkennung
│   └── utils.py             # Hilfsfunktionen
├── www/
│   ├── templates/           # Jinja2 HTML-Templates
│   │   ├── base.html
│   │   ├── dashboard.html
│   │   ├── archive.html
│   │   └── config.html
│   └── static/              # Statische Assets
│       ├── css/
│       │   └── style.css
│       ├── js/
│       │   └── app.js
│       └── img/
├── data/
│   └── disk2iso.db          # SQLite-Datenbank
├── config/
│   └── config.yaml          # Konfigurationsdatei
└── requirements.txt
```

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

1. **Container erstellen**

```bash
lxc-create -n disk2iso -t download -- -d debian -r bookworm -a amd64
```

2. **Speicher konfigurieren**

```bash
# Speicher-Mount für ISO-Ausgabe hinzufügen
lxc config device add disk2iso storage disk source=/storage/isos path=/opt/disk2iso/output
```

3. **Abhängigkeiten installieren**

```bash
# Im Container
apt-get update
apt-get install -y python3 python3-pip python3-venv \
    ddrescue cdrdao cdrtools genisoimage \
    python3-flask redis-server \
    udev udisks2
```

4. **Anwendung bereitstellen**

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
Type=simple
User=disk2iso
Group=disk2iso
WorkingDirectory=/opt/disk2iso
Environment="PATH=/opt/disk2iso/venv/bin"
ExecStart=/opt/disk2iso/venv/bin/python app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

## Flask Anwendungsstruktur

### Basis-Flask-App (app.py)

```python
from flask import Flask, render_template, jsonify, request, send_from_directory
import os

app = Flask(__name__, 
            static_folder='www/static',
            template_folder='www/templates')

@app.route('/')
def dashboard():
    return render_template('dashboard.html')

@app.route('/archive')
def archive():
    return render_template('archive.html')

@app.route('/config')
def config():
    return render_template('config.html')

# API Endpunkte
@app.route('/api/v1/jobs')
def get_jobs():
    # Liste alle Jobs
    return jsonify({'jobs': []})

@app.route('/api/v1/jobs', methods=['POST'])
def create_job():
    # Erstelle neuen Job
    data = request.get_json()
    return jsonify({'id': 'job_123', 'status': 'queued'})

if __name__ == '__main__':
    # Flask eingebauter Server für lokales Netzwerk
    app.run(host='0.0.0.0', port=8080, debug=False)
```
