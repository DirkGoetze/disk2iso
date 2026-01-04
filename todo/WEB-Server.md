# WEB-Server für disk2iso

## Übersicht

Dieses Dokument beschreibt die Implementierung eines Web-Servers für das disk2iso-Projekt. Der Web-Server ermöglicht die Überwachung und Verwaltung des Archivierungsprozesses über eine benutzerfreundliche Web-Oberfläche.

## Ziele

- **Statusüberwachung**: Echtzeit-Anzeige des aktuellen Archivierungsstatus
- **Archivverwaltung**: Übersicht über archivierte ISO-Dateien
- **Log-Einsicht**: Zugriff auf Systemlogs und Archivierungsprotokolle
- **Benutzerfreundlichkeit**: Intuitive Web-Oberfläche für einfache Bedienung
- **Systemintegration**: Nahtlose Integration in die bestehende disk2iso-Infrastruktur

## Technologie-Stack

- **Web-Framework**: Flask (Python)
- **Template-Engine**: Jinja2
- **Frontend**: HTML5, CSS3, JavaScript
- **Webserver**: Gunicorn (WSGI)
- **Reverse Proxy**: Nginx (optional)
- **Systemd**: Service-Integration für automatischen Start

## Architektur

```
┌─────────────────┐
│   Web-Browser   │
└────────┬────────┘
         │ HTTP
         ▼
┌─────────────────┐
│  Flask App      │
│  - Routen       │
│  - Templates    │
│  - API-Endpkte  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  disk2iso       │
│  - Status-Daten │
│  - Archive      │
│  - Logs         │
└─────────────────┘
```

## Detaillierter Umsetzungsplan

### Phase 1: Installation und Grundeinrichtung

**Ziel**: Erweiterung des Install-Skripts um Web-Server-Komponenten

**Aufgaben**:
1. Python3 und pip Installation prüfen/installieren
2. Flask und Abhängigkeiten installieren
3. Verzeichnisstruktur für Web-App erstellen
4. Konfigurationsdateien anlegen

**Code-Beispiel für install.sh-Erweiterung**:

```bash
# In install.sh ergänzen:

install_web_dependencies() {
    echo "Installiere Web-Server-Abhängigkeiten..."
    
    # Python3 und pip installieren
    apt-get install -y python3 python3-pip python3-venv
    
    # Virtuelles Environment erstellen
    python3 -m venv /opt/disk2iso/venv
    
    # Abhängigkeiten installieren
    /opt/disk2iso/venv/bin/pip install --upgrade pip
    /opt/disk2iso/venv/bin/pip install flask gunicorn
    
    # Web-Verzeichnisstruktur erstellen
    mkdir -p /opt/disk2iso/web/{templates,static/{css,js},logs}
    
    echo "Web-Server-Abhängigkeiten erfolgreich installiert."
}

# In der Hauptinstallationsroutine aufrufen:
install_web_dependencies
```

**Erfolgskriterien**:
- Python3 und Flask sind installiert
- Verzeichnisstruktur ist angelegt
- Virtuelle Umgebung ist funktionsfähig

---

### Phase 2: Hello World Test

**Ziel**: Grundlegende Flask-Anwendung zum Testen der Installation

**Aufgaben**:
1. Minimale Flask-App erstellen
2. Systemd-Service-Definition erstellen
3. Service starten und testen
4. Zugriff über Browser verifizieren

**Code-Beispiel - /opt/disk2iso/web/app.py**:

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello_world():
    return '''
    <!DOCTYPE html>
    <html lang="de">
    <head>
        <meta charset="UTF-8">
        <title>disk2iso Web-Server</title>
    </head>
    <body>
        <h1>Willkommen zu disk2iso Web-Server!</h1>
        <p>Die Installation war erfolgreich.</p>
    </body>
    </html>
    '''

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
```

**Systemd Service - /etc/systemd/system/disk2iso-web.service**:

```ini
[Unit]
Description=disk2iso Web-Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/disk2iso/web
Environment="PATH=/opt/disk2iso/venv/bin"
ExecStart=/opt/disk2iso/venv/bin/gunicorn \
    --bind 0.0.0.0:8080 \
    --workers 2 \
    --timeout 120 \
    --access-logfile /opt/disk2iso/web/logs/access.log \
    --error-logfile /opt/disk2iso/web/logs/error.log \
    app:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Service aktivieren**:

```bash
systemctl daemon-reload
systemctl enable disk2iso-web.service
systemctl start disk2iso-web.service
systemctl status disk2iso-web.service
```

**Erfolgskriterien**:
- Service läuft ohne Fehler
- Webseite ist unter http://SERVER-IP:8080 erreichbar
- "Hello World" wird angezeigt

---

### Phase 3: Status-Seite implementieren

**Ziel**: Anzeige des aktuellen Archivierungsstatus

**Aufgaben**:
1. Status-Daten aus disk2iso auslesen
2. Route für Status-Seite erstellen
3. Template für Status-Anzeige entwickeln
4. Automatische Aktualisierung implementieren

**Code-Beispiel - Erweiterte app.py**:

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from flask import Flask, render_template, jsonify
import subprocess
import json
import os
from datetime import datetime

app = Flask(__name__)

def get_archive_status():
    """Liest den aktuellen Archivierungsstatus aus."""
    status = {
        'running': False,
        'current_disk': None,
        'progress': 0,
        'total_archived': 0,
        'last_update': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }
    
    # Prüfen ob Archivierungsprozess läuft
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', 'disk2iso.service'],
            capture_output=True,
            text=True
        )
        status['running'] = (result.stdout.strip() == 'active')
    except Exception as e:
        print(f"Fehler beim Statuscheck: {e}")
    
    # Status-Datei lesen (falls vorhanden)
    status_file = '/var/log/disk2iso/current_status.json'
    if os.path.exists(status_file):
        try:
            with open(status_file, 'r') as f:
                file_status = json.load(f)
                status.update(file_status)
        except Exception as e:
            print(f"Fehler beim Lesen der Status-Datei: {e}")
    
    # Anzahl archivierter ISOs zählen
    iso_dir = '/mnt/archiv'
    if os.path.exists(iso_dir):
        status['total_archived'] = len([f for f in os.listdir(iso_dir) 
                                        if f.endswith('.iso')])
    
    return status

@app.route('/')
def index():
    """Hauptseite mit Status-Übersicht."""
    return render_template('index.html')

@app.route('/api/status')
def api_status():
    """API-Endpunkt für Status-Daten."""
    return jsonify(get_archive_status())

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
```

**Template - templates/index.html**:

```html
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>disk2iso - Status</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>
<body>
    <div class="container">
        <header>
            <h1>🖴 disk2iso Archivierungssystem</h1>
            <p class="subtitle">Status-Überwachung und Verwaltung</p>
        </header>
        
        <nav>
            <a href="/" class="active">Status</a>
            <a href="/archive">Archiv</a>
            <a href="/logs">Logs</a>
        </nav>
        
        <main>
            <section class="status-card">
                <h2>Aktueller Status</h2>
                <div class="status-grid">
                    <div class="status-item">
                        <span class="label">Dienst-Status:</span>
                        <span id="service-status" class="value">Lade...</span>
                    </div>
                    <div class="status-item">
                        <span class="label">Aktuelle Disk:</span>
                        <span id="current-disk" class="value">-</span>
                    </div>
                    <div class="status-item">
                        <span class="label">Fortschritt:</span>
                        <span id="progress" class="value">0%</span>
                    </div>
                    <div class="status-item">
                        <span class="label">Archivierte ISOs:</span>
                        <span id="total-archived" class="value">0</span>
                    </div>
                    <div class="status-item">
                        <span class="label">Letzte Aktualisierung:</span>
                        <span id="last-update" class="value">-</span>
                    </div>
                </div>
                <div class="progress-bar">
                    <div id="progress-fill" class="progress-fill"></div>
                </div>
            </section>
        </main>
        
        <footer>
            <p>&copy; 2026 disk2iso - Automatisches CD/DVD Archivierungssystem</p>
        </footer>
    </div>
    
    <script>
        // Status alle 5 Sekunden aktualisieren
        function updateStatus() {
            fetch('/api/status')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('service-status').textContent = 
                        data.running ? '🟢 Aktiv' : '🔴 Inaktiv';
                    document.getElementById('service-status').className = 
                        'value ' + (data.running ? 'status-active' : 'status-inactive');
                    
                    document.getElementById('current-disk').textContent = 
                        data.current_disk || '-';
                    document.getElementById('progress').textContent = 
                        data.progress + '%';
                    document.getElementById('total-archived').textContent = 
                        data.total_archived;
                    document.getElementById('last-update').textContent = 
                        data.last_update;
                    
                    // Fortschrittsbalken aktualisieren
                    document.getElementById('progress-fill').style.width = 
                        data.progress + '%';
                })
                .catch(error => console.error('Fehler beim Laden des Status:', error));
        }
        
        // Initial laden
        updateStatus();
        
        // Automatische Aktualisierung
        setInterval(updateStatus, 5000);
    </script>
</body>
</html>
```

**Erfolgskriterien**:
- Status-Seite zeigt aktuelle Daten an
- Automatische Aktualisierung funktioniert
- API-Endpunkt liefert korrekte JSON-Daten

---

### Phase 4: Archiv-Seite implementieren

**Ziel**: Übersicht über alle archivierten ISO-Dateien

**Aufgaben**:
1. ISO-Dateien aus Archiv-Verzeichnis auslesen
2. Metadaten anzeigen (Größe, Datum, etc.)
3. Sortier- und Filterfunktionen
4. Download-Links bereitstellen (optional)

**Code-Beispiel - app.py erweitern**:

```python
import os
from pathlib import Path

@app.route('/archive')
def archive():
    """Archiv-Übersicht."""
    return render_template('archive.html')

@app.route('/api/archive')
def api_archive():
    """API-Endpunkt für Archiv-Daten."""
    iso_dir = '/mnt/archiv'
    archives = []
    
    if os.path.exists(iso_dir):
        for filename in os.listdir(iso_dir):
            if filename.endswith('.iso'):
                filepath = os.path.join(iso_dir, filename)
                stat = os.stat(filepath)
                
                archives.append({
                    'name': filename,
                    'size': stat.st_size,
                    'size_mb': round(stat.st_size / (1024*1024), 2),
                    'created': datetime.fromtimestamp(stat.st_ctime).strftime('%Y-%m-%d %H:%M:%S'),
                    'modified': datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
                })
    
    # Nach Datum sortieren (neueste zuerst)
    archives.sort(key=lambda x: x['modified'], reverse=True)
    
    return jsonify({
        'total': len(archives),
        'archives': archives
    })
```

**Template - templates/archive.html**:

```html
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>disk2iso - Archiv</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>
<body>
    <div class="container">
        <header>
            <h1>🖴 disk2iso Archivierungssystem</h1>
            <p class="subtitle">Archiv-Verwaltung</p>
        </header>
        
        <nav>
            <a href="/">Status</a>
            <a href="/archive" class="active">Archiv</a>
            <a href="/logs">Logs</a>
        </nav>
        
        <main>
            <section class="archive-section">
                <h2>Archivierte ISO-Dateien</h2>
                <div class="archive-stats">
                    <p>Gesamt: <strong id="total-count">0</strong> Dateien</p>
                </div>
                
                <div class="table-container">
                    <table id="archive-table">
                        <thead>
                            <tr>
                                <th>Dateiname</th>
                                <th>Größe</th>
                                <th>Erstellt</th>
                                <th>Geändert</th>
                            </tr>
                        </thead>
                        <tbody id="archive-tbody">
                            <tr>
                                <td colspan="4" class="loading">Lade Archiv-Daten...</td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </section>
        </main>
        
        <footer>
            <p>&copy; 2026 disk2iso - Automatisches CD/DVD Archivierungssystem</p>
        </footer>
    </div>
    
    <script>
        function loadArchive() {
            fetch('/api/archive')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('total-count').textContent = data.total;
                    
                    const tbody = document.getElementById('archive-tbody');
                    tbody.innerHTML = '';
                    
                    if (data.archives.length === 0) {
                        tbody.innerHTML = '<tr><td colspan="4" class="no-data">Keine Archiv-Dateien gefunden</td></tr>';
                        return;
                    }
                    
                    data.archives.forEach(archive => {
                        const row = tbody.insertRow();
                        row.innerHTML = `
                            <td class="filename">${archive.name}</td>
                            <td>${archive.size_mb} MB</td>
                            <td>${archive.created}</td>
                            <td>${archive.modified}</td>
                        `;
                    });
                })
                .catch(error => {
                    console.error('Fehler beim Laden des Archivs:', error);
                    document.getElementById('archive-tbody').innerHTML = 
                        '<tr><td colspan="4" class="error">Fehler beim Laden der Daten</td></tr>';
                });
        }
        
        // Beim Laden der Seite
        loadArchive();
        
        // Aktualisierung alle 30 Sekunden
        setInterval(loadArchive, 30000);
    </script>
</body>
</html>
```

**Erfolgskriterien**:
- Alle ISO-Dateien werden angezeigt
- Tabelle ist sortiert und übersichtlich
- Metadaten werden korrekt angezeigt

---

### Phase 5: Log-Viewer implementieren

**Ziel**: Anzeige von System- und Anwendungslogs

**Aufgaben**:
1. Log-Dateien auslesen
2. Filterung nach Log-Level
3. Live-Update-Funktion
4. Download-Option für Logs

**Code-Beispiel - app.py erweitern**:

```python
@app.route('/logs')
def logs():
    """Log-Viewer."""
    return render_template('logs.html')

@app.route('/api/logs')
def api_logs():
    """API-Endpunkt für Log-Daten."""
    log_file = '/var/log/disk2iso/disk2iso.log'
    lines = []
    
    if os.path.exists(log_file):
        try:
            with open(log_file, 'r') as f:
                # Letzte 100 Zeilen lesen
                all_lines = f.readlines()
                lines = all_lines[-100:]
        except Exception as e:
            lines = [f"Fehler beim Lesen der Log-Datei: {str(e)}"]
    else:
        lines = ["Log-Datei nicht gefunden"]
    
    return jsonify({
        'lines': lines,
        'total': len(lines)
    })
```

**Template - templates/logs.html**:

```html
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>disk2iso - Logs</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>
<body>
    <div class="container">
        <header>
            <h1>🖴 disk2iso Archivierungssystem</h1>
            <p class="subtitle">System-Logs</p>
        </header>
        
        <nav>
            <a href="/">Status</a>
            <a href="/archive">Archiv</a>
            <a href="/logs" class="active">Logs</a>
        </nav>
        
        <main>
            <section class="logs-section">
                <h2>Aktuelle System-Logs</h2>
                <div class="log-controls">
                    <button onclick="loadLogs()">🔄 Aktualisieren</button>
                    <label>
                        <input type="checkbox" id="auto-scroll" checked>
                        Auto-Scroll
                    </label>
                </div>
                
                <div class="log-container">
                    <pre id="log-content">Lade Logs...</pre>
                </div>
            </section>
        </main>
        
        <footer>
            <p>&copy; 2026 disk2iso - Automatisches CD/DVD Archivierungssystem</p>
        </footer>
    </div>
    
    <script>
        function loadLogs() {
            fetch('/api/logs')
                .then(response => response.json())
                .then(data => {
                    const logContent = document.getElementById('log-content');
                    logContent.textContent = data.lines.join('');
                    
                    // Auto-Scroll nach unten
                    if (document.getElementById('auto-scroll').checked) {
                        logContent.scrollTop = logContent.scrollHeight;
                    }
                })
                .catch(error => {
                    console.error('Fehler beim Laden der Logs:', error);
                    document.getElementById('log-content').textContent = 
                        'Fehler beim Laden der Logs';
                });
        }
        
        // Initial laden
        loadLogs();
        
        // Automatische Aktualisierung alle 10 Sekunden
        setInterval(loadLogs, 10000);
    </script>
</body>
</html>
```

**Erfolgskriterien**:
- Logs werden korrekt angezeigt
- Auto-Refresh funktioniert
- Scrolling ist benutzerfreundlich

---

### Phase 6: Styling und Responsive Design

**Ziel**: Professionelles und responsives Design

**Aufgaben**:
1. CSS-Framework oder eigenes Design
2. Responsive Layouts für Mobile
3. Farbschema und Branding
4. Benutzerfreundliche UI-Elemente

**Code-Beispiel - static/css/style.css**:

```css
/* Globale Styles */
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

:root {
    --primary-color: #2c3e50;
    --secondary-color: #3498db;
    --success-color: #27ae60;
    --danger-color: #e74c3c;
    --warning-color: #f39c12;
    --bg-color: #ecf0f1;
    --card-bg: #ffffff;
    --text-color: #2c3e50;
    --border-color: #bdc3c7;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background-color: var(--bg-color);
    color: var(--text-color);
    line-height: 1.6;
}

.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 20px;
}

/* Header */
header {
    text-align: center;
    padding: 30px 0;
    background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
    color: white;
    border-radius: 10px;
    margin-bottom: 30px;
    box-shadow: 0 4px 6px rgba(0,0,0,0.1);
}

header h1 {
    font-size: 2.5em;
    margin-bottom: 10px;
}

header .subtitle {
    font-size: 1.2em;
    opacity: 0.9;
}

/* Navigation */
nav {
    display: flex;
    justify-content: center;
    gap: 20px;
    margin-bottom: 30px;
    flex-wrap: wrap;
}

nav a {
    padding: 12px 25px;
    background-color: var(--card-bg);
    color: var(--text-color);
    text-decoration: none;
    border-radius: 5px;
    transition: all 0.3s ease;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

nav a:hover {
    background-color: var(--secondary-color);
    color: white;
    transform: translateY(-2px);
    box-shadow: 0 4px 8px rgba(0,0,0,0.2);
}

nav a.active {
    background-color: var(--primary-color);
    color: white;
}

/* Status Card */
.status-card {
    background-color: var(--card-bg);
    padding: 30px;
    border-radius: 10px;
    box-shadow: 0 4px 6px rgba(0,0,0,0.1);
    margin-bottom: 30px;
}

.status-card h2 {
    margin-bottom: 20px;
    color: var(--primary-color);
    border-bottom: 3px solid var(--secondary-color);
    padding-bottom: 10px;
}

.status-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 20px;
    margin-bottom: 25px;
}

.status-item {
    display: flex;
    justify-content: space-between;
    padding: 15px;
    background-color: var(--bg-color);
    border-radius: 5px;
    border-left: 4px solid var(--secondary-color);
}

.status-item .label {
    font-weight: bold;
    color: var(--primary-color);
}

.status-item .value {
    font-weight: normal;
}

.status-active {
    color: var(--success-color);
    font-weight: bold;
}

.status-inactive {
    color: var(--danger-color);
    font-weight: bold;
}

/* Progress Bar */
.progress-bar {
    width: 100%;
    height: 30px;
    background-color: var(--bg-color);
    border-radius: 15px;
    overflow: hidden;
    box-shadow: inset 0 2px 4px rgba(0,0,0,0.1);
}

.progress-fill {
    height: 100%;
    background: linear-gradient(90deg, var(--secondary-color), var(--success-color));
    transition: width 0.5s ease;
    display: flex;
    align-items: center;
    justify-content: center;
    color: white;
    font-weight: bold;
}

/* Archive Section */
.archive-section {
    background-color: var(--card-bg);
    padding: 30px;
    border-radius: 10px;
    box-shadow: 0 4px 6px rgba(0,0,0,0.1);
}

.archive-section h2 {
    margin-bottom: 20px;
    color: var(--primary-color);
    border-bottom: 3px solid var(--secondary-color);
    padding-bottom: 10px;
}

.archive-stats {
    margin-bottom: 20px;
    padding: 15px;
    background-color: var(--bg-color);
    border-radius: 5px;
}

.table-container {
    overflow-x: auto;
}

table {
    width: 100%;
    border-collapse: collapse;
    background-color: white;
}

table thead {
    background-color: var(--primary-color);
    color: white;
}

table th,
table td {
    padding: 12px;
    text-align: left;
    border-bottom: 1px solid var(--border-color);
}

table tbody tr:hover {
    background-color: var(--bg-color);
}

table .filename {
    font-family: monospace;
    color: var(--secondary-color);
}

.loading,
.no-data,
.error {
    text-align: center;
    padding: 30px;
    color: var(--text-color);
    font-style: italic;
}

.error {
    color: var(--danger-color);
}

/* Logs Section */
.logs-section {
    background-color: var(--card-bg);
    padding: 30px;
    border-radius: 10px;
    box-shadow: 0 4px 6px rgba(0,0,0,0.1);
}

.logs-section h2 {
    margin-bottom: 20px;
    color: var(--primary-color);
    border-bottom: 3px solid var(--secondary-color);
    padding-bottom: 10px;
}

.log-controls {
    margin-bottom: 20px;
    display: flex;
    gap: 15px;
    align-items: center;
}

.log-controls button {
    padding: 10px 20px;
    background-color: var(--secondary-color);
    color: white;
    border: none;
    border-radius: 5px;
    cursor: pointer;
    transition: background-color 0.3s ease;
}

.log-controls button:hover {
    background-color: var(--primary-color);
}

.log-container {
    background-color: #1e1e1e;
    border-radius: 5px;
    overflow: hidden;
}

#log-content {
    padding: 20px;
    color: #d4d4d4;
    font-family: 'Courier New', monospace;
    font-size: 14px;
    max-height: 600px;
    overflow-y: auto;
    white-space: pre-wrap;
    word-wrap: break-word;
}

/* Footer */
footer {
    text-align: center;
    padding: 20px;
    margin-top: 40px;
    color: var(--text-color);
    opacity: 0.7;
}

/* Responsive Design */
@media (max-width: 768px) {
    header h1 {
        font-size: 1.8em;
    }
    
    header .subtitle {
        font-size: 1em;
    }
    
    .status-grid {
        grid-template-columns: 1fr;
    }
    
    nav {
        flex-direction: column;
        gap: 10px;
    }
    
    nav a {
        width: 100%;
        text-align: center;
    }
    
    table {
        font-size: 14px;
    }
    
    table th,
    table td {
        padding: 8px;
    }
}

@media (max-width: 480px) {
    .container {
        padding: 10px;
    }
    
    .status-card,
    .archive-section,
    .logs-section {
        padding: 15px;
    }
    
    header {
        padding: 20px 10px;
    }
}
```

**Erfolgskriterien**:
- Design ist ansprechend und professionell
- Mobile Ansicht funktioniert einwandfrei
- Alle Elemente sind gut lesbar und bedienbar

---

### Phase 7: Integration und Testing

**Ziel**: Vollständige Integration und umfassendes Testing

**Aufgaben**:
1. Konfigurationsdatei erstellen
2. Error-Handling verbessern
3. Sicherheitsaspekte prüfen
4. End-to-End Tests durchführen
5. Performance-Optimierung

**Code-Beispiel - config.py**:

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os

class Config:
    """Konfiguration für disk2iso Web-Server."""
    
    # Flask-Einstellungen
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'dev-secret-key-change-in-production'
    DEBUG = False
    
    # Server-Einstellungen
    HOST = '0.0.0.0'
    PORT = 8080
    
    # Pfade
    ISO_ARCHIVE_DIR = '/mnt/archiv'
    LOG_DIR = '/var/log/disk2iso'
    STATUS_FILE = '/var/log/disk2iso/current_status.json'
    
    # Service-Name
    SERVICE_NAME = 'disk2iso.service'
    
    # Web-Server-Einstellungen
    WORKERS = 2
    TIMEOUT = 120
    
    # Aktualisierungsintervalle (in Sekunden)
    STATUS_UPDATE_INTERVAL = 5
    ARCHIVE_UPDATE_INTERVAL = 30
    LOG_UPDATE_INTERVAL = 10
    
    # Log-Einstellungen
    MAX_LOG_LINES = 100
    
    # Sicherheit
    ALLOWED_HOSTS = ['*']  # In Produktion anpassen!

class DevelopmentConfig(Config):
    """Entwicklungs-Konfiguration."""
    DEBUG = True

class ProductionConfig(Config):
    """Produktions-Konfiguration."""
    DEBUG = False
    # In Produktion Secret Key über Umgebungsvariable setzen!

# Aktuelle Konfiguration
config = ProductionConfig()
```

**Erweiterte app.py mit Error-Handling**:

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from flask import Flask, render_template, jsonify, abort
import subprocess
import json
import os
from datetime import datetime
import logging
from config import config

# Logging einrichten
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/opt/disk2iso/web/logs/app.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config.from_object(config)

@app.errorhandler(404)
def not_found(error):
    """404 Error Handler."""
    return render_template('404.html'), 404

@app.errorhandler(500)
def internal_error(error):
    """500 Error Handler."""
    logger.error(f"Internal Server Error: {error}")
    return render_template('500.html'), 500

def get_archive_status():
    """Liest den aktuellen Archivierungsstatus aus."""
    status = {
        'running': False,
        'current_disk': None,
        'progress': 0,
        'total_archived': 0,
        'last_update': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }
    
    try:
        # Prüfen ob Archivierungsprozess läuft
        result = subprocess.run(
            ['systemctl', 'is-active', config.SERVICE_NAME],
            capture_output=True,
            text=True,
            timeout=5
        )
        status['running'] = (result.stdout.strip() == 'active')
        
        # Status-Datei lesen (falls vorhanden)
        if os.path.exists(config.STATUS_FILE):
            with open(config.STATUS_FILE, 'r') as f:
                file_status = json.load(f)
                status.update(file_status)
        
        # Anzahl archivierter ISOs zählen
        if os.path.exists(config.ISO_ARCHIVE_DIR):
            status['total_archived'] = len([
                f for f in os.listdir(config.ISO_ARCHIVE_DIR) 
                if f.endswith('.iso')
            ])
    
    except subprocess.TimeoutExpired:
        logger.error("Timeout beim Statuscheck")
    except Exception as e:
        logger.error(f"Fehler beim Statuscheck: {e}")
    
    return status

@app.route('/')
def index():
    """Hauptseite mit Status-Übersicht."""
    try:
        return render_template('index.html')
    except Exception as e:
        logger.error(f"Fehler beim Rendern der Index-Seite: {e}")
        abort(500)

@app.route('/api/status')
def api_status():
    """API-Endpunkt für Status-Daten."""
    try:
        return jsonify(get_archive_status())
    except Exception as e:
        logger.error(f"Fehler im Status-API: {e}")
        return jsonify({'error': 'Fehler beim Laden des Status'}), 500

@app.route('/archive')
def archive():
    """Archiv-Übersicht."""
    try:
        return render_template('archive.html')
    except Exception as e:
        logger.error(f"Fehler beim Rendern der Archiv-Seite: {e}")
        abort(500)

@app.route('/api/archive')
def api_archive():
    """API-Endpunkt für Archiv-Daten."""
    archives = []
    
    try:
        if os.path.exists(config.ISO_ARCHIVE_DIR):
            for filename in os.listdir(config.ISO_ARCHIVE_DIR):
                if filename.endswith('.iso'):
                    filepath = os.path.join(config.ISO_ARCHIVE_DIR, filename)
                    stat = os.stat(filepath)
                    
                    archives.append({
                        'name': filename,
                        'size': stat.st_size,
                        'size_mb': round(stat.st_size / (1024*1024), 2),
                        'created': datetime.fromtimestamp(stat.st_ctime).strftime('%Y-%m-%d %H:%M:%S'),
                        'modified': datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
                    })
        
        # Nach Datum sortieren (neueste zuerst)
        archives.sort(key=lambda x: x['modified'], reverse=True)
        
        return jsonify({
            'total': len(archives),
            'archives': archives
        })
    
    except Exception as e:
        logger.error(f"Fehler im Archiv-API: {e}")
        return jsonify({'error': 'Fehler beim Laden des Archivs'}), 500

@app.route('/logs')
def logs():
    """Log-Viewer."""
    try:
        return render_template('logs.html')
    except Exception as e:
        logger.error(f"Fehler beim Rendern der Log-Seite: {e}")
        abort(500)

@app.route('/api/logs')
def api_logs():
    """API-Endpunkt für Log-Daten."""
    log_file = os.path.join(config.LOG_DIR, 'disk2iso.log')
    lines = []
    
    try:
        if os.path.exists(log_file):
            with open(log_file, 'r') as f:
                all_lines = f.readlines()
                lines = all_lines[-config.MAX_LOG_LINES:]
        else:
            lines = ["Log-Datei nicht gefunden"]
        
        return jsonify({
            'lines': lines,
            'total': len(lines)
        })
    
    except Exception as e:
        logger.error(f"Fehler im Log-API: {e}")
        return jsonify({'error': 'Fehler beim Laden der Logs'}), 500

if __name__ == '__main__':
    app.run(host=config.HOST, port=config.PORT, debug=config.DEBUG)
```

**Test-Checkliste**:

```markdown
## Test-Checkliste

### Funktionale Tests
- [ ] Status-Seite zeigt korrekte Daten an
- [ ] Automatische Aktualisierung funktioniert
- [ ] Archiv-Seite listet alle ISOs auf
- [ ] Log-Viewer zeigt aktuelle Logs
- [ ] Navigation zwischen Seiten funktioniert
- [ ] API-Endpunkte liefern valides JSON

### Performance-Tests
- [ ] Seiten laden in < 2 Sekunden
- [ ] API-Antworten in < 500ms
- [ ] Keine Memory-Leaks bei Langzeitbetrieb
- [ ] CPU-Last bleibt unter 10%

### Sicherheits-Tests
- [ ] Keine sensiblen Daten in Logs
- [ ] XSS-Protection aktiv
- [ ] CSRF-Protection (wenn Forms verwendet)
- [ ] Keine Directory-Traversal-Möglichkeiten

### Kompatibilitäts-Tests
- [ ] Chrome/Chromium
- [ ] Firefox
- [ ] Safari
- [ ] Edge
- [ ] Mobile Browser (iOS/Android)

### Responsive Design Tests
- [ ] Desktop (1920x1080)
- [ ] Tablet (768x1024)
- [ ] Mobile (375x667)
- [ ] Mobile (320x568)

### Service-Tests
- [ ] Service startet automatisch beim Boot
- [ ] Service recovered nach Crash
- [ ] Logs werden korrekt geschrieben
- [ ] Ports sind korrekt gebunden
```

**Erfolgskriterien**:
- Alle Tests bestanden
- Keine kritischen Fehler
- Performance-Ziele erreicht
- Dokumentation vollständig

---

## Zeitplan und Meilensteine

| Phase | Beschreibung | Geschätzte Dauer | Status |
|-------|-------------|------------------|--------|
| Phase 1 | Installation und Grundeinrichtung | 2-3 Stunden | ⏳ Ausstehend |
| Phase 2 | Hello World Test | 1-2 Stunden | ⏳ Ausstehend |
| Phase 3 | Status-Seite implementieren | 4-6 Stunden | ⏳ Ausstehend |
| Phase 4 | Archiv-Seite implementieren | 3-4 Stunden | ⏳ Ausstehend |
| Phase 5 | Log-Viewer implementieren | 2-3 Stunden | ⏳ Ausstehend |
| Phase 6 | Styling und Responsive Design | 4-5 Stunden | ⏳ Ausstehend |
| Phase 7 | Integration und Testing | 4-6 Stunden | ⏳ Ausstehend |
| **Gesamt** | **Vollständige Implementierung** | **20-29 Stunden** | ⏳ Ausstehend |

## Nächste Schritte

### Sofort (Priorität 1)
1. ✅ Umsetzungsplan erstellen und reviewen
2. 🔲 Python3 und Flask-Abhängigkeiten installieren
3. 🔲 Grundlegende Verzeichnisstruktur anlegen
4. 🔲 Hello World-Anwendung testen

### Kurzfristig (Priorität 2)
5. 🔲 Status-API entwickeln
6. 🔲 Erste Version der Status-Seite
7. 🔲 Systemd-Service einrichten
8. 🔲 Basis-Styling implementieren

### Mittelfristig (Priorität 3)
9. 🔲 Archiv-Übersicht vervollständigen
10. 🔲 Log-Viewer finalisieren
11. 🔲 Responsive Design optimieren
12. 🔲 Error-Handling verbessern

### Langfristig (Priorität 4)
13. 🔲 Performance-Optimierung
14. 🔲 Erweiterte Features (z.B. Download-Funktion)
15. 🔲 Umfassende Tests durchführen
16. 🔲 Dokumentation vervollständigen

## Technische Anforderungen

### Server-Anforderungen
- **OS**: Debian 11/12 oder Ubuntu 20.04+
- **RAM**: Minimum 512 MB (empfohlen 1 GB+)
- **Speicher**: 100 MB für Web-Server-Komponenten
- **Python**: Version 3.7+
- **Netzwerk**: Port 8080 verfügbar

### Software-Abhängigkeiten
```
python3
python3-pip
python3-venv
flask>=2.0.0
gunicorn>=20.0.0
```

## Sicherheitshinweise

1. **Firewall-Konfiguration**: Port 8080 nur für vertrauenswürdige Netzwerke öffnen
2. **SSL/TLS**: In Produktionsumgebungen HTTPS verwenden (z.B. mit Nginx Reverse Proxy)
3. **Authentifizierung**: Für den Produktiveinsatz Benutzerauthentifizierung hinzufügen
4. **Regelmäßige Updates**: Flask und Abhängigkeiten aktuell halten
5. **Log-Rotation**: Logs regelmäßig rotieren um Speicherplatz zu sparen

## Wartung und Monitoring

### Regelmäßige Aufgaben
- **Täglich**: Log-Dateien prüfen
- **Wöchentlich**: Service-Status überprüfen
- **Monatlich**: Updates installieren
- **Quartalsweise**: Performance-Review

### Monitoring-Punkte
- Service-Verfügbarkeit
- Response-Zeiten
- Fehlerrate in Logs
- Speichernutzung
- CPU-Last

## Erweiterungsmöglichkeiten

### Kurzfristig
- E-Mail-Benachrichtigungen bei Fehlern
- Download-Funktion für ISO-Dateien
- Suchfunktion im Archiv
- Erweiterte Log-Filterung

### Mittelfristig
- Benutzerauthentifizierung und -verwaltung
- API für externe Integrationen
- Dashboard mit Statistiken und Graphen
- Mobile App (Progressive Web App)

### Langfristig
- Multi-Server-Unterstützung
- Backup-Management über Web-Interface
- Automatisierte Tests und CI/CD
- Containerisierung (Docker)

## Dokumentation und Support

### Dokumentations-Dateien
- `README.md`: Allgemeine Projektbeschreibung
- `INSTALL.md`: Installationsanleitung
- `API.md`: API-Dokumentation
- `CONTRIBUTING.md`: Beitragsrichtlinien

### Support-Kanäle
- GitHub Issues: Bug-Reports und Feature-Requests
- Projektdokumentation: Technische Details
- Inline-Code-Kommentare: Implementierungsdetails

## Änderungsprotokoll

| Datum | Version | Änderungen | Autor |
|-------|---------|------------|-------|
| 2026-01-04 | 1.0 | Initiale Version des Umsetzungsplans | DirkGoetze |

---

## Zusammenfassung

Dieser Umsetzungsplan bietet eine strukturierte Roadmap für die Entwicklung des disk2iso Web-Servers. Die Implementierung erfolgt in 7 klar definierten Phasen, von der Grundeinrichtung bis zum vollständigen Testing. 

**Geschätzte Gesamtdauer**: 20-29 Arbeitsstunden

**Erwartetes Ergebnis**: Ein vollständig funktionsfähiger, benutzerfreundlicher Web-Server zur Überwachung und Verwaltung des disk2iso-Archivierungssystems.

Die modulare Struktur ermöglicht eine schrittweise Implementierung und einfache Erweiterungen in der Zukunft.

---

*Letzte Aktualisierung: 2026-01-04 14:29 UTC*
