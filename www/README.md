# disk2iso Web-Server (Vorbereitet)

Dieses Verzeichnis ist für den zukünftigen Web-Server vorgesehen.

## Geplante Struktur

```
www/
├── app.py                    # Flask Hauptanwendung
├── config.py                 # Web-Server Konfiguration
├── requirements.txt          # Python Abhängigkeiten
├── templates/                # Jinja2 HTML Templates
│   ├── index.html           # Status-Seite
│   ├── archive.html         # Archiv-Übersicht
│   ├── logs.html            # Log-Viewer
│   ├── 404.html             # Fehlerseite
│   └── 500.html             # Fehlerseite
├── static/                   # CSS, JavaScript, Bilder
│   ├── css/
│   │   └── style.css
│   └── js/
│       └── app.js
└── logs/                     # Web-Server Logs
    ├── access.log
    ├── error.log
    └── app.log
```

## Installation

Die Web-Server-Komponenten werden in einem späteren Update hinzugefügt.

Siehe: `/doc/WEB-Server.md` für den Implementierungsplan.

## Service

Der Web-Server wird als separater systemd Service laufen:
- Service-Name: `disk2iso-web.service`
- Port: 8080
- Technologie: Flask + Gunicorn
