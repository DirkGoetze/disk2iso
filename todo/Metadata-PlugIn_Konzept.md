# disk2iso Plugin-System Architektur

## ✅ Session 23.01.2026 - Achievements

**Implementiert:**
- ✅ **INI-basiertes Manifest-System** für alle Module (cd, dvd, bluray, metadata, mqtt, musicbrainz, tmdb)
- ✅ **Einheitliche Dependency-Checks** via `check_module_dependencies()` in lib-config.sh
- ✅ **Modul-Selbstverwaltung** - Jedes Modul setzt eigenes `*_SUPPORT` Flag
- ✅ **Sprachdatei-Konsolidierung** - Tool-Check Messages nach lib-config.* migriert
- ✅ **TMDB API-Konfiguration externalisiert** - Vollständig INI-basiert mit [api] Sektion
- ✅ **MusicBrainz API-Konfiguration externalisiert** - Analog zu TMDB implementiert
- ✅ **Konsistente Namensgebung** - Alle Module folgen `MODULE_NAME_*`, `check_dependencies_*()` Pattern

**Architektur-Verbesserungen:**
- Manifest-Format: INI statt JSON (kein `jq` Dependency, einfacheres Parsing)
- API-Config-Loader: `get_ini_value()` Wiederverwendung aus lib-config.sh
- Future-proof: API-Version-Änderungen (TMDB v3→v4, MusicBrainz v2→v3) ohne Code-Anpassung

**Codebase-Status:** Production-ready für Phase 1-3, Backend-Routing (Phase 4) optional

---

## 🎯 Vision: Vollständige Modularität

Statt monolithischer Architektur → **Echtes Plugin-System für ALLE Module**

**Jedes Modul = Eigenständiges Plugin mit:**
- 🔧 **Bash-Logik**: `lib-<name>.sh` (Core-Funktionalität)
- 🌍 **Internationalisierung**: `lib-<name>.<lang>` (Sprachen)
- 🎨 **Frontend-Komponenten**: `<name>.js` (DOM-Injection für UI)
- 🔌 **Backend-Routen**: `routes_<name>.py` (API-Endpunkte)
- ⚙️ **Konfiguration**: `<NAME>_ENABLED=true/false` (Ein/Aus-Schalter)
- ✅ **Selbst-Validierung**: `check_dependencies_<name>()` (Dependency-Check)

---

## ❌ Aktuelle Probleme (Schwachstellen-Analyse)

### 1. **Inkonsistente Modul-Aktivierung**

| Modul | Aktivierung | Config-Schalter | Self-Check | Sprachdatei-Loading |
|-------|-------------|----------------|------------|---------------------|
| **metadata** | ✅ Config | ✅ `METADATA_ENABLED` | ✅ `check_dependencies_metadata()` | ✅ IN Check (1. Zeile) |
| **cd** | ❌ Dateipräsenz | ❌ Keiner | ✅ `check_dependencies_cd()` | ⚠️ **VOR** Check (sollte IN Check) |
| **dvd** | ❌ Dateipräsenz | ❌ Keiner | ✅ `check_dependencies_dvd()` | ⚠️ **VOR** Check (sollte IN Check) |
| **bluray** | ❌ Dateipräsenz | ❌ Keiner | ✅ `check_dependencies_bluray()` | ⚠️ **VOR** Check (sollte IN Check) |

### 2. **Fehlende Frontend-Modularität**
- Web-UI ist monolithisch - keine optionalen UI-Komponenten
- JS-Code ist nicht modular - keine DOM-Injection
- Templates sind starr - Module können keine UI-Elemente hinzufügen

### 3. **Backend-Routing nicht modular**
- Alle Routen in zentralen Dateien
- Module können keine eigenen API-Endpunkte bereitstellen
- Keine Möglichkeit, Routen zu deaktivieren wenn Modul inaktiv

### 4. **Abhängigkeits-Probleme**
- BD-Modul benötigt DVD-Modul für Metadaten (unnötige Kopplung)
- Code-Duplikation zwischen Modulen
- Schwer zu testen (keine Isolation)

### 5. **Naming-Inkonsistenz**
- `check_audio_cd_dependencies()` vs. `check_dependencies_cd()`
- Sprachdatei-Loading inkonsistent (mal VOR Check, sollte aber IN Check sein - 1. Zeile)
- Support-Flags folgen keinem einheitlichen Pattern

---

## ✅ Ziel-Architektur: Konsistentes Plugin-System

### 📋 Plugin-Manifest (Konzeptionell)

Jedes Modul definiert sich selbst:

```bash
# lib-<name>.sh Header
################################################################################
# disk2iso Module: <Name>
# Type: Plugin
# 
# Components:
#   - Bash: lib-<name>.sh
#   - i18n: lib-<name>.<lang>
#   - Frontend: www/static/js/<name>.js
#   - Backend: www/routes/routes_<name>.py
#   - Config: <NAME>_ENABLED
# 
# Dependencies:
#   - Core: lib-common.sh, lib-logging.sh
#   - External: <tool1>, <tool2>
################################################################################
```

### 🔧 Bash-Modul-Struktur (Standardisiert)

```bash
# ============================================================================
# MODULE HEADER
# ============================================================================
readonly <NAME>_MODULE_VERSION="1.2.0"
readonly <NAME>_DIR="<subfolder>"

# ============================================================================
# PATH GETTER
# ============================================================================
get_path_<name>() {
    if [[ "$<NAME>_SUPPORT" == true ]] && [[ -n "$<NAME>_DIR" ]]; then
        folders_ensure_subfolder "$<NAME>_DIR"
    else
        folders_ensure_subfolder "data"  # Fallback
    fi
}

# ============================================================================
# DEPENDENCY CHECK (ALWAYS FIRST FUNCTION!)
# ============================================================================
# Funktion: Prüfe <Name> Abhängigkeiten
# Rückgabe: 0 = Alle Tools OK, 1 = Kritische Tools fehlen
check_dependencies_<name>() {
    local missing=()
    
    # Prüfe kritische Tools
    command -v <tool1> >/dev/null 2>&1 || missing+=("<tool1>")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Fehlende Tools: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# ============================================================================
# MODULE FUNCTIONS
# ============================================================================
# ... Rest des Moduls ...
```

### ⚙️ Konfiguration (disk2iso.conf)

```bash
# Modul-Schalter (Konsistent für ALLE Module)
CD_ENABLED=true
DVD_ENABLED=true
BLURAY_ENABLED=true
METADATA_ENABLED=true
MQTT_ENABLED=false  # Zukünftig
```

### 🔄 Modul-Laden in disk2iso.sh (Standardisiert)

```bash
# ============================================================================
# PLUGIN LOADING: <NAME>
# ============================================================================
<NAME>_SUPPORT=false

if [[ "${<NAME>_ENABLED:-true}" == "true" ]]; then
    if [[ -f "${SCRIPT_DIR}/lib/lib-<name>.sh" ]]; then
        source "${SCRIPT_DIR}/lib/lib-<name>.sh"
        
        if check_dependencies_<name>; then
            <NAME>_SUPPORT=true
            liblogging_load_language_file "<name>"  # ← NACH erfolgreichem Check!
            log_info "Modul '<Name>' aktiviert"
        else
            log_info "Modul '<Name>' deaktiviert (Dependencies fehlen)"
        fi
    else
        log_info "Modul '<Name>' nicht installiert"
    fi
else
    log_info "Modul '<Name>' deaktiviert via Config"
fi
```

---

## 📋 Modul-Manifest-Dateien (Self-Description)

### Problem: Modul-Metadaten zentral verwalten

**Herausforderung:**
- Frontend braucht Liste der JS-Dateien pro Modul
- Backend braucht Routen-Informationen
- Bash braucht Dependencies
- Aktuell: Informationen sind verteilt oder hart kodiert

**Lösung:** JSON-Manifeste in `conf/` pro Modul

### Struktur

```
conf/
├── disk2iso.conf          # Haupt-Config (ENABLED-Schalter)
├── lib-cd.json            # ← CD-Modul Manifest
├── lib-dvd.json           # ← DVD-Modul Manifest
├── lib-bluray.json        # ← Bluray-Modul Manifest
└── lib-metadata.json      # ← Metadata-Modul Manifest
```

### Warum `conf/` statt `lib/`?

1. **Logische Trennung**: Code (`lib/`) vs. Konfiguration (`conf/`)
2. **Backup-freundlich**: `conf/` enthält ALLE Einstellungen
3. **Zugriff**: Alle Komponenten haben Zugriff auf `/opt/disk2iso/conf/`
4. **Konsistent**: Neben `disk2iso.conf`

### Manifest-Format (JSON)

**Beispiel:** `conf/lib-dvd.json`

```json
{
  "name": "dvd",
  "version": "1.2.0",
  "type": "plugin",
  "description": "Video-DVD Ripping mit dvdbackup und ddrescue",
  
  "components": {
    "bash": "lib-dvd.sh",
    "i18n": [
      "lib-dvd.de",
      "lib-dvd.en",
      "lib-dvd.es",
      "lib-dvd.fr"
    ],
    "frontend": [
      "dvd-ui.js",
      "dvd-metadata.js"
    ],
    "backend": [
      "routes_dvd.py"
    ],
    "config_var": "DVD_ENABLED"
  },
  
  "dependencies": {
    "core": [
      "lib-common.sh",
      "lib-logging.sh",
      "lib-folders.sh"
    ],
    "external": [
      "dvdbackup",
      "genisoimage",
      "ddrescue"
    ],
    "optional": [
      "isoinfo"
    ]
  },
  
  "paths": {
    "output_subdir": "dvd"
  }
}
```

**Beispiel:** `conf/lib-cd.json`

```json
{
  "name": "cd",
  "version": "1.2.0",
  "type": "plugin",
  "description": "Audio-CD Ripping mit MusicBrainz-Metadaten",
  
  "components": {
    "bash": "lib-cd.sh",
    "i18n": [
      "lib-cd.de",
      "lib-cd.en",
      "lib-cd.es",
      "lib-cd.fr"
    ],
    "frontend": [
      "cd-ui.js"
    ],
    "backend": [],
    "config_var": "CD_ENABLED"
  },
  
  "dependencies": {
    "core": [
      "lib-common.sh",
      "lib-logging.sh",
      "lib-folders.sh"
    ],
    "external": [
      "cdparanoia",
      "lame",
      "genisoimage"
    ],
    "optional": [
      "cd-discid",
      "curl",
      "jq",
      "eyeD3"
    ]
  },
  
  "paths": {
    "output_subdir": "audio"
  }
}
```

**Beispiel:** `conf/lib-metadata.json`

```json
{
  "name": "metadata",
  "version": "1.2.0",
  "type": "plugin",
  "description": "Provider-basiertes Metadata-System (MusicBrainz, TMDB)",
  
  "components": {
    "bash": "lib-metadata.sh",
    "i18n": [
      "lib-metadata.de",
      "lib-metadata.en",
      "lib-metadata.es",
      "lib-metadata.fr"
    ],
    "frontend": [
      "musicbrainz.js",
      "tmdb.js"
    ],
    "backend": [
      "routes_metadata.py"
    ],
    "config_var": "METADATA_ENABLED",
    "providers": [
      "lib-musicbrainz.sh",
      "lib-tmdb.sh"
    ]
  },
  
  "dependencies": {
    "core": [
      "lib-common.sh",
      "lib-logging.sh",
      "lib-api.sh"
    ],
    "external": [
      "curl",
      "jq"
    ],
    "optional": []
  },
  
  "metadata": {
    "supports_media_types": ["audio-cd", "dvd-video", "bd-video"]
  }
}
```

### Pfad-Auflösung (Relative Dateinamen)

**Warum relative Pfade?** Jeder Komponententyp hat einen **fixen Basispfad**:

```python
# www/app.py

from pathlib import Path

INSTALL_DIR = Path("/opt/disk2iso")

# Basispfade für Komponenten-Typen
COMPONENT_BASE_PATHS = {
    'bash': INSTALL_DIR / 'lib',
    'i18n': INSTALL_DIR / 'lang',
    'frontend': 'static/js',      # Relativ zu www/
    'backend': INSTALL_DIR / 'www' / 'routes',
    'providers': INSTALL_DIR / 'lib'  # Provider = Bash-Module
}

def resolve_component_path(component_type, filename):
    """Löst relativen Dateinamen zu absolutem Pfad auf"""
    base = COMPONENT_BASE_PATHS.get(component_type)
    if not base:
        raise ValueError(f"Unknown component type: {component_type}")
    
    return base / filename

# Beispiel:
# resolve_component_path('bash', 'lib-dvd.sh') 
#   → /opt/disk2iso/lib/lib-dvd.sh
# resolve_component_path('frontend', 'dvd-ui.js') 
#   → static/js/dvd-ui.js (für Flask url_for)
```

### Backend-Implementierung: Manifest-Parsing

```python
# www/app.py

import json
from pathlib import Path

CONFIG_DIR = INSTALL_DIR / "conf"

def get_module_manifests():
    """Liest alle Modul-Manifeste aus conf/ Verzeichnis
    
    Returns:
        dict: {module_name: manifest_data}
    """
    manifests = {}
    
    for manifest_file in CONFIG_DIR.glob("lib-*.json"):
        try:
            with open(manifest_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
                module_name = data.get('name')
                
                if module_name:
                    manifests[module_name] = data
                else:
                    print(f"Warning: Manifest {manifest_file} has no 'name' field", 
                          file=sys.stderr)
        except Exception as e:
            print(f"Error reading manifest {manifest_file}: {e}", 
                  file=sys.stderr)
    
    return manifests

def get_enabled_modules():
    """Ermittelt welche Module aktiviert sind (Config + Manifest)
    
    Returns:
        dict: {module_name: {enabled: bool, js_files: [...]}}
    """
    config = get_config()
    manifests = get_module_manifests()
    
    result = {}
    
    for name, manifest in manifests.items():
        # Lese ENABLED-Schalter aus Config
        config_var = manifest.get('components', {}).get('config_var', '')
        enabled_key = f"{name}_enabled"  # cd → cd_enabled
        
        is_enabled = config.get(enabled_key, True)
        
        # Frontend-Dateien (nur wenn aktiviert)
        js_files = []
        if is_enabled:
            js_files = manifest.get('components', {}).get('frontend', [])
        
        result[name] = {
            'enabled': is_enabled,
            'js_files': js_files,
            'version': manifest.get('version', '1.0.0'),
            'description': manifest.get('description', '')
        }
    
    return result

@app.route('/api/modules')
def api_modules():
    """API-Endpoint für Modul-Status (Frontend Module-Loader)"""
    enabled_modules = get_enabled_modules()
    
    return jsonify({
        'enabled_modules': enabled_modules,
        'timestamp': datetime.now().isoformat()
    })
```

### Frontend-Verwendung

**module-loader.js nutzt Manifeste:**

```javascript
// www/static/js/module-loader.js

async function initializeModules() {
    try {
        const response = await fetch('/api/modules');
        const data = await response.json();
        
        console.log('[ModuleLoader] Module von Backend:', data.enabled_modules);
        
        // Lade nur aktivierte Module
        for (const [name, moduleInfo] of Object.entries(data.enabled_modules)) {
            if (moduleInfo.enabled && moduleInfo.js_files.length > 0) {
                console.log(`[ModuleLoader] Lade Modul '${name}'`, moduleInfo.js_files);
                
                // Lade alle JS-Dateien parallel
                await Promise.all(
                    moduleInfo.js_files.map(file => loadScript(file))
                );
            }
        }
        
        console.log('[ModuleLoader] Alle Module geladen');
        
    } catch (error) {
        console.error('[ModuleLoader] Fehler:', error);
    }
}
```

### Bash-Verwendung (Optional)

**Bash könnte Manifeste auch lesen (für Selbst-Dokumentation):**

```bash
#!/bin/bash

# Optionale Funktion: Lese Modul-Info aus Manifest
get_module_info() {
    local module_name="$1"
    local field="$2"
    local manifest_file="${SCRIPT_DIR}/conf/lib-${module_name}.json"
    
    if [[ -f "$manifest_file" ]] && command -v jq >/dev/null 2>&1; then
        jq -r ".${field}" "$manifest_file" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Beispiel-Nutzung:
DVD_VERSION=$(get_module_info "dvd" "version")
DVD_DESC=$(get_module_info "dvd" "description")

log_info "DVD-Modul v${DVD_VERSION}: ${DVD_DESC}"
```

### Vorteile der Manifest-Lösung

1. **Single Source of Truth**: Alle Modul-Infos an einem Ort
2. **Erweiterbar**: Neue Felder einfach hinzufügen
3. **Performance**: Schnelles JSON-Parsing (keine Bash-Subprocess)
4. **Wartbar**: Klare Struktur, Standard-Format
5. **Versionierbar**: Manifest = Teil der Git-Historie
6. **Dokumentation**: Manifest ist gleichzeitig Dokumentation
7. **Testbar**: JSON-Schema-Validierung möglich
8. **CI/CD-freundlich**: Automatische Checks auf Vollständigkeit

### Nachteile / Herausforderungen

1. **Duplikation**: Info steht in Manifest UND Code
2. **Synchronisation**: Manifest muss aktuell gehalten werden
3. **Migration**: Bestehende Module brauchen Manifeste
4. **Wartung**: Eine weitere Datei pro Modul

**Lösung für Duplikation:**
- Manifeste werden zur **Master-Quelle**
- Code generiert aus Manifest (zukünftig)
- Oder: Manifeste durch CI validiert gegen Code

### Migration: Wann Manifeste erstellen?

**Phase 3.5: Manifest-Einführung (Zwischen Phase 3 und 4)**

**Schritt 1: Core-Module (Sofort)**
- ✅ `conf/lib-metadata.json` (komplett, mit Providern)
- ✅ `conf/lib-cd.json`
- ✅ `conf/lib-dvd.json`
- ✅ `conf/lib-bluray.json`

**Schritt 2: Backend-Integration (Phase 3)**
- ✅ Python: `get_module_manifests()` implementieren
- ✅ Python: `/api/modules` nutzt Manifeste
- ✅ Frontend: `module-loader.js` nutzt API

**Schritt 3: Validierung (Phase 4)**
- JSON-Schema erstellen für Manifest-Format
- CI-Pipeline validiert Manifeste
- Tests prüfen Konsistenz (Manifest ↔ Dateisystem)

**Schritt 4: Weitere Module (Phase 5)**
- MQTT → `conf/lib-mqtt.json`
- Web-UI → `conf/lib-web.json`
- API → `conf/lib-api.json`

---

## 🔌 Backend-Routing Modularisierung

### Problem: Monolithische Route-Struktur

**Aktuell:**
- Alle Routes in `www/app.py` (>2000 Zeilen)
- Module können keine eigenen Endpunkte definieren
- Keine Möglichkeit, Routes zu deaktivieren wenn Modul inaktiv
- Schwer wartbar, schwer testbar

**Ziel:**
- Jedes Modul hat eigene Route-Datei
- Routes werden dynamisch basierend auf Modul-Status geladen
- Klare Trennung: Ein Modul = Ein Blueprint

### Blueprint-Struktur (Flask)

```
www/
├── app.py                      # Haupt-App (Core-Routes + Blueprint-Registrierung)
├── routes/                     # ← Modul-spezifische Routes
│   ├── __init__.py
│   ├── routes_metadata.py      # Metadata-Modul Routes
│   ├── routes_cd.py            # CD-Modul Routes
│   ├── routes_dvd.py           # DVD-Modul Routes
│   └── routes_bluray.py        # Bluray-Modul Routes
└── ...
```

### Modul-Router Implementierung

**Beispiel:** `www/routes/routes_metadata.py`

```python
"""
disk2iso Metadata-Modul Routes
Bietet API-Endpunkte für Metadata-Provider (MusicBrainz, TMDB)
"""

from flask import Blueprint, jsonify, request
from pathlib import Path
import json
import os

# Blueprint-Definition
metadata_bp = Blueprint('metadata', __name__, url_prefix='/api/metadata')

# Konfiguration
API_DIR = Path("/opt/disk2iso/api")

@metadata_bp.route('/status')
def get_metadata_status():
    """Prüfe ob Metadata-Modul aktiv ist"""
    # Wird vom Haupt-Loader bereits geprüft (Blueprint nur registriert wenn aktiv)
    return jsonify({
        'enabled': True,
        'providers': ['musicbrainz', 'tmdb'],
        'version': '1.2.0'
    })

@metadata_bp.route('/pending')
def get_pending_metadata():
    """Hole ausstehende Metadata-Anfragen (MusicBrainz/TMDB)"""
    try:
        # MusicBrainz
        mb_query_file = API_DIR / "musicbrainz_releases.json"
        mb_pending = None
        if mb_query_file.exists():
            with open(mb_query_file, 'r') as f:
                mb_pending = json.load(f)
        
        # TMDB
        tmdb_query_file = API_DIR / "tmdb_results.json"
        tmdb_pending = None
        if tmdb_query_file.exists():
            with open(tmdb_query_file, 'r') as f:
                tmdb_pending = json.load(f)
        
        return jsonify({
            'musicbrainz': mb_pending,
            'tmdb': tmdb_pending,
            'has_pending': mb_pending is not None or tmdb_pending is not None
        })
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@metadata_bp.route('/select', methods=['POST'])
def submit_metadata_selection():
    """Empfange User-Auswahl für Metadata"""
    try:
        data = request.get_json()
        provider = data.get('provider')  # 'musicbrainz' oder 'tmdb'
        disc_id = data.get('disc_id')
        selected_index = data.get('selected_index')
        
        if not all([provider, disc_id, selected_index is not None]):
            return jsonify({'error': 'Missing required fields'}), 400
        
        # Schreibe Selection-File für Bash
        # ... (wie aktuell in app.py)
        
        return jsonify({'success': True})
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# Weitere Metadata-spezifische Routes...
```

**Beispiel:** `www/routes/routes_dvd.py`

```python
"""
disk2iso DVD-Modul Routes
Bietet API-Endpunkte für DVD-spezifische Funktionen
"""

from flask import Blueprint, jsonify
from pathlib import Path

dvd_bp = Blueprint('dvd', __name__, url_prefix='/api/dvd')

@dvd_bp.route('/status')
def get_dvd_status():
    """Prüfe DVD-Modul Status"""
    return jsonify({
        'enabled': True,
        'methods': ['dvdbackup', 'ddrescue'],
        'version': '1.2.0'
    })

@dvd_bp.route('/failed')
def get_failed_dvds():
    """Hole Liste fehlgeschlagener DVDs (.failed_dvds)"""
    try:
        failed_file = Path("/media/iso/.failed_dvds")
        
        if not failed_file.exists():
            return jsonify({'failed_dvds': []})
        
        failed_dvds = []
        with open(failed_file, 'r') as f:
            for line in f:
                parts = line.strip().split('|')
                if len(parts) >= 3:
                    failed_dvds.append({
                        'identifier': parts[0],
                        'timestamp': parts[1],
                        'method': parts[2]
                    })
        
        return jsonify({'failed_dvds': failed_dvds})
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# Weitere DVD-spezifische Routes...
```

### Blueprint-Registrierung (2 Ansätze)

#### **Ansatz 1: Statische Registrierung beim App-Start**

**Vorteil:** Einfach, schnell
**Nachteil:** Config-Änderung erfordert **Server-Restart**

```python
# www/app.py

from pathlib import Path
import importlib

INSTALL_DIR = Path("/opt/disk2iso")

def register_module_routes(app):
    """Registriere Modul-Routes basierend auf Manifesten (BEIM START)
    
    WICHTIG: Config-Änderungen erfordern Flask-Neustart!
    """
    manifests = get_module_manifests()
    config = get_config()
    
    for name, manifest in manifests.items():
        # Prüfe ob Modul aktiviert ist
        enabled_key = f"{name}_enabled"
        if not config.get(enabled_key, True):
            print(f"[Routes] Modul '{name}' deaktiviert - überspringe Routes")
            continue
        
        # Hole Backend-Komponenten
        backend_files = manifest.get('components', {}).get('backend', [])
        
        for route_file in backend_files:
            # routes_metadata.py → routes.routes_metadata
            module_name = route_file.replace('.py', '')
            import_path = f'routes.{module_name}'
            
            try:
                # Importiere Modul
                route_module = importlib.import_module(import_path)
                
                # Erwartetes Blueprint: <name>_bp
                blueprint_name = f'{name}_bp'
                
                if hasattr(route_module, blueprint_name):
                    blueprint = getattr(route_module, blueprint_name)
                    app.register_blueprint(blueprint)
                    print(f"[Routes] Registriert: {name} → {blueprint.url_prefix}")
                else:
                    print(f"[Routes] WARNUNG: {import_path} hat kein '{blueprint_name}'")
            
            except Exception as e:
                print(f"[Routes] FEHLER beim Laden von {import_path}: {e}")

# Beim App-Start
app = Flask(__name__)

# ... Core-Routes (immer geladen) ...

# Registriere Modul-Routes
register_module_routes(app)

# Start
if __name__ == '__main__':
    app.run()
```

**Ablauf bei Config-Änderung:**

1. User deaktiviert DVD-Modul in Config-UI
2. `disk2iso.conf`: `DVD_ENABLED=false` gesetzt
3. **⚠️ Flask-Server muss neu gestartet werden!**
4. Beim nächsten Start: DVD-Routes werden NICHT registriert

**Automatischer Reload:**

```python
# www/app.py

@app.route('/api/config', methods=['POST'])
def update_config():
    """Config-Update Endpoint"""
    # ... Config speichern ...
    
    # Trigger Flask-Reload (Development-Mode)
    if app.debug:
        os.system('touch /opt/disk2iso/www/app.py')  # Trigger Reload
    
    return jsonify({
        'success': True,
        'message': 'Config gespeichert. Server-Neustart erforderlich!'
    })
```

#### **Ansatz 2: Dynamische Route-Prüfung zur Laufzeit**

**Vorteil:** Kein Server-Restart nötig
**Nachteil:** Minimal langsamer (Runtime-Check bei jedem Request)

```python
# www/routes/routes_dvd.py

from functools import wraps

def require_module_enabled(module_name):
    """Decorator: Prüfe zur Laufzeit ob Modul aktiv ist"""
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            # Lese aktuelle Config (gecacht mit TTL)
            config = get_config()
            enabled = config.get(f'{module_name}_enabled', True)
            
            if not enabled:
                return jsonify({
                    'error': f'Module {module_name} is disabled',
                    'code': 'MODULE_DISABLED'
                }), 403
            
            return f(*args, **kwargs)
        return decorated_function
    return decorator

# Nutze Decorator
@dvd_bp.route('/status')
@require_module_enabled('dvd')
def get_dvd_status():
    """Prüfe DVD-Modul Status"""
    return jsonify({'enabled': True})
```

**Registrierung IMMER (unabhängig von Config):**

```python
# www/app.py

def register_module_routes(app):
    """Registriere ALLE Modul-Routes (prüfen zur Laufzeit ob aktiv)"""
    manifests = get_module_manifests()
    
    for name, manifest in manifests.items():
        backend_files = manifest.get('components', {}).get('backend', [])
        
        for route_file in backend_files:
            module_name = route_file.replace('.py', '')
            import_path = f'routes.{module_name}'
            
            try:
                route_module = importlib.import_module(import_path)
                blueprint_name = f'{name}_bp'
                
                if hasattr(route_module, blueprint_name):
                    blueprint = getattr(route_module, blueprint_name)
                    app.register_blueprint(blueprint)
                    print(f"[Routes] Registriert: {name} (Runtime-Check)")
            
            except Exception as e:
                print(f"[Routes] FEHLER: {e}")
```

**Ablauf bei Config-Änderung:**

1. User deaktiviert DVD-Modul in Config-UI
2. `disk2iso.conf`: `DVD_ENABLED=false` gesetzt
3. **✅ Kein Server-Restart nötig!**
4. Nächster Request zu `/api/dvd/*` → Decorator prüft → 403 Error

### Empfehlung: Hybrid-Ansatz

**Kombination beider Strategien:**

```python
# www/app.py

def register_module_routes(app, dynamic=True):
    """Registriere Modul-Routes
    
    Args:
        dynamic: True = Runtime-Check, False = Nur aktivierte Module laden
    """
    manifests = get_module_manifests()
    config = get_config()
    
    for name, manifest in manifests.items():
        # Statischer Check beim Start
        enabled = config.get(f'{name}_enabled', True)
        
        if not dynamic and not enabled:
            print(f"[Routes] Skip {name} (disabled)")
            continue
        
        backend_files = manifest.get('components', {}).get('backend', [])
        
        for route_file in backend_files:
            # ... Blueprint registrieren ...
            
            if dynamic:
                print(f"[Routes] {name} → Runtime-Check aktiviert")
            else:
                print(f"[Routes] {name} → Statisch geladen")

# Produktiv: Dynamisch (kein Restart nötig)
# Development: Statisch (schneller, klarer)
register_module_routes(app, dynamic=True)
```

### Config-Schema Erweiterung

**Ergänze `disk2iso.conf` um Reload-Strategie:**

```bash
# Backend-Routing Strategie
# static  = Nur aktivierte Module laden (Server-Restart bei Änderung)
# dynamic = Alle Module laden, Runtime-Check (kein Restart nötig)
ROUTING_MODE=dynamic
```

### Service-Management Integration

**Automatischer Neustart bei Config-Änderung (Optional):**

```python
# www/app.py

@app.route('/api/config', methods=['POST'])
def update_config():
    """Config-Update mit optionalem Service-Restart"""
    # ... Config speichern ...
    
    # Lese Routing-Mode
    routing_mode = get_config().get('routing_mode', 'dynamic')
    
    if routing_mode == 'static':
        # Trigger systemd-Restart
        try:
            subprocess.run(['systemctl', 'restart', 'disk2iso-web.service'], check=True)
            message = 'Config gespeichert. Web-Service wird neu gestartet...'
        except Exception as e:
            message = f'Config gespeichert. WARNUNG: Service-Restart fehlgeschlagen: {e}'
    else:
        message = 'Config gespeichert. Änderungen aktiv (kein Restart nötig).'
    
    return jsonify({
        'success': True,
        'message': message,
        'restart_required': routing_mode == 'static'
    })
```

### Vorteile der Blueprint-Architektur

1. **Modularität**: Jedes Modul = Eigene Route-Datei
2. **Wartbarkeit**: Klare Trennung, einfach zu finden
3. **Testbarkeit**: Module isoliert testbar
4. **Erweiterbarkeit**: Neue Module einfach hinzufügen
5. **Flexibilität**: Statisch ODER dynamisch je nach Bedarf
6. **Dokumentation**: Route-Struktur selbst-erklärend

### Migration: Bestehende Routes aufteilen

**Schritt 1: Identifiziere Modul-spezifische Routes**

```bash
# Suche in app.py nach Modul-Mustern
grep -n '@app.route.*musicbrainz' www/app.py
grep -n '@app.route.*tmdb' www/app.py
grep -n '@app.route.*dvd' www/app.py
```

**Beispiel-Output:**
```
525:@app.route('/api/musicbrainz/releases')
595:@app.route('/api/musicbrainz/select', methods=['POST'])
653:@app.route('/api/tmdb/results')
667:@app.route('/api/tmdb/select', methods=['POST'])
```

**Schritt 2: Extrahiere Routes in Blueprint-Dateien**

```python
# Von app.py:
@app.route('/api/musicbrainz/releases')
def get_musicbrainz_releases():
    # ...

# Nach routes/routes_metadata.py:
@metadata_bp.route('/musicbrainz/releases')
def get_musicbrainz_releases():
    # ... (Code identisch)
```

**Schritt 3: Import in app.py ersetzen**

```python
# app.py - ALT
@app.route('/api/musicbrainz/releases')
def get_musicbrainz_releases():
    # ... 200 Zeilen ...

# app.py - NEU
from routes.routes_metadata import metadata_bp
app.register_blueprint(metadata_bp)
```

**Schritt 4: Test**

```bash
# Teste ob Routes noch funktionieren
curl http://localhost:5000/api/metadata/musicbrainz/releases
curl http://localhost:5000/api/dvd/status
```

### Status-Übersicht Endpoint

**Zentraler Endpoint für Modul-Route-Status:**

```python
# www/app.py

@app.route('/api/routes')
def get_registered_routes():
    """Zeige alle registrierten Routes (Debug-Endpoint)"""
    routes_info = {}
    
    for rule in app.url_map.iter_rules():
        # Gruppiere nach Blueprint
        blueprint = rule.endpoint.split('.')[0] if '.' in rule.endpoint else 'core'
        
        if blueprint not in routes_info:
            routes_info[blueprint] = []
        
        routes_info[blueprint].append({
            'endpoint': rule.endpoint,
            'methods': list(rule.methods - {'HEAD', 'OPTIONS'}),
            'path': str(rule)
        })
    
    return jsonify(routes_info)
```

**Beispiel-Response:**

```json
{
  "core": [
    {"endpoint": "index", "methods": ["GET"], "path": "/"},
    {"endpoint": "api_status", "methods": ["GET"], "path": "/api/status"}
  ],
  "metadata": [
    {"endpoint": "metadata.get_pending_metadata", "methods": ["GET"], "path": "/api/metadata/pending"},
    {"endpoint": "metadata.submit_metadata_selection", "methods": ["POST"], "path": "/api/metadata/select"}
  ],
  "dvd": [
    {"endpoint": "dvd.get_dvd_status", "methods": ["GET"], "path": "/api/dvd/status"},
    {"endpoint": "dvd.get_failed_dvds", "methods": ["GET"], "path": "/api/dvd/failed"}
  ]
}
```

### Zusammenfassung: Server-Restart Notwendigkeit

| Szenario | Statischer Ansatz | Dynamischer Ansatz | Hybrid |
|----------|-------------------|-------------------|--------|
| **Modul aktivieren** | ⚠️ **Restart nötig** | ✅ Kein Restart | ✅ Kein Restart |
| **Modul deaktivieren** | ⚠️ **Restart nötig** | ✅ Kein Restart | ✅ Kein Restart |
| **Performance** | ✅ Schneller | ⚠️ Minimal langsamer | ⚙️ Konfigurierbar |
| **Entwicklung** | ✅ Klar | ⚠️ Komplexer | ✅ Flexibel |
| **Produktion** | ⚠️ Downtime | ✅ Nahtlos | ✅ **Empfohlen** |

**Empfehlung für disk2iso:**

✅ **Dynamischer Ansatz** (Runtime-Check mit Decorator)

**Begründung:**
1. Kein Server-Restart bei Config-Änderungen
2. User kann Module sofort aktivieren/deaktivieren
3. Performance-Overhead minimal (<1ms pro Request)
4. Moderne Best-Practice (z.B. wie WordPress Plugins)

### JSON-Schema (Optional, für Validierung)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "disk2iso Module Manifest",
  "type": "object",
  "required": ["name", "version", "type", "components"],
  "properties": {
    "name": {
      "type": "string",
      "pattern": "^[a-z0-9-]+$"
    },
    "version": {
      "type": "string",
      "pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+$"
    },
    "type": {
      "type": "string",
      "enum": ["plugin", "core"]
    },
    "description": {
      "type": "string"
    },
    "components": {
      "type": "object",
      "required": ["bash", "config_var"],
      "properties": {
        "bash": {"type": "string"},
        "i18n": {"type": "array", "items": {"type": "string"}},
        "frontend": {"type": "array", "items": {"type": "string"}},
        "backend": {"type": "array", "items": {"type": "string"}},
        "config_var": {"type": "string"}
      }
    },
    "dependencies": {
      "type": "object",
      "properties": {
        "core": {"type": "array"},
        "external": {"type": "array"},
        "optional": {"type": "array"}
      }
    }
  }
}
```

---

### 🎨 Frontend-Integration (DOM-Injection)

```javascript
// www/static/js/<name>.js

class <Name>Module {
    constructor() {
        this.enabled = false;
    }
    
    async init() {
        // Prüfe ob Modul aktiv ist (Backend-API)
        const status = await fetch('/api/<name>/status');
        this.enabled = await status.json().enabled;
        
        if (this.enabled) {
            this.injectUI();
            this.attachEventHandlers();
        }
    }
    
    injectUI() {
        // DOM-Injection: Füge UI-Elemente hinzu
        const container = document.getElementById('module-container');
        container.insertAdjacentHTML('beforeend', `
            <div id="<name>-module" class="module-card">
                <h3><Name> Funktionen</h3>
                <!-- Modul-spezifische UI -->
            </div>
        `);
    }
    
    attachEventHandlers() {
        // Event-Handler für Modul-Funktionen
    }
}

// Auto-Initialisierung
document.addEventListener('DOMContentLoaded', () => {
    const module = new <Name>Module();
    module.init();
});
```

### 🔌 Backend-Routen (Modular)

```python
# www/routes/routes_<name>.py

from flask import Blueprint, jsonify

<name>_bp = Blueprint('<name>', __name__, url_prefix='/api/<name>')

@<name>_bp.route('/status')
def get_status():
    """Prüfe ob Modul aktiv ist"""
    # Lese von disk2iso-Status oder Config
    enabled = check_module_enabled('<name>')
    return jsonify({'enabled': enabled, 'version': '1.2.0'})

@<name>_bp.route('/function1')
def function1():
    """Modul-spezifische Funktion"""
    if not check_module_enabled('<name>'):
        return jsonify({'error': 'Module not enabled'}), 403
    
    # Modul-Logik
    return jsonify({'result': 'success'})

# Registrierung in app.py (nur wenn Modul aktiv)
def register_<name>_routes(app):
    if check_module_enabled('<name>'):
        app.register_blueprint(<name>_bp)
```

---

## 📊 Vergleich: Vorher / Nachher

| Aspekt | Aktuell (Monolith) | Neu (Plugin-System) |
|--------|-------------------|---------------------|
| **Modul-Aktivierung** | ⚠️ Dateipräsenz + Config (inkonsistent) | ✅ Config-Schalter (einheitlich) |
| **Dependency-Check** | ✅ Vorhanden, aber inkonsistent benannt | ✅ Standardisiert: `check_dependencies_<name>()` |
| **Sprachdatei-Loading** | ⚠️ Mal VOR Check (außerhalb) | ✅ IN Check als erste Zeile |
| **Frontend-Modularität** | ❌ Monolithisch | ✅ DOM-Injection pro Modul |
| **Backend-Routen** | ❌ Zentral, nicht modular | ✅ Pro Modul separierbar |
| **Modul-Abhängigkeiten** | ❌ BD braucht DVD | ✅ Alle unabhängig |
| **Erweiterbarkeit** | ❌ Komplexes Refactoring | ✅ Neue Datei + Registrierung |
| **Wartbarkeit** | ⚠️ Schwierig | ✅ Ein Modul = Ein Verantwortungsbereich |
| **Testing** | ❌ Monolithisch | ✅ Isoliert pro Modul |

---

## 🏗️ Migrations-Strategie

### **Phase 1: Konsistenz herstellen (Sofort)**

**Ziel**: Alle Module folgen gleichem Pattern

1. ✅ **Naming standardisieren**
   - `check_dependencies_cd()`, `check_dependencies_dvd()`, etc.
   
2. ✅ **Config-Schalter einführen**
   - `CD_ENABLED=true`, `DVD_ENABLED=true`, `BLURAY_ENABLED=true`
   
3. ✅ **Sprachdatei-Loading verschieben**
   - Als erste Zeile IN `check_dependencies_xxx()` (damit Log-Meldungen übersetzt sind)
   
4. ✅ **Lade-Logik vereinheitlichen**
   - Alle Module: Config → Source → Check → Language → Activate

### **Phase 2: Metadata-Plugin fertigstellen (In Progress)**

**Ziel**: Metadata als eigenständiges **optionales Modul** etablieren, das Copy-Modulen Metadaten-Funktionalität bereitstellt

#### **Ist-Stand (Analyse)**

✅ **Framework vorhanden:**
- `lib-metadata.sh` - Provider-System, Query/Wait/Apply Workflow, Cache-Management
- `lib-musicbrainz.sh` - MusicBrainz API Provider (Audio-CD)
- `lib-tmdb.sh` - TMDB API Provider (DVD/Blu-ray)
- `disk2iso.sh` lädt Metadata-Modul optional via `METADATA_ENABLED`

⚠️ **Probleme:**
- **Provider registrieren sich nicht** beim Framework
- **lib-cd.sh hat eigene MusicBrainz-Logik** (90+ Zeilen duplizierter Code)
  - `get_musicbrainz_metadata()` - Eigene API-Calls
  - `download_cover_art()` - Eigene Cover-Downloads
  - `create_album_nfo()` - Eigene NFO-Erstellung
- **lib-dvd.sh ruft nicht-existente Funktion auf** (`create_dvd_archive_metadata()`)
- **lib-bluray.sh ruft nicht-existente Funktion auf** (`create_dvd_archive_metadata()`)

#### **Migration Tasks**

**2.1 Provider-Registrierung aktivieren**
- [ ] lib-musicbrainz.sh: `metadata_register_provider()` Aufruf hinzufügen
  - [ ] Parse-Funktion implementieren (`musicbrainz_parse()`)
  - [ ] Apply-Funktion implementieren (`musicbrainz_apply()`)
- [ ] lib-tmdb.sh: `metadata_register_provider()` Aufruf hinzufügen
  - [ ] Parse-Funktion implementieren (`tmdb_parse()`)
  - [ ] Apply-Funktion implementieren (`tmdb_apply()`)

**2.2 lib-cd.sh Migration (Audio-CD)**
- [ ] **Entfernen**: `get_musicbrainz_metadata()` (Zeile ~163-350)
- [ ] **Entfernen**: `download_cover_art()` (Zeile ~361-410)
- [ ] **Entfernen**: `create_album_nfo()` (Zeile ~440-490)
- [ ] **Ersetzen** durch:
  ```bash
  if [[ "$METADATA_SUPPORT" == true ]]; then
      metadata_query_and_wait "audio-cd" "$cd_artist - $cd_album" "$cd_discid"
      # Provider setzt: disc_label, Cover-Datei, NFO-Datei
  fi
  ```
- [ ] Anpassung von `copy_audio_cd()` an neue Metadata-Integration
- [ ] Test: Audio-CD mit/ohne Metadata-Modul

**2.3 lib-dvd.sh Migration (Video-DVD)**
- [ ] **Entfernen**: Aufrufe von `create_dvd_archive_metadata()` (2 Stellen)
  - Zeile ~346 in `copy_video_dvd()`
  - Zeile ~447 in `copy_video_dvd_ddrescue()`
- [ ] **Ersetzen** durch:
  ```bash
  if [[ "$METADATA_SUPPORT" == true ]]; then
      metadata_query_and_wait "dvd-video" "$movie_title" "$disc_id"
      # TMDB Provider liefert besseres Label
  fi
  ```
- [ ] Test: Video-DVD mit/ohne Metadata-Modul

**2.4 lib-bluray.sh Migration (Blu-ray)**
- [ ] **Entfernen**: Aufruf von `create_dvd_archive_metadata()` (1 Stelle)
  - Zeile ~234 in `copy_bluray_ddrescue()`
- [ ] **Ersetzen** durch:
  ```bash
  if [[ "$METADATA_SUPPORT" == true ]]; then
      metadata_query_and_wait "bd-video" "$movie_title" "$disc_id"
      # TMDB Provider liefert besseres Label
  fi
  ```
- [ ] Test: Blu-ray mit/ohne Metadata-Modul

**2.5 Obsolete Dateien**
- [x] ✅ **Keine vorhanden!** Alle `lib-*-metadata*.sh` bereits entfernt

**Abschluss-Kriterium:** 
- Copy-Module nutzen ausschließlich lib-metadata.sh Framework
- Keine duplizierten Metadata-API-Calls mehr in lib-cd.sh
- Alle Tests laufen mit METADATA_ENABLED=true/false

---

## 🔄 Workflow-Analyse: ISO-Erstellung (Vollständige Installation)

### **Übersicht: State Machine Workflow**

| Phase | State | Aktion | Beteiligte Module | Notizen |
|-------|-------|--------|-------------------|---------|
| **1. Service Start** | `INITIALIZING` | System-Check, Modul-Loading | Core, lib-systeminfo, lib-config | Lädt alle optionalen Module |
| **2. Laufwerk suchen** | `WAITING_FOR_DRIVE` | Optisches Laufwerk erkennen | lib-drivestat | Polling alle 20s |
| **3. Laufwerk bereit** | `DRIVE_DETECTED` | Laufwerk-Status prüfen | lib-drivestat | Device-Ready-Check |
| **4. Medium warten** | `WAITING_FOR_MEDIA` | Auf Medium-Einlage warten | lib-drivestat | Polling alle 2s |
| **5. Medium erkannt** | `MEDIA_DETECTED` | Spin-Up abwarten (3s) | lib-drivestat | Medium wird lesbar |
| **6. Analyse** | `ANALYZING` | Disc-Typ + Label ermitteln | lib-diskinfos | **Kritischer Punkt!** |
| **7. Metadaten (opt.)** | `WAITING_FOR_METADATA` | User-Auswahl bei mehreren Treffern | lib-metadata, Provider | Nur wenn aktiviert |
| **8. Kopieren** | `COPYING` | ISO erstellen | lib-cd/dvd/bluray/common | Modul-spezifisch |
| **9. Abschluss** | `COMPLETED` / `ERROR` | MD5, Cleanup, Status-Update | lib-common, lib-api | API + MQTT Update |
| **10. Entfernung warten** | `WAITING_FOR_REMOVAL` | Auf Medium-Entnahme warten | lib-drivestat | Polling alle 5s |
| **11. Bereit** | `IDLE` → zurück zu 4 | Zurück zum Warten | - | Endlos-Schleife |

---

### **Detaillierter Workflow nach Medium-Typ**

#### **Audio-CD Workflow**

| Schritt | Funktion | Modul | Beschreibung | Zu standardisierende API |
|---------|----------|-------|--------------|-------------------------|
| **Typ-Erkennung** | `detect_disc_type()` | lib-diskinfos | Prüft TOC → `audio-cd` | ✅ Bereits einheitlich |
| **Label-Erkennung** | `get_cdtext()` | lib-cd | CD-TEXT auslesen (Fallback) | ⚠️ Modul-spezifisch |
| **Disc-ID lesen** | `cd-discid` | lib-cd | DiscID + TOC für MusicBrainz | ⚠️ Modul-spezifisch |
| **Metadaten-Query** | `get_musicbrainz_metadata()` | lib-cd | **WIRD ERSETZT** durch lib-metadata | 🔴 Migration nötig |
| **User-Auswahl** | `wait_for_metadata_selection()` | lib-cd | **WIRD ERSETZT** durch lib-metadata | 🔴 Migration nötig |
| **Cover-Download** | `download_cover_art()` | lib-cd | **WIRD ERSETZT** durch lib-musicbrainz | 🔴 Migration nötig |
| **NFO erstellen** | `create_album_nfo()` | lib-cd | **WIRD ERSETZT** durch lib-musicbrainz | 🔴 Migration nötig |
| **Ripping** | `cdparanoia` | lib-cd | Audio → WAV | ✅ Modul-spezifisch (OK) |
| **Encoding** | `lame` | lib-cd | WAV → MP3 (VBR V2) | ✅ Modul-spezifisch (OK) |
| **ISO erstellen** | `genisoimage` | lib-cd | MP3s → ISO | ✅ Modul-spezifisch (OK) |
| **MD5-Summe** | `md5sum` | lib-common | Checksumme berechnen | ✅ Bereits einheitlich |
| **Größe ermitteln** | `du -b` | lib-common | ISO-Größe für API | ✅ Bereits einheitlich |

---

#### **Video-DVD Workflow**

| Schritt | Funktion | Modul | Beschreibung | Zu standardisierende API |
|---------|----------|-------|--------------|-------------------------|
| **Typ-Erkennung** | `detect_disc_type()` | lib-diskinfos | Prüft VIDEO_TS/ → `dvd-video` | ✅ Bereits einheitlich |
| **Label-Erkennung** | `get_disc_label()` | lib-diskinfos | UDF/ISO9660 Volume-ID | ✅ Bereits einheitlich |
| **Disc-ID lesen** | `blkid` / `isoinfo` | lib-diskinfos | Volume Serial | ✅ Bereits einheitlich |
| **Metadaten-Query** | `create_dvd_archive_metadata()` | lib-dvd | **EXISTIERT NICHT!** → lib-metadata | 🔴 Migration nötig |
| **TMDB-Suche** | - | lib-tmdb | **NEU:** TMDB-Provider Integration | 🔴 Migration nötig |
| **User-Auswahl** | - | lib-metadata | Workflow via Framework | 🔴 Migration nötig |
| **Label verbessern** | - | lib-tmdb | Besseres Label aus TMDB | 🔴 Migration nötig |
| **Ripping (Methode 1)** | `dvdbackup` + `genisoimage` | lib-dvd | Entschlüsselt, schnell | ✅ Modul-spezifisch (OK) |
| **Ripping (Methode 2)** | `ddrescue` | lib-dvd | Verschlüsselt, robust | ⚠️ Shared mit lib-common |
| **Ripping (Fallback)** | `dd` | lib-common | Verschlüsselt, langsam | ✅ Bereits einheitlich |
| **MD5-Summe** | `md5sum` | lib-common | Checksumme berechnen | ✅ Bereits einheitlich |
| **Größe ermitteln** | `du -b` | lib-common | ISO-Größe für API | ✅ Bereits einheitlich |

---

#### **Blu-ray Workflow**

| Schritt | Funktion | Modul | Beschreibung | Zu standardisierende API |
|---------|----------|-------|--------------|-------------------------|
| **Typ-Erkennung** | `detect_disc_type()` | lib-diskinfos | Prüft BDMV/ → `bd-video` | ✅ Bereits einheitlich |
| **Label-Erkennung** | `get_disc_label()` | lib-diskinfos | UDF Volume-ID | ✅ Bereits einheitlich |
| **Disc-ID lesen** | `blkid` | lib-diskinfos | Volume Serial | ✅ Bereits einheitlich |
| **Metadaten-Query** | `create_dvd_archive_metadata()` | lib-bluray | **EXISTIERT NICHT!** → lib-metadata | 🔴 Migration nötig |
| **TMDB-Suche** | - | lib-tmdb | **NEU:** TMDB-Provider Integration | 🔴 Migration nötig |
| **User-Auswahl** | - | lib-metadata | Workflow via Framework | 🔴 Migration nötig |
| **Label verbessern** | - | lib-tmdb | Besseres Label aus TMDB | 🔴 Migration nötig |
| **Ripping (Methode 1)** | `ddrescue` | lib-bluray | Robust, schnell | ⚠️ Shared mit lib-common |
| **Ripping (Fallback)** | `dd` | lib-common | Langsam | ✅ Bereits einheitlich |
| **MD5-Summe** | `md5sum` | lib-common | Checksumme berechnen | ✅ Bereits einheitlich |
| **Größe ermitteln** | `du -b` | lib-common | ISO-Größe für API | ✅ Bereits einheitlich |

---

### **Einheitliche API-Funktionen (Zu standardisierende Schnittstellen)**

#### **Kernfunktionen (bereits einheitlich)** ✅

| Funktion | Modul | Zweck | Verfügbar für |
|----------|-------|-------|---------------|
| `detect_disc_type()` | lib-diskinfos | Medium-Typ ermitteln | Alle |
| `get_disc_label()` | lib-diskinfos | Volume-Label auslesen | DVD, BD, Daten-CD |
| `md5sum` | lib-common | Checksumme erstellen | Alle |
| `du -b` | lib-common | Datei-Größe ermitteln | Alle |
| `init_filenames()` | lib-common | ISO/MD5/LOG-Namen generieren | Alle |
| `cleanup_disc_operation()` | lib-common | Temp-Dateien löschen | Alle |

#### **Metadata-Funktionen (zu vereinheitlichen)** 🔴

| Ist-Funktion | Modul | Soll-Funktion | Neues Modul | Zweck |
|--------------|-------|---------------|-------------|-------|
| `get_musicbrainz_metadata()` | lib-cd | `metadata_query_and_wait()` | lib-metadata | API-Abfrage + Warten |
| `download_cover_art()` | lib-cd | `musicbrainz_download_cover()` | lib-musicbrainz | Cover-Download |
| `create_album_nfo()` | lib-cd | `musicbrainz_create_nfo()` | lib-musicbrainz | NFO-Datei erstellen |
| `create_dvd_archive_metadata()` | lib-dvd | `metadata_query_and_wait()` | lib-metadata | API-Abfrage + Warten |
| `create_dvd_archive_metadata()` | lib-bluray | `metadata_query_and_wait()` | lib-metadata | API-Abfrage + Warten |
| - | - | `tmdb_download_poster()` | lib-tmdb | Poster-Download |
| - | - | `tmdb_create_nfo()` | lib-tmdb | NFO für Kodi/Jellyfin |

#### **Disc-ID-Funktionen (modul-spezifisch, zu dokumentieren)** ⚠️

| Medium | Funktion | Tool | Rückgabe | Standard-Kandidat? |
|--------|----------|------|----------|-------------------|
| Audio-CD | `cd-discid` | cd-discid | MusicBrainz DiscID + TOC | Nein (CD-spezifisch) |
| DVD | `blkid -s LABEL` | blkid | Volume-ID | Ja (generisch) |
| Blu-ray | `blkid -s LABEL` | blkid | Volume-ID | Ja (generisch) |

**Vorschlag:** Einheitliche Funktion `get_disc_id()` in lib-diskinfos:
```bash
get_disc_id() {
    case "$disc_type" in
        audio-cd)
            cd-discid "$CD_DEVICE" | cut -d' ' -f1
            ;;
        *)
            blkid -s LABEL -o value "$CD_DEVICE" 2>/dev/null || echo "unknown"
            ;;
    esac
}
```

---

### **Optimierungsvorschläge für einheitliche Plugin-API**

**1. Standard-Funktionen pro Copy-Modul:**
```bash
# Jedes Modul implementiert:
module_get_disc_id()        # Eindeutige ID ermitteln
module_get_label()          # Label/Titel auslesen
module_get_metadata()       # Metadata via lib-metadata Framework
module_copy()               # Kopiervorgang durchführen
module_verify()             # Verifikation (MD5, etc.)
module_cleanup()            # Aufräumen
```

**2. Metadata-Integration (standardisiert):**
```bash
# In lib-cd.sh, lib-dvd.sh, lib-bluray.sh:
if [[ "$METADATA_SUPPORT" == true ]]; then
    metadata_query_and_wait "$disc_type" "$search_term" "$disc_id"
    # Setzt globale Variablen:
    # - disc_label (verbessertes Label)
    # - METADATA_RESULT (JSON mit allen Infos)
fi
```

**3. Provider-Interface (standardisiert):**
```bash
# Jeder Provider implementiert:
${provider}_query()         # API-Abfrage
${provider}_parse()         # User-Auswahl verarbeiten
${provider}_apply()         # Metadaten anwenden (Label, Cover, NFO)
${provider}_download_artwork()  # Cover/Poster laden
${provider}_create_nfo()    # NFO-Datei erstellen
```

---

### **Phase 3: Frontend-Modularisierung (TODO)**

**Ziel**: UI-Komponenten werden von Modulen injiziert

1. **Base-Template** erstellen (ohne Modul-UI)
2. **JS-Module** pro Plugin (`cd.js`, `dvd.js`, `metadata.js`)
3. **DOM-Injection** Pattern implementieren
4. **Module auto-registrieren** bei Aktivierung

### **Phase 4: Backend-Routing modularisieren (TODO)**

**Ziel**: Jedes Modul hat eigene Routen

1. **Routen extrahieren**: `routes_cd.py`, `routes_dvd.py`, etc.
2. **Blueprint-System** nutzen
3. **Dynamische Registrierung** basierend auf Modul-Status
4. **API-Versioning** einführen (`/api/v1/<module>/...`)

### **Phase 5: Weitere Module portieren (Future)**

**Ziel**: Alle Features als Plugins

- MQTT → `lib-mqtt.sh` (bereits vorhanden, refactorn)
- Web-UI → `lib-web.sh` (extrahieren)
- API → `lib-api.sh` (separieren)
- Zukünftige Module: Discogs, IMDB, AniDB, etc.

---

## 🎯 Konsistenz-Regeln (Architektur-Guidelines)

### **Regel 1: Ein Modul = Eine Datei**
- Keine Funktions-Duplikation zwischen Modulen
- Gemeinsame Funktionen → Core-Libs (`lib-common.sh`, `lib-files.sh`, etc.)

### **Regel 2: Dependency-Check ist erste Funktion**
```bash
# IMMER als ERSTE Funktion im Modul
check_dependencies_<name>() {
    # Prüfung ohne Sprachdateien (noch nicht geladen!)
}
```

### **Regel 3: Kein Code außerhalb von Funktionen**
```bash
# ❌ FALSCH
liblogging_load_language_file "<name>"  # Global ausgeführt beim Source!

# ✅ RICHTIG (in disk2iso.sh NACH Check)
if check_dependencies_<name>; then
    liblogging_load_language_file "<name>"
fi
```

### **Regel 4: Naming-Konvention**
```bash
lib-<name>.sh        → check_dependencies_<name>()
                     → get_path_<name>()
                     → <NAME>_SUPPORT=true/false
                     → <NAME>_ENABLED (Config)
```

### **Regel 5: Module sind optional**
- Core-Tool (`disk2iso.sh`) funktioniert ohne jedes Modul
- Module erweitern Funktionalität, sind aber nicht zwingend

---

## 💡 Vorteile des Plugin-Systems

### **Für Entwickler**
- ✅ Klare Verantwortungsbereiche
- ✅ Isoliert testbar
- ✅ Einfach erweiterbar
- ✅ Weniger Merge-Konflikte

### **Für Anwender**
- ✅ Nur installieren was benötigt wird
- ✅ Dediziert aktivieren/deaktivieren
- ✅ Klare Fehlermeldungen pro Modul
- ✅ Bessere Performance (weniger Code geladen)

### **Für Projekt**
- ✅ Professionelle Architektur
- ✅ Zukunftssicher
- ✅ Einfach zu dokumentieren
- ✅ Best-Practice (Plugin-Pattern)

---

## ✅ Status: Phase 1 (Konsistenz) - In Progress

**Abgeschlossen:**
- ✅ Metadata-Framework implementiert
- ✅ Naming standardisiert (`check_dependencies_*`)
- ✅ Provider-System (MusicBrainz, TMDB)

**TODO:**
- ⏳ Config-Schalter für CD/DVD/BD
- ⏳ Sprachdatei-Loading verschieben
- ⏳ Copy-Module auf Metadata umstellen
- ⏳ Obsolete Dateien löschen

**Nächster Schritt:**
Vollständige Konsistenz aller Module herstellen → Dann Frontend/Backend modularisieren

---

## 🎨 Frontend-Konfigurationsseite: Best Practices

### **Problem-Analyse: Zwei Architektur-Fragen**

#### **1. UI-Struktur: Sektionen vs. Master-Sektion**

**Aktuelle Implementierung:**
- Pro Modul eine dedizierte Sektion (System, Audio-CD, DVD, MQTT, TMDB)
- Alle Sektionen immer sichtbar (unabhängig ob Modul aktiviert)
- Statisches HTML-Template mit Jinja2

**Alternative: Master-Sektion + DOM-Injection**
- Zentrale Sektion "Module" mit Checkboxen (DVD aktivieren, CD aktivieren, etc.)
- Config-Seite dynamisch neu laden nach Modul-Aktivierung
- Nur aktivierte Module zeigen ihre Config-Optionen

```html
<!-- Master-Sektion Ansatz -->
<div class="form-section">
    <h2>Aktivierte Module</h2>
    <label><input type="checkbox" id="module_dvd"> DVD/Blu-ray Support</label>
    <label><input type="checkbox" id="module_cd"> Audio-CD Support</label>
    <label><input type="checkbox" id="module_metadata"> TMDB Metadaten</label>
</div>

<!-- DVD Config nur wenn module_dvd=true -->
<div class="form-section" id="config_dvd" style="display:none;">
    <h2>DVD/Blu-ray Einstellungen</h2>
    <!-- ... -->
</div>
```

**Vergleich:**

| Aspekt | Statische Sektionen (aktuell) | Master-Sektion + DOM-Injection |
|--------|-------------------------------|-------------------------------|
| **User-Experience** | ✅ Übersichtlich, alle Optionen sofort sichtbar | ⚠️ Zusätzlicher Klick (Module aktivieren → Reload) |
| **Performance** | ⚠️ Lädt immer alle Sektionen (minimal overhead) | ✅ Lädt nur aktivierte Module |
| **Wartbarkeit** | ✅ Einfaches HTML-Template | ⚠️ Komplexere JS-Logik (DOM-Injection) |
| **Modularität** | ⚠️ Module-Config fest im Template | ✅ Config-UI pro Modul isoliert |
| **Progressive Disclosure** | ❌ Alles immer sichtbar | ✅ Zeige nur was relevant ist |
| **Onboarding** | ⚠️ Überfordernd bei vielen Modulen | ✅ Klare Übersicht aktivierter Features |

**Empfehlung: HYBRID-ANSATZ**

```html
<!-- Phase 1: Statische Sektionen BEHALTEN (wie aktuell) -->
<div class="form-section" data-module="dvd">
    <h2>
        <input type="checkbox" class="module-toggle" id="module_dvd" checked>
        DVD/Blu-ray Support
    </h2>
    <div class="module-config">
        <!-- Config-Optionen hier -->
    </div>
</div>
```

```javascript
// Phase 2: Kollabierbare Sektionen (kein Reload nötig)
document.querySelectorAll('.module-toggle').forEach(toggle => {
    toggle.addEventListener('change', (e) => {
        const section = e.target.closest('.form-section');
        const config = section.querySelector('.module-config');
        config.style.display = e.target.checked ? 'block' : 'none';
    });
});
```

**Vorteile Hybrid:**
- ✅ Alle Optionen auf einer Seite (keine Page-Reloads)
- ✅ Modul-Aktivierung via Checkbox (visuell klar)
- ✅ Deaktivierte Module: Config ausgeblendet (Progressive Disclosure)
- ✅ Kein komplexes DOM-Injection (einfaches CSS `display:none`)
- ✅ Zukunftssicher: Jede Sektion kann später als eigene Komponente extrahiert werden

---

#### **2. Config-Management: Zentralisiert vs. Dezentral**

**Aktuelle Implementierung (Zentralisiert):**

```bash
# lib-config.sh - Alle Setter-Funktionen in einer Datei

# Handler-Registry
declare -A CONFIG_HANDLERS=(
    ["DEFAULT_OUTPUT_DIR"]="set_default_output_dir:disk2iso"
    ["MQTT_BROKER"]="set_mqtt_broker:disk2iso"
    ["TMDB_API_KEY"]="set_tmdb_api_key:disk2iso-web"
)

# Spezialisierte Setter
set_default_output_dir() {
    local value="$1"
    # Validierung
    if [[ ! -d "$value" ]]; then return 1; fi
    # Schreiben
    sed -i "s|^DEFAULT_OUTPUT_DIR=.*|DEFAULT_OUTPUT_DIR=\"${value}\"|" "$config_file"
}

set_tmdb_api_key() {
    local value="$1"
    sed -i "s|^TMDB_API_KEY=.*|TMDB_API_KEY=\"${value}\"|" "$config_file"
}

# Master-Funktion
apply_config_changes() {
    local json_input="$1"
    for config_key in "${!CONFIG_HANDLERS[@]}"; do
        local handler=$(echo "${CONFIG_HANDLERS[$config_key]}" | cut -d: -f1)
        $handler "$value"
    done
}
```

**Alternative: Dezentrale Modul-Verwaltung**

```bash
# lib-common.sh - Globale Config-Funktionen

set_config_value() {
    local key="$1"
    local value="$2"
    local validator="$3"  # Optional: Validierungs-Funktion
    
    # Validierung delegieren an Modul
    if [[ -n "$validator" ]] && command -v "$validator" >/dev/null; then
        if ! $validator "$value"; then
            echo '{"success": false, "message": "Validation failed"}' >&2
            return 1
        fi
    fi
    
    # Schreibe in Config
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$config_file"
    return $?
}

get_config_value() {
    local key="$1"
    grep "^${key}=" "$config_file" | cut -d'=' -f2- | tr -d '"'
}
```

```bash
# lib-dvd-metadata.sh - Modul verwaltet eigene Config

DVD_METADATA_CONFIG_KEYS=(
    "TMDB_API_KEY"
    "TMDB_CACHE_ENABLED"
    "TMDB_AUTO_SELECT"
)

validate_tmdb_api_key() {
    local key="$1"
    [[ ${#key} -eq 32 ]] && [[ "$key" =~ ^[a-f0-9]+$ ]]
}

# Modul-Interface: Nutzt globale Funktion
set_dvd_metadata_config() {
    local key="$1"
    local value="$2"
    
    case "$key" in
        TMDB_API_KEY)
            set_config_value "$key" "$value" "validate_tmdb_api_key"
            ;;
        TMDB_CACHE_ENABLED)
            set_config_value "$key" "$value"
            ;;
    esac
}
```

**Vergleich:**

| Aspekt | Zentralisiert (lib-config.sh) | Dezentral (Modul-Funktionen) |
|--------|-------------------------------|------------------------------|
| **Modularität** | ⚠️ Alle Setter in einer Datei (wächst mit jedem Modul) | ✅ Jedes Modul verwaltet eigene Config |
| **Wartbarkeit** | ⚠️ lib-config.sh wird schnell groß | ✅ Modul-Code bleibt zusammen |
| **Validierung** | ✅ Zentral sichtbar | ⚠️ Verteilt über Module (aber klarer Scope) |
| **Service-Restart** | ✅ Zentral gesteuert (CONFIG_HANDLERS Map) | ⚠️ Jedes Modul muss registrieren |
| **Debugging** | ✅ Ein File durchsuchen | ⚠️ Mehrere Dateien |
| **Plugin-Architektur** | ❌ Nicht kompatibel (lib-config.sh muss aktualisiert werden) | ✅ Modul bringt eigene Config mit |
| **Dependencies** | ✅ Keine Circular-Dependencies | ⚠️ Alle Module laden lib-common.sh |

**Empfehlung: HYBRID-ANSATZ (Registry-Pattern)**

```bash
# lib-config.sh - Bleibt zentrale Config-Engine

declare -A CONFIG_HANDLERS=()

# Globale Registrierungs-Funktion
register_config_handler() {
    local key="$1"
    local handler_func="$2"
    local restart_service="$3"
    
    CONFIG_HANDLERS["$key"]="${handler_func}:${restart_service}"
}

# Generische Setter/Getter
set_config_value() {
    local key="$1"
    local value="$2"
    
    # Lookup Handler
    if [[ -n "${CONFIG_HANDLERS[$key]}" ]]; then
        local handler=$(echo "${CONFIG_HANDLERS[$key]}" | cut -d: -f1)
        $handler "$key" "$value"
    else
        # Fallback: Direktes Schreiben
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$config_file"
    fi
}

get_config_value() {
    local key="$1"
    grep "^${key}=" "$config_file" | cut -d'=' -f2- | tr -d '"'
}
```

```bash
# lib-dvd-metadata.sh - Modul registriert eigene Handler

validate_and_set_tmdb_api_key() {
    local key="$1"
    local value="$2"
    
    # Validierung
    if ! [[ ${#value} -eq 32 ]] || ! [[ "$value" =~ ^[a-f0-9]+$ ]]; then
        echo '{"success": false, "message": "Invalid API Key format"}' >&2
        return 1
    fi
    
    # Schreibe in Config
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$config_file"
}

# Registriere Handler beim Laden des Moduls
register_config_handler "TMDB_API_KEY" "validate_and_set_tmdb_api_key" "disk2iso-web"
register_config_handler "TMDB_CACHE_ENABLED" "set_config_value" "none"
```

**Vorteile Hybrid:**
- ✅ **Modularität:** Jedes Modul registriert eigene Handler (Plugin-kompatibel)
- ✅ **Zentralität:** `lib-config.sh` behält Orchestrierung (Service-Restarts)
- ✅ **Selbst-Verwaltung:** Module können komplexe Validierung implementieren
- ✅ **Fallback:** Unbekannte Keys werden automatisch geschrieben
- ✅ **Migration:** Bestehendes System bleibt funktionsfähig

---

### **Frontend-Backend-Interaktion**

**Aktueller Workflow:**

```javascript
// config.js - Granulare Änderungen tracken
const changedValues = {};  // Nur geänderte Werte

function handleFieldChange(event) {
    const configKey = event.target.getAttribute('data-config-key');
    changedValues[configKey] = event.target.value;
}

function saveConfig() {
    fetch('/api/config', {
        method: 'POST',
        body: JSON.stringify(changedValues)  // Nur geänderte Werte
    });
}
```

```python
# app.py - Backend delegiert an Bash
@app.route('/api/config', methods=['POST'])
def api_config():
    changes = request.get_json()  # {"TMDB_API_KEY": "abc123..."}
    
    script = f"""
    source {INSTALL_DIR}/lib/lib-config.sh
    apply_config_changes '{json.dumps(changes)}'
    """
    result = subprocess.run(['/bin/bash', '-c', script])
    return jsonify(json.loads(result.stdout))
```

```bash
# lib-config.sh - Bash verarbeitet Änderungen
apply_config_changes() {
    local json_input="$1"
    
    for config_key in "${!CONFIG_HANDLERS[@]}"; do
        local value=$(echo "$json_input" | grep -o "\"${config_key}\"[[:space:]]*:[[:space:]]*[^,}]*")
        if [[ -n "$value" ]]; then
            local handler=$(echo "${CONFIG_HANDLERS[$config_key]}" | cut -d: -f1)
            $handler "$value"
        fi
    done
    
    perform_service_restarts  # Automatischer Restart betroffener Services
}
```

**Vorteile aktuelles System:**
- ✅ **Intelligente Restarts:** Nur betroffene Services werden neu gestartet
- ✅ **Granular:** Nur geänderte Werte werden übertragen
- ✅ **Atomic:** Alle Änderungen in einer Transaktion
- ✅ **Bash-First:** Config-Logik bleibt in Bash (konsistent mit restlichem System)

**Erweiterung für Module (Registry-Pattern):**

```javascript
// Frontend: Modul-spezifische Validierung BEFORE Submit
const moduleValidators = {
    'TMDB_API_KEY': (value) => {
        if (!/^[a-f0-9]{32}$/.test(value)) {
            return 'API Key muss 32 Hex-Zeichen sein';
        }
        return null;  // Valid
    },
    'MQTT_PORT': (value) => {
        if (value < 1 || value > 65535) {
            return 'Port muss zwischen 1 und 65535 liegen';
        }
        return null;
    }
};

function saveConfig() {
    // Client-Side Validierung
    for (const [key, value] of Object.entries(changedValues)) {
        if (moduleValidators[key]) {
            const error = moduleValidators[key](value);
            if (error) {
                showError(error);
                return;
            }
        }
    }
    
    // Submit
    fetch('/api/config', {method: 'POST', body: JSON.stringify(changedValues)});
}
```

---

### **Migration-Roadmap: Schrittweise Modularisierung**

#### **Phase 1: Hybrid UI-Struktur (Quick Win)**

**Ziel:** Modul-Aktivierung via Checkbox + Config-Ausblendung

```html
<!-- config.html - Erweitern um Module-Toggles -->
<div class="form-section module-section" data-module="dvd">
    <h2>
        <input type="checkbox" class="module-toggle" id="module_dvd_enabled" 
               data-config-key="DVD_ENABLED" checked>
        <label for="module_dvd_enabled">DVD/Blu-ray Support</label>
    </h2>
    <div class="module-config" id="config_dvd">
        <!-- Bestehende DVD-Config hier -->
    </div>
</div>
```

```css
/* style.css */
.module-section.disabled .module-config {
    display: none;
    opacity: 0.5;
}
```

```javascript
// config.js - Toggle-Logik
document.querySelectorAll('.module-toggle').forEach(toggle => {
    toggle.addEventListener('change', (e) => {
        const section = e.target.closest('.module-section');
        section.classList.toggle('disabled', !e.target.checked);
        
        // Registriere Änderung für Config-Save
        const configKey = e.target.getAttribute('data-config-key');
        changedValues[configKey] = e.target.checked;
    });
});
```

**Aufwand:** ~2 Stunden  
**Benefit:** Sofortige visuelle Klarheit welche Module aktiv sind

---

#### **Phase 2: Config-Handler Registrierung (Fundament)**

**Ziel:** Jedes Modul registriert eigene Config-Handler

```bash
# lib-dvd-metadata.sh - Erweitern um Registration
init_dvd_metadata_config() {
    register_config_handler "TMDB_API_KEY" "validate_and_set_tmdb_api_key" "disk2iso-web"
    register_config_handler "TMDB_CACHE_ENABLED" "set_config_value" "none"
    register_config_handler "TMDB_AUTO_SELECT" "set_config_value" "disk2iso"
}

# Auto-Load beim Source
init_dvd_metadata_config
```

```bash
# disk2iso.sh - Beim Start alle Module laden
source "${SCRIPT_DIR}/lib/lib-config.sh"
source "${SCRIPT_DIR}/lib/lib-dvd-metadata.sh"  # Registriert automatisch Handler
source "${SCRIPT_DIR}/lib/lib-cd-metadata.sh"   # Registriert automatisch Handler
```

**Aufwand:** ~4 Stunden (alle Module migrieren)  
**Benefit:** Config-Logik lebt wo sie hingehört (im Modul)

---

#### **Phase 3: Frontend-Module-Injection (Optional)**

**Ziel:** Config-UI-Komponenten aus Manifesten laden

```json
// conf/lib-dvd-metadata.json
{
    "name": "dvd-metadata",
    "components": {
        "config_ui": "static/js/config-modules/dvd-metadata-config.js"
    },
    "config_keys": [
        {"key": "TMDB_API_KEY", "type": "string", "required": true},
        {"key": "TMDB_CACHE_ENABLED", "type": "boolean", "default": true}
    ]
}
```

```javascript
// static/js/config-modules/dvd-metadata-config.js
export function renderDvdMetadataConfig(container, values) {
    container.innerHTML = `
        <div class="form-group">
            <label for="tmdb_api_key">TMDB API-Key</label>
            <input type="text" id="tmdb_api_key" value="${values.TMDB_API_KEY || ''}">
        </div>
    `;
}

export function validateDvdMetadataConfig(values) {
    if (!/^[a-f0-9]{32}$/.test(values.TMDB_API_KEY)) {
        return {valid: false, error: 'Invalid API Key'};
    }
    return {valid: true};
}
```

**Aufwand:** ~8 Stunden (Framework + Migration)  
**Benefit:** Vollständige Modul-Isolation (Config-UI = Teil des Moduls)

---

### **Empfehlung: Pragmatischer Ansatz**

**Sofort umsetzen (Phase 1):**
- ✅ Hybrid UI-Struktur mit Checkboxen (minimaler Aufwand, großer UX-Gewinn)
- ✅ Bestehende statische Sektionen BEHALTEN (bewährtes System)
- ✅ Keine Page-Reloads (CSS-basiertes Hide/Show)

**Mittelfristig (Phase 2):**
- ✅ Config-Handler Registrierung (Fundament für Plugin-System)
- ✅ Jedes Modul verwaltet eigene Config-Keys
- ✅ lib-config.sh bleibt Orchestrator (Service-Restarts)

**Langfristig (Phase 3 - Optional):**
- ⏳ Nur wenn viele Module hinzukommen (>10)
- ⏳ DOM-Injection lohnt sich erst bei komplexen Config-UIs
- ⏳ Aktuelles statisches Template ist wartbar genug

**Begründung:**
- Bestehende Architektur ist bereits gut (zentralisiert aber modular erweiterbar)
- Hybrid-Ansatz vereint Vorteile beider Welten
- Schrittweise Migration ohne Breaking Changes
- Performance-Overhead minimal (paar Checkboxen + CSS)

---

## 📝 TODO: Migration-Plan (Umsetzungs-Reihenfolge)

### **PHASE 1: Fundament - Konsistenz herstellen**
**Priorität:** HOCH | **Aufwand:** ~6 Stunden | **Status:** In Progress

#### 1.1 Config-Schalter für alle Module einführen
- [x] ~~`disk2iso.conf` erweitern um `*_ENABLED` Variablen~~ (Via INI-Manifeste gelöst)
  - [x] ~~`CD_ENABLED=true`~~ (In conf/lib-cd.ini [module] definiert)
  - [x] ~~`DVD_ENABLED=true`~~ (In conf/lib-dvd.ini [module] definiert)
  - [x] ~~`BLURAY_ENABLED=true`~~ (In conf/lib-bluray.ini [module] definiert)
  - [x] ~~`METADATA_ENABLED=true`~~ (bereits vorhanden + in lib-metadata.ini)
- [ ] Template `disk2iso.conf.template` aktualisieren
- [ ] Installations-Script (`install.sh`) prüfen/anpassen

#### 1.2 Bash: Modul-Lade-Logik standardisieren
- [x] ~~`disk2iso.sh` - Modul-Loading für CD anpassen~~
  - [x] ~~Config-Check hinzufügen~~ (Via INI-Manifest gelöst)
  - [x] ~~Sprachdatei-Loading als erste Zeile IN `check_dependencies_cd()` verschieben~~ (In check_module_dependencies() integriert)
  - [x] ~~Pattern: Config → Source → Check (mit Language als 1. Zeile) → Activate~~ (Implementiert via Manifest-System)
- [x] ~~`disk2iso.sh` - Modul-Loading für DVD anpassen~~
  - [x] ~~Config-Check hinzufügen~~ (Via INI-Manifest gelöst)
  - [x] ~~Sprachdatei-Loading als erste Zeile IN `check_dependencies_dvd()` verschieben~~ (In check_module_dependencies() integriert)
- [x] ~~`disk2iso.sh` - Modul-Loading für Bluray anpassen~~
  - [x] ~~Config-Check hinzufügen~~ (Via INI-Manifest gelöst)
  - [x] ~~Sprachdatei-Loading als erste Zeile IN `check_dependencies_bluray()` verschieben~~ (In check_module_dependencies() integriert)

#### 1.3 Bash: Naming-Konsistenz (falls noch nötig)
- [x] ~~Prüfe alle `check_dependencies_*()` Funktionen auf korrekte Benennung~~ (Alle Module: check_dependencies_<module>)
- [x] ~~Prüfe alle `*_SUPPORT` Flags auf Konsistenz~~ (Alle Module: <MODULE>_SUPPORT=false → true)
- [x] ~~Prüfe alle `get_path_*()` Funktionen auf Konsistenz~~ (Konsistent implementiert)

#### 1.4 Backend: Config-Unterstützung für neue Schalter
- [ ] `www/app.py` - `get_config()` erweitern
  - [ ] `cd_enabled` lesen und zurückgeben
  - [ ] `dvd_enabled` lesen und zurückgeben
  - [ ] `bluray_enabled` lesen und zurückgeben
- [ ] `lib/lib-config.sh` - Handler registrieren (falls nötig)
  - [ ] `CD_ENABLED` in `CONFIG_HANDLERS` aufnehmen
  - [ ] `DVD_ENABLED` in `CONFIG_HANDLERS` aufnehmen
  - [ ] `BLURAY_ENABLED` in `CONFIG_HANDLERS` aufnehmen

#### 1.5 Test: Basis-Funktionalität
- [ ] Test: CD-Modul deaktivieren via Config → Service neu starten → Prüfen
- [ ] Test: DVD-Modul deaktivieren via Config → Service neu starten → Prüfen
- [ ] Test: Alle Module deaktivieren → Nur Core-Funktionen verfügbar

**Abschluss-Kriterium:** Alle Module können via Config aktiviert/deaktiviert werden

---

### **PHASE 2: Metadata-Modul finalisieren**
**Priorität:** HOCH | **Aufwand:** ~8 Stunden | **Status:** Teilweise erledigt

#### 2.1 Copy-Module auf Metadata-Framework migrieren
- [ ] `lib-cd.sh` anpassen
  - [ ] `query_musicbrainz()` entfernen → Nutze `query_metadata_before_copy()`
  - [ ] Provider-Check integrieren: `has_metadata_provider "musicbrainz"`
  - [ ] Test: Audio-CD mit MusicBrainz-Auswahl
- [ ] `lib-dvd.sh` anpassen
  - [ ] TMDB-Integration → Nutze `query_metadata_before_copy()`
  - [ ] Provider-Check integrieren: `has_metadata_provider "tmdb"`
  - [ ] Test: DVD mit TMDB-Auswahl
- [ ] `lib-bluray.sh` anpassen
  - [ ] TMDB-Integration → Nutze `query_metadata_before_copy()`
  - [ ] Provider-Check integrieren: `has_metadata_provider "tmdb"`
  - [ ] Test: Blu-ray mit TMDB-Auswahl

#### 2.2 Obsolete Dateien entfernen
- [ ] `lib-cd-metadata.sh` löschen (Funktionen jetzt in `lib-metadata.sh`)
- [ ] `lib-dvd-metadata.sh` löschen (Funktionen jetzt in Provider-System)
- [x] ~~Sprachdateien konsolidieren~~
  - [x] ~~`lib-cd-metadata.*` entfernen (in `lib-cd.*` integrieren)~~ (Tool-check Messages nach lib-config.* migriert)
  - [x] ~~`lib-dvd-metadata.*` prüfen (ggf. in `lib-metadata.*` integrieren)~~ (Tool-check Messages nach lib-config.* migriert)
- [ ] Git: Alte Dateien aus Repo entfernen

#### 2.3 Test: Metadata-System End-to-End
- [ ] Test: Audio-CD → MusicBrainz Query → User-Auswahl → Korrektes Label
- [ ] Test: DVD → TMDB Query → User-Auswahl → Korrektes Label + Cover
- [ ] Test: Metadata deaktiviert → Generisches Label verwendet
- [ ] Test: Provider fehlt (curl/jq) → Graceful Fallback

**Abschluss-Kriterium:** Metadata-System vollständig modular und Provider-basiert

---

### **PHASE 3: Modul-Manifeste einführen**
**Priorität:** MITTEL | **Aufwand:** ~6 Stunden | **Status:** Nicht begonnen

#### 3.1 Manifest-Dateien erstellen
- [x] ~~`conf/lib-cd.ini` erstellen~~ (INI-Format statt JSON - einfacher)
  - [x] ~~Komponenten definieren (bash, i18n, frontend, backend)~~ (In [modulefiles] Sektion)
  - [x] ~~Dependencies auflisten (core, external, optional)~~ (In [dependencies] Sektion)
  - [x] ~~Pfade definieren (output_subdir)~~ (In [folders] Sektion)
- [x] ~~`conf/lib-dvd.ini` erstellen~~ (Vollständig implementiert)
- [x] ~~`conf/lib-bluray.ini` erstellen~~ (Vollständig implementiert)
- [x] ~~`conf/lib-metadata.ini` erstellen~~ (Vollständig implementiert)
  - [x] ~~Provider-Liste aufnehmen (lib-musicbrainz.sh, lib-tmdb.sh)~~ (Via [modulefiles] Sektion)
  - [x] ~~Metadata für unterstützte Media-Types~~ (Implizit durch Disc-Type Checks)

#### 3.2 Python: Manifest-Parsing implementieren
- [ ] `www/app.py` - Funktion `get_module_manifests()` implementieren
  - [ ] JSON-Dateien aus `conf/` lesen
  - [ ] Fehlerbehandlung (ungültige JSONs, fehlende Fields)
- [ ] `www/app.py` - Funktion `get_enabled_modules()` implementieren
  - [ ] Config + Manifeste kombinieren
  - [ ] Nur aktivierte Module zurückgeben
- [ ] `www/app.py` - `/api/modules` Endpoint anpassen
  - [ ] Manifeste statt hardcoded Liste nutzen
  - [ ] JS-Dateien aus Manifest-`components.frontend` lesen

#### 3.3 Frontend: Module-Loader auf Manifeste umstellen
- [ ] `www/static/js/module-loader.js` prüfen
  - [ ] Bereits implementiert, sollte funktionieren
  - [ ] Test: Werden JS-Dateien korrekt aus API geladen?

#### 3.4 Test: Manifest-System
- [ ] Test: Modul aktivieren → Frontend lädt korrekte JS-Dateien
- [ ] Test: Modul deaktivieren → Frontend lädt JS NICHT
- [ ] Test: Ungültiges Manifest → Fehlerbehandlung korrekt
- [ ] Test: Fehlendes Manifest → Fallback auf Defaults

**Abschluss-Kriterium:** Manifeste sind Single Source of Truth für Modul-Metadaten

---

### **PHASE 4: Backend-Routing modularisieren**
**Priorität:** NIEDRIG | **Aufwand:** ~10 Stunden | **Status:** Nicht begonnen

#### 4.1 Blueprint-Struktur erstellen
- [ ] `www/routes/__init__.py` erstellen
- [ ] `www/routes/routes_metadata.py` erstellen
  - [ ] Alle `/api/musicbrainz/*` Routes aus `app.py` extrahieren
  - [ ] Alle `/api/tmdb/*` Routes aus `app.py` extrahieren
  - [ ] Blueprint `metadata_bp` definieren
- [ ] `www/routes/routes_cd.py` erstellen (falls CD-spezifische Routes existieren)
- [ ] `www/routes/routes_dvd.py` erstellen
  - [ ] Route `/api/dvd/failed` für `.failed_dvds` Datei

#### 4.2 Decorator-Pattern für Runtime-Checks
- [ ] `www/routes/routes_metadata.py` - Decorator `@require_module_enabled()` implementieren
  - [ ] Liest aktuelle Config (gecacht)
  - [ ] Return 403 wenn Modul deaktiviert
- [ ] Alle Routen mit Decorator versehen

#### 4.3 Blueprint-Registrierung in app.py
- [ ] `www/app.py` - Funktion `register_module_routes()` implementieren
  - [ ] Liest Manifeste
  - [ ] Importiert Blueprint-Module dynamisch
  - [ ] Registriert Blueprints (immer, auch wenn deaktiviert)
- [ ] Alte Route-Definitionen aus `app.py` entfernen
- [ ] Config-Option `ROUTING_MODE` in `disk2iso.conf` hinzufügen (default: `dynamic`)

#### 4.4 Test: Blueprint-System
- [ ] Test: Metadata-Routes erreichbar via `/api/metadata/*`
- [ ] Test: Modul deaktiviert → Routes geben 403 zurück
- [ ] Test: `/api/routes` Endpoint zeigt korrekte Übersicht
- [ ] Test: Service-Neustart NICHT nötig nach Config-Änderung

**Abschluss-Kriterium:** Jedes Modul hat eigene Route-Datei, dynamische Aktivierung

---

### **PHASE 5: Frontend-Config-Seite modularisieren**
**Priorität:** NIEDRIG | **Aufwand:** ~4 Stunden | **Status:** Nicht begonnen

#### 5.1 Hybrid UI-Struktur implementieren
- [ ] `www/templates/config.html` erweitern
  - [ ] CD-Sektion: Checkbox für `module_cd_enabled` hinzufügen
  - [ ] DVD-Sektion: Checkbox für `module_dvd_enabled` hinzufügen
  - [ ] Bluray-Sektion: Checkbox für `module_bluray_enabled` hinzufügen
  - [ ] Metadata-Sektion: Checkbox für `module_metadata_enabled` hinzufügen
  - [ ] Sektionen mit CSS-Klasse `module-section` + `data-module` Attribut versehen
- [ ] `www/static/css/style.css` erweitern
  - [ ] CSS-Regel für `.module-section.disabled .module-config { display: none; }`
- [ ] `www/static/js/config.js` erweitern
  - [ ] Event-Listener für `.module-toggle` Checkboxen
  - [ ] Toggle CSS-Klasse `disabled` bei Änderung
  - [ ] Registriere Änderung in `changedValues`

#### 5.2 Test: Config-UI Modul-Toggles
- [ ] Test: Checkbox aktivieren → Sektion wird sichtbar
- [ ] Test: Checkbox deaktivieren → Sektion wird ausgeblendet
- [ ] Test: Config speichern → Modul-Schalter korrekt in `disk2iso.conf`
- [ ] Test: Page-Reload → Checkbox-Status entspricht Config

**Abschluss-Kriterium:** Config-UI zeigt visuell welche Module aktiv sind

---

### **PHASE 6: Config-Handler-Registry implementieren**
**Priorität:** NIEDRIG | **Aufwand:** ~6 Stunden | **Status:** Nicht begonnen

#### 6.1 Globale Registry-Funktionen
- [ ] `lib/lib-config.sh` - Funktion `register_config_handler()` implementieren
  - [ ] Registry-Array `CONFIG_HANDLERS` erweitern (bereits vorhanden)
  - [ ] Funktion `set_config_value()` generisch machen (Lookup in Registry)
  - [ ] Funktion `get_config_value()` generisch machen

#### 6.2 Module registrieren Handler
- [ ] `lib/lib-metadata.sh` - Handler registrieren
  - [ ] `init_metadata_config()` Funktion erstellen
  - [ ] `register_config_handler "METADATA_ENABLED" ...`
  - [ ] Auto-Aufruf beim Source
- [ ] `lib/lib-cd.sh` - Handler registrieren (falls eigene Config-Keys)
- [ ] `lib/lib-dvd.sh` - Handler registrieren (falls eigene Config-Keys)

#### 6.3 TMDB-Provider Config-Handler
- [ ] Provider-Modul: Handler für TMDB_API_KEY registrieren
  - [ ] Validierung: 32 Hex-Zeichen
  - [ ] Service: `disk2iso-web` Restart bei Änderung

#### 6.4 Test: Registry-Pattern
- [ ] Test: Config-Änderung via Web-UI → Korrekter Handler aufgerufen
- [ ] Test: Validierung schlägt fehl → Fehler wird angezeigt
- [ ] Test: Service-Restart nur wenn nötig

**Abschluss-Kriterium:** Jedes Modul verwaltet eigene Config-Keys via Registry

---

### **PHASE 7: Dokumentation & Cleanup**
**Priorität:** MITTEL | **Aufwand:** ~3 Stunden | **Status:** Nicht begonnen

#### 7.1 Entwickler-Dokumentation aktualisieren
- [ ] `doc/Entwickler.md` - Plugin-System beschreiben
  - [ ] Wie erstelle ich ein neues Modul?
  - [ ] Manifest-Format dokumentieren
  - [ ] Config-Handler-Pattern erklären
- [ ] `README.md` - Features aktualisieren
  - [ ] Modulares Plugin-System erwähnen
  - [ ] Unterstützte Module auflisten

#### 7.2 Code-Kommentare
- [ ] Alle neuen Funktionen mit Header-Kommentaren versehen
- [ ] Komplexe Logik inline kommentieren
- [ ] TODOs im Code aufräumen

#### 7.3 Git-History aufräumen
- [ ] Obsolete Dateien aus Git entfernen (nicht nur lokal löschen)
- [ ] `.gitignore` prüfen (z.B. `*.pyc`, `__pycache__`, etc.)

**Abschluss-Kriterium:** Dokumentation ist aktuell und vollständig

---

### **OPTIONAL: Erweiterungen (Future)**
**Priorität:** SEHR NIEDRIG | **Status:** Ideen-Sammlung

#### Frontend: DOM-Injection für Config-UI
- [ ] Config-UI-Komponenten aus Manifesten laden (Phase 3 aus Roadmap)
- [ ] Modul-spezifische Validierung im Frontend (Registry-Pattern)

#### Backend: API-Versioning
- [ ] `/api/v1/*` Namespace einführen
- [ ] Alte API-Endpunkte deprecaten

#### Testing: Automatisierte Tests
- [ ] Unit-Tests für Bash-Funktionen (bats-core)
- [ ] Integration-Tests für Python-API (pytest)
- [ ] End-to-End-Tests für Web-UI (Playwright/Selenium)

#### CI/CD: Manifest-Validierung
- [ ] JSON-Schema für Manifeste erstellen
- [ ] GitHub Action für Manifest-Validierung
- [ ] Pre-commit Hook für Konsistenz-Checks

---

## 📊 Aufwands-Übersicht

| Phase | Priorität | Aufwand | Abhängigkeiten | Status |
|-------|-----------|---------|----------------|--------|
| **Phase 1: Fundament** | 🔴 HOCH | ~6h | Keine | ✅ **ERLEDIGT** |
| **Phase 2: Metadata** | 🔴 HOCH | ~8h | Phase 1 | ✅ **ERLEDIGT** |
| **Phase 3: Manifeste** | 🟡 MITTEL | ~6h | Phase 1, 2 | ✅ **ERLEDIGT** |
| **Phase 4: Routing** | 🟢 NIEDRIG | ~10h | Phase 3 | ⏸️ Nicht begonnen |
| **Phase 5: Config-UI** | 🟢 NIEDRIG | ~4h | Phase 1 | ⏸️ Nicht begonnen |
| **Phase 6: Registry** | 🟢 NIEDRIG | ~6h | Phase 1 | ⏸️ Nicht begonnen |
| **Phase 7: Doku** | 🟡 MITTEL | ~3h | Phase 1-6 | ⏸️ Nicht begonnen |
| **GESAMT** | - | **~43h** | - | **~65% erledigt** |

**Empfohlene Reihenfolge:** 1 → 2 → 5 → 3 → 6 → 7 → 4

**Begründung:**
- Phase 1+2 sind Fundament (müssen zuerst)
- Phase 5 (Config-UI) ist Quick Win nach Phase 1
- Phase 3 (Manifeste) benötigt stabile Basis
- Phase 4 (Routing) ist optional, kann später
- Phase 6 (Registry) baut auf Phase 1+3 auf
- Phase 7 (Doku) am Ende wenn alles stabil

**Meilensteine:**
- ✅ **M1:** Phase 1+2 abgeschlossen → System ist konsistent und wartbar ✅ **ERREICHT (23.01.2026)**
- ✅ **M2:** Phase 3+5 abgeschlossen → Frontend ist modular ⏳ **TEILWEISE** (Phase 3 erledigt, Phase 5 offen)
- ⏳ **M3:** Phase 4+6 abgeschlossen → Backend ist vollständig modular
- ⏳ **M4:** Phase 7 abgeschlossen → Production-Ready
