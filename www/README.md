# disk2iso Web-Server

Dieser Ordner enthält die Web-Server-Komponenten für disk2iso.

## Installation

Der Web-Server wird automatisch während der Installation konfiguriert, wenn Sie die entsprechende Option im Wizard auswählen.

Nach der Installation:
```bash
sudo /opt/disk2iso/install.sh
# Wählen Sie "Ja" bei "Web-Server installieren"
```

## Installierte Struktur

Nach der Installation unter `/opt/disk2iso/www/`:

```
www/
├── app.py                    # Flask Hauptanwendung (Phase 2)
├── config.py                 # Web-Server Konfiguration (Phase 2)
├── requirements.txt          # ✓ Python Abhängigkeiten (automatisch erstellt)
├── templates/                # ✓ Jinja2 HTML Templates (erstellt)
│   ├── index.html           # Status-Seite (Phase 3)
│   ├── archive.html         # Archiv-Übersicht (Phase 4)
│   ├── logs.html            # Log-Viewer (Phase 5)
│   ├── 404.html             # Fehlerseite
│   └── 500.html             # Fehlerseite
├── static/                   # ✓ CSS, JavaScript, Bilder (erstellt)
│   ├── css/
│   │   └── style.css        # Styling (Phase 6)
│   └── js/
│       └── app.js           # Client-seitige Logik
└── logs/                     # ✓ Web-Server Logs (erstellt)
    ├── access.log
    ├── error.log
    └── app.log
```

## Python Virtual Environment

Der Web-Server nutzt ein isoliertes Python Virtual Environment:
```
/opt/disk2iso/venv/
```

### Abhängigkeiten installiert:
- ✅ Flask >= 2.0.0 (Web-Framework mit eingebautem Server)

### Abhängigkeiten aktualisieren:
```bash
/opt/disk2iso/venv/bin/pip install -r /opt/disk2iso/www/requirements.txt
```

## Service

Der Web-Server wird als separater systemd Service laufen:
- **Service-Name:** `disk2iso-web.service` (Phase 2)
- **Port:** 8080
- **Server:** Flask Development Server
- **Zugriff:** http://SERVER-IP:8080

**Hinweis:** Für lokale/LAN-Nutzung ist der Flask-Server völlig ausreichend.
Gunicorn oder andere Production-Server sind nicht notwendig.

## Implementierungsstatus

### ✅ Phase 1: Grundeinrichtung (ABGESCHLOSSEN)
- ✅ Python3 und pip Installation
- ✅ Virtual Environment erstellt
- ✅ Flask installiert (mit eingebautem Server)
- ✅ Verzeichnisstruktur erstellt
- ✅ requirements.txt generiert

### 🔲 Phase 2: Hello World Test (AUSSTEHEND)
- Flask-App erstellen
- Systemd Service erstellen
- Service testen

### 🔲 Phase 3: Status-Seite (AUSSTEHEND)
- Status-API entwickeln
- Template erstellen
- Live-Updates implementieren

### 🔲 Phase 4: Archiv-Seite (AUSSTEHEND)
- Archiv-API entwickeln
- Dateiliste anzeigen

### 🔲 Phase 5: Log-Viewer (AUSSTEHEND)
- Log-API entwickeln
- Live-Log-Anzeige

### 🔲 Phase 6: Styling (AUSSTEHEND)
- CSS-Framework
- Responsive Design

### 🔲 Phase 7: Testing (AUSSTEHEND)
- Integration testen
- Performance optimieren

## Dokumentation

Vollständiger Implementierungsplan:
- `/opt/disk2iso/doc/WEB-Server.md` (oder im Quellverzeichnis unter `todo/`)

## Entwicklung

Für Entwickler, die am Web-Server arbeiten möchten:

```bash
# Virtual Environment aktivieren
source /opt/disk2iso/venv/bin/activate

# Entwicklungsserver starten
cd /opt/disk2iso/www
python app.py

# Deaktivieren
deactivate
```

---

**Status:** Phase 1 abgeschlossen ✅  
**Nächste Phase:** Hello World Test (Phase 2)
